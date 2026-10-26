import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:image/image.dart' as img;

typedef OfflineProgressCallback = void Function(double value, String phase);

const _qcMadZThreshold = 4.0;
const _qcRelaxedMadZThreshold = 8.0;
const _qcMinOutlierMetrics = 2;

class OfflineGrainAnalyzer {
  static const modelAssetPath = 'assets/models/best_mobile_yolo26_640.onnx';
  static const optimizedHighQualityModelAssetPath =
      'assets/models/best_1024_int8_static.onnx';

  // Keep these aligned with backend/config/grain.settings.json.
  static const _classCount = 2;
  static const _maskCoefficientCount = 32;
  static const _predictionFeatureCount =
      4 + _classCount + _maskCoefficientCount;
  static const _safeModelProfile = _OfflineModelProfile(
    name: 'mobile_640_small_int8_safe',
    modelAssetPath: modelAssetPath,
    inputSize: 640,
    protoSize: 160,
    enableRoiPrepass: false,
    enableFullImagePass: true,
    enableTiledInference: false,
    tileSize: 640,
    tileOverlap: 0.25,
    roiMaxPasses: 0,
    previewMaxSide: 640,
    intraOpThreads: 1,
  );
  static const _fastHighQualityModelProfile = _OfflineModelProfile(
    name: 'mobile_1024_int8_fast',
    modelAssetPath: optimizedHighQualityModelAssetPath,
    inputSize: 1024,
    protoSize: 256,
    enableRoiPrepass: false,
    enableFullImagePass: true,
    enableTiledInference: false,
    tileSize: 1024,
    tileOverlap: 0,
    roiMaxPasses: 0,
    allowZeroCountFallback: true,
    previewMaxSide: 768,
    intraOpThreads: 1,
  );
  static const _deviceMemoryChannel =
      MethodChannel('vn.mekonglab.seedvision/device_memory');
  static const _minFastHighQualityLargeHeapMb = 192;
  static const _minFastHighQualityAvailableMb = 256;
  static const _maxSide = 1024;
  static const _confidence = 0.04;
  static const _iou = 0.70;
  static const _maxDetections = 5000;
  static const _maskThreshold = 0.50;
  static const _longMaskThreshold = 0.40;
  static const _longMaskAspectRatio = 2.15;
  static const _maskCropPaddingRatio = 0.01;
  static const _longMaskCropPaddingRatio = 0.08;
  static const _mergeIou = 0.35;
  static const _mergeOverlap = 0.70;
  static const _edgeMarginRatio = 0.10;
  static const _roiDetectionSide = 768;
  static const _roiPadding = 40;
  static const _roiMergeMaxSide = 640;
  static const _roiMinArea = 48;
  static const _roiMinBoxSide = 6;
  // Low-end Android devices can be killed by many consecutive 640px ONNX
  // passes. Keep a small ROI budget and fall back to one full-image pass when
  // an image is too fragmented.
  static const _roiMaxPasses = 8;
  static const _roiOverflowProbePasses = _roiMaxPasses + 1;
  static const _minArea = 20;
  static const _maxArea = 200000;
  static const _maxAspectRatio = 14.0;
  static const _minSolidity = 0.5;
  static const _minExtent = 0.2;
  static const _skinRejectRatio = 0.58;
  static const _strongSkinRejectRatio = 0.72;
  static const _adaptiveMinCandidates = 8;
  static const _adaptiveMadZ = 5.0;
  static const _dynamicAreaMultiplier = 8.0;
  static const _mergedSplitAreaRatio = 1.45;
  static const _mergedSplitLengthRatio = 1.22;
  static const _mergedSplitWidthRatio = 1.32;
  static const _mergedSplitMadZ = 3.0;
  static const _mergedSplitMaxParts = 4;
  static const _enableFragmentMerge = true;
  static const _fragmentMergeMaxGapRatio = 0.08;
  static const _fragmentMergeMaxAreaRatio = 1.28;
  static const _fragmentMergeMinAreaRatio = 0.65;
  static const _fragmentMergeMaxLengthRatio = 1.20;
  static const _fragmentMergeMaxWidthRatio = 1.22;
  static const _enableClassicalFallback = true;
  static const _classicalFallbackMaxYoloCandidates = 12;
  static const _classicalFallbackMinCandidates = 25;
  static const _classicalFallbackMaxAdded = 180;
  static const _classicalFallbackConfidence = 0.085;
  static const _classicalFallbackBrightPercentile = 96.0;
  static const _classicalFallbackMinBrightDelta = 6.0;
  static const _classicalFallbackBackgroundRadius = 15;
  static const _classicalFallbackDilateIterations = 1;
  static const _classicalFallbackMaxAspect = 18.0;

  OrtSession? _session;
  _OfflineModelProfile? _sessionProfile;

  Future<OfflineModelInfo> loadModelInfo() async {
    final profiles = await _choosePreferredProfiles();
    for (var index = 0; index < profiles.length; index++) {
      final profile = profiles[index];
      try {
        final session = await _loadSession(profile);
        return OfflineModelInfo(
          modelAssetPath: profile.modelAssetPath,
          inputTensors: [
            OfflineTensorInfo(
              name: session.inputNames.first,
              shape: [1, 3, profile.inputSize, profile.inputSize],
              type: 'float32',
            ),
          ],
          outputTensors: [
            OfflineTensorInfo(
              name: session.outputNames.first,
              shape: const [1, 300, _predictionFeatureCount],
              type: 'float32',
            ),
            OfflineTensorInfo(
              name: session.outputNames.last,
              shape: [1, 32, profile.protoSize, profile.protoSize],
              type: 'float32',
            ),
          ],
        );
      } catch (error) {
        if (index + 1 >= profiles.length ||
            !_canFallbackFromProfile(profile, error)) {
          rethrow;
        }
        await close();
      }
    }
    throw StateError('Cannot load offline grain model.');
  }

  Future<OfflineAnalyzeResult> analyze(
    Uint8List imageBytes, {
    double? referencePixels,
    double? referenceMm,
    double? referenceX1,
    double? referenceY1,
    double? referenceX2,
    double? referenceY2,
    OfflineProgressCallback? onProgress,
  }) async {
    final profiles = await _choosePreferredProfiles();
    Object? lastError;
    String? fallbackReason;
    for (var index = 0; index < profiles.length; index++) {
      final profile = profiles[index];
      try {
        final result = await _analyzeWithProfile(
          profile,
          imageBytes,
          referencePixels: referencePixels,
          referenceMm: referenceMm,
          referenceX1: referenceX1,
          referenceY1: referenceY1,
          referenceX2: referenceX2,
          referenceY2: referenceY2,
          onProgress: onProgress,
          fallbackReason: fallbackReason,
        );
        if (profile.allowZeroCountFallback &&
            _shouldRetryZeroDetection(result) &&
            index + 1 < profiles.length) {
          await close();
          fallbackReason = 'fast_model_zero_detections';
          onProgress?.call(
            58,
            'Model 1024 tối ưu không phát hiện hạt, kiểm tra bằng 640 an toàn',
          );
          await Future<void>.delayed(Duration.zero);
          continue;
        }
        return result;
      } catch (error) {
        lastError = error;
        if (index + 1 < profiles.length &&
            _canFallbackFromProfile(profile, error)) {
          await close();
          fallbackReason = _profileFallbackReason(profile, error);
          onProgress?.call(58, _profileFallbackMessage(profile, error));
          await Future<void>.delayed(Duration.zero);
          continue;
        }
        rethrow;
      }
    }
    throw StateError(lastError?.toString() ?? 'Offline analysis failed.');
  }

  Future<OfflineAnalyzeResult> _analyzeWithProfile(
    _OfflineModelProfile profile,
    Uint8List imageBytes, {
    double? referencePixels,
    double? referenceMm,
    double? referenceX1,
    double? referenceY1,
    double? referenceX2,
    double? referenceY2,
    OfflineProgressCallback? onProgress,
    String? fallbackReason,
  }) async {
    Future<void> reportProgress(double value, String phase) async {
      onProgress?.call(value, phase);
      await Future<void>.delayed(Duration.zero);
    }

    await reportProgress(54, 'Chuẩn bị nhận dạng trên thiết bị');
    final session = await _loadSession(profile);
    await reportProgress(60, 'Chuẩn bị ảnh để nhận dạng');
    final original = img.decodeImage(imageBytes);
    if (original == null) throw StateError('Cannot decode selected image.');

    final originalWidth = original.width;
    final originalHeight = original.height;
    final longestSide = math.max(originalWidth, originalHeight);
    final scale = longestSide > _maxSide ? _maxSide / longestSide : 1.0;
    final processed = scale < 1.0
        ? img.copyResize(
            original,
            width: (originalWidth * scale).round(),
            height: (originalHeight * scale).round(),
            interpolation: img.Interpolation.average,
          )
        : img.Image.from(original);

    final rawInstances = <_Instance>[];
    var rawDetectionCount = 0;
    var passCount = 0;
    var roiPassCount = 0;
    var tilePassCount = 0;
    var roiBudgetExceeded = false;
    var detectedRoiRegionCount = 0;
    var roiRegions = const <_RoiBox>[];
    await reportProgress(68, 'Đang nhận dạng hạt trên thiết bị');
    if (profile.enableRoiPrepass) {
      final detectedRoiRegions = _detectRoiRegions(processed);
      detectedRoiRegionCount = detectedRoiRegions.length;
      roiBudgetExceeded = detectedRoiRegions.length > profile.roiMaxPasses;
      roiRegions = roiBudgetExceeded ? const <_RoiBox>[] : detectedRoiRegions;
      for (var i = 0; i < roiRegions.length; i++) {
        final roi = roiRegions[i];
        await reportProgress(
          68 + (14 * (i / math.max(roiRegions.length, 1))),
          'Nhận dạng ROI ${i + 1}/${roiRegions.length}',
        );
        final crop = img.copyCrop(
          processed,
          x: roi.x,
          y: roi.y,
          width: roi.width,
          height: roi.height,
        );
        final pass = await _runInferencePass(
          profile,
          session,
          crop,
          roi.x,
          roi.y,
          'roi',
        );
        final decoded = _decodePassInstances(
          pass,
          imageWidth: processed.width,
          imageHeight: processed.height,
        );
        rawDetectionCount += decoded.rawDetectionCount;
        rawInstances.addAll(decoded.instances);
        passCount++;
        roiPassCount++;
      }
    }
    if ((rawInstances.isEmpty || roiBudgetExceeded) &&
        profile.enableFullImagePass) {
      final pass =
          await _runInferencePass(profile, session, processed, 0, 0, 'full');
      final decoded = _decodePassInstances(
        pass,
        imageWidth: processed.width,
        imageHeight: processed.height,
      );
      rawDetectionCount += decoded.rawDetectionCount;
      rawInstances.addAll(decoded.instances);
      passCount++;
    }
    if (profile.enableTiledInference &&
        (!profile.enableFullImagePass ||
            processed.width > profile.tileSize ||
            processed.height > profile.tileSize)) {
      for (final y in _tileStarts(
        processed.height,
        profile.tileSize,
        profile.tileOverlap,
      )) {
        for (final x in _tileStarts(
          processed.width,
          profile.tileSize,
          profile.tileOverlap,
        )) {
          final tileWidth = math.min(profile.tileSize, processed.width - x);
          final tileHeight = math.min(profile.tileSize, processed.height - y);
          final tile = img.copyCrop(
            processed,
            x: x,
            y: y,
            width: tileWidth,
            height: tileHeight,
          );
          final pass =
              await _runInferencePass(profile, session, tile, x, y, 'tile');
          final decoded = _decodePassInstances(
            pass,
            imageWidth: processed.width,
            imageHeight: processed.height,
          );
          rawDetectionCount += decoded.rawDetectionCount;
          rawInstances.addAll(decoded.instances);
          passCount++;
          tilePassCount++;
        }
      }
    }

    await reportProgress(82, 'Tạo hình dạng, đo hạt và dựng ảnh');
    final mergedInstances = _mergeInstances(rawInstances);
    // Drop duplicate mask buffers before rendering previews and applying calibration.
    rawInstances.clear();

    return _finishAnalysis(
      processed,
      _OfflinePostprocessInput(
        rawInstances: mergedInstances,
        rawDetectionCount: rawDetectionCount,
        passCount: passCount,
        roiRegionCount: detectedRoiRegionCount,
        roiBudgetExceeded: roiBudgetExceeded,
        roiPassCount: roiPassCount,
        tilePassCount: tilePassCount,
        width: processed.width,
        height: processed.height,
        originalWidth: originalWidth,
        originalHeight: originalHeight,
        profile: profile,
        fallbackReason: fallbackReason,
        scale: scale,
        referencePixels: referencePixels,
        referenceMm: referenceMm,
        referenceX1: referenceX1,
        referenceY1: referenceY1,
        referenceX2: referenceX2,
        referenceY2: referenceY2,
      ),
    );
  }

  static _DecodedInferencePass _decodePassInstances(
    _OfflineInferencePass pass, {
    required int imageWidth,
    required int imageHeight,
  }) {
    final detections = _decodePredictions(pass.predictions, pass.profile);
    final instances = <_Instance>[];
    for (final detection in detections) {
      final instance = _decodeMask(
        pass.protos,
        detection,
        width: pass.width,
        height: pass.height,
        paddedSide: pass.paddedSide,
        inputSize: pass.profile.inputSize,
        offsetX: pass.offsetX,
        offsetY: pass.offsetY,
        source: pass.source,
      );
      if (instance == null) continue;
      instances.add(
        _withPassEdgeMetadata(
          instance,
          pass,
          imageWidth: imageWidth,
          imageHeight: imageHeight,
        ),
      );
    }
    return _DecodedInferencePass(
      rawDetectionCount: detections.length,
      instances: instances,
    );
  }

  Future<_OfflineInferencePass> _runInferencePass(
    _OfflineModelProfile profile,
    OrtSession session,
    img.Image source,
    int offsetX,
    int offsetY,
    String sourceName,
  ) async {
    final squareSide = math.max(source.width, source.height);
    final square =
        img.Image(width: squareSide, height: squareSide, numChannels: 3);
    img.fill(square, color: img.ColorRgb8(255, 255, 255));
    img.compositeImage(square, source, dstX: 0, dstY: 0);
    final resized = img.copyResize(
      square,
      width: profile.inputSize,
      height: profile.inputSize,
      interpolation: img.Interpolation.linear,
    );

    final input = Float32List(1 * 3 * profile.inputSize * profile.inputSize);
    final channelSize = profile.inputSize * profile.inputSize;
    for (var y = 0; y < profile.inputSize; y++) {
      for (var x = 0; x < profile.inputSize; x++) {
        final pixel = resized.getPixel(x, y);
        final index = y * profile.inputSize + x;
        input[index] = pixel.r / 255.0;
        input[channelSize + index] = pixel.g / 255.0;
        input[channelSize * 2 + index] = pixel.b / 255.0;
      }
    }

    final inputTensor = await OrtValue.fromList(
      input,
      [1, 3, profile.inputSize, profile.inputSize],
    );
    final outputs = await session.run({session.inputNames.first: inputTensor});
    try {
      return _OfflineInferencePass(
        predictions: _flattenedOutputToFloat32(
          await outputs[session.outputNames.first]!.asFlattenedList(),
        ),
        protos: _flattenedOutputToFloat32(
          await outputs[session.outputNames.last]!.asFlattenedList(),
        ),
        width: source.width,
        height: source.height,
        paddedSide: squareSide,
        offsetX: offsetX,
        offsetY: offsetY,
        source: sourceName,
        profile: profile,
      );
    } finally {
      await inputTensor.dispose();
      for (final output in outputs.values) {
        await output.dispose();
      }
    }
  }

  static Float32List _flattenedOutputToFloat32(Object? values) {
    if (values is Float32List) {
      return Float32List.fromList(values);
    }
    if (values is List) {
      final output = Float32List(values.length);
      for (var i = 0; i < values.length; i++) {
        output[i] = (values[i] as num).toDouble();
      }
      return output;
    }
    throw StateError('Unexpected ONNX output format: ${values.runtimeType}');
  }

  static List<_RoiBox> _detectRoiRegions(img.Image source) {
    final longestSide = math.max(source.width, source.height);
    final detectScale =
        longestSide > _roiDetectionSide ? _roiDetectionSide / longestSide : 1.0;
    final detect = detectScale < 1.0
        ? img.copyResize(
            source,
            width: math.max(1, (source.width * detectScale).round()),
            height: math.max(1, (source.height * detectScale).round()),
            interpolation: img.Interpolation.average,
          )
        : img.Image.from(source);
    final width = detect.width;
    final height = detect.height;
    if (width < 8 || height < 8) return const [];

    final bg = _borderColor(detect);
    final bgLuma = _luma(bg.r, bg.g, bg.b);
    final foreground = Uint8List(width * height);
    for (var y = 0; y < height; y++) {
      final row = y * width;
      for (var x = 0; x < width; x++) {
        final pixel = detect.getPixel(x, y);
        final r = pixel.r.toDouble();
        final g = pixel.g.toDouble();
        final b = pixel.b.toDouble();
        final dr = r - bg.r;
        final dg = g - bg.g;
        final db = b - bg.b;
        final dist2 = dr * dr + dg * dg + db * db;
        final lumaDelta = (_luma(r, g, b) - bgLuma).abs();
        final saturation = _saturation(r, g, b);
        if ((dist2 > 34 * 34 && lumaDelta > 14) ||
            (dist2 > 24 * 24 && saturation > 0.18)) {
          foreground[row + x] = 1;
        }
      }
    }

    final visited = Uint8List(width * height);
    final components = <_RoiBox>[];
    final queue = Int32List(width * height);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final start = y * width + x;
        if (foreground[start] == 0 || visited[start] != 0) continue;
        var head = 0;
        var tail = 0;
        queue[tail++] = start;
        visited[start] = 1;
        var minX = x;
        var maxX = x;
        var minY = y;
        var maxY = y;
        var area = 0;
        while (head < tail) {
          final index = queue[head++];
          final cy = index ~/ width;
          final cx = index - cy * width;
          area++;
          minX = math.min(minX, cx);
          maxX = math.max(maxX, cx);
          minY = math.min(minY, cy);
          maxY = math.max(maxY, cy);
          for (var dy = -1; dy <= 1; dy++) {
            for (var dx = -1; dx <= 1; dx++) {
              if (dx == 0 && dy == 0) continue;
              final nx = cx + dx;
              final ny = cy + dy;
              if (nx < 0 || nx >= width || ny < 0 || ny >= height) continue;
              final ni = ny * width + nx;
              if (foreground[ni] == 0 || visited[ni] != 0) continue;
              visited[ni] = 1;
              queue[tail++] = ni;
            }
          }
        }
        if (area < _roiMinArea ||
            maxX - minX + 1 < _roiMinBoxSide ||
            maxY - minY + 1 < _roiMinBoxSide) {
          continue;
        }
        final x1 = (minX / detectScale).floor() - _roiPadding;
        final y1 = (minY / detectScale).floor() - _roiPadding;
        final x2 = ((maxX + 1) / detectScale).ceil() + _roiPadding;
        final y2 = ((maxY + 1) / detectScale).ceil() + _roiPadding;
        components.add(
          _RoiBox.fromBounds(
            x1.clamp(0, source.width - 1).toInt(),
            y1.clamp(0, source.height - 1).toInt(),
            x2.clamp(1, source.width).toInt(),
            y2.clamp(1, source.height).toInt(),
          ),
        );
      }
    }
    if (components.isEmpty) return const [];
    return _mergeRoiBoxes(components)
        .where((box) => box.width > 8 && box.height > 8)
        .take(_roiOverflowProbePasses)
        .toList();
  }

  static List<_RoiBox> _mergeRoiBoxes(List<_RoiBox> boxes) {
    final pending = [...boxes]
      ..sort((a, b) => a.y == b.y ? a.x.compareTo(b.x) : a.y.compareTo(b.y));
    var changed = true;
    while (changed) {
      changed = false;
      for (var i = 0; i < pending.length; i++) {
        for (var j = i + 1; j < pending.length; j++) {
          final merged = pending[i].union(pending[j]);
          if (math.max(merged.width, merged.height) > _roiMergeMaxSide) {
            continue;
          }
          pending[i] = merged;
          pending.removeAt(j);
          changed = true;
          break;
        }
        if (changed) break;
      }
    }
    pending.sort((a, b) => b.area.compareTo(a.area));
    return pending;
  }

  static _RgbColor _borderColor(img.Image image) {
    var r = 0.0;
    var g = 0.0;
    var b = 0.0;
    var count = 0;
    void sample(int x, int y) {
      final pixel = image.getPixel(x, y);
      r += pixel.r;
      g += pixel.g;
      b += pixel.b;
      count++;
    }

    for (var x = 0; x < image.width; x++) {
      sample(x, 0);
      sample(x, image.height - 1);
    }
    for (var y = 1; y < image.height - 1; y++) {
      sample(0, y);
      sample(image.width - 1, y);
    }
    final divisor = math.max(count, 1);
    return _RgbColor(r / divisor, g / divisor, b / divisor);
  }

  static double _luma(double r, double g, double b) =>
      0.299 * r + 0.587 * g + 0.114 * b;

  static double _saturation(double r, double g, double b) {
    final maxChannel = math.max(r, math.max(g, b));
    final minChannel = math.min(r, math.min(g, b));
    if (maxChannel <= 1e-9) return 0;
    return (maxChannel - minChannel) / maxChannel;
  }

  static OfflineAnalyzeResult _finishAnalysis(
    img.Image processed,
    _OfflinePostprocessInput input,
  ) {
    final rawDetectionCount = input.rawDetectionCount;
    final fallback = _augmentLowRecallInstances(processed, input.rawInstances);
    final instances = fallback.instances;
    final filtered = _filterAndMeasure(
      instances,
      processed,
      width: input.width,
      height: input.height,
      scale: input.scale,
      referencePixels: input.referencePixels,
      referenceMm: input.referenceMm,
      referenceX1: input.referenceX1,
      referenceY1: input.referenceY1,
      referenceX2: input.referenceX2,
      referenceY2: input.referenceY2,
    );
    final summary = _summaryFor(filtered.measurements);
    final preview = _previewRenderInput(processed, filtered, input.profile);
    final overlay = _renderOverlay(preview.rgb, preview.result);
    final mask = _renderMask(preview.result);
    final labels = _renderLabels(
      preview.result,
      coordinateScaleX: preview.coordinateScaleX,
      coordinateScaleY: preview.coordinateScaleY,
    );
    final labelMap = _renderLabelMap(preview.result);

    final seedCandidateCount = instances.where(_isSeedClassInstance).length;
    final refCandidateCount = instances.length - seedCandidateCount;
    return OfflineAnalyzeResult(
      originalPng: Uint8List(0),
      overlayPng: Uint8List.fromList(img.encodePng(overlay)),
      maskPng: Uint8List.fromList(img.encodePng(mask)),
      labelsPng: Uint8List.fromList(img.encodePng(labels)),
      labelMapPng: Uint8List.fromList(img.encodePng(labelMap)),
      image: {
        'width': input.width,
        'height': input.height,
        'original_width': input.originalWidth,
        'original_height': input.originalHeight,
        'scale': _round(input.scale, 6),
      },
      measurements: filtered.measurements,
      summary: summary,
      calibration: {
        'referencePixels': input.referencePixels,
        'referenceMm': input.referenceMm,
        'referencePixelSpace': 'original',
        'enabled': filtered.mmPerPixel > 0,
        'mm_per_pixel': filtered.mmPerPixel,
        'referenceX1': input.referenceX1 ?? -1,
        'referenceY1': input.referenceY1 ?? -1,
        'referenceX2': input.referenceX2 ?? -1,
        'referenceY2': input.referenceY2 ?? -1,
        'excluded_reference_object_count':
            filtered.excludedReferenceObjectCount,
        'suggested_reference': filtered.suggestedReference,
      },
      segmentation: {
        'pipeline': 'yolo_sam_onnx',
        'model': input.profile.modelAssetPath,
        'model_profile': input.profile.name,
        'model_input_size': input.profile.inputSize,
        'model_quality': input.profile.isHighQuality ? 'high' : 'safe',
        'intra_op_threads': input.profile.intraOpThreads,
        'preview_width': preview.result.width,
        'preview_height': preview.result.height,
        'preview_scale': _round(preview.coordinateScaleX, 6),
        'fallback_reason': input.fallbackReason,
        'refiner': 'disabled',
        'refiner_applied': false,
        'confidence': _confidence,
        'iou': _iou,
        'max_det': _maxDetections,
        'merged_split_method': 'distance_marker_projection',
        'merged_split_evidence_gate': 'distance_core_or_low_extent',
        'multi_pass_enabled': input.profile.enableRoiPrepass ||
            input.profile.enableTiledInference,
        'multi_pass_count': input.passCount,
        'roi_prepass_enabled': input.profile.enableRoiPrepass,
        'roi_region_count': input.roiRegionCount,
        'roi_pass_budget': input.profile.roiMaxPasses,
        'roi_budget_exceeded': input.roiBudgetExceeded,
        'roi_pass_count': input.roiPassCount,
        'roi_detection_side': _roiDetectionSide,
        'roi_padding': _roiPadding,
        'roi_merge_max_side': _roiMergeMaxSide,
        'tiled_inference': input.profile.enableTiledInference,
        'full_image_pass': input.profile.enableFullImagePass,
        'tile_size': input.profile.tileSize,
        'tile_overlap': input.profile.tileOverlap,
        'tile_pass_count': input.tilePassCount,
        'candidate_count': rawDetectionCount,
        'refined_candidate_count': instances.length,
        'seed_candidate_count': seedCandidateCount,
        'ref_candidate_count': refCandidateCount,
        'segment_count_before_filter': instances.length,
        'segment_count': filtered.measurements.length,
        'marker_count': filtered.measurements.length,
        'mask_filter': {
          'component_count_before': instances.length,
          'component_count_after': filtered.measurements.length,
          'ignored_ref_count': math.max(
            0,
            refCandidateCount - filtered.acceptedRefClassSeedCount,
          ),
          'excluded_reference_object_count':
              filtered.excludedReferenceObjectCount,
          'accepted_ref_class_seed_count': filtered.acceptedRefClassSeedCount,
          'auto_excluded_non_seed_count': filtered.autoExcludedNonSeedCount,
          'fragment_merge_count': filtered.fragmentMergeCount,
          'suggested_reference_available': filtered.suggestedReference != null,
        },
        'classical_fallback': fallback.stats,
        'effective_thresholds': {
          'minArea': _minArea,
          'maxArea': _maxArea,
          'maxSegmentAspectRatio': _maxAspectRatio,
          'minSegmentSolidity': _minSolidity,
          'minSegmentExtent': _minExtent,
          'adaptiveThresholds': true,
          'adaptiveMinCandidates': _adaptiveMinCandidates,
          'adaptiveMadZ': _adaptiveMadZ,
          'dynamicAreaMultiplier': _dynamicAreaMultiplier,
          'skinRejectRatio': _skinRejectRatio,
          'strongSkinRejectRatio': _strongSkinRejectRatio,
          'mergedSeedSplit': true,
          'mergedSplitAreaRatio': _mergedSplitAreaRatio,
          'mergedSplitLengthRatio': _mergedSplitLengthRatio,
          'mergedSplitWidthRatio': _mergedSplitWidthRatio,
          'mergedSplitMadZ': _mergedSplitMadZ,
          'mergedSplitMaxParts': _mergedSplitMaxParts,
          'fragmentMerge': _enableFragmentMerge,
          'fragmentMergeMaxGapRatio': _fragmentMergeMaxGapRatio,
          'fragmentMergeMaxAreaRatio': _fragmentMergeMaxAreaRatio,
          'classicalFallback': _enableClassicalFallback,
          'classicalFallbackMaxYoloCandidates':
              _classicalFallbackMaxYoloCandidates,
          'classicalFallbackMinCandidates': _classicalFallbackMinCandidates,
          'classicalFallbackBrightPercentile':
              _classicalFallbackBrightPercentile,
          'classicalFallbackDilateIterations':
              _classicalFallbackDilateIterations,
          'mergedSplitMethod': 'distance_marker_projection',
          'mergedSplitEvidenceGate': 'distance_core_or_low_extent',
        },
        'offline': true,
        'execution': 'mobile_onnxruntime',
        'execution_provider': 'CPU',
      },
    );
  }

  static List<_Detection> _decodePredictions(
    Float32List prediction,
    _OfflineModelProfile profile,
  ) {
    final featureCount = profile.predictionFeatureCount;
    final candidateCount = prediction.length ~/ featureCount;
    if (candidateCount <= 0 || prediction.length % featureCount != 0) {
      return const [];
    }
    final candidateMajor = candidateCount == 300;
    double valueAt(int feature, int candidate) {
      return candidateMajor
          ? prediction[candidate * featureCount + feature]
          : prediction[feature * candidateCount + candidate];
    }

    final candidates = <_Detection>[];
    for (var i = 0; i < candidateCount; i++) {
      final seedScore = valueAt(4, i);
      final refScore = valueAt(5, i);
      final classId = seedScore >= refScore ? 0 : 1;
      final score = classId == 0 ? seedScore : refScore;
      if (score < _confidence) continue;
      final cx = valueAt(0, i);
      final cy = valueAt(1, i);
      final width = valueAt(2, i);
      final height = valueAt(3, i);
      candidates.add(
        _Detection(
          score: score,
          classId: classId,
          x1: candidateMajor ? cx : cx - width / 2,
          y1: candidateMajor ? cy : cy - height / 2,
          x2: candidateMajor ? width : cx + width / 2,
          y2: candidateMajor ? height : cy + height / 2,
          coefficients:
              List.generate(_maskCoefficientCount, (c) => valueAt(6 + c, i)),
        ),
      );
    }
    candidates.sort((a, b) => b.score.compareTo(a.score));
    final kept = <_Detection>[];
    for (final candidate in candidates) {
      if (kept.every(
        (other) =>
            other.classId != candidate.classId ||
            _boxIou(candidate, other) < _iou,
      )) {
        kept.add(candidate);
        if (kept.length >= _maxDetections) break;
      }
    }
    return kept;
  }

  static _Instance? _decodeMask(
    Float32List protos,
    _Detection detection, {
    required int width,
    required int height,
    required int paddedSide,
    required int inputSize,
    int offsetX = 0,
    int offsetY = 0,
    required String source,
  }) {
    final protoPlaneSize = protos.length ~/ _maskCoefficientCount;
    final protoSize = math.sqrt(protoPlaneSize).round();
    if (protoSize <= 0 ||
        protoSize * protoSize * _maskCoefficientCount != protos.length) {
      return null;
    }
    final scale = paddedSide / inputSize;
    final boxWidth = math.max(detection.x2 - detection.x1, 1.0);
    final boxHeight = math.max(detection.y2 - detection.y1, 1.0);
    final boxAspect = math.max(boxWidth, boxHeight) /
        math.max(math.min(boxWidth, boxHeight), 1.0);
    final isLongBox = boxAspect >= _longMaskAspectRatio;
    final threshold = isLongBox ? _longMaskThreshold : _maskThreshold;
    final paddingRatio =
        isLongBox ? _longMaskCropPaddingRatio : _maskCropPaddingRatio;
    final cropPadding = paddingRatio <= 0
        ? 0.0
        : math.max(1.0, math.max(boxWidth, boxHeight) * paddingRatio);
    final cropX1 = detection.x1 - cropPadding;
    final cropY1 = detection.y1 - cropPadding;
    final cropX2 = detection.x2 + cropPadding;
    final cropY2 = detection.y2 + cropPadding;
    final x1 = (cropX1 * scale).floor().clamp(0, width);
    final y1 = (cropY1 * scale).floor().clamp(0, height);
    final x2 = (cropX2 * scale).ceil().clamp(0, width);
    final y2 = (cropY2 * scale).ceil().clamp(0, height);
    if (x2 <= x1 || y2 <= y1) return null;
    final maskWidth = x2 - x1;
    final maskHeight = y2 - y1;
    final pixels = Uint8List(maskWidth * maskHeight);
    final protoX1 =
        ((cropX1 / inputSize) * protoSize).floor().clamp(0, protoSize);
    final protoY1 =
        ((cropY1 / inputSize) * protoSize).floor().clamp(0, protoSize);
    final protoX2 =
        ((cropX2 / inputSize) * protoSize).ceil().clamp(0, protoSize);
    final protoY2 =
        ((cropY2 / inputSize) * protoSize).ceil().clamp(0, protoSize);
    if (protoX2 <= protoX1 || protoY2 <= protoY1) return null;

    var area = 0;
    for (var y = y1; y < y2; y++) {
      final protoY = (y / paddedSide) * protoSize - 0.5;
      final py0 = protoY.floor().clamp(0, protoSize - 1);
      final py1 = (py0 + 1).clamp(0, protoSize - 1);
      final dy = (protoY - py0).clamp(0.0, 1.0);
      for (var x = x1; x < x2; x++) {
        final protoX = (x / paddedSide) * protoSize - 0.5;
        final px0 = protoX.floor().clamp(0, protoSize - 1);
        final px1 = (px0 + 1).clamp(0, protoSize - 1);
        final dx = (protoX - px0).clamp(0.0, 1.0);
        final topLeftWeight = (1 - dx) * (1 - dy);
        final topRightWeight = dx * (1 - dy);
        final bottomLeftWeight = (1 - dx) * dy;
        final bottomRightWeight = dx * dy;
        var logit = 0.0;
        for (var c = 0; c < _maskCoefficientCount; c++) {
          final channelOffset = c * protoSize * protoSize;
          final row0 = channelOffset + py0 * protoSize;
          final row1 = channelOffset + py1 * protoSize;
          final topLeft =
              px0 >= protoX1 && px0 < protoX2 && py0 >= protoY1 && py0 < protoY2
                  ? protos[row0 + px0]
                  : 0.0;
          final topRight =
              px1 >= protoX1 && px1 < protoX2 && py0 >= protoY1 && py0 < protoY2
                  ? protos[row0 + px1]
                  : 0.0;
          final bottomLeft =
              px0 >= protoX1 && px0 < protoX2 && py1 >= protoY1 && py1 < protoY2
                  ? protos[row1 + px0]
                  : 0.0;
          final bottomRight =
              px1 >= protoX1 && px1 < protoX2 && py1 >= protoY1 && py1 < protoY2
                  ? protos[row1 + px1]
                  : 0.0;
          final value = topLeft * topLeftWeight +
              topRight * topRightWeight +
              bottomLeft * bottomLeftWeight +
              bottomRight * bottomRightWeight;
          logit += detection.coefficients[c] * value;
        }
        if (_sigmoid(logit) <= threshold) continue;
        pixels[(y - y1) * maskWidth + (x - x1)] = 1;
        area++;
      }
    }
    if (area == 0) return null;
    return _Instance(
      mask: pixels,
      confidence: detection.score,
      classId: detection.classId,
      x: x1 + offsetX,
      y: y1 + offsetY,
      width: maskWidth,
      height: maskHeight,
      source: source,
    );
  }

  static _Instance _withPassEdgeMetadata(
    _Instance instance,
    _OfflineInferencePass pass, {
    required int imageWidth,
    required int imageHeight,
  }) {
    if (pass.source != 'tile') return instance;
    final margin =
        (math.min(pass.width, pass.height) * _edgeMarginRatio).round();
    if (margin <= 0) return instance;
    final localX1 = instance.x - pass.offsetX;
    final localY1 = instance.y - pass.offsetY;
    final localX2 = localX1 + instance.width;
    final localY2 = localY1 + instance.height;
    final touchesInternalEdge = (pass.offsetX > 0 && localX1 <= margin) ||
        (pass.offsetY > 0 && localY1 <= margin) ||
        (pass.offsetX + pass.width < imageWidth &&
            localX2 >= pass.width - margin) ||
        (pass.offsetY + pass.height < imageHeight &&
            localY2 >= pass.height - margin);
    if (!touchesInternalEdge) return instance;
    return _Instance(
      mask: instance.mask,
      confidence: instance.confidence * 0.84,
      classId: instance.classId,
      x: instance.x,
      y: instance.y,
      width: instance.width,
      height: instance.height,
      source: '${instance.source}_edge',
    );
  }

  static List<int> _tileStarts(
    int length,
    int tileSize,
    double tileOverlap,
  ) {
    if (length <= tileSize) return [0];
    final step = math.max(1, (tileSize * (1.0 - tileOverlap)).round()).toInt();
    final starts = <int>[];
    for (var value = 0; value <= length - tileSize; value += step) {
      starts.add(value);
    }
    final last = length - tileSize;
    if (starts.isEmpty || starts.last != last) starts.add(last);
    return starts;
  }

  static List<_Instance> _mergeInstances(List<_Instance> instances) {
    final sorted = [...instances]
      ..sort((a, b) => b.confidence.compareTo(a.confidence));
    final selected = <_Instance>[];
    final selectedAreas = <int>[];
    for (final candidate in sorted) {
      final candidateArea = _instanceArea(candidate);
      if (candidateArea <= 0) continue;
      var duplicate = false;
      for (var i = 0; i < selected.length; i++) {
        if (!_instanceBboxIntersects(candidate, selected[i])) continue;
        final inter = _instanceIntersectionArea(candidate, selected[i]);
        if (inter == 0) continue;
        final union = candidateArea + selectedAreas[i] - inter;
        final iou = inter / math.max(union, 1);
        final overlap =
            inter / math.max(math.min(candidateArea, selectedAreas[i]), 1);
        if (iou >= _mergeIou || overlap >= _mergeOverlap) {
          duplicate = true;
          break;
        }
      }
      if (!duplicate) {
        selected.add(candidate);
        selectedAreas.add(candidateArea);
      }
    }
    return selected;
  }

  static _ClassicalFallbackResult _augmentLowRecallInstances(
    img.Image rgb,
    List<_Instance> instances,
  ) {
    final yoloSeedCount = instances.where(_isSeedClassInstance).length;
    final stats = <String, dynamic>{
      'enabled': _enableClassicalFallback,
      'applied': false,
      'reason': _enableClassicalFallback ? 'not_evaluated' : 'disabled',
      'yolo_seed_count': yoloSeedCount,
      'classical_candidate_count': 0,
      'dilate_iterations': _classicalFallbackDilateIterations,
      'added_count': 0,
    };
    if (!_enableClassicalFallback) {
      return _ClassicalFallbackResult(instances, stats);
    }
    if (yoloSeedCount > _classicalFallbackMaxYoloCandidates) {
      stats['reason'] = 'yolo_candidate_count_ok';
      return _ClassicalFallbackResult(instances, stats);
    }

    final classical = _lightSeedFallbackInstances(rgb);
    stats['classical_candidate_count'] = classical.length;
    if (classical.length < _classicalFallbackMinCandidates) {
      stats['reason'] = 'not_enough_classical_candidates';
      return _ClassicalFallbackResult(instances, stats);
    }

    final merged = [...instances];
    var added = 0;
    for (final candidate in classical) {
      if (added >= _classicalFallbackMaxAdded) break;
      if (_duplicatesExistingInstance(candidate, merged)) continue;
      merged.add(candidate);
      added++;
    }
    stats['added_count'] = added;
    stats['applied'] = added > 0;
    stats['reason'] = added > 0 ? 'applied' : 'all_classical_duplicates';
    return _ClassicalFallbackResult(merged, stats);
  }

  static List<_Instance> _lightSeedFallbackInstances(img.Image rgb) {
    final width = rgb.width;
    final height = rgb.height;
    if (width <= 0 || height <= 0) return const [];
    final imageArea = math.max(1, width * height);
    final shortSide = math.max(1, math.min(width, height));
    final luma = Float64List(width * height);
    final saturation = Float64List(width * height);
    final value = Float64List(width * height);
    for (var y = 0; y < height; y++) {
      final row = y * width;
      for (var x = 0; x < width; x++) {
        final pixel = rgb.getPixel(x, y);
        final r = pixel.r.toDouble();
        final g = pixel.g.toDouble();
        final b = pixel.b.toDouble();
        final maxChannel = math.max(r, math.max(g, b));
        final minChannel = math.min(r, math.min(g, b));
        final index = row + x;
        luma[index] = _luma(r, g, b);
        value[index] = maxChannel;
        saturation[index] =
            maxChannel <= 1e-9 ? 0 : (maxChannel - minChannel) / maxChannel;
      }
    }

    final background =
        _boxBlur(luma, width, height, _classicalFallbackBackgroundRadius);
    final localBright = Uint8List(width * height);
    final hist = Int32List(256);
    for (var i = 0; i < localBright.length; i++) {
      final diff = (luma[i] - background[i]).round().clamp(0, 255).toInt();
      localBright[i] = diff;
      hist[diff]++;
    }
    final percentileValue =
        _histogramPercentile(hist, _classicalFallbackBrightPercentile);
    final threshold = math.max(
      _classicalFallbackMinBrightDelta,
      percentileValue.toDouble(),
    );
    final binary = Uint8List(width * height);
    for (var i = 0; i < binary.length; i++) {
      final bright = localBright[i] >= threshold;
      final coloredSeed = saturation[i] > 35 / 255 &&
          value[i] > 100 &&
          localBright[i] >=
              math.max(4.0, _classicalFallbackMinBrightDelta * 0.75);
      if (bright || coloredSeed) binary[i] = 1;
    }
    final closed = _erode3(_dilate3(binary, width, height), width, height);

    final minArea = math.max(_minArea, (imageArea * 0.00009).round());
    final maxArea =
        math.min(_maxArea, math.max(650, (imageArea * 0.0042).round()));
    final minLength = math.max(7.0, shortSide * 0.016);
    final minWidth = math.max(2.0, shortSide * 0.0045);
    final maxWidth = math.max(28.0, shortSide * 0.065);
    return _connectedLightSeedInstances(
      closed,
      width,
      height,
      minArea: minArea,
      maxArea: maxArea,
      minLength: minLength,
      minWidth: minWidth,
      maxWidth: maxWidth,
    );
  }

  static Float64List _boxBlur(
    Float64List values,
    int width,
    int height,
    int radius,
  ) {
    final integral = Float64List((width + 1) * (height + 1));
    for (var y = 0; y < height; y++) {
      var rowSum = 0.0;
      final srcRow = y * width;
      final integralRow = (y + 1) * (width + 1);
      final previousIntegralRow = y * (width + 1);
      for (var x = 0; x < width; x++) {
        rowSum += values[srcRow + x];
        integral[integralRow + x + 1] =
            integral[previousIntegralRow + x + 1] + rowSum;
      }
    }
    final output = Float64List(width * height);
    for (var y = 0; y < height; y++) {
      final y1 = math.max(0, y - radius);
      final y2 = math.min(height - 1, y + radius);
      for (var x = 0; x < width; x++) {
        final x1 = math.max(0, x - radius);
        final x2 = math.min(width - 1, x + radius);
        final a = y1 * (width + 1) + x1;
        final b = y1 * (width + 1) + x2 + 1;
        final c = (y2 + 1) * (width + 1) + x1;
        final d = (y2 + 1) * (width + 1) + x2 + 1;
        final sum = integral[d] - integral[b] - integral[c] + integral[a];
        output[y * width + x] = sum / ((x2 - x1 + 1) * (y2 - y1 + 1));
      }
    }
    return output;
  }

  static int _histogramPercentile(Int32List hist, double percentile) {
    final total = hist.fold<int>(0, (sum, value) => sum + value);
    if (total <= 0) return 0;
    final target = (total * percentile / 100).ceil();
    var cumulative = 0;
    for (var i = 0; i < hist.length; i++) {
      cumulative += hist[i];
      if (cumulative >= target) return i;
    }
    return hist.length - 1;
  }

  static Uint8List _dilate3(Uint8List binary, int width, int height) {
    final output = Uint8List(binary.length);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        var found = false;
        for (var dy = -1; dy <= 1 && !found; dy++) {
          final yy = y + dy;
          if (yy < 0 || yy >= height) continue;
          final row = yy * width;
          for (var dx = -1; dx <= 1; dx++) {
            final xx = x + dx;
            if (xx < 0 || xx >= width) continue;
            if (binary[row + xx] != 0) {
              found = true;
              break;
            }
          }
        }
        if (found) output[y * width + x] = 1;
      }
    }
    return output;
  }

  static Uint8List _erode3(Uint8List binary, int width, int height) {
    final output = Uint8List(binary.length);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        var keep = true;
        for (var dy = -1; dy <= 1 && keep; dy++) {
          final yy = y + dy;
          if (yy < 0 || yy >= height) {
            keep = false;
            break;
          }
          final row = yy * width;
          for (var dx = -1; dx <= 1; dx++) {
            final xx = x + dx;
            if (xx < 0 || xx >= width || binary[row + xx] == 0) {
              keep = false;
              break;
            }
          }
        }
        if (keep) output[y * width + x] = 1;
      }
    }
    return output;
  }

  static List<_Instance> _connectedLightSeedInstances(
    Uint8List binary,
    int width,
    int height, {
    required int minArea,
    required int maxArea,
    required double minLength,
    required double minWidth,
    required double maxWidth,
  }) {
    final visited = Uint8List(binary.length);
    final queue = Int32List(binary.length);
    final instances = <_Instance>[];
    for (var start = 0; start < binary.length; start++) {
      if (binary[start] == 0 || visited[start] != 0) continue;
      var head = 0;
      var tail = 0;
      queue[tail++] = start;
      visited[start] = 1;
      var minX = start % width;
      var maxX = minX;
      var minY = start ~/ width;
      var maxY = minY;
      while (head < tail) {
        final index = queue[head++];
        final y = index ~/ width;
        final x = index - y * width;
        minX = math.min(minX, x);
        maxX = math.max(maxX, x);
        minY = math.min(minY, y);
        maxY = math.max(maxY, y);
        for (var dy = -1; dy <= 1; dy++) {
          final yy = y + dy;
          if (yy < 0 || yy >= height) continue;
          final row = yy * width;
          for (var dx = -1; dx <= 1; dx++) {
            if (dx == 0 && dy == 0) continue;
            final xx = x + dx;
            if (xx < 0 || xx >= width) continue;
            final ni = row + xx;
            if (binary[ni] == 0 || visited[ni] != 0) continue;
            visited[ni] = 1;
            queue[tail++] = ni;
          }
        }
      }
      final area = tail;
      if (area < minArea || area > maxArea) continue;
      final boxWidth = maxX - minX + 1;
      final boxHeight = maxY - minY + 1;
      final mask = Uint8List(boxWidth * boxHeight);
      for (var i = 0; i < tail; i++) {
        final index = queue[i];
        final y = index ~/ width;
        final x = index - y * width;
        mask[(y - minY) * boxWidth + (x - minX)] = 1;
      }
      final metrics = _maskMetrics(
        mask,
        boxWidth,
        boxHeight,
        offsetX: minX,
        offsetY: minY,
      );
      if (metrics == null) continue;
      final length = (metrics['length_px'] as num).toDouble();
      final seedWidth = (metrics['width_px'] as num).toDouble();
      final aspect = (metrics['aspect_ratio'] as num).toDouble();
      final extent = (metrics['extent'] as num).toDouble();
      final solidity = (metrics['solidity'] as num).toDouble();
      if (length < minLength ||
          seedWidth < minWidth ||
          seedWidth > maxWidth ||
          aspect < 1.2 ||
          aspect > _classicalFallbackMaxAspect ||
          extent < 0.18 ||
          solidity < 0.45) {
        continue;
      }
      final instance = _Instance(
        mask: mask,
        confidence: _classicalFallbackConfidence,
        classId: 0,
        x: minX,
        y: minY,
        width: boxWidth,
        height: boxHeight,
        source: 'classical_light_seed_fallback',
      );
      instances.add(
        _dilateFallbackInstance(
          instance,
          imageWidth: width,
          imageHeight: height,
          iterations: _classicalFallbackDilateIterations,
        ),
      );
    }
    return instances;
  }

  static _Instance _dilateFallbackInstance(
    _Instance instance, {
    required int imageWidth,
    required int imageHeight,
    required int iterations,
  }) {
    if (iterations <= 0) return instance;
    final padding = iterations;
    final x = math.max(0, instance.x - padding);
    final y = math.max(0, instance.y - padding);
    final right = math.min(imageWidth, instance.x + instance.width + padding);
    final bottom =
        math.min(imageHeight, instance.y + instance.height + padding);
    final width = right - x;
    final height = bottom - y;
    if (width <= 0 || height <= 0) return instance;

    var mask = Uint8List(width * height);
    final offsetX = instance.x - x;
    final offsetY = instance.y - y;
    for (var row = 0; row < instance.height; row++) {
      final srcRow = row * instance.width;
      final dstRow = (row + offsetY) * width + offsetX;
      for (var col = 0; col < instance.width; col++) {
        mask[dstRow + col] = instance.mask[srcRow + col];
      }
    }
    for (var i = 0; i < iterations; i++) {
      mask = _dilate3(mask, width, height);
    }
    return _Instance(
      mask: mask,
      confidence: instance.confidence,
      classId: instance.classId,
      x: x,
      y: y,
      width: width,
      height: height,
      source: instance.source,
    );
  }

  static bool _duplicatesExistingInstance(
    _Instance candidate,
    List<_Instance> instances,
  ) {
    final candidateArea = _instanceArea(candidate);
    if (candidateArea <= 0) return true;
    for (final instance in instances) {
      if (!_instanceBboxIntersects(candidate, instance)) continue;
      final otherArea = _instanceArea(instance);
      final inter = _instanceIntersectionArea(candidate, instance);
      if (inter == 0) continue;
      final union = candidateArea + otherArea - inter;
      final iou = inter / math.max(union, 1);
      final overlap = inter / math.max(math.min(candidateArea, otherArea), 1);
      if (iou >= 0.30 || overlap >= 0.58) return true;
    }
    return false;
  }

  static int _instanceArea(_Instance instance) {
    var area = 0;
    for (final value in instance.mask) {
      if (value != 0) area++;
    }
    return area;
  }

  static bool _instanceBboxIntersects(_Instance a, _Instance b) {
    return a.x < b.x + b.width &&
        a.x + a.width > b.x &&
        a.y < b.y + b.height &&
        a.y + a.height > b.y;
  }

  static int _instanceIntersectionArea(_Instance a, _Instance b) {
    final x1 = math.max(a.x, b.x);
    final y1 = math.max(a.y, b.y);
    final x2 = math.min(a.x + a.width, b.x + b.width);
    final y2 = math.min(a.y + a.height, b.y + b.height);
    if (x2 <= x1 || y2 <= y1) return 0;
    var area = 0;
    for (var y = y1; y < y2; y++) {
      final aRow = (y - a.y) * a.width;
      final bRow = (y - b.y) * b.width;
      for (var x = x1; x < x2; x++) {
        if (a.mask[aRow + (x - a.x)] != 0 && b.mask[bRow + (x - b.x)] != 0) {
          area++;
        }
      }
    }
    return area;
  }

  static _FilteredResult _filterAndMeasure(
    List<_Instance> instances,
    img.Image rgb, {
    required int width,
    required int height,
    required double scale,
    required double? referencePixels,
    required double? referenceMm,
    required double? referenceX1,
    required double? referenceY1,
    required double? referenceX2,
    required double? referenceY2,
  }) {
    final labels = Int32List(width * height);
    final measurements = <Map<String, dynamic>>[];
    final mmPerPixel = (referencePixels != null &&
            referencePixels > 0 &&
            referenceMm != null &&
            referenceMm > 0)
        ? referenceMm / (referencePixels * scale)
        : 0.0;
    var excludedReferenceObjectCount = 0;
    final hasReferenceLine = referenceX1 != null &&
        referenceY1 != null &&
        referenceX2 != null &&
        referenceY2 != null &&
        (referenceX1 != referenceX2 || referenceY1 != referenceY2);
    final processedLine = hasReferenceLine
        ? (
            _Point(referenceX1 * scale, referenceY1 * scale),
            _Point(referenceX2 * scale, referenceY2 * scale),
          )
        : null;
    final imageArea = width * height;
    final candidates = <_MeasurementCandidate>[];
    instances.sort((a, b) => b.confidence.compareTo(a.confidence));
    for (final instance in instances) {
      if (!_isMeasurementCandidateInstance(instance)) continue;
      if (processedLine != null &&
          _isReferenceObjectMask(
            instance,
            width,
            height,
            processedLine.$1,
            processedLine.$2,
          )) {
        excludedReferenceObjectCount++;
        continue;
      }
      final metrics = _maskMetrics(
        instance.mask,
        instance.width,
        instance.height,
        offsetX: instance.x,
        offsetY: instance.y,
      );
      if (metrics == null) continue;
      final color = _maskColorMetrics(
        rgb,
        instance.mask,
        instance.width,
        instance.height,
        offsetX: instance.x,
        offsetY: instance.y,
      );
      if (!_passesCandidateFilter(
        instance.confidence,
        metrics,
        color,
        imageArea,
        width,
        height,
        null,
        source: instance.source,
      )) {
        continue;
      }
      candidates.add(_MeasurementCandidate(instance, metrics, color));
    }

    var sizeReference = _sizeReferenceFor(candidates);
    final fragmentMerge = _mergeFragmentCandidates(
      candidates,
      rgb,
      sizeReference,
      imageArea,
      width,
      height,
    );
    sizeReference =
        _sizeReferenceFor(fragmentMerge.candidates) ?? sizeReference;
    final splitCandidates =
        _splitMergedCandidates(fragmentMerge.candidates, rgb, sizeReference);
    sizeReference = _sizeReferenceFor(splitCandidates) ?? sizeReference;
    final markerReference =
        sizeReference ?? _sizeReferenceFor(splitCandidates, minCandidates: 3);
    final suggestedReference = _suggestedReferenceLine(
      splitCandidates,
      imageArea,
      width,
      height,
      markerReference,
      scale,
    );
    final satelliteFragmentIndices =
        _satelliteFragmentIndices(splitCandidates, sizeReference);
    var autoExcludedNonSeedCount = 0;
    final selected = <_MeasurementCandidate>[];
    for (var i = 0; i < splitCandidates.length; i++) {
      final candidate = splitCandidates[i];
      final excluded = satelliteFragmentIndices.contains(i) ||
          _isImplausibleReferenceSeedCandidate(
            candidate.instance,
            candidate.metrics,
            sizeReference,
          ) ||
          _isAdaptiveNonSeedArtifact(
            candidate.metrics,
            candidate.color,
            imageArea,
            width,
            height,
            markerReference,
          ) ||
          _isTinyDimensionFragment(
            candidate.instance.confidence,
            candidate.metrics,
            sizeReference,
            source: candidate.instance.source,
          ) ||
          _isTileEdgeFragment(
            candidate.instance.source,
            candidate.instance.confidence,
            candidate.metrics,
            sizeReference,
          ) ||
          _looksLikeSeedShadow(
              candidate.metrics, candidate.color, sizeReference) ||
          _looksLikeDarkBackgroundArtifact(
            candidate.instance.confidence,
            candidate.metrics,
            candidate.color,
            sizeReference,
          );
      if (excluded) {
        autoExcludedNonSeedCount++;
        continue;
      }
      if (_passesCandidateFilter(
            candidate.instance.confidence,
            candidate.metrics,
            candidate.color,
            imageArea,
            width,
            height,
            sizeReference,
            source: candidate.instance.source,
          ) &&
          !_isAdaptiveNonSeedArtifact(
            candidate.metrics,
            candidate.color,
            imageArea,
            width,
            height,
            markerReference,
          )) {
        selected.add(candidate);
      }
    }
    selected.sort((a, b) => b.priority.compareTo(a.priority));

    var acceptedRefClassSeedCount = 0;
    for (final candidate in selected) {
      final instance = candidate.instance;
      final available = Uint8List(instance.width * instance.height);
      for (var localY = 0; localY < instance.height; localY++) {
        final globalRow = (instance.y + localY) * width + instance.x;
        final localRow = localY * instance.width;
        for (var localX = 0; localX < instance.width; localX++) {
          final localIndex = localRow + localX;
          final globalIndex = globalRow + localX;
          if (instance.mask[localIndex] != 0 && labels[globalIndex] == 0) {
            available[localIndex] = 1;
          }
        }
      }
      final metrics = _maskMetrics(
        available,
        instance.width,
        instance.height,
        offsetX: instance.x,
        offsetY: instance.y,
      );
      if (metrics == null) continue;
      final color = _maskColorMetrics(
        rgb,
        available,
        instance.width,
        instance.height,
        offsetX: instance.x,
        offsetY: instance.y,
      );
      if (!_passesCandidateFilter(
        instance.confidence,
        metrics,
        color,
        imageArea,
        width,
        height,
        sizeReference,
        source: instance.source,
      )) {
        continue;
      }
      if (_isAdaptiveNonSeedArtifact(
        metrics,
        color,
        imageArea,
        width,
        height,
        markerReference,
      )) {
        autoExcludedNonSeedCount++;
        continue;
      }
      if (_isImplausibleReferenceSeedCandidate(
        instance,
        metrics,
        sizeReference,
      )) {
        autoExcludedNonSeedCount++;
        continue;
      }
      if (_isAvailableSatelliteFragment(
        metrics,
        color,
        measurements,
        sizeReference,
      )) {
        autoExcludedNonSeedCount++;
        continue;
      }
      final area = metrics['area_px'] as int;
      final id = measurements.length + 1;
      if (_isReferenceClassInstance(instance)) {
        acceptedRefClassSeedCount++;
      }
      for (var localY = 0; localY < instance.height; localY++) {
        final globalRow = (instance.y + localY) * width + instance.x;
        final localRow = localY * instance.width;
        for (var localX = 0; localX < instance.width; localX++) {
          if (available[localRow + localX] != 0) {
            labels[globalRow + localX] = id;
          }
        }
      }
      measurements.add({
        'id': id,
        ...metrics,
        'area_mm2':
            mmPerPixel == 0 ? null : _round(area * mmPerPixel * mmPerPixel, 6),
        'length_mm': mmPerPixel == 0
            ? null
            : _round((metrics['length_px'] as double) * mmPerPixel, 6),
        'width_mm': mmPerPixel == 0
            ? null
            : _round((metrics['width_px'] as double) * mmPerPixel, 6),
        'confidence': _round(instance.confidence, 6),
        'class_id': 0,
        'class_name': 'seed',
        'detected_class_id': instance.classId,
        'detected_class_name':
            _isReferenceClassInstance(instance) ? 'Ref' : 'seed',
        'quality_flags': _measurementQualityFlags(
          metrics,
          instance,
          width,
          height,
        ),
      });
    }
    return _FilteredResult(
      labels: labels,
      measurements: measurements,
      mmPerPixel: mmPerPixel,
      width: width,
      height: height,
      excludedReferenceObjectCount: excludedReferenceObjectCount,
      acceptedRefClassSeedCount: acceptedRefClassSeedCount,
      autoExcludedNonSeedCount: autoExcludedNonSeedCount,
      fragmentMergeCount: fragmentMerge.mergeCount,
      suggestedReference: suggestedReference,
    );
  }

  static Map<String, dynamic>? _maskMetrics(
    Uint8List mask,
    int width,
    int height, {
    required int offsetX,
    required int offsetY,
  }) {
    final points = <_Point>[];
    var sumX = 0.0;
    var sumY = 0.0;
    var minX = width + offsetX;
    var minY = height + offsetY;
    var maxX = -1;
    var maxY = -1;
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        if (mask[y * width + x] == 0) continue;
        final globalX = x + offsetX;
        final globalY = y + offsetY;
        points.add(_Point(globalX.toDouble(), globalY.toDouble()));
        sumX += globalX;
        sumY += globalY;
        minX = math.min(minX, globalX);
        minY = math.min(minY, globalY);
        maxX = math.max(maxX, globalX);
        maxY = math.max(maxY, globalY);
      }
    }
    if (points.isEmpty) return null;
    final hull = _convexHull(points);
    final hullArea = math.max(_polygonArea(hull), 1.0);
    final feret = _feretShapeMetrics(hull, points);
    final bboxWidth = maxX - minX + 1;
    final bboxHeight = maxY - minY + 1;
    final area = points.length;
    final solidity = math.min(area / hullArea, 1.0);
    return {
      'area_px': area,
      'length_px': _round(feret.length, 3),
      'width_px': _round(feret.width, 3),
      'centroid_x': _round(sumX / area, 3),
      'centroid_y': _round(sumY / area, 3),
      'bbox_x': minX,
      'bbox_y': minY,
      'bbox_w': bboxWidth,
      'bbox_h': bboxHeight,
      'angle_deg': _round(feret.angleDegrees, 3),
      'solidity': _round(solidity, 6),
      'extent': _round(area / math.max(bboxWidth * bboxHeight, 1), 6),
      'aspect_ratio': _round(feret.length / feret.width, 6),
      'measurement_method': 'smartgrain_feret_chord',
    };
  }

  static String _measurementQualityFlags(
    Map<String, dynamic> metrics,
    _Instance instance,
    int imageWidth,
    int imageHeight,
  ) {
    final flags = <String>[];
    if (_isReferenceClassInstance(instance)) {
      flags.add('model_label_ref_as_seed');
    }
    if (instance.confidence < 0.16) {
      flags.add('low_confidence');
    }
    final solidity = (metrics['solidity'] as num?)?.toDouble() ?? 1.0;
    final extent = (metrics['extent'] as num?)?.toDouble() ?? 1.0;
    final aspect = (metrics['aspect_ratio'] as num?)?.toDouble() ?? 1.0;
    final minExtent = aspect >= 3.2 ? 0.24 : (aspect >= 2.2 ? 0.28 : 0.35);
    if (solidity < 0.72 || extent < minExtent) {
      flags.add('loose_mask');
    }
    if (_isTileEdgeSource(instance.source) &&
        instance.confidence < 0.16 &&
        extent < 0.45) {
      flags.add('partial_tile_mask');
    }
    if (aspect > 8.0) {
      flags.add('extreme_aspect');
    }
    final x = (metrics['bbox_x'] as num?)?.toInt() ?? 0;
    final y = (metrics['bbox_y'] as num?)?.toInt() ?? 0;
    final width = (metrics['bbox_w'] as num?)?.toInt() ?? 0;
    final height = (metrics['bbox_h'] as num?)?.toInt() ?? 0;
    if (x <= 1 ||
        y <= 1 ||
        x + width >= imageWidth - 1 ||
        y + height >= imageHeight - 1) {
      flags.add('touches_image_edge');
    }
    return flags.join(',');
  }

  static img.Image _renderOverlay(img.Image rgb, _FilteredResult result) {
    final overlay = img.Image.from(rgb);
    final outlierIds = _outlierIds(result.measurements);
    for (var y = 0; y < result.height; y++) {
      for (var x = 0; x < result.width; x++) {
        final label = result.labels[y * result.width + x];
        if (label <= 0) continue;
        final color = outlierIds.contains(label)
            ? const [220, 38, 38]
            : const [37, 99, 235];
        final isEdge = _isLabelEdge(
            result.labels, result.width, result.height, x, y, label);
        final fillOpacity = isEdge ? 0.56 : 0.34;
        final source = overlay.getPixel(x, y);
        overlay.setPixelRgb(
          x,
          y,
          (source.r * (1 - fillOpacity) + color[0] * fillOpacity).round(),
          (source.g * (1 - fillOpacity) + color[1] * fillOpacity).round(),
          (source.b * (1 - fillOpacity) + color[2] * fillOpacity).round(),
        );
      }
    }
    return overlay;
  }

  static img.Image _renderMask(_FilteredResult result) {
    final mask = img.Image(
      width: result.width,
      height: result.height,
      numChannels: 4,
    );
    final outlierIds = _outlierIds(result.measurements);
    for (var y = 0; y < result.height; y++) {
      for (var x = 0; x < result.width; x++) {
        final label = result.labels[y * result.width + x];
        if (label <= 0) {
          mask.setPixelRgba(x, y, 0, 0, 0, 0);
          continue;
        }
        final isOutlier = outlierIds.contains(label);
        final isEdge = _isLabelEdge(
            result.labels, result.width, result.height, x, y, label);
        if (isEdge) {
          final edgeColor =
              isOutlier ? const [185, 28, 28] : const [30, 64, 175];
          mask.setPixelRgba(
              x, y, edgeColor[0], edgeColor[1], edgeColor[2], 255);
          continue;
        }
        final fillColor =
            isOutlier ? const [239, 68, 68] : const [59, 130, 246];
        final alpha = isOutlier ? 170 : 145;
        mask.setPixelRgba(
            x, y, fillColor[0], fillColor[1], fillColor[2], alpha);
      }
    }
    return mask;
  }

  static img.Image _renderLabelMap(_FilteredResult result) {
    final labelMap = img.Image(
      width: result.width,
      height: result.height,
      numChannels: 3,
    );
    for (var y = 0; y < result.height; y++) {
      for (var x = 0; x < result.width; x++) {
        final label = result.labels[y * result.width + x];
        labelMap.setPixelRgb(
          x,
          y,
          label & 0xFF,
          (label >> 8) & 0xFF,
          (label >> 16) & 0xFF,
        );
      }
    }
    return labelMap;
  }

  static _PreviewRenderInput _previewRenderInput(
    img.Image processed,
    _FilteredResult filtered,
    _OfflineModelProfile profile,
  ) {
    final maxSide = profile.previewMaxSide;
    final longestSide = math.max(filtered.width, filtered.height);
    if (maxSide <= 0 || longestSide <= maxSide) {
      return _PreviewRenderInput(
        rgb: processed,
        result: filtered,
        coordinateScaleX: 1,
        coordinateScaleY: 1,
      );
    }
    final scale = maxSide / longestSide;
    final previewWidth = math.max(1, (filtered.width * scale).round());
    final previewHeight = math.max(1, (filtered.height * scale).round());
    final resizedRgb = img.copyResize(
      processed,
      width: previewWidth,
      height: previewHeight,
      interpolation: img.Interpolation.linear,
    );
    final resizedLabels = _resizeLabelsNearest(
      filtered.labels,
      filtered.width,
      filtered.height,
      previewWidth,
      previewHeight,
    );
    return _PreviewRenderInput(
      rgb: resizedRgb,
      result: _FilteredResult(
        labels: resizedLabels,
        measurements: filtered.measurements,
        mmPerPixel: filtered.mmPerPixel,
        width: previewWidth,
        height: previewHeight,
        excludedReferenceObjectCount: filtered.excludedReferenceObjectCount,
        acceptedRefClassSeedCount: filtered.acceptedRefClassSeedCount,
        autoExcludedNonSeedCount: filtered.autoExcludedNonSeedCount,
        fragmentMergeCount: filtered.fragmentMergeCount,
        suggestedReference: filtered.suggestedReference,
      ),
      coordinateScaleX: previewWidth / filtered.width,
      coordinateScaleY: previewHeight / filtered.height,
    );
  }

  static Int32List _resizeLabelsNearest(
    Int32List labels,
    int sourceWidth,
    int sourceHeight,
    int targetWidth,
    int targetHeight,
  ) {
    final resized = Int32List(targetWidth * targetHeight);
    for (var y = 0; y < targetHeight; y++) {
      final sourceY = ((y + 0.5) * sourceHeight / targetHeight).floor().clamp(
            0,
            sourceHeight - 1,
          );
      for (var x = 0; x < targetWidth; x++) {
        final sourceX = ((x + 0.5) * sourceWidth / targetWidth).floor().clamp(
              0,
              sourceWidth - 1,
            );
        resized[y * targetWidth + x] = labels[sourceY * sourceWidth + sourceX];
      }
    }
    return resized;
  }

  static Set<int> _outlierIds(List<Map<String, dynamic>> measurements) {
    return {
      for (final measurement in measurements)
        if (measurement['qc_outlier'] == true)
          ((measurement['id'] as num?)?.toInt() ?? -1),
    }..remove(-1);
  }

  static bool _isSeedClassInstance(_Instance instance) => instance.classId == 0;

  static bool _isReferenceClassInstance(_Instance instance) =>
      instance.classId == 1;

  static bool _isMeasurementCandidateInstance(_Instance instance) =>
      _isSeedClassInstance(instance) || _isReferenceClassInstance(instance);

  static bool _passesConfidenceAwareShapeFilter(
    double confidence,
    Map<String, dynamic> metrics,
  ) {
    final solidity = (metrics['solidity'] as num).toDouble();
    final extent = (metrics['extent'] as num).toDouble();
    final aspect = (metrics['aspect_ratio'] as num).toDouble();
    if (confidence >= 0.18) {
      return solidity >= 0.5 && extent >= 0.2 && aspect <= 10.5;
    }
    if (confidence >= 0.12) {
      return solidity >= 0.48 && extent >= 0.22 && aspect <= 12.0;
    }
    if (confidence >= 0.08) {
      return solidity >= 0.56 && extent >= 0.25 && aspect <= 10.0;
    }
    return solidity >= 0.62 && extent >= 0.30 && aspect <= 8.0;
  }

  static bool _passesCandidateFilter(
    double confidence,
    Map<String, dynamic> metrics,
    _MaskColorMetrics color,
    int imageArea,
    int imageWidth,
    int imageHeight,
    _SizeReference? sizeReference, {
    String source = '',
  }) {
    final area = metrics['area_px'] as int;
    final aspect = (metrics['aspect_ratio'] as num).toDouble();
    final solidity = (metrics['solidity'] as num).toDouble();
    final extent = (metrics['extent'] as num).toDouble();
    if (area < _minArea || area > _maxArea) return false;
    if (aspect > _maxAspectRatio) return false;
    if (solidity < _minSolidity || extent < _minExtent) return false;
    if (!_passesConfidenceAwareShapeFilter(confidence, metrics)) return false;
    if (_looksLikeLargeSkinObject(area, imageArea, color, sizeReference) &&
        !_couldBeReferenceMarkerWithoutSize(metrics, imageArea)) {
      return false;
    }
    if (_isAdaptiveNonSeedArtifact(
      metrics,
      color,
      imageArea,
      imageWidth,
      imageHeight,
      sizeReference,
    )) {
      return false;
    }
    if (_isTileEdgeFragment(source, confidence, metrics, sizeReference)) {
      return false;
    }
    if (_isTinyDimensionFragment(
      confidence,
      metrics,
      sizeReference,
      source: source,
    )) {
      return false;
    }
    if (_looksLikeSeedShadow(metrics, color, sizeReference)) return false;
    if (_looksLikeDarkBackgroundArtifact(
      confidence,
      metrics,
      color,
      sizeReference,
    )) {
      return false;
    }
    if (_isDynamicNonSeedSize(metrics, color, imageArea, sizeReference)) {
      return false;
    }
    if (_isLowConfidenceReferenceFragment(
      confidence,
      metrics,
      sizeReference,
    )) {
      return false;
    }
    if (_isLowConfidenceOversize(confidence, metrics, sizeReference)) {
      return false;
    }
    return true;
  }

  static bool _isAdaptiveNonSeedArtifact(
    Map<String, dynamic> metrics,
    _MaskColorMetrics color,
    int imageArea,
    int imageWidth,
    int imageHeight,
    _SizeReference? reference,
  ) {
    if (reference == null) return false;
    if (_isPartialBorderArtifact(metrics, imageWidth, imageHeight, reference)) {
      return true;
    }
    if (_looksLikeReferenceMarker(metrics, imageArea, reference)) {
      return true;
    }
    if (_looksLikeNeutralReferenceFragment(
      metrics,
      color,
      imageArea,
      reference,
    )) {
      return true;
    }
    return false;
  }

  static bool _isPartialBorderArtifact(
    Map<String, dynamic> metrics,
    int imageWidth,
    int imageHeight,
    _SizeReference reference,
  ) {
    final area = (metrics['area_px'] as num).toDouble();
    if (area >= reference.area * 0.75) return false;
    final x = (metrics['bbox_x'] as num).toInt();
    final y = (metrics['bbox_y'] as num).toInt();
    final width = (metrics['bbox_w'] as num).toInt();
    final height = (metrics['bbox_h'] as num).toInt();
    return x <= 1 ||
        y <= 1 ||
        x + width >= imageWidth - 1 ||
        y + height >= imageHeight - 1;
  }

  static bool _looksLikeReferenceMarker(
    Map<String, dynamic> metrics,
    int imageArea,
    _SizeReference reference,
  ) {
    final area = (metrics['area_px'] as num).toDouble();
    final length = (metrics['length_px'] as num).toDouble();
    final width = (metrics['width_px'] as num).toDouble();
    final aspect = (metrics['aspect_ratio'] as num).toDouble();
    final solidity = (metrics['solidity'] as num).toDouble();
    final extent = (metrics['extent'] as num).toDouble();
    final areaRatio = area / math.max(reference.area, 1.0);
    final lengthRatio = length / math.max(reference.length, 1.0);
    final widthRatio = width / math.max(reference.width, 1.0);
    final markerAreaFloor =
        math.max(reference.areaSplitUpper, reference.area * 2.8);
    final axesAreLarge =
        areaRatio >= 3.0 && lengthRatio >= 1.35 && widthRatio >= 1.35;
    final roundOversize =
        areaRatio >= 2.8 && aspect <= 1.85 && widthRatio >= 1.65;
    final roundAndSolid = aspect <= 1.75 && solidity >= 0.88 && extent >= 0.45;
    final notMostOfImage = area / math.max(imageArea, 1) <= 0.12;
    return area >= markerAreaFloor &&
        (axesAreLarge || roundOversize) &&
        roundAndSolid &&
        notMostOfImage;
  }

  static bool _looksLikeNeutralReferenceFragment(
    Map<String, dynamic> metrics,
    _MaskColorMetrics color,
    int imageArea,
    _SizeReference reference,
  ) {
    final area = (metrics['area_px'] as num).toDouble();
    final length = (metrics['length_px'] as num).toDouble();
    final width = (metrics['width_px'] as num).toDouble();
    final aspect = (metrics['aspect_ratio'] as num).toDouble();
    final solidity = (metrics['solidity'] as num).toDouble();
    final extent = (metrics['extent'] as num).toDouble();
    final areaRatio = area / math.max(reference.area, 1.0);
    final lengthRatio = length / math.max(reference.length, 1.0);
    final widthRatio = width / math.max(reference.width, 1.0);

    if (area / math.max(imageArea, 1) > 0.12) return false;
    if (areaRatio < 3.2) return false;
    if (solidity < 0.82 || extent < 0.48) return false;
    final neutralSurface = color.neutralRatio >= 0.72 || color.chroma <= 24.0;
    final brightOrMetal = color.luma >= 135.0 || color.neutralRatio >= 0.92;
    if (!(neutralSurface && brightOrMetal)) return false;

    final broadFragment =
        lengthRatio >= 1.75 && widthRatio >= 1.55 && aspect <= 4.2;
    final roundFragment = widthRatio >= 1.85 && aspect <= 1.55;
    return broadFragment || roundFragment;
  }

  static Map<String, dynamic>? _suggestedReferenceLine(
    List<_MeasurementCandidate> candidates,
    int imageArea,
    int imageWidth,
    int imageHeight,
    _SizeReference? reference,
    double scale,
  ) {
    if (reference == null) return null;
    final markerCandidates = candidates
        .where(
          (candidate) =>
              !_isPartialBorderArtifact(
                candidate.metrics,
                imageWidth,
                imageHeight,
                reference,
              ) &&
              _looksLikeReferenceMarker(
                candidate.metrics,
                imageArea,
                reference,
              ) &&
              _isSuggestableReferenceMarker(
                candidate,
                imageArea,
              ),
        )
        .toList();
    if (markerCandidates.isEmpty) return null;
    markerCandidates.sort(
      (a, b) =>
          _referenceMarkerPriority(b).compareTo(_referenceMarkerPriority(a)),
    );
    return _referenceLineFromCandidate(
      markerCandidates.first,
      imageWidth,
      imageHeight,
      scale,
    );
  }

  static double _referenceMarkerPriority(_MeasurementCandidate candidate) {
    final area =
        ((candidate.metrics['area_px'] as num?)?.toDouble() ?? 1).clamp(1, 1e9);
    final refBonus = _isReferenceClassInstance(candidate.instance) ? 1.0 : 0.0;
    return refBonus + candidate.instance.confidence + math.log(area) / 20;
  }

  static bool _isSuggestableReferenceMarker(
    _MeasurementCandidate candidate,
    int imageArea,
  ) {
    if (_isReferenceClassInstance(candidate.instance)) return true;
    final area = ((candidate.metrics['area_px'] as num?)?.toDouble() ?? 0.0);
    if (area / math.max(imageArea, 1) > 0.08) return false;
    if (candidate.color.neutralRatio >= 0.85 && candidate.color.luma >= 225.0) {
      return false;
    }
    return true;
  }

  static Map<String, dynamic>? _referenceLineFromCandidate(
    _MeasurementCandidate candidate,
    int imageWidth,
    int imageHeight,
    double scale,
  ) {
    final instance = candidate.instance;
    final metrics = candidate.metrics;
    final centerX = (metrics['centroid_x'] as num).toDouble();
    final centerY = (metrics['centroid_y'] as num).toDouble();
    var covXx = 0.0;
    var covXy = 0.0;
    var covYy = 0.0;
    var count = 0;
    for (var localY = 0; localY < instance.height; localY++) {
      final row = localY * instance.width;
      for (var localX = 0; localX < instance.width; localX++) {
        if (instance.mask[row + localX] == 0) continue;
        final dx = instance.x + localX - centerX;
        final dy = instance.y + localY - centerY;
        covXx += dx * dx;
        covXy += dx * dy;
        covYy += dy * dy;
        count++;
      }
    }
    if (count < 2) return null;
    final angle = 0.5 * math.atan2(2 * covXy, covXx - covYy);
    var axisX = math.cos(angle);
    var axisY = math.sin(angle);
    if (!axisX.isFinite || !axisY.isFinite) {
      axisX = 1;
      axisY = 0;
    }
    final halfLength =
        math.max((metrics['length_px'] as num).toDouble(), 2.0) / 2;
    final maxX = math.max(imageWidth.toDouble() - 1, 0.0);
    final maxY = math.max(imageHeight.toDouble() - 1, 0.0);
    final x1 = (centerX - axisX * halfLength).clamp(0.0, maxX).toDouble();
    final y1 = (centerY - axisY * halfLength).clamp(0.0, maxY).toDouble();
    final x2 = (centerX + axisX * halfLength).clamp(0.0, maxX).toDouble();
    final y2 = (centerY + axisY * halfLength).clamp(0.0, maxY).toDouble();
    final processedPixels = math.sqrt(
      math.pow(x2 - x1, 2).toDouble() + math.pow(y2 - y1, 2).toDouble(),
    );
    if (processedPixels <= 1) return null;
    final safeScale = scale > 1e-6 ? scale : 1.0;
    return {
      'available': true,
      'source': 'detected_ref',
      'pixel_space': 'original',
      'x1': _round(x1 / safeScale, 3),
      'y1': _round(y1 / safeScale, 3),
      'x2': _round(x2 / safeScale, 3),
      'y2': _round(y2 / safeScale, 3),
      'pixels': _round(processedPixels / safeScale, 3),
      'processed': {
        'x1': _round(x1, 3),
        'y1': _round(y1, 3),
        'x2': _round(x2, 3),
        'y2': _round(y2, 3),
        'pixels': _round(processedPixels, 3),
      },
      'confidence': _round(instance.confidence, 6),
      'class_id': 1,
      'class_name': 'Ref',
      'detected_class_id': instance.classId,
      'detected_class_name':
          _isReferenceClassInstance(instance) ? 'Ref' : 'seed',
    };
  }

  static bool _looksLikeLargeSkinObject(
    int area,
    int imageArea,
    _MaskColorMetrics color,
    _SizeReference? reference,
  ) {
    final referenceArea = reference?.area ?? 0;
    final largeSkinFloor = [
      1800.0,
      imageArea * 0.018,
      referenceArea * 4.0,
    ].reduce(math.max);
    final strongSkinFloor = [
      1000.0,
      imageArea * 0.012,
      referenceArea * 3.0,
    ].reduce(math.max);
    if (color.skinRatio >= _skinRejectRatio && area >= largeSkinFloor) {
      return true;
    }
    if (color.skinRatio >= _strongSkinRejectRatio && area >= strongSkinFloor) {
      return true;
    }
    return false;
  }

  static bool _couldBeReferenceMarkerWithoutSize(
    Map<String, dynamic> metrics,
    int imageArea,
  ) {
    final area = (metrics['area_px'] as num).toDouble();
    final aspect = (metrics['aspect_ratio'] as num).toDouble();
    final solidity = (metrics['solidity'] as num).toDouble();
    final extent = (metrics['extent'] as num).toDouble();
    if (area / math.max(imageArea, 1) > 0.12) return false;
    return area >= math.max(1200.0, imageArea * 0.008) &&
        aspect <= 1.9 &&
        solidity >= 0.86 &&
        extent >= 0.44;
  }

  static bool _isDynamicNonSeedSize(
    Map<String, dynamic> metrics,
    _MaskColorMetrics color,
    int imageArea,
    _SizeReference? reference,
  ) {
    if (reference == null) return false;
    final area = (metrics['area_px'] as num).toDouble();
    final tooLarge = area > reference.areaUpper;
    final coversImage = area / math.max(imageArea, 1) > 0.08;
    return tooLarge && coversImage;
  }

  static bool _isLowConfidenceOversize(
    double confidence,
    Map<String, dynamic> metrics,
    _SizeReference? reference,
  ) {
    if (reference == null || confidence >= 0.08) return false;
    return (metrics['area_px'] as num).toDouble() > reference.area * 1.65;
  }

  static bool _isLowConfidenceReferenceFragment(
    double confidence,
    Map<String, dynamic> metrics,
    _SizeReference? reference,
  ) {
    if (reference == null || confidence >= 0.24) return false;
    final area = (metrics['area_px'] as num).toDouble();
    final length = (metrics['length_px'] as num).toDouble();
    final width = (metrics['width_px'] as num).toDouble();
    final aspect = (metrics['aspect_ratio'] as num).toDouble();
    final refArea = math.max(reference.area, 1.0);
    final refLength = math.max(reference.length, 1.0);
    final refWidth = math.max(reference.width, 1.0);
    if (refLength / refWidth < 1.45) return false;
    final areaLarge = area >= refArea * 1.32;
    final axesLarge = length >= refLength * 1.22 && width >= refWidth * 1.18;
    final roundOversize = aspect <= 1.38 && width >= refWidth * 1.22;
    return areaLarge && (axesLarge || roundOversize);
  }

  static bool _looksLikeSeedShadow(
    Map<String, dynamic> metrics,
    _MaskColorMetrics color,
    _SizeReference? reference,
  ) {
    if (reference == null) return false;
    if (reference.chroma < 24.0 && reference.neutralRatio > 0.70) {
      return false;
    }
    final area = (metrics['area_px'] as num).toDouble();
    final areaRatio = area / math.max(reference.area, 1.0);
    if (areaRatio < 0.12 || areaRatio > 2.6) return false;

    final lowColor = color.neutralRatio >= 0.86 &&
        color.chroma <= math.max(18.0, reference.chroma * 0.46);
    final brighterThanSeed = color.luma >= reference.luma + 24.0;
    final veryNeutral = color.neutralRatio >= 0.96 && color.chroma <= 14.0;
    return lowColor && (brighterThanSeed || veryNeutral);
  }

  static bool _looksLikeDarkBackgroundArtifact(
    double confidence,
    Map<String, dynamic> metrics,
    _MaskColorMetrics color,
    _SizeReference? reference,
  ) {
    if (reference == null) return false;
    if (reference.luma < 145.0) return false;
    final areaRatio =
        (metrics['area_px'] as num).toDouble() / math.max(reference.area, 1.0);
    if (areaRatio < 0.10 || areaRatio > 2.6) return false;

    final muchDarker =
        color.luma <= reference.luma - math.max(42.0, reference.luma * 0.24);
    final woodLike = color.skinRatio >= 0.72 &&
        color.chroma >= math.max(40.0, reference.chroma * 0.48) &&
        color.neutralRatio <= 0.28;
    final lowConfDark = confidence < 0.12 &&
        color.luma <= reference.luma - 75.0 &&
        color.neutralRatio <= 0.45;
    return muchDarker && (woodLike || lowConfDark);
  }

  static Set<int> _satelliteFragmentIndices(
    List<_MeasurementCandidate> candidates,
    _SizeReference? reference,
  ) {
    if (reference == null || candidates.length < 2) return <int>{};
    final refArea = math.max(reference.area, 1.0);
    final refLength = math.max(reference.length, 1.0);
    final refWidth = math.max(reference.width, 1.0);
    final refAspect = refLength / refWidth;
    if (refAspect >= 2.25) return <int>{};
    final maxGap = math.max(3.0, refWidth * 0.38);
    final maxCenterDistance = math.max(refLength * 0.82, refWidth * 2.2);
    final anchors = <int, _MeasurementCandidate>{};
    for (var i = 0; i < candidates.length; i++) {
      if ((candidates[i].metrics['area_px'] as num).toDouble() >=
          refArea * 0.55) {
        anchors[i] = candidates[i];
      }
    }
    final result = <int>{};
    for (var i = 0; i < candidates.length; i++) {
      final candidate = candidates[i];
      final area = (candidate.metrics['area_px'] as num).toDouble();
      final areaRatio = area / refArea;
      final looksLikeShadow =
          _looksLikeSeedShadow(candidate.metrics, candidate.color, reference);
      final tinyFragment = refAspect < 1.65
          ? areaRatio <= 0.24
          : areaRatio <= 0.30 &&
              (((candidate.metrics['width_px'] as num).toDouble() / refWidth) <=
                      0.55 ||
                  ((candidate.metrics['length_px'] as num).toDouble() /
                          refLength) <=
                      0.72);
      final smallSuspicious = areaRatio <= 0.40 &&
          (looksLikeShadow || candidate.instance.confidence < 0.12);
      if (!(tinyFragment || smallSuspicious)) continue;
      if ((candidate.metrics['length_px'] as num).toDouble() >
              refLength * 0.88 &&
          (candidate.metrics['width_px'] as num).toDouble() > refWidth * 0.75) {
        continue;
      }
      for (final entry in anchors.entries) {
        if (entry.key == i) continue;
        final anchorMetrics = entry.value.metrics;
        final anchorArea = (anchorMetrics['area_px'] as num).toDouble();
        if (anchorArea < math.max(refArea * 0.55, area * 1.8)) continue;
        if (_bboxGap(candidate.metrics, anchorMetrics) > maxGap) continue;
        if (_centerDistance(candidate.metrics, anchorMetrics) >
            maxCenterDistance) {
          continue;
        }
        if (_combinedBBoxTooLarge(
          candidate.metrics,
          anchorMetrics,
          refLength,
          refWidth,
        )) {
          continue;
        }
        result.add(i);
        break;
      }
    }
    return result;
  }

  static bool _isAvailableSatelliteFragment(
    Map<String, dynamic> metrics,
    _MaskColorMetrics color,
    List<Map<String, dynamic>> measurements,
    _SizeReference? reference,
  ) {
    if (reference == null || measurements.isEmpty) return false;
    final refArea = math.max(reference.area, 1.0);
    final refLength = math.max(reference.length, 1.0);
    final refWidth = math.max(reference.width, 1.0);
    if (refLength / refWidth >= 1.65) return false;
    final areaRatio = (metrics['area_px'] as num).toDouble() / refArea;
    if (areaRatio > 0.30) return false;
    if (!_looksLikeSeedShadow(metrics, color, reference) &&
        (metrics['length_px'] as num).toDouble() > refLength * 0.70) {
      return false;
    }
    final maxGap = math.max(3.0, refWidth * 0.38);
    final maxCenterDistance = math.max(refLength * 0.82, refWidth * 2.2);
    for (final measurement in measurements) {
      final measurementArea =
          (measurement['area_px'] as num?)?.toDouble() ?? 0.0;
      if (measurementArea < refArea * 0.55) {
        continue;
      }
      if (_bboxGap(metrics, measurement) <= maxGap &&
          _centerDistance(metrics, measurement) <= maxCenterDistance) {
        return true;
      }
    }
    return false;
  }

  static bool _isTileEdgeSource(String source) {
    final value = source.trim().toLowerCase();
    return value.contains('tile') && value.contains('edge');
  }

  static bool _isTileEdgeFragment(
    String source,
    double confidence,
    Map<String, dynamic> metrics,
    _SizeReference? reference,
  ) {
    if (!_isTileEdgeSource(source)) return false;
    final width = (metrics['width_px'] as num).toDouble();
    if (reference == null) return confidence < 0.10 && width <= 8.0;
    final areaRatio =
        (metrics['area_px'] as num).toDouble() / math.max(reference.area, 1.0);
    final lengthRatio = (metrics['length_px'] as num).toDouble() /
        math.max(reference.length, 1.0);
    final widthRatio = width / math.max(reference.width, 1.0);
    final refAspect = reference.length / math.max(reference.width, 1.0);

    if (areaRatio <= 0.24 && (widthRatio <= 0.75 || lengthRatio <= 0.90)) {
      return true;
    }
    if (refAspect < 2.35 &&
        areaRatio <= 0.34 &&
        widthRatio <= 0.62 &&
        lengthRatio <= 0.78) {
      return true;
    }
    if (confidence < 0.16 &&
        areaRatio <= 0.70 &&
        (widthRatio <= 0.72 || lengthRatio <= 0.82)) {
      return true;
    }
    return false;
  }

  static bool _isTinyDimensionFragment(
    double confidence,
    Map<String, dynamic> metrics,
    _SizeReference? reference, {
    String source = '',
  }) {
    if (reference == null) return false;
    final areaRatio =
        (metrics['area_px'] as num).toDouble() / math.max(reference.area, 1.0);
    final lengthRatio = (metrics['length_px'] as num).toDouble() /
        math.max(reference.length, 1.0);
    final widthRatio = (metrics['width_px'] as num).toDouble() /
        math.max(reference.width, 1.0);
    final refAspect = reference.length / math.max(reference.width, 1.0);

    if (refAspect < 1.65) {
      return areaRatio <= 0.38 && widthRatio <= 0.52 && lengthRatio <= 1.15;
    }

    if (refAspect < 2.25) {
      if (areaRatio <= 0.18 && (widthRatio <= 0.72 || lengthRatio <= 0.92)) {
        return true;
      }
      if (areaRatio <= 0.32 && widthRatio <= 0.60 && lengthRatio <= 0.76) {
        return true;
      }
      if (_isTileEdgeSource(source) &&
          areaRatio <= 0.38 &&
          (widthRatio <= 0.68 || lengthRatio <= 0.82)) {
        return true;
      }
      return false;
    }

    // Long crops such as rice have legitimate narrow masks, so only remove
    // very small, low-confidence stubs that are far below the local size model.
    if (confidence < 0.14) {
      return areaRatio <= 0.18 && lengthRatio <= 0.48 && widthRatio <= 0.60;
    }
    return areaRatio <= 0.11 && lengthRatio <= 0.38 && widthRatio <= 0.45;
  }

  static bool _isImplausibleReferenceSeedCandidate(
    _Instance instance,
    Map<String, dynamic> metrics,
    _SizeReference? reference,
  ) {
    if (!_isReferenceClassInstance(instance) || reference == null) {
      return false;
    }
    final areaRatio =
        (metrics['area_px'] as num).toDouble() / math.max(reference.area, 1.0);
    final lengthRatio = (metrics['length_px'] as num).toDouble() /
        math.max(reference.length, 1.0);
    final widthRatio = (metrics['width_px'] as num).toDouble() /
        math.max(reference.width, 1.0);
    final refAspect = reference.length / math.max(reference.width, 1.0);

    if (areaRatio < 0.42 || areaRatio > 2.40) return true;
    if (refAspect >= 1.65) {
      return lengthRatio < 0.62 || widthRatio < 0.48;
    }
    return lengthRatio < 0.55 || widthRatio < 0.55;
  }

  static double _bboxGap(
    Map<String, dynamic> a,
    Map<String, dynamic> b,
  ) {
    final ax1 = (a['bbox_x'] as num).toDouble();
    final ay1 = (a['bbox_y'] as num).toDouble();
    final ax2 = ax1 + (a['bbox_w'] as num).toDouble();
    final ay2 = ay1 + (a['bbox_h'] as num).toDouble();
    final bx1 = (b['bbox_x'] as num).toDouble();
    final by1 = (b['bbox_y'] as num).toDouble();
    final bx2 = bx1 + (b['bbox_w'] as num).toDouble();
    final by2 = by1 + (b['bbox_h'] as num).toDouble();
    final dx = [bx1 - ax2, ax1 - bx2, 0.0].reduce(math.max);
    final dy = [by1 - ay2, ay1 - by2, 0.0].reduce(math.max);
    return math.sqrt(dx * dx + dy * dy);
  }

  static double _centerDistance(
    Map<String, dynamic> a,
    Map<String, dynamic> b,
  ) {
    final dx = (a['centroid_x'] as num).toDouble() -
        (b['centroid_x'] as num).toDouble();
    final dy = (a['centroid_y'] as num).toDouble() -
        (b['centroid_y'] as num).toDouble();
    return math.sqrt(dx * dx + dy * dy);
  }

  static bool _combinedBBoxTooLarge(
    Map<String, dynamic> a,
    Map<String, dynamic> b,
    double refLength,
    double refWidth,
  ) {
    final x1 = math.min(
      (a['bbox_x'] as num).toDouble(),
      (b['bbox_x'] as num).toDouble(),
    );
    final y1 = math.min(
      (a['bbox_y'] as num).toDouble(),
      (b['bbox_y'] as num).toDouble(),
    );
    final x2 = math.max(
      (a['bbox_x'] as num).toDouble() + (a['bbox_w'] as num).toDouble(),
      (b['bbox_x'] as num).toDouble() + (b['bbox_w'] as num).toDouble(),
    );
    final y2 = math.max(
      (a['bbox_y'] as num).toDouble() + (a['bbox_h'] as num).toDouble(),
      (b['bbox_y'] as num).toDouble() + (b['bbox_h'] as num).toDouble(),
    );
    final spanX = x2 - x1;
    final spanY = y2 - y1;
    final diagonal = math.sqrt(spanX * spanX + spanY * spanY);
    return diagonal > math.max(refLength * 1.85, refWidth * 3.0);
  }

  static _SizeReference? _sizeReferenceFor(
    List<_MeasurementCandidate> candidates, {
    int minCandidates = _adaptiveMinCandidates,
  }) {
    final candidateFloor = math.max(3, minCandidates);
    if (candidates.length < candidateFloor) return null;
    final seedCandidates = candidates
        .where((candidate) => _isSeedClassInstance(candidate.instance))
        .toList();
    final referenceSource =
        seedCandidates.length >= candidateFloor ? seedCandidates : candidates;
    var referenceCandidates = referenceSource
        .where((candidate) => candidate.color.skinRatio < 0.35)
        .toList();
    if (referenceCandidates.length < candidateFloor) {
      referenceCandidates = referenceSource;
    }
    final areas = [
      for (final candidate in referenceCandidates)
        (candidate.metrics['area_px'] as num).toDouble(),
    ];
    final lengths = [
      for (final candidate in referenceCandidates)
        (candidate.metrics['length_px'] as num).toDouble(),
    ];
    final widths = [
      for (final candidate in referenceCandidates)
        (candidate.metrics['width_px'] as num).toDouble(),
    ];
    final aspects = [
      for (final candidate in referenceCandidates)
        (candidate.metrics['aspect_ratio'] as num).toDouble(),
    ];
    final colorCandidates =
        candidates.length >= candidateFloor ? candidates : referenceCandidates;
    final chromas = [
      for (final candidate in colorCandidates) candidate.color.chroma,
    ];
    final neutralRatios = [
      for (final candidate in colorCandidates) candidate.color.neutralRatio,
    ];
    final lumas = [
      for (final candidate in colorCandidates) candidate.color.luma,
    ];
    final areaMedian = _median(areas);
    final lengthMedian = _median(lengths);
    final widthMedian = _median(widths);
    final aspectMedian = _median(aspects);
    final chromaMedian = _median(chromas);
    final neutralRatioMedian = _median(neutralRatios);
    final lumaMedian = _median(lumas);
    return _SizeReference(
      area: areaMedian,
      length: lengthMedian,
      width: widthMedian,
      chroma: chromaMedian,
      neutralRatio: neutralRatioMedian,
      luma: lumaMedian,
      splitEnabled: aspectMedian >= 1.75 &&
          _madRatio(areas, areaMedian) <= 0.35 &&
          _madRatio(lengths, lengthMedian) <= 0.25 &&
          _madRatio(widths, widthMedian) <= 0.25,
      areaSplitUpper: _robustUpper(
        areas,
        center: areaMedian,
        z: _mergedSplitMadZ,
        minMultiplier: _mergedSplitAreaRatio,
      ),
      lengthSplitUpper: _robustUpper(
        lengths,
        center: lengthMedian,
        z: _mergedSplitMadZ,
        minMultiplier: _mergedSplitLengthRatio,
      ),
      widthSplitUpper: _robustUpper(
        widths,
        center: widthMedian,
        z: _mergedSplitMadZ,
        minMultiplier: _mergedSplitWidthRatio,
      ),
      areaUpper: _robustUpper(
        areas,
        center: areaMedian,
        z: _adaptiveMadZ,
        minMultiplier: _dynamicAreaMultiplier,
      ),
    );
  }

  static double _robustUpper(
    List<double> values, {
    required double center,
    required double z,
    required double minMultiplier,
  }) {
    if (values.isEmpty) return center * minMultiplier;
    final deviations = values.map((value) => (value - center).abs()).toList();
    final mad = _median(deviations);
    final robustSigma = math.max(1.0, 1.4826 * mad);
    return math.max(center * minMultiplier, center + z * robustSigma);
  }

  static double _madRatio(List<double> values, double center) {
    if (values.isEmpty || center <= 1e-9) return 1;
    final deviations = values.map((value) => (value - center).abs()).toList();
    return _median(deviations) / center;
  }

  static _FragmentMergeResult _mergeFragmentCandidates(
    List<_MeasurementCandidate> candidates,
    img.Image rgb,
    _SizeReference? reference,
    int imageArea,
    int imageWidth,
    int imageHeight,
  ) {
    if (!_enableFragmentMerge || reference == null || candidates.length < 2) {
      return _FragmentMergeResult(candidates, 0);
    }
    var pending = [...candidates];
    var mergeCount = 0;
    final maxMerges = math.max(1, pending.length ~/ 2);
    for (var pass = 0; pass < maxMerges; pass++) {
      ({double score, int i, int j, _MeasurementCandidate candidate})? best;
      for (var i = 0; i < pending.length - 1; i++) {
        for (var j = i + 1; j < pending.length; j++) {
          final candidate = _fragmentMergeCandidate(
            pending[i],
            pending[j],
            rgb,
            reference,
            imageArea,
            imageWidth,
            imageHeight,
          );
          if (candidate == null) continue;
          if (best == null || candidate.score < best.score) {
            best = (
              score: candidate.score,
              i: i,
              j: j,
              candidate: candidate.candidate
            );
          }
        }
      }
      if (best == null) break;
      final next = <_MeasurementCandidate>[];
      for (var index = 0; index < pending.length; index++) {
        if (index == best.i || index == best.j) continue;
        next.add(pending[index]);
      }
      next.add(best.candidate);
      pending = next;
      mergeCount++;
    }
    return _FragmentMergeResult(pending, mergeCount);
  }

  static ({double score, _MeasurementCandidate candidate})?
      _fragmentMergeCandidate(
    _MeasurementCandidate a,
    _MeasurementCandidate b,
    img.Image rgb,
    _SizeReference reference,
    int imageArea,
    int imageWidth,
    int imageHeight,
  ) {
    final refArea = math.max(reference.area, 1.0);
    final refLength = math.max(reference.length, 1.0);
    final refWidth = math.max(reference.width, 1.0);
    final refAspect = refLength / refWidth;
    final gap = _bboxGap(a.metrics, b.metrics);
    final maxGap = math.max(2.0, refWidth * _fragmentMergeMaxGapRatio);
    if (gap > maxGap) return null;
    final centerDistance = _centerDistance(a.metrics, b.metrics);
    if (centerDistance > math.max(refLength * 0.78, refWidth * 1.80)) {
      return null;
    }
    if (_combinedBBoxTooLarge(a.metrics, b.metrics, refLength, refWidth)) {
      return null;
    }

    final aAreaRatio = (a.metrics['area_px'] as num).toDouble() / refArea;
    final bAreaRatio = (b.metrics['area_px'] as num).toDouble() / refArea;
    final aLengthRatio = (a.metrics['length_px'] as num).toDouble() / refLength;
    final bLengthRatio = (b.metrics['length_px'] as num).toDouble() / refLength;
    final aWidthRatio = (a.metrics['width_px'] as num).toDouble() / refWidth;
    final bWidthRatio = (b.metrics['width_px'] as num).toDouble() / refWidth;
    final partialA = aAreaRatio <= 0.68 ||
        aLengthRatio <= 0.74 ||
        aWidthRatio <= 0.68 ||
        a.instance.confidence < 0.12;
    final partialB = bAreaRatio <= 0.68 ||
        bLengthRatio <= 0.74 ||
        bWidthRatio <= 0.68 ||
        b.instance.confidence < 0.12;
    if (!(partialA && partialB)) return null;
    final widthHalfPattern = aWidthRatio <= 0.74 &&
        bWidthRatio <= 0.74 &&
        math.max(aLengthRatio, bLengthRatio) <= 1.16;
    final lengthHalfPattern = aLengthRatio <= 0.74 &&
        bLengthRatio <= 0.74 &&
        math.max(aWidthRatio, bWidthRatio) <= 1.16;
    final compactHalfPattern = aAreaRatio <= 0.58 &&
        bAreaRatio <= 0.58 &&
        math.max(aLengthRatio, bLengthRatio) <= 1.05 &&
        math.max(aWidthRatio, bWidthRatio) <= 1.05;
    if (!(widthHalfPattern || lengthHalfPattern || compactHalfPattern)) {
      return null;
    }
    if (aAreaRatio + bAreaRatio > _fragmentMergeMaxAreaRatio) return null;
    if (math.max(aAreaRatio, bAreaRatio) > 1.08 &&
        math.min(aAreaRatio, bAreaRatio) > 0.38) {
      return null;
    }
    if (refAspect >= 1.65 && _axisSimilarity(a.metrics, b.metrics) < 0.72) {
      return null;
    }

    final merged = _unionInstances(a.instance, b.instance);
    final metrics = _maskMetrics(
      merged.mask,
      merged.width,
      merged.height,
      offsetX: merged.x,
      offsetY: merged.y,
    );
    if (metrics == null) return null;
    final color = _maskColorMetrics(
      rgb,
      merged.mask,
      merged.width,
      merged.height,
      offsetX: merged.x,
      offsetY: merged.y,
    );
    final mergedAreaRatio = (metrics['area_px'] as num).toDouble() / refArea;
    final mergedLengthRatio =
        (metrics['length_px'] as num).toDouble() / refLength;
    final mergedWidthRatio = (metrics['width_px'] as num).toDouble() / refWidth;
    if (mergedAreaRatio < _fragmentMergeMinAreaRatio ||
        mergedAreaRatio > _fragmentMergeMaxAreaRatio) {
      return null;
    }
    if (mergedLengthRatio > _fragmentMergeMaxLengthRatio ||
        mergedWidthRatio > _fragmentMergeMaxWidthRatio ||
        mergedLengthRatio < 0.52 ||
        mergedWidthRatio < 0.42) {
      return null;
    }
    final mergedAspect = (metrics['aspect_ratio'] as num).toDouble();
    if (refAspect >= 1.65) {
      if (mergedAspect < math.max(1.18, refAspect * 0.48) ||
          mergedAspect > refAspect * 1.75) {
        return null;
      }
    } else if (mergedAspect > 2.35) {
      return null;
    }
    final confidence =
        math.max(a.instance.confidence, b.instance.confidence) * 0.995;
    if (!_passesCandidateFilter(
      confidence,
      metrics,
      color,
      imageArea,
      imageWidth,
      imageHeight,
      reference,
      source: 'fragment_merge',
    )) {
      return null;
    }
    final score = (mergedAreaRatio - 1).abs() +
        (mergedLengthRatio - 1).abs() * 0.65 +
        (mergedWidthRatio - 1).abs() * 0.65 +
        gap / math.max(refWidth, 1.0) * 0.45;
    return (
      score: score,
      candidate: _MeasurementCandidate(
        _Instance(
          mask: merged.mask,
          confidence: confidence,
          classId: 0,
          x: merged.x,
          y: merged.y,
          width: merged.width,
          height: merged.height,
          source: 'fragment_merge',
        ),
        metrics,
        color,
      ),
    );
  }

  static _Instance _unionInstances(_Instance a, _Instance b) {
    final x = math.min(a.x, b.x);
    final y = math.min(a.y, b.y);
    final right = math.max(a.x + a.width, b.x + b.width);
    final bottom = math.max(a.y + a.height, b.y + b.height);
    final width = right - x;
    final height = bottom - y;
    final mask = Uint8List(width * height);
    _copyIntoUnionMask(mask, width, x, y, a);
    _copyIntoUnionMask(mask, width, x, y, b);
    return _Instance(
      mask: mask,
      confidence: math.max(a.confidence, b.confidence),
      classId: 0,
      x: x,
      y: y,
      width: width,
      height: height,
      source: 'fragment_merge',
    );
  }

  static void _copyIntoUnionMask(
    Uint8List target,
    int targetWidth,
    int targetX,
    int targetY,
    _Instance source,
  ) {
    for (var localY = 0; localY < source.height; localY++) {
      final sourceRow = localY * source.width;
      final targetRow =
          (source.y - targetY + localY) * targetWidth + (source.x - targetX);
      for (var localX = 0; localX < source.width; localX++) {
        if (source.mask[sourceRow + localX] != 0) {
          target[targetRow + localX] = 1;
        }
      }
    }
  }

  static double _axisSimilarity(
    Map<String, dynamic> a,
    Map<String, dynamic> b,
  ) {
    final aAngle = ((a['angle_deg'] as num?)?.toDouble() ?? 0) * math.pi / 180;
    final bAngle = ((b['angle_deg'] as num?)?.toDouble() ?? 0) * math.pi / 180;
    final dot = math.cos(aAngle) * math.cos(bAngle) +
        math.sin(aAngle) * math.sin(bAngle);
    return dot.abs();
  }

  static List<_MeasurementCandidate> _splitMergedCandidates(
    List<_MeasurementCandidate> candidates,
    img.Image rgb,
    _SizeReference? reference,
  ) {
    if (reference == null) return candidates;
    final result = <_MeasurementCandidate>[];
    for (final candidate in candidates) {
      final parts = _splitCandidateIfMerged(candidate, reference);
      if (parts.length == 1) {
        result.add(candidate);
        continue;
      }
      for (final part in parts) {
        final metrics = _maskMetrics(
          part.mask,
          part.width,
          part.height,
          offsetX: part.x,
          offsetY: part.y,
        );
        if (metrics == null) continue;
        final color = _maskColorMetrics(
          rgb,
          part.mask,
          part.width,
          part.height,
          offsetX: part.x,
          offsetY: part.y,
        );
        result.add(_MeasurementCandidate(part, metrics, color));
      }
    }
    return result;
  }

  static List<_Instance> _splitCandidateIfMerged(
    _MeasurementCandidate candidate,
    _SizeReference reference,
  ) {
    var parts = [candidate.instance];
    for (var pass = 0; pass < _mergedSplitMaxParts - 1; pass++) {
      var changed = false;
      final next = <_Instance>[];
      for (final part in parts) {
        final metrics = _maskMetrics(
          part.mask,
          part.width,
          part.height,
          offsetX: part.x,
          offsetY: part.y,
        );
        if (metrics == null || !_shouldTryMergedSplit(metrics, reference)) {
          next.add(part);
          continue;
        }
        final splitMasks = _mergedSplitMask(
          part.mask,
          part.width,
          part.height,
          reference,
          metrics,
        );
        if (splitMasks.length < 2 ||
            next.length + splitMasks.length + (parts.length - next.length - 1) >
                _mergedSplitMaxParts) {
          next.add(part);
          continue;
        }
        for (final splitMask in splitMasks) {
          next.add(
            _Instance(
              mask: splitMask,
              confidence: part.confidence * 0.98,
              classId: part.classId,
              x: part.x,
              y: part.y,
              width: part.width,
              height: part.height,
              source: '${part.source}_split',
            ),
          );
        }
        changed = true;
      }
      parts = next;
      if (!changed) break;
    }
    return parts.length > 1 ? parts : [candidate.instance];
  }

  static bool _shouldTryMergedSplit(
    Map<String, dynamic> metrics,
    _SizeReference reference,
  ) {
    if (!reference.splitEnabled) return false;
    final area = (metrics['area_px'] as num).toDouble();
    final length = (metrics['length_px'] as num).toDouble();
    final width = (metrics['width_px'] as num).toDouble();
    final areaLarge = area >= reference.areaSplitUpper;
    final lengthLarge = length >= reference.lengthSplitUpper;
    final widthLarge = width >= reference.widthSplitUpper;
    return areaLarge && (lengthLarge || widthLarge);
  }

  static List<Uint8List> _mergedSplitMask(
    Uint8List mask,
    int width,
    int height,
    _SizeReference reference,
    Map<String, dynamic> metrics,
  ) {
    final area = (metrics['area_px'] as num).round();
    final targetParts = _expectedSplitPartCount(area, reference);
    if (!_hasDistanceSplitEvidence(
      mask,
      width,
      height,
      reference,
      targetParts,
      metrics,
    )) {
      return [mask];
    }
    final markerParts = _distanceMarkerSplitMask(
      mask,
      width,
      height,
      reference,
      targetParts,
    );
    if (markerParts.length > 1) return markerParts;
    return _projectionSplitMask(mask, width, height, reference);
  }

  static int _expectedSplitPartCount(int area, _SizeReference reference) {
    final areaRatio = area / math.max(reference.area, 1.0);
    // Bias slightly downward near half steps; over-splitting is worse than
    // leaving an uncertain cluster for the projection fallback/manual review.
    return math.max(
      2,
      math.min(_mergedSplitMaxParts, (areaRatio + 0.35).floor()),
    );
  }

  static bool _hasDistanceSplitEvidence(
    Uint8List mask,
    int width,
    int height,
    _SizeReference reference,
    int targetParts,
    Map<String, dynamic> metrics,
  ) {
    final coreCount =
        _distanceCoreComponentCount(mask, width, height, reference);
    if (targetParts <= 2) return coreCount >= 2;
    if (coreCount >= 2) return true;
    final extent = (metrics['extent'] as num?)?.toDouble() ?? 1.0;
    return extent <= 0.68;
  }

  static int _distanceCoreComponentCount(
    Uint8List mask,
    int width,
    int height,
    _SizeReference reference,
  ) {
    if (width <= 0 || height <= 0 || mask.isEmpty) return 0;
    final distances = _distanceTransform(mask, width, height);
    var maxDistance = 0.0;
    for (final value in distances) {
      if (value > maxDistance && value < _largeDistance) maxDistance = value;
    }
    if (maxDistance < 2.5) return 0;

    final threshold = math.max(2.0, maxDistance * 0.65);
    final visited = Uint8List(mask.length);
    final minCoreArea = math.max(3, (reference.width * 0.25).floor());
    var count = 0;
    final queue = Int32List(mask.length);
    for (var i = 0; i < mask.length; i++) {
      if (visited[i] != 0 || mask[i] == 0 || distances[i] < threshold) {
        continue;
      }
      var head = 0;
      var tail = 0;
      queue[tail++] = i;
      visited[i] = 1;
      var area = 0;
      while (head < tail) {
        final index = queue[head++];
        area++;
        final x = index % width;
        final y = index ~/ width;
        for (var dy = -1; dy <= 1; dy++) {
          final ny = y + dy;
          if (ny < 0 || ny >= height) continue;
          for (var dx = -1; dx <= 1; dx++) {
            if (dx == 0 && dy == 0) continue;
            final nx = x + dx;
            if (nx < 0 || nx >= width) continue;
            final neighbor = ny * width + nx;
            if (visited[neighbor] != 0 ||
                mask[neighbor] == 0 ||
                distances[neighbor] < threshold) {
              continue;
            }
            visited[neighbor] = 1;
            queue[tail++] = neighbor;
          }
        }
      }
      if (area >= minCoreArea) count++;
    }
    return count;
  }

  static List<Uint8List> _distanceMarkerSplitMask(
    Uint8List mask,
    int width,
    int height,
    _SizeReference reference,
    int targetParts,
  ) {
    if (width <= 0 || height <= 0 || mask.isEmpty) return [mask];
    var total = 0;
    for (final value in mask) {
      if (value != 0) total++;
    }
    if (total < 2) return [mask];

    final distances = _distanceTransform(mask, width, height);
    var maxDistance = 0.0;
    for (final value in distances) {
      if (value > maxDistance && value < _largeDistance) maxDistance = value;
    }
    if (maxDistance < 2.5) return [mask];
    final peakThreshold = math.max(2.0, maxDistance * 0.45);
    final candidates = <_MaskSeed>[];
    for (var y = height - 1; y >= 0; y--) {
      final row = y * width;
      for (var x = width - 1; x >= 0; x--) {
        final index = row + x;
        final value = distances[index];
        if (mask[index] == 0 || value < peakThreshold) continue;
        candidates.add(_MaskSeed(x.toDouble(), y.toDouble(), value));
      }
    }
    if (candidates.length < 2) return [mask];

    final minSeedDistance =
        math.max(3.0, math.min(18.0, reference.width * 0.45));
    final minSeedDistanceSq = minSeedDistance * minSeedDistance;
    final seeds = <_MaskSeed>[];
    while (seeds.length < targetParts) {
      _MaskSeed? bestSeed;
      var bestScore = double.negativeInfinity;
      for (final candidate in candidates) {
        var score = candidate.distance;
        if (seeds.isNotEmpty) {
          var nearestSeedDistanceSq = double.infinity;
          for (final seed in seeds) {
            final dx = candidate.x - seed.x;
            final dy = candidate.y - seed.y;
            nearestSeedDistanceSq = math.min(
              nearestSeedDistanceSq,
              dx * dx + dy * dy,
            );
          }
          if (nearestSeedDistanceSq < minSeedDistanceSq) continue;
          final spreadScore = math.min(
            math.sqrt(nearestSeedDistanceSq) / math.max(minSeedDistance, 1.0),
            1.8,
          );
          score *= spreadScore;
        }
        if (score > bestScore) {
          bestScore = score;
          bestSeed = candidate;
        }
      }
      if (bestSeed == null) {
        break;
      }
      seeds.add(bestSeed);
    }
    if (seeds.length < 2) return [mask];

    final parts = List.generate(seeds.length, (_) => Uint8List(mask.length));
    final partAreas = List<int>.filled(seeds.length, 0);
    for (var y = 0; y < height; y++) {
      final row = y * width;
      for (var x = 0; x < width; x++) {
        final index = row + x;
        if (mask[index] == 0) continue;
        var bestSeedIndex = 0;
        var bestDistanceSq = double.infinity;
        for (var seedIndex = 0; seedIndex < seeds.length; seedIndex++) {
          final seed = seeds[seedIndex];
          final dx = x - seed.x;
          final dy = y - seed.y;
          final distanceSq = dx * dx + dy * dy;
          if (distanceSq < bestDistanceSq) {
            bestDistanceSq = distanceSq;
            bestSeedIndex = seedIndex;
          }
        }
        parts[bestSeedIndex][index] = 1;
        partAreas[bestSeedIndex]++;
      }
    }

    final minPartArea = math.max(20, (reference.area * 0.28).round());
    for (final area in partAreas) {
      if (area < minPartArea) return [mask];
    }
    if (partAreas.reduce(math.min) / math.max(total, 1) < 0.18) {
      return [mask];
    }
    if (!_splitPartsArePlausible(
      parts,
      width,
      height,
      reference,
      maxWidthMultiplier: 1.90,
    )) {
      return [mask];
    }
    return parts;
  }

  static const _largeDistance = 1.0e9;

  static Float32List _distanceTransform(Uint8List mask, int width, int height) {
    final distances = Float32List(mask.length);
    for (var i = 0; i < mask.length; i++) {
      distances[i] = mask[i] == 0 ? 0 : _largeDistance;
    }

    const diagonalCost = 1.41421356237;
    for (var y = 0; y < height; y++) {
      final row = y * width;
      for (var x = 0; x < width; x++) {
        final index = row + x;
        if (mask[index] == 0) continue;
        var best = distances[index];
        if (x > 0) best = math.min(best, distances[index - 1] + 1);
        if (y > 0) {
          best = math.min(best, distances[index - width] + 1);
          if (x > 0) {
            best = math.min(
              best,
              distances[index - width - 1] + diagonalCost,
            );
          }
          if (x + 1 < width) {
            best = math.min(
              best,
              distances[index - width + 1] + diagonalCost,
            );
          }
        }
        distances[index] = best;
      }
    }

    for (var y = height - 1; y >= 0; y--) {
      final row = y * width;
      for (var x = width - 1; x >= 0; x--) {
        final index = row + x;
        if (mask[index] == 0) continue;
        var best = distances[index];
        if (x + 1 < width) best = math.min(best, distances[index + 1] + 1);
        if (y + 1 < height) {
          best = math.min(best, distances[index + width] + 1);
          if (x + 1 < width) {
            best = math.min(
              best,
              distances[index + width + 1] + diagonalCost,
            );
          }
          if (x > 0) {
            best = math.min(
              best,
              distances[index + width - 1] + diagonalCost,
            );
          }
        }
        distances[index] = best;
      }
    }
    return distances;
  }

  static List<Uint8List> _projectionSplitMask(
    Uint8List mask,
    int width,
    int height,
    _SizeReference reference,
  ) {
    var count = 0;
    var sumX = 0.0;
    var sumY = 0.0;
    for (var y = 0; y < height; y++) {
      final row = y * width;
      for (var x = 0; x < width; x++) {
        if (mask[row + x] == 0) continue;
        count++;
        sumX += x;
        sumY += y;
      }
    }
    if (count < 2) return [mask];
    final meanX = sumX / count;
    final meanY = sumY / count;
    var covXx = 0.0;
    var covYy = 0.0;
    var covXy = 0.0;
    for (var y = 0; y < height; y++) {
      final row = y * width;
      for (var x = 0; x < width; x++) {
        if (mask[row + x] == 0) continue;
        final dx = x - meanX;
        final dy = y - meanY;
        covXx += dx * dx;
        covYy += dy * dy;
        covXy += dx * dy;
      }
    }
    final angle = 0.5 * math.atan2(2 * covXy, covXx - covYy);
    final majorX = math.cos(angle);
    final majorY = math.sin(angle);
    final candidates = [
      _splitMaskOnAxis(mask, width, height, majorX, majorY, reference),
      _splitMaskOnAxis(mask, width, height, -majorY, majorX, reference),
    ].where((candidate) => candidate.masks.length == 2).toList()
      ..sort((a, b) => a.score.compareTo(b.score));
    return candidates.isEmpty ? [mask] : candidates.first.masks;
  }

  static _ProjectionSplitResult _splitMaskOnAxis(
    Uint8List mask,
    int width,
    int height,
    double axisX,
    double axisY,
    _SizeReference reference,
  ) {
    var projMin = double.infinity;
    var projMax = double.negativeInfinity;
    var total = 0;
    for (var y = 0; y < height; y++) {
      final row = y * width;
      for (var x = 0; x < width; x++) {
        if (mask[row + x] == 0) continue;
        final projection = x * axisX + y * axisY;
        projMin = math.min(projMin, projection);
        projMax = math.max(projMax, projection);
        total++;
      }
    }
    final span = projMax - projMin;
    if (total < 2 || span < 8) return _ProjectionSplitResult([mask], 1);
    final binCount = math.max(12, math.min(96, (span / 4).ceil()));
    final hist = List<int>.filled(binCount, 0);
    for (var y = 0; y < height; y++) {
      final row = y * width;
      for (var x = 0; x < width; x++) {
        if (mask[row + x] == 0) continue;
        final projection = x * axisX + y * axisY;
        final bin = (((projection - projMin) / span) * binCount)
            .floor()
            .clamp(0, binCount - 1)
            .toInt();
        hist[bin]++;
      }
    }
    final cumulative = List<int>.filled(binCount, 0);
    for (var i = 0; i < binCount; i++) {
      cumulative[i] = hist[i] + (i == 0 ? 0 : cumulative[i - 1]);
    }
    final lo = math.max(2, (binCount * 0.2).floor());
    final hi = math.min(binCount - 3, (binCount * 0.8).floor());
    if (hi <= lo) return _ProjectionSplitResult([mask], 1);
    final minPartArea = math.max(20, (reference.area * 0.28).round());
    var bestScore = double.infinity;
    var bestIndex = -1;
    var bestValleyRatio = 1.0;
    for (var index = lo; index <= hi; index++) {
      final leftArea = cumulative[index];
      final rightArea = cumulative.last - leftArea;
      if (leftArea < minPartArea || rightArea < minPartArea) continue;
      final balance = math.min(leftArea, rightArea) / math.max(total, 1);
      if (balance < 0.25) continue;
      final leftPeak = hist.take(index + 1).fold<int>(0, math.max);
      final rightPeak = hist.skip(index).fold<int>(0, math.max);
      final peakFloor = math.max(1, math.min(leftPeak, rightPeak));
      final valleyRatio = hist[index] / peakFloor;
      final score = valleyRatio + (0.5 - balance).abs() * 0.6;
      if (score < bestScore) {
        bestScore = score;
        bestIndex = index;
        bestValleyRatio = valleyRatio;
      }
    }
    if (bestIndex < 0) return _ProjectionSplitResult([mask], 1);
    if (bestValleyRatio > 0.92 && total < reference.area * 1.6) {
      return _ProjectionSplitResult([mask], bestValleyRatio);
    }
    final threshold = projMin + span * ((bestIndex + 0.5) / binCount);
    final leftMask = Uint8List(mask.length);
    final rightMask = Uint8List(mask.length);
    var leftArea = 0;
    var rightArea = 0;
    for (var y = 0; y < height; y++) {
      final row = y * width;
      for (var x = 0; x < width; x++) {
        final localIndex = row + x;
        if (mask[localIndex] == 0) continue;
        final projection = x * axisX + y * axisY;
        if (projection <= threshold) {
          leftMask[localIndex] = 1;
          leftArea++;
        } else {
          rightMask[localIndex] = 1;
          rightArea++;
        }
      }
    }
    if (leftArea < minPartArea || rightArea < minPartArea) {
      return _ProjectionSplitResult([mask], 1);
    }
    if (math.min(leftArea, rightArea) / math.max(leftArea + rightArea, 1) <
        0.25) {
      return _ProjectionSplitResult([mask], 1);
    }
    final parts = [leftMask, rightMask];
    if (!_splitPartsArePlausible(parts, width, height, reference)) {
      return _ProjectionSplitResult([mask], 1);
    }
    return _ProjectionSplitResult(parts, bestValleyRatio);
  }

  static bool _splitPartsArePlausible(
    List<Uint8List> parts,
    int width,
    int height,
    _SizeReference reference, {
    double maxWidthMultiplier = 1.75,
  }) {
    final minAspect = math.max(1.35, reference.length / reference.width * 0.45);
    final maxWidth = reference.width * maxWidthMultiplier;
    final minLength = reference.length * 0.45;
    for (final part in parts) {
      final metrics = _maskMetrics(part, width, height, offsetX: 0, offsetY: 0);
      if (metrics == null) return false;
      if ((metrics['aspect_ratio'] as num).toDouble() < minAspect) {
        return false;
      }
      if ((metrics['width_px'] as num).toDouble() > maxWidth) return false;
      if ((metrics['length_px'] as num).toDouble() < minLength) return false;
    }
    return true;
  }

  static _MaskColorMetrics _maskColorMetrics(
    img.Image rgb,
    Uint8List mask,
    int width,
    int height, {
    required int offsetX,
    required int offsetY,
  }) {
    var count = 0;
    var skinCount = 0;
    var lumaSum = 0.0;
    var chromaSum = 0.0;
    var neutralCount = 0;
    for (var y = 0; y < height; y++) {
      final globalY = y + offsetY;
      if (globalY < 0 || globalY >= rgb.height) continue;
      for (var x = 0; x < width; x++) {
        if (mask[y * width + x] == 0) continue;
        final globalX = x + offsetX;
        if (globalX < 0 || globalX >= rgb.width) continue;
        final pixel = rgb.getPixel(globalX, globalY);
        final r = pixel.r.toDouble();
        final g = pixel.g.toDouble();
        final b = pixel.b.toDouble();
        final maxChannel = math.max(r, math.max(g, b));
        final minChannel = math.min(r, math.min(g, b));
        final chroma = maxChannel - minChannel;
        count++;
        lumaSum += 0.299 * r + 0.587 * g + 0.114 * b;
        chromaSum += chroma;
        if (chroma < 28.0) neutralCount++;
        if (_isSkinLikePixel(r, g, b)) skinCount++;
      }
    }
    if (count == 0) {
      return const _MaskColorMetrics(
        skinRatio: 0,
        luma: 0,
        chroma: 0,
        neutralRatio: 0,
      );
    }
    return _MaskColorMetrics(
      skinRatio: skinCount / count,
      luma: lumaSum / count,
      chroma: chromaSum / count,
      neutralRatio: neutralCount / count,
    );
  }

  static bool _isSkinLikePixel(double r, double g, double b) {
    final maxChannel = math.max(r, math.max(g, b));
    final minChannel = math.min(r, math.min(g, b));
    final cb = 128 - 0.168736 * r - 0.331264 * g + 0.5 * b;
    final cr = 128 + 0.5 * r - 0.418688 * g - 0.081312 * b;
    final rgbRule = r > 70 &&
        g > 35 &&
        b > 20 &&
        r > g &&
        r > b &&
        maxChannel - minChannel > 15;
    final ycbcrRule = cr >= 135 && cr <= 185 && cb >= 75 && cb <= 140;
    return rgbRule && ycbcrRule;
  }

  static bool _isLabelEdge(
    Int32List labels,
    int width,
    int height,
    int x,
    int y,
    int label,
  ) {
    if (x == 0 || y == 0 || x == width - 1 || y == height - 1) return true;
    if (labels[y * width + (x - 1)] != label) return true;
    if (labels[y * width + (x + 1)] != label) return true;
    if (labels[(y - 1) * width + x] != label) return true;
    if (labels[(y + 1) * width + x] != label) return true;
    return false;
  }

  static int _bitmapTextWidth(dynamic font, String text) {
    var width = 0;
    for (final codeUnit in text.codeUnits) {
      final character = font.characters[codeUnit];
      width += character == null
          ? (font.base as int) ~/ 2
          : character.xAdvance as int;
    }
    return width;
  }

  static void _drawReadableId(
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

  static img.Image _renderLabels(
    _FilteredResult result, {
    double coordinateScaleX = 1,
    double coordinateScaleY = 1,
  }) {
    const palette = [
      [45, 108, 191],
      [219, 87, 86],
      [73, 160, 120],
      [235, 174, 73],
      [132, 98, 174],
      [77, 176, 196],
      [201, 112, 165],
      [122, 126, 135],
    ];
    final labelsImage = img.Image(
      width: result.width,
      height: result.height,
      numChannels: 3,
    );
    for (var y = 0; y < result.height; y++) {
      for (var x = 0; x < result.width; x++) {
        final label = result.labels[y * result.width + x];
        if (label <= 0) continue;
        final color = palette[(label - 1) % palette.length];
        labelsImage.setPixelRgb(x, y, color[0], color[1], color[2]);
      }
    }
    for (final measurement in result.measurements) {
      final id = (measurement['id'] as num).toInt();
      final centroidX =
          ((measurement['centroid_x'] as num).toDouble() * coordinateScaleX)
              .round();
      final centroidY =
          ((measurement['centroid_y'] as num).toDouble() * coordinateScaleY)
              .round();
      _drawReadableId(labelsImage, id, centroidX, centroidY);
    }
    return labelsImage;
  }

  Future<List<_OfflineModelProfile>> _choosePreferredProfiles() async {
    if (!Platform.isAndroid) return const [_safeModelProfile];
    final memoryInfo = await _readDeviceMemoryInfo();
    if (memoryInfo?.canUseFastHighQualityModel == true) {
      return const [
        _fastHighQualityModelProfile,
        _safeModelProfile,
      ];
    }
    return const [_safeModelProfile];
  }

  Future<_DeviceMemoryInfo?> _readDeviceMemoryInfo() async {
    if (!Platform.isAndroid) return null;
    try {
      final result = await _deviceMemoryChannel
          .invokeMethod<Map<dynamic, dynamic>>('getMemoryInfo');
      if (result == null) return null;
      return _DeviceMemoryInfo.fromMap(result);
    } catch (_) {
      return null;
    }
  }

  static bool _isResourceError(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('memory') ||
        message.contains('oom') ||
        message.contains('outofmemory') ||
        message.contains('failed to allocate') ||
        message.contains('bad_alloc') ||
        message.contains('allocation') ||
        message.contains('arena');
  }

  static bool _isModelLoadError(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('invalid_graph') ||
        message.contains('invalid graph') ||
        message.contains('failed to load') ||
        message.contains('no such file') ||
        message.contains('unsupported') ||
        message.contains('not implemented') ||
        message.contains('create session');
  }

  static bool _canFallbackFromProfile(
    _OfflineModelProfile profile,
    Object error,
  ) {
    if (profile.allowZeroCountFallback) return true;
    return profile.isHighQuality && _isResourceError(error);
  }

  static bool _shouldRetryZeroDetection(OfflineAnalyzeResult result) {
    final count = (result.summary['count'] as num?)?.toInt() ?? 0;
    final candidates =
        (result.segmentation['candidate_count'] as num?)?.toInt() ?? 0;
    return count == 0 && candidates == 0;
  }

  static String _profileFallbackReason(
    _OfflineModelProfile profile,
    Object error,
  ) {
    if (_isResourceError(error)) return _resourceFallbackReason(error);
    if (_isModelLoadError(error)) return 'fast_model_unavailable';
    if (profile.allowZeroCountFallback) return 'fast_model_error';
    return _resourceFallbackReason(error);
  }

  static String _profileFallbackMessage(
    _OfflineModelProfile profile,
    Object error,
  ) {
    if (_isResourceError(error)) {
      return 'Thiết bị không đủ tài nguyên cho 1024, chuyển sang 640 an toàn';
    }
    if (profile.allowZeroCountFallback) {
      return 'Model 1024 tối ưu không khả dụng, chuyển sang 640 an toàn';
    }
    return 'Chuyển sang chế độ nhận dạng an toàn';
  }

  static String _resourceFallbackReason(Object error) {
    final message = error.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    if (message.isEmpty) return 'resource_error';
    return message.length <= 180 ? message : '${message.substring(0, 180)}...';
  }

  Future<OrtSession> _loadSession(_OfflineModelProfile profile) async {
    final existing = _session;
    if (existing != null &&
        _sessionProfile?.modelAssetPath == profile.modelAssetPath) {
      return existing;
    }
    if (existing != null) await close();
    final options = Platform.isAndroid
        ? OrtSessionOptions(
            providers: const [OrtProvider.CPU],
            intraOpNumThreads: profile.intraOpThreads,
            interOpNumThreads: 1,
            useArena: false,
          )
        : null;
    final loaded = await OnnxRuntime().createSessionFromAsset(
      profile.modelAssetPath,
      options: options,
    );
    _session = loaded;
    _sessionProfile = profile;
    return loaded;
  }

  Future<void> close() async {
    final session = _session;
    _session = null;
    _sessionProfile = null;
    if (session != null) await session.close();
  }
}

double _boxIou(_Detection a, _Detection b) {
  final x1 = math.max(a.x1, b.x1);
  final y1 = math.max(a.y1, b.y1);
  final x2 = math.min(a.x2, b.x2);
  final y2 = math.min(a.y2, b.y2);
  final intersection = math.max(0.0, x2 - x1) * math.max(0.0, y2 - y1);
  final aArea = math.max(0.0, a.x2 - a.x1) * math.max(0.0, a.y2 - a.y1);
  final bArea = math.max(0.0, b.x2 - b.x1) * math.max(0.0, b.y2 - b.y1);
  final union = aArea + bArea - intersection;
  return union == 0 ? 0 : intersection / union;
}

List<_Point> _convexHull(List<_Point> points) {
  final sorted = [...points]..sort((a, b) {
      final byX = a.x.compareTo(b.x);
      return byX != 0 ? byX : a.y.compareTo(b.y);
    });
  if (sorted.length <= 2) return sorted;
  final lower = <_Point>[];
  for (final point in sorted) {
    while (lower.length >= 2 &&
        _cross(lower[lower.length - 2], lower.last, point) <= 0) {
      lower.removeLast();
    }
    lower.add(point);
  }
  final upper = <_Point>[];
  for (final point in sorted.reversed) {
    while (upper.length >= 2 &&
        _cross(upper[upper.length - 2], upper.last, point) <= 0) {
      upper.removeLast();
    }
    upper.add(point);
  }
  lower.removeLast();
  upper.removeLast();
  return [...lower, ...upper];
}

double _polygonArea(List<_Point> points) {
  if (points.length < 3) return 1.0;
  var sum = 0.0;
  for (var i = 0; i < points.length; i++) {
    final next = points[(i + 1) % points.length];
    sum += points[i].x * next.y - next.x * points[i].y;
  }
  return sum.abs() / 2;
}

double _perpendicularChordWidth(
  List<_Point> points,
  double axisX,
  double axisY,
) {
  if (points.length < 2) return 1.0;
  final normalX = -axisY;
  final normalY = axisX;
  final axisProjections = <double>[];
  final normalProjections = <double>[];
  var axisMin = double.infinity;
  for (final point in points) {
    final axisProjection = point.x * axisX + point.y * axisY;
    axisProjections.add(axisProjection);
    normalProjections.add(point.x * normalX + point.y * normalY);
    axisMin = math.min(axisMin, axisProjection);
  }

  var bestWidth = 0.0;
  for (final offset in const [0.0, 0.5]) {
    final spans = <int, _ProjectionSpan>{};
    for (var i = 0; i < points.length; i++) {
      final bucket = (axisProjections[i] - axisMin + offset).floor();
      spans.putIfAbsent(bucket, _ProjectionSpan.new).add(normalProjections[i]);
    }
    for (final span in spans.values) {
      if (span.count >= 2) {
        bestWidth = math.max(bestWidth, span.maxValue - span.minValue);
      }
    }
  }
  return math.max(bestWidth, 1.0);
}

_FeretMetrics _feretShapeMetrics(List<_Point> hull, List<_Point> widthPoints) {
  if (hull.length < 2) {
    return const _FeretMetrics(length: 1, width: 1, angleDegrees: 0);
  }
  var bestDistanceSquared = 0.0;
  var start = hull.first;
  var end = hull.last;
  for (var i = 0; i < hull.length; i++) {
    for (var j = i + 1; j < hull.length; j++) {
      final dx = hull[j].x - hull[i].x;
      final dy = hull[j].y - hull[i].y;
      final distanceSquared = dx * dx + dy * dy;
      if (distanceSquared > bestDistanceSquared) {
        bestDistanceSquared = distanceSquared;
        start = hull[i];
        end = hull[j];
      }
    }
  }
  final rawLength = math.sqrt(bestDistanceSquared);
  final length = math.max(rawLength, 1.0);
  if (length <= 1e-9) {
    return const _FeretMetrics(length: 1, width: 1, angleDegrees: 0);
  }
  final axisX = (end.x - start.x) / length;
  final axisY = (end.y - start.y) / length;
  final width = _perpendicularChordWidth(widthPoints, axisX, axisY);
  return _FeretMetrics(
    length: length,
    width: width,
    angleDegrees: math.atan2(axisY, axisX) * 180 / math.pi,
  );
}

double _cross(_Point origin, _Point a, _Point b) =>
    (a.x - origin.x) * (b.y - origin.y) - (a.y - origin.y) * (b.x - origin.x);

double _sigmoid(double value) => 1 / (1 + math.exp(-value.clamp(-88.0, 88.0)));

bool _isReferenceObjectMask(
  _Instance instance,
  int width,
  int height,
  _Point start,
  _Point end,
) {
  final dx = end.x - start.x;
  final dy = end.y - start.y;
  final length = math.sqrt(dx * dx + dy * dy);
  if (length <= 0) return false;
  final samples = math.max(2, length.ceil() + 1);
  var covered = 0;
  for (var i = 0; i < samples; i++) {
    final ratio = i / (samples - 1);
    final x = (start.x + dx * ratio).round().clamp(0, width - 1).toInt();
    final y = (start.y + dy * ratio).round().clamp(0, height - 1).toInt();
    if (instance.contains(x, y)) covered++;
  }
  final midX = ((start.x + end.x) / 2).round().clamp(0, width - 1).toInt();
  final midY = ((start.y + end.y) / 2).round().clamp(0, height - 1).toInt();
  final midpointInside = instance.contains(midX, midY);
  return midpointInside && covered / samples >= 0.55;
}

double _round(num value, int decimals) {
  final factor = math.pow(10, decimals).toDouble();
  return (value * factor).round() / factor;
}

Map<String, dynamic> _summaryFor(List<Map<String, dynamic>> measurements) {
  if (measurements.isEmpty) {
    return {
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
      'robust_std_area_px': 0,
      'robust_std_length_px': 0,
      'robust_std_width_px': 0,
      'robust_std_area_mm2': null,
      'robust_std_length_mm': null,
      'robust_std_width_mm': null,
      'cv_length_pct': 0,
      'cv_width_pct': 0,
      'qc': {
        'method': 'median_mad_multimetric',
        'suspect_count': 0,
        'inlier_count': 0,
        'suspect_ids': <int>[],
        'review_required': false,
        'suspect_ratio': 0,
        'robust_used_for_reporting': true,
        'threshold': _qcMadZThreshold,
        'min_metrics': _qcMinOutlierMetrics,
        'status': 'ok',
      },
      'quality': _qualitySummary(const []),
    };
  }
  final qcThreshold = _qcMadZThresholdFor(measurements);
  final outliers = _qcOutlierIndices(measurements, qcThreshold);
  final suspectRatio = outliers.length / measurements.length;
  final robustUsedForReporting = suspectRatio <= 0.05;
  for (var index = 0; index < measurements.length; index++) {
    final isOutlier = outliers.contains(index);
    measurements[index]['qc_outlier'] = isOutlier;
    measurements[index]['qc_reason'] =
        isOutlier ? 'size_outlier_mad_multimetric' : '';
  }
  final inliers = [
    for (var index = 0; index < measurements.length; index++)
      if (!outliers.contains(index)) measurements[index],
  ];
  final robustMeasurements = inliers.isEmpty ? measurements : inliers;

  List<double> values(List<Map<String, dynamic>> items, String key) =>
      items.map((item) => ((item[key] as num?)?.toDouble() ?? 0)).toList();
  double mean(List<Map<String, dynamic>> items, String key) =>
      _round(values(items, key).reduce((a, b) => a + b) / items.length, 6);
  double std(List<Map<String, dynamic>> items, String key) {
    if (items.length <= 1) return 0;
    final data = values(items, key);
    final average = data.reduce((a, b) => a + b) / data.length;
    final squaredSum = data.fold<double>(
        0, (total, value) => total + math.pow(value - average, 2));
    return _round(math.sqrt(squaredSum / (data.length - 1)), 6);
  }

  double cv(List<Map<String, dynamic>> items, String key) {
    final average = mean(items, key);
    return average > 0 ? _round(std(items, key) / average * 100, 3) : 0;
  }

  final calibrated = measurements.first['length_mm'] != null;
  double? metricMm(double Function(List<Map<String, dynamic>>, String) stat,
          List<Map<String, dynamic>> items, String key) =>
      calibrated ? stat(items, key) : null;

  return {
    'count': measurements.length,
    'total_area_px': measurements.fold<int>(
      0,
      (total, item) => total + ((item['area_px'] as num?)?.toInt() ?? 0),
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
      'method': 'median_mad_multimetric',
      'threshold': qcThreshold,
      'min_metrics': _qcMinOutlierMetrics,
      'suspect_count': outliers.length,
      'inlier_count': robustMeasurements.length,
      'suspect_ids': [
        for (final index in outliers.toList()..sort())
          measurements[index]['id'],
      ],
      'review_required': outliers.isNotEmpty,
      'suspect_ratio': _round(suspectRatio, 6),
      'robust_used_for_reporting': robustUsedForReporting,
      'status': !robustUsedForReporting
          ? 'review_required'
          : (outliers.isNotEmpty ? 'suspects_flagged' : 'ok'),
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

double _qcMadZThresholdFor(List<Map<String, dynamic>> measurements) {
  if (measurements.length < 5) return _qcMadZThreshold;

  double iqrRatio(String key) {
    final data = measurements
        .map((item) => ((item[key] as num?)?.toDouble() ?? 0))
        .toList()
      ..sort();
    final middle = _median(data);
    if (middle <= 1e-9) return 0;
    return (_percentile(data, 0.75) - _percentile(data, 0.25)) / middle;
  }

  final wideMetrics = [
    iqrRatio('area_px') >= 1.0,
    iqrRatio('length_px') >= 0.65,
    iqrRatio('width_px') >= 0.55,
  ].where((value) => value).length;
  return wideMetrics >= 2 ? _qcRelaxedMadZThreshold : _qcMadZThreshold;
}

Set<int> _qcOutlierIndices(
  List<Map<String, dynamic>> measurements,
  double threshold,
) {
  if (measurements.length < 5) return {};
  final outlierCounts = List<int>.filled(measurements.length, 0);
  for (final key in ['area_px', 'length_px', 'width_px']) {
    final data = measurements
        .map((item) => ((item[key] as num?)?.toDouble() ?? 0))
        .toList();
    final middle = _median(data);
    final deviations = data.map((value) => (value - middle).abs()).toList();
    final mad = _median(deviations);
    for (var index = 0; index < data.length; index++) {
      final deviation = deviations[index];
      final isOutlier =
          mad <= 1e-9 ? deviation > 1e-9 : 0.6745 * deviation / mad > threshold;
      if (isOutlier) outlierCounts[index]++;
    }
  }
  return {
    for (var index = 0; index < outlierCounts.length; index++)
      if (outlierCounts[index] >= _qcMinOutlierMetrics) index,
  };
}

double _median(List<double> values) {
  final ordered = [...values]..sort();
  final middle = ordered.length ~/ 2;
  return ordered.length.isOdd
      ? ordered[middle]
      : (ordered[middle - 1] + ordered[middle]) / 2;
}

double _percentile(List<double> sortedValues, double fraction) {
  if (sortedValues.isEmpty) return 0;
  final position = (sortedValues.length - 1) * fraction.clamp(0, 1);
  final lower = position.floor();
  final upper = position.ceil();
  if (lower == upper) return sortedValues[lower];
  final weight = position - lower;
  return sortedValues[lower] * (1 - weight) + sortedValues[upper] * weight;
}

class _OfflineModelProfile {
  final String name;
  final String modelAssetPath;
  final int inputSize;
  final int protoSize;
  final bool enableRoiPrepass;
  final bool enableFullImagePass;
  final bool enableTiledInference;
  final int tileSize;
  final double tileOverlap;
  final int roiMaxPasses;
  final bool allowZeroCountFallback;
  final int previewMaxSide;
  final int intraOpThreads;

  const _OfflineModelProfile({
    required this.name,
    required this.modelAssetPath,
    required this.inputSize,
    required this.protoSize,
    required this.enableRoiPrepass,
    required this.enableFullImagePass,
    required this.enableTiledInference,
    required this.tileSize,
    required this.tileOverlap,
    required this.roiMaxPasses,
    this.allowZeroCountFallback = false,
    required this.previewMaxSide,
    required this.intraOpThreads,
  });

  int get predictionFeatureCount =>
      4 +
      OfflineGrainAnalyzer._classCount +
      OfflineGrainAnalyzer._maskCoefficientCount;

  bool get isHighQuality => inputSize >= 1024;
}

class _PreviewRenderInput {
  final img.Image rgb;
  final _FilteredResult result;
  final double coordinateScaleX;
  final double coordinateScaleY;

  const _PreviewRenderInput({
    required this.rgb,
    required this.result,
    required this.coordinateScaleX,
    required this.coordinateScaleY,
  });
}

class _DeviceMemoryInfo {
  final bool lowMemory;
  final int availableMb;
  final int thresholdMb;
  final int memoryClassMb;
  final int largeMemoryClassMb;
  final bool lowRamDevice;

  const _DeviceMemoryInfo({
    required this.lowMemory,
    required this.availableMb,
    required this.thresholdMb,
    required this.memoryClassMb,
    required this.largeMemoryClassMb,
    required this.lowRamDevice,
  });

  factory _DeviceMemoryInfo.fromMap(Map<dynamic, dynamic> map) {
    int intValue(String key) => ((map[key] as num?) ?? 0).round();
    return _DeviceMemoryInfo(
      lowMemory: map['lowMemory'] == true,
      availableMb: intValue('availableMb'),
      thresholdMb: intValue('thresholdMb'),
      memoryClassMb: intValue('memoryClassMb'),
      largeMemoryClassMb: intValue('largeMemoryClassMb'),
      lowRamDevice: map['lowRamDevice'] == true,
    );
  }

  bool get canUseFastHighQualityModel =>
      !lowMemory &&
      !lowRamDevice &&
      largeMemoryClassMb >=
          OfflineGrainAnalyzer._minFastHighQualityLargeHeapMb &&
      availableMb >= OfflineGrainAnalyzer._minFastHighQualityAvailableMb;
}

class _Detection {
  final double score;
  final int classId;
  final double x1;
  final double y1;
  final double x2;
  final double y2;
  final List<double> coefficients;

  const _Detection({
    required this.score,
    required this.classId,
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
    required this.coefficients,
  });
}

class _Instance {
  final Uint8List mask;
  final double confidence;
  final int classId;
  final int x;
  final int y;
  final int width;
  final int height;
  final String source;

  const _Instance({
    required this.mask,
    required this.confidence,
    required this.classId,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.source,
  });

  bool contains(int globalX, int globalY) {
    final localX = globalX - x;
    final localY = globalY - y;
    if (localX < 0 || localX >= width || localY < 0 || localY >= height) {
      return false;
    }
    return mask[localY * width + localX] != 0;
  }
}

class _MeasurementCandidate {
  final _Instance instance;
  final Map<String, dynamic> metrics;
  final _MaskColorMetrics color;

  const _MeasurementCandidate(this.instance, this.metrics, this.color);

  double get priority {
    final area = ((metrics['area_px'] as num?)?.toDouble() ?? 0).clamp(1, 1e9);
    final areaPenalty = math.log(area) / 80;
    final skinPenalty = color.skinRatio * 0.35;
    return instance.confidence - areaPenalty - skinPenalty;
  }
}

class _FragmentMergeResult {
  final List<_MeasurementCandidate> candidates;
  final int mergeCount;

  const _FragmentMergeResult(this.candidates, this.mergeCount);
}

class _MaskColorMetrics {
  final double skinRatio;
  final double luma;
  final double chroma;
  final double neutralRatio;

  const _MaskColorMetrics({
    required this.skinRatio,
    required this.luma,
    required this.chroma,
    required this.neutralRatio,
  });
}

class _SizeReference {
  final double area;
  final double length;
  final double width;
  final double chroma;
  final double neutralRatio;
  final double luma;
  final bool splitEnabled;
  final double areaSplitUpper;
  final double lengthSplitUpper;
  final double widthSplitUpper;
  final double areaUpper;

  const _SizeReference({
    required this.area,
    required this.length,
    required this.width,
    required this.chroma,
    required this.neutralRatio,
    required this.luma,
    required this.splitEnabled,
    required this.areaSplitUpper,
    required this.lengthSplitUpper,
    required this.widthSplitUpper,
    required this.areaUpper,
  });
}

class _ProjectionSplitResult {
  final List<Uint8List> masks;
  final double score;

  const _ProjectionSplitResult(this.masks, this.score);
}

class _MaskSeed {
  final double x;
  final double y;
  final double distance;

  const _MaskSeed(this.x, this.y, this.distance);
}

class _Point {
  final double x;
  final double y;

  const _Point(this.x, this.y);
}

class _FeretMetrics {
  final double length;
  final double width;
  final double angleDegrees;

  const _FeretMetrics({
    required this.length,
    required this.width,
    required this.angleDegrees,
  });
}

class _ProjectionSpan {
  var minValue = double.infinity;
  var maxValue = double.negativeInfinity;
  var count = 0;

  void add(double value) {
    minValue = math.min(minValue, value);
    maxValue = math.max(maxValue, value);
    count += 1;
  }
}

class _FilteredResult {
  final Int32List labels;
  final List<Map<String, dynamic>> measurements;
  final double mmPerPixel;
  final int width;
  final int height;
  final int excludedReferenceObjectCount;
  final int acceptedRefClassSeedCount;
  final int autoExcludedNonSeedCount;
  final int fragmentMergeCount;
  final Map<String, dynamic>? suggestedReference;

  const _FilteredResult({
    required this.labels,
    required this.measurements,
    required this.mmPerPixel,
    required this.width,
    required this.height,
    required this.excludedReferenceObjectCount,
    required this.acceptedRefClassSeedCount,
    required this.autoExcludedNonSeedCount,
    required this.fragmentMergeCount,
    required this.suggestedReference,
  });
}

class _OfflinePostprocessInput {
  final List<_Instance> rawInstances;
  final int rawDetectionCount;
  final int passCount;
  final int roiRegionCount;
  final bool roiBudgetExceeded;
  final int roiPassCount;
  final int tilePassCount;
  final int width;
  final int height;
  final int originalWidth;
  final int originalHeight;
  final _OfflineModelProfile profile;
  final String? fallbackReason;
  final double scale;
  final double? referencePixels;
  final double? referenceMm;
  final double? referenceX1;
  final double? referenceY1;
  final double? referenceX2;
  final double? referenceY2;

  const _OfflinePostprocessInput({
    required this.rawInstances,
    required this.rawDetectionCount,
    required this.passCount,
    required this.roiRegionCount,
    required this.roiBudgetExceeded,
    required this.roiPassCount,
    required this.tilePassCount,
    required this.width,
    required this.height,
    required this.originalWidth,
    required this.originalHeight,
    required this.profile,
    required this.fallbackReason,
    required this.scale,
    required this.referencePixels,
    required this.referenceMm,
    required this.referenceX1,
    required this.referenceY1,
    required this.referenceX2,
    required this.referenceY2,
  });
}

class _OfflineInferencePass {
  final Float32List predictions;
  final Float32List protos;
  final int width;
  final int height;
  final int paddedSide;
  final int offsetX;
  final int offsetY;
  final String source;
  final _OfflineModelProfile profile;

  const _OfflineInferencePass({
    required this.predictions,
    required this.protos,
    required this.width,
    required this.height,
    required this.paddedSide,
    required this.offsetX,
    required this.offsetY,
    required this.source,
    required this.profile,
  });
}

class _DecodedInferencePass {
  final int rawDetectionCount;
  final List<_Instance> instances;

  const _DecodedInferencePass({
    required this.rawDetectionCount,
    required this.instances,
  });
}

class _ClassicalFallbackResult {
  final List<_Instance> instances;
  final Map<String, dynamic> stats;

  const _ClassicalFallbackResult(this.instances, this.stats);
}

class _RoiBox {
  final int x;
  final int y;
  final int width;
  final int height;

  const _RoiBox({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  factory _RoiBox.fromBounds(int x1, int y1, int x2, int y2) => _RoiBox(
        x: x1,
        y: y1,
        width: math.max(0, x2 - x1),
        height: math.max(0, y2 - y1),
      );

  int get area => width * height;

  _RoiBox union(_RoiBox other) {
    final x1 = math.min(x, other.x);
    final y1 = math.min(y, other.y);
    final x2 = math.max(x + width, other.x + other.width);
    final y2 = math.max(y + height, other.y + other.height);
    return _RoiBox.fromBounds(x1, y1, x2, y2);
  }
}

class _RgbColor {
  final double r;
  final double g;
  final double b;

  const _RgbColor(this.r, this.g, this.b);
}

class OfflineModelInfo {
  final String modelAssetPath;
  final List<OfflineTensorInfo> inputTensors;
  final List<OfflineTensorInfo> outputTensors;

  const OfflineModelInfo({
    required this.modelAssetPath,
    required this.inputTensors,
    required this.outputTensors,
  });
}

class OfflineTensorInfo {
  final String name;
  final List<int> shape;
  final String type;

  const OfflineTensorInfo({
    required this.name,
    required this.shape,
    required this.type,
  });
}

class OfflineAnalyzeResult {
  final Uint8List originalPng;
  final Uint8List overlayPng;
  final Uint8List maskPng;
  final Uint8List labelsPng;
  final Uint8List labelMapPng;
  final Map<String, dynamic> image;
  final List<Map<String, dynamic>> measurements;
  final Map<String, dynamic> summary;
  final Map<String, dynamic> calibration;
  final Map<String, dynamic> segmentation;

  const OfflineAnalyzeResult({
    required this.originalPng,
    required this.overlayPng,
    required this.maskPng,
    required this.labelsPng,
    required this.labelMapPng,
    required this.image,
    required this.measurements,
    required this.summary,
    required this.calibration,
    required this.segmentation,
  });

  Map<String, dynamic> asApiJson(String fileName) {
    final maskBase64 = base64Encode(maskPng);
    return {
      'run': {
        'id': 'local-${DateTime.now().millisecondsSinceEpoch}',
        'sourceFileName': fileName,
        'localOnly': true,
        'offline': true,
        'createdAt': DateTime.now().toIso8601String(),
      },
      'image': image,
      'summary': summary,
      'segmentation': segmentation,
      'calibration': calibration,
      'features': {
        'pipeline': 'yolo8_nano_segment',
        'source': 'mobile_onnxruntime',
        'preprocess': {'enabled': false},
      },
      'measurements': measurements,
      'csv': _measurementsCsv(measurements),
      'original_png_base64': '',
      'overlay_png_base64': base64Encode(overlayPng),
      'sam_mask_png_base64': '',
      'labels_png_base64': base64Encode(labelsPng),
      'mask_png_base64': maskBase64,
      'label_map_png_base64': base64Encode(labelMapPng),
    };
  }
}

String _measurementsCsv(List<Map<String, dynamic>> measurements) {
  const columns = [
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
  ];
  final rows = <String>[columns.join(',')];
  for (final measurement in measurements) {
    rows.add(columns.map((column) => '${measurement[column] ?? ''}').join(','));
  }
  return '${rows.join('\n')}\n';
}
