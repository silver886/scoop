@echo off
start "" /B conhost.exe --headless powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%~dp0script.ps1"
