@echo off
rem Launch the current playable Greenvader scene configured in project.godot.
set "GODOT=C:\godot\Godot_v4.7.2-stable_win64.exe"
if not exist "%GODOT%" (
  echo Godot not found: %GODOT%
  pause
  exit /b 1
)
start "" "%GODOT%" --path "%~dp0."
