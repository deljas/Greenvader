#!/bin/bash
# Mutation runs: apply one change, run the checks, restore the file. Usage: mut.sh
cd /c/godot/greenvader
run_mut() { # name file perl-expr
  N=$1; F=$2; E=$3
  cp "$F" "/tmp/mut_backup.gd"
  perl -0pi -e "$E" "$F"
  if cmp -s "$F" /tmp/mut_backup.gd; then echo "$N: MUTATION DID NOT APPLY"; return; fi
  evidence/p2/p2-03/run_godot.sh "mut_$N.log" --headless --script res://tests/p2/p2_03_checks.gd >/dev/null 2>&1
  echo "$N: exit=$? fails=$(grep -c '^FAIL' evidence/p2/p2-03/mut_$N.log) $(grep -E 'RESULT' evidence/p2/p2-03/mut_$N.log)"
  cp /tmp/mut_backup.gd "$F"
}
run_mut M1_no_invuln scripts/play/player_health.gd 's/\tinvuln_steps = _invuln_steps\n\tvar away/\tinvuln_steps = 0\n\tvar away/'
run_mut M2_reset_seeds scripts/play/player_health.gd 's/\tplay\.heal_player\(play\.hp_max\)\n\tinvuln_steps = _respawn_invuln_steps/\tplay.heal_player(play.hp_max)\n\tplay.seeds = play.tuning.seed_start\n\tinvuln_steps = _respawn_invuln_steps/'
run_mut M3_shared_slot scripts/play/ground_pickups.gd 's/owner_id >= PLANT_OWNER_BASE and owner_id < ENEMY_OWNER_BASE and String/owner_id >= PLANT_OWNER_BASE and String/; s/\t\tif owner_id >= ENEMY_OWNER_BASE:\n\t\t\tif enemy_cap >= 0 and count_enemy_owned\(\) >= enemy_cap:\n\t\t\t\treturn false\n\t\telif plant_cap/\t\tif plant_cap/'
run_mut M4_pickup_while_downed scripts/play/play_state.gd 's/\tif health\.downed:\n\t\treturn false\n//'
run_mut M5_knock_ignores_map scripts/play/play_driver.gd 's/player\.step\(motion\)/player.simulation_position += motion/'
run_mut M6_no_direct_credit scripts/play/play_state.gd 's/last_drop_direct_seeds = add_seeds\(credit\)/last_drop_direct_seeds = 0/'
run_mut M7_no_full_heal scripts/play/player_health.gd 's/\tplay\.heal_player\(play\.hp_max\)\n\tinvuln_steps = _respawn/\tinvuln_steps = _respawn/'
run_mut M8_longer_contact scripts/play/player_health.gd 's/field\.tuning\.hit_radius_px, player_position, half/field.tuning.hit_radius_px + 2.0, player_position, half/; s/circle_touches_rect\(field\.boar_body_center\(boar\), field\.tuning\.hit_radius_px, player_position, half\)/circle_touches_rect(field.boar_body_center(boar), field.tuning.hit_radius_px + 2.0, player_position, half)/'
run_mut M9_no_teleport scripts/play/player_health.gd 's/	_finish_return(play)
	revived.emit(respawn_position)/	_finish_return(play)/'
