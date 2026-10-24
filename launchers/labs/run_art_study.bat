@echo off
cd /d "%~dp0..\.."
rem Isolated ART-01 comparison. The normal game entry point is unchanged.
set "GODOT=C:\godot\Godot_v4.7.2-stable_win64.exe"
if not exist "%GODOT%" (
  echo Godot not found: %GODOT%
  pause
  exit /b 1
)
start "" "%GODOT%" --path "%~dp0..\.." --scene res://scenes/art_study.tscn --resolution 1280x720
