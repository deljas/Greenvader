@echo off
rem Dedicated real-3D art study. Pass --capture to save morning/noon/evening.
set "GODOT=C:\godot\Godot_v4.7.2-stable_win64.exe"
if not exist "%GODOT%" (
  echo Godot not found: %GODOT%
  pause
  exit /b 1
)
start "" "%GODOT%" --path "%~dp0." --scene res://scenes/render_study_3d.tscn --rendering-method forward_plus --rendering-driver vulkan -- %*
