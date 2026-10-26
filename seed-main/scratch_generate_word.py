import os
import docx
from docx.shared import Inches, Pt, RGBColor
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.enum.table import WD_TABLE_ALIGNMENT, WD_ALIGN_VERTICAL
from docx.oxml import OxmlElement, parse_xml
from docx.oxml.ns import nsdecls, qn

def set_cell_background(cell, hex_color):
    shading_elm = parse_xml(f'<w:shd {nsdecls("w")} w:fill="{hex_color}"/>')
    cell._tc.get_or_add_tcPr().append(shading_elm)

def set_cell_margins(cell, top=100, bottom=100, left=150, right=150):
    tcPr = cell._tc.get_or_add_tcPr()
    tcMar = OxmlElement('w:tcMar')
    for m, val in [('top', top), ('bottom', bottom), ('left', left), ('right', right)]:
        node = OxmlElement(f'w:{m}')
        node.set(qn('w:w'), str(val))
        node.set(qn('w:type'), 'dxa')
        tcMar.append(node)
    tcPr.append(tcMar)

def create_document():
    doc = docx.Document()

    # Set page margins (Normal: 1 inch = 72 pt)
    sections = doc.sections
    for section in sections:
        section.top_margin = Inches(1.0)
        section.bottom_margin = Inches(1.0)
        section.left_margin = Inches(1.0)
        section.right_margin = Inches(1.0)

    # Base styling
    normal_style = doc.styles['Normal']
    normal_style.font.name = 'Times New Roman'
    normal_style.font.size = Pt(12)
    normal_style.font.color.rgb = RGBColor(30, 41, 59) # Slate 800

    # Title
    p_title = doc.add_paragraph()
    p_title.alignment = WD_ALIGN_PARAGRAPH.CENTER
    run_title = p_title.add_run("BÁO CÁO TỔNG QUAN KIẾN TRÚC VÀ TOÀN BỘ MÃ NGUỒN\nDỰ ÁN SEEDVISION")
    run_title.font.name = 'Times New Roman'
    run_title.font.size = Pt(20)
    run_title.font.bold = True
    run_title.font.color.rgb = RGBColor(15, 23, 42) # Slate 900
    p_title.paragraph_format.space_after = Pt(6)

    # Subtitle
    p_sub = doc.add_paragraph()
    p_sub.alignment = WD_ALIGN_PARAGRAPH.CENTER
    run_sub = p_sub.add_run("Hệ Thống Tự Động Đo Lường Hình Thái Học Hạt Giống Bằng Trí Tuệ Nhân Tạo & Thị Giác Máy Tính")
    run_sub.font.name = 'Times New Roman'
    run_sub.font.size = Pt(13)
    run_sub.font.italic = True
    run_sub.font.color.rgb = RGBColor(71, 85, 105) # Slate 600
    p_sub.paragraph_format.space_after = Pt(24)

    # Horizontal Divider Line / Box
    def add_heading_1(text):
        h = doc.add_paragraph()
        run = h.add_run(text)
        run.font.name = 'Times New Roman'
        run.font.size = Pt(15)
        run.font.bold = True
        run.font.color.rgb = RGBColor(30, 64, 175) # Blue 800
        h.paragraph_format.space_before = Pt(16)
        h.paragraph_format.space_after = Pt(6)
        return h

    def add_heading_2(text):
        h = doc.add_paragraph()
        run = h.add_run(text)
        run.font.name = 'Times New Roman'
        run.font.size = Pt(13)
        run.font.bold = True
        run.font.color.rgb = RGBColor(14, 116, 144) # Cyan 700
        h.paragraph_format.space_before = Pt(12)
        h.paragraph_format.space_after = Pt(4)
        return h

    def add_heading_3(text):
        h = doc.add_paragraph()
        run = h.add_run(text)
        run.font.name = 'Times New Roman'
        run.font.size = Pt(12)
        run.font.bold = True
        run.font.color.rgb = RGBColor(51, 65, 85)
        h.paragraph_format.space_before = Pt(8)
        h.paragraph_format.space_after = Pt(3)
        return h

    def add_p(text, bold_prefix="", italic=False):
        p = doc.add_paragraph()
        if bold_prefix:
            r_pre = p.add_run(bold_prefix)
            r_pre.font.bold = True
        r = p.add_run(text)
        r.font.italic = italic
        p.paragraph_format.space_after = Pt(5)
        p.paragraph_format.line_spacing = 1.2
        return p

    def add_bullet(text, bold_prefix=""):
        p = doc.add_paragraph(style='List Bullet')
        if bold_prefix:
            r_pre = p.add_run(bold_prefix)
            r_pre.font.bold = True
        p.add_run(text)
        p.paragraph_format.space_after = Pt(3)
        p.paragraph_format.line_spacing = 1.15
        return p

    def format_table(table, col_widths, headers, data):
        table.alignment = WD_TABLE_ALIGNMENT.CENTER
        # Header Row
        hdr_cells = table.rows[0].cells
        for i, h_text in enumerate(headers):
            hdr_cells[i].text = h_text
            set_cell_background(hdr_cells[i], "1E40AF") # Blue 800
            set_cell_margins(hdr_cells[i], top=120, bottom=120, left=150, right=150)
            p = hdr_cells[i].paragraphs[0]
            p.alignment = WD_ALIGN_PARAGRAPH.CENTER
            for r in p.runs:
                r.font.bold = True
                r.font.color.rgb = RGBColor(255, 255, 255)
                r.font.size = Pt(11)

        # Data Rows
        for r_idx, row_data in enumerate(data):
            row = table.add_row()
            bg_color = "F8FAFC" if r_idx % 2 == 1 else "FFFFFF"
            for c_idx, cell_value in enumerate(row_data):
                cell = row.cells[c_idx]
                cell.text = cell_value
                set_cell_background(cell, bg_color)
                set_cell_margins(cell, top=100, bottom=100, left=140, right=140)
                p = cell.paragraphs[0]
                p.paragraph_format.line_spacing = 1.15
                for r in p.runs:
                    r.font.size = Pt(10.5)

        # Set Column Widths
        for row in table.rows:
            for i, w in enumerate(col_widths):
                row.cells[i].width = Inches(w)

    # --- CHƯƠNG 1 ---
    add_heading_1("CHƯƠNG 1: TỔNG QUAN HỆ THỐNG")
    add_p("SeedVision là một hệ thống nghiên cứu khoa học và ứng dụng thực tiễn trong lĩnh vực Nông nghiệp Công nghệ cao (Agritech), kết hợp giữa Học Sâu (Deep Learning) và Thị giác Máy tính (Computer Vision) để tự động hóa hoàn toàn quy trình phân tích hình thái hạt giống. Hệ thống cho phép người dùng chụp ảnh mẫu hạt giống, tự động nhận diện từng hạt, bóc tách mặt nạ hình dạng, đo đạc kích thước thực tế (chiều dài, chiều rộng, diện tích, chu vi, độ tròn) và sàng lọc chất lượng mẫu hạt.")
    
    add_heading_2("1.1. Cấu trúc Tổng thể Dự án (Monorepo)")
    add_p("Dự án được tổ chức theo mô hình Monorepo đồng nhất, bao gồm 4 thành phần trụ cột:")
    add_bullet(" Nền tảng server viết bằng Express.js (Node.js) kết hợp MongoDB, điều phối tiến trình chạy worker Python xử lý ảnh, xác thực người dùng JWT và quản lý lịch sử đo đạc.", "1. Backend Server & API:")
    add_bullet(" Động cơ cốt lõi viết bằng Python, sử dụng thư viện ONNX Runtime, OpenCV và NumPy để chạy mô hình YOLOv8 Segmentation, đo đạc hình học, tinh chế mặt nạ và kết xuất dữ liệu.", "2. AI & Computer Vision Worker:")
    add_bullet(" Ứng dụng web SPA xây dựng bằng React 18, Vite, Material-UI, Canvas và Zustand. Cung cấp giao diện tương tác trực quan, vẽ vạch đo hiệu chuẩn (calibration), biểu đồ thống kê và xuất báo cáo CSV.", "3. Web Client:")
    add_bullet(" Ứng dụng di động đa nền tảng viết bằng Flutter (Dart). Điểm nổi bật nhất là khả năng suy luận 100% Offline (Local-First) ngay trên chip điện thoại mà không cần mạng Internet.", "4. Mobile App:")

    # --- CHƯƠNG 2 ---
    add_heading_1("CHƯƠNG 2: MÔ HÌNH HỌC SÂU VÀ FILE TRỌNG SỐ BEST.ONNX")
    
    add_heading_2("2.1. File `best.onnx` dùng để làm gì?")
    add_p("File `best.onnx` (được lưu trữ tại thư mục backend/model/main_model/best.onnx) là tệp trọng số mô hình Trí tuệ Nhân tạo cốt lõi của toàn bộ hệ sinh thái SeedVision. Mô hình được huấn luyện theo kiến trúc YOLOv8-seg (YOLOv8 Instance Segmentation) và chuyển đổi sang định dạng chuẩn mở ONNX (Open Neural Network Exchange).")
    add_p("Cụ thể, mô hình thực hiện 3 nhiệm vụ song song trong một lượt chạy (Single Pass):")
    add_bullet(" Dự đoán tọa độ khung bao (x, y, w, h) xác định vị trí của từng đối tượng trong ảnh.", "a) Định vị vật thể (Bounding Box Regression):")
    add_bullet(" Phân loại đối tượng thành 2 nhóm: Class 0 (hạt giống - 'seed') và Class 1 (vật mốc tham chiếu - 'ref' như đồng xu hoặc vạch chuẩn). Điều này giúp hệ thống tách biệt đối tượng cần đo và đối tượng dùng làm thước đo.", "b) Phân lớp đối tượng (Classification Head):")
    add_bullet(" Dự đoán 32 trọng số mặt nạ (mask coefficients) kết hợp với bản đồ nguyên mẫu Proto-mask kích thước 160x160 để tái tạo mặt nạ nhị phân (Binary Mask) bám sát tuyệt đối từng đường cong và góc cạnh của từng hạt giống.", "c) Phân đoạn cá thể (Instance Segmentation Head):")

    add_heading_2("2.2. Vì sao phải sử dụng Instance Segmentation thay vì Object Detection?")
    add_p("Trong bài toán đo đạc hạt giống, việc chỉ sử dụng Object Detection (hộp chữ nhật bao quanh) sẽ dẫn đến sai số rất lớn vì:")
    add_bullet(" Khi hạt giống nằm nghiêng ngẫu nhiên (góc chéo 45 độ), bounding box thẳng đứng sẽ ôm theo cả khoảng trống mặt bàn, khiến chiều dài và chiều rộng bị phóng đại sai lệch hoàn toàn. Với Instance Segmentation, thuật toán lấy được đúng viền hạt và dùng hình chữ nhật xoay tối thiểu (cv2.minAreaRect) ôm sát thân hạt để đo đúng kích thước thật.", "1. Sai lệch góc nghiêng:")
    add_bullet(" Object Detection chỉ tính được diện tích hình hộp (dài x rộng). Instance Segmentation cho phép đếm chính xác từng pixel thật của thân hạt giống.", "2. Đo diện tích và chu vi thực tế:")
    add_bullet(" Từ mặt nạ pixel mới tính được độ tròn (Circularity), độ đặc (Solidity) và áp dụng thuật toán tách hạt dính nhau (Merged Seed Split).", "3. Trích xuất đặc trưng hình thái học:")

    add_heading_2("2.3. Các Biến Thể Model Runtime trên Di Động")
    add_p("Nhằm đảm bảo ứng dụng mobile chạy mượt mà trên nhiều dòng máy điện thoại Android khác nhau, hệ thống phân phối thêm 2 mô hình đã tối ưu hóa tại mobile/assets/models/:")
    add_bullet(" Mô hình kích thước 640px, siêu nhẹ, tiết kiệm pin, dành cho các thiết bị di động có cấu hình phổ thông hoặc dung lượng RAM khả dụng thấp.", "• best_mobile_yolo26_640.onnx:")
    add_bullet(" Mô hình kích thước 1024px đã được lượng tử hóa số nguyên 8-bit (INT8 Quantization), vừa giữ được độ chính xác tương đương server vừa tăng tốc độ xử lý gấp nhiều lần trên chip di động hỗ trợ NPU/DSP.", "• best_1024_int8_static.onnx:")

    # --- CHƯƠNG 3 ---
    add_heading_1("CHƯƠNG 3: PIPELINE THỊ GIÁC MÁY TÍNH & ĐO ĐẠC (PYTHON)")
    add_p("Toàn bộ quy trình tính toán xử lý ảnh trên máy chủ được tổ chức trong module `backend/python/grain_pipeline/`:")

    headers_cv = ["Tên File Code", "Vai Trò Trong Pipeline", "Thuật Toán / Kỹ Thuật Sử Dụng"]
    data_cv = [
        ["analyze_grains.py", "File CLI Entrypoint", "Nhận đối số đường dẫn ảnh và params JSON từ Express server, gọi pipeline và trả kết quả ra stdout."],
        ["pipeline.py", "Bộ điều phối trung tâm", "Kết nối tuần tự 5 giai đoạn: Tiền xử lý -> YOLO -> Hậu xử lý -> Đo đạc -> Kết xuất ảnh."],
        ["preprocess.py", "Tiền xử lý ảnh đầu vào", "Chuẩn hóa hướng xoay EXIF, cân bằng trắng (White Balance), tăng tương phản thích ứng (CLAHE), khử nhiễu Bilateral."],
        ["yolo_segment.py", "Suy luận AI & Giải mã Tensor", "Chạy mô hình best.onnx trên ONNX Runtime, Letterbox resize, giải mã 32 mask coefficients, NMS, hỗ trợ Tiled Inference."],
        ["classical_fallback.py", "Cứu cánh CV truyền thống", "Tự động kích hoạt khi YOLO bị sót hạt (recall thấp): dùng Adaptive Thresholding, Background Subtraction, Contour finding."],
        ["mask_refine.py", "Hậu xử lý & Tách hạt dính", "Tách hạt dính nhau bằng Distance Transform & Watershed; lọc bỏ màu da tay (Skin Reject) và bóng đổ."],
        ["reference_marker.py", "Nhận dạng vật mốc chuẩn", "Tự động phát hiện đồng xu/vật mốc hình tròn bằng biến đổi Hough Circles (cv2.HoughCircles) để tính tỷ lệ mm/pixel."],
        ["measure.py", "Đo đạc kích thước & QC", "Tìm cv2.minAreaRect đo dài/rộng thật; tính diện tích, chu vi, độ tròn; lọc hạt dị tật bằng ngoại lai thống kê MAD Z-score."],
        ["render.py", "Kết xuất ảnh trực quan", "Vẽ ảnh Overlay (phủ màu viền hạt), ảnh Mask nhị phân, và ảnh Labels (đánh số ID từng hạt)."],
        ["io.py & config.py", "I/O & Cấu hình mặc định", "Đọc/ghi ảnh, mã hóa Base64, định nghĩa các ngưỡng mặc định (IoU, Confidence, kích thước tối đa)."]
    ]
    t_cv = doc.add_table(rows=1, cols=3)
    format_table(t_cv, [1.8, 1.8, 3.2], headers_cv, data_cv)
    doc.add_paragraph().paragraph_format.space_after = Pt(10)

    # --- CHƯƠNG 4 ---
    add_heading_1("CHƯƠNG 4: HỆ THỐNG MÁY CHỦ BACKEND (NODE.JS EXPRESS)")
    add_p("Phân hệ Backend được xây dựng theo chuẩn ES Modules hiện đại, đảm bảo tính mở rộng cao:")
    add_bullet(" Sử dụng `child_process.spawn` để kích hoạt worker Python bất đồng bộ, có cơ chế quản lý Timeout (mặc định 5 phút) tự động hủy tiến trình nếu phát sinh lỗi treo.", "• Quản lý tiến trình Worker (IPC):")
    add_bullet(" Hỗ trợ đồng thời 2 luồng: Phân tích nhanh cho khách vãng lai (/api/grain/analyze-public) không lưu dữ liệu, và phân tích có đăng nhập (/api/grain/analyze) lưu trữ đầy đủ lịch sử.", "• Chế độ Guest & Thành viên:")
    add_bullet(" Cơ chế mã hóa mật khẩu bcrypt, phát hành cặp token JWT (Access Token thời hạn ngắn và Refresh Token lưu trữ an toàn).", "• Bảo mật & Xác thực:")
    add_bullet(" Sử dụng Mongoose ODM với 2 bảng dữ liệu chính: User (tài khoản người dùng) và GrainAnalysisRun (toàn bộ kết quả phân tích, tham số và file artifacts ảnh/CSV).", "• Cơ sở dữ liệu MongoDB:")
    add_bullet(" Endpoint chuyên biệt /api/grain/runs/import cho phép ứng dụng Flutter đẩy toàn bộ lịch sử phân tích ngoại tuyến từ máy di động lên đám mây khi có kết nối mạng.", "• Đồng bộ dữ liệu Mobile:")

    # --- CHƯƠNG 5 ---
    add_heading_1("CHƯƠNG 5: PHÂN HỆ DI ĐỘNG FLUTTER (OFFLINE-FIRST)")
    add_p("Một trong những đóng góp kỹ thuật nổi bật nhất của đề tài là việc hiện thực hóa khả năng chạy suy luận Trí tuệ Nhân tạo ngoại tuyến (Edge AI) 100% trên điện thoại di động:")
    
    add_heading_2("5.1. File `offline_grain_analyzer.dart` (~4.800 dòng code)")
    add_p("Đội ngũ phát triển đã viết lại toàn bộ pipeline thị giác máy tính và cơ chế giải mã tensor nơ-ron sang ngôn ngữ Dart thuần:")
    add_bullet(" Nạp trực tiếp mô hình ONNX vào bộ nhớ thiết bị thông qua thư viện `flutter_onnxruntime`.", "1. Tích hợp ONNX Runtime Mobile:")
    add_bullet(" Sử dụng MethodChannel Android để truy vấn dung lượng RAM và Heap khả dụng của điện thoại. Nếu Heap >= 192MB, ứng dụng tự kích hoạt model 1024px INT8 chất lượng cao; nếu thiết bị yếu, ứng dụng chuyển sang model 640px để tránh lỗi tràn bộ nhớ (Out Of Memory).", "2. Quản lý tài nguyên thích ứng:")
    add_bullet(" Cài đặt lại các thuật toán giải mã tensor YOLOv8-seg, nhân ma trận hệ số mask, thuật toán Non-Maximum Suppression (NMS), thuật toán Rotating Calipers để tính MinAreaRect và lọc ngoại lai MAD Z-score bằng Dart thuần.", "3. Tự cài đặt giải thuật OpenCV trên Dart:")

    add_heading_2("5.2. Quản lý Dữ liệu Ngoại Tuyến & Đồng bộ")
    add_bullet(" Lưu kết quả đo đạc vào bộ nhớ cục bộ an toàn, cho phép xem lại lịch sử ngay cả khi ở vùng sâu vùng xa không có sóng điện thoại.", "• local_grain_run_store.dart:")
    add_bullet(" Dịch vụ chạy nền theo dõi trạng thái kết nối mạng (Wi-Fi/4G). Ngay khi có mạng, hệ thống tự động đồng bộ các bản ghi chưa lưu lên server.", "• connectivity_sync_service.dart:")
    add_bullet(" Tự động quét và phát hiện địa chỉ IP của máy chủ backend trong mạng nội bộ Wi-Fi (LAN).", "• api_base_url_resolver.dart:")

    # --- CHƯƠNG 6 ---
    add_heading_1("CHƯƠNG 6: GIAO DIỆN WEB CLIENT (REACT + VITE)")
    add_p("Giao diện người dùng Web mang phong cách hiện đại, tối ưu hóa trải nghiệm nghiên cứu và đo đạc:")
    add_bullet(" Hỗ trợ cả tải ảnh từ ổ đĩa lẫn mở Webcam chụp trực tiếp mẫu hạt trên bàn làm việc.", "• DashboardPage.jsx:")
    add_bullet(" Sử dụng Canvas tương tác cho phép người dùng phóng to/thu nhỏ, rê chuột xem số đo từng hạt, và đặc biệt là công cụ vẽ thước đo thủ công (Calibration Line) trực tiếp trên ảnh để gán kích thước thật tính bằng milimét.", "• DashboardPreviewPanel.jsx:")
    add_bullet(" Trực quan hóa phân bố kích thước hạt (chiều dài, chiều rộng, diện tích) dưới dạng biểu đồ cột thống kê trực quan.", "• GrainStatsCharts.jsx:")
    add_bullet(" Hiển thị bảng số liệu chi tiết từng hạt (kèm cờ cảnh báo bất thường QC) và hỗ trợ tải xuống file CSV phục vụ phân tích số liệu trên Excel hoặc SPSS.", "• DashboardResultPanel.jsx:")
    add_bullet(" Hỗ trợ chuyển đổi song ngữ Tiếng Việt và Tiếng Anh tức thì.", "• i18n.jsx:")

    # --- CHƯƠNG 7 ---
    add_heading_1("CHƯƠNG 7: DEVOPS VÀ TRIỂN KHAI ĐÁM MÂY (AZURE)")
    add_bullet(" Đóng gói toàn bộ mã nguồn vào Docker container qua 2 giai đoạn: Giai đoạn 1 biên dịch mã nguồn React Web; Giai đoạn 2 cài đặt môi trường chạy sản phẩm kết hợp Node.js 20, Python 3 và thư viện đồ họa hệ thống (libgl1, libglib2.0).", "• Multi-stage Dockerfile:")
    add_bullet(" Tự động kích hoạt khi có commit mới lên nhánh `main`, tự động build Docker image, đẩy lên Azure Container Registry (ACR) và deploy vào Azure Web App.", "• GitHub Actions CI/CD:")

    # --- CHƯƠNG 8 ---
    add_heading_1("CHƯƠNG 8: TỔNG KẾT VÀ KẾT LUẬN")
    add_p("Hệ thống SeedVision là một công trình nghiên cứu khoa học có tính ứng dụng thực tiễn rất cao. Dự án không chỉ dừng lại ở mức độ nghiên cứu mô hình lý thuyết mà đã hoàn thiện thành một hệ thống phần mềm đa nền tảng hoàn chỉnh, ổn định và sẵn sàng triển khai trên môi trường sản xuất thực tế.")
    add_p("Sự kết hợp giữa mô hình YOLOv8 Instance Segmentation hiện đại và các thuật toán hình học thị giác máy tính truyền thống giúp bài toán đạt được độ chính xác cao trong đo đạc kích thước hạt giống, đồng thời việc tối ưu hóa mô hình ONNX INT8 trên Flutter đã giải quyết triệt để bài toán hoạt động ngoài đồng ruộng khi không có kết nối mạng Internet.")

    # Save document
    output_path = r"c:\Study\Nghien_Cuu_Khoa_Hoc\seed-main\seed-main\BAO_CAO_TONG_QUAN_SEEDVISION.docx"
    doc.save(output_path)
    print(f"Đã tạo thành công file Word tại: {output_path}")

if __name__ == "__main__":
    create_document()

