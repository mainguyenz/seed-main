import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/network/api_client.dart';
import '../services/local_grain_run_store.dart';

final grainRunsProvider = FutureProvider<List<GrainRun>>((ref) async {
  try {
    const storage = FlutterSecureStorage();
    if (await storage.read(key: guestModeKey) == 'true') {
      final localRuns = await LocalGrainRunStore().readVisible(isGuest: true);
      return _localGrainRuns(localRuns);
    }
    final localStore = LocalGrainRunStore();
    final userId = await _currentUserId(storage);
    final pending = userId == null
        ? <Map<String, dynamic>>[]
        : await localStore.claimAndReadPendingForSync(userId);
    if (pending.isNotEmpty) {
      try {
        await ApiClient().post('/grain/runs/import', data: {'items': pending});
        await localStore.removePendingForSync(userId!);
      } catch (_) {
        // Keep pending local runs and retry next time storage refreshes.
      }
    }
    final response =
        await ApiClient().get('/grain/runs', params: {'limit': 100});
    final data = response.data['data'] as Map<String, dynamic>? ?? {};
    final items = data['items'] as List<dynamic>? ?? [];
    return items
        .map(
            (item) => GrainRun.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
  } on DioException catch (error) {
    const storage = FlutterSecureStorage();
    final isGuest = await storage.read(key: guestModeKey) == 'true';
    final localRuns = await LocalGrainRunStore().readVisible(
      isGuest: isGuest,
      userId: isGuest ? null : await _currentUserId(storage),
    );
    if (localRuns.isNotEmpty && error.response?.statusCode != 401) {
      return _localGrainRuns(localRuns);
    }
    if (error.response?.statusCode == 401) {
      // Don't clear tokens here — the ApiClient interceptor already
      // attempted a transparent refresh. If it still failed, show an
      // error message but keep the session alive so the user can retry
      // or navigate to another tab without being logged out.
      throw const GrainRunsException(
        'Phiên đăng nhập đã hết hạn hoặc hệ thống tạm thời không phản hồi. Kéo xuống để thử lại.',
      );
    }
    throw GrainRunsException(_friendlyDioMessage(error));
  }
});

Future<String?> _currentUserId(FlutterSecureStorage storage) async {
  final raw = await storage.read(key: userKey);
  if (raw == null || raw.isEmpty) return null;
  final user = jsonDecode(raw);
  if (user is! Map) return null;
  final value = user['_id']?.toString() ?? user['id']?.toString() ?? '';
  return value.isEmpty ? null : value;
}

List<GrainRun> _localGrainRuns(List<Map<String, dynamic>> localRuns) {
  return localRuns.map((item) {
    final result = Map<String, dynamic>.from(item['result'] as Map? ?? {});
    final run = Map<String, dynamic>.from(result['run'] as Map? ?? {});
    return GrainRun.fromJson({
      ...run,
      'sourceFileName': item['sourceFileName'] ?? run['sourceFileName'],
      'createdAt': item['createdAt'] ?? run['createdAt'],
      'summary': result['summary'],
      'image': result['image'],
      'calibration': result['calibration'],
      'overlay_png_base64': result['overlay_png_base64'],
    });
  }).toList();
}

String _friendlyDioMessage(DioException error) {
  return switch (error.type) {
    DioExceptionType.connectionTimeout ||
    DioExceptionType.receiveTimeout ||
    DioExceptionType.sendTimeout =>
      'Không tải được dữ liệu. Kiểm tra Wi-Fi rồi thử lại.',
    DioExceptionType.connectionError =>
      'Không kết nối được. Kiểm tra Wi-Fi rồi thử lại.',
    _ => 'Không tải được dữ liệu. Kéo xuống để thử lại.',
  };
}

class GrainRunsException implements Exception {
  final String message;

  const GrainRunsException(this.message);

  @override
  String toString() => message;
}

class GrainRun {
  final String id;
  final String sourceFileName;
  final DateTime? createdAt;
  final int count;
  final double meanLengthPx;
  final double meanWidthPx;
  final double meanAreaPx;
  final double? meanLengthMm;
  final double? meanWidthMm;
  final double? meanAreaMm2;
  final double? qcStdLengthPx;
  final double? qcStdWidthPx;
  final double? qcStdLengthMm;
  final double? qcStdWidthMm;
  final int imageWidth;
  final int imageHeight;
  final String overlayBase64;
  final bool calibrated;

  const GrainRun({
    required this.id,
    required this.sourceFileName,
    required this.createdAt,
    required this.count,
    required this.meanLengthPx,
    required this.meanWidthPx,
    required this.meanAreaPx,
    this.meanLengthMm,
    this.meanWidthMm,
    this.meanAreaMm2,
    this.qcStdLengthPx,
    this.qcStdWidthPx,
    this.qcStdLengthMm,
    this.qcStdWidthMm,
    required this.imageWidth,
    required this.imageHeight,
    required this.overlayBase64,
    required this.calibrated,
  });

  factory GrainRun.fromJson(Map<String, dynamic> json) {
    final summary = Map<String, dynamic>.from(json['summary'] as Map? ?? {});
    final image = Map<String, dynamic>.from(json['image'] as Map? ?? {});
    final calibration =
        Map<String, dynamic>.from(json['calibration'] as Map? ?? {});
    final calibrated = calibration['enabled'] == true;
    final qc = Map<String, dynamic>.from(summary['qc'] as Map? ?? {});
    final useRobustStats = qc['robust_used_for_reporting'] != false;
    dynamic reportedStd(String rawKey, String robustKey) => useRobustStats
        ? (summary[robustKey] ?? summary[rawKey])
        : summary[rawKey];
    return GrainRun(
      id: json['id']?.toString() ?? '',
      sourceFileName: json['sourceFileName']?.toString() ?? 'image.png',
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? ''),
      count: _asInt(summary['count']),
      meanLengthPx: _asDouble(summary['mean_length_px']),
      meanWidthPx: _asDouble(summary['mean_width_px']),
      meanAreaPx: _asDouble(summary['mean_area_px']),
      meanLengthMm:
          calibrated ? _nullableDouble(summary['mean_length_mm']) : null,
      meanWidthMm:
          calibrated ? _nullableDouble(summary['mean_width_mm']) : null,
      meanAreaMm2:
          calibrated ? _nullableDouble(summary['mean_area_mm2']) : null,
      qcStdLengthPx:
          _nullableStat(reportedStd('std_length_px', 'robust_std_length_px')),
      qcStdWidthPx:
          _nullableStat(reportedStd('std_width_px', 'robust_std_width_px')),
      qcStdLengthMm: calibrated
          ? _nullableStat(reportedStd('std_length_mm', 'robust_std_length_mm'))
          : null,
      qcStdWidthMm: calibrated
          ? _nullableStat(reportedStd('std_width_mm', 'robust_std_width_mm'))
          : null,
      imageWidth: _asInt(image['width']),
      imageHeight: _asInt(image['height']),
      overlayBase64: json['overlay_png_base64']?.toString() ?? '',
      calibrated: calibrated,
    );
  }
}

int _asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

double _asDouble(dynamic value) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

double? _nullableDouble(dynamic value) {
  if (value == null) return null;
  final parsed = _asDouble(value);
  return parsed.isFinite && parsed > 0 ? parsed : null;
}

double? _nullableStat(dynamic value) {
  if (value == null) return null;
  final parsed = _asDouble(value);
  return parsed.isFinite && parsed >= 0 ? parsed : null;
}
