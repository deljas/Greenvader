#!/bin/bash
# 隔離プロジェクトで1つの入口スクリプトを実行し、ログを隔離側の evidence/content_pack/self2 へ残す
#   run_one.sh <suite>   例: run_one.sh crops2_logic
set -e
SB='C:/godot/greenvader_content_sandbox'
SBW=/mnt/c/godot/greenvader_content_sandbox
mkdir -p "$SBW/evidence/content_pack/self2"
/mnt/c/godot/Godot_v4.7.2-stable_win64.exe --headless --path "$SB" --script "res://tests/content_pack/self2/$1.gd" 2>&1 | tee "$SBW/evidence/content_pack/self2/$1.log"
