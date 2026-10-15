#!/bin/bash
# Usage: run.sh <logname> <godot args...>  (isolated profile in independent/profile)
ROOT="C:/godot/greenvader"; D="$ROOT/evidence/p2/p2-02/independent"
LOG="$D/$1"; shift
mkdir -p "$D/profile/roaming" "$D/profile/local"
APPDATA="C:\godot\greenvader\evidence\p2\p2-02\independent\profile\roaming" LOCALAPPDATA="C:\godot\greenvader\evidence\p2\p2-02\independent\profile\local" \
  "C:/godot/Godot_v4.7.2-stable_win64_console.exe" --path "$ROOT" --log-file "$LOG" "$@"
