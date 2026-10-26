@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "SCRIPT_DIR=%~dp0"
for %%I in ("%SCRIPT_DIR%.") do set "ROOT=%%~fI"
cd /d "%ROOT%"

set "MODE=%~1"
set "CHECK_ONLY=0"
set "FAILED=0"
set "WARNINGS=0"
set "PYTHON_CMD="
if not defined WIKICROP_ROOT set "WIKICROP_ROOT=D:\Wikicrop"

if /I "%MODE%"=="check" set "CHECK_ONLY=1"
if /I "%MODE%"=="--check" set "CHECK_ONLY=1"
if /I "%MODE%"=="/check" set "CHECK_ONLY=1"
if /I "%MODE%"=="help" goto usage
if /I "%MODE%"=="--help" goto usage
if /I "%MODE%"=="/?" goto usage

if not "%MODE%"=="" if "%CHECK_ONLY%"=="0" (
  echo ERROR: Unknown option "%MODE%".
  echo Usage: install_all.bat [check]
  exit /b 1
)

echo.
echo ==========================================
echo   SeedVision local setup
echo ==========================================
echo Root: %ROOT%
if "%CHECK_ONLY%"=="1" echo Mode: check only, no dependency installation
echo.

call :require_cmd node "Node.js 18+"
call :require_cmd npm "npm 9+"
call :find_python

if "%FAILED%"=="1" (
  echo.
  echo ERROR: Missing required tools. Install them, then run install_all.bat again.
  exit /b 1
)

echo.
echo [1/6] Preparing environment file...
if "%CHECK_ONLY%"=="1" (
  if exist ".env" (
    echo OK: .env exists.
  ) else if exist ".env.example" (
    echo NOTE: .env is missing. Setup mode will create it from .env.example.
  ) else (
    echo WARNING: .env and .env.example were not found. Create .env manually before running backend.
    set /a WARNINGS+=1
  )
) else if not exist ".env" (
  if exist ".env.example" (
    copy /Y ".env.example" ".env" >nul
    echo Created .env from .env.example.
  ) else (
    echo WARNING: .env.example was not found. Create .env manually before running backend.
    set /a WARNINGS+=1
  )
) else (
  echo Keeping existing .env.
)

echo.
echo [2/6] Installing Node workspace dependencies...
if "%CHECK_ONLY%"=="1" (
  if exist "node_modules" (
    echo OK: node_modules exists.
  ) else (
    echo NOTE: node_modules is missing. Setup mode will run npm install.
  )
) else (
  call npm install
  if errorlevel 1 goto fail
)

echo.
echo [3/6] Preparing backend Python virtual environment...
if "%CHECK_ONLY%"=="1" (
  if exist "backend\.venv\Scripts\python.exe" (
    echo OK: backend\.venv exists.
  ) else (
    echo NOTE: backend\.venv is missing. Setup mode will create it and install requirements.txt.
  )
) else if not exist "backend\.venv\Scripts\python.exe" (
  echo Creating backend\.venv ...
  %PYTHON_CMD% -m venv "backend\.venv"
  if errorlevel 1 goto fail
) else (
  echo Keeping existing backend\.venv.
)

if "%CHECK_ONLY%"=="1" (
  echo Check mode skips pip install.
) else (
  echo Installing Python worker requirements...
  "backend\.venv\Scripts\python.exe" -m pip install --disable-pip-version-check -r backend\python\requirements.txt
  if errorlevel 1 goto fail
)

echo.
echo [4/6] Preparing Flutter mobile dependencies...
where flutter >nul 2>&1
if errorlevel 1 (
  echo WARNING: Flutter was not found on PATH. Skipping mobile flutter pub get.
  echo          Install Flutter/Android SDK before running or building the mobile app.
  set /a WARNINGS+=1
) else (
  if "%CHECK_ONLY%"=="1" (
    echo OK: Flutter was found on PATH. Check mode skips flutter pub get.
  ) else (
    pushd "mobile"
    call flutter pub get
    if errorlevel 1 (
      popd
      goto fail
    )
    popd
  )
)

echo.
echo [5/6] Checking model files used at runtime...
call :check_file "backend\model\main_model\best.onnx" "backend/web ONNX model, server input 1024"
call :check_file "mobile\assets\models\best_mobile_yolo26_640.onnx" "mobile ONNX model, device input 640"
if exist "%WIKICROP_ROOT%\extensions\SeedAnalysis\service\model\main_model\best.onnx" (
  echo OK: WikiCrop SeedAnalysis model found at %WIKICROP_ROOT%\extensions\SeedAnalysis\service\model\main_model\best.onnx
) else (
  echo NOTE: WikiCrop SeedAnalysis model was not found at %WIKICROP_ROOT%\extensions\SeedAnalysis\service\model\main_model\best.onnx
  echo       Ignore this if you are only setting up SeedVision, not WikiCrop.
  echo       If WikiCrop is cloned elsewhere, set WIKICROP_ROOT before running this file.
)

echo.
echo [6/6] Local URLs and next commands...
echo SeedVision web local:        http://localhost:5173
echo SeedVision backend local:    http://localhost:3000
echo SeedVision API local:        http://localhost:3000/api
echo Backend health:              http://localhost:3000/health
echo Grain health:                http://localhost:3000/api/grain/health
echo.
echo To run SeedVision locally:
echo   scripts\run.bat
echo.
echo If running mobile on a real phone, keep the phone and this PC on the same Wi-Fi.
echo scripts\run.bat prints the LAN backend URL. If auto-discovery fails, run Flutter with:
echo   flutter run --dart-define=BASE_URL=http://YOUR_PC_LAN_IP:3000/api
echo.
echo To export mobile APK/AAB:
echo   scripts\export_mobile_release.bat
echo Output:
echo   artifacts\releases
echo   artifacts\release-current
echo.
echo WikiCrop SeedAnalysis uses its own runner:
echo   %WIKICROP_ROOT%\extensions\SeedAnalysis\tools\run-local.ps1
echo WikiCrop local page:
echo   http://localhost:8080/w/index.php/Special:SeedAnalysis
echo SeedAnalysis service:
echo   http://127.0.0.1:3001/api

echo.
if "%WARNINGS%"=="0" (
  echo Setup completed.
) else (
  echo Setup completed with %WARNINGS% warnings. Review the messages above.
)
exit /b 0

:require_cmd
where %~1 >nul 2>&1
if errorlevel 1 (
  echo ERROR: %~2 was not found on PATH.
  set "FAILED=1"
) else (
  for /f "delims=" %%V in ('%~1 --version 2^>nul') do (
    echo OK: %~2 - %%V
    goto :require_done
  )
  echo OK: %~2
)
:require_done
exit /b 0

:find_python
py -3.11 --version >nul 2>&1
if not errorlevel 1 (
  set "PYTHON_CMD=py -3.11"
  for /f "delims=" %%V in ('py -3.11 --version 2^>nul') do echo OK: Python - %%V
  exit /b 0
)

py -3 --version >nul 2>&1
if not errorlevel 1 (
  set "PYTHON_CMD=py -3"
  for /f "delims=" %%V in ('py -3 --version 2^>nul') do echo OK: Python - %%V
  exit /b 0
)

python --version >nul 2>&1
if not errorlevel 1 (
  set "PYTHON_CMD=python"
  for /f "delims=" %%V in ('python --version 2^>nul') do echo OK: Python - %%V
  exit /b 0
)

echo ERROR: Python 3 was not found. Install Python, preferably 3.11, then rerun this script.
set "FAILED=1"
exit /b 0

:check_file
if exist "%~1" (
  echo OK: %~2 - %~1
) else (
  echo WARNING: Missing %~2 - %~1
  set /a WARNINGS+=1
)
exit /b 0

:fail
echo.
echo ERROR: Setup failed at the previous step.
exit /b 1

:usage
echo Usage: install_all.bat [check]
echo.
echo   install_all.bat        Install Node, Python and Flutter dependencies.
echo   install_all.bat check  Check tools, paths, models and local URLs only.
echo.
echo Optional:
echo   set WIKICROP_ROOT=D:\Wikicrop
exit /b 0
