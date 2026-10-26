import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum AppLanguage {
  vi('vi', 'Việt Nam'),
  en('en', 'English');

  final String code;
  final String label;

  const AppLanguage(this.code, this.label);

  static AppLanguage fromCode(String? code) {
    return AppLanguage.values.firstWhere(
      (language) => language.code == code,
      orElse: () => AppLanguage.vi,
    );
  }
}

const _languageStorageKey = 'seed_app_language';

final appLanguageProvider =
    StateNotifierProvider<AppLanguageNotifier, AppLanguage>((ref) {
  return AppLanguageNotifier()..load();
});

class AppLanguageNotifier extends StateNotifier<AppLanguage> {
  AppLanguageNotifier() : super(AppLanguage.vi);

  static const _storage = FlutterSecureStorage();

  Future<void> load() async {
    final savedCode = await _storage.read(key: _languageStorageKey);
    state = AppLanguage.fromCode(savedCode);
  }

  Future<void> setLanguage(AppLanguage language) async {
    state = language;
    await _storage.write(key: _languageStorageKey, value: language.code);
  }
}

String appText(AppLanguage language, String vi, String en) {
  return language == AppLanguage.en ? en : vi;
}

const _phrasePairs = <(String, String)>[
  ('Chuẩn bị ảnh', 'Preparing image'),
  ('Chuẩn bị nhận dạng trên thiết bị', 'Preparing on-device detection'),
  ('Phân tích trực tiếp trên thiết bị', 'Analyzing directly on device'),
  ('Chuẩn bị nhận dạng trên thiết bị', 'Preparing on-device detection'),
  ('Chuẩn bị ảnh để nhận dạng', 'Preparing image for detection'),
  ('Đang nhận dạng hạt trên thiết bị', 'Detecting grains on device'),
  ('Nhận dạng ROI', 'Detecting ROI'),
  (
    'Tạo hình dạng, đo hạt và dựng ảnh',
    'Creating masks, measuring grains, and rendering result'
  ),
  ('Lưu kết quả', 'Saving result'),
  ('Hoàn tất', 'Complete'),
  ('Đang xử lý', 'Processing'),
  (
    'Chọn ảnh hoặc chụp ảnh trước khi xử lý.',
    'Choose or capture an image before analyzing.'
  ),
  ('Kiểm tra chất lượng hạt', 'Grain quality check'),
  (
    'Hạt màu đỏ là vùng hệ thống nghi có lỗi tách vùng ảnh hoặc kích thước bất thường. Đây là gợi ý để người dùng kiểm tra lại, không phải kết luận loại hạt.',
    'Red grains are regions the system suspects may have segmentation errors or unusual size. This is a review hint, not a grain classification.'
  ),
  ('Kích thước', 'Size'),
  ('Quyết định', 'Decision'),
  ('Không còn hạt nghi ngờ cần xử lý.', 'No suspect grains need review.'),
  ('Xác nhận đây là hạt thật', 'Confirm this is a real grain'),
  ('Xóa nhận dạng sai khỏi kết quả', 'Remove wrong detection from result'),
  ('Hướng dẫn', 'Guide'),
  ('Xem hướng dẫn', 'View guide'),
  (
    'Kéo chốt A hoặc chốt B để khớp chính xác hai mép vật mốc.',
    'Drag handle A or B to match the two marker edges precisely.'
  ),
  (
    'Nhấn vào vùng bất kỳ trên ảnh để khởi tạo đoạn thẳng tham chiếu kích thước.',
    'Tap anywhere on the image to initialize the size reference line.'
  ),
  ('Chốt A', 'Handle A'),
  ('Chốt B', 'Handle B'),
  ('Chưa có ảnh', 'No image'),
  ('Chọn ảnh hoặc chụp ảnh để bắt đầu', 'Choose or capture an image to start'),
  (
    'Không xử lý được ảnh vì kết nối không ổn định hoặc hệ thống phản hồi quá lâu. Kiểm tra Wi-Fi rồi thử lại.',
    'Could not analyze the image because the connection is unstable or the system took too long. Check Wi-Fi and try again.'
  ),
  (
    'Thiết bị xử lý quá lâu nên đã dừng tác vụ. Hãy thử chụp gần hơn, giảm số hạt trong ảnh hoặc đóng các ứng dụng nền rồi xử lý lại.',
    'The device took too long and stopped the task. Try shooting closer, reducing grain count in the image, or closing background apps before retrying.'
  ),
  (
    'Thiết bị không đủ bộ nhớ để xử lý ảnh này. Hãy thử chụp ảnh gần hơn, giảm độ phân giải ảnh hoặc đóng các ứng dụng nền rồi thử lại.',
    'The device does not have enough memory for this image. Try shooting closer, reducing image resolution, or closing background apps before retrying.'
  ),
  ('Xử lý trên thiết bị thất bại', 'On-device analysis failed'),
  ('Vui lòng thử lại với ảnh khác.', 'Please try again with another image.'),
  ('Hướng dẫn căn mốc', 'Reference marker guide'),
  (
    '1. Upload ảnh hạt và vật mốc',
    '1. Upload grain image and reference marker'
  ),
  (
    'Chọn hoặc chụp ảnh có cả hạt cần đo và vật mốc có kích thước thật đã biết.',
    'Choose or capture an image containing both grains to measure and a reference marker with known real size.'
  ),
  ('2. Tạo đoạn đo bằng 2 chốt', '2. Create a measurement line with 2 handles'),
  (
    'Chạm lên vật mốc để tạo đoạn thẳng gồm chốt A và chốt B.',
    'Tap the reference marker to create a line with handle A and handle B.'
  ),
  ('3. Kéo thả chốt đo vật mốc', '3. Drag the reference marker handles'),
  (
    'Kéo từng chốt tới đúng hai mép vật mốc; có thể dùng nút mũi tên để tinh chỉnh từng pixel.',
    'Drag each handle to the two marker edges; use arrow buttons for pixel-level tuning.'
  ),
  ('4. Nhập kích thước thật', '4. Enter the real size'),
  (
    'Vẽ line để lấy kích thước px tự động, rồi nhập kích thước thật của vật mốc vào ô Kích thước thật (mm); để trống thì kết quả giữ đơn vị px.',
    'Draw the line to measure pixels automatically, then enter the marker real size in Real size (mm); leave it blank to keep pixel units.'
  ),
  ('Quay lại', 'Back'),
  ('Bắt đầu', 'Start'),
  ('Tiếp theo', 'Next'),
  ('Không tải được chi tiết', 'Could not load details'),
  ('Phiên bản mới', 'New version'),
  ('Để sau', 'Later'),
  ('Cập nhật', 'Update'),
  ('Có bản cập nhật mới', 'A new update is available'),
  (
    'Vui lòng cập nhật Seed trên Google Play.',
    'Please update Seed on Google Play.'
  ),
  (
    'Phiên đăng nhập đã hết hạn hoặc hệ thống tạm thời không phản hồi. Kéo xuống để thử lại.',
    'Your session expired or the system is temporarily not responding. Pull down to retry.'
  ),
  (
    'Không tải được dữ liệu. Kiểm tra Wi-Fi rồi thử lại.',
    'Could not load data. Check Wi-Fi and try again.'
  ),
  (
    'Không kết nối được. Kiểm tra Wi-Fi rồi thử lại.',
    'Could not connect. Check Wi-Fi and try again.'
  ),
  (
    'Không tải được dữ liệu. Kéo xuống để thử lại.',
    'Could not load data. Pull down to retry.'
  ),
  ('Email hoặc mật khẩu không đúng.', 'Email or password is incorrect.'),
  (
    'Đăng nhập thất bại. Vui lòng thử lại sau.',
    'Login failed. Please try again later.'
  ),
  ('Đăng nhập thất bại. Vui lòng thử lại.', 'Login failed. Please try again.'),
  (
    'Không kết nối được. Kiểm tra kết nối mạng rồi thử lại.',
    'Could not connect. Check your network and try again.'
  ),
  ('Nhỏ hơn đa số', 'Smaller than most'),
  ('Cỡ thường gặp', 'Typical size'),
  ('Lớn hơn đa số', 'Larger than most'),
  ('Phân bố chiều dài', 'Length distribution'),
  ('Phân bố chiều rộng', 'Width distribution'),
  ('Phân bố diện tích', 'Area distribution'),
  ('Hạt cần xem lại', 'Grains to review'),
  ('tổng số hạt', 'of total grains'),
  ('Khoảng phổ biến', 'Common range'),
  ('Cỡ thường gặp theo', 'Typical size by'),
  ('Nhóm kích thước theo', 'Size groups by'),
  ('chiều dài', 'length'),
  ('chiều rộng', 'width'),
  ('diện tích', 'area'),
  ('hạt', 'grains'),
  (
    'Mỗi cột là một nhóm hạt có kích thước gần nhau.',
    'Each column is a group of grains with similar sizes.'
  ),
  ('Không có hạt nghi ngờ', 'No suspect grains'),
  ('Ít hạt cần xem lại', 'Few grains need review'),
  ('Cần xem lại ảnh', 'Image needs review'),
];

String localizedText(AppLanguage language, String value) {
  if (language == AppLanguage.vi || value.isEmpty) return value;
  var next = value;
  final sortedPairs = [..._phrasePairs]
    ..sort((a, b) => b.$1.length - a.$1.length);
  for (final (vi, en) in sortedPairs) {
    next = next.replaceAll(vi, en);
  }
  return next;
}
