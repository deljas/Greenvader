#!/bin/bash
# Mutation runs of the P2-04 checks: each mutation is applied to a copy of the source file, the checks run, the file is restored.
cd /c/godot/greenvader
EF=scripts/enemy/enemy_field.gd; ZP=scripts/enemy/zone_progress.gd; WS=scripts/world/world_state.gd
cp $EF /tmp/ef.bak; cp $ZP /tmp/zp.bak; cp $WS /tmp/ws.bak
run() { N=$1; evidence/p2/p2-04/run_godot.sh mut_$N.log --headless --script res://tests/p2/p2_04_checks.gd >/dev/null 2>&1; echo "$N: $(grep -c '^FAIL' evidence/p2/p2-04/mut_$N.log) FAIL lines; $(grep -E 'P2_04_RESULT' evidence/p2/p2-04/mut_$N.log)"; cp /tmp/ef.bak $EF; cp /tmp/zp.bak $ZP; cp /tmp/ws.bak $WS; }
# M1: clearing -> stable without waiting for the last boar
sed -i 's/state == WorldState.ZONE_CLEARING and enemies.boar_count_in_zone(zone) == 0/state == WorldState.ZONE_CLEARING/' $ZP; run M1_stable_without_boars_gone
# M2: no purge of boars when a zone turns stable
sed -i 's/	if new_state < WorldState.ZONE_STABLE:/	if new_state < WorldState.ZONE_STABLE or true:/' $EF; run M2_no_purge
# M3: boars may walk into other zones and bite their plants
sed -i 's/if world.zone_of\[y \* world.width + x\] != zone:/if false:/' $EF
sed -i 's/ or world.zone_of\[index\] != boar.zone or not world.zone_open_to_enemies(world.zone_of\[index\]):/:/' $EF; run M3_cross_zone
# M4: complete one tile early
sed -i 's/return zone >= 0 and zone < zone_count and zone_greened_count\[zone\] == zone_target_count\[zone\]/return zone >= 0 and zone < zone_count and zone_greened_count[zone] >= zone_target_count[zone] - 1/' $WS; run M4_complete_one_early
# M5: unconquered -> clearing when any nest is destroyed (not all)
sed -i 's/enemies.alive_nest_count(zone) == 0:/enemies.alive_nest_count(zone) <= 1:/' $ZP; run M5_clearing_one_nest_early
# M6: load accepts a boar in a stable zone / nest alive in a stable zone
sed -i 's/if zone_status >= WorldState.ZONE_CLEARING and alive_by_zone.has(zone):/if false:/; s/		if not world.zone_open_to_enemies(boar.zone):\n			return false//' $EF; run M6_load_nest_in_stable
# M7: regress allowed: a complete zone goes back to stable when a tile is lost
sed -i 's/world.zone_greened_count\[zone\] == world.zone_target_count\[zone\]:/world.zone_greened_count[zone] == world.zone_target_count[zone] or true:/' $ZP; run M7_dummy
