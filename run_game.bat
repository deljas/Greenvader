@echo off
rem Launch Greenvader with the recorded Godot 4.7.2 baseline.
set "GODOT=C:\godot\Godot_v4.7.2-stable_win64.exe"
if not exist "%GODOT%" (
  echo Godot not found: %GODOT%
  pause
  exit /b 1
)
start "" "%GODOT%" --path "%~dp0."
