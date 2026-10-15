#!/bin/bash
cd /c/godot/greenvader
P=evidence/p2/p2-05/independent
run() { N=$1; SC=$2; shift 2; bash $P/run.sh reg_$N.log --script $SC "$@" >/dev/null 2>&1; echo "$N exit=$? $(grep -E 'RESULT' $P/reg_$N.log | tail -2 | tr '\n' '|') fails=$(grep -c '^FAIL' $P/reg_$N.log)"; }
run p1_01 res://tests/p1/p1_01_checks.gd &
run p1_02 res://tests/p1/p1_02_checks.gd &
run p1_03 res://tests/p1/p1_03_checks.gd &
wait
run p1_04 res://tests/p1/p1_04_checks.gd &
run p1_05 res://tests/p1/p1_05_checks.gd &
run p1_06 res://tests/p1/p1_06_checks.gd &
wait
run p2_01 res://tests/p2/p2_01_checks.gd &
run p0_self res://tests/self/p0_checks.gd &
run p0_art res://tests/independent/p0_art_checks.gd &
run p2_02 res://tests/p2/p2_02_checks.gd &
wait
run p2_03 res://tests/p2/p2_03_checks.gd &
run p2_04 res://tests/p2/p2_04_checks.gd &
run p2_05 res://tests/p2/p2_05_checks.gd -- --skip-long &
wait
