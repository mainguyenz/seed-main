import '../constants/app_constants.dart';
import '../network/api_client.dart';

class MobileUpdateInfo {
  final String latestVersionName;
  final int latestBuildNumber;
  final int minSupportedBuildNumber;
  final String playStoreUrl;
  final String title;
  final String message;

  const MobileUpdateInfo({
    required this.latestVersionName,
    required this.latestBuildNumber,
    required this.minSupportedBuildNumber,
    required this.playStoreUrl,
    required this.title,
    required this.message,
  });

  bool isUpdateAvailable(int currentBuildNumber) =>
      latestBuildNumber > currentBuildNumber;

  bool isRequired(int currentBuildNumber) =>
      currentBuildNumber < minSupportedBuildNumber;

  factory MobileUpdateInfo.fromJson(Map<String, dynamic> json) {
    return MobileUpdateInfo(
      latestVersionName: json['latestVersionName']?.toString() ?? '',
      latestBuildNumber: _asInt(json['latestBuildNumber']),
      minSupportedBuildNumber: _asInt(json['minSupportedBuildNumber']),
      playStoreUrl: json['playStoreUrl']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Có bản cập nhật mới',
      message: json['message']?.toString() ??
          'Vui lòng cập nhật Seed trên Google Play.',
    );
  }
}

class MobileUpdateCheckResult {
  final MobileUpdateInfo updateInfo;
  final int currentBuildNumber;

  const MobileUpdateCheckResult({
    required this.updateInfo,
    required this.currentBuildNumber,
  });

  bool get isUpdateAvailable =>
      updateInfo.isUpdateAvailable(currentBuildNumber);

  bool get isRequired => updateInfo.isRequired(currentBuildNumber);
}

class MobileUpdateService {
  final _api = ApiClient();

  Future<MobileUpdateCheckResult?> check() async {
    final response = await _api.get('/mobile/version');
    final data = Map<String, dynamic>.from(response.data['data'] as Map);
    final updateInfo = MobileUpdateInfo.fromJson(data);

    if (!updateInfo.isUpdateAvailable(appBuildNumber)) return null;

    return MobileUpdateCheckResult(
      updateInfo: updateInfo,
      currentBuildNumber: appBuildNumber,
    );
  }
}

int _asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}
