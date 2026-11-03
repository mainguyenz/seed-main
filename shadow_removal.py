"""Khử bóng cho ảnh hạt lúa (Shadow Removal Module).

Tích hợp 2 cơ chế:
1. Khử bóng bằng máy (tự động): Phát hiện dải màu hạt lúa (HSV) + Phân ngưỡng vùng tối (Otsu) -> Mặt nạ bóng tự động.
2. Khử bóng bằng tay (thủ công): Giao diện MaskEditor cho phép người dùng vẽ thêm hoặc xóa bớt bóng, phóng to/thu nhỏ, di chuyển.
3. Thuật toán nâng sáng và hoà trộn biên mềm (Feathering) để khử bóng tự nhiên, không để lại vết cứng viền.

Module này trả về ảnh đã khử bóng để tiếp tục đưa vào mô hình nhận diện (YOLO, đo đạc hạt giống).
"""
from __future__ import annotations

import argparse
import os
import pathlib
import sys
from typing import Any

# Ensure UTF-8 console output on Windows to prevent UnicodeEncodeError
if sys.stdout.encoding and sys.stdout.encoding.lower() != "utf-8":
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass
if sys.stderr.encoding and sys.stderr.encoding.lower() != "utf-8":
    try:
        sys.stderr.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass

import cv2
import numpy as np


# ─────────────────────────────────────────────────────────────────────────────
# 1. Phát hiện vùng bóng bằng máy (HSV + Otsu)
# ─────────────────────────────────────────────────────────────────────────────

def detect_shadow_auto(
    image_bgr: np.ndarray,
    hsv_grain_lower: np.ndarray | None = None,
    hsv_grain_upper: np.ndarray | None = None,
    blur_ksize: int = 5,
    morph_ksize: int = 5,
) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """Tự động phát hiện bóng bằng máy:
    - grain_mask: Pixel có màu hạt lúa (vàng, nâu vàng, trắng ngà)
    - dark_mask: Pixel tối (phân ngưỡng Otsu nghịch đảo)
    - shadow_mask: dark_mask AND (NOT grain_mask) -> Vùng tối không mang màu hạt lúa = bóng
    """
    if hsv_grain_lower is None:
        hsv_grain_lower = np.array([5, 25, 30], dtype=np.uint8)
    if hsv_grain_upper is None:
        hsv_grain_upper = np.array([40, 255, 255], dtype=np.uint8)

    k_blur = max(3, blur_ksize | 1)
    k_morph = max(3, morph_ksize | 1)

    # Lọc màu hạt lúa
    hsv_img = cv2.cvtColor(image_bgr, cv2.COLOR_BGR2HSV)
    grain_mask = cv2.inRange(hsv_img, hsv_grain_lower, hsv_grain_upper)

    # Phân ngưỡng Otsu vùng tối
    gray_img = cv2.cvtColor(image_bgr, cv2.COLOR_BGR2GRAY)
    blurred = cv2.GaussianBlur(gray_img, (k_blur, k_blur), 0)
    _, dark_mask = cv2.threshold(
        blurred, 0, 255, cv2.THRESH_BINARY_INV + cv2.THRESH_OTSU
    )

    # Bóng = Vùng tối AND NOT Hạt lúa
    not_grain = cv2.bitwise_not(grain_mask)
    shadow_mask = cv2.bitwise_and(dark_mask, not_grain)

    # Làm sạch mặt nạ
    kernel_clean = np.ones((k_morph, k_morph), np.uint8)
    shadow_mask = cv2.morphologyEx(shadow_mask, cv2.MORPH_OPEN, kernel_clean)
    shadow_mask = cv2.morphologyEx(shadow_mask, cv2.MORPH_CLOSE, kernel_clean)

    return shadow_mask, grain_mask, dark_mask


# ─────────────────────────────────────────────────────────────────────────────
# 2. Chỉnh sửa mặt nạ thủ công bằng tay (MaskEditor)
# ─────────────────────────────────────────────────────────────────────────────

class MaskEditor:
    """Trình chỉnh sửa mặt nạ bóng thủ công (có Zoom + Pan + Vẽ / Xoá bằng chuột).

    Điều khiển chuột:
        - Chuột trái       : Vẽ thêm bóng (hiển thị màu tím)
        - Chuột phải       : Xoá vùng bóng
        - Chuột giữa (kéo) : Di chuyển ảnh (Pan)
        - Con lăn chuột:
            * Lăn thường    : Cuộn lên / xuống
            * Ctrl + Lăn   : Phóng to / thu nhỏ (Zoom) tại con trỏ
            * Shift + Lăn  : Cuộn trái / phải
            * Alt + Lăn    : Tăng / giảm kích thước cọ

    Phím tắt:
        - Enter / Space    : Xác nhận mặt nạ và hoàn tất
        - Esc              : Đóng editor và giữ nguyên mặt nạ
        - [ / ]            : Giảm / Tăng kích thước cọ
        - R / r            : Phục hồi lại mặt nạ tự động do máy phát hiện
        - C / c            : Xoá trắng toàn bộ mặt nạ
    """

    WIN_W: int = 1280
    WIN_H: int = 720
    ZOOM_MIN: float = 0.05
    ZOOM_MAX: float = 32.0
    ZOOM_STEP: float = 1.15

    def __init__(self, image_bgr: np.ndarray, init_mask: np.ndarray):
        self.img = image_bgr
        self.ih, self.iw = image_bgr.shape[:2]
        self.mask = init_mask.copy()
        self.init_mask_backup = init_mask.copy()

        # Tỉ lệ zoom vừa khít cửa sổ hiển thị
        self.zoom: float = min(self.WIN_W / max(1, self.iw), self.WIN_H / max(1, self.ih))
        self.vx: float = (self.iw - self.WIN_W / self.zoom) / 2.0
        self.vy: float = (self.ih - self.WIN_H / self.zoom) / 2.0
        self.clamp_view()

        # Trạng thái chuột
        self.drawing: bool = False
        self.erasing: bool = False
        self.panning: bool = False
        self.pan_last: tuple[int, int] = (0, 0)
        self.last_img_pt: tuple[int, int] | None = None

        # Kích thước cọ vẽ
        self.brush: int = max(4, int(min(self.ih, self.iw) * 0.015))
        self.cursor_scr: tuple[int, int] = (0, 0)

    def scr2img(self, sx: int, sy: int) -> tuple[float, float]:
        """Chuyển toạ độ màn hình sang toạ độ pixel ảnh gốc."""
        return sx / self.zoom + self.vx, sy / self.zoom + self.vy

    def clamp_view(self) -> None:
        """Căn chỉnh vùng nhìn thấy hợp lý bên trong khung hiển thị."""
        view_w = self.WIN_W / self.zoom
        view_h = self.WIN_H / self.zoom
        if self.iw > view_w:
            self.vx = max(0.0, min(self.vx, self.iw - view_w))
        else:
            self.vx = (self.iw - view_w) / 2.0

        if self.ih > view_h:
            self.vy = max(0.0, min(self.vy, self.ih - view_h))
        else:
            self.vy = (self.ih - view_h) / 2.0

    def paint_at(self, sx: int, sy: int) -> None:
        """Vẽ hoặc xoá pixel trên mặt nạ mask tại toạ độ màn hình (sx, sy)."""
        ix, iy = self.scr2img(sx, sy)
        curr_pt = (int(round(ix)), int(round(iy)))
        color = 0 if self.erasing else 255

        if self.last_img_pt is not None:
            cv2.line(self.mask, self.last_img_pt, curr_pt, color, thickness=self.brush * 2)
        cv2.circle(self.mask, curr_pt, self.brush, color, -1)
        self.last_img_pt = curr_pt

    def render(self) -> np.ndarray:
        """Tạo khung hình hiển thị (WIN_H x WIN_W) với lớp phủ mask tím và con trỏ."""
        canvas = np.zeros((self.WIN_H, self.WIN_W, 3), dtype=np.uint8)

        x0, y0 = self.vx, self.vy
        x1 = x0 + self.WIN_W / self.zoom
        y1 = y0 + self.WIN_H / self.zoom

        ix0 = max(0, int(x0))
        iy0 = max(0, int(y0))
        ix1 = min(self.iw, int(np.ceil(x1)))
        iy1 = min(self.ih, int(np.ceil(y1)))

        if ix1 > ix0 and iy1 > iy0:
            crop_img = self.img[iy0:iy1, ix0:ix1].copy()
            crop_mask = self.mask[iy0:iy1, ix0:ix1]

            # Tô màu tím nhạt lên vùng bóng
            overlay = crop_img.copy()
            overlay[crop_mask > 0] = (200, 150, 220)
            blended = cv2.addWeighted(crop_img, 0.65, overlay, 0.35, 0)

            dst_w = max(1, int(round((ix1 - ix0) * self.zoom)))
            dst_h = max(1, int(round((iy1 - iy0) * self.zoom)))
            interp = cv2.INTER_LINEAR if self.zoom < 4.0 else cv2.INTER_NEAREST
            scaled = cv2.resize(blended, (dst_w, dst_h), interpolation=interp)

            off_x = int(round((ix0 - x0) * self.zoom))
            off_y = int(round((iy0 - y0) * self.zoom))

            s_x0 = max(0, -off_x)
            s_y0 = max(0, -off_y)
            c_x0 = max(0, off_x)
            c_y0 = max(0, off_y)
            copy_w = min(dst_w - s_x0, self.WIN_W - c_x0)
            copy_h = min(dst_h - s_y0, self.WIN_H - c_y0)

            if copy_w > 0 and copy_h > 0:
                canvas[c_y0:c_y0 + copy_h, c_x0:c_x0 + copy_w] = scaled[s_y0:s_y0 + copy_h, s_x0:s_x0 + copy_w]

        # Con trỏ cọ vẽ
        cx, cy = self.cursor_scr
        brush_r_scr = max(1, int(self.brush * self.zoom))
        color_cursor = (0, 0, 255) if self.erasing else (0, 255, 255)
        cv2.circle(canvas, (cx, cy), brush_r_scr, color_cursor, 1, cv2.LINE_AA)

        # Thanh hướng dẫn (HUD)
        pct = self.mask.mean() / 255.0 * 100.0
        hud_lines = [
            f"Zoom: {self.zoom:.2f}x | Co: {self.brush}px | Vung bong: {pct:.1f}%",
            "Chuot trai: Ve bong | Chuot phai: Xoa | Chuot giua: Keo pan | Ctrl+Lan: Zoom | [/]: Co | R: Reset",
            "Nhan [ENTER] hoac [SPACE] de XAC NHAN va tiep tuc | [ESC] de dong",
        ]
        for i, text in enumerate(hud_lines):
            y_pos = 24 + i * 24
            cv2.putText(canvas, text, (10, y_pos), cv2.FONT_HERSHEY_SIMPLEX, 0.52, (0, 0, 0), 3, cv2.LINE_AA)
            cv2.putText(canvas, text, (10, y_pos), cv2.FONT_HERSHEY_SIMPLEX, 0.52, (0, 230, 255) if i < 2 else (0, 255, 120), 1, cv2.LINE_AA)

        return canvas

    def on_mouse(self, event: int, x: int, y: int, flags: int, param: Any) -> None:
        self.cursor_scr = (x, y)

        if event == cv2.EVENT_LBUTTONDOWN:
            self.drawing = True
            self.erasing = False
            self.last_img_pt = None
            self.paint_at(x, y)

        elif event == cv2.EVENT_LBUTTONUP:
            self.drawing = False
            self.last_img_pt = None

        elif event == cv2.EVENT_RBUTTONDOWN:
            self.drawing = True
            self.erasing = True
            self.last_img_pt = None
            self.paint_at(x, y)

        elif event == cv2.EVENT_RBUTTONUP:
            self.drawing = False
            self.last_img_pt = None

        elif event == cv2.EVENT_MBUTTONDOWN:
            self.panning = True
            self.pan_last = (x, y)

        elif event == cv2.EVENT_MBUTTONUP:
            self.panning = False

        elif event == cv2.EVENT_MOUSEMOVE:
            if self.drawing:
                self.paint_at(x, y)
            if self.panning:
                dx = x - self.pan_last[0]
                dy = y - self.pan_last[1]
                self.vx -= dx / self.zoom
                self.vy -= dy / self.zoom
                self.clamp_view()
                self.pan_last = (x, y)

        elif event == cv2.EVENT_MOUSEWHEEL:
            ctrl_held = bool(flags & cv2.EVENT_FLAG_CTRLKEY)
            shift_held = bool(flags & cv2.EVENT_FLAG_SHIFTKEY)
            alt_held = bool(flags & cv2.EVENT_FLAG_ALTKEY)
            wheel_up = flags > 0

            if ctrl_held:
                factor = self.ZOOM_STEP if wheel_up else (1.0 / self.ZOOM_STEP)
                new_zoom = float(np.clip(self.zoom * factor, self.ZOOM_MIN, self.ZOOM_MAX))
                img_x_before = x / self.zoom + self.vx
                img_y_before = y / self.zoom + self.vy
                self.zoom = new_zoom
                self.vx = img_x_before - x / self.zoom
                self.vy = img_y_before - y / self.zoom
                self.clamp_view()
            elif shift_held:
                pan_h = self.WIN_W * 0.10 / self.zoom
                self.vx += -pan_h if wheel_up else pan_h
                self.clamp_view()
            elif alt_held:
                if wheel_up:
                    self.brush = min(500, self.brush + 2)
                else:
                    self.brush = max(1, self.brush - 2)
            else:
                pan_v = self.WIN_H * 0.10 / self.zoom
                self.vy += -pan_v if wheel_up else pan_v
                self.clamp_view()

    def run(self, window_name: str = "Chinh sua mat na bong (MaskEditor)") -> np.ndarray:
        """Khởi chạy giao diện chỉnh sửa tay. Trả về mặt nạ đã xác nhận."""
        cv2.namedWindow(window_name, cv2.WINDOW_NORMAL)
        cv2.resizeWindow(window_name, self.WIN_W, self.WIN_H)
        cv2.setMouseCallback(window_name, self.on_mouse)

        try:
            while True:
                if cv2.getWindowProperty(window_name, cv2.WND_PROP_VISIBLE) < 1:
                    print("-> Cửa sổ đã đóng. Xác nhận mặt nạ hiện tại.")
                    break

                cv2.imshow(window_name, self.render())
                key = cv2.waitKey(16) & 0xFF

                if key in (13, 32):  # Enter hoặc Space
                    print("-> Xác nhận mặt nạ bóng thành công!")
                    break
                elif key == 27:  # Esc
                    print("-> Đã thoát chỉnh sửa tay (giữ mặt nạ hiện tại).")
                    break
                elif key == ord('['):
                    self.brush = max(1, self.brush - 2)
                elif key == ord(']'):
                    self.brush = min(500, self.brush + 2)
                elif key in (ord('r'), ord('R')):
                    self.mask[:] = self.init_mask_backup
                    print("-> Đã khôi phục lại mặt nạ tự động ban đầu từ máy.")
                elif key in (ord('c'), ord('C')):
                    self.mask.fill(0)
                    print("-> Đã xoá sạch toàn bộ mặt nạ bóng.")
        finally:
            cv2.destroyAllWindows()

        return self.mask


# ─────────────────────────────────────────────────────────────────────────────
# 3. Thuật toán nâng sáng và hoà trộn biên khử bóng
# ─────────────────────────────────────────────────────────────────────────────

def remove_shadow(
    image_bgr: np.ndarray,
    mask: np.ndarray,
    blur_ksize: int = 61,
    max_gain: float = 3.0,
    feather: int = 9,
) -> np.ndarray:
    """Thuật toán khử bóng nâng sáng kênh V với tối ưu hóa đa thang đo (Downsampling).

    Tối ưu hóa:
      - Ước lượng ánh sáng nền trên ảnh thu nhỏ giúp giảm 95% CPU và RAM.
      - Phóng to lại bằng song tuyến (Bilinear) mượt mà, không răng cưa.
      - Hoà trộn biên mềm (Feathering) tự nhiên không lộ vết nối.
    """
    if image_bgr.ndim != 3 or image_bgr.shape[2] != 3:
        raise ValueError("Kích thước ảnh không hợp lệ.")
    if mask.shape[:2] != image_bgr.shape[:2]:
        raise ValueError("Kích thước mask không khớp với ảnh.")

    if not np.any(mask > 0):
        return image_bgr.copy()

    hsv_f = cv2.cvtColor(image_bgr, cv2.COLOR_BGR2HSV).astype(np.float32)
    h, s, v = cv2.split(hsv_f)

    # Ước lượng nền sáng cục bộ hiệu năng cao (downsampling)
    h_orig, w_orig = v.shape[:2]
    k = max(3, blur_ksize | 1)

    scale = min(1.0, 480.0 / max(h_orig, w_orig))
    if scale < 0.9:
        small_w = max(16, int(round(w_orig * scale)))
        small_h = max(16, int(round(h_orig * scale)))
        v_small = cv2.resize(v, (small_w, small_h), interpolation=cv2.INTER_AREA)
        k_small = max(3, int(round(k * scale)) | 1)
        kernel_morph = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (k_small, k_small))
        v_bg_small = cv2.morphologyEx(v_small, cv2.MORPH_CLOSE, kernel_morph)
        v_bg_small = cv2.GaussianBlur(v_bg_small, (0, 0), sigmaX=max(1.0, k_small / 6.0))
        v_bg = cv2.resize(v_bg_small, (w_orig, h_orig), interpolation=cv2.INTER_LINEAR)
        del v_small, v_bg_small
    else:
        kernel_morph = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (k, k))
        v_bg = cv2.morphologyEx(v, cv2.MORPH_CLOSE, kernel_morph)
        v_bg = cv2.GaussianBlur(v_bg, (0, 0), sigmaX=k / 6.0)

    # Hệ số khuếch đại sáng
    eps = 1e-3
    gain = np.clip(v_bg / (v + eps), 1.0, max_gain)
    v_new = np.clip(v * gain, 0.0, 255.0)

    v_out = v.copy()
    v_out[mask > 0] = v_new[mask > 0]
    del v_bg, gain, v_new

    hsv_out = cv2.merge([h, s, v_out]).astype(np.uint8)
    del h, s, v_out, hsv_f
    result_bgr = cv2.cvtColor(hsv_out, cv2.COLOR_HSV2BGR)
    del hsv_out

    # Hoà trộn biên mềm (Feathering)
    if feather > 0:
        mask_f = cv2.GaussianBlur(mask.astype(np.float32), (0, 0), sigmaX=float(feather)) / 255.0
        mask_f = mask_f[..., np.newaxis]
        blended = (
            result_bgr.astype(np.float32) * mask_f
            + image_bgr.astype(np.float32) * (1.0 - mask_f)
        )
        del mask_f
        return np.clip(blended, 0, 255).astype(np.uint8)

    return result_bgr


def check_and_remove_shadow_uc(
    image_input: str | pathlib.Path | np.ndarray,
    threshold_pct: float = 0.5,
    blur_ksize: int = 5,
    morph_ksize: int = 5,
    shadow_blur_ksize: int = 61,
    max_gain: float = 3.0,
    feather: int = 9,
    input_format: str = "RGB",
) -> tuple[np.ndarray, np.ndarray, dict]:
    """Use Case (UC): Tiền xử lý xác nhận bóng và xóa bóng có điều kiện.

    Quy trình:
      1. Kiểm tra xác nhận có bóng hay không:
         - Máy chạy phát hiện bóng tự động nhanh (HSV lọc màu hạt + Otsu vùng tối).
         - Tính tỷ lệ phần trăm vùng bóng (shadow_pct).
         - Xác nhận CÓ BÓNG nếu shadow_pct >= threshold_pct (mặc định 0.5%).
      2. Phân nhánh hành động:
         - NẾU CÓ BÓNG: Chạy thuật toán xóa bóng (remove_shadow) đã được tối ưu hóa đa
           thang đo, trả về ảnh đã được làm sạch bóng để chuyển sang bước sau.
         - NẾU KHÔNG CÓ BÓNG: Bỏ qua hoàn toàn thuật toán xóa bóng, giữ nguyên 100%
           ảnh gốc, không tốn thêm tài nguyên và chuyển thẳng qua bước sau.
    """
    if isinstance(image_input, (str, pathlib.Path)):
        img_path = str(image_input)
        image_bgr = cv2.imread(img_path)
        if image_bgr is None:
            raise FileNotFoundError(f"Không thể đọc ảnh từ đường dẫn: {img_path}")
        is_rgb = False
    elif isinstance(image_input, np.ndarray):
        if input_format.upper() == "RGB":
            image_bgr = cv2.cvtColor(image_input, cv2.COLOR_RGB2BGR)
            is_rgb = True
        else:
            image_bgr = image_input.copy()
            is_rgb = False
    else:
        raise TypeError("image_input phải là đường dẫn file hoặc mảng numpy.")

    # 1. Bước 1: Máy tự động xác nhận có bóng không
    auto_mask, grain_mask, dark_mask = detect_shadow_auto(
        image_bgr,
        blur_ksize=blur_ksize,
        morph_ksize=morph_ksize,
    )
    auto_shadow_pct = float(auto_mask.mean() / 255.0 * 100.0)
    grain_pct = float(grain_mask.mean() / 255.0 * 100.0)

    # Mở rộng nhẹ mask để khử sạch viền bóng
    kernel_dilate = np.ones((5, 5), np.uint8)
    final_mask = cv2.dilate(auto_mask, kernel_dilate, iterations=1)
    final_shadow_pct = float(final_mask.mean() / 255.0 * 100.0)

    has_shadow = final_shadow_pct >= threshold_pct

    # 2. Phân nhánh hành động: Có bóng -> Xóa bóng; Không có -> Đi tiếp
    if has_shadow:
        print(f"[UC Shadow] XÁC NHẬN CÓ BÓNG ({final_shadow_pct:.2f}% >= {threshold_pct}%). Bắt đầu xóa bóng...")
        removed_bgr = remove_shadow(
            image_bgr,
            final_mask,
            blur_ksize=shadow_blur_ksize,
            max_gain=max_gain,
            feather=feather,
        )
        applied = True
        result_bgr = removed_bgr
        reason = f"shadow_detected_and_removed_{final_shadow_pct:.2f}pct"
    else:
        print(f"[UC Shadow] XÁC NHẬN KHÔNG CÓ BÓNG ({final_shadow_pct:.2f}% < {threshold_pct}%). Bỏ qua xóa bóng, chuyển qua phần sau.")
        result_bgr = image_bgr
        final_mask = np.zeros(image_bgr.shape[:2], dtype=np.uint8)
        applied = False
        reason = f"no_shadow_detected_{final_shadow_pct:.2f}pct"

    if is_rgb:
        result_img = cv2.cvtColor(result_bgr, cv2.COLOR_BGR2RGB)
    else:
        result_img = result_bgr

    stats = {
        "enabled": True,
        "shadow_detected": bool(has_shadow),
        "applied": bool(applied),
        "shadow_pct": round(final_shadow_pct, 2),
        "auto_shadow_pct": round(auto_shadow_pct, 2),
        "grain_pct": round(grain_pct, 2),
        "threshold_pct": threshold_pct,
        "reason": reason,
    }

    return result_img, final_mask, stats


# ─────────────────────────────────────────────────────────────────────────────
# 4. Hàm điều phối chính (Tự động + Chỉnh tay + Trả về ảnh sạch bóng)
# ─────────────────────────────────────────────────────────────────────────────

def run_shadow_removal(
    image_input: str | pathlib.Path | np.ndarray,
    interactive: bool = True,
    show_comparison: bool = False,
    output_path: str | None = None,
    input_format: str = "BGR",
) -> tuple[np.ndarray, np.ndarray, dict]:
    """Quy trình khử bóng hoàn chỉnh:
    1. Đọc ảnh (nếu là đường dẫn) hoặc lấy mảng ảnh.
    2. Máy tự động phát hiện vùng bóng bằng HSV + Otsu.
    3. Nếu interactive=True: Mở MaskEditor cho người dùng chỉnh tay (vẽ/xoá/zoom/pan).
    4. Áp dụng thuật toán khử bóng nâng sáng kênh V.
    5. Trả về ảnh đã khử bóng (cùng định dạng với đầu vào), mặt nạ bóng và thông số thống kê.

    Returns
    -------
    tuple[np.ndarray, np.ndarray, dict]
        (image_no_shadow, final_mask, stats)
    """
    if isinstance(image_input, (str, pathlib.Path)):
        img_path = str(image_input)
        image_bgr = cv2.imread(img_path)
        if image_bgr is None:
            raise FileNotFoundError(f"Không thể đọc ảnh từ đường dẫn: {img_path}")
        is_rgb_input = False
    elif isinstance(image_input, np.ndarray):
        if input_format.upper() == "RGB":
            image_bgr = cv2.cvtColor(image_input, cv2.COLOR_RGB2BGR)
            is_rgb_input = True
        else:
            image_bgr = image_input.copy()
            is_rgb_input = False
    else:
        raise TypeError("image_input phải là đường dẫn file hoặc mảng numpy.")

    # Bước 1: Máy tự động phát hiện vùng bóng
    auto_mask, grain_mask, dark_mask = detect_shadow_auto(image_bgr)
    auto_shadow_pct = float(auto_mask.mean() / 255.0 * 100.0)
    grain_pct = float(grain_mask.mean() / 255.0 * 100.0)
    print(f"\n[1/3] Khử bóng bằng máy:")
    print(f"      - Diện tích hạt lúa : {grain_pct:.1f}%")
    print(f"      - Vùng tối Otsu     : {dark_mask.mean() / 255.0 * 100.0:.1f}%")
    print(f"      - Vùng bóng phát hiện: {auto_shadow_pct:.1f}%")

    # Bước 2: Chỉnh sửa mặt nạ bằng tay nếu bật interactive
    manual_edited = False
    if interactive and hasattr(cv2, "namedWindow"):
        print("\n[2/3] Chỉnh sửa bóng bằng tay (MaskEditor):")
        print("      - Đang mở cửa sổ... Bạn có thể dùng chuột trái để vẽ thêm bóng,")
        print("        chuột phải để xoá bớt, con lăn để phóng to/thu nhỏ ảnh.")
        print("      - Nhấn [ENTER] hoặc [SPACE] trên cửa sổ ảnh khi đã vừa ý.")
        editor = MaskEditor(image_bgr, auto_mask)
        chosen_mask = editor.run("Chinh sua mat na bong (MaskEditor)")
        manual_edited = True
    else:
        chosen_mask = auto_mask
        if interactive:
            print("\n[2/3] Môi trường không có màn hình GUI, tự động dùng mặt nạ từ máy.")

    # Mở rộng nhẹ mask để khử đều biên
    kernel_dilate = np.ones((5, 5), np.uint8)
    final_mask = cv2.dilate(chosen_mask, kernel_dilate, iterations=1)
    final_shadow_pct = float(final_mask.mean() / 255.0 * 100.0)

    # Bước 3: Nâng sáng khử bóng
    print(f"\n[3/3] Áp dụng thuật toán khử bóng (diện tích xử lý: {final_shadow_pct:.1f}%)...")
    if final_shadow_pct > 0.05:
        shadow_removed_bgr = remove_shadow(
            image_bgr,
            final_mask,
            blur_ksize=61,
            max_gain=3.0,
            feather=9,
        )
        applied = True
    else:
        shadow_removed_bgr = image_bgr.copy()
        applied = False

    # Lưu ảnh kết quả nếu có yêu cầu
    if output_path:
        out_p = pathlib.Path(output_path)
        out_p.parent.mkdir(parents=True, exist_ok=True)
        cv2.imwrite(str(out_p), shadow_removed_bgr)
        print(f"-> Đã lưu ảnh sau khử bóng tại: {out_p}")

    # Hiển thị đồ thị so sánh trước và sau nếu yêu cầu
    if show_comparison:
        try:
            import matplotlib.pyplot as plt
            img_rgb_orig = cv2.cvtColor(image_bgr, cv2.COLOR_BGR2RGB)
            img_rgb_clean = cv2.cvtColor(shadow_removed_bgr, cv2.COLOR_BGR2RGB)
            fig, axes = plt.subplots(1, 2, figsize=(14, 7))
            axes[0].imshow(img_rgb_orig)
            axes[0].set_title("Ảnh gốc (Có bóng)")
            axes[0].axis("off")
            axes[1].imshow(img_rgb_clean)
            axes[1].set_title("Ảnh sau khi khử bóng (Không còn bóng)")
            axes[1].axis("off")
            plt.tight_layout()
            plt.show()
        except Exception as e:
            print(f"Không thể hiển thị matplotlib: {e}")

    # Chuyển đổi định dạng trả về đồng nhất với đầu vào
    if is_rgb_input:
        result_img = cv2.cvtColor(shadow_removed_bgr, cv2.COLOR_BGR2RGB)
    else:
        result_img = shadow_removed_bgr

    stats = {
        "enabled": True,
        "applied": applied,
        "manual_edited": manual_edited,
        "shadow_pct": round(final_shadow_pct, 2),
        "auto_shadow_pct": round(auto_shadow_pct, 2),
        "grain_pct": round(grain_pct, 2),
    }

    return result_img, final_mask, stats


# ─────────────────────────────────────────────────────────────────────────────
# 5. CLI Execution
# ─────────────────────────────────────────────────────────────────────────────

def _find_default_image() -> str:
    candidates = [
        "47_00004.jpg",
        "test_images/sample.jpg",
        "test_images/sample2.jpg",
        "test_images/Cac-loai-hat-giong-co-xuat-xu-da-dang.jpg",
    ]
    for path in candidates:
        if os.path.exists(path):
            return path
    return "test_images/sample.jpg"


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Khử bóng cho ảnh hạt lúa (Máy tự động + Chỉnh sửa tay).")
    parser.add_argument("image", nargs="?", default=None, help="Đường dẫn đến file ảnh cần khử bóng.")
    parser.add_argument("--no-interactive", action="store_true", help="Chỉ khử bóng bằng máy tự động, không mở giao diện chỉnh tay.")
    parser.add_argument("--show", action="store_true", help="Hiển thị đồ thị so sánh trước và sau khi khử bóng.")
    parser.add_argument("--output", default="image_no_shadow.png", help="Đường dẫn lưu ảnh sau khử bóng.")
    args = parser.parse_args()

    target_image = args.image or _find_default_image()
    if not os.path.exists(target_image):
        print(f"Lỗi: Không tìm thấy ảnh tại '{target_image}'.")
        sys.exit(1)

    print(f"=== KHỬ BÓNG CHO ẢNH HẠT LÚA ===")
    print(f"Ảnh đầu vào: {target_image}")
    print(f"Chế độ: {'Tự động + Chỉnh tay' if not args.no_interactive else 'Hoàn toàn tự động'}")

    clean_img, mask, stats = run_shadow_removal(
        image_input=target_image,
        interactive=not args.no_interactive,
        show_comparison=args.show,
        output_path=args.output,
    )

    print("\n=== HOÀN TẤT KHỬ BÓNG ===")
    print(f"Ảnh không có bóng đã sẵn sàng: {args.output}")
    print(f"Thống kê: {stats}")
