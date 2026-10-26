import { useEffect, useRef, useState } from 'react';
import { Box, Grid, Stack, Typography } from '@mui/material';

import { api, ensureFreshAccessToken, publicApi } from '@/api/axios.js';
import { useAuthStore } from '@/store/auth.store.js';
import { DashboardPreviewPanel } from '@/components/grain/DashboardPreviewPanel.jsx';
import { DashboardResultPanel } from '@/components/grain/DashboardResultPanel.jsx';
import { formatMeasure, safeStem } from '@/components/grain/format.js';
import { GrainStatsCharts } from '@/components/grain/GrainStatsCharts.jsx';
import { StatCard } from '@/components/grain/StatCard.jsx';
import { useLanguage } from '@/i18n.jsx';
import { saveGuestRun, updateGuestRunResult } from '@/utils/guestRuns.js';

const emptyCalibration = { start: null, end: null, referenceMm: '' };
const DETECTED_REFERENCE_MM = 23;

const suggestedReferencePoint = (suggestion, xKey, yKey) => {
  const x = Number(suggestion?.[xKey]);
  const y = Number(suggestion?.[yKey]);
  if (!Number.isFinite(x) || !Number.isFinite(y) || x < 0 || y < 0) return null;
  return { x, y };
};

export default function DashboardPage() {
  const isGuest = useAuthStore((state) => state.isGuest);
  const { text } = useLanguage();
  const videoRef = useRef(null);
  const imageRef = useRef(null);
  const [cameraActive, setCameraActive] = useState(false);
  const [previewUrl, setPreviewUrl] = useState('');
  const [imageFile, setImageFile] = useState(null);
  const [fileName, setFileName] = useState('');
  const [cameraError, setCameraError] = useState('');
  const [processing, setProcessing] = useState(false);
  const [processError, setProcessError] = useState('');
  const [result, setResult] = useState(null);
  const [previewMode, setPreviewMode] = useState('overlay');
  const [calibration, setCalibration] = useState(emptyCalibration);
  const [calibrationPreviewRequested, setCalibrationPreviewRequested] = useState(false);
  const [drawingCalibration, setDrawingCalibration] = useState(false);
  const [qcEditMode, setQcEditMode] = useState(false);
  const [progress, setProgress] = useState(0);
  const [progressPhase, setProgressPhase] = useState('');
  const progressTimerRef = useRef(null);
  const qcRenderSeqRef = useRef(0);

  useEffect(() => () => {
    if (videoRef.current?.srcObject) {
      videoRef.current.srcObject.getTracks().forEach((track) => track.stop());
    }
  }, []);

  const resetRunState = () => {
    qcRenderSeqRef.current += 1;
    setResult(null);
    setPreviewMode('overlay');
    setCalibration(emptyCalibration);
    setCalibrationPreviewRequested(false);
    setQcEditMode(false);
  };

  const handleCamera = async () => {
    setCameraError('');
    setProcessError('');
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ video: true });
      if (videoRef.current) videoRef.current.srcObject = stream;
      setImageFile(null);
      setPreviewUrl('');
      setFileName('camera-frame.png');
      setCameraActive(true);
      resetRunState();
    } catch {
      setCameraError(text('Không thể kết nối camera. Kiểm tra quyền truy cập hoặc thiết bị.', 'Could not connect to the camera. Check permission or device access.'));
    }
  };

  const handleFile = (event) => {
    const file = event.target.files?.[0];
    if (!file) return;

    setPreviewUrl('');
    setImageFile(file);
    setFileName(file.name);
    setCameraActive(false);
    setProcessError('');
    resetRunState();

    const reader = new FileReader();
    reader.onload = () => {
      setPreviewUrl(typeof reader.result === 'string' ? reader.result : '');
    };
    reader.onerror = () => {
      setPreviewUrl('');
      setProcessError(text('Không thể đọc ảnh đã chọn. Vui lòng thử ảnh JPG hoặc PNG khác.', 'Could not read the selected image. Please try another JPG or PNG image.'));
    };
    reader.readAsDataURL(file);

    event.target.value = '';
  };

  const getCalibrationPoint = (event) => {
    const image = imageRef.current;
    if (!image?.naturalWidth || !image?.naturalHeight) return null;
    const rect = image.getBoundingClientRect();
    const x = Math.max(0, Math.min(rect.width, event.clientX - rect.left));
    const y = Math.max(0, Math.min(rect.height, event.clientY - rect.top));
    const coordinateWidth = Number(result?.image?.original_width) || image.naturalWidth;
    const coordinateHeight = Number(result?.image?.original_height) || image.naturalHeight;
    return {
      x: (x / Math.max(1, rect.width)) * coordinateWidth,
      y: (y / Math.max(1, rect.height)) * coordinateHeight,
    };
  };

  const calibrationPixels = calibration.start && calibration.end
    ? Math.hypot(calibration.end.x - calibration.start.x, calibration.end.y - calibration.start.y)
    : 0;
  const calibrationMm = Number(calibration.referenceMm);
  const calibrationLineReady = calibrationPixels > 1;
  const calibrationReady = calibrationLineReady && Number.isFinite(calibrationMm) && calibrationMm > 0;

  useEffect(() => {
    const suggestion = result?.calibration?.suggested_reference;
    if (suggestion?.available !== true) return;
    const start = suggestedReferencePoint(suggestion, 'x1', 'y1');
    const end = suggestedReferencePoint(suggestion, 'x2', 'y2');
    if (!start || !end) return;
    setCalibration((current) => {
      if (current.start && current.end) return current;
      return { ...current, start, end };
    });
  }, [result]);

  const renderCalibrationOverlay = () => {
    const image = imageRef.current;
    if (!image?.naturalWidth || !image?.naturalHeight || !calibration.start || !calibration.end) return null;
    const coordinateWidth = Number(result?.image?.original_width) || image.naturalWidth;
    const coordinateHeight = Number(result?.image?.original_height) || image.naturalHeight;
    const start = {
      x: (calibration.start.x / coordinateWidth) * 100,
      y: (calibration.start.y / coordinateHeight) * 100,
    };
    const end = {
      x: (calibration.end.x / coordinateWidth) * 100,
      y: (calibration.end.y / coordinateHeight) * 100,
    };
    return (
      <Box sx={{ position: 'absolute', inset: 0, pointerEvents: 'none' }}>
        <svg width="100%" height="100%" viewBox="0 0 100 100" preserveAspectRatio="none">
          <line x1={start.x} y1={start.y} x2={end.x} y2={end.y} stroke="#1d4ed8" strokeWidth="0.8" vectorEffect="non-scaling-stroke" />
          <circle cx={start.x} cy={start.y} r="1.8" fill="#1d4ed8" stroke="#ffffff" strokeWidth="0.5" />
          <circle cx={end.x} cy={end.y} r="1.8" fill="#1d4ed8" stroke="#ffffff" strokeWidth="0.5" />
        </svg>
      </Box>
    );
  };

  const getImageForProcessing = async () => {
    if (imageFile) return imageFile;
    if (!cameraActive || !videoRef.current?.videoWidth) return null;

    const video = videoRef.current;
    const canvas = document.createElement('canvas');
    canvas.width = video.videoWidth;
    canvas.height = video.videoHeight;
    const context = canvas.getContext('2d');
    context.drawImage(video, 0, 0, canvas.width, canvas.height);

    return new Promise((resolve) => {
      canvas.toBlob((blob) => {
        if (!blob) resolve(null);
        resolve(new File([blob], 'camera-frame.png', { type: 'image/png' }));
      }, 'image/png');
    });
  };

  const handleProcess = async () => {
    setProcessing(true);
    setProcessError('');
    setProgress(5);
    setProgressPhase(text('Chuẩn bị ảnh', 'Preparing image'));

    const startProgressDrift = () => {
      if (progressTimerRef.current) clearInterval(progressTimerRef.current);
      progressTimerRef.current = setInterval(() => {
        setProgress((prev) => {
          if (prev < 90) return Math.min(90, prev + 2);
          return prev;
        });
      }, 700);
    };

    try {
      const file = await getImageForProcessing();
      if (!file) {
        setProcessError(text('Vui lòng import ảnh hoặc bật camera trước khi xử lý.', 'Please import an image or turn on the camera before analyzing.'));
        setProgress(0);
        setProgressPhase('');
        setProcessing(false);
        return;
      }

      setProgress(20);
      setProgressPhase(isGuest ? text('Chuẩn bị xử lý', 'Preparing analysis') : text('Xác thực phiên', 'Checking session'));
      if (!isGuest) await ensureFreshAccessToken();

      const formData = new FormData();
      formData.append('image', file);

      setProgress(50);
      setProgressPhase(text('Tiền xử lý và nhận dạng hạt', 'Preprocessing and detecting grains'));
      startProgressDrift();

      const analysisApi = isGuest ? publicApi : api;
      const analysisPath = isGuest ? '/grain/analyze-public' : '/grain/analyze';
      const { data } = await analysisApi.post(analysisPath, formData, {
        headers: { 'Content-Type': 'multipart/form-data' },
        timeout: 300000,
      });

      if (progressTimerRef.current) clearInterval(progressTimerRef.current);
      setProgress(92);
      setProgressPhase(text('Hậu xử lý và nhận dạng Ref', 'Post-processing and detecting Ref'));
      qcRenderSeqRef.current += 1;
      let nextResult = data.data;
      const suggestion = data.data?.calibration?.suggested_reference;
      const suggestedStart = suggestedReferencePoint(suggestion, 'x1', 'y1');
      const suggestedEnd = suggestedReferencePoint(suggestion, 'x2', 'y2');
      if (suggestion?.available === true && suggestedStart && suggestedEnd) {
        const suggestedPixels = Number(suggestion.pixels) > 1
          ? Number(suggestion.pixels)
          : Math.hypot(
            suggestedEnd.x - suggestedStart.x,
            suggestedEnd.y - suggestedStart.y,
          );
        setCalibration({
          start: suggestedStart,
          end: suggestedEnd,
          referenceMm: String(DETECTED_REFERENCE_MM),
        });
        nextResult = applyPostAnalysisCalibration(data.data, {
          referencePixels: suggestedPixels,
          referenceMm: DETECTED_REFERENCE_MM,
          referenceX1: suggestedStart.x,
          referenceY1: suggestedStart.y,
          referenceX2: suggestedEnd.x,
          referenceY2: suggestedEnd.y,
        });
      }
      setResult(nextResult);
      setCalibrationPreviewRequested(false);
      if (isGuest) {
        try {
          saveGuestRun({ result: nextResult, sourceFileName: file.name });
        } catch (storageError) {
          console.warn('Could not save guest analysis history.', storageError);
        }
      } else if (nextResult !== data.data) {
        const runId = nextResult?.run?.id;
        if (runId) {
          await api.put(`/grain/runs/${runId}/result`, { result: nextResult }).catch(() => {});
        }
      }
      setPreviewMode('overlay');
      setProgress(100);
      setProgressPhase(text('Hoàn tất nhận dạng', 'Detection complete'));
    } catch (err) {
      if (progressTimerRef.current) clearInterval(progressTimerRef.current);
      setProgress(0);
      setProgressPhase('');
      setProcessError(resolveProcessError(err, text));
    } finally {
      if (progressTimerRef.current) clearInterval(progressTimerRef.current);
      setProcessing(false);
      setTimeout(() => {
        setProgress(0);
        setProgressPhase('');
      }, 500);
    }
  };

  const persistEditedResult = async (nextResult) => {
    const runId = nextResult?.run?.id;
    if (!runId) return;
    if (isGuest || nextResult?.run?.localOnly) {
      updateGuestRunResult({ clientRunId: runId, result: nextResult });
      return;
    }
    await api.put(`/grain/runs/${runId}/result`, { result: nextResult }).catch(() => {});
  };

  const applyEditedResult = async (nextResult, renderSeq) => {
    setResult(nextResult);
    const renderedResult = await renderQcPreviewsFromLabelMap(nextResult);
    if (qcRenderSeqRef.current === renderSeq) {
      setResult(renderedResult);
      await persistEditedResult(renderedResult);
    }
  };

  const handleConfirmSuspect = async (measurementId) => {
    if (!result) return;
    const renderSeq = qcRenderSeqRef.current + 1;
    qcRenderSeqRef.current = renderSeq;
    await applyEditedResult(confirmSuspectMeasurement(result, measurementId), renderSeq);
  };

  const handleDeleteSuspect = async (measurementId) => {
    if (!result) return;
    const renderSeq = qcRenderSeqRef.current + 1;
    qcRenderSeqRef.current = renderSeq;
    await applyEditedResult(deleteMeasurement(result, measurementId), renderSeq);
  };

  const handleApplyCalibration = async () => {
    if (!result || !calibrationReady) return;
    const nextResult = applyPostAnalysisCalibration(result, {
      referencePixels: calibrationPixels,
      referenceMm: calibrationMm,
      referenceX1: calibration.start.x,
      referenceY1: calibration.start.y,
      referenceX2: calibration.end.x,
      referenceY2: calibration.end.y,
    });
    const renderSeq = qcRenderSeqRef.current + 1;
    qcRenderSeqRef.current = renderSeq;
    setCalibrationPreviewRequested(false);
    await applyEditedResult(nextResult, renderSeq);
  };

  const downloadCsv = () => {
    if (!result?.csv) return;
    downloadBlob(`${safeStem(fileName)}_measurements.csv`, result.csv, 'text/csv;charset=utf-8');
  };

  const downloadPng = () => {
    if (!result?.overlay_png_base64) return;
    const link = document.createElement('a');
    link.href = `data:image/png;base64,${result.overlay_png_base64}`;
    link.download = `${safeStem(fileName)}_segmentation.png`;
    link.click();
  };

  const summary = result?.summary;
  const previewImages = {
    overlay: result?.overlay_png_base64,
    mask: result?.mask_png_base64,
    labels: result?.labels_png_base64,
    preprocessed: result?.preprocessed_png_base64 || result?.original_png_base64,
  };
  const activePreview = previewImages[previewMode] || result?.overlay_png_base64;
  const displayImage = activePreview
    ? `data:image/png;base64,${activePreview}`
    : previewUrl;
  const calibrationImage = Boolean(previewUrl && (!activePreview || calibrationPreviewRequested));
  const useRobustStats = summary?.qc?.robust_used_for_reporting !== false;
  const reportedStat = (rawKey, robustKey) => (
    useRobustStats ? (summary?.[robustKey] ?? summary?.[rawKey]) : summary?.[rawKey]
  );

  const stats = [
    {
      label: text('Tổng số hạt nhận dạng', 'Total detected grains'),
      value: summary ? String(result?.segmentation?.segment_count ?? summary.count ?? 0) : '0',
      note: result ? text('Theo lần xử lý hiện tại', 'Current analysis') : text('Chưa có dữ liệu', 'No data yet'),
    },
    {
      label: text('Hạt hợp lệ', 'Valid grains'),
      value: summary ? String(summary?.qc?.inlier_count ?? summary.count ?? 0) : '0',
      note: text('Được dùng để tính thống kê', 'Included in statistics'),
    },
    {
      label: text('Hạt cần xem lại', 'Grains to review'),
      value: summary ? String(summary?.qc?.suspect_count ?? 0) : '0',
      note: text('Kiểm tra vùng nhận dạng màu đỏ', 'Review red detection regions'),
    },
    {
      label: text('Giá trị trung bình (dài × rộng)', 'Average value (length × width)'),
      value: summary
        ? `${formatMeasure(summary?.mean_length_mm, 'mm', summary?.mean_length_px, 'px')} × ${formatMeasure(summary?.mean_width_mm, 'mm', summary?.mean_width_px, 'px')}`
        : '-',
      note: text('Thống kê trung bình trên các hạt hợp lệ', 'Average statistics from valid grains'),
    },
    {
      label: text('Giá trị trung bình diện tích', 'Average area'),
      value: summary ? formatMeasure(summary?.mean_area_mm2, 'mm2', summary?.mean_area_px, 'px2') : '-',
      note: text('Thống kê trung bình trên các hạt hợp lệ', 'Average statistics from valid grains'),
    },
    {
      label: text('Độ lệch chuẩn (dài × rộng)', 'Standard deviation (length × width)'),
      value: summary
        ? `${formatMeasure(reportedStat('std_length_mm', 'robust_std_length_mm'), 'mm', reportedStat('std_length_px', 'robust_std_length_px'), 'px')} × ${formatMeasure(reportedStat('std_width_mm', 'robust_std_width_mm'), 'mm', reportedStat('std_width_px', 'robust_std_width_px'), 'px')}`
        : '-',
      note: useRobustStats ? text('Sau kiểm tra hạt nghi ngờ', 'After suspect-grain QC') : text('Dùng SD thô vì hạt nghi ngờ cao', 'Using raw SD because suspect ratio is high'),
    },
    {
      label: text('Độ lệch chuẩn diện tích', 'Area standard deviation'),
      value: summary ? formatMeasure(reportedStat('std_area_mm2', 'robust_std_area_mm2'), 'mm2', reportedStat('std_area_px', 'robust_std_area_px'), 'px2') : '-',
      note: useRobustStats ? text('Sau kiểm tra hạt nghi ngờ', 'After suspect-grain QC') : text('Dùng SD thô vì hạt nghi ngờ cao', 'Using raw SD because suspect ratio is high'),
    },
  ];

  return (
    <Box sx={{ maxWidth: 1280 }}>
      <Box sx={{ mb: 2.5 }}>
        <Typography variant="h5" fontWeight={800}>
          {text('Phân tích hạt SeedVision', 'SeedVision grain analysis')}
        </Typography>
      </Box>

      {result && (
        <Stack spacing={2} mb={3}>
          <Box>
            <Typography variant="h6" fontWeight={800}>
              {text('Kết quả nhận dạng và thống kê', 'Detection and statistics result')}
            </Typography>
          </Box>
          <Box
            sx={{
              display: 'grid',
              gridTemplateColumns: {
                xs: '1fr',
                sm: 'repeat(2, minmax(0, 1fr))',
                md: 'repeat(3, minmax(0, 1fr))',
                lg: 'repeat(4, minmax(0, 1fr))',
              },
              gap: 2,
            }}
          >
            {stats.map((item) => (
              <StatCard key={item.label} {...item} />
            ))}
          </Box>
          {result?.measurements?.length > 0 && (
            <GrainStatsCharts result={result} />
          )}
        </Stack>
      )}

      <Grid container spacing={2}>
        <Grid item xs={12} lg={7}>
          <DashboardPreviewPanel
            cameraActive={cameraActive}
            cameraError={cameraError}
            calibration={calibration}
            calibrationImage={calibrationImage}
            calibrationPixels={calibrationPixels}
            calibrationReady={calibrationReady}
            displayImage={displayImage}
            drawingCalibration={drawingCalibration}
            fileName={fileName}
            imageRef={imageRef}
            previewMode={previewMode}
            previewUrl={previewUrl}
            processError={processError}
            processing={processing}
            result={result}
            videoRef={videoRef}
            onCamera={handleCamera}
            onFile={handleFile}
            onProcess={handleProcess}
            onCalibrationChange={setCalibration}
            onDrawingCalibrationChange={setDrawingCalibration}
            onPreviewModeChange={(mode) => {
              setCalibrationPreviewRequested(false);
              setPreviewMode(mode);
            }}
            onShowCalibrationImage={() => {
              setQcEditMode(false);
              setCalibrationPreviewRequested(true);
            }}
            onApplyCalibration={handleApplyCalibration}
            getCalibrationPoint={getCalibrationPoint}
            renderCalibrationOverlay={renderCalibrationOverlay}
            progress={progress}
            progressPhase={progressPhase}
            qcEditMode={qcEditMode}
            onToggleQcEditMode={() => setQcEditMode((value) => !value)}
            onConfirmSuspect={handleConfirmSuspect}
            onDeleteSuspect={handleDeleteSuspect}
          />
        </Grid>

        <Grid item xs={12} lg={5}>
          <DashboardResultPanel
            calibrationMm={calibrationMm}
            calibrationPixels={calibrationPixels}
            calibrationReady={calibrationReady}
            result={result}
            onDownloadCsv={downloadCsv}
            onDownloadPng={downloadPng}
          />
        </Grid>
      </Grid>
    </Box>
  );
}

const resolveProcessError = (err, text) => {
  if (err.response?.status === 401) {
    return text('Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại rồi chạy xử lý.', 'Your session expired. Please log in again and run analysis.');
  }

  const message = err.response?.data?.message;
  if (message) return message;
  if (err.code === 'ECONNABORTED') {
    return text('Xử lý quá lâu. Hãy thử ảnh nhỏ hơn, chụp gần hơn hoặc xử lý lại sau.', 'Analysis took too long. Try a smaller image, shoot closer, or run it again later.');
  }
  if (err.response?.status === 503 || (err.response?.status === 500 && typeof err.response?.data === 'string')) {
    return text('Hệ thống đang chưa sẵn sàng. Vui lòng thử lại sau.', 'The system is not ready yet. Please try again later.');
  }
  if (err.code === 'ERR_NETWORK') {
    return text('Không kết nối được. Kiểm tra mạng rồi thử lại.', 'Could not connect. Check the network and try again.');
  }
  return text('Không xử lý được ảnh. Vui lòng thử lại với ảnh khác hoặc kiểm tra kết nối.', 'Could not analyze the image. Try another image or check the connection.');
};

const downloadBlob = (fileName, content, mimeType) => {
  const blob = new Blob([content], { type: mimeType });
  const url = URL.createObjectURL(blob);
  const link = document.createElement('a');
  link.href = url;
  link.download = fileName;
  link.click();
  URL.revokeObjectURL(url);
};

const confirmSuspectMeasurement = (result, measurementId) => {
  if (!result?.measurements?.length) return result;
  const measurements = result.measurements.map((measurement) => {
    if (Number(measurement.id) !== Number(measurementId)) return { ...measurement };
    return {
      ...measurement,
      qc_outlier: false,
      qc_reason: '',
      qc_manual_override: true,
      qc_manual_decision: 'confirmed_grain',
    };
  });
  return {
    ...result,
    measurements,
    summary: recomputeSummaryFromMeasurements(result.summary, measurements),
    csv: measurementsToCsv(measurements, result.csv),
  };
};

const deleteMeasurement = (result, measurementId) => {
  if (!result?.measurements?.length) return result;
  const deletedId = Number(measurementId);
  const measurements = result.measurements
    .filter((measurement) => Number(measurement.id) !== deletedId)
    .map((measurement) => ({ ...measurement }));
  return {
    ...result,
    measurements,
    summary: recomputeSummaryFromMeasurements(result.summary, measurements),
    segmentation: {
      ...(result.segmentation || {}),
      segment_count: measurements.length,
      marker_count: measurements.length,
      manual_deleted_ids: [
        ...new Set([
          ...((result.segmentation?.manual_deleted_ids || []).map(Number).filter(Number.isFinite)),
          deletedId,
        ]),
      ],
    },
    csv: measurementsToCsv(measurements, result.csv),
  };
};

const applyPostAnalysisCalibration = (result, reference) => {
  const scale = Number(result?.image?.scale) > 0 ? Number(result.image.scale) : 1;
  const processedReferencePixels = reference.referencePixels * scale;
  if (!(processedReferencePixels > 0) || !(reference.referenceMm > 0)) return result;
  const mmPerPixel = reference.referenceMm / processedReferencePixels;
  const measurements = (result.measurements || []).map((measurement) => ({
    ...measurement,
    area_mm2: round((Number(measurement.area_px) || 0) * mmPerPixel * mmPerPixel, 6),
    length_mm: round((Number(measurement.length_px) || 0) * mmPerPixel, 6),
    width_mm: round((Number(measurement.width_px) || 0) * mmPerPixel, 6),
  }));
  const nextResult = {
    ...result,
    measurements,
    calibration: {
      ...(result.calibration || {}),
      enabled: true,
      mm_per_pixel: round(mmPerPixel, 10),
      referencePixels: round(reference.referencePixels, 6),
      processedReferencePixels: round(processedReferencePixels, 6),
      referenceMm: round(reference.referenceMm, 6),
      referencePixelSpace: 'original',
      referenceX1: reference.referenceX1,
      referenceY1: reference.referenceY1,
      referenceX2: reference.referenceX2,
      referenceY2: reference.referenceY2,
      source: result.calibration?.suggested_reference?.available === true
        ? 'detected_ref_post_analysis'
        : 'manual_line_post_analysis',
      post_analysis_applied: true,
    },
  };
  return {
    ...nextResult,
    summary: recomputeSummaryFromMeasurements(result.summary, measurements),
    csv: measurementsToCsv(measurements, result.csv),
  };
};

const renderQcPreviewsFromLabelMap = async (result) => {
  if (!result?.label_map_png_base64) return result;
  const base64 = result.preprocessed_png_base64 || result.original_png_base64;
  if (!base64) return result;

  const [baseImage, labelMapImage] = await Promise.all([
    loadImageData(base64),
    loadImageData(result.label_map_png_base64),
  ]);
  if (
    !baseImage || !labelMapImage ||
    baseImage.width !== labelMapImage.width ||
    baseImage.height !== labelMapImage.height
  ) {
    return result;
  }

  const outlierIds = new Set(
    result.measurements
      .filter((measurement) => measurement.qc_outlier === true)
      .map((measurement) => Number(measurement.id))
      .filter(Number.isFinite),
  );
  const activeIds = new Set(
    result.measurements
      .map((measurement) => Number(measurement.id))
      .filter(Number.isFinite),
  );
  const width = baseImage.width;
  const height = baseImage.height;
  const overlay = new ImageData(new Uint8ClampedArray(baseImage.data), width, height);
  const mask = new ImageData(width, height);
  const labelAt = (x, y) => {
    const offset = ((y * width) + x) * 4;
    return labelMapImage.data[offset] +
      (labelMapImage.data[offset + 1] << 8) +
      (labelMapImage.data[offset + 2] << 16);
  };
  const isEdge = (x, y, label) => (
    x === 0 || y === 0 || x === width - 1 || y === height - 1 ||
    labelAt(x - 1, y) !== label ||
    labelAt(x + 1, y) !== label ||
    labelAt(x, y - 1) !== label ||
    labelAt(x, y + 1) !== label
  );

  for (let y = 0; y < height; y += 1) {
    for (let x = 0; x < width; x += 1) {
      const label = labelAt(x, y);
      const offset = ((y * width) + x) * 4;
      if (!label || !activeIds.has(label)) {
        mask.data[offset + 3] = 0;
        if (label && !activeIds.has(label)) {
          labelMapImage.data[offset] = 0;
          labelMapImage.data[offset + 1] = 0;
          labelMapImage.data[offset + 2] = 0;
          labelMapImage.data[offset + 3] = 255;
        }
        continue;
      }
      const outlier = outlierIds.has(label);
      const color = outlier ? [220, 38, 38] : [37, 99, 235];
      const edge = isEdge(x, y, label);
      const alpha = edge ? 0.56 : 0.34;
      overlay.data[offset] = Math.round(overlay.data[offset] * (1 - alpha) + color[0] * alpha);
      overlay.data[offset + 1] = Math.round(overlay.data[offset + 1] * (1 - alpha) + color[1] * alpha);
      overlay.data[offset + 2] = Math.round(overlay.data[offset + 2] * (1 - alpha) + color[2] * alpha);
      overlay.data[offset + 3] = 255;

      const maskColor = edge
        ? (outlier ? [185, 28, 28, 255] : [30, 64, 175, 255])
        : (outlier ? [239, 68, 68, 170] : [59, 130, 246, 145]);
      mask.data[offset] = maskColor[0];
      mask.data[offset + 1] = maskColor[1];
      mask.data[offset + 2] = maskColor[2];
      mask.data[offset + 3] = maskColor[3];
    }
  }

  const labels = renderLabelsPreview(baseImage, result.measurements);

  return {
    ...result,
    overlay_png_base64: imageDataToBase64(overlay),
    mask_png_base64: imageDataToBase64(mask),
    sam_mask_png_base64: '',
    labels_png_base64: labels,
    label_map_png_base64: imageDataToBase64(labelMapImage),
  };
};

const renderLabelsPreview = (baseImage, measurements) => {
  const canvas = document.createElement('canvas');
  canvas.width = baseImage.width;
  canvas.height = baseImage.height;
  const context = canvas.getContext('2d');
  context.putImageData(baseImage, 0, 0);
  context.textAlign = 'center';
  context.textBaseline = 'middle';
  measurements.forEach((measurement) => {
    const id = Number(measurement.id);
    const x = Number(measurement.centroid_x ?? (Number(measurement.bbox_x) + Number(measurement.bbox_w) / 2));
    const y = Number(measurement.centroid_y ?? (Number(measurement.bbox_y) + Number(measurement.bbox_h) / 2));
    if (!Number.isFinite(id) || !Number.isFinite(x) || !Number.isFinite(y)) return;
    const radius = Math.max(13, Math.min(26, (Number(measurement.width_px) || 20) * 0.45));
    context.fillStyle = measurement.qc_outlier === true ? '#dc2626' : '#2563eb';
    context.beginPath();
    context.arc(x, y, radius, 0, Math.PI * 2);
    context.fill();
    context.lineWidth = Math.max(2, radius * 0.16);
    context.strokeStyle = '#ffffff';
    context.stroke();
    context.fillStyle = '#ffffff';
    context.font = `700 ${Math.max(11, radius * 0.9)}px Arial, sans-serif`;
    context.fillText(String(id), x, y + 0.5);
  });
  return canvas.toDataURL('image/png').split(',')[1] || '';
};

const loadImageData = (base64) => new Promise((resolve) => {
  const image = new Image();
  image.onload = () => {
    const canvas = document.createElement('canvas');
    canvas.width = image.naturalWidth;
    canvas.height = image.naturalHeight;
    const context = canvas.getContext('2d', { willReadFrequently: true });
    context.drawImage(image, 0, 0);
    resolve(context.getImageData(0, 0, canvas.width, canvas.height));
  };
  image.onerror = () => resolve(null);
  image.src = `data:image/png;base64,${base64}`;
});

const imageDataToBase64 = (imageData) => {
  const canvas = document.createElement('canvas');
  canvas.width = imageData.width;
  canvas.height = imageData.height;
  canvas.getContext('2d').putImageData(imageData, 0, 0);
  return canvas.toDataURL('image/png').split(',')[1] || '';
};

const recomputeSummaryFromMeasurements = (previousSummary = {}, measurements) => {
  if (!measurements.length) {
    return {
      ...previousSummary,
      count: 0,
      total_area_px: 0,
      mean_area_px: 0,
      mean_length_px: 0,
      mean_width_px: 0,
      mean_area_mm2: null,
      mean_length_mm: null,
      mean_width_mm: null,
      std_area_px: 0,
      std_length_px: 0,
      std_width_px: 0,
      std_area_mm2: null,
      std_length_mm: null,
      std_width_mm: null,
      robust_mean_area_px: 0,
      robust_mean_length_px: 0,
      robust_mean_width_px: 0,
      robust_mean_area_mm2: null,
      robust_mean_length_mm: null,
      robust_mean_width_mm: null,
      robust_std_area_px: 0,
      robust_std_length_px: 0,
      robust_std_width_px: 0,
      robust_std_area_mm2: null,
      robust_std_length_mm: null,
      robust_std_width_mm: null,
      cv_length_pct: 0,
      cv_width_pct: 0,
      qc: {
        ...((previousSummary.qc && typeof previousSummary.qc === 'object') ? previousSummary.qc : {}),
        suspect_count: 0,
        inlier_count: 0,
        suspect_ids: [],
        review_required: false,
        suspect_ratio: 0,
        robust_used_for_reporting: true,
        manual_override: true,
        status: 'ok',
      },
      quality: qualitySummary([]),
    };
  }
  const inliers = measurements.filter((measurement) => measurement.qc_outlier !== true);
  const robustMeasurements = inliers.length ? inliers : measurements;
  const suspectIds = measurements
    .filter((measurement) => measurement.qc_outlier === true)
    .map((measurement) => Number(measurement.id))
    .filter(Number.isFinite)
    .sort((a, b) => a - b);
  const suspectRatio = suspectIds.length / measurements.length;
  const robustUsedForReporting = suspectRatio <= 0.05;
  const calibrated = measurements[0]?.length_mm !== null && measurements[0]?.length_mm !== undefined;

  const values = (items, key) => items.map((item) => Number(item[key]) || 0);
  const mean = (items, key) => {
    const data = values(items, key);
    return round(data.reduce((sum, value) => sum + value, 0) / Math.max(1, data.length), 6);
  };
  const std = (items, key) => {
    const data = values(items, key);
    if (data.length <= 1) return 0;
    const average = data.reduce((sum, value) => sum + value, 0) / data.length;
    const variance = data.reduce((sum, value) => sum + ((value - average) ** 2), 0) / (data.length - 1);
    return round(Math.sqrt(variance), 6);
  };
  const cv = (items, key) => {
    const average = mean(items, key);
    return average > 0 ? round((std(items, key) / average) * 100, 3) : 0;
  };
  const metricMm = (statistic, items, key) => calibrated ? statistic(items, key) : null;

  return {
    ...previousSummary,
    count: measurements.length,
    total_area_px: measurements.reduce((sum, item) => sum + (Number(item.area_px) || 0), 0),
    mean_area_px: mean(measurements, 'area_px'),
    mean_length_px: mean(measurements, 'length_px'),
    mean_width_px: mean(measurements, 'width_px'),
    mean_area_mm2: metricMm(mean, measurements, 'area_mm2'),
    mean_length_mm: metricMm(mean, measurements, 'length_mm'),
    mean_width_mm: metricMm(mean, measurements, 'width_mm'),
    std_area_px: std(measurements, 'area_px'),
    std_length_px: std(measurements, 'length_px'),
    std_width_px: std(measurements, 'width_px'),
    std_area_mm2: metricMm(std, measurements, 'area_mm2'),
    std_length_mm: metricMm(std, measurements, 'length_mm'),
    std_width_mm: metricMm(std, measurements, 'width_mm'),
    robust_mean_area_px: mean(robustMeasurements, 'area_px'),
    robust_mean_length_px: mean(robustMeasurements, 'length_px'),
    robust_mean_width_px: mean(robustMeasurements, 'width_px'),
    robust_mean_area_mm2: metricMm(mean, robustMeasurements, 'area_mm2'),
    robust_mean_length_mm: metricMm(mean, robustMeasurements, 'length_mm'),
    robust_mean_width_mm: metricMm(mean, robustMeasurements, 'width_mm'),
    robust_std_area_px: std(robustMeasurements, 'area_px'),
    robust_std_length_px: std(robustMeasurements, 'length_px'),
    robust_std_width_px: std(robustMeasurements, 'width_px'),
    robust_std_area_mm2: metricMm(std, robustMeasurements, 'area_mm2'),
    robust_std_length_mm: metricMm(std, robustMeasurements, 'length_mm'),
    robust_std_width_mm: metricMm(std, robustMeasurements, 'width_mm'),
    cv_length_pct: cv(robustMeasurements, 'length_px'),
    cv_width_pct: cv(robustMeasurements, 'width_px'),
    qc: {
      ...(previousSummary.qc || {}),
      suspect_count: suspectIds.length,
      inlier_count: robustMeasurements.length,
      suspect_ids: suspectIds,
      review_required: suspectIds.length > 0,
      suspect_ratio: round(suspectRatio, 6),
      robust_used_for_reporting: robustUsedForReporting,
      manual_override: true,
      status: !robustUsedForReporting
        ? 'review_required'
        : (suspectIds.length ? 'suspects_flagged' : 'ok'),
    },
    quality: qualitySummary(measurements),
  };
};

const qualitySummary = (measurements) => {
  const flagCounts = {};
  const problemFlags = new Set(['loose_mask', 'touches_image_edge', 'extreme_aspect', 'partial_tile_mask']);
  let problemCount = 0;
  measurements.forEach((measurement) => {
    const flags = new Set(String(measurement.quality_flags || '')
      .split(',')
      .map((flag) => flag.trim())
      .filter(Boolean));
    if ([...flags].some((flag) => problemFlags.has(flag))) {
      problemCount += 1;
    }
    flags.forEach((flag) => {
      flagCounts[flag] = (flagCounts[flag] || 0) + 1;
    });
  });
  const labelConfusionCount = flagCounts.model_label_ref_as_seed || 0;
  const count = measurements.length;
  return {
    flag_counts: flagCounts,
    problem_count: problemCount,
    problem_ratio: count ? round(problemCount / count, 6) : 0,
    label_confusion_count: labelConfusionCount,
    label_confusion_ratio: count ? round(labelConfusionCount / count, 6) : 0,
    review_required: problemCount > 0,
    status: problemCount > 0 ? 'review_required' : 'ok',
  };
};

const measurementsToCsv = (measurements, existingCsv = '') => {
  const firstLine = existingCsv.split(/\r?\n/, 1)[0];
  const baseColumns = firstLine
    ? firstLine.split(',')
    : [
      'id', 'area_px', 'length_px', 'width_px', 'area_mm2', 'length_mm', 'width_mm',
      'centroid_x', 'centroid_y', 'bbox_x', 'bbox_y', 'bbox_w', 'bbox_h', 'angle_deg',
      'solidity', 'extent', 'aspect_ratio', 'confidence', 'class_id', 'class_name',
      'detected_class_id', 'detected_class_name', 'quality_flags',
      'qc_outlier', 'qc_reason',
    ];
  const columns = baseColumns.includes('qc_manual_override')
    ? baseColumns
    : [...baseColumns, 'qc_manual_override'];
  return [
    columns.join(','),
    ...measurements.map((measurement) => columns.map((column) => csvEscape(measurement[column])).join(',')),
  ].join('\n');
};

const csvEscape = (value) => {
  if (value === null || value === undefined) return '';
  const text = String(value);
  return /[",\n\r]/.test(text) ? `"${text.replaceAll('"', '""')}"` : text;
};

const round = (value, decimals) => {
  const factor = 10 ** decimals;
  return Math.round(value * factor) / factor;
};
