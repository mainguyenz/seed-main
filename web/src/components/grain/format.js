export const formatNumber = (value, digits = 2) => (
  Number.isFinite(Number(value)) ? Number(value).toFixed(digits) : '-'
);

export const formatMeasure = (primary, primaryUnit, fallback, fallbackUnit) => {
  const isArea = primaryUnit === 'mm2' || primaryUnit === 'mm²';
  return Number.isFinite(Number(primary)) && Number(primary) > 0
    ? `${formatNumber(primary, isArea ? 3 : 2)} ${primaryUnit}`
    : `${formatNumber(fallback)} ${fallbackUnit}`;
};

export const safeStem = (name = 'seed-image') => (
  name.replace(/\.[^.]+$/, '').replace(/[^a-z0-9_-]+/gi, '_') || 'seed-image'
);

export const formatAnalysisMethod = (segmentation = {}) => (
  segmentation.execution === 'mobile_onnxruntime'
    ? 'Xử lý trực tiếp trên thiết bị'
    : 'Xử lý qua hệ thống trực tuyến'
);
