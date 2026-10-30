import cv2
import sys
import numpy as np
import matplotlib.pyplot as plt

# ─────────────────────────────────────────────
# 1. Đọc ảnh
# ─────────────────────────────────────────────
IMAGE_PATH = "47_00004.jpg"

image_bgr = cv2.imread(IMAGE_PATH)

if image_bgr is None:
    raise FileNotFoundError(f"Không thể đọc ảnh: {IMAGE_PATH}")

print("Kích thước ảnh:", image_bgr.shape)

# ─────────────────────────────────────────────
# 2. Phát hiện vùng bóng bằng HSV + Otsu
#
# Ý tưởng:
#   Hạt lúa có màu vàng/nâu vàng → lọc bằng dải màu HSV
#   Bóng là vùng TỐI không mang màu hạt lúa:
#
#   grain_mask  = pixel có màu hạt lúa (HSV inRange)
#   dark_mask   = pixel tối (Otsu THRESH_BINARY_INV)
#   shadow_mask = dark_mask AND NOT grain_mask
#               → vùng tối mà KHÔNG phải màu hạt = bóng
# ─────────────────────────────────────────────

# ── Thông số — chỉnh tại đây nếu kết quả chưa vừa ý ──────────────────────
# Dải màu HSV của hạt lúa (vàng nhạt → nâu vàng → trắng sữa)
HSV_GRAIN_LOWER = np.array([5,   0,  30])   # [H_min, S_min, V_min]
HSV_GRAIN_UPPER = np.array([40, 255, 255])  # [H_max, S_max, V_max]
#   H: 5–40  → bao phủ vàng chanh đến vàng nâu
#   S: 0–255 → cả hạt nhạt lẫn đậm
#   V: 30+   → loại pixel quá tối

# Kernel Gaussian làm mờ trước Otsu (lẻ >= 3)
BLUR_KSIZE = 5   # Lớn hơn → mờ hơn → Otsu ổn định hơn nhưng mất chi tiết

# Kernel morphology làm sạch mask
MORPH_KSIZE = 5  # Lớn hơn → lấp lỗ hổng rộng hơn, loại nhiễu thô hơn
# ──────────────────────────────────────────────────────────────────────────

# ── Bước 1: Lọc màu hạt lúa (HSV) ────────────────────────────────────────
# Chuyển BGR → HSV (OpenCV dùng H: 0–179, S/V: 0–255)
hsv_img = cv2.cvtColor(image_bgr, cv2.COLOR_BGR2HSV)
grain_mask = cv2.inRange(hsv_img, HSV_GRAIN_LOWER, HSV_GRAIN_UPPER)
# grain_mask: 255 = pixel CÓ màu hạt lúa, 0 = pixel KHÔNG có màu hạt lúa

# ── Bước 2: Phân ngưỡng Otsu — phát hiện vùng tối ───────────────────────
gray_img = cv2.cvtColor(image_bgr, cv2.COLOR_BGR2GRAY)
blurred  = cv2.GaussianBlur(gray_img, (BLUR_KSIZE, BLUR_KSIZE), 0)
_, dark_mask = cv2.threshold(
    blurred, 0, 255,
    cv2.THRESH_BINARY_INV + cv2.THRESH_OTSU
)
# dark_mask: 255 = pixel TỐI (dưới ngưỡng Otsu), 0 = pixel sáng

# ── Bước 3: Bóng = vùng tối mà KHÔNG phải màu hạt lúa ───────────────────
not_grain   = cv2.bitwise_not(grain_mask)          # 255 nơi không có hạt
shadow_mask = cv2.bitwise_and(dark_mask, not_grain) # tối AND không-hạt = bóng

# ── Bước 4: Làm sạch mask bằng morphology ────────────────────────────────
kernel_clean = np.ones((MORPH_KSIZE, MORPH_KSIZE), np.uint8)
shadow_mask = cv2.morphologyEx(shadow_mask, cv2.MORPH_OPEN,  kernel_clean)  # loại nhiễu nhỏ
shadow_mask = cv2.morphologyEx(shadow_mask, cv2.MORPH_CLOSE, kernel_clean)  # lấp lỗ hổng

shadow_pct = shadow_mask.mean() / 255 * 100
print(f"Vung hat lua: {grain_mask.mean()/255*100:.1f}%  |  "
      f"Vung toi:    {dark_mask.mean()/255*100:.1f}%  |  "
      f"Vung bong:   {shadow_pct:.1f}%")

# ─────────────────────────────────────────────
# 3. Chỉnh sửa mặt nạ thủ công (có Zoom + Pan)
#
#   Chuột trái  = Vẽ thêm vùng bóng
#   Chuột phải  = Xoá vùng bóng
#   Con lăn     = Phóng to / Thu nhỏ (tâm tại con trỏ)
#   Chuột giữa  = Kéo pan (giữ + di chuyển)
#   [ / ]       = Giảm / Tăng kích thước cọ
#   Enter        = Xác nhận
#   Esc          = Huỷ
# ─────────────────────────────────────────────

class MaskEditor:
    """
    Trình chỉnh sửa mask với zoom/pan bằng con lăn chuột.

    Hệ toạ độ:
        - Toạ độ ảnh  (img_x, img_y) : pixel trên ảnh gốc độ phân giải đầy đủ
        - Toạ độ màn (scr_x, scr_y) : pixel trên cửa sổ hiển thị

    Biến đổi:
        scr = (img - view_origin) * zoom
        img = scr / zoom + view_origin
    """

    WIN_W = 1280   # chiều rộng cửa sổ hiển thị (pixel)
    WIN_H = 720    # chiều cao  cửa sổ hiển thị (pixel)
    ZOOM_MIN = 0.05
    ZOOM_MAX = 32.0
    ZOOM_STEP = 1.15   # mỗi bước con lăn nhân/chia bằng hệ số này

    def __init__(self, image_bgr: np.ndarray, init_mask: np.ndarray):
        self.img = image_bgr
        self.mask = init_mask.copy()
        self.ih, self.iw = image_bgr.shape[:2]

        # Khởi tạo zoom vừa khít cửa sổ
        self.zoom: float = min(self.WIN_W / self.iw, self.WIN_H / self.ih)
        # view_origin: góc trên-trái của vùng nhìn thấy tính theo toạ độ ảnh
        self.vx: float = (self.iw - self.WIN_W / self.zoom) / 2
        self.vy: float = (self.ih - self.WIN_H / self.zoom) / 2

        # Trạng thái chuột
        self.drawing = False
        self.erasing = False
        self.panning = False
        self.pan_last = (0, 0)   # toạ độ màn lần trước khi pan

        # Kích thước cọ (tính theo pixel ảnh gốc)
        self.brush = 10

        # Lưu toạ độ chuột hiện tại để vẽ con trỏ cọ
        self.cursor_scr = (0, 0)

    # ── Đổi toạ độ ──────────────────────────────────────────────────────────

    def scr2img(self, sx: int, sy: int):
        """Toạ độ màn → toạ độ ảnh (float)."""
        return sx / self.zoom + self.vx, sy / self.zoom + self.vy

    # ── Giới hạn view để không ra ngoài ảnh ─────────────────────────────────

    def clamp_view(self):
        view_w = self.WIN_W / self.zoom
        view_h = self.WIN_H / self.zoom
        self.vx = max(0.0, min(self.vx, self.iw - view_w))
        self.vy = max(0.0, min(self.vy, self.ih - view_h))

    # ── Render khung hình hiện tại ───────────────────────────────────────────

    def render(self) -> np.ndarray:
        """Tạo khung BGR (WIN_H × WIN_W) từ view hiện tại."""
        # Vùng ảnh cần lấy (toạ độ ảnh, float)
        x0 = self.vx
        y0 = self.vy
        x1 = x0 + self.WIN_W / self.zoom
        y1 = y0 + self.WIN_H / self.zoom

        # Clip vào biên ảnh
        ix0 = max(0, int(x0))
        iy0 = max(0, int(y0))
        ix1 = min(self.iw, int(np.ceil(x1)))
        iy1 = min(self.ih, int(np.ceil(y1)))

        # Crop ảnh + mask, tô màu vùng bóng
        crop_img  = self.img [iy0:iy1, ix0:ix1].copy()
        crop_mask = self.mask[iy0:iy1, ix0:ix1]
        ov = crop_img.copy()
        ov[crop_mask > 0] = (200, 150, 220)   # tím
        blended = cv2.addWeighted(crop_img, 0.65, ov, 0.35, 0)

        # Scale lên kích thước màn hình
        dst_w = int(round((ix1 - ix0) * self.zoom))
        dst_h = int(round((iy1 - iy0) * self.zoom))
        dst_w = max(1, dst_w)
        dst_h = max(1, dst_h)
        interp = cv2.INTER_LINEAR if self.zoom < 4 else cv2.INTER_NEAREST
        scaled = cv2.resize(blended, (dst_w, dst_h), interpolation=interp)

        # Đặt lên canvas đen
        canvas = np.zeros((self.WIN_H, self.WIN_W, 3), dtype=np.uint8)
        # offset của crop trên màn hình
        off_x = int(round((ix0 - x0) * self.zoom))
        off_y = int(round((iy0 - y0) * self.zoom))

        # Tính vùng giao giữa scaled và canvas
        s_x0 = max(0, -off_x);  c_x0 = max(0, off_x)
        s_y0 = max(0, -off_y);  c_y0 = max(0, off_y)
        copy_w = min(dst_w - s_x0, self.WIN_W - c_x0)
        copy_h = min(dst_h - s_y0, self.WIN_H - c_y0)
        if copy_w > 0 and copy_h > 0:
            canvas[c_y0:c_y0+copy_h, c_x0:c_x0+copy_w] = \
                scaled[s_y0:s_y0+copy_h, s_x0:s_x0+copy_w]

        # ── Vẽ con trỏ cọ (vòng tròn trắng/đỏ) ─────────────────────────────
        cx, cy = self.cursor_scr
        brush_r_scr = max(1, int(self.brush * self.zoom))
        color_cursor = (0, 0, 220) if self.erasing else (255, 255, 255)
        cv2.circle(canvas, (cx, cy), brush_r_scr, color_cursor, 1, cv2.LINE_AA)

        # ── HUD chữ ──────────────────────────────────────────────────────────
        hud_lines = [
            f"Zoom: {self.zoom:.2f}x  |  Co: {self.brush}px",
            "Trai=Ve  Phai=Xoa  Giua=Keo  Lan=Len/Xuong  Ctrl+Lan=Zoom  Shift+Lan=Trai/Phai  Alt+Lan=Co  [/]=Co",
        ]
        for i, txt in enumerate(hud_lines):
            y_pos = 22 + i * 22
            cv2.putText(canvas, txt, (8, y_pos),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.55, (0, 0, 0), 3, cv2.LINE_AA)
            cv2.putText(canvas, txt, (8, y_pos),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.55, (0, 220, 255), 1, cv2.LINE_AA)

        return canvas

    # ── Vẽ / xoá trên mask ───────────────────────────────────────────────────

    def paint(self, sx: int, sy: int):
        ix, iy = self.scr2img(sx, sy)
        ix, iy = int(round(ix)), int(round(iy))
        color = 0 if self.erasing else 255
        cv2.circle(self.mask, (ix, iy), self.brush, color, -1)

    # ── Callback chuột ───────────────────────────────────────────────────────

    def on_mouse(self, event, x, y, flags, param):
        self.cursor_scr = (x, y)

        # ---- Nút trái: vẽ ----
        if event == cv2.EVENT_LBUTTONDOWN:
            self.drawing = True
            self.erasing = False
            self.paint(x, y)

        elif event == cv2.EVENT_LBUTTONUP:
            self.drawing = False

        # ---- Nút phải: xoá ----
        elif event == cv2.EVENT_RBUTTONDOWN:
            self.drawing = True
            self.erasing = True
            self.paint(x, y)

        elif event == cv2.EVENT_RBUTTONUP:
            self.drawing = False

        # ---- Nút giữa: kéo pan ----
        elif event == cv2.EVENT_MBUTTONDOWN:
            self.panning = True
            self.pan_last = (x, y)

        elif event == cv2.EVENT_MBUTTONUP:
            self.panning = False

        # ---- Di chuyển chuột ----
        elif event == cv2.EVENT_MOUSEMOVE:
            if self.drawing:
                self.paint(x, y)
            if self.panning:
                dx = x - self.pan_last[0]
                dy = y - self.pan_last[1]
                self.vx -= dx / self.zoom
                self.vy -= dy / self.zoom
                self.clamp_view()
                self.pan_last = (x, y)

        # ---- Con lăn: modifier quyết định hành động ----
        elif event == cv2.EVENT_MOUSEWHEEL:
            ctrl_held  = bool(flags & cv2.EVENT_FLAG_CTRLKEY)
            shift_held = bool(flags & cv2.EVENT_FLAG_SHIFTKEY)
            alt_held   = bool(flags & cv2.EVENT_FLAG_ALTKEY)
            wheel_up   = flags > 0   # delta >> modifier bits, dấu vẫn đúng

            pan_step = self.WIN_H * 0.10 / self.zoom   # 10% chiều cao/rộng cửa sổ

            if ctrl_held:
                # Ctrl + lăn → Zoom tại vị trí con trỏ
                factor = self.ZOOM_STEP if wheel_up else 1.0 / self.ZOOM_STEP
                new_zoom = np.clip(self.zoom * factor, self.ZOOM_MIN, self.ZOOM_MAX)
                img_x_before = x / self.zoom + self.vx
                img_y_before = y / self.zoom + self.vy
                self.zoom = new_zoom
                self.vx = img_x_before - x / self.zoom
                self.vy = img_y_before - y / self.zoom
                self.clamp_view()

            elif shift_held:
                # Shift + lăn → Pan trái / phải
                pan_h = self.WIN_W * 0.10 / self.zoom
                self.vx += -pan_h if wheel_up else pan_h
                self.clamp_view()

            elif alt_held:
                # Alt + lăn → Thay đổi kích thước cọ
                if wheel_up:
                    self.brush = min(500, self.brush + 2)
                else:
                    self.brush = max(1, self.brush - 2)

            else:
                # Lăn thường → Pan lên / xuống
                self.vy += -pan_step if wheel_up else pan_step
                self.clamp_view()

    # ── Vòng lặp chính ───────────────────────────────────────────────────────

    def run(self, window_name: str = "Edit Shadow Mask") -> np.ndarray:
        """Chạy editor. Trả về mask đã chỉnh sửa."""
        cv2.namedWindow(window_name, cv2.WINDOW_NORMAL)
        cv2.resizeWindow(window_name, self.WIN_W, self.WIN_H)
        cv2.setMouseCallback(window_name, self.on_mouse)

        while True:
            cv2.imshow(window_name, self.render())
            key = cv2.waitKey(16) & 0xFF   # ~60 fps

            if key == 13:                  # Enter → xác nhận
                break
            elif key == 27:                # Esc → huỷ, thoát bình thường
                cv2.destroyAllWindows()
                print("Da huy thao tac.")
                sys.exit(0)
            elif key == ord('['):          # Giảm cọ
                self.brush = max(1, self.brush - 2)
            elif key == ord(']'):          # Tăng cọ
                self.brush = min(500, self.brush + 2)
            elif key == ord('r'):          # Reset về ảnh tự động
                self.mask[:] = shadow_mask

        cv2.destroyAllWindows()
        return self.mask


# Khởi chạy editor
editor = MaskEditor(image_bgr, shadow_mask)
edited_mask = editor.run("Edit Shadow Mask")

# Lưu mặt nạ đã chỉnh sửa

# ─────────────────────────────────────────────
# 4. Hàm xoá bóng
# ─────────────────────────────────────────────
def remove_shadow(image_bgr: np.ndarray,
                  mask: np.ndarray,
                  blur_ksize: int = 61,
                  max_gain: float = 3.0,
                  feather: int = 9) -> np.ndarray:
    """
    Xoá bóng tại vùng mask (255 = bóng).

    Thuật toán:
    - Chuyển sang HSV, nâng kênh V (độ sáng) của vùng bóng lên mức
      ước lượng từ morphological closing (xấp xỉ độ sáng khi không có bóng).
    - Hoà trộn mềm (feathering) theo biên mask để tránh viền cứng.

    Tham số
    -------
    blur_ksize : kích thước kernel closing (pixel); lớn hơn → vùng nền rộng hơn.
    max_gain   : giới hạn hệ số khuếch đại sáng (tránh cháy trắng).
    feather    : sigma Gaussian làm mờ biên mask (pixel).
    """
    if image_bgr.ndim != 3 or image_bgr.shape[2] != 3:
        raise ValueError("image_bgr phải là ảnh màu 3 kênh (BGR).")
    if mask.shape[:2] != image_bgr.shape[:2]:
        raise ValueError("Kích thước mask không khớp với ảnh.")

    hsv_f = cv2.cvtColor(image_bgr, cv2.COLOR_BGR2HSV).astype(np.float32)
    H, S, V = cv2.split(hsv_f)

    # Ước lượng nền sáng cục bộ
    k = max(3, blur_ksize | 1)
    kernel_morph = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (k, k))
    V_bg = cv2.morphologyEx(V, cv2.MORPH_CLOSE, kernel_morph)
    V_bg = cv2.GaussianBlur(V_bg, (0, 0), sigmaX=k / 6)

    # Hệ số khuếch đại sáng
    eps = 1e-3
    gain = np.clip(V_bg / (V + eps), 1.0, max_gain)
    V_new = np.clip(V * gain, 0, 255)

    V_out = V.copy()
    V_out[mask > 0] = V_new[mask > 0]

    hsv_out = cv2.merge([H, S, V_out]).astype(np.uint8)
    result_bgr = cv2.cvtColor(hsv_out, cv2.COLOR_HSV2BGR)

    # Feathering
    mask_f = cv2.GaussianBlur(mask.astype(np.float32), (0, 0), sigmaX=feather) / 255.0
    mask_f = mask_f[..., np.newaxis]

    blended = (result_bgr.astype(np.float32) * mask_f +
               image_bgr.astype(np.float32) * (1.0 - mask_f))

    return np.clip(blended, 0, 255).astype(np.uint8)


# ─────────────────────────────────────────────
# 6. Áp dụng xoá bóng và hiển thị kết quả
# ─────────────────────────────────────────────

# Mở rộng nhẹ mask để bao phủ tốt hơn ở biên bóng
kernel_dilate = np.ones((5, 5), np.uint8)
mask_final = cv2.dilate(edited_mask, kernel_dilate, iterations=1)

shadow_removed = remove_shadow(
    image_bgr,
    mask_final,
    blur_ksize=61,
    max_gain=3.0,
    feather=9
)

# Hiển thị so sánh: ảnh gốc vs ảnh đã xoá bóng
image_rgb = cv2.cvtColor(image_bgr, cv2.COLOR_BGR2RGB)
fig, axes = plt.subplots(1, 2, figsize=(16, 8))
axes[0].imshow(image_rgb)
axes[0].set_title("Ảnh gốc")
axes[0].axis("off")
axes[1].imshow(cv2.cvtColor(shadow_removed, cv2.COLOR_BGR2RGB))
axes[1].set_title("Ảnh đã xoá bóng")
axes[1].axis("off")
plt.tight_layout()
plt.show()

# Lưu ảnh kết quả
cv2.imwrite("image_no_shadow.png", shadow_removed)
print("Đã lưu ảnh xoá bóng: image_no_shadow.png")
