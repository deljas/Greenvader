extends SceneTree
## Independent verifier for P1-05, scene level (real main.tscn, engine-internal input injection only; headless).
## Run: Godot --headless --fixed-fps 60 --path <project> --script res://tests/p1/independent/p1_05_v_scene.gd -- --only=input|pause|rate [--hz=N]

const OUT: String = "res://evidence/p1/p1-05/independent/"
const TILE: int = 4

var results: Array[Dictionary] = []
var main: Node
var observations: Dictionary = {}
var keys_down: Dictionary = {}
var landed_n: int = 0

func _initialize() -> void:
	run.call_deferred()

func rec(id: String, cond: String, ok: bool, observed: String) -> void:
	results.append({"id": id, "condition": cond, "status": "PASS" if ok else "FAIL", "observed": observed})
	print("%s [%s] %s :: %s" % ["PASS" if ok else "FAIL", id, cond, observed])

func run() -> void:
	var only: String = "input"
	var hz: int = 60
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.trim_prefix("--only=")
		elif a.begins_with("--hz="):
			hz = int(a.trim_prefix("--hz="))
	Engine.physics_ticks_per_second = hz
	match only:
		"input":
			await t_input()
		"pause":
			await t_pause()
		"rate":
			await t_rate(hz)
	var f: FileAccess = FileAccess.open(OUT + "checks_scene_%s%s.json" % [only, "_%d" % hz if only == "rate" else ""], FileAccess.WRITE)
	f.store_string(JSON.stringify({"results": results, "observations": observations}, "  "))
	f.close()
	var fails: int = 0
	for r: Dictionary in results:
		if r["status"] != "PASS":
			fails += 1
	print("V_RESULT total=%d fails=%d" % [results.size(), fails])
	quit(1 if fails > 0 else 0)

# ------------------------------------------------------------------------------------------ helpers

func new_main() -> Node:
	if main != null:
		main.queue_free()
		await process_frame
	paused = false
	keys_down.clear()
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	landed_n = 0
	main.projectile_view.landed.connect(func(_k: String, _p: Vector2) -> void: landed_n += 1)
	return main

func ticks(n: int) -> void:
	for i: int in n:
		await physics_frame

func drain_shots(limit: int = 600) -> void:
	var n: int = 0
	while not main.projectile_view.shots.is_empty() and n < limit:
		await physics_frame
		n += 1

func key_tap(code: Key) -> void:
	var d: InputEventKey = InputEventKey.new()
	d.physical_keycode = code
	d.keycode = code
	d.pressed = true
	Input.parse_input_event(d)
	var u: InputEventKey = InputEventKey.new()
	u.physical_keycode = code
	u.keycode = code
	u.pressed = false
	Input.parse_input_event(u)

func wheel_tap(button: MouseButton) -> void:
	var d: InputEventMouseButton = InputEventMouseButton.new()
	d.button_index = button
	d.pressed = true
	d.position = Vector2(200, 100)
	d.global_position = d.position
	Input.parse_input_event(d)
	var u: InputEventMouseButton = InputEventMouseButton.new()
	u.button_index = button
	u.pressed = false
	u.position = d.position
	u.global_position = d.position
	Input.parse_input_event(u)

func screen_of(world_pos: Vector2) -> Vector2:
	return main.get_viewport().get_canvas_transform() * world_pos

func click_at(world_pos: Vector2) -> void:
	var m: InputEventMouseMotion = InputEventMouseMotion.new()
	m.position = screen_of(world_pos)
	m.global_position = m.position
	Input.parse_input_event(m)
	var d: InputEventMouseButton = InputEventMouseButton.new()
	d.button_index = MOUSE_BUTTON_LEFT
	d.pressed = true
	d.position = m.position
	d.global_position = m.position
	Input.parse_input_event(d)
	var u: InputEventMouseButton = InputEventMouseButton.new()
	u.button_index = MOUSE_BUTTON_LEFT
	u.pressed = false
	u.position = m.position
	u.global_position = m.position
	Input.parse_input_event(u)

func click_wait(world_pos: Vector2) -> void:
	click_at(world_pos)
	await process_frame
	await process_frame

func tap_escape() -> void:
	key_tap(KEY_ESCAPE)

func settle() -> void:
	await process_frame
	await process_frame

func square_all(world: WorldState, cx: int, cy: int, half: int, terrain_id: int) -> bool:
	if cx - half < 0 or cy - half < 0 or cx + half >= world.width or cy + half >= world.height:
		return false
	for y: int in range(cy - half, cy + half + 1):
		for x: int in range(cx - half, cx + half + 1):
			if world.terrain[y * world.width + x] != terrain_id or world.stage[y * world.width + x] != 0:
				return false
	return true

func find_square(world: WorldState, terrain_id: int, half: int, near: Vector2i) -> Vector2i:
	var best: Vector2i = Vector2i(-1, -1)
	var best_d: int = 1 << 60
	for cy: int in range(half, world.height - half, 2):
		for cx: int in range(half, world.width - half, 2):
			var d: int = (cx - near.x) * (cx - near.x) + (cy - near.y) * (cy - near.y)
			if d >= best_d:
				continue
			if square_all(world, cx, cy, half, terrain_id):
				best = Vector2i(cx, cy)
				best_d = d
	return best

func center_of(t: Vector2i) -> Vector2:
	return (Vector2(t) + Vector2(0.5, 0.5)) * TILE

func place_player(p: Vector2) -> void:
	main.player.simulation_position = p
	main.player.position = p.round()
	await settle()

## Mature 10x10 block at origin `o`; returns its centre in px.
func make_block(o: Vector2i) -> Vector2:
	var world: WorldState = main.grid
	world.debug_fill_stage(Rect2i(o.x, o.y, 10, 10), 4)
	return (Vector2(o) + Vector2(5, 5)) * TILE

func hud_plant_text() -> String:
	return main.hud.plant_label.text

# ------------------------------------------------------------------------------------------ input

func t_input() -> void:
	await new_main()
	var play: PlayState = main.play
	var world: WorldState = main.grid
	await settle()
	rec("input.hud_initial", "HUD shows the selection line with the ordinary plant in brackets, and HP 10/10", hud_plant_text() == "植物 [通常] にんじん キウイ" and main.hud.hp_label.text == "HP 10/10", "plant='%s' hp='%s'" % [hud_plant_text(), main.hud.hp_label.text])
	# Tab cycle
	var seq: Array[int] = []
	var texts: Array[String] = []
	for i: int in 4:
		key_tap(KEY_TAB)
		await settle()
		seq.append(play.selected_index)
		texts.append(hud_plant_text())
	rec("input.tab_cycle", "Tab (injected) cycles 1,2,0,1 and the HUD follows each time", seq == [1, 2, 0, 1] and texts[0] == "植物 通常 [にんじん:3] キウイ" and texts[1] == "植物 通常 にんじん [キウイ:3]" and texts[2] == "植物 [通常] にんじん キウイ", "seq=%s texts=%s" % [str(seq), str(texts)])
	play.select_index(0)
	await settle()
	var seq_d: Array[int] = []
	for i: int in 4:
		wheel_tap(MOUSE_BUTTON_WHEEL_DOWN)
		await settle()
		seq_d.append(play.selected_index)
	rec("input.wheel_down", "wheel down (injected) behaves like Tab: 1,2,0,1", seq_d == [1, 2, 0, 1], "seq=%s" % str(seq_d))
	play.select_index(0)
	await settle()
	var seq_u: Array[int] = []
	var text_u: Array[String] = []
	for i: int in 4:
		wheel_tap(MOUSE_BUTTON_WHEEL_UP)
		await settle()
		seq_u.append(play.selected_index)
		text_u.append(hud_plant_text())
	rec("input.wheel_up", "wheel up goes the other way: 2,1,0,2, HUD follows", seq_u == [2, 1, 0, 2] and text_u[0] == "植物 通常 にんじん [キウイ:3]" and text_u[1] == "植物 通常 [にんじん:3] キウイ", "seq=%s texts=%s" % [str(seq_u), str(text_u)])
	rec("input.no_shot_from_wheel_tab", "selection input alone never fires or spends anything", main.projectile_view.shots.is_empty() and play.seeds == 20 and play.reserved_seeds == 0, "shots=%d seeds=%d" % [main.projectile_view.shots.size(), play.seeds])
	# Tab does not also trigger focus change / button press (weather buttons focus)
	rec("input.tab_no_focus_steal", "Tab leaves no focused control (UI focus is not used)", main.get_viewport().gui_get_focus_owner() == null, "focus=%s" % str(main.get_viewport().gui_get_focus_owner()))
	# HP HUD
	play.damage_player(4)
	await settle()
	var gauge_frac: float = main.hud.hp_gauge.fraction
	rec("input.hp_hud", "HP HUD shows 6/10 after 4 damage and the gauge fraction 0.6", main.hud.hp_label.text == "HP 6/10" and absf(gauge_frac - 0.6) < 1e-6, "text='%s' fraction=%f" % [main.hud.hp_label.text, gauge_frac])
	play.damage_player(3)
	await settle()
	rec("input.hp_hud_low", "HP 3/10 is shown and flagged low", main.hud.hp_label.text == "HP 3/10" and main.hud.hp_gauge.low, "text='%s' low=%s" % [main.hud.hp_label.text, main.hud.hp_gauge.low])
	play.heal_player(100)
	await settle()
	rec("input.hp_hud_full", "HP back to 10/10", main.hud.hp_label.text == "HP 10/10" and not main.hud.hp_gauge.low, "text='%s'" % main.hud.hp_label.text)
	# set up a mature block and plant through clicks
	var site: Vector2i = find_square(world, 0, 20, main.region_def.start_tile + Vector2i(60, 0))
	var origin: Vector2i = site + Vector2i(-5, -5)
	var center_px: Vector2 = make_block(origin)
	var player_px: Vector2 = center_px + Vector2(-70, 0)
	await place_player(player_px)
	main.projectile_view.shots.clear()
	play.select_index(1)
	await settle()
	var seeds0: int = play.seeds
	var plants0: int = play.cultivation.plants.size()
	var ground_before: int = world.greened_count
	await click_wait(center_px)
	var in_flight: bool = main.projectile_view.shots.size() == 1
	var reserved_mid: int = play.reserved_seeds
	var avail_mid: int = play.available_seeds()
	var seeds_mid: int = play.seeds
	await settle()
	var hud_seed_mid: String = main.hud.seed_label.text
	await drain_shots()
	await settle()
	rec("input.carrot_in_flight", "click with the carrot selected fires one shot; its cost is held back (HUD shows the lower amount) but not yet spent", in_flight and reserved_mid == 3 and seeds_mid == seeds0 and avail_mid == seeds0 - 3 and hud_seed_mid.contains("%d/" % (seeds0 - 3)), "in_flight=%s reserved=%d seeds=%d avail=%d hud='%s'" % [in_flight, reserved_mid, seeds_mid, avail_mid, hud_seed_mid])
	var planted: CultivatedPlant = play.last_plant
	rec("input.carrot_planted", "after landing, a carrot stands on the mature block (2x2 inside it), cost spent once, nothing reserved", planted != null and play.cultivation.plants.size() == plants0 + 1 and Rect2i(origin, Vector2i(10, 10)).encloses(planted.rect()) and play.seeds == seeds0 - 3 and play.reserved_seeds == 0 and main.hud.seed_label.text.contains("%d/" % (seeds0 - 3)), "plant=%s seeds=%d reserved=%d hud='%s'" % [str(planted.tile) if planted != null else "null", play.seeds, play.reserved_seeds, main.hud.seed_label.text])
	rec("input.greened_unchanged_by_plant", "the planted footprint does not change the greened count", world.greened_count >= ground_before and world.counters_consistent(), "greened %d -> %d" % [ground_before, world.greened_count])
	# failure: shoot at empty ground
	var seeds1: int = play.seeds
	var fail0: int = play.plant_failures
	var empty_target: Vector2 = player_px + Vector2(0, 80)
	await click_wait(empty_target)
	await drain_shots()
	await settle()
	rec("input.fail_returns_cost", "a carrot that lands on non-mature ground plants nothing and the seeds come back (none spent)", play.plant_failures == fail0 + 1 and play.seeds == seeds1 and play.reserved_seeds == 0 and play.available_seeds() == seeds1 and play.cultivation.plants.size() == plants0 + 1, "failures=%d seeds=%d reserved=%d" % [play.plant_failures, play.seeds, play.reserved_seeds])
	# kiwi through wheel + click
	wheel_tap(MOUSE_BUTTON_WHEEL_DOWN)
	await settle()
	rec("input.wheel_selects_kiwi", "wheel down from carrot selects kiwi", play.selected_def().key == &"kiwi", "sel=%s" % str(play.selected_def().key))
	var kiwi_aim: Vector2 = center_px + Vector2(16, 0)
	await click_wait(kiwi_aim)
	await drain_shots()
	await settle()
	var kiwi_plant: CultivatedPlant = play.last_plant
	rec("input.kiwi_planted", "click with the kiwi selected plants a kiwi (non-overlapping with the carrot) and spends its cost", kiwi_plant != null and kiwi_plant.key == &"kiwi" and play.cultivation.plants.size() == plants0 + 2 and not kiwi_plant.rect().intersects(planted.rect()) and play.seeds == seeds1 - 3, "kiwi=%s seeds=%d" % [str(kiwi_plant.tile) if kiwi_plant != null else "null", play.seeds])
	# the ordinary seed still works and is not a cultivated shot
	play.select_index(0)
	await settle()
	var seeds_n: int = play.seeds
	var plants_n: int = play.cultivation.plants.size()
	await click_wait(player_px + Vector2(0, 40))
	await drain_shots()
	await settle()
	rec("input.normal_seed_unchanged", "with the ordinary plant selected a click spends exactly 1 seed and plants no cultivated plant", play.seeds == seeds_n - 1 and play.cultivation.plants.size() == plants_n, "seeds %d->%d" % [seeds_n, play.seeds])
	# not enough seeds
	play.select_index(1)
	play.seeds = 2
	await settle()
	var shots_before: int = landed_n
	await click_wait(center_px)
	await ticks(3)
	rec("input.not_enough_seeds", "with 2 seeds (< cost 3) the carrot click fires nothing", main.projectile_view.shots.is_empty() and landed_n == shots_before and play.seeds == 2 and play.reserved_seeds == 0, "shots=%d seeds=%d" % [main.projectile_view.shots.size(), play.seeds])
	# expiry in the air returns the cost
	play.seeds = 20
	var old_age: float = main.play_tuning.projectile_max_age
	main.play_tuning.projectile_max_age = 0.001
	var expired_n: Array[int] = [0]
	main.projectile_view.expired.connect(func(_k: String, _p: Vector2) -> void: expired_n[0] += 1)
	await click_wait(player_px + Vector2(100, 0))
	await ticks(4)
	main.play_tuning.projectile_max_age = old_age
	await drain_shots()
	await settle()
	rec("input.expiry_returns_cost", "a cultivated shot that expires in the air gives the cost back; nothing planted", expired_n[0] == 1 and play.seeds == 20 and play.reserved_seeds == 0 and play.inflight.get(&"carrot", 0) == 0 and play.cultivation.plants.size() == plants_n, "expired signals=%d seeds=%d reserved=%d inflight=%s plants=%d" % [expired_n[0], play.seeds, play.reserved_seeds, str(play.inflight), play.cultivation.plants.size()])
	# enemy hit returns the cost
	main.projectile_view.enemy_hit_provider = func(_shot: Dictionary, _from: Vector2, to: Vector2) -> Dictionary: return {"point": to}
	var hit_n: Array[int] = [0]
	main.projectile_view.enemy_hit.connect(func(_k: String, _p: Vector2, _i: Dictionary) -> void: hit_n[0] += 1)
	await click_wait(center_px)
	await ticks(4)
	main.projectile_view.enemy_hit_provider = Callable()
	await drain_shots()
	await settle()
	rec("input.hit_returns_cost", "a cultivated shot that hits an enemy gives the cost back; nothing planted", hit_n[0] == 1 and play.seeds == 20 and play.reserved_seeds == 0 and play.cultivation.plants.size() == plants_n, "hit signals=%d seeds=%d reserved=%d inflight=%s" % [hit_n[0], play.seeds, play.reserved_seeds, str(play.inflight)])
	# water shot is unaffected by selection
	play.select_index(1)
	var water0: float = play.water
	var seeds_w: int = play.seeds
	main.fire(true, player_px + Vector2(30, 0))
	await drain_shots()
	rec("input.water_unaffected", "a water shot with the carrot selected spends water only", play.water < water0 and play.seeds == seeds_w and play.reserved_seeds == 0, "water %f->%f seeds=%d" % [water0, play.water, play.seeds])
	# per-kind limit counts shots in flight (limit 1 temporarily)
	var def: PlantDef = play.def_by_key(&"carrot")
	var old_max: int = def.max_count
	def.max_count = play.cultivation.count(&"carrot") + 1
	play.seeds = 20
	play.select_index(1)
	var first: bool = main.fire(false, center_px + Vector2(24, 8))
	var second: bool = main.fire(false, center_px + Vector2(24, 8))
	var reserved_two: int = play.reserved_seeds
	await drain_shots()
	def.max_count = old_max
	rec("input.limit_inflight", "limit = planted+1: the first shot fires, the second is refused while the first is still in flight", first and not second and reserved_two == 3, "first=%s second=%s reserved=%d" % [first, second, reserved_two])
	# stray clicks while plants exist: selection restored to normal
	observations["final_plants"] = play.cultivation.plants.size()

# ------------------------------------------------------------------------------------------ pause

func snap_state() -> Dictionary:
	var play: PlayState = main.play
	var sim: SimulationDriver = main.simulation
	var plants: Array = []
	for p: CultivatedPlant in play.cultivation.plants:
		plants.append([p.uid, String(p.key), snappedf(p.age, 0.0001), p.mature, snappedf(p.timer, 0.0001), p.drops])
	var items: Array = []
	for it: Dictionary in play.pickups.items:
		items.append([String(it["kind"]), snappedf(float(it["age"]), 0.0001), int(it["owner"])])
	return {
		"plants": plants, "items": items, "hp": play.hp, "seeds": play.seeds, "elapsed": snappedf(play.elapsed, 0.0001),
		"clock": [snappedf(sim.clock.elapsed, 0.0001), sim.clock.growth_ticks, sim.clock.spread_ticks],
		"hash": "%d/%d/%d" % [hash(main.grid.stage), hash(main.grid.growth), hash(main.grid.natural)],
		"planted": sim.spread.total_planted, "boost_n": play.cultivation.boost.size(),
	}

func t_pause() -> void:
	await new_main()
	var play: PlayState = main.play
	var world: WorldState = main.grid
	var site: Vector2i = find_square(world, 0, 20, main.region_def.start_tile + Vector2i(60, 0))
	var origin: Vector2i = site + Vector2i(-5, -5)
	var center_px: Vector2 = make_block(origin)
	var far_player: Vector2 = center_px + Vector2(0, 90)
	await place_player(far_player)
	var k: CultivatedPlant = null
	var c: CultivatedPlant = null
	play.reserve_plant(play.def_by_key(&"kiwi"))
	k = play.land_plant(&"kiwi", center_px + Vector2(-16, 0))
	play.reserve_plant(play.def_by_key(&"carrot"))
	c = play.land_plant(&"carrot", center_px + Vector2(16, 0))
	rec("pause.setup", "a kiwi and a carrot stand on a mature block", k != null and c != null, "kiwi=%s carrot=%s" % [str(k.tile) if k != null else "null", str(c.tile) if c != null else "null"])
	if k == null or c == null:
		return
	k.age = 30.0
	c.age = 36.0
	await ticks(30)
	var before_pause: Dictionary = snap_state()
	rec("pause.running_before", "before pausing the plants age", float(before_pause["plants"][0][2]) > 30.3 and float(before_pause["plants"][1][2]) > 36.3 and not bool(before_pause["plants"][0][3]), "snap=%s" % str(before_pause["plants"]))
	tap_escape()
	await settle()
	var paused_now: bool = paused
	var s0: Dictionary = snap_state()
	# actions while paused: selection and clicks do nothing, HP does not change by time
	play.hp = 5
	play.pickups.spawn("heal_fruit", main.player.simulation_position, 2000000 + k.uid, 30.0)
	var sel0: int = play.selected_index
	key_tap(KEY_TAB)
	wheel_tap(MOUSE_BUTTON_WHEEL_DOWN)
	wheel_tap(MOUSE_BUTTON_WHEEL_UP)
	await click_wait(center_px)
	await settle()
	var fired: bool = main.fire(false, center_px)
	var s_a: Dictionary = snap_state()
	await create_timer(1.5, true).timeout
	var s1: Dictionary = snap_state()
	rec("pause.is_paused", "Escape (injected) pauses the tree", paused_now, "paused=%s" % paused_now)
	rec("pause.selection_inactive", "Tab / wheel / click / fire() do nothing while paused", play.selected_index == sel0 and not fired and main.projectile_view.shots.is_empty() and play.reserved_seeds == 0, "sel %d->%d fired=%s" % [sel0, play.selected_index, fired])
	var s_cmp0: Dictionary = s_a.duplicate(true)
	s_cmp0["items"] = s0["items"].duplicate()
	var same: bool = s1["plants"] == s0["plants"] and s1["clock"] == s0["clock"] and s1["hash"] == s0["hash"] and s1["planted"] == s0["planted"] and s1["elapsed"] == s0["elapsed"] and s1["boost_n"] == s0["boost_n"]
	rec("pause.frozen_state", "during a 1.5 s pause plants (age, timer, fruit timer, drops), the sim clock, spread and world do not change", same, "before=%s after=%s" % [str({"plants": s0["plants"], "clock": s0["clock"], "elapsed": s0["elapsed"]}), str({"plants": s1["plants"], "clock": s1["clock"], "elapsed": s1["elapsed"]})])
	rec("pause.hp_and_fruit_frozen", "a healing fruit lying at the player does not heal during the pause (HP stays 5) and its age does not advance", s1["hp"] == 5 and s1["items"].size() >= 1 and s1["items"][s1["items"].size() - 1][1] == 0.0, "hp=%s items=%s" % [str(s1["hp"]), str(s1["items"])])
	tap_escape()
	await settle()
	var resumed: bool = not paused
	var age_k_before: float = k.age
	var age_c_before: float = c.age
	await ticks(12)
	var dt_expected: float = 12.0 / float(Engine.physics_ticks_per_second)
	var dk: float = k.age - age_k_before
	var dc: float = c.age - age_c_before
	rec("pause.resume_no_bank", "after resuming, 12 physics ticks add about 12 ticks of time to the plants (not the 1.5 s spent paused)", resumed and dk > 0.0 and dk < dt_expected + 0.3 and dc > 0.0 and dc < dt_expected + 0.3 and dk < 1.0, "resumed=%s kiwi age +%.4f carrot age +%.4f (12 ticks = %.3f s; paused 1.5 s)" % [resumed, dk, dc, dt_expected])
	rec("pause.hp_after_resume", "after resuming, the fruit at the player heals (+2: HP 7)", play.hp == 7, "hp=%d" % play.hp)
	# kiwi matures only after exactly 10 s of running game time from age 30
	var t0: float = play.elapsed
	var expect_remaining: float = 40.0 - k.age
	var guard: int = 0
	while not k.mature and guard < 60 * 20:
		await physics_frame
		guard += 1
	var run_time: float = play.elapsed - t0
	rec("pause.kiwi_matures_on_running_time", "the kiwi (age 30 at pause time) matures after exactly the remaining running game time (40 s minus its age), the 1.5 s paused do not count", k.mature and absf(run_time - expect_remaining) < 0.05, "ran %.3f s of game time after resume, 40 - age = %.3f s" % [run_time, expect_remaining])

# ------------------------------------------------------------------------------------------ frame rate

func t_rate(hz: int) -> void:
	await new_main()
	var play: PlayState = main.play
	var world: WorldState = main.grid
	var site: Vector2i = find_square(world, 0, 20, main.region_def.start_tile + Vector2i(60, 0))
	var origin: Vector2i = site + Vector2i(-5, -5)
	var center_px: Vector2 = make_block(origin)
	await place_player(center_px + Vector2(0, 160))
	play.reserve_plant(play.def_by_key(&"kiwi"))
	var k: CultivatedPlant = play.land_plant(&"kiwi", center_px)
	var t0: float = play.elapsed
	var frames_39: int = 0
	var mature_at: float = -1.0
	var first_fruit_at: float = -1.0
	var target_frames: int = int(61.5 * hz)
	for i: int in target_frames:
		await physics_frame
		if mature_at < 0.0 and k.mature:
			mature_at = play.elapsed - t0
		if first_fruit_at < 0.0 and play.pickups.count_kind("heal_fruit") > 0:
			first_fruit_at = play.elapsed - t0
	var tol: float = 1.5 / float(hz) + 0.01
	rec("rate.kiwi_%d" % hz, "at %d Hz the kiwi matures at 40 s and drops the first fruit at 60 s of game time" % hz, absf(mature_at - 40.0) <= tol and absf(first_fruit_at - 60.0) <= tol, "mature_at=%.4f first_fruit_at=%.4f drops=%d elapsed=%.3f" % [mature_at, first_fruit_at, k.drops, play.elapsed - t0])
	observations["rate_%d" % hz] = {"mature_at": mature_at, "first_fruit_at": first_fruit_at, "drops": k.drops}
