import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_language.dart';
import '../../../core/theme/app_theme.dart';
import '../services/grain_analysis_api.dart';

const _sizeGroups = <_SizeGroupDef>[
  _SizeGroupDef(key: 'small', label: 'Nhỏ hơn đa số', color: Color(0xFF60A5FA)),
  _SizeGroupDef(
      key: 'typical', label: 'Cỡ thường gặp', color: Color(0xFF2F6B4F)),
  _SizeGroupDef(key: 'large', label: 'Lớn hơn đa số', color: Color(0xFFF59E0B)),
];

const _metricDefs = <String, _MetricDef>{
  'length': _MetricDef(
    title: 'Phân bố chiều dài',
    pxKey: 'length_px',
    mmKey: 'length_mm',
    pxUnit: 'px',
    mmUnit: 'mm',
    pxDecimals: 1,
    mmDecimals: 2,
    color: Color(0xFF2F6B4F),
  ),
  'width': _MetricDef(
    title: 'Phân bố chiều rộng',
    pxKey: 'width_px',
    mmKey: 'width_mm',
    pxUnit: 'px',
    mmUnit: 'mm',
    pxDecimals: 1,
    mmDecimals: 2,
    color: Color(0xFF2563EB),
  ),
  'area': _MetricDef(
    title: 'Phân bố diện tích',
    pxKey: 'area_px',
    mmKey: 'area_mm2',
    pxUnit: 'px²',
    mmUnit: 'mm²',
    pxDecimals: 0,
    mmDecimals: 3,
    color: Color(0xFFD97706),
  ),
};

class GrainStatsCharts extends ConsumerStatefulWidget {
  final GrainAnalysisResult result;
  final bool compact;

  const GrainStatsCharts({
    super.key,
    required this.result,
    this.compact = false,
  });

  @override
  ConsumerState<GrainStatsCharts> createState() => _GrainStatsChartsState();
}

class _GrainStatsChartsState extends ConsumerState<GrainStatsCharts> {
  String _chartMode = 'length';

  void _showHelp() {
    final language = ref.read(appLanguageProvider);
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(appText(
          language,
          'Cách đọc phần kích thước',
          'How to read size charts',
        )),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                appText(
                  language,
                  'Chọn Chiều dài, Chiều rộng hoặc Diện tích để các thẻ số, nhóm kích thước và biểu đồ cùng đổi theo chỉ số đó.',
                  'Choose Length, Width, or Area so the number cards, size groups, and chart use the same metric.',
                ),
              ),
              const SizedBox(height: 10),
              Text(
                appText(
                  language,
                  'Cỡ thường gặp là trung vị: khoảng một nửa số hạt nhỏ hơn mức này, một nửa lớn hơn.',
                  'Typical size is the median: about half the grains are smaller and half are larger.',
                ),
              ),
              const SizedBox(height: 10),
              Text(
                appText(
                  language,
                  'Mỗi cột trong biểu đồ là một khoảng kích thước; số trên cột là số hạt trong khoảng đó.',
                  'Each chart column is a size range; the number above it is the grain count in that range.',
                ),
              ),
              const SizedBox(height: 10),
              Text(
                appText(
                  language,
                  'Số dưới cột là điểm bắt đầu của khoảng. Ví dụ cột 5+, cột kế tiếp là 8+, thì cột 5+ chứa các hạt có kích thước trong nửa khoảng [5; 8).',
                  'The label under a column is the start of the range. If one column is 5+ and the next is 8+, the 5+ column contains grains in [5; 8).',
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                height: 86,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (final item in const [
                      (3, 22.0),
                      (8, 44.0),
                      (14, 72.0),
                      (10, 56.0),
                      (5, 28.0),
                    ])
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text('${item.$1}',
                                style: const TextStyle(
                                    fontSize: 11, fontWeight: FontWeight.w800)),
                            const SizedBox(height: 4),
                            Container(
                              width: 28,
                              height: item.$2,
                              decoration: const BoxDecoration(
                                color: AppTheme.primary,
                                borderRadius: BorderRadius.vertical(
                                    top: Radius.circular(4)),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(appText(language, 'Đã hiểu', 'Got it')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final language = ref.watch(appLanguageProvider);
    final model = _buildModel(widget.result);
    if (model == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            appText(
              language,
              'Chưa đủ dữ liệu hạt để xem kích thước.',
              'Not enough grain data to view sizes.',
            ),
            style: TextStyle(
              color: AppTheme.textSecondary.withValues(alpha: 0.95),
            ),
          ),
        ),
      );
    }

    final visibleCharts = _chartMode == 'all'
        ? const ['length', 'width', 'area']
        : <String>[_chartMode];

    return Card(
      child: Padding(
        padding: EdgeInsets.all(widget.compact ? 12 : 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    appText(language, 'Kích thước hạt', 'Grain size'),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton(
                  tooltip: appText(
                    language,
                    'Cách đọc kích thước',
                    'How to read size charts',
                  ),
                  icon: const Icon(Icons.help_outline, size: 20),
                  onPressed: _showHelp,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              appText(
                language,
                'Chọn chỉ số muốn xem để đọc đúng theo chiều dài, chiều rộng hoặc diện tích.',
                'Choose a metric to read the result by length, width, or area.',
              ),
              style:
                  const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _modeChip('length', appText(language, 'Chiều dài', 'Length')),
                _modeChip('width', appText(language, 'Chiều rộng', 'Width')),
                _modeChip('area', appText(language, 'Diện tích', 'Area')),
                _modeChip('all', appText(language, 'Tất cả', 'All')),
              ],
            ),
            const SizedBox(height: 14),
            _MetricGrid(
              model: model,
              chartMode: _chartMode,
            ),
            const SizedBox(height: 14),
            if (_chartMode == 'all')
              for (final key in const ['length', 'width', 'area']) ...[
                _SizeGroupSection(distribution: model.distributions[key]),
                if (key != 'area') const SizedBox(height: 10),
              ]
            else
              _SizeGroupSection(distribution: model.distributions[_chartMode]),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Text(
                    appText(language, 'Biểu đồ phân bố', 'Distribution chart'),
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton(
                  tooltip: appText(
                    language,
                    'Cách đọc biểu đồ',
                    'How to read the chart',
                  ),
                  icon: const Icon(Icons.help_outline, size: 18),
                  visualDensity: VisualDensity.compact,
                  constraints:
                      const BoxConstraints.tightFor(width: 32, height: 32),
                  padding: EdgeInsets.zero,
                  onPressed: _showHelp,
                ),
              ],
            ),
            const SizedBox(height: 6),
            for (final key in visibleCharts) ...[
              _DistributionChart(
                distribution: model.distributions[key],
                compact: widget.compact,
              ),
              if (key != visibleCharts.last) const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
  }

  Widget _modeChip(String key, String label) {
    return ChoiceChip(
      label: Text(label),
      selected: _chartMode == key,
      onSelected: (_) => setState(() => _chartMode = key),
    );
  }
}

class _MetricGrid extends ConsumerWidget {
  final _ChartModel model;
  final String chartMode;

  const _MetricGrid({
    required this.model,
    required this.chartMode,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final language = ref.watch(appLanguageProvider);
    final activeDistribution = model.distributions[chartMode];
    final keys = chartMode == 'all'
        ? const ['length', 'width', 'area']
        : <String>[chartMode, 'variation', 'review'];
    final tiles = [
      for (final key in keys)
        if (key == 'review')
          _MetricTile(
            label: appText(language, 'Hạt cần xem lại', 'Grains to review'),
            value: '${model.suspectCount}/${model.totalCount}',
            helper: appText(
              language,
              '${_formatNumber(model.suspectPct, 1)}% tổng số hạt.',
              '${_formatNumber(model.suspectPct, 1)}% of total grains.',
            ),
          )
        else if (key == 'variation' && activeDistribution != null)
          _MetricTile(
            label: appText(language, 'Độ biến thiên (CV)',
                'Coefficient of variation (CV)'),
            value: '${_formatNumber(activeDistribution.cvPct, 1)}%',
            helper: appText(
              language,
              'Độ lệch chuẩn / trung bình của các hạt hợp lệ.',
              'Standard deviation / mean for valid grains.',
            ),
          )
        else if (model.distributions[key] case final distribution?)
          _MetricTile(
            label: localizedText(
              language,
              distribution.title
                  .replaceFirst('Phân bố ', 'Cỡ thường gặp theo '),
            ),
            value:
                '${_formatNumber(distribution.midpoint, distribution.decimals)} ${distribution.unit}',
            helper:
                '${appText(language, 'Khoảng phổ biến', 'Common range')}: ${_formatNumber(_percentile(distribution.sortedValues, 0.1), distribution.decimals)}-${_formatNumber(_percentile(distribution.sortedValues, 0.9), distribution.decimals)} ${distribution.unit}',
          ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final columnCount = availableWidth >= 720
            ? math.min(3, tiles.length)
            : (availableWidth >= 420 ? math.min(2, tiles.length) : 1);
        const gap = 10.0;
        final tileWidth = columnCount <= 1
            ? availableWidth
            : (availableWidth - gap * (columnCount - 1)) / columnCount;

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final tile in tiles)
              SizedBox(
                width: tileWidth,
                child: tile,
              ),
          ],
        );
      },
    );
  }
}

class _MetricTile extends StatelessWidget {
  final String label;
  final String value;
  final String helper;

  const _MetricTile({
    required this.label,
    required this.value,
    required this.helper,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.bgDefault,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.border),
      ),
      constraints: const BoxConstraints(minHeight: 92),
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
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 2),
          Text(
            helper,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _SizeGroupSection extends ConsumerWidget {
  final _Distribution? distribution;

  const _SizeGroupSection({required this.distribution});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final language = ref.watch(appLanguageProvider);
    final data = distribution;
    if (data == null || data.sortedValues.isEmpty || data.midpoint <= 0) {
      return const SizedBox.shrink();
    }
    final groups = _buildSizeGroups(data.sortedValues, data.midpoint);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          localizedText(
            language,
            'Nhóm kích thước theo ${data.title.replaceFirst('Phân bố ', '').toLowerCase()}',
          ),
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        _SegmentBar(groups: groups),
        const SizedBox(height: 10),
        for (final group in groups) ...[
          _GroupRow(group: group),
          if (group != groups.last) const SizedBox(height: 7),
        ],
      ],
    );
  }
}

class _DistributionChart extends ConsumerWidget {
  final _Distribution? distribution;
  final bool compact;

  const _DistributionChart({required this.distribution, required this.compact});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final language = ref.watch(appLanguageProvider);
    final data = distribution;
    if (data == null) return const SizedBox.shrink();
    final maxCount = data.bins.fold<int>(
      1,
      (maxValue, bin) => math.max(maxValue, bin.count),
    );

    return Container(
      padding: EdgeInsets.all(compact ? 10 : 12),
      decoration: BoxDecoration(
        border: Border.all(color: AppTheme.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(localizedText(language, data.title),
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w800)),
              ),
              Text('${data.sampleCount} ${appText(language, 'hạt', 'grains')}',
                  style: const TextStyle(
                      fontSize: 12, color: AppTheme.textSecondary)),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            appText(
              language,
              'Mỗi cột là một nhóm hạt có kích thước gần nhau.',
              'Each column is a group of grains with similar sizes.',
            ),
            style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: compact ? 140 : 160,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final bin in data.bins) ...[
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text('${bin.count}',
                            style: const TextStyle(
                                fontSize: 11, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 4),
                        Container(
                          width: 26,
                          height: math.max(8, bin.count / maxCount * 92),
                          decoration: BoxDecoration(
                            color: data.color,
                            borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(4)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final bin in data.bins)
                Expanded(
                  child: Text(
                    bin.shortLabel,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    style: const TextStyle(
                        fontSize: 9,
                        color: AppTheme.textSecondary,
                        height: 1.15),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SegmentBar extends StatelessWidget {
  final List<_SizeGroup> groups;

  const _SegmentBar({required this.groups});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: Row(
        children: [
          for (final group in groups)
            Expanded(
              flex: math.max(1, (group.pct * 10).round()),
              child: Container(height: 14, color: group.color),
            ),
        ],
      ),
    );
  }
}

class _GroupRow extends ConsumerWidget {
  final _SizeGroup group;

  const _GroupRow({required this.group});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final language = ref.watch(appLanguageProvider);
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: group.color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            localizedText(language, group.label),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            '${group.count} ${appText(language, 'hạt', 'grains')} (${_formatNumber(group.pct, 1)}%)',
            textAlign: TextAlign.right,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

class _MetricDef {
  final String title;
  final String pxKey;
  final String mmKey;
  final String pxUnit;
  final String mmUnit;
  final int pxDecimals;
  final int mmDecimals;
  final Color color;

  const _MetricDef({
    required this.title,
    required this.pxKey,
    required this.mmKey,
    required this.pxUnit,
    required this.mmUnit,
    required this.pxDecimals,
    required this.mmDecimals,
    required this.color,
  });
}

class _Metric {
  final String key;
  final String unit;
  final int decimals;

  const _Metric({
    required this.key,
    required this.unit,
    required this.decimals,
  });
}

class _DistributionBin {
  final String label;
  final String shortLabel;
  final int count;

  const _DistributionBin({
    required this.label,
    required this.shortLabel,
    required this.count,
  });
}

class _Distribution {
  final String title;
  final String unit;
  final int decimals;
  final int sampleCount;
  final double midpoint;
  final double cvPct;
  final Color color;
  final List<_DistributionBin> bins;
  final List<double> sortedValues;

  const _Distribution({
    required this.title,
    required this.unit,
    required this.decimals,
    required this.sampleCount,
    required this.midpoint,
    required this.cvPct,
    required this.color,
    required this.bins,
    required this.sortedValues,
  });
}

class _SizeGroupDef {
  final String key;
  final String label;
  final Color color;

  const _SizeGroupDef({
    required this.key,
    required this.label,
    required this.color,
  });
}

class _SizeGroup {
  final String key;
  final String label;
  final int count;
  final double pct;
  final Color color;

  const _SizeGroup({
    required this.key,
    required this.label,
    required this.count,
    required this.pct,
    required this.color,
  });
}

class _ChartModel {
  final List<_SizeGroup> sizeGroups;
  final Map<String, _Distribution?> distributions;
  final int totalCount;
  final String unitLabel;
  final int decimals;
  final double midpoint;
  final int suspectCount;
  final double suspectPct;

  const _ChartModel({
    required this.sizeGroups,
    required this.distributions,
    required this.totalCount,
    required this.unitLabel,
    required this.decimals,
    required this.midpoint,
    required this.suspectCount,
    required this.suspectPct,
  });

  String get qcLabel {
    if (suspectPct <= 0) return 'Không có hạt nghi ngờ';
    if (suspectPct <= 5) return 'Ít hạt cần xem lại';
    return 'Cần xem lại ảnh';
  }

  Color get qcColor {
    if (suspectPct <= 0) return AppTheme.primary;
    if (suspectPct <= 5) return const Color(0xFFD97706);
    return const Color(0xFFDC2626);
  }
}

_ChartModel? _buildModel(GrainAnalysisResult result) {
  if (result.measurements.isEmpty) return null;

  final lengthDistribution = _buildDistribution(result, 'length');
  if (lengthDistribution == null) return null;

  final midpoint = lengthDistribution.midpoint;

  final summarySuspects = _asInt(result.summary['qc'] is Map
      ? (result.summary['qc'] as Map)['suspect_count']
      : null);
  final measuredSuspects = result.measurements
      .where((measurement) => measurement['qc_outlier'] == true)
      .length;
  final suspectCount = _clampInt(
    summarySuspects > 0 ? summarySuspects : measuredSuspects,
    0,
    result.measurements.length,
  );
  final suspectPct = result.measurements.isEmpty
      ? 0.0
      : _round(suspectCount * 100 / result.measurements.length, 1);

  return _ChartModel(
    sizeGroups: _buildSizeGroups(lengthDistribution.sortedValues, midpoint),
    distributions: {
      'length': lengthDistribution,
      'width': _buildDistribution(result, 'width'),
      'area': _buildDistribution(result, 'area'),
    },
    totalCount: result.measurements.length,
    unitLabel: lengthDistribution.unit,
    decimals: lengthDistribution.decimals,
    midpoint: midpoint,
    suspectCount: suspectCount,
    suspectPct: suspectPct,
  );
}

_Distribution? _buildDistribution(GrainAnalysisResult result, String key) {
  final def = _metricDefs[key]!;
  final metric = _pickMetric(result, def);
  final values = result.measurements
      .where((measurement) => measurement['qc_outlier'] != true)
      .map((measurement) => _asDouble(measurement[metric.key]))
      .where((value) => value > 0)
      .toList()
    ..sort();
  if (values.isEmpty) return null;

  final binCount = values.length < 4
      ? math.max(1, values.length)
      : _clampInt(math.sqrt(values.length).round(), 4, 8);
  final bins = _buildBins(values, binCount, metric.decimals);
  final mean = values.reduce((sum, value) => sum + value) / values.length;
  final variance = values.fold<double>(
        0,
        (sum, value) => sum + math.pow(value - mean, 2).toDouble(),
      ) /
      values.length;
  final standardDeviation = math.sqrt(variance);
  return _Distribution(
    title: def.title,
    unit: metric.unit,
    decimals: metric.decimals,
    sampleCount: values.length,
    midpoint: _percentile(values, 0.5),
    cvPct: mean > 0 ? _round(standardDeviation * 100 / mean, 1) : 0,
    color: def.color,
    bins: bins,
    sortedValues: values,
  );
}

_Metric _pickMetric(GrainAnalysisResult result, _MetricDef def) {
  if (!result.calibrated) {
    return _Metric(key: def.pxKey, unit: def.pxUnit, decimals: def.pxDecimals);
  }
  final metricReady = result.measurements
      .where((measurement) => _asDouble(measurement[def.mmKey]) > 0)
      .length;
  if (metricReady >= math.max(3, (result.measurements.length * 0.6).round())) {
    return _Metric(key: def.mmKey, unit: def.mmUnit, decimals: def.mmDecimals);
  }
  return _Metric(key: def.pxKey, unit: def.pxUnit, decimals: def.pxDecimals);
}

List<_DistributionBin> _buildBins(
    List<double> values, int binCount, int decimals) {
  final minValue = values.first;
  final maxValue = values.last;
  if (minValue == maxValue || binCount == 1) {
    return [
      _DistributionBin(
        label: _formatNumber(minValue, decimals),
        shortLabel: _compactLabelNumber(minValue, decimals),
        count: values.length,
      ),
    ];
  }

  final width = (maxValue - minValue) / binCount;
  final counts = List<int>.filled(binCount, 0);
  for (final value in values) {
    final index = _clampInt(
        ((value - minValue) / math.max(width, 1e-9)).floor(), 0, binCount - 1);
    counts[index] += 1;
  }
  return [
    for (var index = 0; index < binCount; index++)
      _DistributionBin(
        label:
            '${_formatNumber(minValue + width * index, decimals)}-${_formatNumber(index == binCount - 1 ? maxValue : minValue + width * (index + 1), decimals)}',
        shortLabel:
            '${_compactLabelNumber(minValue + width * index, decimals)}+',
        count: counts[index],
      ),
  ];
}

List<_SizeGroup> _buildSizeGroups(List<double> sortedValues, double midpoint) {
  if (sortedValues.isEmpty || midpoint <= 0) return const [];
  final counts = <String, int>{'small': 0, 'typical': 0, 'large': 0};
  for (final value in sortedValues) {
    final ratio = value / midpoint;
    if (ratio < 0.9) {
      counts['small'] = counts['small']! + 1;
    } else if (ratio <= 1.1) {
      counts['typical'] = counts['typical']! + 1;
    } else {
      counts['large'] = counts['large']! + 1;
    }
  }
  final total = sortedValues.length.toDouble();
  return [
    for (final group in _sizeGroups)
      _SizeGroup(
        key: group.key,
        label: group.label,
        count: counts[group.key] ?? 0,
        pct: _round((counts[group.key] ?? 0) * 100 / total, 1),
        color: group.color,
      ),
  ];
}

double _percentile(List<double> sortedValues, double ratio) {
  if (sortedValues.isEmpty) return 0;
  final p = ratio.clamp(0, 1).toDouble();
  final index = (sortedValues.length - 1) * p;
  final lower = index.floor();
  final upper = index.ceil();
  if (lower == upper) return sortedValues[lower];
  final weight = index - lower;
  return sortedValues[lower] * (1 - weight) + sortedValues[upper] * weight;
}

int _clampInt(int value, int min, int max) =>
    value < min ? min : (value > max ? max : value);

double _round(num value, int digits) {
  final factor = math.pow(10, digits).toDouble();
  return (value * factor).round() / factor;
}

String _formatNumber(num value, int digits) => value.toStringAsFixed(digits);

String _compactLabelNumber(num value, int digits) {
  final number = value.toDouble();
  if (number.abs() >= 1000000) {
    return '${(number / 1000000).toStringAsFixed(1)}m';
  }
  if (number.abs() >= 1000) {
    return '${(number / 1000).toStringAsFixed(1)}k';
  }
  return _formatNumber(number, digits);
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
