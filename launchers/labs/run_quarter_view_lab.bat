@echo off
cd /d "%~dp0..\.."
rem Dedicated technical map. Pass --1080 for a 1920x1080 client area.
set "GODOT=C:\godot\Godot_v4.7.2-stable_win64.exe"
if not exist "%GODOT%" (
  echo Godot not found: %GODOT%
  pause
  exit /b 1
)
start "" "%GODOT%" --path "%~dp0..\.." res://scenes/quarter_view_lab.tscn -- %*
