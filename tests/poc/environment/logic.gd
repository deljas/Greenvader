extends SceneTree
## POC-05 logic checks (headless OK). Run:
## godot --headless --path <repo> --script res://tests/poc/environment/logic.gd
## Long conditions are fast-forwarded with advance_game(); each condition runs once. No OS-level input.
## Compass (screen based): north = ground (-1,0,-1), east = (+1,0,-1), south = (+1,0,+1), west = (-1,0,+1).
const Config: GDScript = preload("res://scripts/poc/poc_config.gd")
const Coords: GDScript = preload("res://scripts/poc/poc_coords.gd")
const Session: GDScript = preload("res://scripts/poc/poc_session.gd")
const PocInput: GDScript = preload("res://scripts/poc/poc_input.gd")
const Day: GDScript = preload("res://scripts/poc/environment/poc_day.gd")
const Layout: GDScript = preload("res://scripts/poc/environment/wall_layout.gd")
const WallGrowthScript: GDScript = preload("res://scripts/poc/environment/wall_growth.gd")
const GroundCoverScript: GDScript = preload("res://scripts/poc/environment/ground_cover.gd")

var failures: int = 0
var passes: int = 0
var sessions: Array[RefCounted] = []

func check(name: String, ok: bool, detail: String = "") -> void:
	if ok:
		passes += 1
		print("PASS ", name, " ", detail)
	else:
		failures += 1
		print("FAIL ", name, " ", detail)

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	_time_from_clock()
	_sun_compass()
	_sunlight_growth()
	_paved_rules()
	_ground_cover_display()
	_wall_layouts()
	_wall_growth_rules()
	_wall_save()
	await _main_checks()
	for s: RefCounted in sessions:
		s.close()
	print("RESULT passes=%d failures=%d" % [passes, failures])
	quit(1 if failures > 0 else 0)

func new_session(combat: bool = false, map: String = "", paved: bool = false) -> RefCounted:
	var s: RefCounted = Session.new()
	if paved:
		s.paving = Session.paving_from(s.env_tuning)
	var ok: bool = s.load_combat() if combat else (s.load_placement(map) if map != "" else s.load_placement())
	check("setup.load", ok)
	sessions.append(s)
	return s

## Jumps the clock to `hour` without making the clock replay ticks (elapsed and the tick counters move together).
func set_hour(s: RefCounted, hour: float) -> void:
	var start: float = float(s.env_tuning["start_hour"])
	var day_seconds: float = float(s.env_tuning["day_seconds"])
	var elapsed: float = fposmod(hour - start, 24.0) / 24.0 * day_seconds
	s.clock.load_dict({"version": 1, "elapsed": elapsed, "growth_ticks": int(elapsed / s.clock.growth_period), "spread_ticks": int(elapsed / s.clock.spread_period)})
	s.growth.ticks = s.clock.growth_ticks
	s.state.growth_tick = s.clock.growth_ticks

func run_for(s: RefCounted, seconds: float) -> void:
	var left: float = seconds
	while left > 0.0:
		var piece: float = minf(left, 0.25)
		s.advance_game(piece)
		left -= piece

func horizontal(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z).normalized()

# ---------------------------------------------------------------- time

func _time_from_clock() -> void:
	var s: RefCounted = new_session()
	var tuning: Dictionary = s.env_tuning
	check("time.tuning_loaded", float(tuning.get("day_seconds", 0.0)) == 600.0 and float(tuning.get("start_hour", -1.0)) == 8.0)
	check("time.start_is_morning", is_equal_approx(s.day_hour(), 8.0), "hour=%f" % s.day_hour())
	run_for(s, 100.0)
	var expected: float = fposmod(8.0 + s.clock.elapsed / 600.0 * 24.0, 24.0)
	check("time.hour_from_elapsed", is_equal_approx(s.day_hour(), expected) and is_equal_approx(s.day_hour(), 12.0), "elapsed=%f hour=%f" % [s.clock.elapsed, s.day_hour()])
	# the same elapsed gives the same hour in a different session (no hidden hour state)
	var other: RefCounted = new_session()
	other.clock.elapsed = s.clock.elapsed
	check("time.same_elapsed_same_hour", other.day_hour() == s.day_hour())
	s.paused = true
	var hour_paused: float = s.day_hour()
	s.advance_game(50.0)
	check("time.pause_freezes", s.day_hour() == hour_paused and is_equal_approx(s.clock.elapsed, 100.0))
	s.paused = false
	s.advance_game(0.25)
	check("time.resume_no_catch_up", is_equal_approx(s.clock.elapsed, 100.25) and absf(s.day_hour() - hour_paused) < 0.02, "dh=%f" % (s.day_hour() - hour_paused))
	run_for(s, 499.75)
	check("time.wraps_after_one_day", is_equal_approx(s.day_hour(), 8.0) and s.day_hour() >= 0.0 and s.day_hour() < 24.0, "hour=%f" % s.day_hour())

# ---------------------------------------------------------------- sun

func _sun_compass() -> void:
	var tuning: Dictionary = Day.load_tuning()
	var morning: Dictionary = Day.state(7.0, tuning)
	var noon: Dictionary = Day.state(12.0, tuning)
	var evening: Dictionary = Day.state(17.0, tuning)
	var midnight: Dictionary = Day.state(0.0, tuning)
	check("sun.morning_is_east", horizontal(morning["source"]).dot(Day.EAST) > 0.9 and morning["source"].y > 0.0, "h=%s" % str(horizontal(morning["source"])))
	check("sun.noon_is_south", horizontal(noon["source"]).dot(Day.SOUTH) > 0.99, "h=%s" % str(horizontal(noon["source"])))
	check("sun.evening_is_west", horizontal(evening["source"]).dot(Day.WEST) > 0.9 and evening["source"].y > 0.0, "h=%s" % str(horizontal(evening["source"])))
	check("sun.noon_highest", float(noon["sun_elevation"]) > float(morning["sun_elevation"]) and float(noon["sun_elevation"]) > float(evening["sun_elevation"]) and float(noon["sun_elevation"]) > 50.0, "noon=%f" % float(noon["sun_elevation"]))
	check("sun.night_sun_below_horizon", float(midnight["sun_elevation"]) < 0.0 and float(midnight["sun_power"]) == 0.0 and float(midnight["moon_source"].y) > 0.0)
	var east2: Vector2 = Vector2(Day.EAST.x, Day.EAST.z)
	var north2: Vector2 = Vector2(Day.NORTH.x, Day.NORTH.z)
	var south2: Vector2 = Vector2(Day.SOUTH.x, Day.SOUTH.z)
	check("sun.compass_matches_screen", east2.dot(Coords.screen_dir_to_ground(Vector2(1, 0))) > 0.7 and north2.dot(Coords.screen_dir_to_ground(Vector2(0, -1))) > 0.7 and south2.dot(Coords.screen_dir_to_ground(Vector2(0, 1))) > 0.7)

# ---------------------------------------------------------------- sunlight and growth

func _sunlight_growth() -> void:
	var s: RefCounted = new_session()
	var low: float = 99.0
	var high: float = 0.0
	for tenth: int in 241:
		var h: float = float(tenth) / 10.0
		var f: float = Day.sunlight_factor(Day.state(h, s.env_tuning), s.env_tuning)
		low = minf(low, f)
		high = maxf(high, f)
	check("sunlight.range", low >= 1.0 and is_equal_approx(low, 1.0) and absf(high - 1.25) < 0.001, "min=%f max=%f" % [low, high])
	set_hour(s, 0.0)
	check("sunlight.night_is_1", s.sunlight_factor(0) == 1.0)
	set_hour(s, 12.0)
	check("sunlight.noon_max", absf(s.sunlight_factor(0) - 1.25) < 0.001)
	check("sunlight.provider_connected", s.growth.sunlight_provider.is_valid() and s.growth.sunlight_factor(5) == s.sunlight_factor(5))
	# independent of moisture: the provider answers the same for a wet and a dry tile, and moisture changes the gain by its own factor
	var dry: int = -1
	var wet: int = -1
	for i: int in s.state.tile_count():
		if s.state.target[i] == 1 and s.state.terrain[i] == Session.T_WASTE:
			if dry < 0:
				dry = i
			elif wet < 0:
				wet = i
	s.state.set_stage(dry, WorldState.STAGE_SEED)
	s.state.set_stage(wet, WorldState.STAGE_SEED)
	s.state.set_moisture(wet, s.sim_tuning.moisture_max)
	s.state.set_moisture(dry, 0)
	check("sunlight.independent_of_moisture", s.sunlight_factor(dry) == s.sunlight_factor(wet))
	var gain_noon_dry: int = s.growth.gain_for(dry)
	var gain_noon_wet: int = s.growth.gain_for(wet)
	set_hour(s, 0.0)
	var gain_night_dry: int = s.growth.gain_for(dry)
	var gain_night_wet: int = s.growth.gain_for(wet)
	check("sunlight.noon_faster_than_night", gain_noon_dry >= gain_night_dry and gain_noon_wet > gain_night_wet, "dry %d/%d wet %d/%d" % [gain_noon_dry, gain_night_dry, gain_noon_wet, gain_night_wet])
	var ratio_wet: float = float(gain_noon_wet) / float(gain_night_wet)
	check("sunlight.factor_applies_as_ratio", absf(ratio_wet - 1.25) < 0.05, "wet ratio=%f" % ratio_wet)
	check("sunlight.moisture_factor_separate", gain_night_wet > gain_night_dry, "night wet=%d dry=%d" % [gain_night_wet, gain_night_dry])
	# night + dry still grows (every tick adds at least 1)
	var before: int = s.state.growth[dry]
	run_for(s, 10.0)
	check("sunlight.night_dry_still_grows", s.state.growth[dry] - before >= 15 or s.state.stage[dry] > WorldState.STAGE_SEED, "growth +%d stage=%d" % [s.state.growth[dry] - before, s.state.stage[dry]])

# ---------------------------------------------------------------- pavement

func _paved_rules() -> void:
	var s: RefCounted = new_session(true, "", true)
	var plain: RefCounted = new_session(true)
	var paved: PackedInt32Array = PackedInt32Array()
	var soil: int = -1
	for i: int in s.state.tile_count():
		if s.state.terrain[i] == Session.T_PAVED:
			paved.append(i)
		elif s.state.terrain[i] == Session.T_WASTE and soil < 0 and s.state.target[i] == 1:
			soil = i
	var plain_paved: int = 0
	for i: int in plain.state.tile_count():
		if plain.state.terrain[i] == Session.T_PAVED:
			plain_paved += 1
	check("paved.opt_in_only", plain_paved == 0 and plain.state.target_count == s.state.target_count, "plain paved=%d" % plain_paved)
	check("paved.exists_in_fixture", paved.size() >= 60, "cells=%d" % paved.size())
	var all_target: bool = true
	var all_plantable: bool = true
	var bad: int = -1
	for i: int in paved:
		all_target = all_target and s.state.target[i] == 1 and s.state.is_target_tile(i)
		if not s.state.can_plant(i):
			all_plantable = false
			bad = i
	check("paved.target_and_plantable_like_soil", all_target and all_plantable, "bad=%d stage=%d occ=%d" % [bad, s.state.stage[maxi(bad, 0)], s.state.occupant[maxi(bad, 0)]])
	var def_paved: TerrainDef = s.state.terrain_defs[Session.T_PAVED]
	var def_soil: TerrainDef = s.state.terrain_defs[Session.T_WASTE]
	check("paved.def_same_rules", def_paved.is_target == def_soil.is_target and def_paved.plantable == def_soil.plantable and def_paved.walkable == def_soil.walkable and def_paved.is_waterside == def_soil.is_waterside and def_paved.initial_stage == def_soil.initial_stage and def_paved.ground_color != def_soil.ground_color)
	var greened0: int = s.state.greened_count
	var targets: int = s.state.target_count
	s.state.set_stage(paved[0], WorldState.STAGE_SPROUT1)
	check("paved.greened_counts_like_soil_1", s.state.greened_count == greened0 + 1)
	s.state.set_stage(soil, WorldState.STAGE_SPROUT1)
	check("paved.greened_counts_like_soil_2", s.state.greened_count == greened0 + 2 and s.state.target_count == targets and s.state.counters_consistent())
	s.state.set_stage(paved[0], WorldState.STAGE_EMPTY)
	check("paved.stage_loss_like_soil", s.state.greened_count == greened0 + 1)

func _ground_cover_display() -> void:
	var s: RefCounted = new_session(true, "", true)
	var cover: Node3D = GroundCoverScript.new()
	cover.build(s, s.env_tuning)
	s.state.clear_dirty()
	var paved_cells: PackedInt32Array = PackedInt32Array()
	var soil_cells: PackedInt32Array = PackedInt32Array()
	for i: int in s.state.tile_count():
		if s.state.target[i] == 1:
			if s.state.terrain[i] == Session.T_PAVED:
				paved_cells.append(i)
			elif soil_cells.size() < 400:
				soil_cells.append(i)
	for i: int in 40:
		s.state.set_stage(paved_cells[i], WorldState.STAGE_MATURE)
	for i: int in 40:
		s.state.set_stage(soil_cells[i], WorldState.STAGE_MATURE)
	var dirty: PackedInt32Array = s.state.take_dirty()
	var updates0: int = cover.cell_updates
	cover.apply(dirty)
	check("cover.differential_update", dirty.size() >= 80 and dirty.size() < s.state.tile_count() / 4 and cover.cell_updates - updates0 == dirty.size(), "dirty=%d updates=%d" % [dirty.size(), cover.cell_updates - updates0])
	var soil_ok: bool = true
	for i: int in 40:
		soil_ok = soil_ok and cover.shown_soil[soil_cells[i]] == 100 and cover.shown_pave[soil_cells[i]] == 0 and cover.shown_crack[soil_cells[i]] == 0
	var pave_ok: bool = true
	for i: int in 40:
		pave_ok = pave_ok and cover.shown_pave[paved_cells[i]] == 100 and cover.shown_soil[paved_cells[i]] == 0 and cover.shown_crack[paved_cells[i]] == 1
	check("cover.soil_covered_pavement_cracks", soil_ok and pave_ok)
	check("cover.pavement_untouched_has_no_cover", cover.shown_pave[paved_cells[60]] == 0 and cover.shown_crack[paved_cells[60]] == 0)
	s.state.set_stage(soil_cells[100], WorldState.STAGE_SPROUT1)
	s.state.set_stage(soil_cells[101], WorldState.STAGE_SPROUT2)
	cover.apply(s.state.take_dirty())
	check("cover.stage_scales_grow", cover.shown_soil[soil_cells[100]] < cover.shown_soil[soil_cells[101]] and cover.shown_soil[soil_cells[101]] < cover.shown_soil[soil_cells[0]], "%d < %d < %d" % [cover.shown_soil[soil_cells[100]], cover.shown_soil[soil_cells[101]], cover.shown_soil[soil_cells[0]]])
	# display density never changes the internal greening
	var greened: int = s.state.greened_count
	var percent: int = s.greening_percent()
	var full: int = cover.visible_count("soil") + cover.visible_count("pave")
	cover.set_density(0.3, 0.3)
	var thin: int = cover.visible_count("soil") + cover.visible_count("pave")
	check("cover.density_changes_display_only", thin < full and s.state.greened_count == greened and s.greening_percent() == percent and s.state.counters_consistent(), "visible %d -> %d, greened=%d" % [full, thin, s.state.greened_count])
	cover.set_density(1.0, 1.0)
	check("cover.density_restored", cover.visible_count("soil") + cover.visible_count("pave") == full and s.state.greened_count == greened)
	cover.free()

# ---------------------------------------------------------------- wall layouts

func _wall_layouts() -> void:
	var s: RefCounted = new_session()
	var catalog: Dictionary = s.placement.catalog
	var checked: int = 0
	var worst: float = 0.0
	var door_hits: int = 0
	var window_edge: int = 0
	var window_overlap: int = 0
	var rows: PackedStringArray = []
	for asset_id: String in catalog.keys():
		var surfaces: Array[Dictionary] = Layout.surfaces_for(catalog[asset_id])
		if surfaces.is_empty():
			continue
		checked += 1
		var paths: Array[Dictionary] = Layout.vine_paths(surfaces, 7, 0.05)
		var patches: Array[Dictionary] = Layout.moss_patches(surfaces, 7, float(s.env_tuning["wall"]["moss_span_scale"]))
		var cov: Dictionary = Layout.coverage(surfaces, paths, patches)
		worst = maxf(worst, float(cov["ratio"]))
		rows.append("%s paths=%d moss=%d cover=%.2f" % [asset_id, paths.size(), patches.size(), float(cov["ratio"])])
		for path: Dictionary in paths:
			var surface: Dictionary = surfaces[int(path["surface"])]
			for point: Dictionary in path["points"]:
				var uv: Vector2 = Vector2(float(point["u"]), float(point["v"]))
				for hole: Rect2 in surface["holes"]:
					if Layout.is_door(hole):
						if hole.grow(0.10).has_point(uv):
							door_hits += 1
					else:
						if hole.has_point(uv):
							window_overlap += 1
						elif hole.grow(0.30).has_point(uv):
							window_edge += 1
		for patch: Dictionary in patches:
			var surface2: Dictionary = surfaces[int(patch["surface"])]
			for corner: Vector2 in [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]:
				var uv2: Vector2 = Layout.moss_uv(patch["center"], patch["span"], 1, corner)
				for hole2: Rect2 in surface2["holes"]:
					if Layout.is_door(hole2) and hole2.has_point(uv2) and Layout.moss_corner_ok(surface2, uv2):
						door_hits += 1
	print("layout: ", " | ".join(rows))
	check("wall.assets_with_surfaces", checked >= 2, "assets=%d" % checked)
	check("wall.coverage_at_most_half", worst <= 0.5 and worst > 0.02, "worst=%.3f" % worst)
	check("wall.door_never_covered", door_hits == 0, "hits=%d" % door_hits)
	check("wall.vines_along_window_frames", window_edge > 0, "points near frames=%d" % window_edge)
	check("wall.vines_reach_part_of_a_window", window_overlap > 0, "points over glass=%d" % window_overlap)

# ---------------------------------------------------------------- wall growth

func _roots_cells(entry: Dictionary) -> PackedInt32Array:
	var cells: PackedInt32Array = PackedInt32Array()
	for root: Dictionary in entry["roots"]:
		for c: int in root["cells"]:
			if not cells.has(c):
				cells.append(c)
	for moss: Dictionary in entry["moss"]:
		for c: int in moss["cells"]:
			if not cells.has(c):
				cells.append(c)
	return cells

func _wall_growth_rules() -> void:
	var s: RefCounted = new_session()
	var wg: RefCounted = s.wall_growth
	check("wallg.entries", wg != null and wg.entries.size() >= 2 and not wg.entry_of("mill_01").is_empty() and not wg.entry_of("chapel_01").is_empty(), "entries=%d" % wg.entries.size())
	var entry: Dictionary = wg.entry_of("mill_01")
	var cells: PackedInt32Array = _roots_cells(entry)
	check("wallg.roots_have_ground_cells", cells.size() >= 10 and (entry["roots"] as Array).size() >= 3, "cells=%d roots=%d moss=%d" % [cells.size(), (entry["roots"] as Array).size(), (entry["moss"] as Array).size()])
	run_for(s, 4.0)
	check("wallg.no_green_no_growth", wg.total_progress() == 0.0)
	for c: int in cells:
		s.state.set_stage(c, WorldState.STAGE_MATURE)
	run_for(s, 6.0)
	var grown: float = wg.total_progress()
	check("wallg.grows_with_green", grown > 0.0, "progress sum=%f" % grown)
	# lost green: stage back to empty, progress is kept and no longer advances
	for c: int in cells:
		s.state.set_stage(c, WorldState.STAGE_EMPTY)
	for i: int in 6:
		wg.on_growth_tick(0)
	check("wallg.loss_keeps_progress_and_stops", wg.total_progress() == grown, "before=%f after=%f" % [grown, wg.total_progress()])
	# partial green grows slower than full green
	for c: int in cells:
		s.state.set_stage(c, WorldState.STAGE_MATURE)
	var root0: Dictionary = entry["roots"][0]
	wg.on_growth_tick(0)
	var full_input: float = float(root0["input"])
	for c: int in root0["cells"]:
		s.state.set_stage(c, WorldState.STAGE_SPROUT1)
		s.state.growth[c] = s.sim_tuning.mature_growth / 2
	wg.on_growth_tick(0)
	check("wallg.input_follows_green", full_input > float(root0["input"]) and float(root0["input"]) > 0.0, "full=%f partial=%f" % [full_input, float(root0["input"])])
	for c: int in cells:
		s.state.set_stage(c, WorldState.STAGE_MATURE)
	# pause stops it
	s.paused = true
	var frozen: float = wg.total_progress()
	run_for(s, 20.0)
	check("wallg.pause_stops", wg.total_progress() == frozen)
	s.paused = false
	run_for(s, 2.0)
	check("wallg.resume_continues", wg.total_progress() > frozen)
	# sun independence: the same ground at noon and at midnight gives the same progress
	var day: RefCounted = new_session()
	var night: RefCounted = new_session()
	set_hour(day, 12.0)
	set_hour(night, 0.0)
	for pair: RefCounted in [day, night]:
		for c: int in _roots_cells(pair.wall_growth.entry_of("mill_01")):
			pair.state.set_stage(c, WorldState.STAGE_MATURE)
		run_for(pair, 8.0)
	check("wallg.sun_independent", day.wall_growth.total_progress() > 0.0 and is_equal_approx(day.wall_growth.total_progress(), night.wall_growth.total_progress()), "noon=%f night=%f" % [day.wall_growth.total_progress(), night.wall_growth.total_progress()])
	# vine growth finishes: full progress reaches exactly 1.0 and stays
	wg.debug_set_all(0.999)
	run_for(s, 20.0)
	var maxed: bool = true
	for e: Dictionary in wg.entries:
		for r: Dictionary in e["roots"]:
			maxed = maxed and float(r["progress"]) <= 1.0
	check("wallg.capped_at_one", maxed)

func _wall_save() -> void:
	var s: RefCounted = new_session()
	var entry: Dictionary = s.wall_growth.entry_of("mill_01")
	for c: int in _roots_cells(entry):
		s.state.set_stage(c, WorldState.STAGE_MATURE)
	run_for(s, 8.0)
	var data: Dictionary = s.wall_growth.to_dict()
	var json: Variant = JSON.parse_string(JSON.stringify(data))
	var fresh: RefCounted = new_session()
	check("wallsave.fresh_is_zero", fresh.wall_growth.total_progress() == 0.0 and s.wall_growth.total_progress() > 0.0)
	var ok: bool = fresh.wall_growth.load_dict(json)
	check("wallsave.roundtrip_equal", ok and same_progress(fresh.wall_growth.to_dict(), data) and is_equal_approx(fresh.wall_growth.total_progress(), s.wall_growth.total_progress()) and fresh.wall_growth.tick_count == s.wall_growth.tick_count)
	var direct: RefCounted = new_session()
	check("wallsave.exact_without_json", direct.wall_growth.load_dict(data) and direct.wall_growth.to_dict() == data)
	var bad: Dictionary = data.duplicate(true)
	(bad["entries"] as Dictionary).erase("mill_01")
	check("wallsave.mismatch_rejected", not fresh.wall_growth.load_dict(bad) and same_progress(fresh.wall_growth.to_dict(), data))
	check("wallsave.session_dict_has_it", s.to_dict().has("wall_growth"))

func same_progress(a: Dictionary, b: Dictionary) -> bool:
	var rows_a: Dictionary = a["entries"]
	var rows_b: Dictionary = b["entries"]
	if rows_a.size() != rows_b.size():
		return false
	for id: Variant in rows_a.keys():
		if not rows_b.has(id):
			return false
		for key: String in ["roots", "moss"]:
			var xs: Array = rows_a[id][key]
			var ys: Array = rows_b[id][key]
			if xs.size() != ys.size():
				return false
			for i: int in xs.size():
				if absf(float(xs[i]) - float(ys[i])) > 0.000001:
					return false
	return true

# ---------------------------------------------------------------- display layer

func _frames(n: int) -> void:
	for i: int in n:
		await process_frame

func _main_checks() -> void:
	PocInput.register()
	var main: Node = load("res://scenes/poc.tscn").instantiate()
	main.set_meta(&"poc_combat", true)
	root.add_child(main)
	await _frames(2)
	main.auto_process = false
	main.window_size_override = Vector2i(1920, 1080)
	var s: RefCounted = main.session
	main.tick(0.0, Vector2.ZERO)
	check("main.hud_shows_time", main.hud.text.contains("時刻 08:00"), main.hud.text.split("\n")[1])
	check("main.env_built", main.env_view != null and main.water_view != null and main.wall_view != null and main.wall_view.instance_ids().size() >= 1)
	# key light follows the clock: sun in the east in the morning, south at noon, moon by night; sprite shadow follows
	var checks: Array = [[7.0, Day.EAST, false], [12.0, Day.SOUTH, false], [17.0, Day.WEST, false], [1.0, null, true]]
	for entry: Array in checks:
		set_hour(s, float(entry[0]))
		main.tick(0.0, Vector2.ZERO)
		var toward: Vector3 = main.sun.global_basis.z
		var dir_ok: bool = true
		if entry[1] != null:
			dir_ok = horizontal(toward).dot(entry[1] as Vector3) > 0.9 and toward.y > 0.0 and main.sun.light_energy > 0.2
		else:
			dir_ok = main.env_view.last_is_moon and toward.y > 0.0 and main.sun.light_energy > 0.02 and main.sun.light_energy < 0.2
		var board: Vector3 = main.actor.shadow_board.global_basis.z
		var board_ok: bool = absf(horizontal(board).dot(horizontal(toward)) - 1.0) < 0.001
		check("main.light_hour_%d" % int(entry[0]), dir_ok and board_ok, "toward=%s energy=%f board_dot=%f" % [str(toward), main.sun.light_energy, horizontal(board).dot(horizontal(toward))])
	set_hour(s, 12.0)
	main.tick(0.0, Vector2.ZERO)
	var noon_ambient: float = main.world_environment.ambient_light_energy
	set_hour(s, 0.0)
	main.tick(0.0, Vector2.ZERO)
	check("main.night_darker_ambient", main.world_environment.ambient_light_energy < noon_ambient, "%f -> %f" % [noon_ambient, main.world_environment.ambient_light_energy])
	check("main.hud_shows_night", main.hud.text.contains("時刻 00:00") and main.hud.text.contains("夜"))
	# water: reflection viewport is proportional to the resolution
	check("water.surface_cells", main.water_view.water_cells >= 60 and main.water_view.surface_node.mesh != null, "cells=%d" % main.water_view.water_cells)
	var size640: Vector2i = main.water_view.reflection_view.size
	main.set_resolution(1, Vector2i(1920, 1080))
	var size960: Vector2i = main.water_view.reflection_view.size
	check("water.reflection_scales_with_resolution", size640 == Vector2i(320, 180) and size960 == Vector2i(480, 270), "640->%s 960->%s" % [str(size640), str(size960)])
	var floor_layers: int = (main.world.get_node("Ground") as MeshInstance3D).layers
	check("water.ground_layer_not_reflected", (floor_layers & main.water_view.reflection_camera.cull_mask) == 0 and main.water_view.reflection_camera.cull_mask == 1, "ground layers=%d" % floor_layers)
	# puddles are visual only: they are never a water source
	var puddle_sources: int = 0
	for inst: Dictionary in s.placement.instances:
		if inst["kind"] == "puddle":
			var cell: Vector2i = Coords.ground_to_cell(inst["pos"])
			if s.placement.is_water_source(cell):
				puddle_sources += 1
	check("water.puddle_not_a_source", puddle_sources == 0 and s.placement.puddle.count(1) > 0)
	# pause: the lit time stops with the clock
	set_hour(s, 9.0)
	s.paused = true
	main.tick(5.0, Vector2.ZERO)
	check("main.pause_time_frozen", is_equal_approx(s.day_hour(), 9.0))
	s.paused = false
	main.queue_free()
	await _frames(2)
