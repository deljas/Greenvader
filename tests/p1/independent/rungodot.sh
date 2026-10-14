#!/bin/bash
# Usage: rungodot.sh <logname> <godot args...> ; isolates APPDATA/LOCALAPPDATA to evidence/p1/p1-01/independent/profile
ROOT="C:/godot/greenvader"
LOG="$ROOT/evidence/p1/p1-01/independent/$1"; shift
mkdir -p "$ROOT/evidence/p1/p1-01/independent/profile/roaming" "$ROOT/evidence/p1/p1-01/independent/profile/local"
APPDATA="C:\godot\greenvader\evidence\p1\p1-01\independent\profile\roaming" LOCALAPPDATA="C:\godot\greenvader\evidence\p1\p1-01\independent\profile\local" \
  "C:/godot/Godot_v4.7.2-stable_win64_console.exe" --path "$ROOT" --log-file "$LOG" "$@"
