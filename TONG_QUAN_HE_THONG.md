# BÁO CÁO TỔNG QUAN KIẾN TRÚC VÀ TOÀN BỘ HỆ THỐNG MÃ NGUỒN SEEDVISION

---

## I. TỔNG QUAN HỆ THỐNG
**SeedVision** là một giải pháp hoàn chỉnh (Monorepo) kết hợp giữa **Trí tuệ nhân tạo (AI)** và **Thị giác máy tính (Computer Vision)** nhằm tự động hóa việc nhận diện, bóc tách mặt nạ (Instance Segmentation), đo đạc các chỉ số hình thái học (chiều dài, chiều rộng, diện tích, độ tròn) và đánh giá chất lượng hạt giống.

Hệ thống được thiết kế với kiến trúc đa nền tảng:
- **Server-side Pipeline:** Node.js Express + Python (ONNX Runtime, OpenCV).
- **Client Web:** React 18, Vite, Material UI, Canvas.
- **Client Mobile:** Flutter (Android/iOS) với cơ chế **Local-First (Offline Inference)** bằng ONNX Runtime.

---

## II. `best.onnx` DÙNG ĐỂ LÀM GÌ?

File `best.onnx` (nằm tại `backend/model/main_model/best.onnx`) là **trọng số mô hình AI cốt lõi** của toàn bộ hệ thống trên server:

1. **Bản chất của file:**
   - Đây là mô hình học sâu **YOLOv8 Instance Segmentation (YOLOv8-seg)** đã được huấn luyện (train) trên tập dữ liệu hạt giống và vật mốc.
   - Mô hình sau đó được chuyển đổi (export) từ định dạng PyTorch (`.pt`) sang định dạng chuẩn công nghiệp **ONNX (Open Neural Network Exchange)**.
2. **Nhiệm vụ cụ thể trong bài toán:**
   - **Xác định vị trí (Object Detection):** Tìm tọa độ hộp bao (bounding box $x, y, w, h$) của từng đối tượng trong ảnh.
   - **Phân loại (Classification):** Phân biệt 2 lớp đối tượng:
     - `Class 0 (seed)`: Hạt giống cần đo.
     - `Class 1 (ref)`: Vật mốc tham chiếu (đồng xu hoặc thẻ tỷ lệ) dùng để tính tỷ lệ mm/pixel.
   - **Phân đoạn cá thể (Instance Segmentation):** Dự đoán 32 trọng số mặt nạ (mask coefficients) kết hợp với các ma trận nguyên mẫu (Proto-masks) để tạo ra **mặt nạ nhị phân (Binary Mask)** bám sát từng đường viền và góc cong của từng hạt giống.
3. **Tại sao lại dùng định dạng `.onnx`?**
   - Độc lập với framework PyTorch nặng nề.
   - Tối ưu hóa tốc độ chạy suy luận (Inference) trên CPU/GPU thông qua thư viện **ONNX Runtime**.
   - Dễ dàng tích hợp đa nền tảng (chạy bằng Python trên Backend và chạy bằng Dart/C++ trên Mobile).

---

## III. CẤU TRÚC VÀ VAI TRÒ CỦA TOÀN BỘ CÁC FILE MÃ NGUỒN

### 1. Phân hệ AI & Pipeline Xử lý ảnh (`backend/python/`)

Nằm tại thư mục `backend/python/grain_pipeline/`, đây là nơi thực hiện toàn bộ thuật toán tính toán khoa học:

| File | Vai trò & Thuật toán |
| :--- | :--- |
| **`analyze_grains.py`** | Entrypoint CLI. Nhận đường dẫn ảnh và tham số JSON từ Express server, gọi pipeline và trả kết quả về `stdout`. |
| **`pipeline.py`** | Bộ điều phối trung tâm (Orchestrator). Nối kết các giai đoạn: Tiền xử lý $\rightarrow$ YOLO $\rightarrow$ Tách hạt $\rightarrow$ Đo kích thước $\rightarrow$ Tạo ảnh trực quan. |
| **`yolo_segment.py`** | Nạp mô hình `best.onnx`, tiền xử lý Letterbox, chạy suy luận ONNX Runtime, lọc trùng lặp bằng Non-Maximum Suppression (NMS), hỗ trợ Tiled Inference (cắt lưới nhận diện hạt li ti). |
| **`preprocess.py`** | Tiền xử lý ảnh thị giác máy tính: Cân bằng trắng (White Balance), tăng độ tương phản thích ứng (CLAHE), lọc nhiễu Gaussian/Bilateral, xoay ảnh theo EXIF. |
| **`classical_fallback.py`** | Nhận diện cứu cánh bằng CV cổ điển: Khi YOLO bị sót hạt (recall thấp), thuật toán trừ nền (Background Subtraction) và phân ngưỡng thích ứng (Adaptive Thresholding) sẽ bổ sung các hạt bị thiếu. |
| **`mask_refine.py`** | Hậu xử lý mặt nạ: Áp dụng biến đổi khoảng cách (**Distance Transform**) và Watershed để **phân tách các hạt bị dính chùm**; loại trừ màu da tay (`enableSkinReject`) và bóng đổ. |
| **`reference_marker.py`** | Tự động phát hiện vật chuẩn đo lường (như đồng xu tròn) bằng thuật toán biến đổi Hough Circles (`cv2.HoughCircles`) để suy ra tỷ lệ quy đổi sang milimét ($mm$). |
| **`measure.py`** | Đo đạc hình học: Tìm hình chữ nhật bao xoay tối thiểu (`cv2.minAreaRect`) để tính chiều dài/rộng thật; tính diện tích, chu vi, độ tròn; lọc hạt dị tật bằng thuật toán thống kê ngoại lai **MAD Z-score**. |
| **`render.py`** | Kết xuất ảnh trực quan: Vẽ lớp phủ phân đoạn màu sắc (Overlay), mặt nạ trắng đen (Mask), và ảnh đánh số thứ tự ID từng hạt (Labels). |
| **`io.py` & `config.py`** | Quản lý đọc/ghi ảnh, chuyển đổi Base64, thiết lập các ngưỡng mặc định cho toàn bộ pipeline. |

---

### 2. Phân hệ Máy chủ Backend (`backend/src/`)

Viết bằng **Node.js (ES Modules)** và **Express.js**, kết nối **MongoDB**:

| File / Thư mục | Vai trò |
| :--- | :--- |
| **`src/index.js`** | Khởi tạo máy chủ Express, cấu hình middleware, CORS, bảo mật và kết nối Database. |
| **`src/services/grainProcessing.service.js`** | Cầu nối IPC (Inter-Process Communication). Nhận file ảnh từ client, gọi tiến trình Python con (`child_process.spawn`), giám sát timeout và bắt lỗi. |
| **`src/controllers/grain.controller.js`** | Xử lý nghiệp vụ phân tích ảnh công khai (Guest), phân tích có lưu trữ, cập nhật kết quả sau khi người dùng chỉnh sửa QC, xóa lượt phân tích. |
| **`src/controllers/auth.controller.js`** | Quản lý đăng ký, đăng nhập, cấp và làm mới cặp JWT (Access Token & Refresh Token). |
| **`src/models/GrainAnalysisRun.js`** | Schema MongoDB lưu trữ toàn bộ lịch sử đo đạc, thông số cấu hình và metadata của ảnh. |
| **`src/models/User.js`** | Schema MongoDB quản lý thông tin người dùng và phân quyền (Admin / User). |
| **`src/routes/`** | Định tuyến API cho hệ thống (`/api/auth`, `/api/users`, `/api/grain`). |

---

### 3. Phân hệ Ứng dụng Di động (`mobile/`)

Được xây dựng bằng **Flutter (Dart)**, sở hữu tính năng **chạy offline không cần mạng**:

| File / Thư mục | Vai trò |
| :--- | :--- |
| **`offline_grain_analyzer.dart`** | File đồ sộ (~4.800 dòng code). Tự xây dựng lại toàn bộ pipeline AI và giải thuật hình học bằng Dart thuần: chạy ONNX Runtime qua `flutter_onnxruntime`, giải mã tensor YOLO, NMS, MinAreaRect, phân tách hạt dính. |
| **`assets/models/`** | Chứa 2 model tối ưu cho di động:<br>- `best_mobile_yolo26_640.onnx`: Cấu hình an toàn cho máy cấu hình yếu.<br>- `best_1024_int8_static.onnx`: Cấu hình chất lượng cao INT8 cho máy có RAM heap $\ge$ 192MB. |
| **`local_grain_run_store.dart`** | Lưu trữ kết quả phân tích trực tiếp vào bộ nhớ điện thoại khi offline. |
| **`connectivity_sync_service.dart`** | Lắng nghe trạng thái mạng (Wi-Fi/4G), tự động đồng bộ kết quả offline lên máy chủ khi có mạng (`/api/grain/runs/import`). |
| **`dashboard_screen.dart`** | Màn hình chụp ảnh từ Camera/Gallery, hiển thị hướng dẫn đặt vật chuẩn và chạy phân tích. |
| **`storage_screen.dart`** | Màn hình quản lý lịch sử các đợt đo đạc trên máy. |

---

### 4. Phân hệ Giao diện Web Client (`web/`)

Xây dựng bằng **React 18 + Vite + Material UI (MUI)**:

| File / Thư mục | Vai trò |
| :--- | :--- |
| **`src/pages/DashboardPage.jsx`** | Giao diện làm việc chính: Chọn ảnh hoặc kết nối Webcam, tùy chỉnh kích thước vật mẫu, xem tiến trình nhận diện. |
| **`src/components/grain/DashboardPreviewPanel.jsx`** | Trình hiển thị tương tác bằng Canvas: Chuyển đổi giữa các chế độ Overlay/Mask/Labels, phóng to/thu nhỏ, vẽ vạch đo hiệu chuẩn (Calibration Line) trực quan. |
| **`src/components/grain/GrainStatsCharts.jsx`** | Biểu đồ trực quan hóa dữ liệu thống kê: Phân bố chiều dài, chiều rộng, diện tích của toàn bộ hạt. |
| **`src/components/grain/DashboardResultPanel.jsx`** | Bảng danh sách chi tiết từng hạt (kích thước mm, tỷ lệ tin cậy, cờ QC cảnh báo) và nút xuất dữ liệu ra file **CSV**. |
| **`src/pages/StoragePage.jsx`** | Xem lại lịch sử các đợt phân tích đã lưu trên hệ thống. |
| **`src/i18n.jsx`** | Hỗ trợ đa ngôn ngữ (Tiếng Việt và Tiếng Anh). |

---

### 5. Thư viện Dùng chung & DevOps (`shared/`, `scripts/`, `Dockerfile`)

| File | Vai trò |
| :--- | :--- |
| **`shared/src/constants/index.js`** | Định nghĩa các hằng số dùng chung giữa Web và Backend (API routes, Roles, HTTP Status). |
| **`shared/src/validators/index.js`** | Kiểm tra tính hợp lệ của tham số cấu hình đầu vào. |
| **`Dockerfile`** | Multi-stage build: Stage 1 biên dịch mã nguồn Web React; Stage 2 tạo môi trường chạy sản phẩm kết hợp Node.js 20, Python 3 và thư viện đồ họa OpenCV headless. |
| **`.github/workflows/deploy-...yml`** | CI/CD pipeline tự động build Docker image và deploy lên nền tảng **Azure Web App**. |

---

## IV. TỔNG KẾT LUỒNG DỮ LIỆU
1. Người dùng tải ảnh lên qua **Web** hoặc chụp từ **Mobile**.
2. Mô hình **`best.onnx`** thực hiện nhận diện và tách mặt nạ từng hạt giống.
3. Thuật toán **Thị giác máy tính (OpenCV/Dart)** đo kích thước hình học xoay, bóc tách hạt dính và quy đổi ra $mm$ thực tế nhờ vật chuẩn.
4. Dữ liệu được hiển thị dưới dạng **Ảnh phủ viền (Overlay)**, **Bảng số liệu (CSV)** và **Biểu đồ thống kê**.
