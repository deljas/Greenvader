#!/bin/bash
# runs every scene section sequentially (one Godot at a time)
cd C:/godot/greenvader
E=evidence/p1/p1-06/independent
S=res://tests/p1/independent/p1_06_v_scene.gd
for spec in "walk 30" "walk 144" "pause 60" "chain 60" "water 60" "recover 60" "spread 60" "control 60" "carrot 60" "kiwi 60" "invalid 60"; do
  set -- $spec
  echo "=== $1 hz=$2"
  bash tests/p1/independent/p1_06_run.sh v_scene_$1_$2.log --headless --fixed-fps $2 --script $S -- --only=$1 --hz=$2 > $E/v_scene_$1_$2_stdout.log 2>&1
  echo "exit=$?"; grep -a "FAIL\|V_RESULT\|SCRIPT ERROR\|Parse Error" $E/v_scene_$1_$2_stdout.log | head -12
done
echo ALLDONE
