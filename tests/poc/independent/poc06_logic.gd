extends SceneTree
## POC-06 independent logic verification (headless OK, no OS input). Own screen-space oracle, own restore snapshots.
const Coords: GDScript = preload("res://scripts/poc/poc_coords.gd")
const Occ: GDScript = preload("res://scripts/poc/occlusion/occlusion.gd")
var fails: int = 0
var main: Node
var s: RefCounted
var ov: Node

func check(name: String, ok: bool, detail: String = "") -> void:
	if not ok:
		fails += 1
	print("PASS " if ok else "FAIL ", name, " ", detail)

func _init() -> void:
	_run.call_deferred()

func place(cell: Vector2i) -> void:
	s.position = Coords.cell_center_logic(cell)

func settle_at(cell: Vector2i) -> void:
	place(cell)
	ov.reset()
	main.tick(0.0, Vector2.ZERO)

## Own oracle: screen-space. Cast the camera ray through the screen projection of a body point, hit world triangles of
## each non-puddle instance, occluder if the hit is nearer to the camera than the body point.
func oracle() -> Dictionary:
	var out: Dictionary = {}
	var cam: Camera3D = main.camera
	var foot: Vector3 = main.player_ground3() + Vector3.UP * 0.04
	var h: float = float(main.actor.snapshot()["height_m"]) / maxf(cam.global_basis.y.dot(Vector3.UP), 0.1)
	var pts: Array = [foot + Vector3.UP * 0.1, foot + Vector3.UP * h * 0.5, foot + Vector3.UP * h * 0.92]
	for inst: Dictionary in main.placement_view.placement.instances:
		if inst["kind"] == "puddle":
			continue
		var holder: Node3D = main.placement_view.holders[inst["id"]]
		var hit: bool = false
		for child: Node in holder.find_children("*", "MeshInstance3D", true, false):
			var mi: MeshInstance3D = child as MeshInstance3D
			if mi.mesh == null or not mi.visible:
				continue
			var faces: PackedVector3Array = mi.mesh.get_faces()
			var xf: Transform3D = mi.global_transform
			for p: Vector3 in pts:
				var sp: Vector2 = cam.unproject_position(p)
				var o: Vector3 = cam.project_ray_origin(sp)
				var d: Vector3 = cam.project_ray_normal(sp)
				var tp: float = (p - o).dot(d)
				for i: int in range(0, faces.size(), 3):
					var r: Variant = Geometry3D.ray_intersects_triangle(o, d, xf * faces[i], xf * faces[i + 1], xf * faces[i + 2])
					if r != null and (r as Vector3).distance_to(o) < tp - 0.05:
						hit = true
						break
				if hit:
					break
			if hit:
				break
		if hit:
			out[inst["id"]] = true
	return out

func snap_state() -> Dictionary:
	var st: WorldState = s.state
	var cells: PackedByteArray = PackedByteArray()
	var pl: RefCounted = s.placement
	for y: int in st.height:
		for x: int in st.width:
			var c: Vector2i = Vector2i(x, y)
			cells.append(int(pl.blocks_walk(c)) | (int(pl.projectile_blocked_cell(c)) << 1) | (int(pl.is_greening_target(c)) << 2))
	return {"terrain": st.terrain.duplicate(), "target": st.target.duplicate(), "stage": st.stage.duplicate(), "greened": st.greened_count, "tcount": st.target_count, "cells": cells, "obstacle": pl.obstacle.duplicate(), "proj": pl.projectile.duplicate()}

func mat_snapshot() -> Array:
	var out: Array = []
	for id: String in main.placement_view.holders:
		var holder: Node3D = main.placement_view.holders[id]
		for child: Node in holder.find_children("*", "MeshInstance3D", true, false):
			var mi: MeshInstance3D = child as MeshInstance3D
			if mi.mesh == null or mi.name.begins_with("Occ"):
				continue
			var e: Array = [str(mi.get_path()), mi.cast_shadow, mi.layers, mi.transparency, mi.visible]
			for sf: int in mi.mesh.get_surface_count():
				var m: Material = mi.get_surface_override_material(sf)
				var bm: BaseMaterial3D = m as BaseMaterial3D
				e.append([m.get_instance_id() if m else 0, bm.transparency if bm else -1, bm.depth_draw_mode if bm else -1, bm.albedo_color if bm else null, bm.next_pass == null if bm else true, bm.render_priority if bm else 0, bm.cull_mode if bm else 0])
			out.append(e)
	return out

func veg_alpha(id: String) -> float:
	var g: Node3D = main.wall_view.group_of(id)
	if g == null:
		return -1.0
	var mx: float = 0.0
	for c: Node in g.find_children("*", "GeometryInstance3D", true, false):
		mx = maxf(mx, (c as GeometryInstance3D).transparency)
	return mx

func _run() -> void:
	main = (load("res://scenes/poc.tscn") as PackedScene).instantiate()
	root.add_child(main)
	main.auto_process = false
	main.window_size_override = Vector2i(1920, 1080)
	await process_frame
	await process_frame
	s = main.session
	for y: int in s.state.height:
		for x: int in s.state.width:
			var i: int = s.state.index_of(x, y)
			if s.state.target[i] != 0:
				s.state.set_stage(i, WorldState.STAGE_MATURE)
	for i: int in 560:
		s.advance_game(0.25)
	ov = main.occlusion_view
	main.tick(0.0, Vector2.ZERO)
	check("veg.grown", s.wall_growth.total_progress() > 1.0, "progress=%f" % s.wall_growth.total_progress())
	settle_at(Vector2i(24, 38))
	check("base.open_ground_nothing_faded", ov.faded_instances().is_empty())
	var base_mats: Array = mat_snapshot()
	var base_state: Dictionary = snap_state()
	# ---- 1: sweep every walkable cell (step 2) against the oracle
	var total: int = 0
	var missing: int = 0
	var extra: int = 0
	var ground_or_unknown: int = 0
	var multi: int = 0
	var anyfade: int = 0
	var examples: Array = []
	var ids: Dictionary = {}
	for inst: Dictionary in s.placement.instances:
		ids[inst["id"]] = true
	for y: int in range(0, s.state.height, 2):
		for x: int in range(0, s.state.width, 2):
			if not s.state.is_walkable(x, y):
				continue
			settle_at(Vector2i(x, y))
			total += 1
			var got: PackedStringArray = ov.occlusion.occluded_groups()
			var ora: Dictionary = oracle()
			for g: String in got:
				if not ids.has(g) or g.begins_with("puddle"):
					ground_or_unknown += 1
			for k: String in ora:
				if not got.has(k):
					missing += 1
					if examples.size() < 6:
						examples.append("missing %s at %d,%d" % [k, x, y])
			for g: String in got:
				if not ora.has(g):
					extra += 1
					if examples.size() < 6:
						examples.append("extra %s at %d,%d" % [g, x, y])
			if got.size() > 1:
				multi += 1
			if got.size() > 0:
				anyfade += 1
			# fading set must equal occluded groups (alpha snaps), others fully opaque
			var fset: PackedStringArray = ov.faded_instances()
			if fset != got:
				examples.append("fading!=occluded at %d,%d %s vs %s" % [x, y, str(fset), str(got)])
				fails += 1
	check("oracle.cells", total > 50, "walkable cells=%d occluded cells=%d multi=%d" % [total, anyfade, multi])
	check("oracle.no_missing", missing == 0, "missing=%d %s" % [missing, str(examples)])
	print("INFO extra(impl superset via lateral/fine tri)=%d" % extra)
	check("targets.only_instances", ground_or_unknown == 0)
	# ---- 1b: specific: mill behind, others unaffected; same-GLB instance (tree_01/tree_02) separate
	var found_tree_single: bool = false
	for y: int in range(0, s.state.height):
		for x: int in range(0, s.state.width):
			if not s.state.is_walkable(x, y):
				continue
			settle_at(Vector2i(x, y))
			var got: PackedStringArray = ov.occlusion.occluded_groups()
			if got == PackedStringArray(["tree_01"]) or got == PackedStringArray(["tree_02"]):
				found_tree_single = true
				var other: String = "tree_02" if got[0] == "tree_01" else "tree_01"
				var ia: float = main.placement_view.instance_alpha(got[0])
				var ib: float = main.placement_view.instance_alpha(other)
				check("same_glb.only_one_faded", absf(ia - 0.4) < 0.01 and absf(ib - 1.0) < 0.001, "%s=%f %s=%f" % [got[0], ia, other, ib])
				break
		if found_tree_single:
			break
	check("same_glb.case_found", found_tree_single)
	# ---- 1c: vegetation follows mill, not others
	var mill_cell: Vector2i = Vector2i(-1, -1)
	for y: int in range(0, s.state.height):
		for x: int in range(0, s.state.width):
			if mill_cell.x < 0 and s.state.is_walkable(x, y):
				settle_at(Vector2i(x, y))
				if ov.occlusion.occluded_groups() == PackedStringArray(["mill_01"]):
					mill_cell = Vector2i(x, y)
	check("mill.found", mill_cell.x >= 0)
	if mill_cell.x >= 0:
		settle_at(mill_cell)
		var va: float = veg_alpha("mill_01")
		check("veg.follows_mill", va > 0.55 and va < 0.65, "veg transparency=%f" % va)
		var others: float = 0.0
		for id: String in main.wall_view.instance_ids():
			if id != "mill_01":
				others = maxf(others, veg_alpha(id))
		check("veg.others_untouched", others == 0.0, "max other=%f (veg ids %s)" % [others, str(main.wall_view.instance_ids())])
		check("ground.water.unchanged", main.get("water_view") != null and ov.fading.size() == 1)
		# ---- 3: display-only
		var during: Dictionary = snap_state()
		check("display_only.state_equal_during_fade", during == base_state)
		# ---- 2: restore
		var faded_mats: Array = mat_snapshot()
		check("restore.snapshot_differs_while_faded", faded_mats != base_mats)
		# movement by real tick with dir to leave; teleport out front
		place(Vector2i(24, 38))
		for i: int in 60:
			main.tick(0.05, Vector2.ZERO)
		check("restore.none_faded_after", ov.faded_instances().is_empty() and ov.occlusion.occluded_groups().is_empty(), str(ov.faded_instances()))
		var after_mats: Array = mat_snapshot()
		for k: int in base_mats.size():
			if base_mats[k] != after_mats[k]:
				print("DIFF ", base_mats[k], " -> ", after_mats[k])
		check("restore.materials_identical", after_mats == base_mats)
		check("restore.no_copies", main.placement_view.find_children("Occ*", "MeshInstance3D", true, false).is_empty())
		check("restore.veg_zero", veg_alpha("mill_01") == 0.0)
		check("display_only.state_equal_after", snap_state() == base_state)
		# ---- 2b flicker: oscillate between two cells each frame
		var cell_in: Vector2i = mill_cell
		var cell_out: Vector2i = Vector2i(24, 38)
		settle_at(cell_in)
		var flips: int = 0
		var prev: bool = true
		var min_alpha: float = 1.0
		var max_after: float = 0.0
		for i: int in 40:
			place(cell_in if i % 2 == 0 else cell_out)
			main.tick(0.016, Vector2.ZERO)
			var cur: bool = ov.faded_instances().has("mill_01")
			if cur != prev:
				flips += 1
			prev = cur
		check("flicker.alternating_every_frame", flips <= 1, "flips=%d" % flips)
		# boundary-ish: leave for 0.2s (< hold 0.35) then come back
		settle_at(cell_in)
		place(cell_out)
		for i: int in 10:
			main.tick(0.02, Vector2.ZERO)
		check("flicker.hold_keeps_fade_0.2s", ov.faded_instances().has("mill_01"))
		for i: int in 80:
			main.tick(0.02, Vector2.ZERO)
		check("restore.after_hold", ov.faded_instances().is_empty())
		# ---- 2c: resolution switch / rebuild while faded
		settle_at(cell_in)
		for ri: int in [1, 0, 1]:
			main.set_resolution(ri, Vector2i(1920, 1080))
			main.tick(0.0, Vector2.ZERO)
		check("resolution.still_only_mill", ov.occlusion.occluded_groups() == PackedStringArray(["mill_01"]) and ov.faded_instances() == PackedStringArray(["mill_01"]), str(ov.faded_instances()))
		var cnt: int = main.placement_view.find_children("OccShadow*", "MeshInstance3D", true, false).size()
		var cnt2: int = main.placement_view.find_children("OccReflect*", "MeshInstance3D", true, false).size()
		check("resolution.copies_not_duplicated", cnt == cnt2 and cnt > 0, "shadow=%d reflect=%d" % [cnt, cnt2])
		place(cell_out)
		main.set_resolution(0, Vector2i(1920, 1080))
		for i: int in 60:
			main.tick(0.05, Vector2.ZERO)
		check("resolution.restores", ov.faded_instances().is_empty() and mat_snapshot() == base_mats and main.placement_view.find_children("Occ*", "MeshInstance3D", true, false).is_empty())
		# rebuild: placement view rebuild while faded
		settle_at(cell_in)
		var pv: Node3D = main.placement_view
		pv.build(s.placement)
		ov.bind()
		await process_frame
		await process_frame
		main.tick(0.0, Vector2.ZERO)
		check("rebuild.only_mill_faded", ov.faded_instances() == PackedStringArray(["mill_01"]), str(ov.faded_instances()))
		var alphas_ok: bool = true
		for id: String in pv.holders:
			if id != "mill_01" and id.begins_with("puddle") == false and absf(pv.instance_alpha(id) - 1.0) > 0.001 and pv.instance_alpha(id) != -1.0:
				alphas_ok = false
		check("rebuild.others_opaque", alphas_ok)
		place(cell_out)
		for i: int in 60:
			main.tick(0.05, Vector2.ZERO)
		check("rebuild.restores_no_orphans", ov.faded_instances().is_empty() and pv.find_children("Occ*", "MeshInstance3D", true, false).is_empty())
		settle_at(Vector2i(24, 38))
		base_mats = mat_snapshot()   # placement view was rebuilt: new material instances, new baseline
		# ---- 2d: rebuild with old nodes freed while faded without restore: bind() restores
		settle_at(cell_in)
		ov.bind()
		check("bind_while_faded.no_stale", ov.fading.is_empty() and pv.find_children("Occ*", "MeshInstance3D", true, false).is_empty())
		main.tick(0.0, Vector2.ZERO)
		place(cell_out)
		ov.reset()
		main.tick(0.0, Vector2.ZERO)
		# ---- 4: tuning reflected
		var file_t: Dictionary = Occ.load_tuning()
		var f: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/poc/occlusion.json"))
		check("tuning.default_matches_file", ov.occlusion.tuning["target_alpha"] == float(f["target_alpha"]) and file_t["release_hold_seconds"] == float(f["release_hold_seconds"]))
		var alt: Dictionary = Occ.load_tuning("res://evidence/poc/06/independent/occ_alt.json")
		check("tuning.alt_loaded", absf(float(alt["target_alpha"]) - 0.2) < 1e-6 and float(alt["release_hold_seconds"]) == 1.0)
		ov.setup(pv, main.wall_view, main.camera, main.water_view, alt)
		settle_at(cell_in)
		check("tuning.alpha_applied_0.2", absf(pv.instance_alpha("mill_01") - 0.2) < 0.005, "alpha=%f" % pv.instance_alpha("mill_01"))
		check("tuning.veg_applied", absf(veg_alpha("mill_01") - 0.8) < 0.01, "veg=%f" % veg_alpha("mill_01"))
		place(cell_out)
		for i: int in 40:
			main.tick(0.02, Vector2.ZERO)   # 0.8s < hold 1.0
		check("tuning.hold_1.0_applied", ov.faded_instances().has("mill_01"))
		for i: int in 20:
			main.tick(0.02, Vector2.ZERO)
		check("tuning.released_after_hold", ov.faded_instances().is_empty())
		check("restore.after_alt", mat_snapshot() == base_mats)
		# ---- 2e (robustness): rebuild, a frame passes, only then bind
		settle_at(cell_in)
		pv.build(s.placement)
		await process_frame
		await process_frame
		ov.bind()
		main.tick(0.0, Vector2.ZERO)
		place(cell_out)
		for i: int in 30:
			main.tick(0.05, Vector2.ZERO)
		check("rebuild.gap_frame_then_bind_clean", ov.fading.is_empty() and pv.find_children("Occ*", "MeshInstance3D", true, false).is_empty(), "fading=%s" % str(ov.fading.keys()))
		# ---- 3b: enemy / combat code does not reference occlusion
		var refs: int = 0
		for path: String in ["res://scripts/poc/combat", "res://scripts/poc/play", "res://scripts/poc/poc_session.gd", "res://scripts/poc/assets/placement.gd", "res://scripts/world"]:
			refs += _grep(path)
		check("display_only.no_logic_reference_to_occlusion", refs == 0, "refs=%d" % refs)
	main.queue_free()
	await process_frame
	print("RESULT fails=%d" % fails)
	quit(1 if fails > 0 else 0)

func _grep(path: String) -> int:
	var n: int = 0
	if DirAccess.dir_exists_absolute(path):
		for f: String in DirAccess.get_files_at(path):
			if f.ends_with(".gd"):
				n += _grep(path + "/" + f)
		for d: String in DirAccess.get_directories_at(path):
			n += _grep(path + "/" + d)
	elif FileAccess.file_exists(path):
		var t: String = FileAccess.get_file_as_string(path).to_lower()
		if t.contains("occlusion") or t.contains("occluded"):
			n += 1
			print("INFO ref in ", path)
	return n
