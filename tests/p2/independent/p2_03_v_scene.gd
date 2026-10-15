extends SceneTree
## Independent P2-03 verification on the real main.tscn. Input: engine-internal injection only.
## Run: Godot --headless --fixed-fps 60 --path <p> --script res://tests/p2/independent/p2_03_v_scene.gd -- --hz=N
## Expectations come from the ticket / claimed spec: contact 2, invuln 1.2 s, knock 12 px, downed 1.5 s, respawn invuln 2.0 s, caps 12/35.
var results: Array[Dictionary] = []
var main: Node
var hz: int = 60
var e: EnemyField
var w: WorldState
var play: PlayState
var player: Node2D
var pv: Node
var mouse_screen: Vector2 = Vector2(320, 180)
var hit_times: Array[float] = []
var hit_amounts: Array[int] = []
var follow: Boar = null
var follow_off: Vector2 = Vector2(-9, 0)

func _initialize() -> void:
	run.call_deferred()

func rec(id: String, cond: String, ok: bool, observed: String) -> void:
	results.append({"id": id, "condition": cond, "status": "PASS" if ok else "FAIL", "observed": observed})
	print("%s [%s] %s :: %s" % ["PASS" if ok else "FAIL", id, cond, observed])

func ticks(n: int) -> void:
	for i: int in n:
		await physics_frame
		if follow != null:
			follow.pos = player.simulation_position + follow_off

func secs(s: float) -> void:
	await ticks(roundi(s * hz))

func key_event(code: Key, pressed: bool) -> void:
	var ev: InputEventKey = InputEventKey.new()
	ev.physical_keycode = code
	ev.keycode = code
	ev.pressed = pressed
	Input.parse_input_event(ev)
	await process_frame

func key_tap(code: Key) -> void:
	await key_event(code, true)
	await key_event(code, false)

func aim_at(world_point: Vector2) -> void:
	var guess: Vector2 = world_point - player.position + Vector2(320, 180)
	for attempt: int in 4:
		var m: InputEventMouseMotion = InputEventMouseMotion.new()
		m.position = guess
		m.global_position = guess
		mouse_screen = guess
		Input.parse_input_event(m)
		await process_frame
		var achieved: Vector2 = player.get_global_mouse_position()
		if achieved.distance_to(world_point) < 0.6:
			break
		guess += world_point - achieved

func click(button: MouseButton) -> void:
	for pressed: bool in [true, false]:
		var ev: InputEventMouseButton = InputEventMouseButton.new()
		ev.button_index = button
		ev.pressed = pressed
		ev.position = mouse_screen
		ev.global_position = mouse_screen
		Input.parse_input_event(ev)
		await process_frame

func teleport(p: Vector2) -> void:
	player.simulation_position = p
	player.position = p.round()
	await ticks(3)

func bare_boar(id: int, pos: Vector2) -> Boar:
	var b: Boar = Boar.new()
	b.id = id
	b.nest_id = e.nests[0].id
	b.zone = e.nests[0].zone
	b.hp = 3
	b.pos = pos
	b.wait = 100000000
	e.boars.append(b)
	return b

func snap() -> Dictionary:
	var nest_state: Array = []
	for n: Nest in e.nests:
		nest_state.append([n.alive, n.hp])
	return {
		"seeds": play.seeds, "water": play.water, "greened": w.greened_count, "zg": w.zone_greened_count.duplicate(), "zt": w.zone_target_count.duplicate(),
		"zs": w.zone_state.duplicate(), "nests": nest_state, "cult": _cult_ids(), "stage": w.stage.duplicate(),
		"carc": e.carcasses.size(), "boars": e.boars.size(), "fert": w.fertility.duplicate(), "etime": e.time, "ptime": play.production_time,
		"killed": e.total_killed, "selected": String(play.selected_def().key),
	}

## Open spot: feet clear along x within +-76 and y within +-16 (so knocks and a following boar never hit a wall).
func open_spot(near: Vector2, min_dist: float) -> Vector2:
	for ty: int in range(60, w.height - 60, 2):
		for tx: int in range(60, w.width - 60, 2):
			var p: Vector2 = Vector2((tx + 0.5) * 4.0, (ty + 0.5) * 4.0)
			if p.distance_to(near) < min_dist or p.distance_to(near) > 400.0:
				continue
			var ok: bool = true
			for dx: int in range(-76, 77, 4):
				for dy: int in [-16, 0, 16]:
					if not Walker.is_clear(w, 4, p + Vector2(dx, dy), Vector2(3, 2)):
						ok = false
						break
				if not ok:
					break
			if ok:
				return p
	return Vector2.INF

func wall_spot() -> Vector2:
	for ty: int in range(8, w.height - 8):
		for tx: int in range(20, w.width - 20):
			var p: Vector2 = Vector2((tx + 0.5) * 4.0, (ty + 0.5) * 4.0)
			if Walker.is_clear(w, 4, p, Vector2(3, 2)) and Walker.is_clear(w, 4, p + Vector2(-2, 0), Vector2(3, 2)) and not Walker.is_clear(w, 4, p + Vector2(5, 0), Vector2(3, 2)) and not Walker.is_clear(w, 4, p + Vector2(5, 5), Vector2(3, 2)):
				return p
	return Vector2.INF

func _cult_ids() -> String:
	var out: Array = []
	for pl in play.cultivation.plants:
		out.append([pl.uid, String(pl.key), pl.tile.x, pl.tile.y])
	return JSON.stringify(out)

func _ge_arr(a: PackedInt32Array, b: PackedInt32Array) -> bool:
	if a.size() != b.size():
		return false
	for i: int in a.size():
		if a[i] < b[i]:
			return false
	return true

func run() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--hz="):
			hz = int(a.trim_prefix("--hz="))
	Engine.physics_ticks_per_second = hz
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await ticks(3)
	e = main.enemies
	w = main.grid
	play = main.play
	player = main.player
	pv = main.projectile_view
	main.enemy_tuning.boar_cap = 0
	var start: Vector2 = player.simulation_position
	rec("start", "hp full 10 at start", play.hp == 10 and play.hp_max == 10, "start=%s hp=%d" % [str(start), play.hp])
	play.health.damaged.connect(func(amount: int, _s: Vector2) -> void:
		hit_times.append(play.health.time)
		hit_amounts.append(amount))

	play.seeds = 30
	play.water = 60.0
	var cult_idx: int = -1
	for i: int in play.selectable.size():
		if play.selectable[i].is_cultivated():
			cult_idx = i
			break
	var placed: int = 0
	if cult_idx >= 0:
		var key: StringName = play.selectable[cult_idx].key
		for off: int in range(0, 120, 12):
			if placed >= 2:
				break
			if play.land_plant(key, start + Vector2(30 + off, 20)) != null:
				placed += 1
	rec("setup.cultivated", "cultivated plants placed for the roll-back check", placed >= 1, "placed=%d" % placed)
	play.seeds = 25
	play.water = 60.0
	await secs(0.3)

	var P: Vector2 = open_spot(start, 60.0)
	rec("setup.spot", "found an open spot away from start", P != Vector2.INF, "P=%s" % str(P))
	var b: Boar = bare_boar(9001, P + Vector2(-30, 0))
	await teleport(P)
	# ---- 2. damage ----
	await secs(0.5)
	rec("dmg.no_touch", "no contact, no damage", play.hp == 10 and hit_times.is_empty(), "hp=%d" % play.hp)
	b.pos = P + follow_off
	await secs(0.3)
	rec("dmg.contact2", "contact takes exactly 2 HP (10 -> 8)", play.hp == 8 and hit_amounts == [2], "hp=%d hits=%s" % [play.hp, str(hit_amounts)])
	var moved: Vector2 = player.simulation_position - P
	var away: Vector2 = (P - (P + follow_off + Vector2(0, -6.0))).normalized()
	rec("dmg.knockback", "pushed 12 px (10.5..13.5) roughly away from the boar", moved.length() > 10.5 and moved.length() < 13.5 and moved.normalized().dot(away) > 0.9, "moved=%.2f dot=%.3f" % [moved.length(), moved.normalized().dot(away)])
	follow = b
	await secs(0.7)
	rec("dmg.invuln_nostack", "continuous contact for ~1.1 s after a hit: no second hit", hit_times.size() == 1 and play.hp == 8, "hits=%d hp=%d" % [hit_times.size(), play.hp])
	await secs(0.5)
	rec("dmg.second", "second hit after invuln ends (hp 6)", hit_times.size() >= 2 and play.hp == 6, "hits=%d hp=%d" % [hit_times.size(), play.hp])
	var interval: float = hit_times[1] - hit_times[0] if hit_times.size() >= 2 else -1.0
	rec("dmg.interval", "interval between contact hits is 1.2 s (+-0.05)", absf(interval - 1.2) < 0.05, "interval=%.4f" % interval)

	# ---- 5. pause during invuln ----
	await key_tap(KEY_ESCAPE)
	await ticks(2)
	var was_paused: bool = paused
	var inv_p: int = play.health.invuln_steps
	var ht_p: float = play.health.time
	await secs(4.0)
	rec("pause.invuln", "Esc freezes invulnerability + health time (4 s)", was_paused and play.health.invuln_steps == inv_p and play.health.time == ht_p and play.hp == 6, "paused=%s invuln %d->%d time %.3f->%.3f hp=%d" % [str(was_paused), inv_p, play.health.invuln_steps, ht_p, play.health.time, play.hp])
	await key_tap(KEY_ESCAPE)
	await ticks(2)
	rec("pause.nobank", "after resume invuln dropped < 0.2 s of steps (no lump sum)", not paused and inv_p - play.health.invuln_steps < 12, "invuln %d->%d" % [inv_p, play.health.invuln_steps])

	# ---- 1/3. downed ----
	await secs(1.5)
	rec("dmg.third", "third hit (hp 4)", play.hp == 4, "hp=%d" % play.hp)
	play.hp = 2
	var sg: Dictionary = {}
	play.health.downed_started.connect(func() -> void:
		sg["before"] = snap()
		sg["t0"] = play.health.time)
	play.health.revived.connect(func(_p: Vector2) -> void:
		sg["after"] = snap()
		sg["t"] = play.health.time
		sg["pos"] = player.simulation_position
		sg["hp"] = play.hp
		sg["inv"] = play.health.invuln_steps)
	var guard: int = 0
	while not play.health.downed and guard < hz * 4:
		await physics_frame
		follow.pos = player.simulation_position + follow_off
		guard += 1
	rec("down.enter", "a contact hit at HP 2 downs the player (hp 0)", play.health.downed and play.hp == 0, "downed=%s hp=%d" % [str(play.health.downed), play.hp])
	follow = null
	b.pos = P + Vector2(-60, 0)
	var dpos: Vector2 = player.simulation_position
	play.pickups.items.clear()
	play.pickups.spawn(GroundPickups.KIND_SEED_FRUIT, dpos, 1)
	play.pickups.spawn(GroundPickups.KIND_HEAL_FRUIT, dpos, GroundPickups.HEAL_OWNER_BASE + 1)
	var seeds_d: int = play.seeds
	var water_d: float = play.water
	await key_event(KEY_D, true)
	await aim_at(dpos + Vector2(40, 0))
	await click(MOUSE_BUTTON_LEFT)
	await click(MOUSE_BUTTON_RIGHT)
	await secs(0.6)
	var shots_empty: bool = pv.shots.is_empty()
	rec("down.locked", "downed: move + fire inputs do nothing (position kept, no shot, seeds kept, water not spent)", player.simulation_position == dpos and shots_empty and play.seeds == seeds_d and play.water >= water_d and play.health.downed, "moved=%.2f shots_empty=%s seeds %d->%d water %.1f->%.1f" % [player.simulation_position.distance_to(dpos), str(shots_empty), seeds_d, play.seeds, water_d, play.water])
	rec("down.no_pickup", "downed: fruits under the player not collected, hp stays 0", play.pickups.items.size() == 2 and play.hp == 0 and play.seeds == seeds_d, "items=%d hp=%d" % [play.pickups.items.size(), play.hp])
	await key_tap(KEY_ESCAPE)
	await ticks(2)
	var ds_p: int = play.health.downed_steps
	await secs(3.0)
	rec("pause.downed", "Esc freezes the downed timer (3 s)", paused and play.health.downed_steps == ds_p and play.health.downed, "downed_steps %d -> %d" % [ds_p, play.health.downed_steps])
	await key_tap(KEY_ESCAPE)
	await ticks(2)
	await key_event(KEY_D, false)
	guard = 0
	while play.health.downed and guard < hz * 4:
		await physics_frame
		guard += 1
	await ticks(2)
	var snap_before: Dictionary = sg.get("before", {})
	var snap_after: Dictionary = sg.get("after", {})
	var revive_t: float = sg.get("t", -1.0)
	var revive_pos: Vector2 = sg.get("pos", Vector2.INF)
	var revive_hp: int = sg.get("hp", -1)
	var revive_inv: int = sg.get("inv", -1)
	var downed_len: float = revive_t - float(sg.get("t0", 0.0))
	rec("down.length", "lying phase lasts 1.5 s of game time (+-0.05; pause excluded)", absf(downed_len - 1.5) < 0.05, "len=%.4f" % downed_len)
	rec("down.world_runs", "world kept running while downed (enemy time and production time advanced ~1.5 s)", absf((snap_after["etime"] - snap_before["etime"]) - 1.5) < 0.1 and absf((snap_after["ptime"] - snap_before["ptime"]) - 1.5) < 0.1, "enemy dt=%.3f production dt=%.3f" % [snap_after["etime"] - snap_before["etime"], snap_after["ptime"] - snap_before["ptime"]])
	rec("revive.state", "return: at start position, HP full 10, invulnerable 2.0 s (120 steps)", revive_pos.distance_to(start) < 0.01 and revive_hp == 10 and revive_inv == 120, "pos=%s start=%s hp=%d inv=%d" % [str(revive_pos), str(start), revive_hp, revive_inv])
	var sb: Dictionary = snap_before
	var sa: Dictionary = snap_after
	var regress: int = 0
	for i: int in w.tile_count():
		if sa["stage"][i] < sb["stage"][i]:
			regress += 1
	rec("keep.seeds_water", "seeds exactly kept; water kept (>= before, not reset)", sa["seeds"] == sb["seeds"] and sa["water"] >= sb["water"] - 0.001 and sa["water"] > 0.0, "seeds %d->%d water %.2f->%.2f" % [sb["seeds"], sa["seeds"], sb["water"], sa["water"]])
	rec("keep.plants_green", "plants/greening not rolled back: no tile regressed, greened >= before, zone counters >= before, targets equal", regress == 0 and sa["greened"] >= sb["greened"] and _ge_arr(sa["zg"], sb["zg"]) and sa["zt"] == sb["zt"], "regressed tiles=%d greened %d->%d zg_equal=%s" % [regress, sb["greened"], sa["greened"], str(sa["zg"] == sb["zg"])])
	rec("keep.zones_nests_cult", "zone state, nests (alive/hp), cultivated plants, carcasses, boars, kills, fertility identical", sa["zs"] == sb["zs"] and sa["nests"] == sb["nests"] and sa["cult"] == sb["cult"] and sa["carc"] == sb["carc"] and sa["boars"] == sb["boars"] and sa["killed"] == sb["killed"] and sa["fert"] == sb["fert"] and sa["selected"] == sb["selected"], "zs=%s nests=%s cult=%s carc=%d boars=%d" % [str(sa["zs"] == sb["zs"]), str(sa["nests"] == sb["nests"]), str(sa["cult"] == sb["cult"]), sa["carc"], sa["boars"]])
	rec("keep.cult_count", "cultivated plants placed earlier are still in the save structure", placed >= 1 and (sa["cult"] as String).length() > 20, "placed=%d cult_json_len=%d" % [placed, (sa["cult"] as String).length()])

	# ---- respawn invuln ----
	play.pickups.items.clear()
	await teleport(P)
	follow = b
	b.pos = P + follow_off
	var hits_pre: int = hit_times.size()
	var g2: int = 0
	while hit_times.size() == hits_pre and g2 < hz * 4:
		await physics_frame
		follow.pos = player.simulation_position + follow_off
		g2 += 1
	var rinv: float = hit_times[hit_times.size() - 1] - revive_t if hit_times.size() > hits_pre else -1.0
	rec("revive.invuln", "no damage for 2.0 s after the return (first hit 2.0 +-0.1 s after it), hp 8 after", absf(rinv - 2.0) < 0.1 and play.hp == 8, "first hit %.4f s after return, hp=%d" % [rinv, play.hp])
	follow = null
	b.pos = P + Vector2(-60, 0)

	# ---- knockback vs wall ----
	var W: Vector2 = wall_spot()
	if W == Vector2.INF:
		rec("knock.wall", "knockback never enters water/building", false, "no wall spot found (NOT_RUN)")
		results[results.size() - 1]["status"] = "NOT_RUN"
	else:
		await secs(2.5)
		play.health.invuln_steps = 0
		await teleport(W)
		var hits_k: int = hit_times.size()
		b.pos = W + Vector2(-9, 0)
		var violation: int = 0
		var max_x: float = 0.0
		for t: int in roundi(0.5 * hz):
			await physics_frame
			if not Walker.is_clear(w, 4, player.simulation_position, Vector2(3, 2)):
				violation += 1
			max_x = maxf(max_x, player.simulation_position.x - W.x)
		rec("knock.wall", "knockback toward a wall: feet never inside water/building; moved < 5 px toward it", hit_times.size() > hits_k and violation == 0 and max_x < 5.0, "hit=%s violations=%d max dx=%.2f W=%s" % [str(hit_times.size() > hits_k), violation, max_x, str(W)])
		b.pos = W + Vector2(-60, 0)

	# ---- 4. drops ----
	await secs(2.5)
	play.hp = 10
	var pk: GroundPickups = play.pickups
	pk.items.clear()
	rec("drop.caps", "pickup caps: total 35, plant 20, enemy 12", pk.total_cap == 35 and pk.plant_cap == 20 and pk.enemy_cap == 12, "total=%d plant=%d enemy=%d" % [pk.total_cap, pk.plant_cap, pk.enemy_cap])
	for i: int in 20:
		pk.spawn(GroundPickups.KIND_SEED_FRUIT, Vector2(8000 + i, 8000), GroundPickups.PLANT_OWNER_BASE + 1 + i)
	var Q: Vector2 = open_spot(P, 100.0)
	if Q == Vector2.INF:
		Q = P
	play.select_index(0)
	var kb: Boar = bare_boar(9002, Q)
	await teleport(Q + Vector2(-40, 0))
	play.seeds = 20
	await aim_at(e.boar_body_center(kb))
	for k: int in 3:
		await click(MOUSE_BUTTON_LEFT)
		await secs(0.6)
	var own: int = pk.count_owned(GroundPickups.ENEMY_OWNER_BASE + kb.id)
	rec("drop.real_kill_plant_full", "plant fruits at cap 20: killing a boar with shots still drops 2 seed fruits", not e.boars.has(kb) and own == 2 and pk.count_plant_owned() == 20, "boar gone=%s hp=%d drops=%d plant_owned=%d seeds=%d sel=%s player=%s boar=%s shots=%s" % [str(not e.boars.has(kb)), kb.hp, own, pk.count_plant_owned(), play.seeds, String(play.selected_def().key), str(player.simulation_position), str(kb.pos), str(pv.shots.size())])
	var s_pre: int = play.seeds
	await teleport(e.boar_body_center(kb) + Vector2(0, 6))
	await secs(0.3)
	rec("drop.collect", "walking over them gives +2 seeds", play.seeds == s_pre + 2 and pk.count_owned(GroundPickups.ENEMY_OWNER_BASE + kb.id) == 0, "seeds %d->%d" % [s_pre, play.seeds])
	pk.items.clear()
	for i: int in 20:
		pk.spawn(GroundPickups.KIND_SEED_FRUIT, Vector2(8000 + i, 8000), GroundPickups.PLANT_OWNER_BASE + 1 + i)
	for i: int in 12:
		pk.spawn(GroundPickups.KIND_SEED_FRUIT, Vector2(8100 + i, 8100), GroundPickups.ENEMY_OWNER_BASE + 700 + i)
	rec("drop.full_slot_refuse", "13th enemy fruit refused on the ground", not pk.spawn(GroundPickups.KIND_SEED_FRUIT, Vector2(8200, 8200), GroundPickups.ENEMY_OWNER_BASE + 800) and pk.count_enemy_owned() == 12, "enemy=%d" % pk.count_enemy_owned())
	var srcs: int = 0
	for k: int in 4:
		if pk.spawn(GroundPickups.KIND_SEED_FRUIT, Vector2(8300 + k, 8300), 1):
			srcs += 1
	rec("drop.source_reserve", "plants 20 + enemies 12 full: a source still gets 3 slots (4th refused, total 35)", srcs == 3 and pk.count_seed_items() == 35, "source accepted=%d total=%d" % [srcs, pk.count_seed_items()])
	rec("drop.heal_budget", "healing fruit still spawns with every seed slot full", pk.spawn(GroundPickups.KIND_HEAL_FRUIT, Vector2(8400, 8400), GroundPickups.HEAL_OWNER_BASE + 5), "heal items=%d" % pk.count_kind(GroundPickups.KIND_HEAL_FRUIT))
	var kb2: Boar = bare_boar(9003, Q)
	play.seeds = 10
	var ground_before: int = pk.count_seed_items()
	e.damage_boar(kb2, 3)
	rec("drop.direct", "enemy slot full: kill credits +2 seeds directly (no new ground fruit)", play.seeds == 12 and pk.count_seed_items() == ground_before, "seeds 10->%d ground %d->%d" % [play.seeds, ground_before, pk.count_seed_items()])
	var kb3: Boar = bare_boar(9004, Q)
	play.seeds = 39
	var lost0: int = play.enemy_lost_seeds
	e.damage_boar(kb3, 3)
	rec("drop.direct_cap", "pouch 39/40: +1 only, the rest lost", play.seeds == 40 and play.enemy_lost_seeds == lost0 + 1, "seeds=%d lost %d->%d" % [play.seeds, lost0, play.enemy_lost_seeds])
	pk.items.clear()

	# ---- save round trip ----
	await secs(2.5)
	play.hp = 6
	play.health.invuln_steps = 0
	play.health.hit(play, 2, Q, Q)
	await ticks(roundi(0.3 * hz))
	var inv_s: int = play.health.invuln_steps
	var d1: Dictionary = JSON.parse_string(JSON.stringify(play.to_dict()))
	var seeds_s: int = play.seeds
	var hp_s: int = play.hp
	var water_s: float = play.water
	await secs(2.0)
	play.load_dict(d1)
	rec("save.invuln", "round trip (not downed): hp, seeds, water, remaining invulnerability restored", play.hp == hp_s and play.seeds == seeds_s and absf(play.water - water_s) < 0.01 and play.health.invuln_steps == inv_s and not play.health.downed, "hp=%d seeds=%d inv %d->%d" % [play.hp, play.seeds, inv_s, play.health.invuln_steps])
	await secs(1.5)
	play.hp = 1
	play.health.invuln_steps = 0
	play.health.hit(play, 2, Q, Q)
	await ticks(roundi(0.4 * hz))
	var was_down: bool = play.health.downed
	var d2: Dictionary = JSON.parse_string(JSON.stringify(play.to_dict()))
	var dc: int = play.health.down_count
	var sd: int = play.seeds
	play.load_dict(d2)
	await ticks(2)
	rec("save.downed", "save taken while downed restores as returned: not downed, hp full, ~2 s invuln, at start, seeds kept", was_down and d2["health"]["downed"] == true and not play.health.downed and play.hp == 10 and play.health.invuln_steps >= 115 and player.simulation_position.distance_to(start) < 0.01 and play.seeds == sd and play.health.down_count == dc, "was_down=%s hp=%d inv=%d pos=%s seeds=%d" % [str(was_down), play.hp, play.health.invuln_steps, str(player.simulation_position), play.seeds])
	var d3: Dictionary = play.to_dict()
	var d3r: Dictionary = JSON.parse_string(JSON.stringify(d3))
	play.load_dict(d3r)
	rec("save.stable", "to_dict -> JSON -> load_dict -> to_dict keeps the health block", JSON.stringify(JSON.parse_string(JSON.stringify(play.to_dict()["health"]))) == JSON.stringify(JSON.parse_string(JSON.stringify(d3["health"]))), "round-trip equal")
	var old_save: Dictionary = JSON.parse_string(JSON.stringify(play.to_dict()))
	old_save.erase("health")
	old_save.erase("enemy_drops")
	var okold: bool = play.load_dict(old_save)
	rec("save.old", "older save without the health block loads, not downed", okold and not play.health.downed, "ok=%s" % str(okold))

	var f: FileAccess = FileAccess.open("res://evidence/p2/p2-03/independent/checks_scene_%d.json" % hz, FileAccess.WRITE)
	f.store_string(JSON.stringify({"hz": hz, "results": results}, "  "))
	f.close()
	var fails: int = 0
	for r: Dictionary in results:
		if r["status"] == "FAIL":
			fails += 1
	print("RESULT scene hz=%d checks=%d failures=%d" % [hz, results.size(), fails])
	quit(1 if fails > 0 else 0)
