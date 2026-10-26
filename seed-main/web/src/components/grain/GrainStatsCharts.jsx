import { useMemo, useState } from "react";
import {
  Alert,
  Box,
  Button,
  Card,
  CardContent,
  Dialog,
  DialogContent,
  DialogTitle,
  IconButton,
  Stack,
  Tooltip,
  Typography,
} from "@mui/material";
import HelpOutlineIcon from "@mui/icons-material/HelpOutline";

import { formatNumber } from "./format.js";

const SIZE_GROUPS = [
  { key: "small", label: "Nhỏ hơn đa số", color: "#60a5fa" },
  { key: "typical", label: "Cỡ thường gặp", color: "#2f6b4f" },
  { key: "large", label: "Lớn hơn đa số", color: "#f59e0b" },
];

const CHART_CHOICES = [
  { key: "length", label: "Chiều dài" },
  { key: "width", label: "Chiều rộng" },
  { key: "area", label: "Diện tích" },
  { key: "all", label: "Tất cả" },
];

const METRIC_DEFS = {
  length: {
    title: "Phân bố chiều dài",
    pxKey: "length_px",
    mmKey: "length_mm",
    pxUnit: "px",
    mmUnit: "mm",
    pxDigits: 1,
    mmDigits: 2,
    color: "#2f6b4f",
  },
  width: {
    title: "Phân bố chiều rộng",
    pxKey: "width_px",
    mmKey: "width_mm",
    pxUnit: "px",
    mmUnit: "mm",
    pxDigits: 1,
    mmDigits: 2,
    color: "#2563eb",
  },
  area: {
    title: "Phân bố diện tích",
    pxKey: "area_px",
    mmKey: "area_mm2",
    pxUnit: "px²",
    mmUnit: "mm²",
    pxDigits: 0,
    mmDigits: 3,
    color: "#d97706",
  },
};

const toFiniteNumber = (value) => {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
};

const clamp = (value, min, max) => Math.max(min, Math.min(max, value));

const round = (value, digits = 2) => {
  const factor = 10 ** digits;
  return Math.round(value * factor) / factor;
};

const compactLabelNumber = (value, digits) => {
  const number = Number(value);
  if (!Number.isFinite(number)) return "-";
  if (Math.abs(number) >= 1000000)
    return `${formatNumber(number / 1000000, 1)}m`;
  if (Math.abs(number) >= 1000) return `${formatNumber(number / 1000, 1)}k`;
  return formatNumber(number, digits);
};

const percentile = (sortedValues, ratio) => {
  if (!sortedValues.length) return null;
  const index = (sortedValues.length - 1) * clamp(ratio, 0, 1);
  const lower = Math.floor(index);
  const upper = Math.ceil(index);
  if (lower === upper) return sortedValues[lower];
  const weight = index - lower;
  return sortedValues[lower] * (1 - weight) + sortedValues[upper] * weight;
};

const pickMetric = (measurements, calibrationEnabled, metricDef) => {
  if (!measurements.length || !calibrationEnabled) {
    return {
      key: metricDef.pxKey,
      unit: metricDef.pxUnit,
      digits: metricDef.pxDigits,
    };
  }
  const metricReadyCount = measurements.reduce((count, measurement) => {
    const value = toFiniteNumber(measurement?.[metricDef.mmKey]);
    return value && value > 0 ? count + 1 : count;
  }, 0);
  if (metricReadyCount >= Math.max(3, measurements.length * 0.6)) {
    return {
      key: metricDef.mmKey,
      unit: metricDef.mmUnit,
      digits: metricDef.mmDigits,
    };
  }
  return {
    key: metricDef.pxKey,
    unit: metricDef.pxUnit,
    digits: metricDef.pxDigits,
  };
};

const buildDistribution = (measurements, calibrationEnabled, metricKey) => {
  const metricDef = METRIC_DEFS[metricKey];
  const metric = pickMetric(measurements, calibrationEnabled, metricDef);
  const values = measurements
    .filter((measurement) => measurement?.qc_outlier !== true)
    .map((measurement) => toFiniteNumber(measurement?.[metric.key]))
    .filter((value) => value && value > 0)
    .sort((a, b) => a - b);
  if (!values.length) return null;

  const min = values[0];
  const max = values[values.length - 1];
  const mean = values.reduce((sum, value) => sum + value, 0) / values.length;
  const variance = values.reduce(
    (sum, value) => sum + (value - mean) ** 2,
    0,
  ) / values.length;
  const standardDeviation = Math.sqrt(variance);
  const binCount =
    values.length < 4
      ? Math.max(1, values.length)
      : clamp(Math.round(Math.sqrt(values.length)), 4, 8);
  const bins = [];
  if (min === max || binCount === 1) {
    bins.push({ start: min, end: max, count: values.length });
  } else {
    const width = (max - min) / binCount;
    for (let index = 0; index < binCount; index += 1) {
      bins.push({
        start: min + width * index,
        end: index === binCount - 1 ? max : min + width * (index + 1),
        count: 0,
      });
    }
    values.forEach((value) => {
      const index = clamp(
        Math.floor((value - min) / Math.max(width, Number.EPSILON)),
        0,
        bins.length - 1,
      );
      bins[index].count += 1;
    });
  }

  return {
    key: metricKey,
    title: metricDef.title,
    color: metricDef.color,
    unit: metric.unit,
    digits: metric.digits,
    sampleCount: values.length,
    sortedValues: values,
    midpoint: percentile(values, 0.5),
    low: percentile(values, 0.1),
    high: percentile(values, 0.9),
    cvPct: mean > 0 ? round((standardDeviation / mean) * 100, 1) : 0,
    bins: bins.map((bin) => ({
      ...bin,
      pct: round((bin.count / values.length) * 100, 1),
      label:
        bin.start === bin.end
          ? formatNumber(bin.start, metric.digits)
          : `${formatNumber(bin.start, metric.digits)}-${formatNumber(bin.end, metric.digits)}`,
      shortLabel:
        bin.start === bin.end
          ? compactLabelNumber(bin.start, metric.digits)
          : `${compactLabelNumber(bin.start, metric.digits)}+`,
    })),
  };
};

const buildSizeGroups = (values, midpoint) => {
  if (!values.length || !midpoint || midpoint <= 0) return [];
  const counts = { small: 0, typical: 0, large: 0 };
  values.forEach((value) => {
    const ratio = value / midpoint;
    if (ratio < 0.9) counts.small += 1;
    else if (ratio <= 1.1) counts.typical += 1;
    else counts.large += 1;
  });

  return SIZE_GROUPS.map((group) => ({
    ...group,
    count: counts[group.key],
    pct: round((counts[group.key] / values.length) * 100, 1),
  }));
};

const buildChartModel = (result) => {
  if (!result) return null;
  const measurements = Array.isArray(result.measurements)
    ? result.measurements
    : [];
  if (!measurements.length) return null;

  const calibrationEnabled = result.calibration?.enabled === true;
  const lengthDistribution = buildDistribution(
    measurements,
    calibrationEnabled,
    "length",
  );
  if (!lengthDistribution) return null;

  const d50 = lengthDistribution.midpoint;
  const measuredSuspects = measurements.reduce(
    (count, measurement) =>
      measurement?.qc_outlier === true ? count + 1 : count,
    0,
  );
  const summarySuspects = Number(result.summary?.qc?.suspect_count);
  const suspectCount = Number.isFinite(summarySuspects)
    ? clamp(summarySuspects, 0, measurements.length)
    : measuredSuspects;
  const suspectPct = round((suspectCount / measurements.length) * 100, 1);

  return {
    metric: {
      unit: lengthDistribution.unit,
      digits: lengthDistribution.digits,
    },
    sampleCount: lengthDistribution.sampleCount,
    totalCount: measurements.length,
    midpoint: d50,
    suspectCount,
    suspectPct,
    distributions: {
      length: lengthDistribution,
      width: buildDistribution(measurements, calibrationEnabled, "width"),
      area: buildDistribution(measurements, calibrationEnabled, "area"),
    },
  };
};

const SegmentBar = ({ groups }) => (
  <Box
    sx={{
      display: "flex",
      width: "100%",
      height: 14,
      overflow: "hidden",
      borderRadius: 999,
      bgcolor: "grey.100",
    }}
  >
    {groups.map((group) => (
      <Box
        key={group.key}
        sx={{
          width: `${group.pct}%`,
          minWidth: group.count > 0 ? 4 : 0,
          bgcolor: group.color,
        }}
      />
    ))}
  </Box>
);

const MetricRow = ({ label, value, helper }) => (
  <Box sx={{ minWidth: 0 }}>
    <Typography variant="body2" color="text.secondary">
      {label}
    </Typography>
    <Typography variant="h6" fontWeight={800} sx={{ lineHeight: 1.25 }}>
      {value}
    </Typography>
    {helper && (
      <Typography variant="caption" color="text.secondary">
        {helper}
      </Typography>
    )}
  </Box>
);

const DistributionChart = ({ distribution, compact = false }) => {
  if (!distribution) return null;
  const maxCount = Math.max(1, ...distribution.bins.map((bin) => bin.count));
  return (
    <Box
      sx={{
        border: "1px solid",
        borderColor: "divider",
        borderRadius: 1,
        p: compact ? 1 : 1.25,
      }}
    >
      <Stack
        direction={{ xs: "column", sm: "row" }}
        justifyContent="space-between"
        alignItems={{ xs: "flex-start", sm: "baseline" }}
        gap={0.5}
        mb={1}
      >
        <Box>
          <Typography variant="body2" fontWeight={800}>
            {distribution.title}
          </Typography>
          <Typography variant="caption" color="text.secondary">
            Mỗi cột là một nhóm hạt có kích thước gần nhau.
          </Typography>
        </Box>
        <Typography
          variant="caption"
          color="text.secondary"
          sx={{ whiteSpace: "nowrap" }}
        >
          {distribution.sampleCount} hạt
        </Typography>
      </Stack>
      <Box
        sx={{
          display: "flex",
          alignItems: "end",
          gap: 0.75,
          height: compact ? 130 : 150,
          pt: 1,
        }}
      >
        {distribution.bins.map((bin) => (
          <Box
            key={bin.label}
            sx={{
              flex: 1,
              minWidth: 0,
              display: "flex",
              flexDirection: "column",
              alignItems: "center",
              gap: 0.5,
            }}
          >
            <Typography variant="caption" fontWeight={800}>
              {bin.count}
            </Typography>
            <Box
              title={`${bin.label} ${distribution.unit}: ${bin.count} hạt`}
              sx={{
                width: "100%",
                maxWidth: 42,
                minHeight: bin.count > 0 ? 8 : 2,
                height: `${Math.max(3, (bin.count / maxCount) * 92)}%`,
                bgcolor: distribution.color,
                borderRadius: "4px 4px 0 0",
              }}
            />
          </Box>
        ))}
      </Box>
      <Box
        sx={{
          display: "grid",
          gridTemplateColumns: `repeat(${distribution.bins.length}, minmax(0, 1fr))`,
          gap: 0.75,
          mt: 0.75,
        }}
      >
        {distribution.bins.map((bin) => (
          <Typography
            key={bin.label}
            title={`${bin.label} ${distribution.unit}`}
            variant="caption"
            color="text.secondary"
            textAlign="center"
            sx={{
              whiteSpace: "nowrap",
              overflow: "hidden",
              textOverflow: "clip",
              fontSize: compact ? 10 : 11,
              lineHeight: 1.2,
            }}
          >
            {bin.shortLabel}
          </Typography>
        ))}
      </Box>
    </Box>
  );
};

const SummaryCards = ({
  distributions,
  chartMode,
  totalCount,
  suspectCount,
  suspectPct,
}) => {
  const keys = chartMode === "all" ? ["length", "width", "area"] : [chartMode];
  return (
    <Box
      sx={{
        display: "grid",
        gridTemplateColumns: {
          xs: "1fr",
          sm: chartMode === "all" ? "1fr" : "repeat(3, minmax(0, 1fr))",
          md: "repeat(3, minmax(0, 1fr))",
        },
        gap: 1.5,
      }}
    >
      {keys.map((key) => {
        const distribution = distributions[key];
        if (!distribution) return null;
        return (
          <Box
            key={key}
            sx={{
              p: 1.5,
              border: "1px solid",
              borderColor: "divider",
              borderRadius: 1,
              bgcolor: "#FBFCFA",
            }}
          >
            <Typography variant="body2" color="text.secondary">
              {distribution.title.replace("Phân bố ", "Cỡ thường gặp theo ")}
            </Typography>
            <Typography variant="h6" fontWeight={800} sx={{ lineHeight: 1.25 }}>
              {formatNumber(distribution.midpoint, distribution.digits)}{" "}
              {distribution.unit}
            </Typography>
            <Typography variant="caption" color="text.secondary">
              Khoảng phổ biến:{" "}
              {formatNumber(distribution.low, distribution.digits)}-
              {formatNumber(distribution.high, distribution.digits)}{" "}
              {distribution.unit}
            </Typography>
          </Box>
        );
      })}
      {chartMode !== "all" && (
        <Box
          sx={{
            p: 1.5,
            border: "1px solid",
            borderColor: "divider",
            borderRadius: 1,
            bgcolor: "#FBFCFA",
          }}
        >
          <Typography variant="body2" color="text.secondary">
            Độ biến thiên (CV)
          </Typography>
          <Typography variant="h6" fontWeight={800} sx={{ lineHeight: 1.25 }}>
            {formatNumber(distributions[chartMode]?.cvPct, 1)}%
          </Typography>
          <Typography variant="caption" color="text.secondary">
            Độ lệch chuẩn / trung bình của các hạt hợp lệ.
          </Typography>
        </Box>
      )}
      {chartMode !== "all" && (
        <Box
          sx={{
            p: 1.5,
            border: "1px solid",
            borderColor: "divider",
            borderRadius: 1,
            bgcolor: "#FBFCFA",
          }}
        >
          <Typography variant="body2" color="text.secondary">
            Hạt cần xem lại
          </Typography>
          <Typography variant="h6" fontWeight={800} sx={{ lineHeight: 1.25 }}>
            {suspectCount}/{totalCount}
          </Typography>
          <Typography variant="caption" color="text.secondary">
            {formatNumber(suspectPct, 1)}% tổng số hạt.
          </Typography>
        </Box>
      )}
    </Box>
  );
};

const SizeGroupRows = ({ distribution }) => {
  if (!distribution?.sortedValues?.length || !distribution.midpoint)
    return null;
  const groups = buildSizeGroups(
    distribution.sortedValues,
    distribution.midpoint,
  );
  return (
    <Box>
      <Typography variant="body2" fontWeight={700} mb={0.75}>
        Nhóm kích thước theo{" "}
        {distribution.title.replace("Phân bố ", "").toLowerCase()}
      </Typography>
      <SegmentBar groups={groups} />
      <Stack spacing={0.75} mt={1}>
        {groups.map((group) => (
          <Stack
            key={group.key}
            direction={{ xs: "column", sm: "row" }}
            spacing={{ xs: 0.25, sm: 1 }}
            alignItems={{ xs: "flex-start", sm: "center" }}
          >
            <Box
              sx={{
                width: 10,
                height: 10,
                borderRadius: 0.75,
                bgcolor: group.color,
                flex: "0 0 auto",
              }}
            />
            <Typography variant="body2" sx={{ flex: 1, minWidth: 0 }}>
              {group.label}
            </Typography>
            <Typography
              variant="body2"
              fontWeight={700}
              sx={{
                alignSelf: { xs: "flex-end", sm: "center" },
                textAlign: "right",
              }}
            >
              {group.count} hạt ({formatNumber(group.pct, 1)}%)
            </Typography>
          </Stack>
        ))}
      </Stack>
    </Box>
  );
};

const HelpDialog = ({ open, onClose }) => (
  <Dialog
    open={open}
    onClose={onClose}
    maxWidth="sm"
    fullWidth
    PaperProps={{ sx: { maxHeight: "calc(100dvh - 32px)" } }}
  >
    <DialogTitle>Cách đọc phần kích thước</DialogTitle>
    <DialogContent>
      <Stack spacing={1.5}>
        <Typography variant="body2">
          Chọn `Chiều dài`, `Chiều rộng` hoặc `Diện tích` để các thẻ số, nhóm
          kích thước và biểu đồ cùng đổi theo chỉ số đó.
        </Typography>
        <Typography variant="body2">
          `Cỡ thường gặp` là trung vị: khoảng một nửa số hạt nhỏ hơn mức này,
          một nửa lớn hơn.
        </Typography>
        <Typography variant="body2">
          `Khoảng phổ biến` cho biết vùng kích thước mà phần lớn hạt rơi vào.
          Mỗi cột trong biểu đồ là một khoảng kích thước; số trên cột là số hạt
          trong khoảng đó.
        </Typography>
        <Typography variant="body2">
          Số dưới cột là điểm bắt đầu của khoảng. Ví dụ cột `5+`, cột kế tiếp là
          `8+`, thì cột `5+` chứa các hạt có kích thước trong nửa khoảng [5; 8).
        </Typography>
        <Box
          sx={{
            display: "flex",
            alignItems: "end",
            gap: 1,
            height: 86,
            px: 1,
            pt: 1,
            border: "1px solid",
            borderColor: "divider",
            borderRadius: 1,
          }}
        >
          {[22, 44, 72, 56, 28].map((height, index) => (
            <Box key={height} sx={{ flex: 1, textAlign: "center" }}>
              <Typography variant="caption" fontWeight={800}>
                {[3, 8, 14, 10, 5][index]}
              </Typography>
              <Box
                sx={{
                  height,
                  bgcolor: "#2f6b4f",
                  borderRadius: "4px 4px 0 0",
                  mt: 0.5,
                }}
              />
            </Box>
          ))}
        </Box>
      </Stack>
    </DialogContent>
  </Dialog>
);

export function GrainStatsCharts({ result, compact = false }) {
  const model = useMemo(() => buildChartModel(result), [result]);
  const [chartMode, setChartMode] = useState("length");
  const [helpOpen, setHelpOpen] = useState(false);

  if (!model) {
    return (
      <Alert severity="info">Chưa đủ dữ liệu hạt để xem kích thước.</Alert>
    );
  }

  const visibleCharts =
    chartMode === "all" ? ["length", "width", "area"] : [chartMode];
  const primaryDistribution =
    model.distributions[chartMode === "all" ? "length" : chartMode];

  return (
    <Card variant="outlined">
      <CardContent sx={{ p: compact ? 1.5 : 2 }}>
        <Stack spacing={1.75}>
          <Stack
            direction={{ xs: "column", sm: "row" }}
            spacing={1}
            alignItems={{ xs: "flex-start", sm: "center" }}
            justifyContent="space-between"
          >
            <Box>
              <Stack direction="row" alignItems="center" spacing={0.5}>
                <Typography variant="subtitle1" fontWeight={800}>
                  Kích thước hạt
                </Typography>
                <IconButton
                  size="small"
                  onClick={() => setHelpOpen(true)}
                  aria-label="Cách đọc kích thước"
                >
                  <HelpOutlineIcon fontSize="small" />
                </IconButton>
              </Stack>
              <Typography variant="body2" color="text.secondary">
                Chọn chỉ số muốn xem để đọc đúng theo chiều dài, chiều rộng hoặc
                diện tích.
              </Typography>
            </Box>
          </Stack>

          <Box sx={{ display: "flex", flexWrap: "wrap", gap: 0.75 }}>
            {CHART_CHOICES.map((choice) => (
              <Button
                key={choice.key}
                size="small"
                variant={chartMode === choice.key ? "contained" : "outlined"}
                onClick={() => setChartMode(choice.key)}
                sx={{
                  textTransform: "none",
                  flex: { xs: "1 1 calc(50% - 6px)", sm: "0 0 auto" },
                  minWidth: { xs: 0, sm: 88 },
                }}
              >
                {choice.label}
              </Button>
            ))}
          </Box>

          <SummaryCards
            distributions={model.distributions}
            chartMode={chartMode}
            totalCount={model.totalCount}
            suspectCount={model.suspectCount}
            suspectPct={model.suspectPct}
          />

          {chartMode === "all" ? (
            <Stack spacing={1.25}>
              {["length", "width", "area"].map((key) => (
                <SizeGroupRows
                  key={key}
                  distribution={model.distributions[key]}
                />
              ))}
            </Stack>
          ) : (
            <SizeGroupRows distribution={primaryDistribution} />
          )}

          <Box>
            <Stack
              direction={{ xs: "column", sm: "row" }}
              spacing={1}
              justifyContent="space-between"
              alignItems={{ xs: "stretch", sm: "center" }}
              mb={1}
            >
              <Stack direction="row" alignItems="center" spacing={0.5}>
                <Typography variant="body2" fontWeight={800}>
                  Biểu đồ phân bố
                </Typography>
                <Tooltip title="Cách đọc biểu đồ">
                  <IconButton
                    size="small"
                    onClick={() => setHelpOpen(true)}
                    aria-label="Cách đọc biểu đồ"
                    sx={{ width: 30, height: 30 }}
                  >
                    <HelpOutlineIcon fontSize="small" />
                  </IconButton>
                </Tooltip>
              </Stack>
            </Stack>
            <Stack spacing={1}>
              {visibleCharts.map((key) => (
                <DistributionChart
                  key={key}
                  distribution={model.distributions[key]}
                  compact={compact}
                />
              ))}
            </Stack>
          </Box>
          <HelpDialog open={helpOpen} onClose={() => setHelpOpen(false)} />
        </Stack>
      </CardContent>
    </Card>
  );
}
