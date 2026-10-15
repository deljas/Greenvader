#!/bin/bash
# Two mutation runs that needed other line-ending handling than mut.sh. Usage: mut_b.sh
cd /c/godot/greenvader
run_mut() {
  N=$1; F=$2; E=$3
  cp "$F" "/tmp/mut_backup.gd"
  perl -0pi -e "$E" "$F"
  if cmp -s "$F" /tmp/mut_backup.gd; then echo "$N: MUTATION DID NOT APPLY"; return; fi
  evidence/p2/p2-03/run_godot.sh "mut_$N.log" --headless --script res://tests/p2/p2_03_checks.gd >/dev/null 2>&1
  echo "$N: exit=$? fails=$(grep -c '^FAIL' evidence/p2/p2-03/mut_$N.log) $(grep -E 'RESULT' evidence/p2/p2-03/mut_$N.log)"
  cp /tmp/mut_backup.gd "$F"
}
run_mut M4_pickup_while_downed scripts/play/play_state.gd 's/\tif health\.downed:\r?\n\t\treturn false\r?\n//'
run_mut M9_no_teleport scripts/play/player_health.gd 's/\trevived\.emit\(respawn_position\)\r?\n\nfunc _finish_return/\n\nfunc _finish_return/'
