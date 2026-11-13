@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\start_project.ps1" -Editor
if errorlevel 1 pause
