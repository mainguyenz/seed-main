@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "SCRIPT_DIR=%~dp0"
for %%I in ("%SCRIPT_DIR%..") do set "ROOT=%%~fI"
set "MOBILE_DIR=%ROOT%\mobile"
set "OUT_DIR=%ROOT%\artifacts\releases"
set "CURRENT_DIR=%ROOT%\artifacts\release-current"
set "KEY_PROPS=%MOBILE_DIR%\android\key.properties"
set "APK_ARM64_SRC=%MOBILE_DIR%\build\app\outputs\flutter-apk\app-arm64-v8a-release.apk"
set "APK_ARMEABI_SRC=%MOBILE_DIR%\build\app\outputs\flutter-apk\app-armeabi-v7a-release.apk"
set "APK_X86_64_SRC=%MOBILE_DIR%\build\app\outputs\flutter-apk\app-x86_64-release.apk"
set "AAB_SRC=%MOBILE_DIR%\build\app\outputs\bundle\release\app-release.aab"

echo.
echo === SeedVision Mobile Release Export ===
echo Root   : %ROOT%
echo Mobile : %MOBILE_DIR%
echo Output : %OUT_DIR%
echo.

where flutter >nul 2>&1
if errorlevel 1 (
  echo ERROR: Flutter was not found on PATH.
  exit /b 1
)

set "FLUTTER_ROOT="
for /f "delims=" %%F in ('where flutter 2^>nul') do (
  if not defined FLUTTER_ROOT for %%I in ("%%~dpF..") do set "FLUTTER_ROOT=%%~fI"
)
set "DART_EXE=%FLUTTER_ROOT%\bin\cache\dart-sdk\bin\dart.exe"
set "FLUTTER_SNAPSHOT=%FLUTTER_ROOT%\bin\cache\flutter_tools.snapshot"
set "FLUTTER_PACKAGES=%FLUTTER_ROOT%\packages\flutter_tools\.dart_tool\package_config.json"
if not exist "%DART_EXE%" (
  echo ERROR: Dart executable was not found: %DART_EXE%
  exit /b 1
)
if not exist "%FLUTTER_SNAPSHOT%" (
  echo ERROR: Flutter tool snapshot was not found: %FLUTTER_SNAPSHOT%
  exit /b 1
)

if not exist "%KEY_PROPS%" (
  echo ERROR: Release signing config is missing: %KEY_PROPS%
  echo Create mobile\android\key.properties and keep it out of git.
  exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$props=@{}; Get-Content -LiteralPath '%KEY_PROPS%' | Where-Object { $_ -match '^\s*[^#=]+\s*=' } | ForEach-Object { $k,$v=$_.Split('=',2); $props[$k.Trim()]=$v.Trim() }; if (-not $props.storeFile) { Write-Host 'ERROR: key.properties is missing storeFile.'; exit 2 }; $store=Join-Path (Split-Path -Parent '%KEY_PROPS%') $props.storeFile; if (-not (Test-Path -LiteralPath $store)) { Write-Host ('ERROR: Keystore file not found: ' + $store); exit 3 }"
if errorlevel 1 exit /b 1

if /I "%~1"=="clean" (
  echo Running flutter clean...
  pushd "%MOBILE_DIR%"
  call flutter clean
  if errorlevel 1 (
    popd
    exit /b 1
  )
  popd
)

if /I "%~1"=="pub" (
  echo Running flutter pub get...
  pushd "%MOBILE_DIR%"
  call flutter pub get
  if errorlevel 1 (
    popd
    exit /b 1
  )
  popd
)

pushd "%MOBILE_DIR%"

echo Building release APKs split by Android ABI...
call "%DART_EXE%" --packages="%FLUTTER_PACKAGES%" "%FLUTTER_SNAPSHOT%" build apk --release --split-per-abi --no-pub
if errorlevel 1 (
  popd
  exit /b 1
)

echo Building release AAB for Play Console...
call "%DART_EXE%" --packages="%FLUTTER_PACKAGES%" "%FLUTTER_SNAPSHOT%" build appbundle --release --no-pub
if errorlevel 1 (
  popd
  exit /b 1
)
popd

if not exist "%APK_ARM64_SRC%" (
  echo ERROR: ARM64 APK output not found: %APK_ARM64_SRC%
  exit /b 1
)
if not exist "%AAB_SRC%" (
  echo ERROR: AAB output not found: %AAB_SRC%
  exit /b 1
)

if not exist "%OUT_DIR%" mkdir "%OUT_DIR%"
if not exist "%CURRENT_DIR%" mkdir "%CURRENT_DIR%"

copy /Y "%APK_ARM64_SRC%" "%OUT_DIR%\seedvision-release.apk" >nul
copy /Y "%APK_ARM64_SRC%" "%OUT_DIR%\seedvision-release-arm64-v8a.apk" >nul
if exist "%APK_ARMEABI_SRC%" copy /Y "%APK_ARMEABI_SRC%" "%OUT_DIR%\seedvision-release-armeabi-v7a.apk" >nul
if exist "%APK_X86_64_SRC%" copy /Y "%APK_X86_64_SRC%" "%OUT_DIR%\seedvision-release-x86_64.apk" >nul
copy /Y "%AAB_SRC%" "%OUT_DIR%\seedvision-release.aab" >nul
copy /Y "%APK_ARM64_SRC%" "%CURRENT_DIR%\Seed.apk" >nul
copy /Y "%AAB_SRC%" "%CURRENT_DIR%\Seed.aab" >nul

echo.
echo === Export complete ===
echo Install APK : %OUT_DIR%\seedvision-release.apk ^(arm64-v8a^)
if exist "%OUT_DIR%\seedvision-release-armeabi-v7a.apk" echo 32-bit APK : %OUT_DIR%\seedvision-release-armeabi-v7a.apk
if exist "%OUT_DIR%\seedvision-release-x86_64.apk" echo x86_64 APK : %OUT_DIR%\seedvision-release-x86_64.apk
echo Play AAB    : %OUT_DIR%\seedvision-release.aab
echo Easy pick   : %CURRENT_DIR%\Seed.apk ^(arm64-v8a^)
echo Play upload : %CURRENT_DIR%\Seed.aab
echo.
exit /b 0
