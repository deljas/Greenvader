#!/bin/bash
# Usage: sweep.sh <name> <tempo args...>   -> runs/<name>.json (+ runs/<name>.out). Headless, no window.
cd /c/godot/greenvader/evidence/p2/p2-06
NAME="$1"; shift
./run_godot.sh "runs/$NAME.log" --headless --script res://tests/p2/p2_06_tempo.gd -- --quiet --out=C:/godot/greenvader/evidence/p2/p2-06/runs/$NAME.json "$@" > "runs/$NAME.out" 2>&1
