import { useEffect, useRef, useState } from 'react';
import {
  Alert,
  Box,
  Button,
  Card,
  CardContent,
  CircularProgress,
  Dialog,
  DialogActions,
  DialogContent,
  DialogTitle,
  Divider,
  Grid,
  IconButton,
  Stack,
  Typography,
} from '@mui/material';
import {
  DeleteOutline,
  DownloadOutlined,
  ImageOutlined,
  RefreshOutlined,
  VisibilityOutlined,
} from '@mui/icons-material';

import { api } from '@/api/axios.js';
import { formatMeasure, formatNumber, safeStem } from '@/components/grain/format.js';
import { GrainStatsCharts } from '@/components/grain/GrainStatsCharts.jsx';
import { useLanguage } from '@/i18n.jsx';
import { useAuthStore } from '@/store/auth.store.js';
import { deleteGuestRun, readGuestRuns } from '@/utils/guestRuns.js';

function reportedStat(summary, rawKey, robustKey) {
  return summary?.qc?.robust_used_for_reporting === false
    ? summary?.[rawKey]
    : (summary?.[robustKey] ?? summary?.[rawKey]);
}

function RunThumbnail({ run, isGuest }) {
  const { text } = useLanguage();
  const hostRef = useRef(null);
  const [overlay, setOverlay] = useState(run.overlay_png_base64 || '');
  const [visible, setVisible] = useState(Boolean(run.overlay_png_base64));

  useEffect(() => {
    setOverlay(run.overlay_png_base64 || '');
    setVisible(Boolean(run.overlay_png_base64));
  }, [run.id, run.overlay_png_base64]);

  useEffect(() => {
    if (overlay || isGuest || !hostRef.current) return undefined;
    const observer = new IntersectionObserver(([entry]) => {
      if (entry.isIntersecting) {
        setVisible(true);
        observer.disconnect();
      }
    }, { rootMargin: '120px' });
    observer.observe(hostRef.current);
    return () => observer.disconnect();
  }, [overlay, isGuest, run.id]);

  useEffect(() => {
    if (!visible || overlay || isGuest) return undefined;
    let active = true;
    api.get(`/grain/runs/${run.id}`)
      .then(({ data }) => {
        if (active) setOverlay(data.data?.result?.overlay_png_base64 || '');
      })
      .catch(() => {});
    return () => {
      active = false;
    };
  }, [visible, overlay, isGuest, run.id]);

  return (
    <Box ref={hostRef} sx={{
      width: 112,
      minWidth: 112,
      height: 112,
      bgcolor: 'rgba(47, 107, 79, 0.08)',
      borderRadius: 1.5,
      border: '1px solid',
      borderColor: 'divider',
      overflow: 'hidden',
      display: 'grid',
      placeItems: 'center',
    }}>
      {overlay ? (
        <Box
          component="img"
          src={`data:image/png;base64,${overlay}`}
          alt={text('Ảnh đánh dấu', 'Overlay image')}
          sx={{ width: '100%', height: '100%', objectFit: 'cover' }}
        />
      ) : (
        <ImageOutlined color="disabled" />
      )}
    </Box>
  );
}

export default function StoragePage() {
  const isGuest = useAuthStore((state) => state.isGuest);
  const { language, text } = useLanguage();
  const [runs, setRuns] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [detailLoading, setDetailLoading] = useState(false);
  const [selected, setSelected] = useState(null);
  const [detailPreviewMode, setDetailPreviewMode] = useState('overlay');

  const loadRuns = async () => {
    setLoading(true);
    setError('');
    try {
      if (isGuest) {
        setRuns(readGuestRuns().map((item) => ({
          ...(item.result?.run || {}),
          id: item.clientRunId,
          sourceFileName: item.sourceFileName,
          createdAt: item.createdAt,
          image: item.result?.image || {},
          summary: item.result?.summary || {},
          calibration: item.result?.calibration || {},
          overlay_png_base64: item.result?.overlay_png_base64 || '',
          localOnly: true,
        })));
        return;
      }
      const { data } = await api.get('/grain/runs', { params: { limit: 100 } });
      setRuns(data.data.items || []);
    } catch (err) {
      setError(err.response?.data?.message || text('Không tải được lịch sử phân tích', 'Could not load analysis history'));
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    loadRuns();
  }, [isGuest]);

  const openDetail = async (runId) => {
    setDetailLoading(true);
    setError('');
    try {
      if (isGuest) {
        const local = readGuestRuns().find((item) => item.clientRunId === runId);
        if (!local) throw new Error(text('Không tìm thấy bản xử lý local', 'Local analysis run was not found'));
        setSelected({
          run: {
            ...(local.result?.run || {}),
            id: local.clientRunId,
            sourceFileName: local.sourceFileName,
            createdAt: local.createdAt,
          },
          result: local.result,
        });
        setDetailPreviewMode('overlay');
        return;
      }
      const { data } = await api.get(`/grain/runs/${runId}`);
      setSelected(data.data);
      setDetailPreviewMode('overlay');
    } catch (err) {
      setError(err.response?.data?.message || text('Không tải được chi tiết xử lý', 'Could not load analysis details'));
    } finally {
      setDetailLoading(false);
    }
  };

  const deleteRun = async (run) => {
    const ok = window.confirm(`${text('Xóa lần xử lý', 'Delete analysis run')} ${shortRunId(run.id)}?`);
    if (!ok) return;

    try {
      if (isGuest) {
        deleteGuestRun(run.id);
        setRuns((current) => current.filter((item) => item.id !== run.id));
        if (selected?.run?.id === run.id) setSelected(null);
        return;
      }
      await api.delete(`/grain/runs/${run.id}`);
      setRuns((current) => current.filter((item) => item.id !== run.id));
      if (selected?.run?.id === run.id) setSelected(null);
    } catch (err) {
      setError(err.response?.data?.message || text('Xóa lần xử lý thất bại', 'Could not delete analysis run'));
    }
  };

  const detailResult = selected?.result;
  const detailRun = selected?.run;
  const detailPreviewImages = {
    original: detailResult?.original_png_base64,
    preprocessed: detailResult?.preprocessed_png_base64,
    overlay: detailResult?.overlay_png_base64,
    mask: detailResult?.mask_png_base64,
    labels: detailResult?.labels_png_base64,
  };
  const detailPreviewImage = detailPreviewImages[detailPreviewMode] || detailResult?.overlay_png_base64;

  return (
    <Box sx={{ maxWidth: 1200, minWidth: 0 }}>
      <Box sx={{ display: 'flex', justifyContent: 'space-between', gap: 2, mb: 2.5, flexWrap: 'wrap' }}>
        <Box>
          <Typography variant="h5" fontWeight={700} mb={0.75}>{text('Lưu trữ', 'Storage')}</Typography>
          {isGuest && (
            <Typography variant="body2" color="text.secondary">
              {text('Dữ liệu đang được lưu trên thiết bị này. Đăng nhập để đồng bộ lên tài khoản của bạn.', 'Data is saved on this device. Log in to sync it to your account.')}
            </Typography>
          )}
        </Box>
        <IconButton color="primary" onClick={loadRuns} disabled={loading} aria-label={text('Làm mới', 'Refresh')}>
          <RefreshOutlined />
        </IconButton>
      </Box>

      {error && <Alert severity="error" sx={{ mb: 2 }}>{error}</Alert>}

      {loading ? (
        <Card>
          <CardContent sx={{ py: 5, textAlign: 'center' }}>
            <CircularProgress size={28} />
          </CardContent>
        </Card>
      ) : runs.length ? (
        <Grid container spacing={2}>
          {runs.map((run) => (
            <Grid item xs={12} md={6} key={run.id}>
              <Card sx={{ height: '100%' }}>
                <CardContent sx={{ display: 'flex', gap: 1.5, alignItems: 'stretch' }}>
                  <RunThumbnail run={run} isGuest={isGuest} />
                  <Stack spacing={0.75} sx={{ minWidth: 0, flexGrow: 1 }}>
                    <Typography variant="body1" fontWeight={700} noWrap>
                      {`${run.summary?.count ?? 0} ${text('hạt', 'grains')} - ${formatDate(run.createdAt, language)}`}
                    </Typography>
                    <Typography variant="body2" fontWeight={650} color="text.primary">
                      {text('ĐLC', 'SD')}: {formatPair(
                        reportedStat(run.summary, 'std_length_mm', 'robust_std_length_mm'),
                        reportedStat(run.summary, 'std_width_mm', 'robust_std_width_mm'),
                        reportedStat(run.summary, 'std_length_px', 'robust_std_length_px'),
                        reportedStat(run.summary, 'std_width_px', 'robust_std_width_px'),
                        run.calibration?.enabled === true,
                      )}
                    </Typography>
                    <Typography variant="body2" fontWeight={650} color="text.primary">
                      {text('TB', 'Avg')}: {formatPair(
                        run.summary?.mean_length_mm,
                        run.summary?.mean_width_mm,
                        run.summary?.mean_length_px,
                        run.summary?.mean_width_px,
                        run.calibration?.enabled === true,
                      )}
                    </Typography>
                    <Stack direction="row" spacing={0.5} sx={{ mt: 'auto' }}>
                      <Button size="small" startIcon={<VisibilityOutlined />} onClick={() => openDetail(run.id)} disabled={detailLoading}>{text('Xem', 'View')}</Button>
                      <Button size="small" color="error" startIcon={<DeleteOutline />} onClick={() => deleteRun(run)}>{text('Xóa', 'Delete')}</Button>
                    </Stack>
                  </Stack>
                </CardContent>
              </Card>
            </Grid>
          ))}
        </Grid>
      ) : (
        <Alert severity="info">{text('Chưa có dữ liệu.', 'No data yet.')}</Alert>
      )}

      <Dialog open={Boolean(selected)} onClose={() => setSelected(null)} maxWidth="lg" fullWidth>
        <DialogTitle>{text('Chi tiết xử lý', 'Analysis detail')} {detailRun ? shortRunId(detailRun.id) : ''}</DialogTitle>
        <DialogContent dividers>
          {detailResult && (
            <Grid container spacing={2}>
              <Grid item xs={12} md={7}>
                <Box sx={{
                  display: 'flex',
                  flexWrap: 'wrap',
                  gap: 1,
                  mb: 1.5,
                }}>
                  {[
                    ['original', text('Ảnh gốc', 'Original')],
                    ['overlay', text('Đánh dấu', 'Overlay')],
                    ['mask', text('Hình dạng', 'Mask')],
                    ['labels', text('Đánh số', 'Labels')],
                  ].map(([key, label]) => (
                    <Button
                      key={key}
                      size="small"
                      variant={detailPreviewMode === key ? 'contained' : 'outlined'}
                      disabled={!detailPreviewImages[key]}
                      onClick={() => setDetailPreviewMode(key)}
                      sx={{
                        flex: '0 1 auto',
                        minWidth: 0,
                        maxWidth: '100%',
                        whiteSpace: 'nowrap',
                      }}
                    >
                      {label}
                    </Button>
                  ))}
                </Box>
                <Box sx={{
                  border: '1px solid',
                  borderColor: 'divider',
                  borderRadius: 1,
                  bgcolor: '#FBFCFA',
                  minHeight: 320,
                  width: '100%',
                  display: 'grid',
                  placeItems: 'center',
                  overflow: 'hidden',
                }}>
                  {detailPreviewImage ? (
                    <Box
                      component="img"
                      src={`data:image/png;base64,${detailPreviewImage}`}
                      alt={detailRun?.sourceFileName || 'overlay'}
                      sx={{ width: '100%', maxHeight: 420, objectFit: 'contain', display: 'block' }}
                    />
                  ) : (
                    <Typography variant="body2" color="text.secondary">{text('Không có overlay', 'No overlay')}</Typography>
                  )}
                </Box>
              </Grid>
              <Grid item xs={12} md={5}>
                <Stack spacing={1.2}>
                  <ResultRow label={text('Tên tệp ảnh', 'Image file name')} value={detailRun?.sourceFileName || '-'} />
                  <ResultRow label={text('Thời gian quét', 'Scan time')} value={formatDate(detailRun?.createdAt, language)} />
                  <ResultRow label={text('Tổng số hạt đo được', 'Total measured grains')} value={detailResult.summary?.count ?? 0} />
                  <ResultRow label={text('ĐLC chiều dài (báo cáo)', 'Length SD (reported)')} value={formatStorageMeasure(detailResult.calibration, reportedStat(detailResult.summary, 'std_length_mm', 'robust_std_length_mm'), 'mm', reportedStat(detailResult.summary, 'std_length_px', 'robust_std_length_px'), 'px')} />
                  <ResultRow label={text('ĐLC chiều rộng (báo cáo)', 'Width SD (reported)')} value={formatStorageMeasure(detailResult.calibration, reportedStat(detailResult.summary, 'std_width_mm', 'robust_std_width_mm'), 'mm', reportedStat(detailResult.summary, 'std_width_px', 'robust_std_width_px'), 'px')} />
                  <ResultRow label={text('ĐLC diện tích (báo cáo)', 'Area SD (reported)')} value={formatStorageMeasure(detailResult.calibration, reportedStat(detailResult.summary, 'std_area_mm2', 'robust_std_area_mm2'), 'mm2', reportedStat(detailResult.summary, 'std_area_px', 'robust_std_area_px'), 'px2')} />
                  <ResultRow label={text('Hạt nghi ngờ sau kiểm tra', 'Suspect grains after QC')} value={String(detailResult.summary?.qc?.suspect_count ?? 0)} />
                  <ResultRow label={text('Tỷ lệ thước đo', 'Scale ratio')} value={detailResult.calibration?.enabled ? `${formatNumber(detailResult.calibration.mm_per_pixel, 5)} mm/px` : text('Chưa thiết lập', 'Not set')} />

                  <Divider sx={{ my: 0.5 }} />
                  <Box>
                    <Typography variant="subtitle2" fontWeight={800} mb={0.75}>
                      {text('Tóm tắt kích thước đã lưu', 'Saved size summary')}
                    </Typography>
                    <GrainStatsCharts result={detailResult} compact />
                  </Box>
                  <Divider />
                  <Stack direction={{ xs: 'column', sm: 'row' }} spacing={1} useFlexGap flexWrap="wrap" pt={1}>
                    <Button
                      variant="contained"
                      startIcon={<DownloadOutlined />}
                      disabled={!detailResult.csv}
                      onClick={() => downloadBlob(`${safeStem(detailRun?.sourceFileName)}_measurements.csv`, detailResult.csv, 'text/csv;charset=utf-8')}
                    >
                      {text('Xuất CSV', 'Export CSV')}
                    </Button>
                    <Button
                      variant="outlined"
                      startIcon={<DownloadOutlined />}
                      disabled={!detailResult.overlay_png_base64}
                      onClick={() => downloadPng(detailRun?.sourceFileName, detailResult.overlay_png_base64)}
                    >
                      {text('Xuất ảnh kết quả', 'Export result image')}
                    </Button>
                  </Stack>
                </Stack>
              </Grid>
            </Grid>
          )}
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setSelected(null)}>{text('Đóng', 'Close')}</Button>
        </DialogActions>
      </Dialog>
    </Box>
  );
}

const ResultRow = ({ label, value }) => (
  <Box sx={{
    display: 'grid',
    gridTemplateColumns: { xs: '1fr', sm: 'minmax(92px, max-content) minmax(0, 1fr)' },
    alignItems: 'start',
    gap: { xs: 0.25, sm: 2 },
  }}>
    <Typography variant="body2" color="text.secondary" sx={{ minWidth: 0 }}>{label}</Typography>
    <Typography
      variant="body2"
      fontWeight={650}
      textAlign={{ xs: 'left', sm: 'right' }}
      sx={{ minWidth: 0, overflowWrap: 'anywhere' }}
    >
      {value}
    </Typography>
  </Box>
);

const shortRunId = (id = '') => id ? `RUN-${id.slice(-8).toUpperCase()}` : 'RUN';

const formatDate = (value, language = 'vi') => {
  if (!value) return '-';
  return new Intl.DateTimeFormat(language === 'en' ? 'en-US' : 'vi-VN', {
    dateStyle: 'short',
    timeStyle: 'short',
  }).format(new Date(value));
};

const formatPair = (lengthMm, widthMm, lengthPx, widthPx, calibrated) => {
  const hasMm = calibrated && lengthMm != null && widthMm != null;
  return hasMm
    ? `${formatStorageMeasure({ enabled: true }, lengthMm, 'mm', lengthPx, 'px')} x ${formatStorageMeasure({ enabled: true }, widthMm, 'mm', widthPx, 'px')}`
    : `${formatMeasure(null, 'mm', lengthPx, 'px')} x ${formatMeasure(null, 'mm', widthPx, 'px')}`;
};

const formatStorageMeasure = (calibration, mmValue, mmUnit, pxValue, pxUnit) => (
  calibration?.enabled === true && mmValue != null
    ? `${Number(mmValue).toFixed(mmUnit === 'mm2' ? 3 : 2)} ${mmUnit}`
    : formatMeasure(null, mmUnit, pxValue, pxUnit)
);


const downloadBlob = (fileName, content, mimeType) => {
  const blob = new Blob([content], { type: mimeType });
  const url = URL.createObjectURL(blob);
  const link = document.createElement('a');
  link.href = url;
  link.download = fileName;
  link.click();
  URL.revokeObjectURL(url);
};

const downloadPng = (sourceName, base64) => {
  const link = document.createElement('a');
  link.href = `data:image/png;base64,${base64}`;
  link.download = `${safeStem(sourceName)}_segmentation.png`;
  link.click();
};
