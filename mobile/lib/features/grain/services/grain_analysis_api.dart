import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:image/image.dart' as img;

import '../../../core/constants/app_constants.dart';
import '../../../core/network/api_client.dart';
import 'local_grain_run_store.dart';
import 'offline_grain_analyzer.dart';

class GrainAnalysisApi {
  final ApiClient _client;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  final LocalGrainRunStore _localStore = LocalGrainRunStore();
  final OfflineGrainAnalyzer _offlineAnalyzer = OfflineGrainAnalyzer();

  GrainAnalysisApi({ApiClient? client}) : _client = client ?? ApiClient();

  Future<GrainAnalysisResult> analyzeImage({
    required Uint8List bytes,
    required String fileName,
    double? referencePixels,
    double? referenceMm,
    double? referenceX1,
    double? referenceY1,
    double? referenceX2,
    double? referenceY2,
    OfflineProgressCallback? onProgress,
  }) async {
    final localResult = GrainAnalysisResult.fromJson(
      (await _offlineAnalyzer.analyze(
        bytes,
        referencePixels: referencePixels,
        referenceMm: referenceMm,
        referenceX1: referenceX1,
        referenceY1: referenceY1,
        referenceX2: referenceX2,
        referenceY2: referenceY2,
        onProgress: onProgress,
      ))
          .asApiJson(fileName),
    );
    final guest = await isGuestMode();
    final ownerUserId = guest ? null : await _currentUserId();
    await _localStore.save({
      'pendingSync': true,
      'ownerUserId': ownerUserId,
      'clientRunId': localResult.run['id']?.toString() ?? '',
      'sourceFileName': fileName,
      'createdAt': DateTime.now().toIso8601String(),
      'result': localResult.toJson(),
    });

    if (!guest && ownerUserId != null) {
      unawaited(_syncPendingRunsInBackground());
    }
    return localResult;
  }

  Future<GrainRunDetail> getRun(String id) async {
    final guest = await isGuestMode();
    final localRuns = await _localStore.readVisible(
      isGuest: guest,
      userId: guest ? null : await _currentUserId(),
    );
    for (final localRun in localRuns) {
      final rawResult = localRun['result'];
      if (rawResult is! Map) continue;
      final result = GrainAnalysisResult.fromJson(
        Map<String, dynamic>.from(rawResult),
      );
      if (result.run['id']?.toString() == id) {
        return GrainRunDetail(run: result.run, result: result);
      }
    }
    final response = await _client.get('/grain/runs/$id');
    return GrainRunDetail.fromJson(
      Map<String, dynamic>.from(response.data['data'] as Map),
    );
  }

  Future<bool> isGuestMode() async =>
      await _storage.read(key: guestModeKey) == 'true';

  Future<void> syncPendingRuns() async {
    final userId = await _currentUserId();
    if (userId == null) return;
    final pending = await _localStore.claimAndReadPendingForSync(userId);
    if (pending.isEmpty) return;
    await _client.post('/grain/runs/import', data: {'items': pending});
    await _localStore.removePendingForSync(userId);
  }

  Future<void> persistEditedRun(GrainAnalysisResult result) async {
    final runId = result.run['id']?.toString() ?? '';
    if (runId.isEmpty) return;
    await _localStore.updateResult(runId, result.toJson());
  }

  Future<String?> _currentUserId() async {
    final raw = await _storage.read(key: userKey);
    if (raw == null || raw.isEmpty) return null;
    final user = jsonDecode(raw);
    if (user is! Map) return null;
    final value = user['_id']?.toString() ?? user['id']?.toString() ?? '';
    return value.isEmpty ? null : value;
  }

  Future<void> _syncPendingRunsInBackground() async {
    try {
      await syncPendingRuns();
    } catch (_) {
      // Connectivity service retries pending local runs later.
    }
  }
}

class GrainRunDetail {
  final Map<String, dynamic> run;
  final GrainAnalysisResult result;

  const GrainRunDetail({required this.run, required this.result});

  factory GrainRunDetail.fromJson(Map<String, dynamic> json) {
    return GrainRunDetail(
      run: Map<String, dynamic>.from(json['run'] as Map? ?? {}),
      result: GrainAnalysisResult.fromJson(
        Map<String, dynamic>.from(json['result'] as Map? ?? {}),
      ),
    );
  }
}

class GrainAnalysisResult {
  final Map<String, dynamic> run;
  final Map<String, dynamic> image;
  final Map<String, dynamic> summary;
  final Map<String, dynamic> segmentation;
  final Map<String, dynamic> calibration;
  final List<Map<String, dynamic>> measurements;
  final String csv;
  final Map<String, String> previews;

  const GrainAnalysisResult({
    required this.run,
    required this.image,
    required this.summary,
    required this.segmentation,
    required this.calibration,
    required this.measurements,
    required this.csv,
    required this.previews,
  });

  factory GrainAnalysisResult.fromJson(Map<String, dynamic> json) {
    final rawMeasurements = json['measurements'] as List<dynamic>? ?? const [];
    final maskPreview = json['mask_png_base64']?.toString() ?? '';
    final samMaskPreview = json['sam_mask_png_base64']?.toString() ?? '';
    return GrainAnalysisResult(
      run: Map<String, dynamic>.from(json['run'] as Map? ?? {}),
      image: Map<String, dynamic>.from(json['image'] as Map? ?? {}),
      summary: Map<String, dynamic>.from(json['summary'] as Map? ?? {}),
      segmentation:
          Map<String, dynamic>.from(json['segmentation'] as Map? ?? {}),
      calibration: Map<String, dynamic>.from(json['calibration'] as Map? ?? {}),
      measurements: rawMeasurements
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList(),
      csv: json['csv']?.toString() ?? '',
      previews: {
        'original': json['original_png_base64']?.toString() ?? '',
        'preprocessed': json['preprocessed_png_base64']?.toString() ?? '',
        'overlay': json['overlay_png_base64']?.toString() ?? '',
        'samMask': samMaskPreview == maskPreview ? '' : samMaskPreview,
        'labels': json['labels_png_base64']?.toString() ?? '',
        'mask': maskPreview,
        'labelMap': json['label_map_png_base64']?.toString() ?? '',
      },
    );
  }

  Map<String, dynamic> toJson() => {
        'run': run,
        'image': image,
        'summary': summary,
        'segmentation': segmentation,
        'calibration': calibration,
        'features': {},
        'measurements': measurements,
        'csv': csv,
        'original_png_base64': previews['original'] ?? '',
        'preprocessed_png_base64': previews['preprocessed'] ?? '',
        'overlay_png_base64': previews['overlay'] ?? '',
        'sam_mask_png_base64': previews['samMask'] ?? '',
        'labels_png_base64': previews['labels'] ?? '',
        'mask_png_base64': previews['mask'] ?? '',
        'label_map_png_base64': previews['labelMap'] ?? '',
      };

  int get count => _asInt(summary['count']);
  double get meanAreaPx => _asDouble(summary['mean_area_px']);
  double get meanLengthPx => _asDouble(summary['mean_length_px']);
  double get meanWidthPx => _asDouble(summary['mean_width_px']);
  double? get meanAreaMm2 => _nullableDouble(summary['mean_area_mm2']);
  double? get meanLengthMm => _nullableDouble(summary['mean_length_mm']);
  double? get meanWidthMm => _nullableDouble(summary['mean_width_mm']);
  bool get calibrated => calibration['enabled'] == true;
  double get rawStdLengthPx => _asDouble(summary['std_length_px']);
  double get rawStdWidthPx => _asDouble(summary['std_width_px']);
  double? get rawStdLengthMm =>
      calibrated ? _statDouble(summary['std_length_mm']) : null;
  double? get rawStdWidthMm =>
      calibrated ? _statDouble(summary['std_width_mm']) : null;
  bool get qcRobustUsedForReporting {
    final qc = summary['qc'];
    return qc is! Map || qc['robust_used_for_reporting'] != false;
  }

  dynamic _reportedStd(String rawKey, String robustKey) =>
      qcRobustUsedForReporting
          ? (summary[robustKey] ?? summary[rawKey])
          : summary[rawKey];

  double get qcStdAreaPx =>
      _asDouble(_reportedStd('std_area_px', 'robust_std_area_px'));
  double get qcStdLengthPx =>
      _asDouble(_reportedStd('std_length_px', 'robust_std_length_px'));
  double get qcStdWidthPx =>
      _asDouble(_reportedStd('std_width_px', 'robust_std_width_px'));
  double? get qcStdAreaMm2 => calibrated
      ? _statDouble(_reportedStd('std_area_mm2', 'robust_std_area_mm2'))
      : null;
  double? get qcStdLengthMm => calibrated
      ? _statDouble(_reportedStd('std_length_mm', 'robust_std_length_mm'))
      : null;
  double? get qcStdWidthMm => calibrated
      ? _statDouble(_reportedStd('std_width_mm', 'robust_std_width_mm'))
      : null;
  int get qcSuspectCount {
    final qc = summary['qc'];
    return qc is Map ? _asInt(qc['suspect_count']) : 0;
  }

  int get qcInlierCount {
    final qc = summary['qc'];
    return qc is Map ? _asInt(qc['inlier_count']) : count;
  }

  String get qcSuspectIdsLabel {
    final qc = summary['qc'];
    final rawIds = qc is Map ? qc['suspect_ids'] : null;
    if (rawIds is! List || rawIds.isEmpty) return '';
    final ids = rawIds.take(8).map((id) => '#${_asInt(id)}').join(', ');
    return rawIds.length > 8 ? '$ids, ...' : ids;
  }

  String previewBase64(String key) => previews[key] ?? '';

  String previewWithFallback(String key) {
    final selected = previewBase64(key);
    if (selected.isNotEmpty) return selected;
    if (key == 'samMask') {
      final mask = previewBase64('mask');
      if (mask.isNotEmpty) return mask;
    }
    if (key == 'mask') {
      final samMask = previewBase64('samMask');
      if (samMask.isNotEmpty) return samMask;
    }
    if (key != 'overlay') {
      final overlay = previewBase64('overlay');
      if (overlay.isNotEmpty) return overlay;
    }
    return '';
  }

  GrainAnalysisResult withAppliedCalibration({
    required double referencePixels,
    required double referenceMm,
    double? referenceX1,
    double? referenceY1,
    double? referenceX2,
    double? referenceY2,
    String referencePixelSpace = 'original',
    String source = 'manual_post_analysis',
  }) {
    final safeScale =
        _asDouble(image['scale']) > 0 ? _asDouble(image['scale']) : 1.0;
    final processedReferencePixels = referencePixelSpace == 'original'
        ? referencePixels * safeScale
        : referencePixels;
    if (referencePixels <= 0 ||
        referenceMm <= 0 ||
        processedReferencePixels <= 0) {
      return this;
    }
    final mmPerPixel = referenceMm / processedReferencePixels;
    final nextMeasurements = measurements.map((measurement) {
      final copy = Map<String, dynamic>.from(measurement);
      final areaPx = _asDouble(copy['area_px']);
      final lengthPx = _asDouble(copy['length_px']);
      final widthPx = _asDouble(copy['width_px']);
      copy['area_mm2'] = _round(areaPx * mmPerPixel * mmPerPixel, 6);
      copy['length_mm'] = _round(lengthPx * mmPerPixel, 6);
      copy['width_mm'] = _round(widthPx * mmPerPixel, 6);
      return copy;
    }).toList();
    final nextCalibration = {
      ...calibration,
      'enabled': true,
      'mm_per_pixel': _round(mmPerPixel, 10),
      'referencePixels': _round(referencePixels, 6),
      'processedReferencePixels': _round(processedReferencePixels, 6),
      'referenceMm': _round(referenceMm, 6),
      'referencePixelSpace': referencePixelSpace,
      'referenceX1': referenceX1 ?? calibration['referenceX1'] ?? -1,
      'referenceY1': referenceY1 ?? calibration['referenceY1'] ?? -1,
      'referenceX2': referenceX2 ?? calibration['referenceX2'] ?? -1,
      'referenceY2': referenceY2 ?? calibration['referenceY2'] ?? -1,
      'source': source,
      'post_analysis_applied': true,
    };

    return _copyWithMeasurements(nextMeasurements,
        calibration: nextCalibration);
  }

  GrainAnalysisResult withConfirmedGrain(int measurementId) {
    final nextMeasurements = measurements.map((measurement) {
      final copy = Map<String, dynamic>.from(measurement);
      if (_asInt(copy['id']) != measurementId) return copy;
      copy['qc_outlier'] = false;
      copy['qc_reason'] = '';
      copy['qc_manual_override'] = true;
      copy['qc_manual_decision'] = 'confirmed_grain';
      return copy;
    }).toList();

    return _copyWithMeasurements(nextMeasurements);
  }

  GrainAnalysisResult withDeletedMeasurement(int measurementId) {
    final nextMeasurements = [
      for (final measurement in measurements)
        if (_asInt(measurement['id']) != measurementId)
          Map<String, dynamic>.from(measurement),
    ];
    final deletedIds = {
      ...((segmentation['manual_deleted_ids'] as List?) ?? const [])
          .map(_asInt)
          .where((id) => id > 0),
      measurementId,
    }.toList()
      ..sort();
    final nextSegmentation = {
      ...segmentation,
      'segment_count': nextMeasurements.length,
      'marker_count': nextMeasurements.length,
      'manual_deleted_ids': deletedIds,
    };
    return _copyWithMeasurements(nextMeasurements,
        segmentation: nextSegmentation);
  }

  GrainAnalysisResult _copyWithMeasurements(
    List<Map<String, dynamic>> nextMeasurements, {
    Map<String, dynamic>? segmentation,
    Map<String, dynamic>? calibration,
  }) {
    return GrainAnalysisResult(
      run: run,
      image: image,
      summary: _recomputeSummary(summary, nextMeasurements),
      segmentation: segmentation ?? this.segmentation,
      calibration: calibration ?? this.calibration,
      measurements: nextMeasurements,
      csv: _measurementsCsv(nextMeasurements, csv),
      previews: _renderQcPreviews(previews, nextMeasurements),
    );
  }
}

int _bitmapTextWidth(dynamic font, String text) {
  var width = 0;
  for (final codeUnit in text.codeUnits) {
    final character = font.characters[codeUnit];
    width +=
        character == null ? (font.base as int) ~/ 2 : character.xAdvance as int;
  }
  return width;
}

void _drawReadablePreviewId(
  img.Image image,
  int id,
  int centerX,
  int centerY,
) {
  final text = '$id';
  final font =
      math.max(image.width, image.height) >= 720 ? img.arial48 : img.arial24;
  final textWidth = _bitmapTextWidth(font, text);
  final textHeight = font.lineHeight;
  final maxX = math.max(0, image.width - textWidth);
  final maxY = math.max(0, image.height - textHeight);
  final x = (centerX - textWidth ~/ 2).clamp(0, maxX).toInt();
  final y = (centerY - textHeight ~/ 2).clamp(0, maxY).toInt();
  const outlineOffsets = [
    [-2, -2],
    [0, -2],
    [2, -2],
    [-2, 0],
    [2, 0],
    [-2, 2],
    [0, 2],
    [2, 2],
  ];
  for (final offset in outlineOffsets) {
    img.drawString(
      image,
      text,
      font: font,
      x: x + offset[0],
      y: y + offset[1],
      color: img.ColorRgb8(0, 0, 0),
    );
  }
  img.drawString(
    image,
    text,
    font: font,
    x: x,
    y: y,
    color: img.ColorRgb8(255, 255, 255),
  );
}

Map<String, String> _renderQcPreviews(
  Map<String, String> previews,
  List<Map<String, dynamic>> measurements,
) {
  final labelMapBase64 = previews['labelMap'] ?? '';
  final baseBase64 = (previews['preprocessed']?.isNotEmpty == true)
      ? previews['preprocessed']!
      : (previews['original'] ?? '');
  if (labelMapBase64.isEmpty || baseBase64.isEmpty) return previews;
  final img.Image? labelMap;
  final img.Image? base;
  try {
    labelMap = img.decodePng(base64Decode(labelMapBase64));
    base = img.decodePng(base64Decode(baseBase64));
  } catch (_) {
    return previews;
  }
  final labelMapImage = labelMap;
  final baseImage = base;
  if (labelMapImage == null || baseImage == null) return previews;
  if (labelMapImage.width != baseImage.width ||
      labelMapImage.height != baseImage.height) {
    return previews;
  }

  final outlierIds = {
    for (final measurement in measurements)
      if (measurement['qc_outlier'] == true) _asInt(measurement['id']),
  }..remove(0);
  final activeIds = {
    for (final measurement in measurements) _asInt(measurement['id']),
  }..remove(0);
  final overlay = img.Image.from(baseImage);
  final mask = img.Image(
    width: baseImage.width,
    height: baseImage.height,
    numChannels: 4,
  );
  final labels = img.Image(
    width: baseImage.width,
    height: baseImage.height,
    numChannels: 3,
  );
  const labelPalette = [
    [45, 108, 191],
    [219, 87, 86],
    [73, 160, 120],
    [235, 174, 73],
    [132, 98, 174],
    [77, 176, 196],
    [201, 112, 165],
    [122, 126, 135],
  ];

  int labelAt(int x, int y) {
    final pixel = labelMapImage.getPixel(x, y);
    return pixel.r.toInt() | (pixel.g.toInt() << 8) | (pixel.b.toInt() << 16);
  }

  bool isEdge(int x, int y, int label) {
    if (x == 0 ||
        y == 0 ||
        x == labelMapImage.width - 1 ||
        y == labelMapImage.height - 1) {
      return true;
    }
    return labelAt(x - 1, y) != label ||
        labelAt(x + 1, y) != label ||
        labelAt(x, y - 1) != label ||
        labelAt(x, y + 1) != label;
  }

  for (var y = 0; y < labelMapImage.height; y++) {
    for (var x = 0; x < labelMapImage.width; x++) {
      final label = labelAt(x, y);
      if (label <= 0 || !activeIds.contains(label)) {
        mask.setPixelRgba(x, y, 0, 0, 0, 0);
        if (label > 0 && !activeIds.contains(label)) {
          labelMapImage.setPixelRgba(x, y, 0, 0, 0, 255);
        }
        continue;
      }
      final outlier = outlierIds.contains(label);
      final color = outlier ? const [220, 38, 38] : const [37, 99, 235];
      final labelColor = outlier
          ? const [220, 38, 38]
          : labelPalette[(label - 1) % labelPalette.length];
      labels.setPixelRgb(x, y, labelColor[0], labelColor[1], labelColor[2]);
      final edge = isEdge(x, y, label);
      final fillOpacity = edge ? 0.56 : 0.34;
      final source = overlay.getPixel(x, y);
      overlay.setPixelRgb(
        x,
        y,
        (source.r * (1 - fillOpacity) + color[0] * fillOpacity).round(),
        (source.g * (1 - fillOpacity) + color[1] * fillOpacity).round(),
        (source.b * (1 - fillOpacity) + color[2] * fillOpacity).round(),
      );

      if (edge) {
        final edgeColor = outlier ? const [185, 28, 28] : const [30, 64, 175];
        mask.setPixelRgba(
          x,
          y,
          edgeColor[0],
          edgeColor[1],
          edgeColor[2],
          255,
        );
      } else {
        final fillColor = outlier ? const [239, 68, 68] : const [59, 130, 246];
        mask.setPixelRgba(
          x,
          y,
          fillColor[0],
          fillColor[1],
          fillColor[2],
          outlier ? 170 : 145,
        );
      }
    }
  }
  for (final measurement in measurements) {
    final id = _asInt(measurement['id']);
    if (id <= 0 || !activeIds.contains(id)) continue;
    final centroidX = _asDouble(measurement['centroid_x']).round();
    final centroidY = _asDouble(measurement['centroid_y']).round();
    _drawReadablePreviewId(labels, id, centroidX, centroidY);
  }

  final maskBase64 = base64Encode(img.encodePng(mask));
  return {
    ...previews,
    'overlay': base64Encode(img.encodePng(overlay)),
    'mask': maskBase64,
    'samMask': '',
    'labels': base64Encode(img.encodePng(labels)),
    'labelMap': base64Encode(img.encodePng(labelMapImage)),
  };
}

Map<String, dynamic> _recomputeSummary(
  Map<String, dynamic> previousSummary,
  List<Map<String, dynamic>> measurements,
) {
  if (measurements.isEmpty) {
    return {
      ...previousSummary,
      'count': 0,
      'total_area_px': 0,
      'mean_area_px': 0,
      'mean_length_px': 0,
      'mean_width_px': 0,
      'mean_area_mm2': null,
      'mean_length_mm': null,
      'mean_width_mm': null,
      'std_area_px': 0,
      'std_length_px': 0,
      'std_width_px': 0,
      'std_area_mm2': null,
      'std_length_mm': null,
      'std_width_mm': null,
      'robust_mean_area_px': 0,
      'robust_mean_length_px': 0,
      'robust_mean_width_px': 0,
      'robust_mean_area_mm2': null,
      'robust_mean_length_mm': null,
      'robust_mean_width_mm': null,
      'robust_std_area_px': 0,
      'robust_std_length_px': 0,
      'robust_std_width_px': 0,
      'robust_std_area_mm2': null,
      'robust_std_length_mm': null,
      'robust_std_width_mm': null,
      'cv_length_pct': 0,
      'cv_width_pct': 0,
      'qc': {
        ...Map<String, dynamic>.from(previousSummary['qc'] as Map? ?? {}),
        'suspect_count': 0,
        'inlier_count': 0,
        'suspect_ids': [],
        'review_required': false,
        'suspect_ratio': 0,
        'robust_used_for_reporting': true,
        'manual_override': true,
        'status': 'ok',
      },
      'quality': _qualitySummary(const []),
    };
  }
  final inliers = [
    for (final measurement in measurements)
      if (measurement['qc_outlier'] != true) measurement,
  ];
  final robustMeasurements = inliers.isEmpty ? measurements : inliers;
  final suspectIds = [
    for (final measurement in measurements)
      if (measurement['qc_outlier'] == true) _asInt(measurement['id']),
  ]..sort();
  final suspectRatio = suspectIds.length / measurements.length;
  final robustUsedForReporting = suspectRatio <= 0.05;
  final calibrated = measurements.first['length_mm'] != null;

  List<double> values(List<Map<String, dynamic>> items, String key) =>
      items.map((item) => _asDouble(item[key])).toList();
  double mean(List<Map<String, dynamic>> items, String key) {
    final data = values(items, key);
    return _round(data.reduce((a, b) => a + b) / data.length, 6);
  }

  double std(List<Map<String, dynamic>> items, String key) {
    if (items.length <= 1) return 0;
    final data = values(items, key);
    final average = data.reduce((a, b) => a + b) / data.length;
    final squaredSum = data.fold<double>(
      0,
      (total, value) => total + math.pow(value - average, 2),
    );
    return _round(math.sqrt(squaredSum / (data.length - 1)), 6);
  }

  double cv(List<Map<String, dynamic>> items, String key) {
    final average = mean(items, key);
    return average > 0 ? _round(std(items, key) / average * 100, 3) : 0;
  }

  double? metricMm(
    double Function(List<Map<String, dynamic>>, String) statistic,
    List<Map<String, dynamic>> items,
    String key,
  ) =>
      calibrated ? statistic(items, key) : null;

  return {
    ...previousSummary,
    'count': measurements.length,
    'total_area_px': measurements.fold<int>(
      0,
      (total, item) => total + _asInt(item['area_px']),
    ),
    'mean_area_px': mean(measurements, 'area_px'),
    'mean_length_px': mean(measurements, 'length_px'),
    'mean_width_px': mean(measurements, 'width_px'),
    'mean_area_mm2': metricMm(mean, measurements, 'area_mm2'),
    'mean_length_mm': metricMm(mean, measurements, 'length_mm'),
    'mean_width_mm': metricMm(mean, measurements, 'width_mm'),
    'std_area_px': std(measurements, 'area_px'),
    'std_length_px': std(measurements, 'length_px'),
    'std_width_px': std(measurements, 'width_px'),
    'std_area_mm2': metricMm(std, measurements, 'area_mm2'),
    'std_length_mm': metricMm(std, measurements, 'length_mm'),
    'std_width_mm': metricMm(std, measurements, 'width_mm'),
    'robust_mean_area_px': mean(robustMeasurements, 'area_px'),
    'robust_mean_length_px': mean(robustMeasurements, 'length_px'),
    'robust_mean_width_px': mean(robustMeasurements, 'width_px'),
    'robust_mean_area_mm2': metricMm(mean, robustMeasurements, 'area_mm2'),
    'robust_mean_length_mm': metricMm(mean, robustMeasurements, 'length_mm'),
    'robust_mean_width_mm': metricMm(mean, robustMeasurements, 'width_mm'),
    'robust_std_area_px': std(robustMeasurements, 'area_px'),
    'robust_std_length_px': std(robustMeasurements, 'length_px'),
    'robust_std_width_px': std(robustMeasurements, 'width_px'),
    'robust_std_area_mm2': metricMm(std, robustMeasurements, 'area_mm2'),
    'robust_std_length_mm': metricMm(std, robustMeasurements, 'length_mm'),
    'robust_std_width_mm': metricMm(std, robustMeasurements, 'width_mm'),
    'cv_length_pct': cv(robustMeasurements, 'length_px'),
    'cv_width_pct': cv(robustMeasurements, 'width_px'),
    'qc': {
      ...Map<String, dynamic>.from(previousSummary['qc'] as Map? ?? {}),
      'suspect_count': suspectIds.length,
      'inlier_count': robustMeasurements.length,
      'suspect_ids': suspectIds,
      'review_required': suspectIds.isNotEmpty,
      'suspect_ratio': _round(suspectRatio, 6),
      'robust_used_for_reporting': robustUsedForReporting,
      'manual_override': true,
      'status': !robustUsedForReporting
          ? 'review_required'
          : (suspectIds.isNotEmpty ? 'suspects_flagged' : 'ok'),
    },
    'quality': _qualitySummary(measurements),
  };
}

Map<String, dynamic> _qualitySummary(List<Map<String, dynamic>> measurements) {
  final flagCounts = <String, int>{};
  const problemFlags = {
    'loose_mask',
    'touches_image_edge',
    'extreme_aspect',
    'partial_tile_mask',
  };
  var problemCount = 0;
  for (final measurement in measurements) {
    final flags = (measurement['quality_flags']?.toString() ?? '')
        .split(',')
        .map((flag) => flag.trim())
        .where((flag) => flag.isNotEmpty)
        .toSet();
    if (flags.any(problemFlags.contains)) {
      problemCount++;
    }
    for (final flag in flags) {
      flagCounts[flag] = (flagCounts[flag] ?? 0) + 1;
    }
  }
  final labelConfusionCount = flagCounts['model_label_ref_as_seed'] ?? 0;
  final count = measurements.length;
  return {
    'flag_counts': flagCounts,
    'problem_count': problemCount,
    'problem_ratio': count == 0 ? 0 : _round(problemCount / count, 6),
    'label_confusion_count': labelConfusionCount,
    'label_confusion_ratio':
        count == 0 ? 0 : _round(labelConfusionCount / count, 6),
    'review_required': problemCount > 0,
    'status': problemCount > 0 ? 'review_required' : 'ok',
  };
}

String _measurementsCsv(
  List<Map<String, dynamic>> measurements,
  String existingCsv,
) {
  final csvLines = existingCsv.split(RegExp(r'\r?\n'));
  final firstLine = csvLines.isEmpty ? '' : csvLines.first;
  final baseColumns = firstLine.isEmpty
      ? const [
          'id',
          'area_px',
          'length_px',
          'width_px',
          'area_mm2',
          'length_mm',
          'width_mm',
          'centroid_x',
          'centroid_y',
          'bbox_x',
          'bbox_y',
          'bbox_w',
          'bbox_h',
          'angle_deg',
          'solidity',
          'extent',
          'aspect_ratio',
          'measurement_method',
          'confidence',
          'class_id',
          'class_name',
          'detected_class_id',
          'detected_class_name',
          'quality_flags',
          'qc_outlier',
          'qc_reason',
        ]
      : firstLine.split(',');
  final columns = [
    ...baseColumns,
    if (!baseColumns.contains('measurement_method')) 'measurement_method',
    if (!baseColumns.contains('qc_manual_override')) 'qc_manual_override',
  ];
  final rows = [
    columns.join(','),
    for (final measurement in measurements)
      columns.map((column) => _csvEscape(measurement[column])).join(','),
  ];
  return rows.join('\n');
}

String _csvEscape(dynamic value) {
  if (value == null) return '';
  final text = value.toString();
  return text.contains(RegExp(r'[",\r\n]'))
      ? '"${text.replaceAll('"', '""')}"'
      : text;
}

double _round(num value, int decimals) {
  final factor = math.pow(10, decimals).toDouble();
  return (value * factor).round() / factor;
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

double? _statDouble(dynamic value) {
  if (value == null) return null;
  final parsed = _asDouble(value);
  return parsed.isFinite && parsed >= 0 ? parsed : null;
}
