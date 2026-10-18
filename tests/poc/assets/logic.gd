extends SceneTree
## POC-02 logic checks (headless OK):
## godot --headless --path <repo> --script res://tests/poc/assets/logic.gd
const Config: GDScript = preload("res://scripts/poc/poc_config.gd")
const Coords: GDScript = preload("res://scripts/poc/poc_coords.gd")
const Session: GDScript = preload("res://scripts/poc/poc_session.gd")
const Placement: GDScript = preload("res://scripts/poc/assets/placement.gd")
const PlacementView: GDScript = preload("res://scripts/poc/assets/placement_view.gd")

var failures: int = 0
var passes: int = 0

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
	_catalog_and_ids()
	_relocation()
	_walls_and_openings()
	_roof_not_box()
	_water_and_puddle()
	_projectile()
	_denominator()
	_shared_judgement()
	_material_isolation()
	print("RESULT passes=%d failures=%d" % [passes, failures])
	quit(1 if failures > 0 else 0)

func _fixture() -> Array:
	var session: RefCounted = Session.new()
	var ok: bool = session.load_placement()
	return [session, session.placement, ok]

func _cell_of(ground: Vector2) -> Vector2i:
	return Coords.ground_to_cell(ground)

## Moves the player feet from `from_g` towards `to_g` (ground m) with the shared Walker; true when it arrives.
func _walk_to(state: WorldState, from_g: Vector2, to_g: Vector2) -> bool:
	var pos: Vector2 = Coords.ground_to_logic(from_g)
	var goal: Vector2 = Coords.ground_to_logic(to_g)
	var half: Vector2 = Config.player_half_px()
	if not Walker.is_clear(state, Config.TILE_PX, pos, half):
		return false
	for i: int in 2000:
		var delta: Vector2 = goal - pos
		if delta.length() < 0.5:
			return true
		pos = Walker.move(state, Config.TILE_PX, pos, delta.limit_length(1.0), half)
	return (goal - pos).length() < 0.5

func _bbox_of(cells: PackedInt32Array, width: int) -> Rect2i:
	var lo: Vector2i = Vector2i(100000, 100000)
	var hi: Vector2i = Vector2i(-100000, -100000)
	for index: int in cells:
		lo = Vector2i(mini(lo.x, index % width), mini(lo.y, index / width))
		hi = Vector2i(maxi(hi.x, index % width), maxi(hi.y, index / width))
	return Rect2i(lo, hi - lo + Vector2i.ONE)

func _single(asset: String, pos: Vector2, yaw: float, start: Vector2i = Vector2i(40, 30), seal: bool = false) -> Array:
	var session: RefCounted = Session.new()
	var p: RefCounted = Placement.new()
	p.load_catalog()
	p.seal_enclosed = seal
	p.player_start_cell = start
	p.add_instance("a", asset, pos, yaw, false)
	p.attach(session.state, Session.open_base_terrain())
	return [session, p]

func _catalog_and_ids() -> void:
	var f: Array = _fixture()
	var p: RefCounted = f[1]
	check("fixture.loads", f[2] and p != null)
	check("catalog.hashes", p.verify_hashes(), "%d adopted assets" % p.catalog.size())
	var ids: Dictionary = {}
	var unique: bool = true
	for inst: Dictionary in p.instances:
		unique = unique and not ids.has(inst["id"])
		ids[inst["id"]] = true
	check("fixture.instance_ids_unique", unique and ids.size() == p.instances.size(), "%d instances" % ids.size())
	var shapes: Dictionary = {}
	for inst: Dictionary in p.instances:
		if inst["kind"] == "building":
			var box: Rect2i = _bbox_of(p.cells_of[inst["id"]], p.width)
			shapes[inst["asset"]] = [box.size, (p.cells_of[inst["id"]] as PackedInt32Array).size()]
	check("fixture.three_building_shapes", shapes.size() >= 3, str(shapes))
	var distinct: Dictionary = {}
	for key: String in shapes:
		distinct[str(shapes[key])] = true
	check("fixture.buildings_differ_in_shape", distinct.size() == shapes.size())
	var entry_ok: bool = true
	for id: String in p.catalog:
		var e: Dictionary = p.catalog[id]
		for field: String in ["collision", "greenable", "water_source", "vine_surfaces", "occlusion_group", "glb_sha256", "source"]:
			entry_ok = entry_ok and e.has(field)
		entry_ok = entry_ok and e["water_source"] == false and (e["glb"] as String).begins_with("res://assets/models/town_lab/")
	check("catalog.aux_fields_and_no_external_path", entry_ok)
	var has_vine: bool = false
	for id: String in ["BLD-007", "BLD-038"]:
		has_vine = has_vine or (p.catalog[id]["vine_surfaces"] as Array).size() > 0
	check("catalog.vine_surfaces_recorded", has_vine)
	f[0].close()

func _relocation() -> void:
	var a: Array = _single("BLD-091", Vector2(-3.07, -3.13), 0.0)
	var b: Array = _single("BLD-091", Vector2(-3.07 + 2.0, -3.13 + 1.2), 0.0)
	var cells_a: PackedInt32Array = a[1].cells_of["a"]
	var cells_b: PackedInt32Array = b[1].cells_of["a"]
	var shifted: Dictionary = {}
	for index: int in cells_a:
		shifted[index + 3 * 48 + 5] = true
	var same: bool = cells_a.size() == cells_b.size() and cells_a.size() > 20
	for index: int in cells_b:
		same = same and shifted.has(index)
	check("place.relocate_same_id_new_transform_moves_cells", same, "%d cells, shift (+5,+3)" % cells_a.size())
	var old_free: bool = true
	var new_busy: bool = true
	for index: int in cells_a:
		if not shifted.has(index):
			old_free = old_free and b[1].obstacle[index] == 0
	for index: int in cells_b:
		new_busy = new_busy and b[0].state.terrain[index] == b[1].building_id
	check("place.old_cells_released_new_cells_blocked", old_free and new_busy)
	var m1: Array = _single("BLD-079", Vector2(0, 0), 0.0)
	var m2: Array = _single("BLD-079", Vector2(0, 0), 90.0)
	var box1: Rect2i = _bbox_of(m1[1].cells_of["a"], 48)
	var box2: Rect2i = _bbox_of(m2[1].cells_of["a"], 48)
	check("place.yaw_90_swaps_extent", absi(box1.size.x - box2.size.y) <= 2 and absi(box1.size.y - box2.size.x) <= 2 and absi(box1.size.x - box1.size.y) >= 2, "yaw0 %s yaw90 %s" % [box1.size, box2.size])
	# Move through the editing API and back: the base terrain returns exactly.
	var before: PackedByteArray = a[0].state.terrain.duplicate()
	a[1].move_instance("a", Vector2(2.0, 2.0), 0.0)
	var moved: bool = a[0].state.terrain != before
	a[1].move_instance("a", Vector2(-3.07, -3.13), 0.0)
	check("place.move_and_back_restores_state", moved and a[0].state.terrain == before)
	a[1].remove_instance("a")
	check("place.remove_restores_base", a[0].state.terrain == Session.open_base_terrain() and a[0].state.target_count == a[1].target_count)
	for pair: Array in [a, b, m1, m2]:
		pair[0].close()

func _walls_and_openings() -> void:
	var f: Array = _fixture()
	var s: RefCounted = f[0]
	var p: RefCounted = f[1]
	var state: WorldState = s.state
	check("walk.start_cell_free", p.player_start_cell == Vector2i(24, 20) and not p.blocks_walk(p.player_start_cell))
	# Chapel (AABB x -8.68..3.88, z -7.6..-1.0): standing in the street south of it, walk straight north.
	var pos: Vector2 = Coords.ground_to_logic(Vector2(0.0, 0.2))
	var chapel_x: float = 0.0
	for i: int in 400:
		pos = Walker.move(state, Config.TILE_PX, pos, Vector2(0.0, -1.0), Config.player_half_px())
	var end_g: Vector2 = Coords.logic_to_ground(pos)
	check("walk.chapel_wall_stops_player", end_g.y > -0.8 and absf(end_g.x - chapel_x) < 0.01 and Walker.is_clear(state, Config.TILE_PX, pos, Config.player_half_px()), "ended at ground %s" % end_g)
	var cell_wall: Vector2i = _cell_of(Vector2(-2.4, -1.05))
	var cell_in_wall: bool = p.blocks_walk(cell_wall) or p.blocks_walk(cell_wall + Vector2i(0, -1))
	check("walk.exterior_wall_cells_blocked", cell_in_wall)
	check("walk.outer_ring_blocked", p.blocks_walk(Vector2i(0, 10)) and p.blocks_walk(Vector2i(47, 10)) and p.blocks_walk(Vector2i(10, 0)) and p.blocks_walk(Vector2i(10, 39)) and p.blocks_walk(Vector2i(-1, 5)))
	# Intended gaps: street between chapel and the mill, and between the mill and the ruin (1.0 m clear), plaza to east.
	check("walk.street_between_chapel_and_mill", _walk_to(state, Vector2(-7.0, 0.35), Vector2(1.0, 0.35)))
	check("walk.gap_between_buildings", _walk_to(state, Vector2(2.1, 1.2), Vector2(2.1, 6.4)))
	check("walk.plaza_to_east_side", _walk_to(state, Vector2(0.2, 0.2), Vector2(1.0, -0.4)) and _walk_to(state, Vector2(1.0, -0.4), Vector2(7.6, -0.4)))
	# Under the bus shelter roof (open front): the covered cell is walkable, and reachable from the plaza.
	var shelter_cell: Vector2i = _cell_of(Vector2(-0.2, 4.2))
	var shelter_half: Vector2 = Vector2(p.asset_shape("PRP-012")["size"].x, p.asset_shape("PRP-012")["size"].z) * 0.5
	var shelter_pos: Vector2 = p.get_instance("shelter_01")["pos"]
	var under_roof: bool = absf(Coords.cell_center_ground(shelter_cell).x - shelter_pos.x) < shelter_half.x and absf(Coords.cell_center_ground(shelter_cell).y - shelter_pos.y) < shelter_half.y
	check("walk.under_shelter_roof", under_roof and not p.blocks_walk(shelter_cell) and _walk_to(state, Vector2(-0.2, 4.8), Vector2(-0.2, 4.4)), "cell %s under the roof AABB" % shelter_cell)
	# Sealed interior: no way in through a closed wall.
	check("walk.cannot_enter_closed_building", not _walk_to(state, Vector2(0.2, 0.2), Vector2(5.9, 4.0)))
	# Small props block exactly their cell(s).
	var props_ok: bool = true
	for id: String in ["pole_01", "tree_01", "tree_02", "hydrant_01"]:
		var owned: PackedInt32Array = p.cells_of[id]
		props_ok = props_ok and owned.size() >= 1 and owned.size() <= 6
		for index: int in owned:
			props_ok = props_ok and p.blocks_walk(Vector2i(index % 48, index / 48)) and Coords.cell_center_ground(Vector2i(index % 48, index / 48)).distance_to(p.get_instance(id)["pos"]) < 1.2
	check("walk.small_props_block_few_cells", props_ok)
	f[0].close()

func _roof_not_box() -> void:
	var f: Array = _fixture()
	var p: RefCounted = f[1]
	var shape: Dictionary = p.asset_shape("BLD-038")
	var inst: Dictionary = p.get_instance("chapel_01")
	var half: Vector2 = Vector2(shape["size"].x, shape["size"].z) * 0.5
	var lo: Vector2i = _cell_of(inst["pos"] - half)
	var hi: Vector2i = _cell_of(inst["pos"] + half)
	var inside: int = 0
	var free_inside: int = 0
	for y: int in range(lo.y, hi.y + 1):
		for x: int in range(lo.x, hi.x + 1):
			inside += 1
			if not p.blocks_walk(Vector2i(x, y)):
				free_inside += 1
	check("roof.chapel_aabb_not_filled", free_inside >= 20 and free_inside < inside, "%d of %d cells inside the roof AABB are walkable" % [free_inside, inside])
	# BLD-007: long external gallery -> walkable ground under the gallery slab, reachable from outside (flood sealed).
	var g: Array = _single("BLD-007", Vector2(0.0, -3.9), 0.0, Vector2i(24, 28), true)
	var gp: RefCounted = g[1]
	var gs: Dictionary = gp.asset_shape("BLD-007")
	var ghalf: Vector2 = Vector2(gs["size"].x, gs["size"].z) * 0.5
	var glo: Vector2i = _cell_of(Vector2(0.0, -3.9) - ghalf)
	var ghi: Vector2i = _cell_of(Vector2(0.0, -3.9) + ghalf)
	var open_inside: int = 0
	var total: int = 0
	for y: int in range(glo.y, ghi.y + 1):
		for x: int in range(glo.x, ghi.x + 1):
			total += 1
			if not gp.blocks_walk(Vector2i(x, y)):
				open_inside += 1
	check("roof.gallery_aabb_has_walkable_ground", open_inside >= 15 and open_inside < total, "%d of %d cells walkable inside the BLD-007 roof AABB, sealed=%d" % [open_inside, total, gp.sealed_count])
	g[0].close()
	f[0].close()

func _water_and_puddle() -> void:
	var f: Array = _fixture()
	var p: RefCounted = f[1]
	var state: WorldState = f[0].state
	var wet: Vector2i = _cell_of(Vector2(-5.2, 0.2))
	var safe_wet: Vector2i = _cell_of(Vector2(-0.4, 1.3))
	check("puddle.walkable_target_plantable", p.is_puddle(wet) and not p.blocks_walk(wet) and p.is_greening_target(wet) and p.can_plant(wet) and p.is_puddle(safe_wet) and not p.blocks_walk(safe_wet) and p.is_greening_target(safe_wet), "cell %s (wasteland) / %s (on the safe patch, already green)" % [wet, safe_wet])
	check("puddle.not_a_water_source", not p.is_water_source(wet) and not p.is_water_source(_cell_of(Vector2(-5.2, 0.2))))
	var pond: Vector2i = Vector2i(41, 5)
	var shore: Vector2i = Vector2i(38, 5)
	check("water.terrain_blocks_walk_not_target", state.terrain_def_at(pond.y * 48 + pond.x).key == &"water" and p.blocks_walk(pond) and not p.is_greening_target(pond) and p.is_water_source(pond))
	check("water.shore_is_source_and_target", state.terrain_def_at(shore.y * 48 + shore.x).key == &"shore" and p.is_water_source(shore) and p.is_greening_target(shore) and not p.blocks_walk(shore))
	var puddle_count: int = 0
	var puddle_blocking: int = 0
	for i: int in 48 * 40:
		if p.puddle[i] == 1:
			puddle_count += 1
			if p.obstacle[i] == 1:
				puddle_blocking += 1
	check("puddle.cells_exist_never_obstacles", puddle_count > 8 and puddle_blocking == 0, "%d puddle cells" % puddle_count)
	f[0].close()

func _projectile() -> void:
	var f: Array = _fixture()
	var p: RefCounted = f[1]
	var origin: Vector2 = Coords.ground_to_logic(Vector2(0.2, 0.2))
	var behind: Vector2 = Coords.ground_to_logic(Vector2(-2.4, -6.0))
	check("shot.through_wall_blocked", p.blocks_projectile(origin, behind) and p.blocks_projectile(behind, origin))
	check("shot.clear_corridor_open", not p.blocks_projectile(Coords.ground_to_logic(Vector2(-4.0, 0.3)), Coords.ground_to_logic(Vector2(1.0, 0.3))))
	check("shot.diagonal_clear_plaza", not p.blocks_projectile(Coords.ground_to_logic(Vector2(-1.0, 0.4)), Coords.ground_to_logic(Vector2(2.0, 6.0))))
	check("shot.over_tree_pole_hydrant_not_blocked", not p.blocks_projectile(Coords.ground_to_logic(Vector2(4.4, -1.8)), Coords.ground_to_logic(Vector2(8.4, -1.8))) and not p.blocks_projectile(Coords.ground_to_logic(Vector2(0.8, 0.2)), Coords.ground_to_logic(Vector2(2.6, 0.2))))
	check("shot.over_water_open", not p.blocks_projectile(Coords.ground_to_logic(Vector2(5.2, -5.8)), Coords.ground_to_logic(Vector2(8.8, -5.8))))
	check("shot.outside_map_blocked", p.blocks_projectile(origin, Coords.ground_to_logic(Vector2(30.0, 0.2))))
	check("shot.ruin_wall_blocked", p.blocks_projectile(Coords.ground_to_logic(Vector2(0.2, 5.0)), Coords.ground_to_logic(Vector2(8.0, 5.0))))
	f[0].close()

func _denominator() -> void:
	var f: Array = _fixture()
	var s: RefCounted = f[0]
	var p: RefCounted = f[1]
	var state: WorldState = s.state
	var expected: int = 0
	var base: PackedByteArray = Session.open_base_terrain()
	var base_target_cells: int = 0
	for i: int in 48 * 40:
		var def: TerrainDef = state.terrain_defs[base[i]]
		if def.is_target:
			base_target_cells += 1
			if p.obstacle[i] == 0:
				expected += 1
	check("denominator.excludes_obstacles", state.target_count == expected and state.recount_targets() == expected and p.target_count == expected and state.counters_consistent(), "target_count=%d expected=%d (open terrain %d)" % [state.target_count, expected, base_target_cells])
	var leaks: int = 0
	for i: int in 48 * 40:
		if p.obstacle[i] == 1 and state.target[i] == 1:
			leaks += 1
	check("denominator.no_target_on_obstacle", leaks == 0 and expected < base_target_cells)
	p.detach()
	check("denominator.detach_restores_base", state.terrain == base and state.target_count == base_target_cells)
	f[0].close()

func _shared_judgement() -> void:
	var f: Array = _fixture()
	var s: RefCounted = f[0]
	var p: RefCounted = f[1]
	var state: WorldState = s.state
	var mismatches: int = 0
	var tiny: Vector2 = Vector2(0.5, 0.5)
	for y: int in 40:
		for x: int in 48:
			var center: Vector2 = Coords.cell_center_logic(Vector2i(x, y))
			var walker_clear: bool = Walker.is_clear(state, Config.TILE_PX, center, tiny)
			if walker_clear == p.blocks_walk(Vector2i(x, y)) or state.is_walkable(x, y) != not p.blocks_walk(Vector2i(x, y)):
				mismatches += 1
	check("shared.walker_enemy_mover_matches_blocks_walk", mismatches == 0, "all 1920 cells, mismatches=%d" % mismatches)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 11
	var bad: int = 0
	var boar_half: Vector2 = Vector2(5, 3)
	for i: int in 300:
		var point: Vector2 = Vector2(rng.randf_range(4, 188), rng.randf_range(4, 156))
		var x0: int = floori((point.x - boar_half.x + 1.0e-4) / 4.0)
		var x1: int = ceili((point.x + boar_half.x - 1.0e-4) / 4.0) - 1
		var y0: int = floori((point.y - boar_half.y + 1.0e-4) / 4.0)
		var y1: int = ceili((point.y + boar_half.y - 1.0e-4) / 4.0) - 1
		var any_blocked: bool = false
		for y: int in range(y0, y1 + 1):
			for x: int in range(x0, x1 + 1):
				any_blocked = any_blocked or p.blocks_walk(Vector2i(x, y))
		if any_blocked == Walker.is_clear(state, Config.TILE_PX, point, boar_half):
			bad += 1
	check("shared.boar_footprint_matches_blocks_walk", bad == 0, "300 random footprints, mismatches=%d" % bad)
	f[0].close()

func _material_isolation() -> void:
	var f: Array = _fixture()
	var p: RefCounted = f[1]
	var view: Node3D = PlacementView.new()
	view.build(p)
	var ids_a: PackedInt64Array = view.material_ids("tree_01")
	var ids_b: PackedInt64Array = view.material_ids("tree_02")
	var disjoint: bool = ids_a.size() > 0 and ids_a.size() == ids_b.size()
	for id: int in ids_a:
		disjoint = disjoint and not ids_b.has(id)
	check("material.same_glb_instances_own_materials", disjoint, "%d materials each" % ids_a.size())
	var before_b: float = view.instance_alpha("tree_02")
	view.set_instance_alpha("tree_01", 0.35)
	var a_alpha: float = view.instance_alpha("tree_01")
	var b_alpha: float = view.instance_alpha("tree_02")
	var untouched: bool = true
	for id: String in view.materials:
		if id != "tree_01":
			for material: BaseMaterial3D in view.materials[id]:
				untouched = untouched and absf(material.albedo_color.a - float(material.get_meta(&"base_alpha"))) < 0.0001 and material.transparency == int(material.get_meta(&"base_transparency"))
	check("material.alpha_is_per_instance", absf(a_alpha - 0.35) < 0.001 and absf(b_alpha - before_b) < 0.0001 and untouched, "tree_01=%f tree_02=%f" % [a_alpha, b_alpha])
	var shared_clean: bool = true
	var tree_scene: PackedScene = load(p.catalog["TRE-001"]["glb"]) as PackedScene
	var probe: Node3D = tree_scene.instantiate() as Node3D
	for child: Node in probe.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = child as MeshInstance3D
		for surface: int in mi.mesh.get_surface_count():
			var shared: Material = mi.mesh.surface_get_material(surface)
			if shared is BaseMaterial3D:
				shared_clean = shared_clean and (shared as BaseMaterial3D).transparency == BaseMaterial3D.TRANSPARENCY_DISABLED and (shared as BaseMaterial3D).albedo_color.a >= 0.999
	probe.free()
	check("material.shared_glb_resource_untouched", shared_clean)
	view.set_instance_alpha("tree_01", 1.0)
	check("material.alpha_restore", absf(view.instance_alpha("tree_01") - 1.0) < 0.001)
	view.free()
	f[0].close()
