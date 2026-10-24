@echo off
rem Dedicated automatic walking fixture; no normal-game changes.
set "GODOT=C:\godot\Godot_v4.7.2-stable_win64.exe"
if not exist "%GODOT%" (
  echo Godot not found: %GODOT%
  pause
  exit /b 1
)
start "" "%GODOT%" --path "%~dp0." --scene res://scenes/sprite_shadow_lab.tscn --rendering-method forward_plus --rendering-driver vulkan
