@echo off
rem SysMedic evidence collector launcher. Double-click to run.
rem It lists what it will collect and waits for you to type YES. Read-only; works offline.
rem -ExecutionPolicy Bypass applies to this one run only (the script is plain text: open it to read it).
net session >nul 2>&1
if %errorlevel% neq 0 (
  echo.
  echo   This works best as administrator. Right-click this file, "Run as administrator".
  echo   Continuing without it: some items may be incomplete.
  echo.
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0SysMedic-Collect.ps1"
echo.
pause
