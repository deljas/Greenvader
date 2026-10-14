#!/bin/bash
# Usage: p1_04_run.sh <logname> <godot args...> ; isolated profile in evidence/p1/p1-04/independent/profile
ROOT="C:/godot/greenvader"
LOG="$ROOT/evidence/p1/p1-04/independent/$1"; shift
mkdir -p "$ROOT/evidence/p1/p1-04/independent/profile/roaming" "$ROOT/evidence/p1/p1-04/independent/profile/local"
APPDATA="C:\godot\greenvader\evidence\p1\p1-04\independent\profile\roaming" LOCALAPPDATA="C:\godot\greenvader\evidence\p1\p1-04\independent\profile\local" \
  "C:/godot/Godot_v4.7.2-stable_win64_console.exe" --path "$ROOT" --log-file "$LOG" "$@"
