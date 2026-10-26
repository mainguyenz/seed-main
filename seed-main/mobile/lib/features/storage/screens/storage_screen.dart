import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/i18n/app_language.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/providers/auth_provider.dart';
import '../../grain/providers/grain_runs_provider.dart';
import '../../grain/services/grain_analysis_api.dart';
import '../../grain/widgets/grain_stats_charts.dart';

class StorageScreen extends ConsumerWidget {
  const StorageScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final runsState = ref.watch(grainRunsProvider);
    final isGuest = ref.watch(guestModeProvider).value ?? false;
    final language = ref.watch(appLanguageProvider);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(grainRunsProvider);
        await ref.read(grainRunsProvider.future);
      },
      child: runsState.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _Header(isGuest: isGuest),
            const SizedBox(height: 18),
            Text(
              localizedText(language, error.toString()),
              style: TextStyle(color: Colors.red.shade700),
            ),
          ],
        ),
        data: (runs) => ListView.builder(
          padding: const EdgeInsets.all(20),
          itemCount: runs.isEmpty ? 3 : runs.length + 2,
          itemBuilder: (context, index) {
            if (index == 0) return _Header(isGuest: isGuest);
            if (index == 1) return const SizedBox(height: 18);
            if (runs.isEmpty) {
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    appText(language, 'Chưa có dữ liệu', 'No data yet'),
                    style: const TextStyle(color: AppTheme.textSecondary),
                  ),
                ),
              );
            }
            final run = runs[index - 2];
            return _RunCard(
              run: run,
              onTap: () => _openRunDetail(context, run.id, language),
            );
          },
        ),
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  final bool isGuest;

  const _Header({required this.isGuest});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final language = ref.watch(appLanguageProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          isGuest
              ? appText(
                  language,
                  'Dữ liệu đang được lưu trên thiết bị này. Đăng nhập để đồng bộ lên tài khoản của bạn.',
                  'Data is saved on this device. Log in to sync it to your account.',
                )
              : appText(
                  language,
                  'Các lần xử lý đã đồng bộ với tài khoản của bạn.',
                  'Analyses are synced with your account.',
                ),
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14),
        ),
      ],
    );
  }
}

class _RunCard extends ConsumerStatefulWidget {
  final GrainRun run;
  final VoidCallback onTap;

  const _RunCard({required this.run, required this.onTap});

  @override
  ConsumerState<_RunCard> createState() => _RunCardState();
}

class _RunCardState extends ConsumerState<_RunCard> {
  Future<Uint8List?>? _remoteOverlay;
  String _overlayCacheKey = '';
  Uint8List? _overlayCacheBytes;

  @override
  void initState() {
    super.initState();
    _prepareRemoteOverlay();
  }

  @override
  void didUpdateWidget(covariant _RunCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.run.id != widget.run.id ||
        oldWidget.run.overlayBase64 != widget.run.overlayBase64) {
      _prepareRemoteOverlay();
    }
  }

  void _prepareRemoteOverlay() {
    if (_overlayBytesFromRun() != null) {
      _remoteOverlay = null;
      return;
    }
    _remoteOverlay = GrainAnalysisApi()
        .getRun(widget.run.id)
        .then(
            (detail) => _decodePreview(detail.result.previewBase64('overlay')))
        .catchError((_) => null);
  }

  Uint8List? _overlayBytesFromRun() {
    final source = widget.run.overlayBase64;
    if (source.isEmpty) {
      _overlayCacheKey = '';
      _overlayCacheBytes = null;
      return null;
    }
    final cacheKey = '${widget.run.id}:${source.length}:${source.hashCode}';
    if (_overlayCacheKey == cacheKey) return _overlayCacheBytes;
    _overlayCacheBytes = _decodePreview(source);
    _overlayCacheKey = cacheKey;
    return _overlayCacheBytes;
  }

  @override
  Widget build(BuildContext context) {
    final overlayBytes = _overlayBytesFromRun();
    final language = ref.watch(appLanguageProvider);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 82,
                height: 82,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.border),
                ),
                clipBehavior: Clip.antiAlias,
                child: overlayBytes == null
                    ? FutureBuilder<Uint8List?>(
                        future: _remoteOverlay,
                        builder: (context, snapshot) {
                          final bytes = snapshot.data;
                          if (bytes != null) {
                            return Image.memory(
                              bytes,
                              fit: BoxFit.cover,
                              cacheWidth: 164,
                            );
                          }
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return const Center(
                              child: SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              ),
                            );
                          }
                          return const Icon(
                            Icons.image_outlined,
                            color: AppTheme.textSecondary,
                          );
                        },
                      )
                    : Image.memory(
                        overlayBytes,
                        fit: BoxFit.cover,
                        cacheWidth: 164,
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${widget.run.count} ${appText(language, 'hạt', 'grains')}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(
                          Icons.schedule_outlined,
                          size: 15,
                          color: AppTheme.textSecondary,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            '${appText(language, 'Thực hiện', 'Created')}: ${_formatDate(widget.run.createdAt)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${appText(language, 'ĐLC', 'SD')}: ${_formatPair(widget.run.qcStdLengthMm, widget.run.qcStdWidthMm, widget.run.qcStdLengthPx, widget.run.qcStdWidthPx)}',
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${appText(language, 'TB', 'Avg')}: ${_formatPair(widget.run.meanLengthMm, widget.run.meanWidthMm, widget.run.meanLengthPx, widget.run.meanWidthPx)}',
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Uint8List? _decodePreview(String value) {
  if (value.isEmpty) return null;
  try {
    return base64Decode(value);
  } on FormatException {
    return null;
  }
}

Future<void> _openRunDetail(
    BuildContext context, String runId, AppLanguage language) async {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  );

  try {
    final detail = await GrainAnalysisApi().getRun(runId);
    if (!context.mounted) return;
    Navigator.of(context).pop();
    await showDialog<void>(
      context: context,
      builder: (_) => _RunDetailDialog(detail: detail),
    );
  } catch (error) {
    if (!context.mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${appText(language, 'Không tải được chi tiết', 'Could not load details')}: $error',
        ),
      ),
    );
  }
}

class _RunDetailDialog extends ConsumerStatefulWidget {
  final GrainRunDetail detail;

  const _RunDetailDialog({required this.detail});

  @override
  ConsumerState<_RunDetailDialog> createState() => _RunDetailDialogState();
}

class _RunDetailDialogState extends ConsumerState<_RunDetailDialog> {
  String _previewMode = 'overlay';
  String _previewCacheKey = '';
  Uint8List? _previewCacheBytes;

  Uint8List? _previewBytesFor(String previewBase64) {
    if (previewBase64.isEmpty) {
      _previewCacheKey = '';
      _previewCacheBytes = null;
      return null;
    }
    final cacheKey = '$_previewMode:${previewBase64.length}';
    if (_previewCacheKey == cacheKey) return _previewCacheBytes;
    _previewCacheBytes = _decodePreview(previewBase64);
    _previewCacheKey = cacheKey;
    return _previewCacheBytes;
  }

  @override
  Widget build(BuildContext context) {
    final result = widget.detail.result;
    final run = widget.detail.run;
    final preview = result.previewWithFallback(_previewMode);
    final previewBytes = _previewBytesFor(preview);
    final name = run['sourceFileName']?.toString() ?? 'seed-image';
    final language = ref.watch(appLanguageProvider);

    return AlertDialog(
      title: Text('Run ${_shortId(run['id']?.toString() ?? '')}'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _chip('original', appText(language, 'Ảnh gốc', 'Original')),
                  _chip('overlay', appText(language, 'Đánh dấu', 'Overlay')),
                  _chip('mask', appText(language, 'Hình dạng', 'Mask')),
                  _chip('labels', appText(language, 'Đánh số', 'Labels')),
                ],
              ),
              const SizedBox(height: 12),
              if (previewBytes != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(
                    previewBytes,
                    cacheWidth: 1200,
                  ),
                ),
              const SizedBox(height: 12),
              _detailRow(
                  appText(
                      language, 'Tổng số hạt đo được', 'Total measured grains'),
                  '${result.count}'),
              _detailRow(
                  appText(language, 'ĐLC chiều dài (báo cáo)',
                      'Length SD (reported)'),
                  _formatMeasure(
                      result.qcStdLengthMm, 'mm', result.qcStdLengthPx, 'px')),
              _detailRow(
                  appText(language, 'ĐLC chiều rộng (báo cáo)',
                      'Width SD (reported)'),
                  _formatMeasure(
                      result.qcStdWidthMm, 'mm', result.qcStdWidthPx, 'px')),
              _detailRow(
                  appText(language, 'ĐLC diện tích (báo cáo)',
                      'Area SD (reported)'),
                  _formatMeasure(
                      result.qcStdAreaMm2, 'mm2', result.qcStdAreaPx, 'px2')),
              _detailRow(
                  appText(language, 'Hạt nghi ngờ sau kiểm tra',
                      'Suspect grains after QC'),
                  '${result.qcSuspectCount}'),
              _detailRow(
                  appText(language, 'Tỷ lệ thước đo', 'Scale ratio'),
                  result.calibration['enabled'] == true
                      ? '${_asDouble(result.calibration['mm_per_pixel']).toStringAsFixed(5)} mm/px'
                      : appText(language, 'Chưa thiết lập', 'Not set')),
              const SizedBox(height: 10),
              Text(
                appText(language, 'Tóm tắt kích thước đã lưu',
                    'Saved size summary'),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              GrainStatsCharts(result: result, compact: true),
              const Divider(),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(appText(language, 'Đóng', 'Close')),
        ),
        TextButton.icon(
          onPressed:
              result.csv.isEmpty ? null : () => _shareCsv(name, result.csv),
          icon: const Icon(Icons.table_view_outlined),
          label: Text(appText(language, 'Xuất CSV', 'Export CSV')),
        ),
        TextButton.icon(
          onPressed: _segmentationPng(result).isEmpty
              ? null
              : () => _sharePng(name, _segmentationPng(result)),
          icon: const Icon(Icons.image_outlined),
          label: Text(
              appText(language, 'Xuất ảnh kết quả', 'Export result image')),
        ),
      ],
    );
  }

  Widget _chip(String mode, String label) {
    return ChoiceChip(
      label: Text(label),
      selected: _previewMode == mode,
      onSelected: (_) => setState(() => _previewMode = mode),
    );
  }
}

Widget _detailRow(String label, String value) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Expanded(
            child: Text(label,
                style: const TextStyle(color: AppTheme.textSecondary))),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    ),
  );
}

Future<void> _shareCsv(String sourceName, String csv) async {
  final file = await _writeTempFile(
      '${_safeStem(sourceName)}_measurements.csv', utf8.encode(csv));
  await Share.shareXFiles([XFile(file.path)],
      text: 'SeedVision measurements CSV');
}

String _segmentationPng(GrainAnalysisResult result) {
  final segment = result.previewBase64('samMask');
  if (segment.isNotEmpty) return segment;
  final mask = result.previewBase64('mask');
  if (mask.isNotEmpty) return mask;
  final labels = result.previewBase64('labels');
  if (labels.isNotEmpty) return labels;
  return result.previewBase64('overlay');
}

Future<void> _sharePng(String sourceName, String base64) async {
  final file = await _writeTempFile(
      '${_safeStem(sourceName)}_segmentation.png', base64Decode(base64));
  await Share.shareXFiles([XFile(file.path)],
      text: 'SeedVision segmentation PNG');
}

Future<File> _writeTempFile(String name, List<int> bytes) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$name');
  return file.writeAsBytes(bytes, flush: true);
}

String _shortId(String id) =>
    id.length >= 8 ? id.substring(id.length - 8).toUpperCase() : id;

String _safeStem(String name) {
  final withoutExt = name.replaceFirst(RegExp(r'\.[^.]+$'), '');
  return withoutExt.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');
}

String _formatMeasure(
    double? primary, String primaryUnit, double fallback, String fallbackUnit) {
  if (primary != null) {
    return '${primary.toStringAsFixed(primaryUnit == 'mm2' ? 3 : 2)} $primaryUnit';
  }
  return '${fallback.toStringAsFixed(1)} $fallbackUnit';
}

String _formatPair(
    double? lengthMm, double? widthMm, double? lengthPx, double? widthPx) {
  if (lengthMm != null && widthMm != null) {
    return '${lengthMm.toStringAsFixed(2)} mm x ${widthMm.toStringAsFixed(2)} mm';
  }
  if (lengthPx == null || widthPx == null) return '-';
  return '${lengthPx.toStringAsFixed(1)} px x ${widthPx.toStringAsFixed(1)} px';
}

String _formatDate(DateTime? value) {
  if (value == null) return '-';
  return '${value.day.toString().padLeft(2, '0')}/'
      '${value.month.toString().padLeft(2, '0')}/'
      '${value.year} '
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';
}

double _asDouble(dynamic value) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}
