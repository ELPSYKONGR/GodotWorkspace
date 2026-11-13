@echo off
setlocal
cd /d "%~dp0"
set "PYTHONUTF8=1"
set "PYTHONPYCACHEPREFIX=%~dp0.cache\pycache"
set "TEMP=%~dp0.cache\tmp"
set "TMP=%~dp0.cache\tmp"
if not exist ".venv\Scripts\python.exe" (
  echo Please run setup.ps1 first.
  pause
  exit /b 1
)
".venv\Scripts\python.exe" -B -m src.cli render %*
if errorlevel 1 (
  echo Rendering failed. See the message above.
  pause
  exit /b 1
)
echo Rendering completed. Open the outputs folder for final.mp4.
pause
