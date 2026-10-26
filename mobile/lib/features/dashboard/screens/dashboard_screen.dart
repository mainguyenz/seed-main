import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/i18n/app_language.dart';
import '../../../core/theme/app_theme.dart';
import '../../grain/providers/grain_runs_provider.dart';
import '../../grain/services/grain_analysis_api.dart';
import '../../grain/widgets/grain_stats_charts.dart';
import '../providers/dashboard_state_provider.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen>
    with AutomaticKeepAliveClientMixin<DashboardScreen> {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final runsState = ref.watch(grainRunsProvider);

    return runsState.when(
      loading: () => _DashboardContent(
        onSessionResultChanged: (result) =>
            ref.read(dashboardStateProvider.notifier).setResult(result),
      ),
      error: (error, _) => _DashboardContent(
        historyError: error.toString(),
        onSessionResultChanged: (result) =>
            ref.read(dashboardStateProvider.notifier).setResult(result),
      ),
      data: (_) => _DashboardContent(
        onSessionResultChanged: (result) =>
            ref.read(dashboardStateProvider.notifier).setResult(result),
      ),
    );
  }
}

class _DashboardContent extends ConsumerWidget {
  final String? historyError;
  final ValueChanged<GrainAnalysisResult?> onSessionResultChanged;

  const _DashboardContent({
    this.historyError,
    required this.onSessionResultChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final language = ref.watch(appLanguageProvider);
    final screenWidth = MediaQuery.sizeOf(context).width;
    final horizontalPadding = screenWidth < 360 ? 12.0 : 20.0;

    return ListView(
      key: const PageStorageKey<String>('dashboard-home-scroll'),
      padding: EdgeInsets.all(horizontalPadding),
      children: [
        if (historyError != null) ...[
          Text(
            localizedText(language, historyError!),
            style: TextStyle(color: Colors.red.shade700),
          ),
          const SizedBox(height: 14),
        ],
        _BackendAnalysisCard(onResultChanged: onSessionResultChanged),
      ],
    );
  }
}

String _formatMeasureStat(double? primary, String primaryUnit, double? fallback,
    String fallbackUnit) {
  if (primary != null && primary > 0) {
    return '${primary.toStringAsFixed(primaryUnit == 'mm2' ? 3 : 2)} $primaryUnit';
  }
  if (fallback != null) {
    return '${fallback.toStringAsFixed(1)} $fallbackUnit';
  }
  return '_';
}

class _SeedVisionResultOverview extends ConsumerWidget {
  final GrainAnalysisResult result;

  const _SeedVisionResultOverview({required this.result});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final language = ref.watch(appLanguageProvider);
    final detectedCount = int.tryParse(
          result.segmentation['segment_count']?.toString() ?? '',
        ) ??
        result.count;
    final metrics = <(String, String)>[
      (
        appText(language, 'Tổng hạt nhận dạng', 'Total detected grains'),
        '$detectedCount',
      ),
      (
        appText(language, 'Hạt hợp lệ', 'Valid grains'),
        '${result.qcInlierCount}',
      ),
      (
        appText(language, 'Hạt cần xem lại', 'Grains to review'),
        '${result.qcSuspectCount}',
      ),
      (
        appText(language, 'Chiều dài TB', 'Average length'),
        _formatMeasureStat(
          result.meanLengthMm,
          'mm',
          result.meanLengthPx,
          'px',
        ),
      ),
      (
        appText(language, 'Chiều rộng TB', 'Average width'),
        _formatMeasureStat(
          result.meanWidthMm,
          'mm',
          result.meanWidthPx,
          'px',
        ),
      ),
      (
        appText(language, 'Diện tích TB', 'Average area'),
        _formatMeasureStat(
          result.meanAreaMm2,
          'mm2',
          result.meanAreaPx,
          'px2',
        ),
      ),
      (
        appText(language, 'ĐLC chiều dài', 'Length SD'),
        _formatMeasureStat(
          result.qcStdLengthMm,
          'mm',
          result.qcStdLengthPx,
          'px',
        ),
      ),
      (
        appText(language, 'ĐLC chiều rộng', 'Width SD'),
        _formatMeasureStat(
          result.qcStdWidthMm,
          'mm',
          result.qcStdWidthPx,
          'px',
        ),
      ),
      (
        appText(language, 'ĐLC diện tích', 'Area SD'),
        _formatMeasureStat(
          result.qcStdAreaMm2,
          'mm2',
          result.qcStdAreaPx,
          'px2',
        ),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          appText(language, 'Kết quả nhận dạng và thống kê',
              'Detection and statistics result'),
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        Text(
          appText(
            language,
            'Số liệu và biểu đồ được tính trực tiếp từ các hạt đã nhận dạng trong ảnh.',
            'Figures and charts are calculated directly from grains detected in the image.',
          ),
          style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 620
                ? 3
                : (constraints.maxWidth >= 280 ? 2 : 1);
            const gap = 10.0;
            final tileWidth = columns == 1
                ? constraints.maxWidth
                : (constraints.maxWidth - gap * (columns - 1)) / columns;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final metric in metrics)
                  SizedBox(
                    width: tileWidth,
                    child: _OverviewStatTile(
                      label: metric.$1,
                      value: metric.$2,
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        GrainStatsCharts(result: result),
      ],
    );
  }
}

class _OverviewStatTile extends StatelessWidget {
  final String label;
  final String value;

  const _OverviewStatTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 82),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.bgDefault,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 5),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

String _localizedProgressPhase(AppLanguage language, String phase) {
  if (language == AppLanguage.vi) return phase;
  return switch (phase) {
    'Chuẩn bị ảnh' => 'Preparing image',
    'Chuẩn bị nhận dạng trên thiết bị' => 'Preparing on-device detection',
    'Phân tích trực tiếp trên thiết bị' => 'Analyzing directly on device',
    'Chuẩn bị ảnh để nhận dạng' => 'Preparing image for detection',
    'Đang nhận dạng hạt trên thiết bị' => 'Detecting grains on device',
    'Tạo hình dạng, đo hạt và dựng ảnh' =>
      'Creating masks, measuring grains, and rendering result',
    'Đang nhận dạng hạt' => 'Detecting grains',
    'Đo kích thước' => 'Measuring size',
    'Lưu kết quả' => 'Saving result',
    'Hoàn tất' => 'Complete',
    'Đang xử lý' => 'Processing',
    _ => phase.startsWith('Nhận dạng ROI ')
        ? phase.replaceFirst('Nhận dạng ROI ', 'Detecting ROI ')
        : localizedText(language, phase),
  };
}

class _BackendAnalysisCard extends ConsumerStatefulWidget {
  final ValueChanged<GrainAnalysisResult?> onResultChanged;

  const _BackendAnalysisCard({required this.onResultChanged});

  @override
  ConsumerState<_BackendAnalysisCard> createState() =>
      _BackendAnalysisCardState();
}

class _BackendAnalysisCardState extends ConsumerState<_BackendAnalysisCard>
    with AutomaticKeepAliveClientMixin<_BackendAnalysisCard> {
  static const _previewCacheWidth = 1200;

  final _picker = ImagePicker();
  final _api = GrainAnalysisApi();
  final _referencePixels = TextEditingController();
  final _referenceMm = TextEditingController();

  Timer? _progressTimer;
  String _decodedPreviewKey = '';
  Uint8List? _decodedPreviewBytes;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _progressTimer?.cancel();
    _referencePixels.dispose();
    _referenceMm.dispose();
    super.dispose();
  }

  void _setProgress(double value, String phase) {
    ref.read(dashboardStateProvider.notifier).setProgress(value, phase);
  }

  void _startProgressDrift() {
    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(const Duration(milliseconds: 700), (_) {
      if (!mounted) return;
      final currentProgress = ref.read(dashboardStateProvider).progress;
      if (currentProgress < 82) {
        ref.read(dashboardStateProvider.notifier).setProgress(
              (currentProgress + 2).clamp(0, 82),
              ref.read(dashboardStateProvider).progressPhase,
            );
      }
    });
  }

  void _stopProgress() {
    _progressTimer?.cancel();
    _progressTimer = null;
  }

  void _clearPreviewCache() {
    _decodedPreviewKey = '';
    _decodedPreviewBytes = null;
  }

  Uint8List? _previewBytesFor(GrainAnalysisResult? result, String mode) {
    if (result == null) {
      _clearPreviewCache();
      return null;
    }
    final previewBase64 = result.previewWithFallback(mode);
    if (previewBase64.isEmpty) {
      _clearPreviewCache();
      return null;
    }
    final cacheKey =
        '${identityHashCode(result)}:$mode:${previewBase64.length}';
    if (_decodedPreviewKey == cacheKey) return _decodedPreviewBytes;
    try {
      _decodedPreviewBytes = base64Decode(previewBase64);
      _decodedPreviewKey = cacheKey;
      return _decodedPreviewBytes;
    } on FormatException {
      _clearPreviewCache();
      return null;
    }
  }

  void _applySuggestedReferenceLine(GrainAnalysisResult result) {
    final current = ref.read(dashboardStateProvider);
    if (current.referenceStart != null && current.referenceEnd != null) return;
    final suggestion = result.calibration['suggested_reference'];
    if (suggestion is! Map || suggestion['available'] != true) return;
    final start = _suggestedReferenceOffset(suggestion, 'x1', 'y1');
    final end = _suggestedReferenceOffset(suggestion, 'x2', 'y2');
    if (start == null || end == null || (end - start).distance <= 1) return;
    ref.read(dashboardStateProvider.notifier).setReferenceLine(start, end);
  }

  Offset? _suggestedReferenceOffset(
    Map<dynamic, dynamic> suggestion,
    String xKey,
    String yKey,
  ) {
    final x = (suggestion[xKey] as num?)?.toDouble();
    final y = (suggestion[yKey] as num?)?.toDouble();
    if (x == null ||
        y == null ||
        !x.isFinite ||
        !y.isFinite ||
        x < 0 ||
        y < 0) {
      return null;
    }
    return Offset(x, y);
  }

  bool _hasSuggestedReference(GrainAnalysisResult? result) {
    final suggestion = result?.calibration['suggested_reference'];
    return suggestion is Map && suggestion['available'] == true;
  }

  ({double pixels, String pixelSpace, String source})? _calibrationReference(
      GrainAnalysisResult result) {
    final suggestion = result.calibration['suggested_reference'];
    if (suggestion is Map && suggestion['available'] == true) {
      final pixels = _asDouble(suggestion['pixels']);
      if (pixels > 1) {
        return (
          pixels: pixels,
          pixelSpace: 'original',
          source: 'detected_ref_post_analysis'
        );
      }
      final processed = suggestion['processed'];
      if (processed is Map) {
        final processedPixels = _asDouble(processed['pixels']);
        if (processedPixels > 1) {
          return (
            pixels: processedPixels,
            pixelSpace: 'processed',
            source: 'detected_ref_post_analysis'
          );
        }
      }
    }

    final stateVal = ref.read(dashboardStateProvider);
    final start = stateVal.referenceStart;
    final end = stateVal.referenceEnd;
    if (start == null || end == null) return null;
    final pixels = (end - start).distance;
    if (pixels <= 1) return null;
    return (
      pixels: pixels,
      pixelSpace: 'original',
      source: 'manual_line_post_analysis'
    );
  }

  double? _parsePositiveNumber(String value) {
    final parsed = double.tryParse(value.trim().replaceAll(',', '.'));
    return parsed != null && parsed.isFinite && parsed > 0 ? parsed : null;
  }

  Future<void> _applyCalibrationFromCurrentReference() async {
    final stateVal = ref.read(dashboardStateProvider);
    final result = stateVal.result;
    if (result == null) return;
    final reference = _calibrationReference(result);
    if (reference == null) {
      ref.read(dashboardStateProvider.notifier).setError(
          'Vẽ đường tham chiếu trên vật mốc trước khi áp dụng đơn vị mm.');
      return;
    }
    final referenceMm = _parsePositiveNumber(_referenceMm.text);
    if (referenceMm == null) {
      ref.read(dashboardStateProvider.notifier).setError(
          'Nhập kích thước thật của vật mốc theo mm trước khi áp dụng.');
      return;
    }

    final next = result.withAppliedCalibration(
      referencePixels: reference.pixels,
      referenceMm: referenceMm,
      referenceX1: stateVal.referenceStart?.dx,
      referenceY1: stateVal.referenceStart?.dy,
      referenceX2: stateVal.referenceEnd?.dx,
      referenceY2: stateVal.referenceEnd?.dy,
      referencePixelSpace: reference.pixelSpace,
      source: reference.source,
    );
    await _applyEditedResult(next);
    ref.read(dashboardStateProvider.notifier).markCalibrationApplied();
  }

  void _confirmPixelOnly() {
    ref.read(dashboardStateProvider.notifier).confirmPixelOnly();
  }

  void _requestManualCalibration() {
    ref.read(dashboardStateProvider.notifier).requestManualCalibration();
  }

  Future<void> _pick(ImageSource source) async {
    try {
      final file = await _picker.pickImage(
        source: source,
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 92,
        requestFullMetadata: false,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      final imageSize = await _imageSizeFromBytes(bytes);
      if (!mounted) return;
      ref
          .read(dashboardStateProvider.notifier)
          .setSelectedImage(bytes, imageSize, file.name);
      _clearPreviewCache();
    } catch (_) {
      if (!mounted) return;
      ref.read(dashboardStateProvider.notifier).setError(
          'Không thể đọc ảnh đã chọn. Vui lòng thử ảnh JPG hoặc PNG khác.');
    }
  }

  static Future<Size?> _imageSizeFromBytes(Uint8List bytes) async {
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    try {
      buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      return Size(descriptor.width.toDouble(), descriptor.height.toDouble());
    } catch (_) {
      return null;
    } finally {
      descriptor?.dispose();
      buffer?.dispose();
    }
  }

  Future<void> _analyze() async {
    final stateVal = ref.read(dashboardStateProvider);
    final bytes = stateVal.selectedBytes;
    if (bytes == null) {
      ref
          .read(dashboardStateProvider.notifier)
          .setError('Chọn ảnh hoặc chụp ảnh trước khi xử lý.');
      return;
    }

    ref.read(dashboardStateProvider.notifier).setBusy(true);
    ref.read(dashboardStateProvider.notifier).setError(null);
    ref.read(dashboardStateProvider.notifier).setQcEditMode(false);
    _setProgress(5, 'Chuẩn bị ảnh');
    try {
      _setProgress(
        20,
        'Chuẩn bị nhận dạng trên thiết bị',
      );
      _setProgress(
        50,
        'Phân tích trực tiếp trên thiết bị',
      );
      _startProgressDrift();
      final result = await _api
          .analyzeImage(
            bytes: bytes,
            fileName: stateVal.fileName,
            onProgress: (value, phase) {
              if (mounted) _setProgress(value, phase);
            },
          )
          .timeout(const Duration(minutes: 5));
      _stopProgress();
      _setProgress(96, 'Lưu kết quả');
      if (!mounted) return;
      final notifier = ref.read(dashboardStateProvider.notifier);
      notifier.setResult(result);
      notifier.resetCalibrationDecision();
      _applySuggestedReferenceLine(result);
      _clearPreviewCache();
      widget.onResultChanged(result);
      _setProgress(100, 'Hoàn tất');
      ref.invalidate(grainRunsProvider);
    } catch (error) {
      _stopProgress();
      if (!mounted) return;
      ref.read(dashboardStateProvider.notifier).setError(_friendlyError(error));
    } finally {
      _stopProgress();
      if (mounted) {
        ref.read(dashboardStateProvider.notifier).setBusy(false);
        Future.delayed(const Duration(milliseconds: 500), () {
          if (!mounted) return;
          ref.read(dashboardStateProvider.notifier).setProgress(0, '');
        });
      }
    }
  }

  Future<void> _shareCsv() async {
    final stateVal = ref.read(dashboardStateProvider);
    final csv = stateVal.result?.csv;
    if (csv == null || csv.isEmpty) return;
    final file = await _writeTempFile(
        '${_safeStem(stateVal.fileName)}_measurements.csv', utf8.encode(csv));
    await Share.shareXFiles([XFile(file.path)],
        text: 'SeedVision measurements CSV');
  }

  Future<void> _sharePng() async {
    final stateVal = ref.read(dashboardStateProvider);
    final base64 = stateVal.result?.previewWithFallback('samMask');
    if (base64 == null || base64.isEmpty) return;
    final file = await _writeTempFile(
        '${_safeStem(stateVal.fileName)}_segmentation.png',
        base64Decode(base64));
    await Share.shareXFiles([XFile(file.path)],
        text: 'SeedVision segmentation PNG');
  }

  Future<void> _applyEditedResult(GrainAnalysisResult next) async {
    ref.read(dashboardStateProvider.notifier).setResult(next);
    _clearPreviewCache();
    widget.onResultChanged(next);
    await _api.persistEditedRun(next);
    ref.invalidate(grainRunsProvider);
  }

  Future<void> _confirmSuspect(int measurementId) async {
    final current = ref.read(dashboardStateProvider).result;
    if (current == null) return;
    await _applyEditedResult(current.withConfirmedGrain(measurementId));
  }

  Future<void> _deleteSuspect(int measurementId) async {
    final current = ref.read(dashboardStateProvider).result;
    if (current == null) return;
    await _applyEditedResult(current.withDeletedMeasurement(measurementId));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final stateVal = ref.watch(dashboardStateProvider);
    final result = stateVal.result;
    final language = ref.watch(appLanguageProvider);
    final previewBytes = _previewBytesFor(result, stateVal.previewMode);
    final screenWidth = MediaQuery.sizeOf(context).width;
    final cardPadding = screenWidth < 360 ? 12.0 : 18.0;

    final distance =
        stateVal.referenceStart != null && stateVal.referenceEnd != null
            ? (stateVal.referenceEnd! - stateVal.referenceStart!).distance
            : null;
    final suggestedReferenceAvailable = _hasSuggestedReference(result);
    final showReferenceTools = result != null &&
        !result.calibrated &&
        !stateVal.pixelOnlyConfirmed &&
        (suggestedReferenceAvailable || stateVal.manualCalibrationRequested);
    final calibrationReference =
        result == null ? null : _calibrationReference(result);
    final displayReferencePixels = calibrationReference?.pixels ?? distance;
    _referencePixels.text = displayReferencePixels != null
        ? displayReferencePixels.toStringAsFixed(1)
        : '';
    if (_referenceMm.text != stateVal.referenceMmInput) {
      _referenceMm.text = stateVal.referenceMmInput;
    }

    return Card(
      child: Padding(
        padding: EdgeInsets.all(cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              appText(language, 'Phân tích hạt SeedVision',
                  'SeedVision grain analysis'),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              appText(
                language,
                'Nhận dạng từng hạt, đếm số lượng, đo kích thước và dựng biểu đồ từ cùng một ảnh.',
                'Detect individual grains, count them, measure their size, and build charts from one image.',
              ),
              style: const TextStyle(
                fontSize: 13,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                OutlinedButton.icon(
                  onPressed:
                      stateVal.busy ? null : () => _pick(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library_outlined),
                  label: Text(appText(language, 'Chọn ảnh', 'Choose image')),
                ),
                OutlinedButton.icon(
                  onPressed:
                      stateVal.busy ? null : () => _pick(ImageSource.camera),
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: const Text('Camera'),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _ReferenceImageSelector(
              bytes: stateVal.selectedBytes,
              imageSize: stateVal.selectedImageSize,
              start: stateVal.referenceStart,
              end: stateVal.referenceEnd,
              enabled: showReferenceTools &&
                  !stateVal.busy &&
                  stateVal.selectedBytes != null,
              showReferenceTools: showReferenceTools,
              referenceDetected: suggestedReferenceAvailable,
              onPickImage:
                  stateVal.busy ? null : () => _pick(ImageSource.gallery),
              onChanged: (start, end) {
                ref
                    .read(dashboardStateProvider.notifier)
                    .setReferenceLine(start, end);
              },
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: stateVal.busy || stateVal.selectedBytes == null
                    ? null
                    : _analyze,
                icon: stateVal.busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_awesome_motion_outlined),
                label: Text(stateVal.busy
                    ? appText(language, 'Đang xử lý', 'Processing')
                    : appText(language, 'Nhận dạng & thống kê',
                        'Detect, count & analyze')),
              ),
            ),
            if (stateVal.error != null) ...[
              const SizedBox(height: 12),
              Text(
                localizedText(language, stateVal.error!),
                style: TextStyle(color: Colors.red.shade700),
              ),
            ],
            if (stateVal.busy) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      stateVal.progressPhase.isEmpty
                          ? appText(language, 'Đang xử lý', 'Processing')
                          : _localizedProgressPhase(
                              language, stateVal.progressPhase),
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  Text(
                    '${stateVal.progress.round()}%',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              LinearProgressIndicator(
                  value: (stateVal.progress / 100).clamp(0, 1)),
            ],
            if (result != null && !result.calibrated) ...[
              const SizedBox(height: 12),
              _buildCalibrationDecisionPanel(
                language: language,
                stateVal: stateVal,
                result: result,
                suggestedReferenceAvailable: suggestedReferenceAvailable,
              ),
            ],
            if (result != null) ...[
              const SizedBox(height: 18),
              _SeedVisionResultOverview(result: result),
            ],
            if (result != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF4E5),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFF2C078)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.fact_check_outlined,
                          size: 20,
                          color: Color(0xFF9A3412),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                appText(language, 'Kiểm tra chất lượng hạt',
                                    'Grain quality check'),
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF7C2D12),
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                appText(
                                  language,
                                  'Hạt màu đỏ là vùng hệ thống nghi có lỗi tách vùng ảnh hoặc kích thước bất thường. Đây là gợi ý để người dùng kiểm tra lại, không phải kết luận loại hạt.',
                                  'Red grains are regions the system suspects may have segmentation errors or unusual size. This is a review hint, not a grain classification.',
                                ),
                                style: const TextStyle(fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _QcFactCard(
                            label: appText(language, 'Hạt đang nghi ngờ',
                                'Suspect grains'),
                            value: '${result.qcSuspectCount}',
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _QcFactCard(
                            label:
                                appText(language, 'ID nghi ngờ', 'Suspect IDs'),
                            value: result.qcSuspectIdsLabel.isEmpty
                                ? '-'
                                : result.qcSuspectIdsLabel,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _previewChip(
                    mode: 'overlay',
                    label: appText(language, 'Đánh dấu', 'Overlay'),
                    previewMode: stateVal.previewMode,
                  ),
                  _previewChip(
                    mode: 'mask',
                    label: appText(language, 'Hình dạng', 'Mask'),
                    previewMode: stateVal.previewMode,
                  ),
                  _previewChip(
                    mode: 'labels',
                    label: appText(language, 'Đánh số', 'Labels'),
                    previewMode: stateVal.previewMode,
                  ),
                  _qcEditChip(stateVal.qcEditMode),
                ],
              ),
              if (stateVal.qcEditMode) ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF93C5FD)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.touch_app_outlined,
                        size: 18,
                        color: Color(0xFF2563EB),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          appText(
                            language,
                            'Đang chỉnh hạt nghi ngờ: dùng bảng ID dưới ảnh. Tích xanh để xác nhận là hạt thật, X đỏ để xóa hẳn nhận dạng sai khỏi kết quả.',
                            'Editing suspect grains: use the ID table below the image. Tap the green check to confirm a real grain, or the red X to remove a wrong detection.',
                          ),
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF1E3A8A),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              if (previewBytes != null)
                _QcEditablePreview(
                  result: result,
                  previewBytes: previewBytes,
                  editMode: stateVal.qcEditMode,
                ),
              if (stateVal.qcEditMode) ...[
                const SizedBox(height: 10),
                _SuspectDecisionTable(
                  result: result,
                  language: language,
                  onConfirm: _confirmSuspect,
                  onDelete: _deleteSuspect,
                ),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  ElevatedButton.icon(
                    onPressed: _shareCsv,
                    icon: const Icon(Icons.table_view_outlined),
                    label: Text(appText(language, 'Export CSV', 'Export CSV')),
                  ),
                  OutlinedButton.icon(
                    onPressed: _sharePng,
                    icon: const Icon(Icons.image_outlined),
                    label: Text(appText(language, 'Export PNG', 'Export PNG')),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCalibrationDecisionPanel({
    required AppLanguage language,
    required DashboardState stateVal,
    required GrainAnalysisResult result,
    required bool suggestedReferenceAvailable,
  }) {
    final hasReferenceLine =
        stateVal.referenceStart != null && stateVal.referenceEnd != null;
    final reference = _calibrationReference(result);
    final canApplyCalibration = reference != null &&
        _parsePositiveNumber(_referenceMm.text) != null &&
        !stateVal.busy;

    Widget statusText(String title, String description, Color color) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            suggestedReferenceAvailable
                ? Icons.straighten_outlined
                : Icons.tune_outlined,
            size: 20,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    Widget referenceFields() {
      final pixelsField = TextField(
        controller: _referencePixels,
        enabled: false,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: appText(language, 'Vật mốc (px ảnh)', 'Marker size (px)'),
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      );
      final millimetersField = TextField(
        controller: _referenceMm,
        enabled: !stateVal.busy,
        onChanged: (val) {
          ref.read(dashboardStateProvider.notifier).setReferenceMmInput(val);
        },
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText:
              appText(language, 'Kích thước thật (mm)', 'Real size (mm)'),
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      );

      return LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 380) {
            return Column(
              children: [
                pixelsField,
                const SizedBox(height: 10),
                millimetersField,
              ],
            );
          }

          return Row(
            children: [
              Expanded(child: pixelsField),
              const SizedBox(width: 10),
              Expanded(child: millimetersField),
            ],
          );
        },
      );
    }

    if (stateVal.pixelOnlyConfirmed && !stateVal.manualCalibrationRequested) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAF7),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppTheme.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            statusText(
              appText(language, 'Đang dùng kích thước tương đối',
                  'Using relative size'),
              appText(
                language,
                'Kết quả đã sẵn sàng theo pixel. Nếu cần đơn vị mm, có thể vẽ đường tham chiếu và nhập kích thước thật mà không chạy lại nhận dạng.',
                'The result is ready in pixels. If millimeters are needed, draw a reference line and enter its real size without running detection again.',
              ),
              AppTheme.textSecondary,
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: stateVal.busy ? null : _requestManualCalibration,
              icon: const Icon(Icons.straighten_outlined),
              label: Text(appText(language, 'Đổi sang mm', 'Convert to mm')),
            ),
          ],
        ),
      );
    }

    final needsReferenceInput =
        suggestedReferenceAvailable || stateVal.manualCalibrationRequested;
    final title = suggestedReferenceAvailable
        ? appText(language, 'Đã phát hiện vật mốc', 'Reference marker detected')
        : appText(language, 'Chưa phát hiện vật mốc', 'No marker detected');
    final description = suggestedReferenceAvailable
        ? appText(
            language,
            'App đã đặt sẵn đường đo trên vật mốc. Nhập kích thước thật theo mm rồi áp dụng để đổi kết quả hiện tại sang đơn vị mm.',
            'A measurement line was placed on the marker. Enter its real size in mm to convert the current result to millimeters.',
          )
        : stateVal.manualCalibrationRequested
            ? appText(
                language,
                hasReferenceLine
                    ? 'Kiểm tra lại hai chốt trên ảnh, nhập kích thước thật của đường vừa vẽ rồi áp dụng mm.'
                    : 'Vẽ một đường trên vật có kích thước thật đã biết, sau đó nhập kích thước của đường đó theo mm.',
                hasReferenceLine
                    ? 'Check the two handles on the image, enter the real size of the line, then apply millimeters.'
                    : 'Draw a line over an object with known real size, then enter that line size in millimeters.',
              )
            : appText(
                language,
                'Kết quả pixel đã sẵn sàng. Nếu cần kích thước thật, hãy vẽ đường tham chiếu trên một vật có kích thước đã biết; nếu không, dùng kết quả pixel ngay.',
                'Pixel results are ready. For real-world size, draw a reference line over an object with known size; otherwise, use the pixel result now.',
              );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: suggestedReferenceAvailable
            ? const Color(0xFFEFF6FF)
            : const Color(0xFFF8FAF7),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: suggestedReferenceAvailable
              ? const Color(0xFFBFDBFE)
              : AppTheme.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          statusText(
            title,
            description,
            suggestedReferenceAvailable
                ? const Color(0xFF1D4ED8)
                : AppTheme.textPrimary,
          ),
          if (needsReferenceInput) ...[
            const SizedBox(height: 12),
            referenceFields(),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton.icon(
                  onPressed: canApplyCalibration
                      ? _applyCalibrationFromCurrentReference
                      : null,
                  icon: const Icon(Icons.check_circle_outline),
                  label: Text(appText(language, 'Áp dụng mm', 'Apply mm')),
                ),
                OutlinedButton.icon(
                  onPressed: stateVal.busy ? null : _confirmPixelOnly,
                  icon: const Icon(Icons.grid_4x4_outlined),
                  label: Text(appText(language, 'Dùng pixel', 'Use pixels')),
                ),
                if (hasReferenceLine)
                  TextButton.icon(
                    onPressed: stateVal.busy
                        ? null
                        : () {
                            ref
                                .read(dashboardStateProvider.notifier)
                                .clearReference();
                          },
                    icon: const Icon(Icons.clear),
                    label:
                        Text(appText(language, 'Xóa đường đo', 'Clear line')),
                  ),
              ],
            ),
          ] else ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton.icon(
                  onPressed: stateVal.busy ? null : _requestManualCalibration,
                  icon: const Icon(Icons.straighten_outlined),
                  label: Text(appText(language, 'Cần kết quả mm', 'Need mm')),
                ),
                OutlinedButton.icon(
                  onPressed: stateVal.busy ? null : _confirmPixelOnly,
                  icon: const Icon(Icons.grid_4x4_outlined),
                  label: Text(appText(language, 'Dùng pixel', 'Use pixels')),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _previewChip(
      {required String mode,
      required String label,
      required String previewMode}) {
    return ChoiceChip(
      label: Text(label),
      selected: previewMode == mode,
      onSelected: (_) =>
          ref.read(dashboardStateProvider.notifier).setPreviewMode(mode),
    );
  }

  Widget _qcEditChip(bool active) {
    final language = ref.watch(appLanguageProvider);
    return FilterChip(
      avatar: Icon(
        active ? Icons.check_circle_outline : Icons.edit_outlined,
        size: 18,
        color: active ? const Color(0xFF9A3412) : AppTheme.primary,
      ),
      label: Text(active
          ? appText(language, 'Xong chỉnh hạt', 'Finish editing')
          : appText(language, 'Chỉnh hạt nghi ngờ', 'Edit suspect grains')),
      selected: active,
      onSelected: (_) =>
          ref.read(dashboardStateProvider.notifier).setQcEditMode(!active),
      selectedColor: const Color(0xFFFFEDD5),
      checkmarkColor: const Color(0xFF9A3412),
      side: BorderSide(
        color: active ? const Color(0xFFF97316) : AppTheme.border,
        width: active ? 1.4 : 1,
      ),
      labelStyle: TextStyle(
        fontWeight: FontWeight.w700,
        color: active ? const Color(0xFF9A3412) : AppTheme.textPrimary,
      ),
    );
  }
}

class _QcEditablePreview extends StatelessWidget {
  final GrainAnalysisResult result;
  final Uint8List previewBytes;
  final bool editMode;

  const _QcEditablePreview({
    required this.result,
    required this.previewBytes,
    required this.editMode,
  });

  @override
  Widget build(BuildContext context) {
    final imageWidth = _asDouble(result.image['width']);
    final imageHeight = _asDouble(result.image['height']);
    if (imageWidth <= 0 || imageHeight <= 0) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.memory(previewBytes),
      );
    }

    final boxes = result.measurements
        .where((measurement) =>
            (_asDouble(measurement['length_px']) > 0 &&
                _asDouble(measurement['width_px']) > 0) ||
            (_asDouble(measurement['bbox_w']) > 0 &&
                _asDouble(measurement['bbox_h']) > 0))
        .toList();

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxWidth = constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : MediaQuery.sizeOf(context).width;
          final displayWidth = math.max(1.0, maxWidth);
          final displayHeight = displayWidth * imageHeight / imageWidth;
          final scaleX = displayWidth / imageWidth;
          final scaleY = displayHeight / imageHeight;

          return SizedBox(
            width: displayWidth,
            height: displayHeight,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.memory(
                  previewBytes,
                  fit: BoxFit.fill,
                  gaplessPlayback: true,
                ),
                for (final measurement in boxes)
                  _QcMeasurementBox(
                    measurement: measurement,
                    editMode: editMode,
                    scaleX: scaleX,
                    scaleY: scaleY,
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _QcMeasurementBox extends StatelessWidget {
  final Map<String, dynamic> measurement;
  final bool editMode;
  final double scaleX;
  final double scaleY;

  const _QcMeasurementBox({
    required this.measurement,
    required this.editMode,
    required this.scaleX,
    required this.scaleY,
  });

  @override
  Widget build(BuildContext context) {
    final id = _asInt(measurement['id']);
    if (!editMode || measurement['qc_outlier'] != true) {
      return const SizedBox.shrink();
    }

    final centerX = (_asDouble(measurement['centroid_x']) > 0
            ? _asDouble(measurement['centroid_x'])
            : _asDouble(measurement['bbox_x']) +
                _asDouble(measurement['bbox_w']) / 2) *
        scaleX;
    final centerY = (_asDouble(measurement['centroid_y']) > 0
            ? _asDouble(measurement['centroid_y'])
            : _asDouble(measurement['bbox_y']) +
                _asDouble(measurement['bbox_h']) / 2) *
        scaleY;
    return Positioned(
      left: centerX - 15,
      top: centerY - 15,
      width: 30,
      height: 30,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFFDC2626),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: const [
            BoxShadow(
              color: Color(0x55000000),
              blurRadius: 4,
              offset: Offset(0, 1),
            ),
          ],
        ),
        child: Center(
          child: Text(
            '#$id',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}

class _SuspectDecisionTable extends StatelessWidget {
  final GrainAnalysisResult result;
  final AppLanguage language;
  final Future<void> Function(int id) onConfirm;
  final Future<void> Function(int id) onDelete;

  const _SuspectDecisionTable({
    required this.result,
    required this.language,
    required this.onConfirm,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final suspects = [
      for (final measurement in result.measurements)
        if (measurement['qc_outlier'] == true) measurement,
    ];

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppTheme.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC),
              border: Border(bottom: BorderSide(color: AppTheme.border)),
            ),
            child: Row(
              children: [
                const Expanded(
                  flex: 2,
                  child:
                      Text('ID', style: TextStyle(fontWeight: FontWeight.w800)),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    appText(language, 'Kích thước', 'Size'),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                SizedBox(
                  width: 92,
                  child: Text(
                    appText(language, 'Quyết định', 'Decision'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          ),
          if (suspects.isEmpty)
            Padding(
              padding: const EdgeInsets.all(10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  appText(language, 'Không còn hạt nghi ngờ cần xử lý.',
                      'No suspect grains need review.'),
                  style: const TextStyle(color: AppTheme.textSecondary),
                ),
              ),
            )
          else
            for (final measurement in suspects)
              _SuspectDecisionRow(
                measurement: measurement,
                language: language,
                onConfirm: onConfirm,
                onDelete: onDelete,
              ),
        ],
      ),
    );
  }
}

class _SuspectDecisionRow extends StatelessWidget {
  final Map<String, dynamic> measurement;
  final AppLanguage language;
  final Future<void> Function(int id) onConfirm;
  final Future<void> Function(int id) onDelete;

  const _SuspectDecisionRow({
    required this.measurement,
    required this.language,
    required this.onConfirm,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final id = _asInt(measurement['id']);
    final lengthMm = _asDouble(measurement['length_mm']);
    final widthMm = _asDouble(measurement['width_mm']);
    final lengthPx = _asDouble(measurement['length_px']);
    final widthPx = _asDouble(measurement['width_px']);
    final sizeText = lengthMm > 0 && widthMm > 0
        ? '${lengthMm.toStringAsFixed(2)} x ${widthMm.toStringAsFixed(2)} mm'
        : '${lengthPx.toStringAsFixed(1)} x ${widthPx.toStringAsFixed(1)} px';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppTheme.border)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text('#$id',
                style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
          Expanded(
            flex: 3,
            child: Text(
              sizeText,
              style: const TextStyle(color: AppTheme.textSecondary),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SizedBox(
            width: 92,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  tooltip: appText(language, 'Xác nhận đây là hạt thật',
                      'Confirm this is a real grain'),
                  icon:
                      const Icon(Icons.check_circle, color: Color(0xFF16A34A)),
                  onPressed: () => onConfirm(id),
                ),
                IconButton(
                  tooltip: appText(language, 'Xóa nhận dạng sai khỏi kết quả',
                      'Remove wrong detection from result'),
                  icon: const Icon(Icons.cancel, color: Color(0xFFDC2626)),
                  onPressed: () => onDelete(id),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReferenceImageSelector extends ConsumerStatefulWidget {
  final Uint8List? bytes;
  final Size? imageSize;
  final Offset? start;
  final Offset? end;
  final bool enabled;
  final bool showReferenceTools;
  final bool referenceDetected;
  final VoidCallback? onPickImage;
  final void Function(Offset start, Offset end) onChanged;

  const _ReferenceImageSelector({
    required this.bytes,
    required this.imageSize,
    required this.start,
    required this.end,
    required this.enabled,
    required this.showReferenceTools,
    required this.referenceDetected,
    required this.onPickImage,
    required this.onChanged,
  });

  @override
  ConsumerState<_ReferenceImageSelector> createState() =>
      _ReferenceImageSelectorState();
}

class _ReferenceImageSelectorState
    extends ConsumerState<_ReferenceImageSelector> {
  static const _handleHitRadius = 52.0;

  String? _dragTarget;
  String _selectedHandle = 'end';
  Offset? _fingerPosition;
  Offset? _activeHandlePosition;
  Offset? _activeImagePoint;
  ui.Image? _previewImage;

  @override
  void initState() {
    super.initState();
    _decodePreviewImage();
  }

  @override
  void didUpdateWidget(covariant _ReferenceImageSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.bytes, widget.bytes)) {
      _decodePreviewImage();
    }
  }

  Future<void> _decodePreviewImage() async {
    final bytes = widget.bytes;
    if (bytes == null) {
      final previous = _previewImage;
      if (mounted) setState(() => _previewImage = null);
      previous?.dispose();
      return;
    }
    final sourceSize = widget.imageSize;
    int? targetWidth;
    int? targetHeight;
    if (sourceSize != null) {
      final longestSide = math.max(sourceSize.width, sourceSize.height);
      if (longestSide > _BackendAnalysisCardState._previewCacheWidth) {
        final scale =
            _BackendAnalysisCardState._previewCacheWidth / longestSide;
        targetWidth = math.max(1, (sourceSize.width * scale).round());
        targetHeight = math.max(1, (sourceSize.height * scale).round());
      }
    } else {
      targetWidth = _BackendAnalysisCardState._previewCacheWidth;
    }
    final codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: targetWidth,
      targetHeight: targetHeight,
      allowUpscaling: false,
    );
    final frame = await codec.getNextFrame();
    codec.dispose();
    if (!mounted || !identical(widget.bytes, bytes)) {
      frame.image.dispose();
      return;
    }
    final previous = _previewImage;
    setState(() => _previewImage = frame.image);
    previous?.dispose();
  }

  @override
  void dispose() {
    _previewImage?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final language = ref.watch(appLanguageProvider);
    final sourceSize = widget.imageSize;
    final hasLine = widget.start != null && widget.end != null;

    void nudgeSelected(Offset delta) {
      if (!widget.enabled || sourceSize == null || !hasLine) return;
      Offset clamp(Offset point) => Offset(
            point.dx.clamp(0, sourceSize.width - 1).toDouble(),
            point.dy.clamp(0, sourceSize.height - 1).toDouble(),
          );
      if (_selectedHandle == 'start') {
        final next = clamp(widget.start! + delta);
        setState(() {
          _fingerPosition = null;
          _activeHandlePosition = null;
          _activeImagePoint = next;
        });
        widget.onChanged(next, widget.end!);
      } else {
        final next = clamp(widget.end! + delta);
        setState(() {
          _fingerPosition = null;
          _activeHandlePosition = null;
          _activeImagePoint = next;
        });
        widget.onChanged(widget.start!, next);
      }
    }

    void selectHandle(String handle) {
      setState(() {
        _selectedHandle = handle;
        _fingerPosition = null;
        _activeHandlePosition = null;
        _activeImagePoint = handle == 'start' ? widget.start : widget.end;
      });
    }

    void showGuideModal() {
      showDialog(
        context: context,
        barrierDismissible: true,
        builder: (context) => const _CalibrationGuideDialog(),
      );
    }

    Widget buildFixedMagnifierBox() {
      final isMagnifierActive = _activeImagePoint != null &&
          sourceSize != null &&
          _previewImage != null;

      return Container(
        width: 90,
        height: 90,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isMagnifierActive ? AppTheme.primary : AppTheme.border,
            width: isMagnifierActive ? 1.5 : 1,
          ),
          boxShadow: isMagnifierActive
              ? [
                  BoxShadow(
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                    color: Colors.black.withValues(alpha: 0.08),
                  )
                ]
              : null,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(7),
          child: isMagnifierActive
              ? _ReferenceMagnifier(
                  sourceImage: _previewImage!,
                  imageSize: sourceSize,
                  start: widget.start,
                  end: widget.end,
                  selectedHandle: _selectedHandle,
                  targetImagePoint: _activeImagePoint!,
                )
              : Center(
                  child: Icon(
                    Icons.zoom_in,
                    size: 28,
                    color: AppTheme.textSecondary.withValues(alpha: 0.55),
                  ),
                ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        widget.showReferenceTools
                            ? appText(
                                language,
                                'Hiệu chỉnh kích thước',
                                'Size calibration',
                              )
                            : appText(language, 'Ảnh đầu vào', 'Input image'),
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      if (widget.showReferenceTools) ...[
                        const SizedBox(width: 4),
                        IconButton(
                          icon: const Icon(
                            Icons.help_outline,
                            color: AppTheme.primary,
                            size: 20,
                          ),
                          onPressed: showGuideModal,
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          tooltip:
                              appText(language, 'Xem hướng dẫn', 'View guide'),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    widget.showReferenceTools
                        ? (hasLine
                            ? appText(
                                language,
                                'Kéo chốt A hoặc chốt B để khớp chính xác hai mép vật mốc.',
                                'Drag handle A or B to match the two marker edges precisely.',
                              )
                            : widget.referenceDetected
                                ? appText(
                                    language,
                                    'App đã gợi ý vị trí vật mốc. Nếu đường chưa hiện đúng, chạm vào ảnh để đặt lại đường đo.',
                                    'A marker was suggested. If the line is not placed correctly, tap the image to set it again.',
                                  )
                                : appText(
                                    language,
                                    'Nhấn vào vùng bất kỳ trên ảnh để khởi tạo đoạn thẳng tham chiếu kích thước.',
                                    'Tap anywhere on the image to initialize the size reference line.',
                                  ))
                        : appText(
                            language,
                            'Chọn hoặc chụp ảnh rồi bấm nhận dạng. Kết quả pixel sẽ có trước, phần mm có thể bổ sung sau.',
                            'Choose or capture an image, then run detection. Pixel results appear first, and millimeters can be added later.',
                          ),
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            if (widget.showReferenceTools) ...[
              const SizedBox(width: 12),
              buildFixedMagnifierBox(),
            ],
          ],
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, outerConstraints) {
            final availableWidth = outerConstraints.maxWidth.isFinite
                ? outerConstraints.maxWidth
                : MediaQuery.sizeOf(context).width;
            final previewHeight = availableWidth < 340
                ? 220.0
                : (availableWidth > 620 ? 360.0 : 280.0);

            return ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                height: previewHeight,
                width: double.infinity,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final canvasSize =
                        Size(constraints.maxWidth, previewHeight);
                    final fittedRect = sourceSize == null
                        ? Offset.zero & canvasSize
                        : _containedRect(canvasSize, sourceSize);

                    Offset displayPoint(Offset imagePoint) => Offset(
                          fittedRect.left +
                              imagePoint.dx /
                                  sourceSize!.width *
                                  fittedRect.width,
                          fittedRect.top +
                              imagePoint.dy /
                                  sourceSize.height *
                                  fittedRect.height,
                        );

                    Offset? imagePoint(Offset localPoint) {
                      if (sourceSize == null ||
                          !fittedRect.contains(localPoint)) {
                        return null;
                      }
                      return Offset(
                        (localPoint.dx - fittedRect.left) /
                            fittedRect.width *
                            sourceSize.width,
                        (localPoint.dy - fittedRect.top) /
                            fittedRect.height *
                            sourceSize.height,
                      );
                    }

                    Offset? dragImagePoint(Offset fingerPoint) {
                      final target = Offset(
                        fingerPoint.dx
                            .clamp(fittedRect.left, fittedRect.right)
                            .toDouble(),
                        fingerPoint.dy
                            .clamp(fittedRect.top, fittedRect.bottom)
                            .toDouble(),
                      );
                      final point = imagePoint(target);
                      if (point == null) return null;
                      setState(() {
                        _fingerPosition = fingerPoint;
                        _activeHandlePosition = target;
                        _activeImagePoint = point;
                      });
                      return point;
                    }

                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: widget.bytes == null ? widget.onPickImage : null,
                      onTapUp: widget.enabled && sourceSize != null
                          ? (details) {
                              if (widget.start != null && widget.end != null) {
                                final distStart = (details.localPosition -
                                        displayPoint(widget.start!))
                                    .distance;
                                final distEnd = (details.localPosition -
                                        displayPoint(widget.end!))
                                    .distance;
                                if (math.min(distStart, distEnd) <=
                                    _handleHitRadius) {
                                  selectHandle(
                                      distStart <= distEnd ? 'start' : 'end');
                                  return;
                                }
                              }
                              final point = imagePoint(details.localPosition);
                              if (point == null) return;

                              final halfLength =
                                  math.min(56.0, fittedRect.width * 0.2);
                              final left = Offset(
                                (details.localPosition.dx - halfLength)
                                    .clamp(fittedRect.left, fittedRect.right)
                                    .toDouble(),
                                details.localPosition.dy,
                              );
                              final right = Offset(
                                (details.localPosition.dx + halfLength)
                                    .clamp(fittedRect.left, fittedRect.right)
                                    .toDouble(),
                                details.localPosition.dy,
                              );
                              final start = imagePoint(left);
                              final end = imagePoint(right);
                              if (start != null && end != null) {
                                setState(() => _selectedHandle = 'end');
                                widget.onChanged(start, end);
                              }
                            }
                          : null,
                      onPanStart: widget.enabled
                          ? (details) {
                              final local = details.localPosition;
                              if (widget.start != null && widget.end != null) {
                                final startCanvas = displayPoint(widget.start!);
                                final endCanvas = displayPoint(widget.end!);

                                final distStart =
                                    (local - startCanvas).distance;
                                final distEnd = (local - endCanvas).distance;

                                if (distStart <= _handleHitRadius &&
                                    distStart < distEnd) {
                                  setState(() => _selectedHandle = 'start');
                                  _dragTarget = _selectedHandle;
                                } else if (distEnd <= _handleHitRadius) {
                                  setState(() => _selectedHandle = 'end');
                                  _dragTarget = _selectedHandle;
                                } else {
                                  _dragTarget = null;
                                }
                              } else {
                                final point = imagePoint(local);
                                if (point == null) return;
                                _dragTarget = 'new';
                                setState(() => _selectedHandle = 'end');
                                widget.onChanged(point, point);
                              }
                            }
                          : null,
                      onPanUpdate: widget.enabled
                          ? (details) {
                              final point =
                                  _dragTarget == 'start' || _dragTarget == 'end'
                                      ? dragImagePoint(details.localPosition)
                                      : imagePoint(details.localPosition);
                              if (point == null) return;

                              if (_dragTarget == 'start') {
                                if (widget.end != null) {
                                  widget.onChanged(point, widget.end!);
                                }
                              } else if (_dragTarget == 'end') {
                                if (widget.start != null) {
                                  widget.onChanged(widget.start!, point);
                                }
                              } else if (_dragTarget == 'new') {
                                if (widget.start != null) {
                                  widget.onChanged(widget.start!, point);
                                }
                              }
                            }
                          : null,
                      onPanEnd: widget.enabled
                          ? (_) => setState(() {
                                _dragTarget = null;
                                _fingerPosition = null;
                                _activeHandlePosition = null;
                                _activeImagePoint = null;
                              })
                          : null,
                      onPanCancel: widget.enabled
                          ? () => setState(() {
                                _dragTarget = null;
                                _fingerPosition = null;
                                _activeHandlePosition = null;
                                _activeImagePoint = null;
                              })
                          : null,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          ColoredBox(
                            color: const Color(0xFFF8FAF7),
                            child: widget.bytes == null
                                ? const _ImagePlaceholder()
                                : Image.memory(widget.bytes!,
                                    fit: BoxFit.contain,
                                    cacheWidth: _BackendAnalysisCardState
                                        ._previewCacheWidth),
                          ),
                          CustomPaint(
                            painter: _ReferenceLinePainter(
                              fittedRect: fittedRect,
                              imageSize: sourceSize,
                              start: widget.start,
                              end: widget.end,
                              selectedHandle: _selectedHandle,
                              fingerPosition: _fingerPosition,
                              activeHandlePosition: _activeHandlePosition,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            );
          },
        ),
        if (hasLine) ...[
          const SizedBox(height: 8),
          _ReferenceHandleControls(
            enabled: widget.enabled,
            selectedHandle: _selectedHandle,
            onSelectStart: () => selectHandle('start'),
            onSelectEnd: () => selectHandle('end'),
            onNudgeLeft: () => nudgeSelected(const Offset(-1, 0)),
            onNudgeUp: () => nudgeSelected(const Offset(0, -1)),
            onNudgeDown: () => nudgeSelected(const Offset(0, 1)),
            onNudgeRight: () => nudgeSelected(const Offset(1, 0)),
          ),
        ],
      ],
    );
  }
}

class _ReferenceHandleControls extends ConsumerWidget {
  final bool enabled;
  final String selectedHandle;
  final VoidCallback onSelectStart;
  final VoidCallback onSelectEnd;
  final VoidCallback onNudgeLeft;
  final VoidCallback onNudgeUp;
  final VoidCallback onNudgeDown;
  final VoidCallback onNudgeRight;

  const _ReferenceHandleControls({
    required this.enabled,
    required this.selectedHandle,
    required this.onSelectStart,
    required this.onSelectEnd,
    required this.onNudgeLeft,
    required this.onNudgeUp,
    required this.onNudgeDown,
    required this.onNudgeRight,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final language = ref.watch(appLanguageProvider);
    final chips = [
      ChoiceChip(
        label: Text(appText(language, 'Chốt A', 'Handle A')),
        selected: selectedHandle == 'start',
        onSelected: enabled ? (_) => onSelectStart() : null,
      ),
      ChoiceChip(
        label: Text(appText(language, 'Chốt B', 'Handle B')),
        selected: selectedHandle == 'end',
        onSelected: enabled ? (_) => onSelectEnd() : null,
      ),
    ];
    final nudges = [
      _NudgeButton(
        icon: Icons.arrow_back,
        onPressed: enabled ? onNudgeLeft : null,
      ),
      _NudgeButton(
        icon: Icons.arrow_upward,
        onPressed: enabled ? onNudgeUp : null,
      ),
      _NudgeButton(
        icon: Icons.arrow_downward,
        onPressed: enabled ? onNudgeDown : null,
      ),
      _NudgeButton(
        icon: Icons.arrow_forward,
        onPressed: enabled ? onNudgeRight : null,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 420;
        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(spacing: 6, runSpacing: 6, children: chips),
              const SizedBox(height: 4),
              Wrap(spacing: 6, runSpacing: 6, children: nudges),
            ],
          );
        }

        return Row(
          children: [
            ...chips.expand((chip) => [chip, const SizedBox(width: 6)]),
            const Spacer(),
            ...nudges,
          ],
        );
      },
    );
  }
}

Rect _containedRect(Size target, Size source) {
  final scale =
      math.min(target.width / source.width, target.height / source.height);
  final fitted = Size(source.width * scale, source.height * scale);
  return Rect.fromLTWH(
    (target.width - fitted.width) / 2,
    (target.height - fitted.height) / 2,
    fitted.width,
    fitted.height,
  );
}

class _NudgeButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;

  const _NudgeButton({required this.icon, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 38,
      height: 38,
      child: IconButton(
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        iconSize: 19,
        onPressed: onPressed,
        icon: Icon(icon),
      ),
    );
  }
}

class _ReferenceMagnifier extends StatelessWidget {
  final ui.Image sourceImage;
  final Size imageSize;
  final Offset? start;
  final Offset? end;
  final String selectedHandle;
  final Offset targetImagePoint;

  const _ReferenceMagnifier({
    required this.sourceImage,
    required this.imageSize,
    required this.start,
    required this.end,
    required this.selectedHandle,
    required this.targetImagePoint,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        CustomPaint(
          size: const Size(90, 90),
          painter: _ReferenceMagnifierPainter(
            sourceImage: sourceImage,
            imageSize: imageSize,
            start: start,
            end: end,
            target: targetImagePoint,
          ),
        ),
        const Center(child: _MagnifierCrosshair()),
        Positioned(
          top: 4,
          left: 4,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AppTheme.primary,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              child: Text(
                selectedHandle == 'start' ? 'A' : 'B',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ReferenceMagnifierPainter extends CustomPainter {
  static const _windowPixels = 72.0;

  final ui.Image sourceImage;
  final Size imageSize;
  final Offset? start;
  final Offset? end;
  final Offset target;

  const _ReferenceMagnifierPainter({
    required this.sourceImage,
    required this.imageSize,
    required this.start,
    required this.end,
    required this.target,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cropSide = math.min(
      _windowPixels,
      math.min(imageSize.width, imageSize.height),
    );
    final maxLeft = math.max(0.0, imageSize.width - cropSide);
    final maxTop = math.max(0.0, imageSize.height - cropSide);
    final cropLeft = (target.dx - cropSide / 2).clamp(0.0, maxLeft).toDouble();
    final cropTop = (target.dy - cropSide / 2).clamp(0.0, maxTop).toDouble();
    final originalCropRect =
        Rect.fromLTWH(cropLeft, cropTop, cropSide, cropSide);
    final decodedScaleX = sourceImage.width / imageSize.width;
    final decodedScaleY = sourceImage.height / imageSize.height;
    final sourceRect = Rect.fromLTWH(
      originalCropRect.left * decodedScaleX,
      originalCropRect.top * decodedScaleY,
      originalCropRect.width * decodedScaleX,
      originalCropRect.height * decodedScaleY,
    );
    final destination = Offset.zero & size;
    canvas.drawImageRect(sourceImage, sourceRect, destination, Paint());

    Offset magnifiedPoint(Offset point) => Offset(
          (point.dx - originalCropRect.left) /
              originalCropRect.width *
              size.width,
          (point.dy - originalCropRect.top) /
              originalCropRect.height *
              size.height,
        );
    if (start != null && end != null) {
      final linePaint = Paint()
        ..color = const Color(0xFF2563EB)
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(magnifiedPoint(start!), magnifiedPoint(end!), linePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _ReferenceMagnifierPainter oldDelegate) =>
      sourceImage != oldDelegate.sourceImage ||
      imageSize != oldDelegate.imageSize ||
      start != oldDelegate.start ||
      end != oldDelegate.end ||
      target != oldDelegate.target;
}

class _MagnifierCrosshair extends StatelessWidget {
  const _MagnifierCrosshair();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(30, 30),
      painter: _MagnifierCrosshairPainter(),
    );
  }
}

class _MagnifierCrosshairPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final outer = Paint()
      ..color = Colors.white
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    final inner = Paint()
      ..color = const Color(0xFFDC2626)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    for (final paint in [outer, inner]) {
      canvas.drawCircle(center, 6, paint);
      canvas.drawLine(center.translate(-14, 0), center.translate(-8, 0), paint);
      canvas.drawLine(center.translate(8, 0), center.translate(14, 0), paint);
      canvas.drawLine(center.translate(0, -14), center.translate(0, -8), paint);
      canvas.drawLine(center.translate(0, 8), center.translate(0, 14), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ReferenceLinePainter extends CustomPainter {
  final Rect fittedRect;
  final Size? imageSize;
  final Offset? start;
  final Offset? end;
  final String selectedHandle;
  final Offset? fingerPosition;
  final Offset? activeHandlePosition;

  const _ReferenceLinePainter({
    required this.fittedRect,
    required this.imageSize,
    required this.start,
    required this.end,
    required this.selectedHandle,
    required this.fingerPosition,
    required this.activeHandlePosition,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final sourceSize = imageSize;
    if (sourceSize == null || start == null || end == null) return;
    Offset displayPoint(Offset point) => Offset(
          fittedRect.left + point.dx / sourceSize.width * fittedRect.width,
          fittedRect.top + point.dy / sourceSize.height * fittedRect.height,
        );
    final a = displayPoint(start!);
    final b = displayPoint(end!);

    final paintLine = Paint()
      ..color = const Color(0xFF2563EB)
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round;

    final paintHandleInner = Paint()
      ..color = const Color(0xFF2563EB)
      ..style = PaintingStyle.fill;

    final paintHandleOuter = Paint()
      ..color = const Color(0x242563EB)
      ..style = PaintingStyle.fill;

    final paintBorder = Paint()
      ..color = Colors.white
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    final paintSelected = Paint()
      ..color = const Color(0xFF2563EB)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    final paintLeader = Paint()
      ..color = const Color(0x992563EB)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    canvas.drawLine(a, b, paintLine);
    final selectedPoint = selectedHandle == 'start' ? a : b;
    for (final point in [a, b]) {
      if (point == selectedPoint) {
        canvas.drawCircle(point, 20, paintHandleOuter);
      }
      canvas.drawCircle(point, 9, paintHandleInner);
      canvas.drawCircle(point, 9, paintBorder);
    }
    canvas.drawCircle(selectedPoint, 22, paintSelected);

    final finger = fingerPosition;
    final target = activeHandlePosition;
    if (finger != null && target != null) {
      canvas.drawCircle(target, 22, paintSelected);
      canvas.drawLine(
          target.translate(-16, 0), target.translate(16, 0), paintLeader);
      canvas.drawLine(
          target.translate(0, -16), target.translate(0, 16), paintLeader);
    }
  }

  @override
  bool shouldRepaint(covariant _ReferenceLinePainter oldDelegate) =>
      fittedRect != oldDelegate.fittedRect ||
      imageSize != oldDelegate.imageSize ||
      start != oldDelegate.start ||
      end != oldDelegate.end ||
      selectedHandle != oldDelegate.selectedHandle ||
      fingerPosition != oldDelegate.fingerPosition ||
      activeHandlePosition != oldDelegate.activeHandlePosition;
}

class _ImagePlaceholder extends ConsumerWidget {
  const _ImagePlaceholder();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final language = ref.watch(appLanguageProvider);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.add_photo_alternate_outlined,
            size: 42,
            color: AppTheme.textSecondary.withValues(alpha: 0.45),
          ),
          const SizedBox(height: 10),
          Text(
            appText(language, 'Chưa có ảnh', 'No image'),
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            appText(language, 'Chọn ảnh hoặc chụp ảnh để bắt đầu',
                'Choose or capture an image to start'),
            style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _QcFactCard extends StatelessWidget {
  final String label;
  final String value;

  const _QcFactCard({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 74),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFF2C078)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

Future<File> _writeTempFile(String name, List<int> bytes) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$name');
  return file.writeAsBytes(bytes, flush: true);
}

String _safeStem(String name) {
  final withoutExt = name.replaceFirst(RegExp(r'\.[^.]+$'), '');
  return withoutExt.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');
}

String _friendlyError(Object error) {
  if (error is DioException) {
    final message = error.response?.data is Map
        ? (error.response?.data['message']?.toString())
        : null;
    if (message != null && message.isNotEmpty) return message;
    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.connectionError) {
      return 'Không xử lý được ảnh vì kết nối không ổn định hoặc hệ thống phản hồi quá lâu. Kiểm tra Wi-Fi rồi thử lại.';
    }
  }
  if (error is TimeoutException) {
    return 'Thiết bị xử lý quá lâu nên đã dừng tác vụ. Hãy thử chụp gần hơn, giảm số hạt trong ảnh hoặc đóng các ứng dụng nền rồi xử lý lại.';
  }
  if (error is OutOfMemoryError ||
      error.toString().toLowerCase().contains('memory')) {
    return 'Thiết bị không đủ bộ nhớ để xử lý ảnh này. Hãy thử chụp ảnh gần hơn, giảm độ phân giải ảnh hoặc đóng các ứng dụng nền rồi thử lại.';
  }
  final message = error.toString().replaceFirst('Exception: ', '').trim();
  if (message.isNotEmpty && message != 'null') {
    final firstLine = message.split('\n').first;
    return 'Xử lý trên thiết bị thất bại: $firstLine';
  }
  return 'Xử lý trên thiết bị thất bại. Vui lòng thử lại với ảnh khác.';
}

double _asDouble(dynamic value) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

int _asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

class _GuideSlide extends StatelessWidget {
  final String title;
  final String description;
  final Widget diagram;

  const _GuideSlide({
    required this.title,
    required this.description,
    required this.diagram,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: AppTheme.primary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: const TextStyle(
              fontSize: 13,
              color: AppTheme.textSecondary,
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          Expanded(
            child: Center(
              child: diagram,
            ),
          ),
        ],
      ),
    );
  }
}

class _GuideImage extends StatelessWidget {
  final String assetPath;

  const _GuideImage(this.assetPath);

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAF7),
          border: Border.all(color: AppTheme.border),
        ),
        child: Image.asset(
          assetPath,
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}

class _CalibrationGuideDialog extends ConsumerStatefulWidget {
  const _CalibrationGuideDialog();

  @override
  ConsumerState<_CalibrationGuideDialog> createState() =>
      _CalibrationGuideDialogState();
}

class _CalibrationGuideDialogState
    extends ConsumerState<_CalibrationGuideDialog> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final language = ref.watch(appLanguageProvider);
    final mediaSize = MediaQuery.sizeOf(context);
    final dialogWidth = math.min(360.0, math.max(280.0, mediaSize.width - 32));
    final dialogHeight =
        math.min(425.0, math.max(320.0, mediaSize.height - 48));
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      backgroundColor: Colors.white,
      child: Container(
        padding: const EdgeInsets.all(16),
        width: dialogWidth,
        height: dialogHeight,
        child: Column(
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.help_center_outlined,
                        color: AppTheme.primary, size: 20),
                    const SizedBox(width: 6),
                    Text(
                      appText(language, 'Hướng dẫn căn mốc',
                          'Reference marker guide'),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => Navigator.of(context).pop(),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const Divider(height: 20, color: AppTheme.border),
            // Slides
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: (page) => setState(() => _currentPage = page),
                children: [
                  _GuideSlide(
                    title: appText(language, '1. Upload ảnh hạt và vật mốc',
                        '1. Upload grain image and reference marker'),
                    description: appText(
                      language,
                      'Chọn hoặc chụp ảnh có cả hạt cần đo và vật mốc có kích thước thật đã biết.',
                      'Choose or capture an image containing both grains to measure and a reference marker with known real size.',
                    ),
                    diagram: const _GuideImage(
                        'assets/images/calibration_guide_1.webp'),
                  ),
                  _GuideSlide(
                    title: appText(language, '2. Tạo đoạn đo bằng 2 chốt',
                        '2. Create a measurement line with 2 handles'),
                    description: appText(
                      language,
                      'Chạm lên vật mốc để tạo đoạn thẳng gồm chốt A và chốt B.',
                      'Tap the reference marker to create a line with handle A and handle B.',
                    ),
                    diagram: const _GuideImage(
                        'assets/images/calibration_guide_2.webp'),
                  ),
                  _GuideSlide(
                    title: appText(language, '3. Kéo thả chốt đo vật mốc',
                        '3. Drag the reference marker handles'),
                    description: appText(
                      language,
                      'Kéo từng chốt tới đúng hai mép vật mốc; có thể dùng nút mũi tên để tinh chỉnh từng pixel.',
                      'Drag each handle to the two marker edges; use arrow buttons for pixel-level tuning.',
                    ),
                    diagram: const _GuideImage(
                        'assets/images/calibration_guide_3.webp'),
                  ),
                  _GuideSlide(
                    title: appText(language, '4. Nhập kích thước thật',
                        '4. Enter the real size'),
                    description: appText(
                      language,
                      'Vẽ line để lấy kích thước px tự động, rồi nhập kích thước thật của vật mốc vào ô Kích thước thật (mm); để trống thì kết quả giữ đơn vị px.',
                      'Draw the line to measure pixels automatically, then enter the marker real size in Real size (mm); leave it blank to keep pixel units.',
                    ),
                    diagram: const _GuideImage(
                        'assets/images/calibration_guide_4.webp'),
                  ),
                ],
              ),
            ),
            const Divider(height: 20, color: AppTheme.border),
            // Footer Control
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Indicators
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(4, (index) {
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: _currentPage == index ? 14 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: _currentPage == index
                            ? AppTheme.primary
                            : AppTheme.border,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    );
                  }),
                ),
                // Buttons
                Row(
                  children: [
                    if (_currentPage > 0)
                      TextButton(
                        onPressed: () {
                          _pageController.previousPage(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                          );
                        },
                        child: Text(
                          appText(language, 'Quay lại', 'Back'),
                          style: const TextStyle(
                              color: AppTheme.textSecondary, fontSize: 13),
                        ),
                      ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        textStyle: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                      onPressed: () {
                        if (_currentPage < 3) {
                          _pageController.nextPage(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                          );
                        } else {
                          Navigator.of(context).pop();
                        }
                      },
                      child: Text(_currentPage == 3
                          ? appText(language, 'Bắt đầu', 'Start')
                          : appText(language, 'Tiếp theo', 'Next')),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
