#!/bin/bash
# Sequential regression runner for P1-05 verification (all outputs under evidence/p1/p1-05/independent/).
cd C:/godot/greenvader
R=tests/p1/independent/p1_05_run.sh
D=res://tests/p1/independent/reg05
run() { name=$1; shift; echo "=== $name"; bash $R reg_${name}.log "$@" > evidence/p1/p1-05/independent/reg_${name}_stdout.log 2>&1; echo "exit=$?"; grep -E "V_RESULT|failures|FAIL" evidence/p1/p1-05/independent/reg_${name}_stdout.log | tail -4; }
run r_impl_p1_05 --headless --script $D/r_impl_p1_05.gd
run r_impl_p1_01 --headless --script $D/r_impl_p1_01.gd
run r_impl_p1_02 --headless --script $D/r_impl_p1_02.gd
run r_impl_p1_03 --headless --script $D/r_impl_p1_03.gd
run r_impl_p1_04 --headless --script $D/r_impl_p1_04.gd
run r_p0_checks --headless --script $D/r_p0_checks.gd
run r_p0_art --headless --script $D/r_p0_art.gd
run r_p1_01_v --headless --script $D/r_p1_01_v.gd
run r_p1_02_v --headless --fixed-fps 60 --script $D/r_p1_02_v.gd
run r_p1_03_logic --headless --script $D/r_p1_03_logic.gd
for s in chain pause night; do run scene3_$s --headless --fixed-fps 60 --script $D/r_p1_03_scene.gd -- --only=$s; done
run scene3_rate --headless --fixed-fps 60 --script $D/r_p1_03_scene.gd -- --only=rate --hz=60
run r_p1_04_logic --headless --script $D/r_p1_04_logic.gd
for s in pause water; do run scene4_$s --headless --fixed-fps 60 --script $D/r_p1_04_scene.gd -- --only=$s; done
for hz in 30 60 144; do run scene4_rate_$hz --headless --script $D/r_p1_04_scene.gd -- --only=rate --hz=$hz; done
echo ALLDONE
