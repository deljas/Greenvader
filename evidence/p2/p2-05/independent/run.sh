#!/bin/bash
ROOT="C:/godot/greenvader"; P="$ROOT/evidence/p2/p2-05/independent"
LOG="$P/$1"; shift
APPDATA="C:\godot\greenvader\evidence\p2\p2-05\independent\profile\roaming" LOCALAPPDATA="C:\godot\greenvader\evidence\p2\p2-05\independent\profile\local" "C:/godot/Godot_v4.7.2-stable_win64_console.exe" --headless --path "$ROOT" --log-file "$LOG" "$@"
