@echo off
setlocal
cd /d "%~dp0"

where python >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Python not found in PATH. Please install Python 3 first.
    echo [ERROR] Web UI cannot start.
    pause
    exit /b 1
)

if not exist "web_ui.py" (
    echo [ERROR] web_ui.py not found in this folder.
    pause
    exit /b 1
)

echo ================================================
echo   CF Best IP Web UI starting...
echo   Open in browser:  http://127.0.0.1:5000
echo   Press Ctrl+C to stop the server.
echo ================================================
echo.

python web_ui.py --host 127.0.0.1 --port 5000

echo.
echo ================================================
echo   Web UI stopped.
echo ================================================
pause
endlocal
