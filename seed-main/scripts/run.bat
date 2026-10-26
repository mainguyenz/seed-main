@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "SCRIPT_DIR=%~dp0"
for %%I in ("%SCRIPT_DIR%..") do set "ROOT=%%~fI"
cd /d "%ROOT%"
title Seed Launcher

if /i "%~1"=="backend" goto backend_worker

:menu
cls
echo ==========================
echo        Seed Launcher
echo ==========================
echo.
echo 1. Run web
echo 2. Run mobile app
echo 3. Run all
echo 0. Exit
echo.
set /p choice=Choose an option: 

if "%choice%"=="1" goto run_web
if "%choice%"=="2" goto run_mobile
if "%choice%"=="3" goto run_all
if "%choice%"=="0" goto end

echo.
echo Invalid option. Press any key to try again.
pause >nul
goto menu

:run_web
call :start_backend
call :start_web
goto done

:run_mobile
call :start_backend
call :start_mobile
goto done

:run_all
call :start_backend
call :start_web
call :start_mobile
goto done

:start_backend
start "Seed Backend" /D "%ROOT%" cmd /k call scripts\run.bat backend
exit /b

:start_web
start "Seed Web" /D "%ROOT%" cmd /k "npm run dev:web"
exit /b

:start_mobile
start "Seed Mobile" /D "%ROOT%\mobile" cmd /k "echo Seed Mobile will auto-discover the backend on the local network. && flutter pub get && flutter run"
exit /b

:done
echo.
echo Started selected service(s).
echo Close the opened terminal windows to stop them.
echo.
pause
goto menu

:end
endlocal
exit /b

:backend_worker
set "BACKEND_PID="
for /f "tokens=5" %%a in ('netstat -ano -p tcp ^| findstr /R /C:":3000 .*LISTENING"') do (
  if not defined BACKEND_PID set "BACKEND_PID=%%a"
)

if defined BACKEND_PID (
  echo Backend API is already running on port 3000. Restarting it in this window...
  powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-CimInstance Win32_Process -Filter 'name = ''node.exe''' | Where-Object { $_.CommandLine -match 'dev:backend|workspace=backend|nodemon|src/index.js' } | ForEach-Object { Write-Host ('Stopping PID ' + $_.ProcessId); Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }"
  if errorlevel 1 goto backend_failed
  timeout /t 2 /nobreak >nul
)

if not exist backend\.venv\Scripts\python.exe (
  echo Creating Python virtual environment...
  python -m venv backend\.venv
  if errorlevel 1 goto backend_failed
  backend\.venv\Scripts\python.exe -m pip install -r backend\python\requirements.txt
  if errorlevel 1 goto backend_failed
)

echo Starting backend API on:
echo   Local: http://localhost:3000
powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notlike '127.*' -and $_.PrefixOrigin -ne 'WellKnown' } | ForEach-Object { Write-Host ('  LAN:   http://' + $_.IPAddress + ':3000') }"
echo.
echo Mobile auto-discovery will look for /health on port 3000.
npm run dev:backend
exit /b

:backend_failed
echo.
echo Backend setup failed. Check Python installation and backend\python\requirements.txt.
exit /b 1
