extends SceneTree
## POC3-PLAYTEST-01 work A: area watering (1/3/5/7), no-effect refusal, sprinkler radius, animation timeline, save.
const Session: GDScript = preload("res://scripts/poc2/poc2_session.gd")
const Coords: GDScript = preload("res://scripts/poc/poc_coords.gd")
const Work: GDScript = preload("res://scripts/poc2/simulation/helper_work.gd")
const Timeline: GDScript = preload("res://scripts/poc2/view/fire_timeline.gd")
const WaterArea: GDScript = preload("res://scripts/poc2/simulation/water_area.gd")
const OUT: String = "res://evidence/poc3/playtest01/self/"
var checks: Array[Dictionary] = []

func _init() -> void:
	call_deferred("run")

func check(label: String, passed: bool, detail: Variant = "") -> void:
	checks.append({"name": label, "status": "PASS" if passed else "FAIL", "detail": detail})
	print(JSON.stringify(checks.back()))

const CENTER: Vector2i = Vector2i(192, 188)

func fresh() -> RefCounted:
	var s: RefCounted = Session.new()
	s.enemies.clear(); s.nests.clear(); s.fossils.clear()
	for y: int in range(183, 193):
		for x: int in range(180, 205): s.state.set_stage(s.state.index_of(x, y), WorldState.STAGE_EMPTY)
	s.position = Coords.cell_center_logic(Vector2i(187, 188))
	s.known.fill(1)
	s.water = 100.0
	return s

func grow(s: RefCounted, rect: Rect2i, stage: int = WorldState.STAGE_SEED) -> void:
	for y: int in range(rect.position.y, rect.end.y):
		for x: int in range(rect.position.x, rect.end.x): s.state.set_stage(s.state.index_of(x, y), stage)

func wet_cells(s: RefCounted, rect: Rect2i) -> int:
	var n: int = 0
	for y: int in range(rect.position.y, rect.end.y):
		for x: int in range(rect.position.x, rect.end.x):
			if s.state.moisture[s.state.index_of(x, y)] > 0: n += 1
	return n

func aim(cell: Vector2i) -> Vector2:
	return Coords.cell_center_logic(cell)

func sizes() -> void:
	for width: int in [1, 3, 5, 7]:
		var s: RefCounted = fresh()
		grow(s, Rect2i(CENTER - Vector2i(4, 4), Vector2i(9, 9)))
		s.sow_width = width
		var r: Dictionary = s.water_at(aim(CENTER))
		var half: int = width >> 1
		var inside: int = wet_cells(s, Rect2i(CENTER - Vector2i(half, half), Vector2i(width, width)))
		var total: int = wet_cells(s, Rect2i(CENTER - Vector2i(4, 4), Vector2i(9, 9)))
		check("size_%d_center_cost" % width, bool(r.ok) and int(r.cost) == width * width and inside == width * width and total == width * width and is_equal_approx(s.water, 100.0 - float(width * width)), {"cost": r.get("cost"), "water": s.water, "wet": total})
		s.close()

func shortage() -> void:
	var s: RefCounted = fresh()
	grow(s, Rect2i(CENTER - Vector2i(4, 4), Vector2i(9, 9)))
	s.sow_width = 7; s.water = 10.0
	var plan: Dictionary = s.water_preview(aim(CENTER))
	var r: Dictionary = s.water_at(aim(CENTER))
	# Independently derived: centre, 4 edge neighbours, 4 diagonals, then (0,-2) first in y/x order.
	var near: Array[Vector2i] = [CENTER]
	for d: Vector2i in [Vector2i(0, -1), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1)]: near.append(CENTER + d)
	near.append(CENTER + Vector2i(0, -2))
	var ok: bool = true
	for c: Vector2i in near: ok = ok and s.state.moisture[s.state.index_of(c.x, c.y)] > 0
	check("shortage_nearest_first_only_held_water", bool(r.ok) and int(r.cost) == 10 and plan.cost == 10 and plan.affordable.size() == 10 and plan.unaffordable.size() == 39 and ok and wet_cells(s, Rect2i(CENTER - Vector2i(4, 4), Vector2i(9, 9))) == 10 and is_equal_approx(s.water, 0.0))
	var again: Dictionary = s.water_at(aim(CENTER))
	check("empty_tank_refuses", not bool(again.ok) and again.reason == "no_water")
	s.close()

func mixed() -> void:
	var s: RefCounted = fresh()
	s.sow_width = 3
	grow(s, Rect2i(CENTER - Vector2i(1, 1), Vector2i(3, 3)))
	s.state.set_stage(s.state.index_of(CENTER.x - 1, CENTER.y - 1), WorldState.STAGE_MATURE)
	s.state.set_stage(s.state.index_of(CENTER.x, CENTER.y - 1), WorldState.STAGE_EMPTY)
	s.state.set_moisture(s.state.index_of(CENTER.x + 1, CENTER.y - 1), 100)
	s.state.set_stage(s.state.index_of(CENTER.x - 1, CENTER.y), WorldState.STAGE_SPROUT1)
	s.state.set_stage(s.state.index_of(CENTER.x + 1, CENTER.y), WorldState.STAGE_SPROUT2)
	var plan: Dictionary = s.water_preview(aim(CENTER))
	var r: Dictionary = s.water_at(aim(CENTER))
	var skipped: bool = s.state.moisture[s.state.index_of(CENTER.x - 1, CENTER.y - 1)] == 0 and s.state.moisture[s.state.index_of(CENTER.x, CENTER.y - 1)] == 0
	check("mixed_cells_only_effective_charged", plan.valid.size() == 6 and bool(r.ok) and int(r.cost) == 6 and skipped and is_equal_approx(s.water, 94.0), {"valid": plan.valid.size(), "cost": r.get("cost"), "water": s.water})
	# Crops: one unit regardless of footprint; mature / already watered crops are not effective.
	var t: RefCounted = fresh()
	t.unlocked["watermelon"] = true; t.unlocked["clover"] = true; t.seeds = 100000
	grow(t, Rect2i(CENTER - Vector2i(4, 4), Vector2i(9, 9)), WorldState.STAGE_MATURE)
	var melon: Dictionary = t.place_plant("watermelon", CENTER + Vector2i(-1, -1))
	var clover: Dictionary = t.place_plant("clover", CENTER + Vector2i(3, 3))
	t.sow_width = 7
	var cplan: Dictionary = t.water_preview(aim(CENTER))
	var cr: Dictionary = t.water_at(aim(CENTER))
	var melon_p: Dictionary = {}
	var clover_p: Dictionary = {}
	for p: Dictionary in t.plants:
		if p.kind == "watermelon": melon_p = p
		else: clover_p = p
	check("crops_count_one_each_and_become_watered", bool(melon.ok) and bool(clover.ok) and cplan.valid.size() == 2 and bool(cr.ok) and int(cr.cost) == 2 and bool(melon_p.watered) and bool(clover_p.watered) and is_equal_approx(t.water, 98.0), {"valid": cplan.valid.size(), "water": t.water})
	var second: Dictionary = t.water_at(aim(CENTER))
	check("watered_crops_and_mature_grass_refused", not bool(second.ok) and second.reason == "no_effect" and is_equal_approx(t.water, 98.0))
	t.close()
	s.close()

func no_effect() -> void:
	var s: RefCounted = fresh()
	s.sow_width = 7
	grow(s, Rect2i(CENTER - Vector2i(4, 4), Vector2i(9, 9)), WorldState.STAGE_MATURE)
	var before_dirty: int = s.state.dirty_tiles.size()
	var check_r: Dictionary = s.water_check(aim(CENTER))
	var plan: Dictionary = s.water_preview(aim(CENTER))
	var r: Dictionary = s.water_at(aim(CENTER))
	check("no_effect_mature_area_refused_nothing_spent", not bool(check_r.ok) and check_r.reason == "no_effect" and not bool(r.ok) and r.reason == "no_effect" and plan.no_effect and plan.cost == 0 and is_equal_approx(s.water, 100.0) and s.state.dirty_tiles.size() == before_dirty)
	var empty: RefCounted = fresh()
	empty.sow_width = 7
	var er: Dictionary = empty.water_at(aim(CENTER))
	check("no_effect_bare_ground_refused", not bool(er.ok) and er.reason == "no_effect" and is_equal_approx(empty.water, 100.0))
	empty.close()
	# Far aim is limited to the 50px reach like the seed shot; the plan is built there.
	s.close()
	var far: RefCounted = fresh()
	far.sow_width = 1
	var target: Vector2 = far.water_preview(far.position + Vector2(200, 0)).target
	check("aim_limited_to_reach_50", absf(far.position.distance_to(target) - 50.0) < 0.001)
	var cell: Vector2i = Coords.logic_to_cell(target)
	far.state.set_stage(far.state.index_of(cell.x, cell.y), WorldState.STAGE_SEED)
	var fr: Dictionary = far.water_at(far.position + Vector2(200, 0))
	check("far_aim_waters_at_reach_limit", bool(fr.ok) and far.state.moisture[far.state.index_of(cell.x, cell.y)] > 0 and is_equal_approx(far.water, 99.0))
	far.close()

func dirty_and_save() -> void:
	var s: RefCounted = fresh()
	s.sow_width = 3
	grow(s, Rect2i(CENTER - Vector2i(1, 1), Vector2i(3, 3)))
	s.state.clear_dirty()
	s.water_at(aim(CENTER))
	check("watered_cells_marked_dirty_for_renderer", s.state.dirty_tiles.size() == 9)
	s.unlocked["clover"] = true
	s.state.set_stage(s.state.index_of(CENTER.x + 3, CENTER.y), WorldState.STAGE_MATURE)
	s.place_plant("clover", CENTER + Vector2i(3, 0))
	s.sow_width = 1
	s.position = Coords.cell_center_logic(CENTER + Vector2i(1, 0))
	s.water_at(aim(CENTER + Vector2i(3, 0)))
	var data: Dictionary = s.to_dict()
	var restored: RefCounted = Session.new()
	var r: Dictionary = restored.restore(JSON.parse_string(JSON.stringify(data)))
	var wet: int = 0
	for y: int in range(CENTER.y - 1, CENTER.y + 2):
		for x: int in range(CENTER.x - 1, CENTER.x + 2):
			if restored.state.moisture[restored.state.index_of(x, y)] > 0: wet += 1
	var crop_wet: bool = restored.plants.size() == 1 and bool(restored.plants[0].watered)
	check("save_restore_keeps_wet_grass_and_watered_crop", bool(r.ok) and wet == 9 and crop_wet and is_equal_approx(restored.water, s.water), {"restore": r, "wet": wet})
	restored.close()
	s.close()

func sprinkler() -> void:
	check("sprinkler_radius_constants", Work.SPRINKLER_WORK_RADIUS == 120.0 and Work.WORK_RADIUS == 60.0, {"was": 60.0, "now": Work.SPRINKLER_WORK_RADIUS})
	var home: Vector2 = Vector2(100, 100)
	var helper: Dictionary = {"home": home, "pos": home, "job_kind": "", "job_id": -1}
	var near: Array[Dictionary] = [{"tile": 1, "pos": home + Vector2(100, 0), "growing": true, "watered": false}]
	var far: Array[Dictionary] = [{"tile": 2, "pos": home + Vector2(130, 0), "growing": true, "watered": false}]
	var none: Array[Dictionary] = []
	check("sprinkler_targets_100px_not_130px", Work.sprinkler_target(helper, none, near).get("kind", "") == "grass" and Work.sprinkler_target(helper, none, far).is_empty())
	check("army_gatlinger_radius_unchanged", Work.WORK_RADIUS == 60.0)
	# Real session: a sprinkler at (187,188) finds a dry growing cell 25 cells (100px) away.
	var s: RefCounted = fresh()
	s.unlocked["sprinkler"] = true
	var placed: Dictionary = s.place_helper("sprinkler", Vector2i(187, 188))
	var h: Dictionary = s.helpers[0]
	var tile: Vector2i = Vector2i(187 + 22, 188)
	for y: int in range(183, 193):
		for x: int in range(180, 205): s.state.set_stage(s.state.index_of(x, y), WorldState.STAGE_EMPTY)
	s.state.set_stage(s.state.index_of(tile.x, tile.y), WorldState.STAGE_SEED)
	var pos: Vector2 = s.plant_system._work_target(h, true)
	check("session_sprinkler_job_at_88px", bool(placed.ok) and pos == Coords.cell_center_logic(tile), {"pos": pos})
	var far_tile: Vector2i = Vector2i(187 + 31, 188)
	s.state.set_stage(s.state.index_of(tile.x, tile.y), WorldState.STAGE_EMPTY)
	s.state.set_stage(s.state.index_of(far_tile.x, far_tile.y), WorldState.STAGE_SEED)
	check("session_sprinkler_ignores_124px", s.plant_system._work_target(h, true).x < 0.0)
	s.close()

func timeline() -> void:
	var water_total: float = Timeline.total_ms(&"water")
	var seed_total: float = Timeline.total_ms(&"seed")
	check("timeline_totals_from_manifest", is_equal_approx(water_total, 800.0) and is_equal_approx(seed_total, 400.0) and is_equal_approx(Timeline.release_ms(&"water"), 400.0) and is_equal_approx(Timeline.release_ms(&"seed"), 66.0))
	var frames: Array[int] = []
	for ms: float in [0.0, 79.0, 80.0, 179.0, 180.0, 279.0, 280.0, 399.0, 400.0, 499.0, 500.0, 619.0, 620.0, 799.0]:
		frames.append(Timeline.frame_at(&"water", ms))
	check("water_frames_0_to_6_then_end", frames == [0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6] and Timeline.frame_at(&"water", 800.0) == -1 and Timeline.frame_at(&"water", 801.0) == -1, frames)
	check("seed_frames_0_to_3_then_end", Timeline.frame_at(&"seed", 65.0) == 0 and Timeline.frame_at(&"seed", 66.0) == 1 and Timeline.frame_at(&"seed", 399.0) == 3 and Timeline.frame_at(&"seed", 400.0) == -1)

func run() -> void:
	if not OS.get_user_data_dir().replace("\\", "/").contains("evidence/poc3/playtest01/self/profile/"):
		push_error("profile not isolated"); quit(1); return
	sizes(); shortage(); mixed(); no_effect(); dirty_and_save(); sprinkler(); timeline()
	var failures: int = 0
	for row: Dictionary in checks:
		if row.status == "FAIL": failures += 1
	var file: FileAccess = FileAccess.open(OUT + "logic_results.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": checks, "failures": failures, "passes": checks.size() - failures}, "  "))
	file.close()
	quit(1 if failures > 0 else 0)
