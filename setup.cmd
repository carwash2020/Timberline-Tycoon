@echo off
rem Double-click me on Windows: runs setup.ps1 (PowerShell blocks .ps1 files by default).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup.ps1"
pause
