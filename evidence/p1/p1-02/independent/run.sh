#!/bin/bash
# Usage: run.sh <logname> <godot args...>  (isolated APPDATA)
ROOT="C:/godot/greenvader"
D="$ROOT/evidence/p1/p1-02/independent"
LOG="$D/$1"; shift
mkdir -p "$D/profile/roaming" "$D/profile/local"
APPDATA="C:\godot\greenvader\evidence\p1\p1-02\independent\profile\roaming" LOCALAPPDATA="C:\godot\greenvader\evidence\p1\p1-02\independent\profile\local" \
  "C:/godot/Godot_v4.7.2-stable_win64_console.exe" --path "$ROOT" --log-file "$LOG" "$@"
