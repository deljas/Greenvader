extends SceneTree
## Independent P2-02 verification on the real main.tscn. Input: engine-internal injection only (Input.parse_input_event).
## Run: Godot --headless --fixed-fps 60 --path <p> --script res://tests/p2/independent/p2_02_v_scene.gd [-- --hz=N]
## Expected values come from the ticket / design text (3 hits, 20 hits, 2 / 4 fruits, radius 4 tiles, +40 / +20, cap 60, 60 s + 40 s,
## 24 carcasses, growth factor 1 + 0.5 * fertility / 100), and from brute-force geometry written here.
var results: Array[Dictionary] = []
var main: Node
var hz: int = 60
var e: EnemyField
var w: WorldState
var play: PlayState
var player: Node2D
var pv: Node
var mouse_screen: Vector2 = Vector2(320, 180)
var obs: Dictionary = {}

func _initialize() -> void:
	run.call_deferred()

func rec(id: String, cond: String, ok: bool, observed: String) -> void:
	results.append({"id": id, "condition": cond, "status": "PASS" if ok else "FAIL", "observed": observed})
	print("%s [%s] %s :: %s" % ["PASS" if ok else "FAIL", id, cond, observed])

func fact(id: String, text: String) -> void:
	results.append({"id": id, "condition": "FACT (not a pass/fail)", "status": "FACT", "observed": text})
	print("FACT [%s] %s" % [id, text])

func ticks(n: int) -> void:
	for i: int in n:
		await physics_frame

func key_tap(code: Key) -> void:
	for pressed: bool in [true, false]:
		var ev: InputEventKey = InputEventKey.new()
		ev.physical_keycode = code
		ev.keycode = code
		ev.pressed = pressed
		Input.parse_input_event(ev)
		await process_frame

func aim_at(world_point: Vector2) -> Vector2:
	var guess: Vector2 = world_point - player.position + Vector2(320, 180)
	var achieved: Vector2 = Vector2.ZERO
	for attempt: int in 4:
		var m: InputEventMouseMotion = InputEventMouseMotion.new()
		m.position = guess
		m.global_position = guess
		mouse_screen = guess
		Input.parse_input_event(m)
		await process_frame
		achieved = player.get_global_mouse_position()
		if achieved.distance_to(world_point) < 0.6:
			break
		guess += world_point - achieved
	return achieved

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
	await ticks(3)

func body(b: Boar) -> Vector2:
	return e.boar_body_center(b)

## A frozen boar next to some nest (uses the field's own spawn placement, then freezes it).
func make_boar(nest_index: int) -> Boar:
	for k: int in e.nests.size():
		var nest: Nest = e.nests[(nest_index + k) % e.nests.size()]
		if not nest.alive:
			continue
		if e._spawn(nest):
			var b: Boar = e.boars.back()
			b.wait = 100000000
			return b
	return null

func fertility_snapshot() -> PackedByteArray:
	return w.fertility.duplicate()

## Brute-force disk (written here from the spec: tile centres within 4 tiles of the spot).
func disk(pos: Vector2) -> Array[int]:
	var out: Array[int] = []
	var r: float = 4.0 * 4.0
	for y: int in range(0, w.height):
		if absf((y + 0.5) * 4.0 - pos.y) > r + 4.0:
			continue
		for x: int in range(0, w.width):
			if absf((x + 0.5) * 4.0 - pos.x) > r + 4.0:
				continue
			if Vector2((x + 0.5) * 4.0, (y + 0.5) * 4.0).distance_to(pos) <= r + 1.0e-6:
				out.append(y * w.width + x)
	return out

func shoot(point: Vector2, button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	await aim_at(point)
	await click(button)
	await ticks(roundi(0.6 * hz))

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
	main.enemy_tuning.boar_cap = 0   # no natural spawns while measuring
	var base_fert: PackedByteArray = fertility_snapshot()
	var world_base_dict: Dictionary = w.to_dict()
	play.seeds = 30
	var E: Dictionary = {}
	rec("wire", "real scene wires the hit provider and combat", pv.enemy_hit_provider.is_valid() and main.enemy_combat != null and e.nests.size() == 15, "nests=%d" % e.nests.size())

	# ---------------- 1. hits ----------------
	var b1: Boar = make_boar(0)
	await teleport(b1.pos + Vector2(-40, 0))
	var seeds0: int = play.seeds
	var land0: int = play.landing_counter
	await shoot(body(b1))
	rec("hit.seed1", "one seed shot takes exactly 1 HP from a boar (3 -> 2), costs 1 seed, no landing", b1.hp == 2 and play.seeds == seeds0 - 1 and play.landing_counter == land0 and pv.shots.is_empty(), "hp=%d seeds %d->%d landings %d->%d" % [b1.hp, seeds0, play.seeds, land0, play.landing_counter])
	# flash
	var t_hit: float = e.time
	var flash_end: float = -1.0
	var flash_started: bool = b1.flash_steps > 0 or true
	# the hit already happened during shoot(); measure remaining flash by a fresh hit
	await shoot(body(b1))
	rec("hit.seed2", "second shot: hp 1, still alive, still in field", b1.hp == 1 and e.boars.has(b1), "hp=%d" % b1.hp)
	var carc0: int = e.carcasses.size()
	# fire the lethal shot and watch the timeline from the kill
	await aim_at(body(b1))
	var seeds_before_kill: int = play.seeds
	await click(MOUSE_BUTTON_LEFT)
	var guard: int = 0
	while e.boars.has(b1) and guard < hz * 2:
		await physics_frame
		guard += 1
	var kill_time: float = e.time
	var kill_steps: int = e.steps_done
	var kill_pos: Vector2 = b1.pos
	rec("kill.boar3", "third seed shot kills the boar (exactly 3 hits), leaves 1 carcass", not e.boars.has(b1) and e.carcasses.size() == carc0 + 1 and e.total_killed >= 1, "carcasses=%d killed=%d" % [e.carcasses.size(), e.total_killed])
	var owner: int = GroundPickups.ENEMY_OWNER_BASE + b1.id
	var drop_n: int = play.pickups.count_owned(owner)
	rec("kill.drop2", "boar drops 2 seed fruits", drop_n == 2, "dropped=%d" % drop_n)
	await teleport(kill_pos)
	await ticks(10)
	var seeds_after: int = play.seeds
	rec("kill.collect", "walking over the fruit adds seeds (+2) and clears them", seeds_after == seeds_before_kill - 1 + 2 and play.pickups.count_owned(owner) == 0, "seeds %d -> %d (kill shot spent 1)" % [seeds_before_kill, seeds_after])

	# ---------------- water passes, plant shot stopped ----------------
	var b2: Boar = make_boar(3)
	await teleport(b2.pos + Vector2(-40, 0))
	var water0: float = play.water
	var hits0: int = main.enemy_combat.hits
	var landw0: int = play.last_wet_count
	await shoot(body(b2), MOUSE_BUTTON_RIGHT)
	rec("hit.water", "water shot passes through a boar (hp 3, no enemy hit, water spent)", b2.hp == 3 and main.enemy_combat.hits == hits0 and play.water < water0, "hp=%d hits %d->%d water %.1f->%.1f" % [b2.hp, hits0, main.enemy_combat.hits, water0, play.water])
	# plant shot
	var plant_idx: int = -1
	for i: int in play.selectable.size():
		if play.selectable[i].is_cultivated():
			plant_idx = i
			break
	if plant_idx < 0:
		rec("hit.plant", "cultivated shot is stopped with 0 damage", false, "no cultivated plant selectable (NOT_RUN)")
		results[results.size() - 1]["status"] = "NOT_RUN"
	else:
		play.select_index(plant_idx)
		play.seeds = 30
		var s_before: int = play.seeds
		var res_before: int = play.reserved_seeds
		var land_p: int = play.plant_landings
		await shoot(body(b2))
		await ticks(5)
		rec("hit.plant", "cultivated plant shot is stopped by the boar: hp unchanged, no planting, held seeds back", b2.hp == 3 and play.plant_landings == land_p and play.reserved_seeds == res_before and play.seeds == s_before and pv.shots.is_empty(), "key=%s hp=%d seeds %d->%d reserved=%d plant_landings %d->%d" % [play.selected_def().key, b2.hp, s_before, play.seeds, play.reserved_seeds, land_p, play.plant_landings])
		play.select_index(0)
	play.seeds = 30

	# ---------------- first target only ----------------
	var near_b: Boar = make_boar(5)
	var far_b: Boar = make_boar(5)
	if near_b != null and far_b != null:
		# line them up on one row in front of the player: place by hand
		var row_y: float = near_b.pos.y
		far_b.pos = near_b.pos + Vector2(24, 0)
		far_b.hp = 3
		await teleport(near_b.pos + Vector2(-40, 0))
		await shoot(body(far_b))
		rec("hit.first", "two boars in a row: only the first one is hit", near_b.hp == 2 and far_b.hp == 3, "near=%d far=%d" % [near_b.hp, far_b.hp])
		e.remove_boar(near_b)
		e.remove_boar(far_b)
	e.remove_boar(b2)

	# ---------------- 3. carcass: fertility disk, growth, timeline ----------------
	var idxs: Array[int] = disk(kill_pos)
	var after_kill: PackedByteArray = fertility_snapshot()
	# Note: the kill already happened; reconstruct "before" from base_fert (nothing else touches fertility)
	var disk_ok: bool = true
	var diff_count: int = 0
	var in_set: Dictionary = {}
	for i: int in idxs:
		in_set[i] = true
	for i: int in w.tile_count():
		var expect: int = int(base_fert[i]) + (40 if in_set.has(i) else 0)
		if int(after_kill[i]) != expect:
			disk_ok = false
		if after_kill[i] != base_fert[i]:
			diff_count += 1
	rec("carcass.disk", "carcass adds +40 on exactly the tiles within 4 tiles (brute force), nothing elsewhere", disk_ok and diff_count == idxs.size(), "disk tiles=%d changed=%d" % [idxs.size(), diff_count])
	obs["disk_tiles"] = idxs.size()

	# growth: tile inside vs outside (same moisture), both seed stage
	var in_tile: int = -1
	var out_tile: int = -1
	for i: int in idxs:
		var p: Vector2 = Vector2((i % w.width + 0.5) * 4.0, (i / w.width + 0.5) * 4.0)
		if p.distance_to(kill_pos) < 10.0 and w.target[i] == 1 and w.can_plant(i):
			in_tile = i
			break
	for y: int in range(w.height):
		pass
	var out_candidates: Array[int] = []
	for dx: int in range(-14, 15):
		for dy: int in range(-14, 15):
			var xx: int = floori(kill_pos.x / 4.0) + dx
			var yy: int = floori(kill_pos.y / 4.0) + dy
			if not w.in_bounds(xx, yy):
				continue
			var i2: int = yy * w.width + xx
			var p2: Vector2 = Vector2((xx + 0.5) * 4.0, (yy + 0.5) * 4.0)
			if p2.distance_to(kill_pos) > 24.0 and p2.distance_to(kill_pos) < 56.0 and w.target[i2] == 1 and w.can_plant(i2) and not in_set.has(i2):
				out_candidates.append(i2)
	if not out_candidates.is_empty():
		out_tile = out_candidates[0]
	if in_tile >= 0 and out_tile >= 0:
		w.set_stage(in_tile, WorldState.STAGE_SEED)
		w.set_stage(out_tile, WorldState.STAGE_SEED)
		w.set_moisture(in_tile, 100)
		w.set_moisture(out_tile, 100)
		var g_in0: int = w.growth[in_tile]
		var g_out0: int = w.growth[out_tile]
		var f_in: int = int(w.fertility[in_tile])
		var f_out: int = int(w.fertility[out_tile])
		await ticks(roundi(6.0 * hz))
		var d_in: int = int(w.growth[in_tile]) - g_in0
		var d_out: int = int(w.growth[out_tile]) - g_out0
		var exp_ratio: float = (1.0 + 0.5 * minf(float(f_in), 100.0) / 100.0) / (1.0 + 0.5 * minf(float(f_out), 100.0) / 100.0)
		var ratio: float = float(d_in) / maxf(float(d_out), 1.0)
		rec("carcass.growth", "tile in disk grows faster by 1+0.5*f/100 ratio (6 s, same moisture)", d_out > 0 and absf(ratio - exp_ratio) < 0.03 and ratio > 1.1, "growth in=%d out=%d ratio=%.3f expected %.3f (fert in=%d out=%d)" % [d_in, d_out, ratio, exp_ratio, f_in, f_out])
		w.set_stage(in_tile, WorldState.STAGE_EMPTY)
		w.set_stage(out_tile, WorldState.STAGE_EMPTY)
	else:
		rec("carcass.growth", "growth in/out", false, "no suitable tiles in=%d out=%d" % [in_tile, out_tile])
		results[results.size() - 1]["status"] = "NOT_RUN"

	# pause freeze (corpse active)
	var c: Carcass = e.carcasses.back()
	var age_a: int = c.age_steps
	var t_a: float = e.time
	await key_tap(KEY_ESCAPE)
	await ticks(2)
	var was_paused: bool = paused
	var age_p: int = c.age_steps
	await ticks(roundi(20.0 * hz))
	rec("pause.freeze", "Esc: 20 s paused leaves carcass age unchanged", was_paused and c.age_steps == age_p, "paused=%s age %d -> %d" % [was_paused, age_p, c.age_steps])
	await key_tap(KEY_ESCAPE)
	await ticks(2)
	var t_r: float = e.time
	var age_r: int = c.age_steps
	await ticks(roundi(1.0 * hz))
	var d_age: int = c.age_steps - age_r
	rec("pause.nobank", "after resume ~1 s of game time passes, no lump sum (age +60 +-6 steps)", not paused and absi(d_age - 60) <= 6, "age +%d steps in 1 s" % d_age)

	# timeline: poll every frame
	var bone_steps: int = -1
	var gone_steps: int = -1
	var fert_center: int = w.index_of(floori(kill_pos.x / 4.0), floori(kill_pos.y / 4.0))
	var f_corpse: int = int(w.fertility[fert_center]) - int(base_fert[fert_center])
	var f_bone: int = -999
	var f_gone: int = -999
	var frames: int = 0
	while frames < hz * 130 and gone_steps < 0:
		await physics_frame
		frames += 1
		if not e.carcasses.has(c):
			gone_steps = e.steps_done
			f_gone = int(w.fertility[fert_center]) - int(base_fert[fert_center])
		elif c.stage == Carcass.STAGE_BONE and bone_steps < 0:
			bone_steps = e.steps_done
			f_bone = int(w.fertility[fert_center]) - int(base_fert[fert_center])
	var bone_after: float = float(bone_steps - kill_steps) / 60.0
	var gone_after: float = float(gone_steps - kill_steps) / 60.0
	rec("timeline.bone", "corpse turns to bone 60 s after the kill (+-0.1 s), fertility +40 -> +20", f_corpse == 40 and absf(bone_after - 60.0) <= 0.1 and f_bone == 20, "bone at %.3f s, fert %d -> %d" % [bone_after, f_corpse, f_bone])
	rec("timeline.gone", "bone vanishes 100 s after the kill (+-0.1 s) and fertility returns to the original", absf(gone_after - 100.0) <= 0.1 and f_gone == 0 and fertility_snapshot() == base_fert, "gone at %.3f s, delta %d, whole map equal=%s" % [gone_after, f_gone, str(fertility_snapshot() == base_fert)])
	obs["bone_after_s"] = bone_after
	obs["gone_after_s"] = gone_after
	obs["kill_steps"] = kill_steps

	# flash: a non-lethal hit flashes ~0.25 s
	var bf: Boar = make_boar(7)
	await teleport(bf.pos + Vector2(-40, 0))
	await aim_at(body(bf))
	await click(MOUSE_BUTTON_LEFT)
	var fg: int = 0
	while bf.hp == 3 and fg < hz:
		await physics_frame
		fg += 1
	var fl0: float = e.time
	var fl_steps0: int = e.steps_done
	var started: bool = bf.flash_steps > 0
	fg = 0
	while bf.flash_steps > 0 and fg < hz * 2:
		await physics_frame
		fg += 1
	var flash_len: float = float(e.steps_done - fl_steps0) / 60.0
	rec("flash", "non-lethal hit flashes for 0.25 s (+-0.07)", started and absf(flash_len - 0.25) <= 0.07, "flash length %.3f s (measured from hp drop)" % flash_len)
	obs["flash_len"] = flash_len
	e.remove_boar(bf)

	# ---------------- shared fruit slots ----------------
	var pk: GroundPickups = play.pickups
	pk.items.clear()
	var cap_plant: int = pk.plant_cap
	var total_cap: int = pk.total_cap
	var reserved_expected: int = play.sources.size() * 3
	rec("slots.reservation_math", "plant limit leaves the sources' reserved slots: plant_cap + sources*3 <= total", cap_plant + reserved_expected <= total_cap and cap_plant >= 0, "plant_cap=%d sources=%d total=%d" % [cap_plant, play.sources.size(), total_cap])
	var fill_to: int = cap_plant - 1
	for i: int in fill_to:
		pk.spawn(GroundPickups.KIND_SEED_FRUIT, Vector2(8000 + i, 8000), GroundPickups.PLANT_OWNER_BASE + 1 + i)
	var b3: Boar = make_boar(9)
	var dropped_before: int = main.enemy_combat.fruits_dropped
	e.damage_boar(b3, 3)
	var got1: int = pk.count_owned(GroundPickups.ENEMY_OWNER_BASE + b3.id)
	fact("slots.near_cap", "plant-owned fruits at cap-1 (%d): boar reward = %d of 2" % [fill_to, got1])
	var b4: Boar = make_boar(9)
	e.damage_boar(b4, 3)
	var got0: int = pk.count_owned(GroundPickups.ENEMY_OWNER_BASE + b4.id)
	fact("slots.at_cap", "plant-owned fruits at cap (%d): boar reward = %d of 2; boar still dies=%s" % [pk.count_plant_owned(), got0, str(not e.boars.has(b4))])
	rec("slots.never_over", "plant-owned fruits never exceed plant_cap; boar dies anyway", pk.count_plant_owned() <= cap_plant and not e.boars.has(b4), "plant-owned=%d cap=%d" % [pk.count_plant_owned(), cap_plant])
	var src_ok: bool = pk.spawn(GroundPickups.KIND_SEED_FRUIT, Vector2(8100, 8100), 1)
	rec("slots.sources_keep_room", "with plant-owned at cap a seed source can still drop a fruit (reservation kept)", src_ok and pk.count_seed_items() <= total_cap, "source spawn accepted=%s items=%d/%d" % [str(src_ok), pk.count_seed_items(), total_cap])
	pk.items.clear()
	# clear carcasses of this section
	for k: int in range(e.carcasses.size() - 1, -1, -1):
		e._remove_carcass(e.carcasses[k])

	# ---------------- cap 24 & overlap ----------------
	var pre_cap: PackedByteArray = fertility_snapshot()
	var start_pos: Vector2 = e.nests[0].center_px(4) + Vector2(0, 80)
	var ids: Array[int] = []
	var positions: Array[Vector2] = []
	for k: int in 25:
		var bb: Boar = Boar.new()
		bb.id = 9000 + k
		bb.nest_id = e.nests[0].id
		bb.zone = e.nests[0].zone
		bb.hp = 1
		bb.pos = Vector2(40.0 + 36.0 * float(k % 12), 40.0 + 36.0 * float(k / 12) * 2.0)
		bb.wait = 100000000
		e.boars.append(bb)
		positions.append(bb.pos)
		var before_id: int = e.next_carcass_id
		play.pickups.items.clear()
		e.damage_boar(bb, 1)
		ids.append(before_id)
	var oldest_gone: bool = true
	for cc: Carcass in e.carcasses:
		if cc.id == ids[0]:
			oldest_gone = false
	var expect_arr: PackedByteArray = pre_cap.duplicate()
	for k: int in range(1, 25):
		for i: int in disk(positions[k]):
			expect_arr[i] = expect_arr[i] + 40
	rec("cap.24", "25 kills leave 24 carcasses; the oldest vanished; fertility = exactly the other 24 disks", e.carcasses.size() == 24 and oldest_gone and fertility_snapshot() == expect_arr, "carcasses=%d oldest_gone=%s array_equal=%s" % [e.carcasses.size(), str(oldest_gone), str(fertility_snapshot() == expect_arr)])
	for k: int in range(e.carcasses.size() - 1, -1, -1):
		e._remove_carcass(e.carcasses[k])
	rec("cap.restore", "removing all returns fertility to the original", fertility_snapshot() == pre_cap, "equal=%s" % str(fertility_snapshot() == pre_cap))
	# overlap
	var spot: Vector2 = Vector2(600.5, 300.5)
	var ct: int = w.index_of(floori(spot.x / 4.0), floori(spot.y / 4.0))
	var f0: int = int(w.fertility[ct])
	var seq: Array[int] = []
	for k: int in 3:
		var bo: Boar = Boar.new()
		bo.id = 9100 + k
		bo.nest_id = e.nests[0].id
		bo.hp = 1
		bo.pos = spot
		e.boars.append(bo)
		e.damage_boar(bo, 1)
		seq.append(int(w.fertility[ct]) - f0)
	rec("cap.overlap", "overlapping carcasses add up but cap at +60: 40, 60, 60", seq == [40, 60, 60], str(seq))
	for k: int in range(e.carcasses.size() - 1, -1, -1):
		e._remove_carcass(e.carcasses[k])
	play.pickups.items.clear()
	rec("cap.overlap_restore", "after the overlap goes, fertility is back", fertility_snapshot() == pre_cap, "equal=%s" % str(fertility_snapshot() == pre_cap))

	# ---------------- save round trip ----------------
	var sb: Boar = make_boar(2)
	e.damage_boar(sb, 3)
	var sb2: Boar = make_boar(4)
	e.damage_boar(sb2, 3)
	e.advance(5.0)   # ages in the saved data
	var edata: Dictionary = JSON.parse_string(JSON.stringify(e.to_dict()))
	var wdata: Dictionary = JSON.parse_string(JSON.stringify(w.to_dict()))
	var w2: WorldState = WorldState.from_dict(wdata, w.terrain_defs)
	var e2: EnemyField = EnemyField.new(w2, main.enemy_tuning, 4)
	var ok_true: bool = e2.load_dict(edata, true)
	var same: bool = ok_true and e2.carcasses.size() == e.carcasses.size() and w2.fertility == w.fertility
	for k: int in e.carcasses.size():
		if same and (e2.carcasses[k].age_steps != e.carcasses[k].age_steps or e2.carcasses[k].stage != e.carcasses[k].stage or e2.carcasses[k].pos != e.carcasses[k].pos):
			same = false
	rec("save.with_layer", "load_dict(data, true) on a world restored from the same save reproduces carcasses", same, "ok=%s n=%d" % [str(ok_true), e2.carcasses.size()])
	var w3: WorldState = WorldState.from_dict(JSON.parse_string(JSON.stringify(world_base_dict)), w.terrain_defs)
	var e3: EnemyField = EnemyField.new(w3, main.enemy_tuning, 4)
	var refuse: bool = not EnemyField.new(WorldState.from_dict(JSON.parse_string(JSON.stringify(world_base_dict)), w.terrain_defs), main.enemy_tuning, 4).load_dict(edata, true)
	var ok_false: bool = e3.load_dict(edata, false)
	rec("save.without_layer", "load_dict(data,false) on a fresh world adds the layer (== live world); load_dict(data,true) on a world without layer is refused", ok_false and w3.fertility == w.fertility and refuse, "ok=%s equal=%s refused_true_on_bare_world=%s" % [str(ok_false), str(w3.fertility == w.fertility), str(refuse)])
	# continue both for 120 s: same end (everything vanishes, fertility back to base)
	e.advance(0.0)
	var ages_before: Array[int] = []
	for cc2: Carcass in e2.carcasses:
		ages_before.append(cc2.age_steps)
	for i: int in 480:
		e.advance(0.25)
		e2.advance(0.25)
		e3.advance(0.25)
	rec("save.continue", "restored fields keep aging identically and fertility returns to base", e.carcasses.is_empty() and e2.carcasses.is_empty() and e3.carcasses.is_empty() and w.fertility == base_fert and w2.fertility == base_fert and w3.fertility == base_fert, "e=%d e2=%d e3=%d" % [e.carcasses.size(), e2.carcasses.size(), e3.carcasses.size()])

	# ---------------- nest ----------------
	main.enemy_tuning.boar_cap = 0
	var nest: Nest = e.nests[1]
	var nest_center: Vector2 = nest.center_px(4)
	var tiles_blocked: bool = true
	var tiles: Array[int] = []
	for y: int in range(nest.tile.y, nest.tile.y + nest.size):
		for x: int in range(nest.tile.x, nest.tile.x + nest.size):
			tiles.append(w.index_of(x, y))
	for i: int in tiles:
		if w.can_plant(i):
			tiles_blocked = false
	play.seeds = 40
	await teleport(nest_center + Vector2(-36, 0))
	await aim_at(nest_center)
	var hp_trace: Array[int] = []
	var landN0: int = play.landing_counter
	for k: int in 19:
		await click(MOUSE_BUTTON_LEFT)
		await ticks(roundi(0.3 * hz))
	await ticks(roundi(0.6 * hz))
	var hp19: int = nest.hp
	var alive19: bool = nest.alive
	await click(MOUSE_BUTTON_LEFT)
	await ticks(roundi(0.8 * hz))
	var seedsN: int = play.seeds
	rec("nest.20hits", "19 seed hits leave the nest alive (hp 1); the 20th destroys it; hit shots never land", alive19 and hp19 == 1 and not nest.alive and nest.hp == 0 and play.landing_counter == landN0, "hp after 19 = %d alive=%s; after 20 alive=%s; landings %d->%d; seeds left %d" % [hp19, str(alive19), str(nest.alive), landN0, play.landing_counter, seedsN])
	var nown: int = play.pickups.count_owned(GroundPickups.ENEMY_OWNER_BASE + 1000000 + nest.id)
	rec("nest.drop4", "nest drops 4 seed fruits", nown == 4, "dropped=%d" % nown)
	var free_after: bool = true
	for i: int in tiles:
		if w.occupant[i] != 0:
			free_after = false
	rec("nest.release", "destroyed nest releases its tiles (before: not plantable; after: occupant 0)", tiles_blocked and free_after, "blocked_before=%s free_after=%s" % [str(tiles_blocked), str(free_after)])
	var stage_before: int = 0
	for i: int in tiles:
		stage_before += w.stage[i]
	for k: int in 6:
		play.land_seed(nest_center)
	var planted: int = 0
	for i: int in tiles:
		if w.stage[i] != 0:
			planted += 1
	rec("nest.plantable", "seeds landing on the cleared nest ground can be planted", planted > 0, "planted tiles=%d (before sum %d)" % [planted, stage_before])
	# spawning stops
	var spawned_before: int = nest.spawned
	main.enemy_tuning.boar_cap = 40
	var total_before: int = e.total_spawned
	await ticks(roundi(40.0 * hz))
	var from_dead: int = 0
	for bo2: Boar in e.boars:
		if bo2.nest_id == nest.id:
			from_dead += 1
	rec("nest.no_spawn", "destroyed nest stops spawning (40 s, others keep spawning as control)", nest.spawned == spawned_before and e.total_spawned > total_before, "nest.spawned %d->%d, others total %d->%d" % [spawned_before, nest.spawned, total_before, e.total_spawned])
	main.enemy_tuning.boar_cap = 0

	# ---------------- output ----------------
	var f: FileAccess = FileAccess.open("res://evidence/p2/p2-02/independent/checks_scene_%d.json" % hz, FileAccess.WRITE)
	f.store_string(JSON.stringify({"hz": hz, "observations": obs, "results": results}, "  "))
	f.close()
	var fails: int = 0
	for r: Dictionary in results:
		if r["status"] == "FAIL":
			fails += 1
	print("RESULT scene hz=%d checks=%d failures=%d" % [hz, results.size(), fails])
	quit(1 if fails > 0 else 0)
