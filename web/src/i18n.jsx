import { createContext, useContext, useEffect, useMemo, useState } from 'react';

const LanguageContext = createContext(null);

const STORAGE_KEY = 'seed-app-language';

export const languages = [
  { code: 'vi', label: 'Việt Nam' },
  { code: 'en', label: 'English' },
];

const phrasePairs = [
  ['Trang chủ', 'Home'],
  ['Lưu trữ', 'Storage'],
  ['Tài khoản', 'Account'],
  ['Khách', 'Guest'],
  ['Chưa đồng bộ', 'Not synced'],
  ['Ngôn ngữ', 'Language'],
  ['Đăng nhập để đồng bộ', 'Log in to sync'],
  ['Đăng ký', 'Sign up'],
  ['Đăng xuất', 'Log out'],
  ['Đăng nhập', 'Log in'],
  ['ĐỊA CHỈ EMAIL', 'EMAIL ADDRESS'],
  ['MẬT KHẨU', 'PASSWORD'],
  ['HỌ VÀ TÊN', 'FULL NAME'],
  ['Nhập mật khẩu', 'Enter password'],
  ['Nhập họ và tên của bạn', 'Enter your full name'],
  ['Tiếp tục không đăng nhập', 'Continue without login'],
  ['Chưa có tài khoản?', 'No account yet?'],
  ['Đăng ký ngay', 'Sign up now'],
  ['Đã có tài khoản?', 'Already have an account?'],
  ['Đăng nhập ngay', 'Log in now'],
  ['Hình ảnh hiển thị', 'Image preview'],
  ['Sẵn sàng', 'Ready'],
  ['Đã xử lý', 'Processed'],
  ['Đánh dấu', 'Overlay'],
  ['Hình dạng', 'Mask'],
  ['Đánh số', 'Labels'],
  ['Ảnh gốc', 'Original'],
  ['Chỉnh hạt nghi ngờ', 'Edit suspect grains'],
  ['Xong chỉnh hạt', 'Finish editing'],
  ['Đang chỉnh kết quả kiểm tra hạt', 'Editing QC result'],
  ['Chưa có ảnh đầu vào', 'No input image'],
  ['Kích thước', 'Size'],
  ['Quyết định', 'Decision'],
  ['Không còn hạt nghi ngờ cần xử lý.', 'No suspect grains need review.'],
  ['Kích thước (mm)', 'Size (mm)'],
  ['Kéo 1 đoạn trên vật mốc', 'Drag one line on the reference marker'],
  ['Xóa vật mốc', 'Clear reference marker'],
  ['Kết nối camera', 'Connect camera'],
  ['Import ảnh', 'Import image'],
  ['Đang xử lý...', 'Processing...'],
  ['Chạy lại', 'Run again'],
  ['Chạy xử lý', 'Run analysis'],
  ['Hướng dẫn căn vật mốc', 'Reference marker guide'],
  ['Quay lại', 'Back'],
  ['Bắt đầu', 'Start'],
  ['Tiếp theo', 'Next'],
  ['QC là gì?', 'What is QC?'],
  ['Đã hiểu', 'Got it'],
  ['Thông số tham chiếu', 'Reference settings'],
  ['Đơn vị đo', 'Measurement unit'],
  ['Milimét (mm)', 'Millimeter (mm)'],
  ['Điểm ảnh (px)', 'Pixels (px)'],
  ['Tỷ lệ thước đo', 'Scale ratio'],
  ['Chưa thiết lập', 'Not set'],
  ['Kết quả phân tích', 'Analysis result'],
  ['Mã lần quét', 'Run ID'],
  ['Tổng số hạt đo được', 'Total measured grains'],
  ['Xuất CSV', 'Export CSV'],
  ['Xuất ảnh kết quả', 'Export result image'],
  ['Số hạt đo được', 'Measured grains'],
  ['Theo lần xử lý hiện tại', 'Current analysis'],
  ['Chưa có dữ liệu', 'No data yet'],
  ['Giá trị trung bình (dài × rộng)', 'Average value (length × width)'],
  ['Thống kê trung bình trên các hạt hợp lệ', 'Average statistics from valid grains'],
  ['Giá trị trung bình diện tích', 'Average area'],
  ['Độ lệch chuẩn (dài × rộng)', 'Standard deviation (length × width)'],
  ['Sau kiểm tra hạt nghi ngờ', 'After suspect-grain QC'],
  ['Dùng SD thô vì hạt nghi ngờ cao', 'Using raw SD because suspect ratio is high'],
  ['Độ lệch chuẩn diện tích', 'Area standard deviation'],
  ['Làm mới', 'Refresh'],
  ['Xóa', 'Delete'],
  ['Chi tiết xử lý', 'Analysis detail'],
  ['Không có overlay', 'No overlay'],
  ['Tên tệp ảnh', 'Image file name'],
  ['Thời gian quét', 'Scan time'],
  ['ĐLC chiều dài (báo cáo)', 'Length SD (reported)'],
  ['ĐLC chiều rộng (báo cáo)', 'Width SD (reported)'],
  ['ĐLC diện tích (báo cáo)', 'Area SD (reported)'],
  ['Hạt nghi ngờ sau kiểm tra', 'Suspect grains after QC'],
  ['Tóm tắt kích thước đã lưu', 'Saved size summary'],
  ['Đóng', 'Close'],
  ['Thông tin người dùng được dùng chung cho web và mobile.', 'User information is shared between web and mobile.'],
  ['Thông tin tài khoản', 'Account information'],
  ['Họ và tên', 'Full name'],
  ['Vai trò', 'Role'],
  ['Đơn vị đo mặc định', 'Default measurement unit'],
  ['Đang lưu...', 'Saving...'],
  ['Lưu thay đổi', 'Save changes'],
  ['Cài đặt', 'Settings'],
  ['Cài đặt website', 'Website settings'],
  ['Chế độ lưu ảnh', 'Image storage mode'],
  ['Lưu ảnh đã xử lý', 'Save processed image'],
  ['Lưu ảnh gốc', 'Save original image'],
  ['Lưu cả hai', 'Save both'],
  ['Tự động lưu kết quả sau xử lý', 'Automatically save results after analysis'],
  ['Hiển thị lưới tham chiếu khi xem ảnh', 'Show reference grid when viewing images'],
  ['Hủy', 'Cancel'],
  ['Lưu cài đặt', 'Save settings'],
  ['Kích thước hạt', 'Grain size'],
  ['Cách đọc kích thước', 'How to read size charts'],
  ['Chiều dài', 'Length'],
  ['Chiều rộng', 'Width'],
  ['Diện tích', 'Area'],
  ['Tất cả', 'All'],
  ['Biểu đồ phân bố', 'Distribution chart'],
  ['Cách đọc biểu đồ', 'How to read the chart'],
  ['Cách đọc phần kích thước', 'How to read size charts'],
  ['Chọn `Chiều dài`, `Chiều rộng` hoặc `Diện tích` để các thẻ số, nhóm kích thước và biểu đồ cùng đổi theo chỉ số đó.', 'Choose `Length`, `Width`, or `Area` so the number cards, size groups, and chart use the same metric.'],
  ['`Cỡ thường gặp` là trung vị: khoảng một nửa số hạt nhỏ hơn mức này, một nửa lớn hơn.', '`Typical size` is the median: about half the grains are smaller and half are larger.'],
  ['`Khoảng phổ biến` cho biết vùng kích thước mà phần lớn hạt rơi vào. Mỗi cột trong biểu đồ là một khoảng kích thước; số trên cột là số hạt trong khoảng đó.', '`Common range` shows where most grain sizes fall. Each chart column is a size range; the number above it is the grain count in that range.'],
  ['Số dưới cột là điểm bắt đầu của khoảng. Ví dụ cột `5+`, cột kế tiếp là `8+`, thì cột `5+` chứa các hạt có kích thước trong nửa khoảng [5; 8).', 'The label under a column is the start of the range. If one column is `5+` and the next is `8+`, the `5+` column contains grains in [5; 8).'],
  ['Chọn chỉ số muốn xem để đọc đúng theo chiều dài, chiều rộng hoặc diện tích.', 'Choose the metric to read length, width, or area consistently.'],
  ['Hạt cần xem lại', 'Grains to review'],
  ['Phiên đăng nhập đã hết hạn', 'Session expired'],
  ['Không tải được thông tin tài khoản', 'Could not load account information'],
  ['Đã cập nhật tài khoản', 'Account updated'],
  ['Cập nhật tài khoản thất bại', 'Account update failed'],
  ['Centimét (cm)', 'Centimeter (cm)'],
  ['Không thể kết nối camera. Kiểm tra quyền truy cập hoặc thiết bị.', 'Could not connect to the camera. Check permission or device access.'],
  ['Không thể đọc ảnh đã chọn. Vui lòng thử ảnh JPG hoặc PNG khác.', 'Could not read the selected image. Please try another JPG or PNG image.'],
  ['Chuẩn bị ảnh', 'Preparing image'],
  ['Vui lòng import ảnh hoặc bật camera trước khi xử lý.', 'Please import an image or turn on the camera before analyzing.'],
  ['Chuẩn bị xử lý', 'Preparing analysis'],
  ['Xác thực phiên', 'Checking session'],
  ['Đang nhận dạng hạt', 'Detecting grains'],
  ['Lưu kết quả', 'Saving result'],
  ['Hoàn tất', 'Complete'],
  ['Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại rồi chạy xử lý.', 'Your session expired. Please log in again and run analysis.'],
  ['Xử lý quá lâu. Hãy thử ảnh nhỏ hơn, chụp gần hơn hoặc xử lý lại sau.', 'Analysis took too long. Try a smaller image, shoot closer, or run it again later.'],
  ['Hệ thống đang chưa sẵn sàng. Vui lòng thử lại sau.', 'The system is not ready yet. Please try again later.'],
  ['Không kết nối được. Kiểm tra mạng rồi thử lại.', 'Could not connect. Check the network and try again.'],
  ['Không xử lý được ảnh. Vui lòng thử lại với ảnh khác hoặc kiểm tra kết nối.', 'Could not analyze the image. Try another image or check the connection.'],
  ['Không tải được lịch sử phân tích', 'Could not load analysis history'],
  ['Không tìm thấy bản xử lý local', 'Local analysis run was not found'],
  ['Không tải được chi tiết xử lý', 'Could not load analysis details'],
  ['Xóa lần xử lý', 'Delete analysis run'],
  ['Xóa lần xử lý thất bại', 'Could not delete analysis run'],
  ['Ảnh đánh dấu', 'Overlay image'],
  ['Xem', 'View'],
  ['hạt', 'grains'],
  ['ĐLC', 'SD'],
  ['TB', 'Avg'],
  ['Nhỏ hơn đa số', 'Smaller than most'],
  ['Cỡ thường gặp', 'Typical size'],
  ['Lớn hơn đa số', 'Larger than most'],
  ['Phân bố chiều dài', 'Length distribution'],
  ['Phân bố chiều rộng', 'Width distribution'],
  ['Phân bố diện tích', 'Area distribution'],
  ['Mỗi cột là một nhóm hạt có kích thước gần nhau.', 'Each column is a group of grains with similar sizes.'],
  ['Khoảng phổ biến', 'Common range'],
  ['Độ biến thiên (CV)', 'Coefficient of variation (CV)'],
  ['Độ lệch chuẩn / trung bình của các hạt hợp lệ.', 'Standard deviation / mean for valid grains.'],
  ['Nhóm kích thước theo', 'Size groups by'],
  ['Cỡ thường gặp theo', 'Typical size by'],
  ['chiều dài', 'length'],
  ['chiều rộng', 'width'],
  ['diện tích', 'area'],
  ['Không có hạt nghi ngờ', 'No suspect grains'],
  ['Ít hạt cần xem lại', 'Few grains need review'],
  ['Cần xem lại ảnh', 'Image needs review'],
  ['Xử lý trực tiếp trên thiết bị', 'Processed directly on device'],
  ['Xử lý qua hệ thống trực tuyến', 'Processed through online system'],
  ['1. Upload ảnh hạt và vật mốc', '1. Upload grain image and reference marker'],
  ['Chọn hoặc chụp ảnh có cả hạt cần đo và vật mốc có kích thước thật đã biết.', 'Choose or capture an image containing both grains to measure and a reference marker with known real size.'],
  ['2. Tạo đoạn đo bằng 2 chốt', '2. Create a measurement line with 2 handles'],
  ['Kéo chuột trên vật mốc để tạo đoạn thẳng gồm chốt A và chốt B.', 'Drag on the reference marker to create a line with handle A and handle B.'],
  ['3. Kéo thả chốt đo vật mốc', '3. Drag the reference marker handles'],
  ['Kéo từng chốt tới đúng hai mép vật mốc; có thể dùng nút mũi tên để tinh chỉnh.', 'Drag each handle to the two marker edges; use arrow buttons for fine tuning.'],
  ['4. Nhập kích thước thật', '4. Enter the real size'],
  ['Nhập chiều dài thật của vật mốc vào ô Kích thước (mm), sau đó bấm Xử lý.', 'Enter the marker real length in Size (mm), then press Analyze.'],
  ['Xem hướng dẫn căn mốc', 'View reference marker guide'],
  ['Giải thích QC và cách chỉnh hạt nghi ngờ', 'Explain QC and suspect-grain editing'],
  ['Hạt màu đỏ là vùng hệ thống nghi có lỗi tách vùng ảnh hoặc kích thước bất thường.', 'Red grains are regions the system suspects may have segmentation errors or unusual size.'],
  ['Đây là gợi ý để người dùng kiểm tra lại, không phải kết luận loại hạt.', 'This is a review hint, not a grain classification.'],
  ['Dùng bảng ID bên dưới ảnh: tích xanh để xác nhận là hạt thật, X đỏ để xóa hẳn nhận dạng sai khỏi kết quả.', 'Use the ID table below the image: green check confirms a real grain, red X removes a wrong detection from the result.'],
  ['Hạt nghi ngờ', 'Suspect grain'],
  ['Xác nhận đây là hạt thật', 'Confirm this is a real grain'],
  ['Xóa nhận dạng sai khỏi kết quả', 'Remove wrong detection from result'],
  ['*Ảnh chụp minh họa được chụp từ mobile app*', '*Example screenshots were captured from the mobile app*'],
  ['QC là bước kiểm tra chất lượng kết quả sau khi AI tách từng hạt. Nó không phải một loại hạt mới.', 'QC checks result quality after AI segments each grain. It is not a new grain type.'],
  ['Vùng xanh là hạt đang được tính là hợp lệ. Vùng đỏ là hạt hệ thống nghi có lỗi tách dính, tách thiếu, hoặc kích thước lệch bất thường so với nhóm còn lại.', 'Green regions are counted as valid grains. Red regions may be merged, under-segmented, or unusually sized compared with the rest.'],
  ['Nếu nhìn ảnh thấy hạt đỏ vẫn được tách đúng, bật "Chỉnh hạt nghi ngờ" rồi click vào hạt đó để chuyển về hợp lệ. Nếu một hạt xanh bị tách sai, click vào hạt đó để đánh dấu nghi ngờ.', 'If a red grain looks correctly segmented, turn on "Edit suspect grains" and click it to mark it valid. If a green grain is wrong, click it to mark it suspect.'],
  ['Sau khi chỉnh, số hạt nghi ngờ, độ lệch chuẩn báo cáo và file CSV sẽ được tính lại cho kết quả hiện tại.', 'After editing, suspect count, reported standard deviation, and CSV are recalculated for the current result.'],
  ['Hệ thống đang nghi', 'The system suspects'],
  ['có thể bị tách vùng ảnh sai hoặc có kích thước bất thường.', 'may have segmentation errors or unusual size.'],
  ['Độ lệch chuẩn báo cáo được tính trên', 'Reported standard deviation is calculated from'],
  ['hạt hợp lệ sau kiểm tra.', 'valid grains after QC.'],
  ['Tỷ lệ hạt nghi ngờ cao, nên hệ thống giữ độ lệch chuẩn thô và cần người dùng xem lại ảnh.', 'Suspect ratio is high, so the system keeps raw standard deviation and needs user review.'],
  ['Có thể dùng nút "Chỉnh hạt nghi ngờ" ở khung ảnh để sửa thủ công.', 'Use "Edit suspect grains" in the image panel to fix it manually.'],
  ['ID hạt nghi ngờ', 'Suspect grain IDs'],
];

const viToEn = new Map(phrasePairs);
const enToVi = new Map(phrasePairs.map(([vi, en]) => [en, vi]));

function replacePhrases(value, map) {
  let next = value;
  const entries = [...map.entries()].sort((a, b) => b[0].length - a[0].length);
  for (const [from, to] of entries) {
    if (next.includes(from)) next = next.split(from).join(to);
  }
  return next;
}

export function translateTextValue(value, language) {
  const map = language === 'en' ? viToEn : enToVi;
  const trimmed = value.trim();
  if (!trimmed) return value;
  if (map.has(trimmed)) return value.replace(trimmed, map.get(trimmed));
  return replacePhrases(value, map);
}

function translateDom(root, language) {
  if (typeof document === 'undefined') return;
  const walker = document.createTreeWalker(
    root,
    NodeFilter.SHOW_TEXT,
    {
      acceptNode(node) {
        const parent = node.parentElement;
        if (!parent || ['SCRIPT', 'STYLE', 'TEXTAREA', 'INPUT'].includes(parent.tagName)) {
          return NodeFilter.FILTER_REJECT;
        }
        return NodeFilter.FILTER_ACCEPT;
      },
    }
  );

  const nodes = [];
  while (walker.nextNode()) nodes.push(walker.currentNode);
  for (const node of nodes) {
    const nextValue = translateTextValue(node.nodeValue, language);
    if (nextValue !== node.nodeValue) node.nodeValue = nextValue;
  }

  for (const element of root.querySelectorAll?.('[aria-label], [title], [placeholder], [alt]') ?? []) {
    for (const attr of ['aria-label', 'title', 'placeholder', 'alt']) {
      if (element.hasAttribute(attr)) {
        const currentValue = element.getAttribute(attr);
        const nextValue = translateTextValue(currentValue, language);
        if (nextValue !== currentValue) element.setAttribute(attr, nextValue);
      }
    }
  }
}

export function LanguageProvider({ children }) {
  const [language, setLanguageState] = useState(() => {
    const saved = localStorage.getItem(STORAGE_KEY);
    return saved === 'en' ? 'en' : 'vi';
  });

  const setLanguage = (nextLanguage) => {
    const code = nextLanguage === 'en' ? 'en' : 'vi';
    setLanguageState(code);
    localStorage.setItem(STORAGE_KEY, code);
  };

  useEffect(() => {
    document.documentElement.lang = language === 'en' ? 'en' : 'vi';
    translateDom(document.body, language);
    const observer = new MutationObserver(() => translateDom(document.body, language));
    observer.observe(document.body, { childList: true, subtree: true, characterData: true });
    return () => observer.disconnect();
  }, [language]);

  const value = useMemo(
    () => ({
      language,
      setLanguage,
      text: (vi, en) => (language === 'en' ? en : vi),
    }),
    [language]
  );

  return <LanguageContext.Provider value={value}>{children}</LanguageContext.Provider>;
}

export function useLanguage() {
  const value = useContext(LanguageContext);
  if (!value) {
    throw new Error('useLanguage must be used inside LanguageProvider');
  }
  return value;
}
