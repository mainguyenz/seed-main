"""Shadow detection and removal module for grain images.

Combines automatic machine detection (HSV color filtering + Otsu dark thresholding)
with optional interactive manual editing (MaskEditor with zoom, pan, brush drawing/erasing)
and smooth luminance lifting (morphological closing background estimation + Gaussian feathering).
"""
from __future__ import annotations

import os
import sys
from pathlib import Path
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

from .config import bool_param, float_param, int_param


def is_gui_available() -> bool:
    """Check if OpenCV GUI windows (HighGUI) can be displayed in the current environment."""
    if not hasattr(cv2, "namedWindow"):
        return False
    # On Linux / headless systems, check DISPLAY or WAYLAND_DISPLAY
    if sys.platform.startswith("linux"):
        return bool(os.environ.get("DISPLAY") or os.environ.get("WAYLAND_DISPLAY"))
    # On Windows / macOS desktop, GUI is generally supported
    return True


# ─────────────────────────────────────────────────────────────────────────────
# 1. Automatic Machine Shadow Detection (HSV + Otsu + Morphology)
# ─────────────────────────────────────────────────────────────────────────────

def detect_shadow_auto(
    image_bgr: np.ndarray,
    hsv_grain_lower: np.ndarray | None = None,
    hsv_grain_upper: np.ndarray | None = None,
    blur_ksize: int = 5,
    morph_ksize: int = 5,
) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """Detect shadow regions automatically using HSV color filtering and Otsu thresholding.

    Idea:
      - Rice grains have yellow/golden-brown/cream hues -> filtered via HSV inRange.
      - Shadows are DARK regions that do NOT have rice grain hue:
          grain_mask  = pixels matching grain color (HSV inRange)
          dark_mask   = dark pixels below Otsu threshold
          shadow_mask = dark_mask AND (NOT grain_mask)

    Parameters
    ----------
    image_bgr : np.ndarray
        Input image in BGR format.
    hsv_grain_lower : np.ndarray, optional
        Lower bound [H, S, V] for grain color (default: [5, 0, 30]).
    hsv_grain_upper : np.ndarray, optional
        Upper bound [H, S, V] for grain color (default: [40, 255, 255]).
    blur_ksize : int
        Kernel size for Gaussian blur prior to Otsu thresholding.
    morph_ksize : int
        Kernel size for morphological opening and closing to clean noise.

    Returns
    -------
    tuple[np.ndarray, np.ndarray, np.ndarray]
        (shadow_mask, grain_mask, dark_mask) - each uint8 with values 0 or 255.
    """
    if hsv_grain_lower is None:
        hsv_grain_lower = np.array([5, 0, 30], dtype=np.uint8)
    if hsv_grain_upper is None:
        hsv_grain_upper = np.array([40, 255, 255], dtype=np.uint8)

    k_blur = max(3, blur_ksize | 1)
    k_morph = max(3, morph_ksize | 1)

    # 1. Grain mask via HSV
    hsv_img = cv2.cvtColor(image_bgr, cv2.COLOR_BGR2HSV)
    grain_mask = cv2.inRange(hsv_img, hsv_grain_lower, hsv_grain_upper)

    # 2. Dark mask via Otsu thresholding
    gray_img = cv2.cvtColor(image_bgr, cv2.COLOR_BGR2GRAY)
    blurred = cv2.GaussianBlur(gray_img, (k_blur, k_blur), 0)
    _, dark_mask = cv2.threshold(
        blurred, 0, 255, cv2.THRESH_BINARY_INV + cv2.THRESH_OTSU
    )

    # 3. Shadow mask = Dark regions that are NOT grain
    not_grain = cv2.bitwise_not(grain_mask)
    shadow_mask = cv2.bitwise_and(dark_mask, not_grain)

    # 4. Clean mask with morphological operations
    kernel_clean = np.ones((k_morph, k_morph), np.uint8)
    shadow_mask = cv2.morphologyEx(shadow_mask, cv2.MORPH_OPEN, kernel_clean)
    shadow_mask = cv2.morphologyEx(shadow_mask, cv2.MORPH_CLOSE, kernel_clean)

    return shadow_mask, grain_mask, dark_mask


# ─────────────────────────────────────────────────────────────────────────────
# 2. Interactive Manual Mask Editor (Zoom + Pan + Draw + Erase)
# ─────────────────────────────────────────────────────────────────────────────

class MaskEditor:
    """Interactive mask editor with zoom and pan for fine-tuning shadow masks.

    Mouse Controls:
        - Left click: Draw shadow (paint purple overlay)
        - Right click: Erase shadow (remove overlay)
        - Middle click (drag): Pan view
        - Scroll wheel:
            * Normal: Pan up / down
            * Ctrl + Wheel: Zoom at cursor position
            * Shift + Wheel: Pan left / right
            * Alt + Wheel: Adjust brush size
    Keyboard Controls:
        - Enter / Space: Confirm mask and proceed
        - Esc: Cancel manual edit and keep current mask
        - [ / ]: Decrease / Increase brush size
        - R / r: Reset to machine auto-detected mask
        - C / c: Clear all mask (fill with 0)
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

        # Initial fit-to-window zoom
        self.zoom: float = min(self.WIN_W / max(1, self.iw), self.WIN_H / max(1, self.ih))
        self.vx: float = (self.iw - self.WIN_W / self.zoom) / 2.0
        self.vy: float = (self.ih - self.WIN_H / self.zoom) / 2.0
        self.clamp_view()

        # Mouse interaction state
        self.drawing: bool = False
        self.erasing: bool = False
        self.panning: bool = False
        self.pan_last: tuple[int, int] = (0, 0)
        self.last_img_pt: tuple[int, int] | None = None

        # Brush size (pixels in full-resolution image space)
        self.brush: int = max(4, int(min(self.ih, self.iw) * 0.015))
        self.cursor_scr: tuple[int, int] = (0, 0)

    def scr2img(self, sx: int, sy: int) -> tuple[float, float]:
        """Convert screen pixel coordinates to full-resolution image coordinates."""
        return sx / self.zoom + self.vx, sy / self.zoom + self.vy

    def clamp_view(self) -> None:
        """Keep the viewing region nicely bounded and centered."""
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
        """Paint or erase on the mask at screen point (sx, sy)."""
        ix, iy = self.scr2img(sx, sy)
        curr_pt = (int(round(ix)), int(round(iy)))
        color = 0 if self.erasing else 255

        # Draw smooth line from previous point to current point
        if self.last_img_pt is not None:
            cv2.line(self.mask, self.last_img_pt, curr_pt, color, thickness=self.brush * 2)
        cv2.circle(self.mask, curr_pt, self.brush, color, -1)
        self.last_img_pt = curr_pt

    def render(self) -> np.ndarray:
        """Render the current view onto a WIN_W x WIN_H BGR canvas."""
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

            # Purple overlay for shadow region
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

        # Draw brush cursor
        cx, cy = self.cursor_scr
        brush_r_scr = max(1, int(self.brush * self.zoom))
        color_cursor = (0, 0, 255) if self.erasing else (0, 255, 255)
        cv2.circle(canvas, (cx, cy), brush_r_scr, color_cursor, 1, cv2.LINE_AA)

        # Draw HUD
        hud_lines = [
            f"Zoom: {self.zoom:.2f}x | Co: {self.brush}px | Vung bong: {self.mask.mean() / 255.0 * 100.0:.1f}%",
            "Chuot trai: Ve bong | Chuot phai: Xoa | Chuot giua: Keo | Ctrl+Lan: Zoom | [/]: Co | R: Reset",
            "Nhan [ENTER] hoac [SPACE] de XAC NHAN va tiep tuc xu ly | [ESC] de dong",
        ]
        for i, text in enumerate(hud_lines):
            y_pos = 24 + i * 24
            cv2.putText(canvas, text, (10, y_pos), cv2.FONT_HERSHEY_SIMPLEX, 0.52, (0, 0, 0), 3, cv2.LINE_AA)
            cv2.putText(canvas, text, (10, y_pos), cv2.FONT_HERSHEY_SIMPLEX, 0.52, (0, 230, 255) if i < 2 else (0, 255, 120), 1, cv2.LINE_AA)

        return canvas

    def on_mouse(self, event: int, x: int, y: int, flags: int, param: Any) -> None:
        """Mouse callback handling painting, erasing, panning, and zooming."""
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
        """Run the interactive editor loop. Returns the confirmed mask."""
        cv2.namedWindow(window_name, cv2.WINDOW_NORMAL)
        cv2.resizeWindow(window_name, self.WIN_W, self.WIN_H)
        cv2.setMouseCallback(window_name, self.on_mouse)

        try:
            while True:
                # Check if window was closed by the user
                if cv2.getWindowProperty(window_name, cv2.WND_PROP_VISIBLE) < 1:
                    print("-> Cua so da duoc dong. Xac nhan mat na hien tai.")
                    break

                cv2.imshow(window_name, self.render())
                key = cv2.waitKey(16) & 0xFF

                if key in (13, 32):  # Enter or Space
                    print("-> Da xac nhan mat na chinh sua bang tay.")
                    break
                elif key == 27:  # Esc
                    print("-> Da thoat che do chinh tay (giu nguyen mat na hien tai).")
                    break
                elif key == ord('['):
                    self.brush = max(1, self.brush - 2)
                elif key == ord(']'):
                    self.brush = min(500, self.brush + 2)
                elif key in (ord('r'), ord('R')):
                    self.mask[:] = self.init_mask_backup
                    print("-> Da khoi phuc lai mat na tu dong ban dau.")
                elif key in (ord('c'), ord('C')):
                    self.mask.fill(0)
                    print("-> Da xoa sach toan bo mat na bong.")
        finally:
            cv2.destroyAllWindows()

        return self.mask


# ─────────────────────────────────────────────────────────────────────────────
# 3. Core Shadow Removal (Luminance Lifting in HSV)
# ─────────────────────────────────────────────────────────────────────────────

def remove_shadow(
    image_bgr: np.ndarray,
    mask: np.ndarray,
    blur_ksize: int = 61,
    max_gain: float = 3.0,
    feather: int = 9,
) -> np.ndarray:
    """Remove shadows from the masked regions of a BGR image.

    Algorithm:
      1. Converts to HSV color space and isolates V (value/luminance).
      2. Estimates local background brightness using morphological closing
         with an elliptical kernel, followed by gentle Gaussian smoothing.
      3. Calculates adaptive luminance gain: gain = clip(V_bg / (V + eps), 1.0, max_gain).
      4. Replaces V values inside the shadow mask with boosted values.
      5. Softly blends the result with the original image using Gaussian feathering
         along the mask boundaries to eliminate harsh seams.

    Parameters
    ----------
    image_bgr : np.ndarray
        3-channel BGR image.
    mask : np.ndarray
        Binary mask (255 = shadow, 0 = non-shadow).
    blur_ksize : int
        Kernel size for background closing estimation (odd integer >= 3).
    max_gain : float
        Maximum luminance gain ceiling to prevent overexposure/clipping.
    feather : int
        Gaussian feathering sigma (pixels) along the mask edge.

    Returns
    -------
    np.ndarray
        Shadow-removed BGR image.
    """
    if image_bgr.ndim != 3 or image_bgr.shape[2] != 3:
        raise ValueError("image_bgr must be a 3-channel image.")
    if mask.shape[:2] != image_bgr.shape[:2]:
        raise ValueError("Mask dimensions must match the image.")

    if not np.any(mask > 0):
        return image_bgr.copy()

    hsv_f = cv2.cvtColor(image_bgr, cv2.COLOR_BGR2HSV).astype(np.float32)
    h, s, v = cv2.split(hsv_f)

    # Efficient background luminance estimation via downsampling
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

    # Gain multiplier
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

    # Gaussian feathering to prevent sharp border artifacts
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


# ─────────────────────────────────────────────────────────────────────────────
# 4. Pipeline Integration (Machine + Manual + Luminance Lifting)
# ─────────────────────────────────────────────────────────────────────────────

def detect_and_remove_shadow(
    rgb: np.ndarray,
    params: dict | None = None,
    interactive: bool | None = None,
) -> tuple[np.ndarray, np.ndarray, dict]:
    """Detect and remove shadows from an RGB grain image.

    Combines automatic machine detection and optional manual MaskEditor editing,
    then returns the shadow-removed RGB image to feed downstream processing.

    Parameters
    ----------
    rgb : np.ndarray
        RGB image of shape (H, W, 3) and uint8 type.
    params : dict, optional
        Pipeline parameter dictionary.
    interactive : bool, optional
        Whether to launch the interactive manual MaskEditor window.
        If None, reads from params['interactiveShadowRemoval'] (defaults to False).

    Returns
    -------
    tuple[np.ndarray, np.ndarray, dict]
        (shadow_removed_rgb, shadow_mask, stats_dict)
    """
    if params is None:
        params = {}

    blur_ksize = int_param(params, "shadowBlurKsize", 5, 3, 31)
    morph_ksize = int_param(params, "shadowMorphKsize", 5, 3, 31)
    shadow_blur_ksize = int_param(params, "shadowRemovalBlurKsize", 61, 3, 201)
    max_gain = float_param(params, "shadowMaxGain", 3.0, 1.0, 10.0)
    feather = int_param(params, "shadowFeather", 9, 0, 50)

    if interactive is None:
        interactive = bool_param(params, "interactiveShadowRemoval")

    # 1. Convert RGB -> BGR for OpenCV
    bgr = cv2.cvtColor(rgb, cv2.COLOR_RGB2BGR)

    # 2. Bước 1: Khử bóng bằng máy (HSV + Otsu tự động)
    auto_mask, grain_mask, dark_mask = detect_shadow_auto(
        bgr,
        blur_ksize=blur_ksize,
        morph_ksize=morph_ksize,
    )
    auto_shadow_pct = float(auto_mask.mean() / 255.0 * 100.0)
    grain_pct = float(grain_mask.mean() / 255.0 * 100.0)
    print(f"[Shadow Removal] May tu dong phat hien: Hat lua={grain_pct:.1f}% | Vung toi={dark_mask.mean() / 255.0 * 100.0:.1f}% | Bong={auto_shadow_pct:.1f}%")

    # 3. Bước 2: Chỉnh sửa thủ công bằng tay (MaskEditor) nếu được kích hoạt
    manual_edited = False
    if interactive:
        if is_gui_available():
            print("\n[MaskEditor] Dang mo trinh chinh sua mat na bong bang tay...")
            print("  - Chuot trai: Ve them bong (mau tim)")
            print("  - Chuot phai: Xoa vung bong bi nhan nham")
            print("  - Con lan chuot / Ctrl+Lan: Pan / Zoom anh")
            print("  - Phim [ va ]: Thay doi kich thuoc co")
            print("  - Phim R: Reset ve mat na tu dong ban dau")
            print("  - Nhan ENTER hoac SPACE tren cua so anh khi hoan tat de tiep tuc xu ly.")
            editor = MaskEditor(bgr, auto_mask)
            chosen_mask = editor.run("Chinh sua mat na bong (MaskEditor)")
            manual_edited = True
        else:
            print("[Shadow Removal] Khong tim thay giao dien GUI (headless), tu dong su dung ket qua may.")
            chosen_mask = auto_mask
    else:
        chosen_mask = auto_mask

    # Dilate mask slightly to cleanly enclose shadow edges
    kernel_dilate = np.ones((5, 5), np.uint8)
    final_mask = cv2.dilate(chosen_mask, kernel_dilate, iterations=1)
    final_shadow_pct = float(final_mask.mean() / 255.0 * 100.0)

    # 4. Bước 3: Khử bóng và trả về ảnh không có bóng
    if final_shadow_pct > 0.05:
        removed_bgr = remove_shadow(
            bgr,
            final_mask,
            blur_ksize=shadow_blur_ksize,
            max_gain=max_gain,
            feather=feather,
        )
        removed_rgb = cv2.cvtColor(removed_bgr, cv2.COLOR_BGR2RGB)
        applied = True
        print(f"[Shadow Removal] Da khu bong thanh cong ({final_shadow_pct:.1f}% dien tich). Tra ve anh sach bong.")
    else:
        removed_rgb = rgb.copy()
        applied = False
        print("[Shadow Removal] Vung bong < 0.05%, giu nguyen anh goc.")

    stats = {
        "enabled": True,
        "applied": applied,
        "manual_edited": manual_edited,
        "shadow_pct": round(final_shadow_pct, 2),
        "auto_shadow_pct": round(auto_shadow_pct, 2),
        "grain_pct": round(grain_pct, 2),
    }

    return removed_rgb, final_mask, stats
