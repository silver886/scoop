@echo off
set LAUNCHER=start "" /B conhost.exe --headless
if "%~1"=="--debug" set "LAUNCHER="
%LAUNCHER% powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%~dp0script.ps1"
