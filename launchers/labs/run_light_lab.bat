@echo off
cd /d "%~dp0..\.."
rem Dedicated sun controls and shadowed orbiting point-light lab.
set "GODOT=C:\godot\Godot_v4.7.2-stable_win64.exe"
if not exist "%GODOT%" (
  echo Godot not found: %GODOT%
  pause
  exit /b 1
)
start "" "%GODOT%" --path "%~dp0..\.." --scene res://scenes/light_lab.tscn --rendering-method forward_plus --rendering-driver vulkan
