#!/bin/bash
# Usage: sweep.sh <label> <mode> <minutes> <sim-overrides> <play-overrides>
cd /c/godot/greenvader
L=$1; M=$2; MIN=$3; SIM=$4; PLAY=$5
evidence/p1/p1-06/run_godot.sh sweep_${L}.log --headless --script res://tests/p1/p1_06_tempo.gd -- --mode=$M --minutes=$MIN --sim="$SIM" --play="$PLAY" >/dev/null 2>&1
grep TEMPO_RESULT evidence/p1/p1-06/sweep_${L}.log | python -c "
import sys,json
d=json.loads(sys.stdin.read().split('TEMPO_RESULT ',1)[1])
r=d['reach_times_min']
print('$L mode=$M done=%s min=%.1f pct=%.1f 50%%=%s 90%%=%s 99%%=%s 100%%=%s stall=%.0f/%.0f carrots=%d seedshots=%d refills=%d'%(d['complete'],d['minutes'],d['percent'],r.get('50'),r.get('90'),r.get('99'),r.get('100'),d['stall_total_s'],d['stall_longest_s'],d['carrots_placed'],d['shots_seed'],d['refills']))
"
