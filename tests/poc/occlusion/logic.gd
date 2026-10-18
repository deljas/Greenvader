extends SceneTree
## POC-06 logic checks (headless OK):
## godot --headless --path <repo> --script res://tests/poc/occlusion/logic.gd
## Part A: synthetic geometry (gate with an opening, two gates, a corner). Part B: the real POC-02 fixture through the
## PoC scene (judgement, hysteresis, fade, restore, isolation, display-only, rebuild / resolution reset).
const Occlusion: GDScript = preload("res://scripts/poc/occlusion/occlusion.gd")
const Coords: GDScript = preload("res://scripts/poc/poc_coords.gd")
## Camera direction of the PoC (elevation 30 deg, azimuth 45 deg): from the scene towards the camera.
const TO_CAMERA: Vector3 = Vector3(0.612372, 0.5, 0.612372)
const RIGHT: Vector3 = Vector3(0.707107, 0.0, -0.707107)

var failures: int = 0
var passes: int = 0
var main: Node

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
	_synthetic()
	await _fixture()
	print("RESULT passes=%d failures=%d" % [passes, failures])
	quit(1 if failures > 0 else 0)

# ---------------------------------------------------------------- A: synthetic

func _box_mesh(offsets: Array, size: Vector3) -> ArrayMesh:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var box: BoxMesh = BoxMesh.new()
	box.size = size
	for offset: Vector3 in offsets:
		st.append_from(box, 0, Transform3D(Basis.IDENTITY, offset))
	return st.commit()

func _gate(name: String, origin: Vector3, parent: Node3D) -> Dictionary:
	# Two pillars 1x3x1 at x = -1.5 / +1.5 around `origin`: the opening between them is 2 m wide and the AABB covers it.
	var node: MeshInstance3D = MeshInstance3D.new()
	node.name = name
	node.mesh = _box_mesh([Vector3(-1.5, 1.5, 0.0), Vector3(1.5, 1.5, 0.0)], Vector3(1.0, 3.0, 1.0))
	parent.add_child(node)
	node.global_position = origin
	return {"group": name, "ids": [name], "parts": [Occlusion.make_part(node, {})]}

func _synthetic() -> void:
	var holder: Node3D = Node3D.new()
	root.add_child(holder)
	var occ: RefCounted = Occlusion.new()
	# Synthetic camera: looks along -Z from +Z with 30 degrees elevation (rays go +Z and up, no sideways drift).
	var dir: Vector3 = Vector3(0.0, 0.5, 0.866025)
	var right: Vector3 = Vector3.RIGHT
	var gate_a: Dictionary = _gate("gate_a", Vector3.ZERO, holder)
	var gate_b: Dictionary = _gate("gate_b", Vector3(3.0, 0, 1.5), holder)
	occ.set_entries([gate_a, gate_b])
	var part: Dictionary = gate_a["parts"][0]
	var height: float = 1.42
	var foot: Vector3 = Vector3(0, 0, -3.0)
	var through: Vector3 = foot + Vector3.UP * 0.7
	check("syn.aabb_coarse_hit_but_opening", (part["aabb"] as AABB).intersects_segment(through, through + dir * 70.0) != null, "AABB covers the opening")
	var raw: Dictionary = occ.raw_occluders(occ.sample_points(foot, height, right), dir)
	check("syn.opening_not_detected", not raw.has("gate_a"), str(raw.keys()))
	raw = occ.raw_occluders(occ.sample_points(Vector3(1.5, 0, -3.0), height, right), dir)
	check("syn.behind_pillar_detected", raw.has("gate_a"), str(raw.keys()))
	raw = occ.raw_occluders(occ.sample_points(Vector3(1.5, 0, 3.0), height, right), dir)
	check("syn.in_front_of_gate_a_not_detected", raw.is_empty(), str(raw.keys()))
	raw = occ.raw_occluders(occ.sample_points(Vector3(1.5, 0, -3.0), height, right), dir)
	check("syn.two_groups_at_once", raw.has("gate_a") and raw.has("gate_b"), str(raw.keys()))
	raw = occ.raw_occluders(occ.sample_points(Vector3(4.5, 0, -3.0), height, right), dir)
	check("syn.only_second_gate_when_first_missed", raw.has("gate_b") and not raw.has("gate_a"), str(raw.keys()))
	var between_ok: bool = true
	for i: int in 60:
		var r: Dictionary = occ.raw_occluders(occ.sample_points(Vector3(-3.0 + float(i) * 0.1, 0, 0.75), height, right), dir)
		between_ok = between_ok and not r.has("gate_a")
	check("syn.between_gates_ignores_far_gate", between_ok)
	# corner of the left pillar (x in [-2,-1]): the opening side is x > -1. Torso lateral margin is 0.2 m.
	var edge_miss: Dictionary = occ.raw_occluders(occ.sample_points(Vector3(-0.7, 0, -3.0), height, right), dir)
	var edge_hit: Dictionary = occ.raw_occluders(occ.sample_points(Vector3(-0.85, 0, -3.0), height, right), dir)
	check("syn.corner_margin", not edge_miss.has("gate_a") and edge_hit.has("gate_a"), "miss=%s hit=%s" % [str(edge_miss.keys()), str(edge_hit.keys())])
	holder.free()

# ---------------------------------------------------------------- B: fixture

func _frames(n: int) -> void:
	for i: int in n:
		await process_frame

func _open() -> void:
	main = load("res://scenes/poc.tscn").instantiate()
	root.add_child(main)
	main.auto_process = false
	main.window_size_override = Vector2i(1920, 1080)
	await _frames(2)

func _behind(id: String, k: float) -> Vector3:
	var p: Vector2 = main.session.placement.get_instance(id)["pos"]
	return Vector3(p.x - 0.5 * k * 0.707107, 0.04, p.y - 0.5 * k * 0.707107)

func _raw(foot: Vector3) -> Array:
	var ov: Node = main.occlusion_view
	var keys: Array = ov.occlusion.raw_occluders(ov.occlusion.sample_points(foot, 1.42, RIGHT), TO_CAMERA).keys()
	keys.sort()
	return keys

func _run_for(foot: Vector3, seconds: float) -> void:
	var steps: int = int(seconds / 0.05)
	for i: int in steps:
		main.occlusion_view.update(0.05, foot, 1.42)

func _materials_signature() -> String:
	var parts: PackedStringArray = PackedStringArray()
	var pv: Node3D = main.placement_view
	for id: String in pv.holders:
		if not pv.materials.has(id):
			continue
		for material: BaseMaterial3D in pv.materials[id]:
			parts.append("%s:%d/%d/%s" % [id, material.transparency, material.depth_draw_mode, str(material.albedo_color)])
		for child: Node in (pv.holders[id] as Node3D).find_children("*", "MeshInstance3D", true, false):
			var mi: MeshInstance3D = child as MeshInstance3D
			parts.append("%s:%s:%d/%d" % [id, mi.name, mi.cast_shadow, mi.layers])
	return "\n".join(parts)

func _world_signature() -> String:
	var s: RefCounted = main.session
	var p: RefCounted = s.placement
	return "%d/%d/%d/%d/%d/%d/%d" % [hash(s.state.terrain), hash(s.state.target), hash(s.state.stage), s.state.target_count, s.state.greened_count, hash(p.obstacle), hash(p.puddle)]

func _alpha(id: String) -> float:
	return main.placement_view.instance_alpha(id)

func _veg_transparency(id: String) -> float:
	var group: Node3D = main.wall_view.group_of(id)
	if group == null:
		return -1.0
	var worst: float = 0.0
	for child: Node in group.find_children("*", "GeometryInstance3D", true, false):
		worst = maxf(worst, (child as GeometryInstance3D).transparency)
	return worst

func _copy_count() -> int:
	var n: int = 0
	for node: Node in main.placement_view.find_children("Occ*", "MeshInstance3D", true, false):
		n += 1
	return n

func _fixture() -> void:
	await _open()
	var ov: Node = main.occlusion_view
	check("fx.view_present", ov != null and ov.occlusion.entries.size() == 9, "groups=%d" % ov.occlusion.entries.size())
	main.session.position = Coords.cell_center_logic(Vector2i(24, 38))
	main.tick(0.0, Vector2.ZERO)
	main.tick(1.0, Vector2.ZERO)
	check("fx.base_masks", main.camera.cull_mask & 16 == 0 and main.water_view.reflection_camera.cull_mask == 1, "cam=%d refl=%d" % [main.camera.cull_mask, main.water_view.reflection_camera.cull_mask])
	var base_materials: String = _materials_signature()
	var base_world: String = _world_signature()
	var base_walk: int = 0
	for y: int in main.session.state.height:
		for x: int in main.session.state.width:
			base_walk += 1 if main.session.state.is_walkable(x, y) and main.session.placement.can_plant(Vector2i(x, y)) else 0
	# ---- judgement
	var behind_ruin: Vector3 = _behind("ruin_01", 6.0)
	check("fx.behind_ruin_only_ruin", _raw(behind_ruin) == ["ruin_01"], str(_raw(behind_ruin)))
	check("fx.in_front_of_ruin_none", _raw(_behind("ruin_01", -8.0)).is_empty(), str(_raw(_behind("ruin_01", -8.0))))
	var behind_tree: Vector3 = _behind("tree_01", 3.0)
	check("fx.behind_tree_01_only_tree_01", _raw(behind_tree) == ["tree_01"], str(_raw(behind_tree)))
	check("fx.beside_tree_01_none", _raw(behind_tree + Vector3(3.0, 0, -3.0)).is_empty() or not _raw(behind_tree + Vector3(3.0, 0, -3.0)).has("tree_01"), str(_raw(behind_tree + Vector3(3.0, 0, -3.0))))
	check("fx.two_groups_chapel_and_tree", _raw(_behind("tree_01", 8.0)) == ["chapel_01", "tree_01"], str(_raw(_behind("tree_01", 8.0))))
	check("fx.tree_02_behind_mill_and_tree", _raw(_behind("tree_02", 2.0)) == ["mill_01", "tree_02"], str(_raw(_behind("tree_02", 2.0))))
	# front of the building: walking along the camera direction leaves the occlusion.
	var left: bool = false
	var entered: bool = false
	for k: int in range(10, -16, -1):
		var r: Array = _raw(_behind("ruin_01", float(k)))
		if r.has("ruin_01"):
			entered = true
		elif entered:
			left = true
			break
	check("fx.stepping_out_front_clears", entered and left)
	# ---- fade through the real tick path (player position on a walkable cell)
	var s: RefCounted = main.session
	s.position = Coords.ground_to_logic(Vector2(behind_ruin.x, behind_ruin.z))
	for i: int in 12:
		main.tick(0.05, Vector2.ZERO)
	var ruin_alpha: float = _alpha("ruin_01")
	check("fx.fade_target_alpha", absf(ruin_alpha - float(ov.occlusion.tuning["target_alpha"])) < 0.01 and ov.occlusion.occluded_groups() == PackedStringArray(["ruin_01"]), "alpha=%f groups=%s" % [ruin_alpha, str(ov.occlusion.occluded_groups())])
	var others_clean: bool = true
	for id: String in main.placement_view.materials:
		if id != "ruin_01":
			others_clean = others_clean and absf(_alpha(id) - 1.0) < 0.0001
	check("fx.others_untouched_incl_same_glb", others_clean and absf(_alpha("tree_02") - 1.0) < 0.0001)
	var fade_ok: bool = ov.faded_instances() == PackedStringArray(["ruin_01"]) and _copy_count() > 0
	var shadow_copy: bool = false
	var reflect_copy: bool = false
	for node: Node in main.placement_view.find_children("Occ*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = node as MeshInstance3D
		shadow_copy = shadow_copy or (mi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY and mi.layers == 8)
		reflect_copy = reflect_copy or (mi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and mi.layers == 16)
	check("fx.shadow_and_reflection_copies", fade_ok and shadow_copy and reflect_copy and main.water_view.reflection_camera.cull_mask == 1 and ov.reflection_mask_during_draw() == 17 and main.camera.cull_mask & 16 == 0, "copies=%d mask between frames=%d during draw=%d" % [_copy_count(), main.water_view.reflection_camera.cull_mask, ov.reflection_mask_during_draw()])
	var display_off: bool = true
	for node: Node in main.placement_view.holders["ruin_01"].find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = node as MeshInstance3D
		if not mi.name.begins_with("Occ"):
			display_off = display_off and mi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat_ok: bool = true
	for material: BaseMaterial3D in main.placement_view.materials["ruin_01"]:
		mat_ok = mat_ok and material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA and material.depth_draw_mode == BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY
	check("fx.display_faded_materials", display_off and mat_ok)
	print("INFO vegetation ids=", main.wall_view.instance_ids())
	check("fx.display_only_world_unchanged", _world_signature() == base_world)
	# ---- hysteresis: oscillate across the boundary (bisect along the camera direction)
	var lo: float = -8.0
	var hi: float = 6.0
	for i: int in 24:
		var mid: float = (lo + hi) * 0.5
		if _raw(_behind("ruin_01", mid)).has("ruin_01"):
			hi = mid
		else:
			lo = mid
	var inside: Vector3 = _behind("ruin_01", hi + 0.02)
	var outside: Vector3 = _behind("ruin_01", lo - 0.02)
	check("fx.boundary_found", _raw(inside).has("ruin_01") and not _raw(outside).has("ruin_01"), "k=%f" % hi)
	ov.reset()
	_run_for(inside, 1.0)
	var flips: int = 0
	var last: bool = ov.occlusion.is_occluded("ruin_01")
	var alpha_min: float = 1.0
	var alpha_jump: float = 0.0
	var prev_alpha: float = ov.occlusion.alpha_of("ruin_01")
	for i: int in 80:
		ov.update(0.016, inside if i % 2 == 0 else outside, 1.42)
		var now: bool = ov.occlusion.is_occluded("ruin_01")
		flips += 1 if now != last else 0
		last = now
		alpha_min = minf(alpha_min, ov.occlusion.alpha_of("ruin_01"))
		alpha_jump = maxf(alpha_jump, absf(ov.occlusion.alpha_of("ruin_01") - prev_alpha))
		prev_alpha = ov.occlusion.alpha_of("ruin_01")
	check("fx.no_flicker_at_boundary", flips == 0 and last and alpha_jump < 0.01, "flips=%d jump=%f" % [flips, alpha_jump])
	# real release: leave for good -> held, then fade in, then fully restored
	_run_for(outside, 0.2)
	check("fx.release_is_delayed", ov.occlusion.is_occluded("ruin_01"))
	_run_for(outside, 1.0)
	check("fx.released_and_restored", not ov.occlusion.is_occluded("ruin_01") and ov.faded_instances().is_empty() and _copy_count() == 0 and _materials_signature() == base_materials and main.water_view.reflection_camera.cull_mask == 1, "occ=%s faded=%s copies=%d same=%s mask=%d" % [ov.occlusion.is_occluded("ruin_01"), str(ov.faded_instances()), _copy_count(), _materials_signature() == base_materials, main.water_view.reflection_camera.cull_mask])
	# ---- multiple groups restore independently
	var two: Vector3 = _behind("tree_01", 8.0)
	_run_for(two, 1.0)
	check("fx.two_groups_faded", ov.faded_instances() == PackedStringArray(["chapel_01", "tree_01"]) and absf(_alpha("chapel_01") - 0.4) < 0.01 and absf(_alpha("tree_01") - 0.4) < 0.01)
	check("fx.vegetation_follows_chapel", absf(_veg_transparency("chapel_01") - 0.6) < 0.01 and _veg_transparency("tree_01") <= 0.0, "chapel veg=%f" % _veg_transparency("chapel_01"))
	_run_for(_behind("tree_01", 3.0), 1.0)
	check("fx.one_group_left_other_restored", absf(_alpha("tree_01") - 0.4) < 0.01 and _alpha("chapel_01") > 0.999 and _veg_transparency("chapel_01") == 0.0 and ov.faded_instances() == PackedStringArray(["tree_01"]), "chapel=%f" % _alpha("chapel_01"))
	# ---- resolution switch and rebuild: no stale / all-transparent state
	main.set_resolution(1, Vector2i(1920, 1080))
	s.position = Coords.ground_to_logic(Vector2(_behind("ruin_01", 6.0).x, _behind("ruin_01", 6.0).z))
	main.tick(0.0, Vector2.ZERO)
	check("fx.snap_after_switch", ov.occlusion.is_occluded("ruin_01") and absf(_alpha("ruin_01") - 0.4) < 0.01, "alpha=%f" % _alpha("ruin_01"))
	main.placement_view.build(s.placement)
	ov.bind()
	check("fx.rebuild_clears", _copy_count() == 0 and ov.faded_instances().is_empty() and _materials_signature() == base_materials, "copies=%d" % _copy_count())

	# build -> wait frames -> bind while an instance is faded (old copies are queued for deletion)
	s.position = Coords.ground_to_logic(Vector2(behind_ruin.x, behind_ruin.z))
	main.tick(0.0, Vector2.ZERO)
	check("fx.gap_precondition_faded", ov.faded_instances().size() > 0)
	main.placement_view.build(s.placement)
	await _frames(3)
	ov.bind()
	check("fx.gap_frame_then_bind_clean", ov.faded_instances().is_empty() and _copy_count() == 0 and _materials_signature() == base_materials)
	main.tick(0.05, Vector2.ZERO)
	main.tick(0.05, Vector2.ZERO)
	s.position = Coords.cell_center_logic(Vector2i(24, 38))
	main.tick(0.0, Vector2.ZERO)
	main.tick(0.5, Vector2.ZERO)
	var all_opaque: bool = true
	for id: String in main.placement_view.materials:
		all_opaque = all_opaque and _alpha(id) > 0.999
	check("fx.open_ground_nothing_faded", all_opaque and ov.occlusion.occluded_groups().is_empty(), "raw=%s" % str(ov.last_raw.keys()))
	# ---- world unchanged after all of it
	check("fx.world_and_walkable_unchanged", _world_signature() == base_world)
	var walk_now: int = 0
	for y: int in main.session.state.height:
		for x: int in main.session.state.width:
			walk_now += 1 if main.session.state.is_walkable(x, y) and main.session.placement.can_plant(Vector2i(x, y)) else 0
	check("fx.walkable_plantable_count_same", walk_now == base_walk, "%d vs %d" % [walk_now, base_walk])
	# ---- disabled: nothing fades
	ov.set_enabled(false)
	s.position = Coords.ground_to_logic(Vector2(behind_ruin.x, behind_ruin.z))
	main.tick(0.3, Vector2.ZERO)
	check("fx.disabled_no_fade", _alpha("ruin_01") > 0.999 and ov.faded_instances().is_empty())
	main.queue_free()
	await _frames(2)
