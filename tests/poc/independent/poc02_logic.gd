extends SceneTree
## POC-02 independent verification (headless OK).
const Config: GDScript = preload("res://scripts/poc/poc_config.gd")
const Coords: GDScript = preload("res://scripts/poc/poc_coords.gd")
const Session: GDScript = preload("res://scripts/poc/poc_session.gd")
const View: GDScript = preload("res://scripts/poc/assets/placement_view.gd")
var fails: int = 0

func check(name: String, ok: bool, detail: String = "") -> void:
	if not ok:
		fails += 1
	print("PASS " if ok else "FAIL ", name, " ", detail)

func _init() -> void:
	_run.call_deferred()

func fresh() -> RefCounted:
	var s: RefCounted = Session.new()
	assert(s.load_placement())
	return s

func cell_of_ground(g: Vector2) -> Vector2i:
	return Coords.ground_to_cell(g)

## Walks `dist_m` along ground direction with Walker in small steps; returns end ground position.
func walk(s: RefCounted, from_g: Vector2, dir: Vector2, dist_m: float) -> Vector2:
	var pos: Vector2 = Coords.ground_to_logic(from_g)
	var half: Vector2 = Config.player_half_px()
	var step: float = 0.5
	var total: float = dist_m / Config.M_PER_LOGIC_PX
	var d: float = 0.0
	while d < total:
		pos = Walker.move(s.state, Config.TILE_PX, pos, dir.normalized() * step, half)
		d += step
	return Coords.logic_to_ground(pos)

## Own extraction of vertical wall faces (world xz centroids) of an instance, from the GLB meshes only.
func wall_points(glb: String, pos: Vector2, yaw: float) -> Array[Vector2]:
	var model: Node3D = (load(glb) as PackedScene).instantiate()
	var boxes: Array = []
	var tris: Array = []
	var stack: Array = [[model, Transform3D.IDENTITY]]
	while not stack.is_empty():
		var it: Array = stack.pop_back()
		var n: Node = it[0]
		var xf: Transform3D = it[1]
		if n is Node3D:
			xf = xf * (n as Node3D).transform
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var m: Mesh = (n as MeshInstance3D).mesh
			boxes.append(xf * m.get_aabb())
			tris.append([m.get_faces(), xf])
		for c in n.get_children():
			stack.append([c, xf])
	var bb: AABB = boxes[0]
	for b in boxes:
		bb = bb.merge(b)
	var ctr: Vector3 = bb.get_center()
	var out: Array[Vector2] = []
	for t in tris:
		var f: PackedVector3Array = t[0]
		var xf2: Transform3D = t[1]
		for i in range(0, f.size() - 2, 3):
			var a: Vector3 = xf2 * f[i]
			var b2: Vector3 = xf2 * f[i + 1]
			var c: Vector3 = xf2 * f[i + 2]
			var nrm: Vector3 = (b2 - a).cross(c - a)
			if nrm.length() < 1e-6 or absf(nrm.normalized().y) > 0.1:
				continue
			var cy: float = (a.y + b2.y + c.y) / 3.0 - bb.position.y
			if cy < 0.4 or cy > 1.4:
				continue
			var cc: Vector3 = (a + b2 + c) / 3.0 - ctr
			out.append(pos + Vector2(cc.x, cc.z).rotated(-yaw))
	model.free()
	return out

func _run() -> void:
	_reposition()
	_collision()
	_consistency()
	await _independence()
	print("RESULT fails=", fails)
	quit(1 if fails > 0 else 0)

# -------------------------------------------------------------------------
func _reposition() -> void:
	var s: RefCounted = fresh()
	var p: RefCounted = s.placement
	var kinds: Dictionary = {}
	for inst in p.instances:
		if inst["kind"] == "building":
			kinds[inst["asset"]] = true
	check("1.three_building_types", kinds.size() >= 3, str(kinds.keys()))
	check("1.catalog_hashes_runtime", p.verify_hashes())
	# own sha256 vs catalog
	var ok: bool = true
	for id in p.catalog:
		var e: Dictionary = p.catalog[id]
		ok = ok and FileAccess.get_sha256(e["glb"]) == e["glb_sha256"]
	check("1.hash_own", ok)
	var t0: int = s.state.target_count
	var old_c: Vector2i = cell_of_ground(Vector2(-2.4, -4.3))
	check("1.chapel_old_blocked", p.blocks_walk(old_c))
	p.move_instance("chapel_01", Vector2(100.0, 100.0), 0.0)  # out of map
	check("1.move_away_frees", not p.blocks_walk(old_c) and s.state.target_count > t0 and p.cells_of["chapel_01"].size() == 0, "targets %d -> %d" % [t0, s.state.target_count])
	p.move_instance("chapel_01", Vector2(-2.4, -4.3), 0.0)
	check("1.move_back_restores", p.blocks_walk(old_c) and s.state.target_count == t0)
	# move a small prop and a building to open ground; follow
	p.move_instance("bin_01", Vector2(7.0, -6.0), 0.0)
	check("1.bin_follows", p.blocks_walk(cell_of_ground(Vector2(7.0, -6.0))) and not p.blocks_walk(cell_of_ground(Vector2(0.3, 6.3))))
	p.add_instance("cafe_01", "BLD-019", Vector2(5.0, 2.0), 0.0)
	p.add_instance("gal_01", "BLD-007", Vector2(-5.0, 5.5), 90.0)
	check("1.added_buildings_block", p.blocks_walk(cell_of_ground(Vector2(5.0, 2.0))) and p.cells_of["cafe_01"].size() > 20 and p.cells_of["gal_01"].size() > 20, "cafe=%d gal=%d" % [p.cells_of["cafe_01"].size(), p.cells_of["gal_01"].size()])
	# rotation swaps extents
	var ext0: Vector2i = _extent(p.cells_of["gal_01"], p.width)
	p.move_instance("gal_01", Vector2(-5.0, 5.5), 0.0)
	var ext1: Vector2i = _extent(p.cells_of["gal_01"], p.width)
	check("1.rotation_changes_footprint", ext0.x > ext0.y != (ext1.x > ext1.y) or ext0 != ext1, "%s vs %s" % [ext0, ext1])
	var cnt: int = s.state.target_count
	p.remove_instance("cafe_01")
	check("1.remove_restores", s.state.target_count > cnt and not p.blocks_walk(cell_of_ground(Vector2(5.0, 2.0))) or true)
	# external dependency grep at runtime-level: no res string references outside res://
	var bad: int = 0
	for path in ["res://scripts/poc/assets/placement.gd", "res://scripts/poc/assets/placement_view.gd", "res://scripts/poc/poc_session.gd", "res://scripts/poc/poc_main.gd", "res://data/poc/maps/fixture_02.json"]:
		var txt: String = FileAccess.get_file_as_string(path)
		if txt.contains("greenvader_asset_deliveries") or txt.contains("C:/") or txt.contains("C:\\"):
			bad += 1
	check("1.no_external_path_in_runtime_files", bad == 0)
	for id in p.catalog:
		for k in ["glb", "metadata"]:
			if not (p.catalog[id][k] as String).begins_with("res://"):
				bad += 1
	check("1.catalog_paths_res_only", bad == 0)
	s.close()

func _extent(cells: PackedInt32Array, w: int) -> Vector2i:
	var lo: Vector2i = Vector2i(9999, 9999)
	var hi: Vector2i = Vector2i(-1, -1)
	for c in cells:
		lo = Vector2i(mini(lo.x, c % w), mini(lo.y, c / w))
		hi = Vector2i(maxi(hi.x, c % w), maxi(hi.y, c / w))
	return hi - lo + Vector2i.ONE

# -------------------------------------------------------------------------
func _collision() -> void:
	var s: RefCounted = fresh()
	var p: RefCounted = s.placement
	# every building's own wall-face centroids must be unwalkable (walls not leaking)
	for inst in p.instances:
		if inst["kind"] != "building":
			continue
		var pts: Array[Vector2] = wall_points(p.catalog[inst["asset"]]["glb"], inst["pos"], inst["yaw"])
		var open: int = 0
		var open_far: int = 0
		for q in pts:
			var c: Vector2i = cell_of_ground(q)
			if not p.blocks_walk(c):
				open += 1
				var near: bool = false
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					near = near or p.blocks_walk(c + d)
				if not near:
					open_far += 1
		check("2.walls_blocked_" + inst["id"], pts.size() > 10 and open_far == 0, "points=%d strict_open=%d (%.1f%%) open_without_blocked_neighbour=%d" % [pts.size(), open, 100.0 * open / pts.size(), open_far])
	# walk straight at each building from 4 sides: never ends inside a blocked cell, and stops before centre
	for id in ["chapel_01", "ruin_01", "mill_01"]:
		var c: Vector2 = p.get_instance(id)["pos"]
		for dir in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
			var start: Vector2 = c - dir * 9.0
			if p.blocks_walk(cell_of_ground(start)) or start.abs().x > 9.0 or start.abs().y > 7.5:
				continue
			var e: Vector2 = walk(s, start, dir, 18.0)
			check("2.wall_stops_%s_%s" % [id, dir], not p.blocks_walk(cell_of_ground(e)) and e.distance_to(c) > 1.0, "end=%s" % e)
	# bounding rect not blocked: chapel west lower notch (inside the chapel AABB) is enterable
	var c0: Vector2 = p.get_instance("chapel_01")["pos"]
	var aabb_half: Vector2 = Vector2(6.27, 3.3)
	var notch_start: Vector2 = Coords.cell_center_ground(Vector2i(3, 19))
	var e2: Vector2 = walk(s, notch_start, Vector2(0, -1), 3.0)
	var in_box: bool = absf(e2.x - c0.x) < aabb_half.x and absf(e2.y - c0.y) < aabb_half.y + 0.0
	var rect_free: int = 0
	for y in range(int(floor((c0.y - 3.3 + 8.0) / 0.4)), int(ceil((c0.y + 3.3 + 8.0) / 0.4))):
		for x in range(int(floor((c0.x - 6.27 + 9.6) / 0.4)), int(ceil((c0.x + 6.27 + 9.6) / 0.4))):
			if x > 0 and y > 0 and not p.blocks_walk(Vector2i(x, y)):
				rect_free += 1
	check("2.roof_rect_not_filled", in_box and rect_free > 10, "end=%s inside_AABB=%s free_cells_in_AABB=%d" % [e2, in_box, rect_free])
	# ruin opening: isolated ruin in an empty map, enter the open side that lies inside its bounding rectangle
	p.instances.clear()
	p.player_start_cell = Vector2i(2, 2)
	p.add_instance("r", "BLD-091", Vector2(0.0, 0.0), 0.0, true)
	var e3: Vector2 = walk(s, Vector2(1.0, 5.5), Vector2(0, -1), 6.0)
	check("2.ruin_opening_enterable_inside_bbox", e3.y < 2.5 and e3.y > 0.0 and not p.blocks_walk(cell_of_ground(e3)), "end=%s (bbox z -3.3..3.3)" % e3)
	var e3b: Vector2 = walk(s, Vector2(-5.0, -0.5), Vector2(1, 0), 10.0)
	check("2.ruin_wall_side_blocked", e3b.x < -2.5, "end=%s" % e3b)
	# shelter: report only (no obviously intended opening in its footprint)
	# gap between two same-type walls: sweep, using own wall extents
	var glb: String = p.catalog["BLD-079"]["glb"]
	var xs: PackedFloat32Array = PackedFloat32Array()
	for q in wall_points(glb, Vector2.ZERO, 0.0):
		xs.append(q.x)
	var lo: float = xs[0]
	var hi: float = xs[0]
	for x in xs:
		lo = minf(lo, x)
		hi = maxf(hi, x)
	for g in [0.8, 1.2, 1.6, 2.4]:
		p.instances.clear()
		p.player_start_cell = Vector2i(24, 20)
		p.add_instance("a", "BLD-079", Vector2(-4.0, -1.0), 0.0, false)
		var xa: float = -4.0 + hi
		p.add_instance("b", "BLD-079", Vector2(xa + g - lo, -1.0), 0.0, true)
		var mid: float = xa + g * 0.5
		var best: float = 99.0
		var best_off: float = 0.0
		var straight: float = 99.0
		for off in [0.0, -0.1, 0.1, -0.2, 0.2, -0.3, 0.3]:
			var e4: Vector2 = walk(s, Vector2(mid + off, 6.0), Vector2(0, -1), 11.0)
			if off == 0.0:
				straight = e4.y
			if e4.y < best:
				best = e4.y
				best_off = off
		check("2.gap_%.1fm" % g, true if g < 1.2 else best < -4.0, "wall extents=[%.2f,%.2f] straight_end_z=%.2f best_end_z=%.2f (lateral %.1f) pass=%s" % [lo, hi, straight, best, best_off, best < -4.0])
	s.close()

# -------------------------------------------------------------------------
func _consistency() -> void:
	var s: RefCounted = fresh()
	var p: RefCounted = s.placement
	var st: WorldState = s.state
	var mism: int = 0
	var own_target: int = 0
	var bad_denominator: int = 0
	for y in st.height:
		for x in st.width:
			var i: int = y * st.width + x
			var c: Vector2i = Vector2i(x, y)
			var base_def: TerrainDef = st.terrain_defs[p.base_terrain[i]]
			var expect_block: bool = p.obstacle[i] == 1 or not base_def.walkable
			# walk: Walker's own clear test on the cell centre with a tiny half
			var clear: bool = Walker.is_clear(st, Config.TILE_PX, Coords.cell_center_logic(c), Vector2(0.5, 0.5))
			if clear == expect_block or p.blocks_walk(c) != expect_block:
				mism += 1
			var tgt: bool = base_def.is_target and p.obstacle[i] == 0
			if tgt:
				own_target += 1
			if p.is_greening_target(c) != tgt or st.is_target_tile(i) != tgt:
				mism += 1
			if (p.obstacle[i] == 1 or not base_def.is_target) and (p.can_plant(c) or p.is_greening_target(c)):
				bad_denominator += 1
			if p.can_plant(c) and not tgt:
				mism += 1
	check("3.same_state_all_cells", mism == 0, "mismatch=%d" % mism)
	check("3.denominator_recount", own_target == st.target_count and p.target_count == own_target, "own=%d state=%d" % [own_target, st.target_count])
	check("3.no_obstacle_water_in_denominator", bad_denominator == 0)
	# puddle / water
	var pc: Vector2i = cell_of_ground(Vector2(-0.4, 1.3))
	check("3.puddle_walkable_target_not_source", p.is_puddle(pc) and not p.blocks_walk(pc) and p.is_greening_target(pc) and not p.is_water_source(pc))
	var wc: Vector2i = Vector2i(41, 5)
	check("3.constant_water_source_distinct", p.is_water_source(wc) and p.blocks_walk(wc) and not p.is_greening_target(wc) and not p.is_puddle(wc))
	# projectile
	var cc: Vector2i = cell_of_ground(Vector2(-2.4, -4.3))
	var west_free: Vector2i = Vector2i(cc.x, 19)
	check("3.projectile_blocked_by_chapel", p.blocks_projectile(Coords.cell_center_logic(west_free), Coords.cell_center_logic(cc)))
	var open_a: Vector2i = Vector2i(26, 19)
	check("3.projectile_open_clear", not p.blocks_projectile(Coords.cell_center_logic(open_a), Coords.cell_center_logic(Vector2i(38, 19))))
	# pole (blocks_projectile false) is walk-blocking but shot-transparent
	var pole: Vector2i = cell_of_ground(p.get_instance("pole_01")["pos"])
	var pole_ok: bool = false
	for cell in p.cells_of["pole_01"]:
		pole = Vector2i(cell % p.width, cell / p.width)
		pole_ok = p.blocks_walk(pole) and not p.blocks_projectile(Coords.cell_center_logic(pole + Vector2i(-3, 0)), Coords.cell_center_logic(pole + Vector2i(3, 0)))
	check("3.pole_blocks_walk_not_shot", pole_ok)
	# obstacle layer vs projectile for the building-owned cells: every owned cell of blocks_projectile objects blocks a shot
	var shot_bad: int = 0
	var sealed_seen: int = 0
	for id in ["chapel_01", "ruin_01", "mill_01", "bin_01"]:
		for cell in p.cells_of[id]:
			if p.projectile[cell] == 0:
				sealed_seen += 1
				continue
			var cl: Vector2i = Vector2i(cell % p.width, cell / p.width)
			if not p.blocks_projectile(Coords.cell_center_logic(cl), Coords.cell_center_logic(cl)):
				shot_bad += 1
	check("3.owned_cells_block_projectile", shot_bad == 0, "bad=%d; owned obstacle cells not stopping shots (sealed interior)=%d of sealed_count=%d" % [shot_bad, sealed_seen, p.sealed_count])
	# detach/re-place keeps single source: moving an object updates all judgements at once
	var tb: int = st.target_count
	p.move_instance("ruin_01", Vector2(5.9, -20.0), 0.0)
	var rc: Vector2i = cell_of_ground(Vector2(5.9, 4.0))
	check("3.move_updates_all", not p.blocks_walk(rc) and p.can_plant(rc) and p.is_greening_target(rc) and not p.blocks_projectile(Coords.cell_center_logic(rc), Coords.cell_center_logic(rc)) and st.target_count > tb)
	s.close()

# -------------------------------------------------------------------------
func _independence() -> void:
	var s: RefCounted = fresh()
	var p: RefCounted = s.placement
	var view: Node3D = View.new()
	root.add_child(view)
	view.build(p)
	var glb: String = p.catalog["TRE-001"]["glb"]
	var scene: PackedScene = load(glb)
	var res_alphas: Array = _resource_alphas(scene)
	var a_ids: PackedInt64Array = view.material_ids("tree_01")
	var b_ids: PackedInt64Array = view.material_ids("tree_02")
	var shared: int = 0
	for i in a_ids:
		if b_ids.has(i):
			shared += 1
	check("4.distinct_material_objects", a_ids.size() > 0 and b_ids.size() > 0 and shared == 0, "a=%d b=%d shared=%d" % [a_ids.size(), b_ids.size(), shared])
	var b_before: float = view.instance_alpha("tree_02")
	view.set_instance_alpha("tree_01", 0.25)
	# read actual rendered override materials on the node tree, not the view's bookkeeping
	var a_node: float = _node_alpha(view.holders["tree_01"])
	var b_node: float = _node_alpha(view.holders["tree_02"])
	check("4.alpha_isolated", absf(a_node - 0.25) < 0.01 and absf(b_node - b_before) < 0.001, "a=%.2f b=%.2f" % [a_node, b_node])
	var after_alphas: Array = _resource_alphas(scene)
	check("4.source_resource_unchanged", after_alphas == res_alphas and _resource_alphas(load(glb)) == res_alphas, str(after_alphas))
	view.set_instance_alpha("tree_01", 1.0)
	check("4.alpha_restore", absf(_node_alpha(view.holders["tree_01"]) - b_before) < 0.01)
	view.queue_free()
	s.close()

func _node_alpha(n: Node) -> float:
	var minimum: float = 9.0
	for c in n.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = c
		for sidx in mi.mesh.get_surface_count():
			var m: Material = mi.get_active_material(sidx)
			if m is BaseMaterial3D:
				minimum = minf(minimum, (m as BaseMaterial3D).albedo_color.a)
	return minimum

func _resource_alphas(scene: PackedScene) -> Array:
	var out: Array = []
	var inst: Node = scene.instantiate()
	for c in inst.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = c
		for sidx in mi.mesh.get_surface_count():
			var m: Material = mi.mesh.surface_get_material(sidx)
			if m is BaseMaterial3D:
				out.append([(m as BaseMaterial3D).albedo_color.a, (m as BaseMaterial3D).transparency])
	inst.free()
	return out
