@echo off
powershell.exe -NoProfile -File "%~dp0Install.ps1"
if errorlevel 1 (
    echo Installation failed. See the error above.
    pause
    exit /b 1
)
echo Installation complete. The watcher is running and will start at sign-in.
pause
