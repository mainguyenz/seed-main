import {
  Alert,
  Box,
  Button,
  Card,
  CardContent,
  Divider,
  Stack,
  Typography,
} from "@mui/material";

import { ResultRow } from "./ResultRow.jsx";
import { useLanguage } from "@/i18n.jsx";

export const DashboardResultPanel = ({
  calibrationMm,
  calibrationPixels,
  calibrationReady,
  result,
  onDownloadCsv,
  onDownloadPng,
}) => {
  const { text } = useLanguage();
  const qc = result?.summary?.qc;
  const calibrationApplied = result?.calibration?.enabled === true;
  const suspectCount = qc?.suspect_count ?? 0;
  const suspectIds = qc?.suspect_ids ?? [];
  const suspectIdText = suspectIds.length
    ? `${text("ID hạt nghi ngờ", "Suspect grain IDs")}: ${suspectIds
        .slice(0, 8)
        .map((id) => `#${id}`)
        .join(", ")}${suspectIds.length > 8 ? ", ..." : ""}.`
    : "";

  return (
    <Stack spacing={2}>
      <Card>
        <CardContent sx={{ p: 2.5 }}>
          <Typography variant="h6" fontWeight={700} mb={0.5}>
            {text("Thông số tham chiếu", "Reference settings")}
          </Typography>
          <Box mb={2} />

          <Stack spacing={1.25}>
            <ResultRow
              label={text("Đơn vị đo", "Measurement unit")}
              value={
                calibrationApplied
                  ? text("Milimét (mm)", "Millimeter (mm)")
                  : text("Điểm ảnh (px)", "Pixels (px)")
              }
            />
            <ResultRow
              label={text("Tỷ lệ thước đo", "Scale ratio")}
              value={
                calibrationApplied
                  ? `${Number(result.calibration.referencePixels ?? calibrationPixels).toFixed(1)} px = ${result.calibration.referenceMm ?? calibrationMm} mm`
                  : text("Chưa thiết lập", "Not set")
              }
            />
          </Stack>
        </CardContent>
      </Card>

      {result && (
        <Card>
          <CardContent sx={{ p: 2.5 }}>
            <Typography variant="h6" fontWeight={700} mb={0.5}>
              {text("Kết quả phân tích", "Analysis result")}
            </Typography>
            <Box mb={2} />

            <Stack spacing={1.2}>
              <ResultRow
                label={text("Mã lần quét", "Run ID")}
                value={
                  result.run?.id ? result.run.id.slice(-8).toUpperCase() : "-"
                }
              />
              <ResultRow
                label={text("Tổng số hạt đo được", "Total measured grains")}
                value={
                  result.segmentation?.segment_count ??
                  result.summary?.count ??
                  "-"
                }
              />
              {suspectCount > 0 && (
                <Alert severity="warning" sx={{ overflowWrap: "anywhere" }}>
                  {text("Hệ thống đang nghi", "The system suspects")}{" "}
                  {suspectCount}{" "}
                  {text(
                    "hạt có thể bị tách vùng ảnh sai hoặc có kích thước bất thường.",
                    "grains may have segmentation errors or unusual size.",
                  )}{" "}
                  {qc.robust_used_for_reporting !== false
                    ? `${text("Độ lệch chuẩn báo cáo được tính trên", "Reported standard deviation is calculated from")} ${qc.inlier_count} ${text("hạt hợp lệ sau kiểm tra.", "valid grains after QC.")}`
                    : text(
                        "Tỷ lệ hạt nghi ngờ cao, nên hệ thống giữ độ lệch chuẩn thô và cần người dùng xem lại ảnh.",
                        "Suspect ratio is high, so the system keeps raw standard deviation and needs user review.",
                      )}{" "}
                  {text(
                    'Có thể dùng nút "Chỉnh hạt nghi ngờ" ở khung ảnh để sửa thủ công.',
                    'Use "Edit suspect grains" in the image panel to fix it manually.',
                  )}
                  {suspectIdText ? ` ${suspectIdText}` : ""}
                </Alert>
              )}

              <Divider sx={{ my: 1 }} />

              <Divider />
              <Stack direction={{ xs: "column", sm: "row" }} spacing={1} pt={1}>
                <Button variant="contained" onClick={onDownloadCsv}>
                  {text("Xuất CSV", "Export CSV")}
                </Button>
                <Button variant="outlined" onClick={onDownloadPng}>
                  {text("Xuất ảnh kết quả", "Export result image")}
                </Button>
              </Stack>
            </Stack>
          </CardContent>
        </Card>
      )}
    </Stack>
  );
};
