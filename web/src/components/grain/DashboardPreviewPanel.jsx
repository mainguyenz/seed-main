import { useRef, useState } from "react";
import {
  Alert,
  AlertTitle,
  Box,
  Button,
  Card,
  CardContent,
  Chip,
  CircularProgress,
  Dialog,
  Divider,
  IconButton,
  LinearProgress,
  Stack,
  TextField,
  Tooltip,
  Typography,
} from "@mui/material";
import {
  HelpOutline,
  Close,
  Edit,
  Check,
  CheckCircle,
  Cancel,
} from "@mui/icons-material";
import { useLanguage } from "@/i18n.jsx";

const PREVIEW_MODES = [
  ["overlay", "Đánh dấu"],
  ["mask", "Hình dạng"],
  ["labels", "Đánh số"],
];

const CALIBRATION_GUIDE_SLIDES = [
  {
    title: "1. Import ảnh hạt và vật Ref",
    titleEn: "1. Import the grain and Ref image",
    description:
      "Chọn hoặc chụp ảnh có cả hạt cần đo và vật Ref có kích thước thật đã biết, sau đó chạy nhận dạng.",
    descriptionEn:
      "Choose or capture an image containing the grains and a Ref object of known size, then run detection.",
    image: "/images/calibration_guide_1.webp",
  },
  {
    title: "2. Kiểm tra Ref sau nhận dạng",
    titleEn: "2. Check Ref after detection",
    description:
      "Sau tiền xử lý, nhận dạng và hậu xử lý, hệ thống tự nhận dạng Ref và đề xuất một vạch đo.",
    descriptionEn:
      "After preprocessing, detection, and post-processing, the system detects Ref and suggests a measurement line.",
    image: "/images/calibration_guide_2.webp",
  },
  {
    title: "3. Chỉnh vạch Ref nếu cần",
    titleEn: "3. Adjust the Ref line if needed",
    description:
      "Kéo từng chốt tới đúng hai mép vật mốc; có thể dùng nút mũi tên để tinh chỉnh.",
    descriptionEn:
      "Drag each endpoint to the correct Ref edges; use the arrow controls for fine adjustment.",
    image: "/images/calibration_guide_3.webp",
  },
  {
    title: "4. Nhập kích thước thật",
    titleEn: "4. Enter the real size",
    description:
      "Nhập kích thước thật của Ref vào ô Kích thước (mm), sau đó bấm Áp dụng đơn vị mm.",
    descriptionEn:
      "Enter the real Ref size in millimeters, then select Apply millimeters.",
    image: "/images/calibration_guide_4.webp",
  },
];

const SlideContent = ({ title, description, diagram }) => (
  <Stack
    alignItems="center"
    spacing={2}
    sx={{ px: 2, py: 1, textAlign: "center", height: "100%" }}
  >
    <Typography variant="subtitle1" fontWeight={750} color="primary">
      {title}
    </Typography>
    <Typography
      variant="body2"
      color="text.secondary"
      sx={{ minHeight: 48, lineHeight: 1.45 }}
    >
      {description}
    </Typography>
    <Box
      sx={{
        flexGrow: 1,
        width: "100%",
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        minHeight: 260,
        mt: 1,
      }}
    >
      {diagram}
    </Box>
  </Stack>
);

const GuideImage = ({ src, alt }) => (
  <Box
    sx={{
      width: "100%",
      maxWidth: 460,
      height: { xs: 300, sm: 420 },
      borderRadius: 2,
      overflow: "hidden",
      border: "1px solid",
      borderColor: "divider",
      bgcolor: "#F8FAF7",
      display: "flex",
      alignItems: "center",
      justifyContent: "center",
    }}
  >
    <Box
      component="img"
      src={src}
      alt={alt}
      loading="eager"
      decoding="async"
      sx={{
        width: "100%",
        height: "100%",
        objectFit: "contain",
        display: "block",
      }}
    />
  </Box>
);

export const DashboardPreviewPanel = ({
  cameraActive,
  cameraError,
  calibration,
  calibrationImage,
  calibrationPixels,
  calibrationReady,
  displayImage,
  drawingCalibration,
  fileName,
  imageRef,
  previewMode,
  previewUrl,
  processError,
  processing,
  result,
  videoRef,
  onCamera,
  onFile,
  onProcess,
  onCalibrationChange,
  onDrawingCalibrationChange,
  onPreviewModeChange,
  onShowCalibrationImage,
  onApplyCalibration,
  getCalibrationPoint,
  renderCalibrationOverlay,
  progress,
  progressPhase,
  qcEditMode,
  onToggleQcEditMode,
  onConfirmSuspect,
  onDeleteSuspect,
}) => {
  const { text } = useLanguage();
  const [guideOpen, setGuideOpen] = useState(false);
  const [qcGuideOpen, setQcGuideOpen] = useState(false);
  const [currentStep, setCurrentStep] = useState(0);
  const fileInputRef = useRef(null);
  const [draggingHandle, setDraggingHandle] = useState(null);

  const openFilePicker = () => {
    if (!processing) fileInputRef.current?.click();
  };

  const handleNext = () => {
    if (currentStep < 3) {
      setCurrentStep((prev) => prev + 1);
    } else {
      setGuideOpen(false);
    }
  };

  const handleBack = () => {
    setCurrentStep((prev) => Math.max(prev - 1, 0));
  };

  const getNearestCalibrationHandle = (point) => {
    const image = imageRef.current;
    if (
      !point ||
      !image?.naturalWidth ||
      !calibration.start ||
      !calibration.end
    )
      return null;

    const rect = image.getBoundingClientRect();
    const coordinateWidth =
      Number(result?.image?.original_width) || image.naturalWidth;
    const threshold = (16 / Math.max(1, rect.width)) * coordinateWidth;
    const startDistance = Math.hypot(
      point.x - calibration.start.x,
      point.y - calibration.start.y,
    );
    const endDistance = Math.hypot(
      point.x - calibration.end.x,
      point.y - calibration.end.y,
    );

    if (Math.min(startDistance, endDistance) > threshold) return null;
    return startDistance <= endDistance ? "start" : "end";
  };

  const currentGuideSlide =
    CALIBRATION_GUIDE_SLIDES[currentStep] ?? CALIBRATION_GUIDE_SLIDES[0];
  const previewBoxHeight = { xs: 300, sm: 360 };
  const imageWidth =
    Number(result?.image?.width) || imageRef.current?.naturalWidth || 1;
  const imageHeight =
    Number(result?.image?.height) || imageRef.current?.naturalHeight || 1;
  const measurementMasks = (result?.measurements || [])
    .filter(
      (measurement) =>
        (Number(measurement.length_px) > 0 &&
          Number(measurement.width_px) > 0) ||
        (Number(measurement.bbox_w) > 0 && Number(measurement.bbox_h) > 0),
    )
    .map((measurement) => ({
      id: measurement.id,
      outlier: measurement.qc_outlier === true,
      manual: measurement.qc_manual_override === true,
      centerX:
        (Number(
          measurement.centroid_x ??
            Number(measurement.bbox_x) + Number(measurement.bbox_w) / 2,
        ) /
          imageWidth) *
        100,
      centerY:
        (Number(
          measurement.centroid_y ??
            Number(measurement.bbox_y) + Number(measurement.bbox_h) / 2,
        ) /
          imageHeight) *
        100,
      width:
        (Math.max(
          Number(measurement.length_px) || 0,
          Number(measurement.bbox_w) || 0,
        ) /
          imageWidth) *
        100,
      height:
        (Math.max(
          Number(measurement.width_px) || 0,
          Math.min(
            Number(measurement.bbox_h) || 0,
            Number(measurement.bbox_w) || 0,
          ),
        ) /
          imageHeight) *
        100,
      angle: Number(measurement.angle_deg) || 0,
    }));
  const suspectMeasurements = (result?.measurements || [])
    .filter((measurement) => measurement.qc_outlier === true)
    .map((measurement) => ({
      id: measurement.id,
      length: Number(measurement.length_mm || measurement.length_px || 0),
      width: Number(measurement.width_mm || measurement.width_px || 0),
      unit: measurement.length_mm ? "mm" : "px",
    }));

  return (
    <>
      <Card sx={{ height: "100%" }}>
        <CardContent sx={{ p: 2.5 }}>
          <Box
            sx={{
              display: "flex",
              alignItems: "center",
              justifyContent: "space-between",
              gap: 2,
              mb: 2,
            }}
          >
            <Box sx={{ display: "flex", alignItems: "flex-start", gap: 0.75 }}>
              <Box>
                <Typography variant="h6" fontWeight={700}>
                  Hình ảnh hiển thị
                </Typography>
              </Box>
              <IconButton
                size="small"
                color="primary"
                onClick={() => {
                  setCurrentStep(0);
                  setGuideOpen(true);
                }}
                title="Xem hướng dẫn căn mốc"
                aria-label="Xem hướng dẫn căn mốc"
              >
                <HelpOutline fontSize="small" />
              </IconButton>
            </Box>
            <Chip
              label={result ? "Đã xử lý" : "Sẵn sàng"}
              color={result ? "primary" : "success"}
              variant="outlined"
              size="small"
            />
          </Box>

          {result && (
            <Stack spacing={1} sx={{ mb: 1.5 }}>
              <Stack direction={{ xs: "column", sm: "row" }} spacing={1}>
                {PREVIEW_MODES.map(([key, label]) => (
                  <Button
                    key={key}
                    size="small"
                    variant={previewMode === key ? "contained" : "outlined"}
                    onClick={() => onPreviewModeChange(key)}
                  >
                    {label}
                  </Button>
                ))}
                <Stack direction="row" spacing={0.5} alignItems="center">
                  <Button
                    size="small"
                    color={qcEditMode ? "warning" : "primary"}
                    variant={qcEditMode ? "contained" : "outlined"}
                    startIcon={
                      qcEditMode ? (
                        <Check fontSize="small" />
                      ) : (
                        <Edit fontSize="small" />
                      )
                    }
                    onClick={onToggleQcEditMode}
                    sx={{ fontWeight: 750 }}
                  >
                    {qcEditMode ? "Xong chỉnh hạt" : "Chỉnh hạt nghi ngờ"}
                  </Button>
                  <Tooltip
                    title="Giải thích QC và cách chỉnh hạt nghi ngờ"
                    arrow
                  >
                    <IconButton
                      size="small"
                      color="primary"
                      onClick={() => setQcGuideOpen(true)}
                      aria-label="QC là gì?"
                      sx={{ border: "1px solid", borderColor: "divider" }}
                    >
                      <HelpOutline fontSize="small" />
                    </IconButton>
                  </Tooltip>
                </Stack>
              </Stack>
              {qcEditMode && (
                <Alert severity="info" sx={{ py: 0.75 }}>
                  <AlertTitle sx={{ mb: 0.25, fontWeight: 750 }}>
                    Đang chỉnh kết quả kiểm tra hạt
                  </AlertTitle>
                  Hạt màu đỏ là vùng hệ thống nghi có lỗi tách vùng ảnh hoặc
                  kích thước bất thường. Dùng bảng ID bên dưới ảnh: tích xanh để
                  xác nhận là hạt thật, X đỏ để xóa hẳn nhận dạng sai khỏi kết
                  quả.
                </Alert>
              )}
            </Stack>
          )}

          <Box
            sx={{
              minHeight: previewBoxHeight,
              border: "1px dashed",
              borderColor: "divider",
              borderRadius: 1,
              bgcolor: "#FBFCFA",
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
              overflow: "hidden",
              mb: 2,
              position: "relative",
              cursor:
                !displayImage && !cameraActive && !processing
                  ? "pointer"
                  : "default",
            }}
            onClick={
              !displayImage && !cameraActive ? openFilePicker : undefined
            }
          >
            {displayImage ? (
              <Box
                sx={{
                  position: "relative",
                  width: "100%",
                  height: previewBoxHeight,
                  display: "grid",
                  placeItems: "center",
                  touchAction: calibrationImage ? "none" : "auto",
                }}
                onPointerDown={(event) => {
                  if (qcEditMode) return;
                  if (!calibrationImage || processing) return;
                  const point = getCalibrationPoint(event);
                  if (!point) return;
                  const handle = getNearestCalibrationHandle(point);
                  event.currentTarget.setPointerCapture(event.pointerId);
                  if (handle) {
                    setDraggingHandle(handle);
                    return;
                  }
                  setDraggingHandle(null);
                  onDrawingCalibrationChange(true);
                  onCalibrationChange((current) => ({
                    ...current,
                    start: point,
                    end: point,
                  }));
                }}
                onPointerMove={(event) => {
                  const point = getCalibrationPoint(event);
                  if (!point) return;
                  if (draggingHandle) {
                    onCalibrationChange((current) => ({
                      ...current,
                      [draggingHandle]: point,
                    }));
                    return;
                  }
                  if (drawingCalibration)
                    onCalibrationChange((current) => ({
                      ...current,
                      end: point,
                    }));
                }}
                onPointerUp={(event) => {
                  setDraggingHandle(null);
                  onDrawingCalibrationChange(false);
                  if (event.currentTarget.hasPointerCapture(event.pointerId)) {
                    event.currentTarget.releasePointerCapture(event.pointerId);
                  }
                }}
                onPointerCancel={() => {
                  setDraggingHandle(null);
                  onDrawingCalibrationChange(false);
                }}
                onPointerLeave={() => {
                  if (!draggingHandle) onDrawingCalibrationChange(false);
                }}
              >
                <Box
                  component="span"
                  sx={{
                    position: "relative",
                    display: "inline-flex",
                    maxWidth: "100%",
                    maxHeight: previewBoxHeight,
                  }}
                >
                  <Box
                    component="img"
                    ref={imageRef}
                    src={displayImage}
                    alt={fileName}
                    draggable={false}
                    sx={{
                      maxWidth: "100%",
                      maxHeight: previewBoxHeight,
                      objectFit: "contain",
                      userSelect: "none",
                    }}
                  />
                  {result &&
                    measurementMasks.map((mask) => {
                      if (!qcEditMode || !mask.outlier) return null;
                      return (
                        <Tooltip
                          key={mask.id}
                          title={`Hạt nghi ngờ #${mask.id}`}
                          arrow
                        >
                          <Box
                            sx={{
                              position: "absolute",
                              left: `${mask.centerX}%`,
                              top: `${mask.centerY}%`,
                              minWidth: 24,
                              height: 24,
                              px: 0.5,
                              border: "2px solid #fff",
                              bgcolor: "#dc2626",
                              color: "#fff",
                              borderRadius: 999,
                              transform: "translate(-50%, -50%)",
                              transformOrigin: "50% 50%",
                              pointerEvents: "none",
                              display: "grid",
                              placeItems: "center",
                              fontSize: 12,
                              fontWeight: 800,
                              boxShadow: "0 1px 4px rgba(0,0,0,0.28)",
                            }}
                          >
                            #{mask.id}
                          </Box>
                        </Tooltip>
                      );
                    })}
                  {result && calibrationPixels > 1 && renderCalibrationOverlay()}
                </Box>
              </Box>
            ) : (
              <video
                ref={videoRef}
                autoPlay
                muted
                playsInline
                style={{
                  width: "100%",
                  maxHeight: 360,
                  display: cameraActive ? "block" : "none",
                }}
              />
            )}
            {!displayImage && !cameraActive && (
              <Stack
                alignItems="center"
                spacing={1.25}
                sx={{ color: "text.secondary", textAlign: "center", px: 2 }}
              >
                <Typography fontWeight={650} color="text.primary">
                  Chưa có ảnh đầu vào
                </Typography>
              </Stack>
            )}
            {processing && (
              <Box
                sx={{
                  position: "absolute",
                  inset: 0,
                  bgcolor: "rgba(255,255,255,0.85)",
                  display: "flex",
                  alignItems: "center",
                  justifyContent: "center",
                  p: 3,
                }}
              >
                <Stack
                  alignItems="center"
                  spacing={1.5}
                  sx={{ width: "80%", maxWidth: 360 }}
                >
                  <CircularProgress size={36} thickness={4.5} />
                  <Box sx={{ width: "100%", mt: 1 }}>
                    <Box
                      sx={{
                        display: "flex",
                        justifyContent: "space-between",
                        mb: 0.5,
                      }}
                    >
                      <Typography
                        variant="body2"
                        color="text.secondary"
                        fontWeight={600}
                      >
                        {progressPhase || "Đang xử lý..."}
                      </Typography>
                      <Typography
                        variant="body2"
                        fontWeight={750}
                        color="primary"
                      >
                        {Math.round(progress)}%
                      </Typography>
                    </Box>
                    <Box
                      sx={{
                        width: "100%",
                        bgcolor: "divider",
                        borderRadius: 1,
                        overflow: "hidden",
                        height: 6,
                      }}
                    >
                      <Box
                        sx={{
                          width: `${progress}%`,
                          bgcolor: "primary.main",
                          height: "100%",
                          transition: "width 0.4s ease",
                        }}
                      />
                    </Box>
                  </Box>
                </Stack>
              </Box>
            )}
          </Box>

          {fileName && (
            <Typography
              variant="caption"
              color="text.secondary"
              display="block"
              mb={1.5}
            >
              {fileName}
            </Typography>
          )}
          {result && qcEditMode && (
            <Box
              sx={{
                mb: 1.5,
                border: "1px solid",
                borderColor: "divider",
                borderRadius: 1,
                overflowX: "auto",
              }}
            >
              <Box
                sx={{
                  display: "grid",
                  gridTemplateColumns:
                    "minmax(72px, 1fr) minmax(96px, 1fr) 96px",
                  minWidth: 280,
                  gap: 1,
                  px: 1.25,
                  py: 0.75,
                  bgcolor: "#F8FAFC",
                  borderBottom: "1px solid",
                  borderColor: "divider",
                }}
              >
                <Typography variant="caption" fontWeight={800}>
                  ID
                </Typography>
                <Typography variant="caption" fontWeight={800}>
                  Kích thước
                </Typography>
                <Typography
                  variant="caption"
                  fontWeight={800}
                  textAlign="center"
                >
                  Quyết định
                </Typography>
              </Box>
              {suspectMeasurements.length ? (
                suspectMeasurements.map((measurement) => (
                  <Box
                    key={measurement.id}
                    sx={{
                      display: "grid",
                      gridTemplateColumns:
                        "minmax(72px, 1fr) minmax(96px, 1fr) 96px",
                      minWidth: 280,
                      gap: 1,
                      alignItems: "center",
                      px: 1.25,
                      py: 0.75,
                      borderBottom: "1px solid",
                      borderColor: "divider",
                      "&:last-child": { borderBottom: 0 },
                    }}
                  >
                    <Typography variant="body2" fontWeight={800}>
                      #{measurement.id}
                    </Typography>
                    <Typography variant="body2" color="text.secondary">
                      {measurement.length > 0 && measurement.width > 0
                        ? `${measurement.length.toFixed(measurement.unit === "mm" ? 2 : 1)} x ${measurement.width.toFixed(measurement.unit === "mm" ? 2 : 1)} ${measurement.unit}`
                        : "-"}
                    </Typography>
                    <Stack
                      direction="row"
                      spacing={0.5}
                      justifyContent="center"
                    >
                      <Tooltip title="Xác nhận đây là hạt thật" arrow>
                        <IconButton
                          size="small"
                          color="success"
                          onClick={() => onConfirmSuspect(measurement.id)}
                        >
                          <CheckCircle fontSize="small" />
                        </IconButton>
                      </Tooltip>
                      <Tooltip title="Xóa nhận dạng sai khỏi kết quả" arrow>
                        <IconButton
                          size="small"
                          color="error"
                          onClick={() => onDeleteSuspect(measurement.id)}
                        >
                          <Cancel fontSize="small" />
                        </IconButton>
                      </Tooltip>
                    </Stack>
                  </Box>
                ))
              ) : (
                <Typography
                  variant="body2"
                  color="text.secondary"
                  sx={{ px: 1.25, py: 1 }}
                >
                  Không còn hạt nghi ngờ cần xử lý.
                </Typography>
              )}
            </Box>
          )}
          {previewUrl && result && (
            <Box sx={{ mb: 1.5 }}>
              <Typography variant="body2" color="text.secondary" sx={{ mb: 1 }}>
                {text(
                  "Nhận dạng và hậu xử lý đã hoàn tất. Kiểm tra vạch Ref, nhập kích thước thật rồi áp dụng đơn vị mm.",
                  "Detection and post-processing are complete. Check the Ref line, enter its real size, then apply millimeters.",
                )}
              </Typography>
              <Stack
                direction={{ xs: "column", sm: "row" }}
                spacing={1}
                alignItems={{ xs: "stretch", sm: "center" }}
              >
                <TextField
                  label={text("Kích thước Ref (mm)", "Ref size (mm)")}
                  type="number"
                  size="small"
                  value={calibration.referenceMm}
                  onChange={(event) =>
                    onCalibrationChange((current) => ({
                      ...current,
                      referenceMm: event.target.value,
                    }))
                  }
                  inputProps={{ min: 0, step: 0.01 }}
                  sx={{ maxWidth: { sm: 220 } }}
                />
                <Chip
                  size="small"
                  color={calibrationReady ? "primary" : "default"}
                  variant="outlined"
                  label={
                    calibrationPixels > 1
                      ? `${calibrationPixels.toFixed(1)} px`
                      : "Kéo 1 đoạn trên vật mốc"
                  }
                />
                {result && !calibrationImage && (
                  <Button
                    size="small"
                    variant="outlined"
                    onClick={onShowCalibrationImage}
                  >
                    {text("Vẽ/chỉnh vật mốc", "Draw/edit reference")}
                  </Button>
                )}
                <Button
                  size="small"
                  variant="contained"
                  disabled={!calibrationReady}
                  onClick={onApplyCalibration}
                >
                  {result?.calibration?.enabled === true
                    ? text("Cập nhật theo vạch Ref", "Update from Ref line")
                    : text("Áp dụng đơn vị mm", "Apply millimeters")}
                </Button>
                <Button
                  size="small"
                  variant="text"
                  onClick={() =>
                    onCalibrationChange({
                      start: null,
                      end: null,
                      referenceMm: "",
                    })
                  }
                >
                  Xóa vật mốc
                </Button>
              </Stack>
            </Box>
          )}
          {cameraError && (
            <Alert severity="error" sx={{ mb: 1.5 }}>
              {cameraError}
            </Alert>
          )}
          {processError && (
            <Alert severity="error" sx={{ mb: 1.5 }}>
              {processError}
            </Alert>
          )}

          <Stack direction={{ xs: "column", sm: "row" }} spacing={1}>
            <Button variant="contained" onClick={onCamera}>
              Kết nối camera
            </Button>
            <Button variant="outlined" component="label">
              Import ảnh
              <input
                ref={fileInputRef}
                hidden
                type="file"
                accept="image/jpeg,image/png"
                onChange={onFile}
              />
            </Button>
            <Button
              variant="outlined"
              disabled={processing || (!fileName && !cameraActive)}
              onClick={onProcess}
            >
              {processing
                ? "Đang xử lý..."
                : result
                  ? "Chạy lại"
                  : "Chạy xử lý"}
            </Button>
          </Stack>

          {processing && (
            <Box sx={{ width: "100%", mt: 2.5 }}>
              <Box
                sx={{
                  display: "flex",
                  justifyContent: "space-between",
                  alignItems: "center",
                  mb: 1,
                }}
              >
                <Typography
                  variant="body2"
                  color="text.secondary"
                  fontWeight={600}
                >
                  {progressPhase || "Đang xử lý..."}
                </Typography>
                <Typography
                  variant="body2"
                  fontWeight={750}
                  color="primary.main"
                >
                  {Math.round(progress)}%
                </Typography>
              </Box>
              <LinearProgress
                variant="determinate"
                value={progress}
                sx={{
                  height: 6,
                  borderRadius: 3,
                  bgcolor: "rgba(47, 107, 79, 0.08)",
                  "& .MuiLinearProgress-bar": {
                    borderRadius: 3,
                    bgcolor: "primary.main",
                  },
                }}
              />
            </Box>
          )}
        </CardContent>
      </Card>

      {/* Web Calibration Guide Dialog */}
      <Dialog
        open={guideOpen}
        onClose={() => setGuideOpen(false)}
        maxWidth="sm"
        fullWidth
        PaperProps={{
          sx: {
            borderRadius: 3,
            p: 2,
            maxHeight: "calc(100dvh - 32px)",
            overflowY: "auto",
          },
        }}
      >
        <Box
          sx={{
            display: "flex",
            alignItems: "center",
            justifyContent: "space-between",
            mb: 1.5,
          }}
        >
          <Stack direction="row" spacing={1} alignItems="center">
            <HelpOutline color="primary" sx={{ fontSize: 22 }} />
            <Stack spacing={0.25}>
              <Typography
                variant="h6"
                fontWeight={750}
                color="text.primary"
                sx={{ fontSize: "1rem" }}
              >
                Hướng dẫn căn vật mốc
              </Typography>
              <Typography
                variant="caption"
                color="text.secondary"
                sx={{ fontStyle: "italic", lineHeight: 1.25 }}
              >
                *Ảnh chụp minh họa được chụp từ mobile app*
              </Typography>
            </Stack>
          </Stack>
          <IconButton
            size="small"
            onClick={() => setGuideOpen(false)}
            sx={{ color: "text.secondary" }}
          >
            <Close fontSize="small" />
          </IconButton>
        </Box>

        <Divider sx={{ mb: 2 }} />

        <Box
          sx={{
            minHeight: { xs: 390, sm: 520 },
            display: "flex",
            flexDirection: "column",
            justifyContent: "center",
          }}
        >
          <SlideContent
            title={text(currentGuideSlide.title, currentGuideSlide.titleEn)}
            description={text(
              currentGuideSlide.description,
              currentGuideSlide.descriptionEn,
            )}
            diagram={
              <GuideImage
                src={currentGuideSlide.image}
                alt={text(currentGuideSlide.title, currentGuideSlide.titleEn)}
              />
            }
          />
        </Box>

        <Divider sx={{ mt: 2, mb: 1.5 }} />

        <Box
          sx={{
            display: "flex",
            alignItems: "center",
            justifyContent: "space-between",
          }}
        >
          {/* Custom dots indicators */}
          <Stack direction="row" spacing={0.75}>
            {[0, 1, 2, 3].map((step) => (
              <Box
                key={step}
                sx={{
                  width: currentStep === step ? 16 : 6,
                  height: 6,
                  borderRadius: 3,
                  bgcolor: currentStep === step ? "primary.main" : "divider",
                  transition: "all 0.3s ease",
                }}
              />
            ))}
          </Stack>

          <Stack direction="row" spacing={1}>
            {currentStep > 0 && (
              <Button
                size="small"
                color="inherit"
                onClick={handleBack}
                sx={{ fontWeight: 600 }}
              >
                Quay lại
              </Button>
            )}
            <Button
              size="small"
              variant="contained"
              onClick={handleNext}
              sx={{ fontWeight: 700, px: 2 }}
            >
              {currentStep === 3 ? "Bắt đầu" : "Tiếp theo"}
            </Button>
          </Stack>
        </Box>
      </Dialog>

      <Dialog
        open={qcGuideOpen}
        onClose={() => setQcGuideOpen(false)}
        maxWidth="sm"
        fullWidth
        PaperProps={{
          sx: {
            borderRadius: 3,
            p: 2,
            maxHeight: "calc(100dvh - 32px)",
            overflowY: "auto",
          },
        }}
      >
        <Box
          sx={{
            display: "flex",
            alignItems: "center",
            justifyContent: "space-between",
            mb: 1.5,
          }}
        >
          <Stack direction="row" spacing={1} alignItems="center">
            <HelpOutline color="primary" sx={{ fontSize: 22 }} />
            <Typography variant="h6" fontWeight={750} sx={{ fontSize: "1rem" }}>
              QC là gì?
            </Typography>
          </Stack>
          <IconButton
            size="small"
            onClick={() => setQcGuideOpen(false)}
            sx={{ color: "text.secondary" }}
          >
            <Close fontSize="small" />
          </IconButton>
        </Box>

        <Divider sx={{ mb: 2 }} />

        <Stack spacing={1.5}>
          <Alert severity="info">
            QC là bước kiểm tra chất lượng kết quả sau khi AI tách từng hạt. Nó
            không phải một loại hạt mới.
          </Alert>
          <Typography variant="body2" color="text.secondary">
            Vùng xanh là hạt đang được tính là hợp lệ. Vùng đỏ là hạt hệ thống
            nghi có lỗi tách dính, tách thiếu, hoặc kích thước lệch bất thường
            so với nhóm còn lại.
          </Typography>
          <Typography variant="body2" color="text.secondary">
            Nếu nhìn ảnh thấy hạt đỏ vẫn được tách đúng, bật "Chỉnh hạt nghi
            ngờ" rồi dùng bảng ID bên dưới ảnh để xác nhận là hạt thật hoặc xóa
            nhận dạng sai khỏi kết quả.
          </Typography>
          <Typography variant="body2" color="text.secondary">
            Sau khi chỉnh, số hạt nghi ngờ, độ lệch chuẩn báo cáo và file CSV sẽ
            được tính lại cho kết quả hiện tại.
          </Typography>
        </Stack>

        <Box sx={{ display: "flex", justifyContent: "flex-end", mt: 2 }}>
          <Button variant="contained" onClick={() => setQcGuideOpen(false)}>
            Đã hiểu
          </Button>
        </Box>
      </Dialog>
    </>
  );
};
