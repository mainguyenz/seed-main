# SeedVision

Monorepo phân tích ảnh hạt giống bằng YOLO segmentation ONNX. Web chạy inference qua backend/Python worker. Mobile Flutter chạy inference local bằng ONNX Runtime và chỉ đồng bộ kết quả khi người dùng đăng nhập.

## Tổng Quan

| Phần | Trạng thái |
| --- | --- |
| Backend | Express API, MongoDB, JWT, Python worker |
| Web | React/Vite, gọi backend để phân tích ảnh |
| Mobile | Flutter Android, local-first, guest vẫn phân tích được |
| iOS | Chưa commit runner `mobile/ios`; tạo runner trên macOS khi cần build |
| Production | Azure Web App, deploy từ `main` bằng GitHub Actions |

## Tech Stack

| Layer | Công nghệ |
| --- | --- |
| Backend | Node.js, Express, Mongoose, JWT, Socket.IO |
| Image worker | Python, ONNX Runtime, OpenCV, NumPy |
| Web | React, Vite, Material UI, Zustand |
| Mobile | Flutter, Riverpod, Dio, flutter_onnxruntime |
| Deploy | Docker, Azure Web App, Azure Container Registry, GitHub Actions |

## Cấu Trúc Repo

| Path | Nội dung |
| --- | --- |
| `backend/` | API, auth, MongoDB models, Python worker |
| `backend/python/grain_pipeline/` | Inference, đo mask, calibration, QC, render preview |
| `backend/model/main_model/best.onnx` | Model server production |
| `web/` | React web client |
| `mobile/` | Flutter app và Android runner |
| `mobile/assets/models/` | Model ONNX cho mobile |
| `shared/` | Constant và validator dùng chung cho JS |
| `scripts/` | Script chạy/export local |
| `test_images/` | Ảnh mẫu để smoke test |
| `Dockerfile` | Build web + backend + Python worker cho production |

## Luồng Chạy

Web:

```text
Browser -> React web -> /api/grain/analyze-public hoặc /api/grain/analyze
-> Express -> backend/python/analyze_grains.py
-> backend/python/grain_pipeline/ -> backend/model/main_model/best.onnx
-> JSON result + preview PNG + CSV + optional MongoDB history
```

Mobile:

```text
Camera/gallery -> Flutter dashboard -> OfflineGrainAnalyzer
-> flutter_onnxruntime -> mobile ONNX model
-> local result/history/CSV -> optional /api/grain/runs/import
```

Mobile không cần backend để phân tích ảnh. Backend cần cho đăng nhập, lưu/sync lịch sử và web inference.

## Runtime Models

| File | Dùng ở đâu |
| --- | --- |
| `backend/model/main_model/best.onnx` | Backend/Python worker |
| `mobile/assets/models/best_mobile_yolo26_640.onnx` | Mobile safe profile |
| `mobile/assets/models/best_1024_int8_static.onnx` | Mobile Android quality profile |

Chỉ commit model runtime. Model thử nghiệm, export cũ, `.pt`, `.onnx` ngoài danh sách trên không nên đưa lên repo.

## Cài Đặt Local

Yêu cầu:

- Node.js `>=18`, npm `>=9`
- Python `3.11+`
- MongoDB nếu cần auth/history local
- Flutter SDK + Android SDK
- macOS + Xcode nếu build iOS

```powershell
npm install
py -3.11 -m venv backend\.venv
backend\.venv\Scripts\python.exe -m pip install -r backend\python\requirements.txt
Push-Location mobile
flutter pub get
Pop-Location
```

Copy `.env.example` thành `.env` trước khi chạy backend local.

## Biến Môi Trường Chính

| Biến | Mục đích |
| --- | --- |
| `PORT` | Port backend, mặc định `3000` |
| `MONGODB_URI` | MongoDB connection string |
| `JWT_ACCESS_SECRET`, `JWT_REFRESH_SECRET` | JWT secrets |
| `ALLOWED_ORIGINS` | Origin web được phép gọi API |
| `GRAIN_PROCESS_TIMEOUT_MS` | Timeout Python worker |
| `GRAIN_PYTHON_BIN` | Override Python executable |
| `GRAIN_DEFAULT_PARAMS_JSON` | Override default tham số phân tích |

Mobile API override:

```powershell
flutter run --dart-define=BASE_URL=http://192.168.1.x:3000/api
```

Nếu không truyền `BASE_URL`, mobile dùng production API và có cơ chế dò backend trong LAN.

## Chạy Và Build

| Việc | Lệnh |
| --- | --- |
| Chạy backend + web | `npm run dev` |
| Chạy backend | `npm run dev:backend` |
| Chạy web | `npm run dev:web` |
| Build web | `npm run build:web` |
| Chạy mobile | `cd mobile; flutter run` |
| Build Android APK | `cd mobile; flutter build apk --release --no-pub` |
| Export APK/AAB signed | `scripts\export_mobile_release.bat` |

Local URLs:

| Service | URL |
| --- | --- |
| Web | `http://localhost:5173` |
| Backend | `http://localhost:3000` |
| API | `http://localhost:3000/api` |

Android APK output:

```text
mobile/build/app/outputs/flutter-apk/app-release.apk
```

## Build iOS

Repo chưa commit `mobile/ios`. Tạo runner trên macOS:

```bash
cd mobile
flutter create --platforms=ios .
flutter pub get
open ios/Runner.xcworkspace
```

Checklist iOS:

- cấu hình bundle id, signing team, display name, icon trong Xcode;
- giữ model ONNX trong `mobile/pubspec.yaml`;
- test `OfflineGrainAnalyzer` trên thiết bị thật;
- truyền `--dart-define=BASE_URL=...` khi test backend local;
- thêm handler App Store nếu bật update gate cho iOS.

## API

Production API:

```text
https://seed-vanb2207577-aybrd9fwhnf3hqeq.eastasia-01.azurewebsites.net/api
```

| Method | Path | Auth | Mục đích |
| --- | --- | --- | --- |
| `POST` | `/api/auth/register` | No | Tạo tài khoản |
| `POST` | `/api/auth/login` | No | Đăng nhập |
| `POST` | `/api/auth/refresh` | No | Refresh token |
| `POST` | `/api/auth/logout` | Yes | Đăng xuất |
| `GET` | `/api/auth/me` | Yes | User hiện tại |
| `GET` | `/api/users/me` | Yes | Profile |
| `PATCH` | `/api/users/me` | Yes | Cập nhật profile |
| `GET` | `/api/users` | Admin | Danh sách user |
| `GET` | `/api/grain/health` | No | Worker health/default params |
| `POST` | `/api/grain/analyze-public` | No | Web guest phân tích ảnh |
| `POST` | `/api/grain/analyze` | Yes | Web user phân tích và lưu run |
| `GET` | `/api/grain/runs` | Yes | Danh sách run |
| `POST` | `/api/grain/runs/import` | Yes | Mobile sync run local |
| `GET` | `/api/grain/runs/:id` | Yes | Chi tiết run |
| `PUT` | `/api/grain/runs/:id/result` | Yes | Lưu kết quả sau chỉnh QC |
| `DELETE` | `/api/grain/runs/:id` | Yes | Xóa run |

Request phân tích ảnh dùng `multipart/form-data`:

| Field | Bắt buộc | Ghi chú |
| --- | --- | --- |
| `image` | Yes | JPG/PNG, tối đa 25 MB |
| `referencePixels` | No | Độ dài vật mốc theo pixel |
| `referenceMm` | No | Độ dài thật của vật mốc, đơn vị mm |
| `referencePixelSpace` | No | Thường là `original` |
| `referenceX1`, `referenceY1`, `referenceX2`, `referenceY2` | No | Hai điểm vật mốc |

Response chính gồm `image`, `segmentation`, `calibration`, `summary`, `measurements`, `csv`, `overlay_png_base64`, `mask_png_base64`, `labels_png_base64`.

## File Quan Trọng

| Việc | File |
| --- | --- |
| Route/controller backend | `backend/src/routes/*.js`, `backend/src/controllers/*.js` |
| Default tham số grain | `backend/config/grain.settings.json` |
| Pipeline Python | `backend/python/grain_pipeline/pipeline.py` |
| Decode/inference YOLO | `backend/python/grain_pipeline/yolo_segment.py` |
| Đo kích thước, calibration, QC | `backend/python/grain_pipeline/measure.py` |
| Render overlay/mask/labels | `backend/python/grain_pipeline/render.py` |
| Web dashboard | `web/src/pages/DashboardPage.jsx` |
| Web preview/result | `web/src/components/grain/` |
| Mobile dashboard | `mobile/lib/features/dashboard/screens/dashboard_screen.dart` |
| Mobile local inference | `mobile/lib/features/grain/services/offline_grain_analyzer.dart` |
| Mobile API/result mapping | `mobile/lib/features/grain/services/grain_analysis_api.dart` |
| Mobile local history | `mobile/lib/features/grain/services/local_grain_run_store.dart` |
| Mobile base URL | `mobile/lib/core/constants/app_constants.dart` |

Khi đổi measurement, calibration, QC, CSV hoặc result schema, kiểm tra cả backend và mobile.

## Kiểm Thử

```powershell
.\backend\.venv\Scripts\python.exe -m py_compile backend\python\grain_pipeline\measure.py backend\python\grain_pipeline\pipeline.py backend\python\grain_pipeline\yolo_segment.py backend\python\grain_pipeline\render.py backend\python\grain_pipeline\mask_refine.py backend\python\grain_pipeline\classical_fallback.py
npm run build:web
Push-Location mobile
flutter analyze
flutter test
flutter build apk --release --no-pub
Pop-Location
```

Smoke test Python worker:

```powershell
$env:PYTHONPATH='backend\python'
@'
from pathlib import Path
from grain_pipeline.pipeline import analyze_image
r = analyze_image(Path("test_images/sample.jpg"), {})
print(r["summary"]["count"], r["segmentation"]["execution"], r["measurements"][0]["measurement_method"])
'@ | backend\.venv\Scripts\python.exe -
```

## Deploy

Production:

```text
https://seed-vanb2207577-aybrd9fwhnf3hqeq.eastasia-01.azurewebsites.net
```

Flow:

```text
push main -> GitHub Actions -> Docker build -> Azure Container Registry -> Azure Web App
```

Workflow:

```text
.github/workflows/deploy-main_seed-vanb2207577.yml
```

## Không Commit

- `.env` hoặc secret
- báo cáo, `.docx`, dataset local
- APK/AAB và build output
- model thử nghiệm ngoài runtime
- `AGENTS.md`
