#!/bin/bash
# Usage: run_godot.sh <logname> <godot args...>   (runs Godot with APPDATA/LOCALAPPDATA isolated to evidence/p2/p2-06/profile)
ROOT="C:/godot/greenvader"
LOG="$ROOT/evidence/p2/p2-06/$1"; shift
mkdir -p "$ROOT/evidence/p2/p2-06/profile/roaming" "$ROOT/evidence/p2/p2-06/profile/local"
APPDATA="C:\godot\greenvader\evidence\p2\p2-06\profile\roaming" LOCALAPPDATA="C:\godot\greenvader\evidence\p2\p2-06\profile\local" \
  "C:/godot/Godot_v4.7.2-stable_win64_console.exe" --path "$ROOT" --log-file "$LOG" "$@"
