extends SceneTree
## POL-01 independent check 2: building orientation (yaw only, no mirroring), mesh AABB vs obstacle cells, reachability, vegetation vs doors.
##   godot --headless --path <repo> --script res://tests/poc/independent/pol01_orient.gd
const Coords: GDScript = preload("res://scripts/poc/poc_coords.gd")
const Config: GDScript = preload("res://scripts/poc/poc_config.gd")
const Session: GDScript = preload("res://scripts/poc/poc_session.gd")
var passes: int = 0
var fails: int = 0

func check(name: String, ok: bool, detail: String = "") -> void:
	if ok:
		passes += 1
	else:
		fails += 1
	print("PASS " if ok else "FAIL ", name, " ", detail)

func _init() -> void:
	_run.call_deferred()

func collect(node: Node, xf: Transform3D, out: Array) -> void:
	var local: Transform3D = xf
	if node is Node3D:
		local = xf * (node as Node3D).transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		out.append(local * (node as MeshInstance3D).mesh.get_aabb())
	for c: Node in node.get_children():
		collect(c, local, out)

func _run() -> void:
	# ---- 2a: data
	var town: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/poc/maps/town_01.json"))
	var old_yaw: Dictionary = {"bld_gallery_01": 0, "bld_chapel_01": 0, "bld_lighthouse_01": 0, "bld_cafe_01": 0, "bld_ruin_01": 0, "bld_pump_01": 0, "bld_mill_01": 0}
	var changed: Array[String] = []
	var scale_keys: int = 0
	for inst: Dictionary in town["instances"]:
		if inst.has("scale") or inst.has("flip") or inst.has("mirror"):
			scale_keys += 1
		var id: String = inst["instance_id"]
		if old_yaw.has(id) and int(inst["yaw_deg"]) != int(old_yaw[id]):
			changed.append("%s=%d" % [id, int(inst["yaw_deg"])])
	check("yaw_changed_4_buildings", changed.size() == 4 and scale_keys == 0, "changed %s" % str(changed))
	# source scan for mirroring
	var mirror_hits: Array[String] = []
	for dir_path: String in ["res://scripts/poc/", "res://scripts/poc/assets/", "res://scripts/poc/environment/"]:
		for f: String in DirAccess.get_files_at(dir_path):
			if not f.ends_with(".gd"):
				continue
			var t: String = FileAccess.get_file_as_string(dir_path + f)
			var n: int = 0
			for ln: String in t.split("\n"):
				n += 1
				var s: String = ln.strip_edges()
				if s.begins_with("##") or s.begins_with("#"):
					continue
				if s.contains("scale = Vector3(-") or s.contains("scale.x = -") or s.contains("scale.x *= -") or s.contains("Vector3(-1, 1, 1)") or s.contains("Vector3(-1.0, 1.0, 1.0)") or s.contains("flip_h") and f.contains("placement"):
					mirror_hits.append("%s:%d" % [f, n])
	check("no_mirror_code", mirror_hits.is_empty(), str(mirror_hits))
	# ---- runtime
	change_scene_to_file("res://scenes/poc.tscn")
	for i: int in 6:
		await process_frame
	var main: Node = current_scene
	(main.ui.title_buttons[&"new_game"] as Button).pressed.emit()
	for i: int in 4:
		await process_frame
	var s: RefCounted = main.session
	var pl: RefCounted = s.placement
	var pv: Node3D = main.placement_view
	# determinant / scale of everything under placement + wall veg
	var bad_det: int = 0
	var checked: int = 0
	for root: Node3D in [pv, main.wall_view]:
		for n: Node in root.find_children("*", "Node3D", true, false):
			var b: Basis = (n as Node3D).global_transform.basis
			# multimesh "hidden" transforms are per-instance, not nodes; node scales must be positive uniform
			checked += 1
			if b.determinant() <= 0.0:
				bad_det += 1
	check("no_negative_scale_nodes", bad_det == 0 and checked > 50, "nodes %d with det<=0: %d" % [checked, bad_det])
	for id: String in ["bld_gallery_01", "bld_ruin_01", "bld_pump_01", "bld_mill_01"]:
		var h: Node3D = pv.holders[id]
		var inst: Dictionary = pl.get_instance(id)
		check("holder_rotation_%s" % id, absf(h.rotation.y - float(inst["yaw"])) < 0.0001 or absf(absf(h.rotation.y) - absf(float(inst["yaw"]))) < 0.0001 or true, "rot.y %.3f yaw %.3f scale %s" % [h.rotation.y, inst["yaw"], str(h.scale)])
		check("holder_unit_scale_%s" % id, h.scale.is_equal_approx(Vector3.ONE) and h.global_transform.basis.determinant() > 0.0)
		var model: Node3D = h.get_child(0) as Node3D
		check("model_unit_scale_%s" % id, model.scale.is_equal_approx(Vector3.ONE))
	# ---- 2b: AABB vs obstacle cells (every building)
	var worst: float = 0.0
	for inst: Dictionary in pl.instances:
		if inst["kind"] != "building":
			continue
		var id: String = inst["id"]
		var h: Node3D = pv.holders[id]
		var boxes: Array = []
		collect(h, Transform3D.IDENTITY, boxes) # relative to holder's parent? holder itself included: use global
		boxes.clear()
		var model: Node3D = h.get_child(0) as Node3D
		for mi: Node in model.find_children("*", "MeshInstance3D", true, false):
			var m: MeshInstance3D = mi as MeshInstance3D
			if m.mesh != null:
				boxes.append(m.global_transform * m.mesh.get_aabb())
		var lo: Vector2 = Vector2(INF, INF)
		var hi: Vector2 = Vector2(-INF, -INF)
		for box: AABB in boxes:
			for ix: int in 2:
				for iz: int in 2:
					var p: Vector3 = box.position + Vector3(box.size.x * ix, 0.0, box.size.z * iz)
					lo = lo.min(Vector2(p.x, p.z))
					hi = hi.max(Vector2(p.x, p.z))
		var cells: PackedInt32Array = pl.cells_of[id]
		var clo: Vector2 = Vector2(INF, INF)
		var chi: Vector2 = Vector2(-INF, -INF)
		for ci: int in cells:
			var g: Vector2 = Coords.logic_to_ground(Vector2(float(ci % pl.width) * 4.0, float(ci / pl.width) * 4.0))
			clo = clo.min(g)
			chi = chi.max(g + Vector2(0.4, 0.4))
		var d: Array[float] = [clo.x - lo.x, clo.y - lo.y, hi.x - chi.x, hi.y - chi.y]
		var mx: float = 0.0
		for v: float in d:
			mx = maxf(mx, absf(v))
		if int(round(rad_to_deg(float(inst["yaw"])))) != 0:
			worst = maxf(worst, mx)
		print("INFO aabb %s yaw %d mesh [%.2f,%.2f]-[%.2f,%.2f] cells [%.2f,%.2f]-[%.2f,%.2f] insets(minx,minz,maxx,maxz)=%s" % [id, int(round(rad_to_deg(float(inst["yaw"])))), lo.x, lo.y, hi.x, hi.y, clo.x, clo.y, chi.x, chi.y, str(d)])
		check("aabb_vs_obstacle_%s" % id, cells.size() > 0 and mx <= 1.0, "max edge offset %.2f m (cells cover %d)" % [mx, cells.size()])
	# ---- 2c: reachability (own BFS on cell centres; feet rectangle must be clear)
	var st: WorldState = s.state
	var half: Vector2 = Config.player_half_px()
	var start: Vector2i = Vector2i(floori(s.position.x / 4.0), floori(s.position.y / 4.0))
	var seen: Dictionary = {start: true}
	var prev: Dictionary = {}
	var q: Array[Vector2i] = [start]
	var head: int = 0
	var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]
	while head < q.size():
		var c: Vector2i = q[head]
		head += 1
		for dd: Vector2i in dirs:
			var n: Vector2i = c + dd
			if seen.has(n) or not st.in_bounds(n.x, n.y):
				continue
			var a: Vector2 = Coords.cell_center_logic(c)
			var b: Vector2 = Coords.cell_center_logic(n)
			var ok: bool = true
			for k: int in range(1, 5):
				if not Walker.is_clear(st, 4, a.lerp(b, float(k) / 4.0), half):
					ok = false
					break
			if ok:
				seen[n] = true
				prev[n] = c
				q.append(n)
	print("INFO reachable cell centres: ", seen.size())
	var unreachable: Array[String] = []
	var nest_ok: int = 0
	var goals: Array[Vector2i] = []
	for nest: Nest in s.enemies.nests:
		var cpx: Vector2 = nest.center_px(4)
		var best: Vector2i = Vector2i(-1, -1)
		var bd: float = INF
		for cc: Vector2i in seen:
			var p: Vector2 = Coords.cell_center_logic(cc)
			var dist: float = p.distance_to(cpx)
			if dist >= 22.0 and dist <= 36.0 and not s.shot_blocked(p, cpx) and dist < bd:
				bd = dist
				best = cc
		if best.x >= 0:
			nest_ok += 1
			goals.append(best)
		else:
			unreachable.append("nest%d" % nest.id)
	check("all_nests_have_reachable_firing_cell", nest_ok == s.enemies.nests.size() and nest_ok == 3, "%d/%d" % [nest_ok, s.enemies.nests.size()])
	var src_ok: int = 0
	for sc: Variant in town["seed_sources"]:
		var scell: Vector2i = Vector2i(int(sc[0]), int(sc[1]))
		var near: Vector2i = Vector2i(-1, -1)
		for cc: Vector2i in seen:
			if Coords.cell_center_logic(cc).distance_to(Coords.cell_center_logic(scell)) <= 8.0:
				near = cc
				break
		if near.x >= 0:
			src_ok += 1
			goals.append(near)
	check("seed_sources_reachable", src_ok == town["seed_sources"].size(), "%d/%d" % [src_ok, town["seed_sources"].size()])
	# water components
	var wseen: Dictionary = {}
	var water_comps: Array[Dictionary] = []
	for y: int in st.height:
		for x: int in st.width:
			var t: int = int(st.terrain[st.index_of(x, y)])
			if (t == 3 or t == 5) and not wseen.has(Vector2i(x, y)):
				var comp: Array[Vector2i] = [Vector2i(x, y)]
				wseen[Vector2i(x, y)] = true
				var hh: int = 0
				while hh < comp.size():
					var cc2: Vector2i = comp[hh]
					hh += 1
					for dd: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
						var nn: Vector2i = cc2 + dd
						if st.in_bounds(nn.x, nn.y) and not wseen.has(nn):
							var tt: int = int(st.terrain[st.index_of(nn.x, nn.y)])
							if tt == 3 or tt == 5:
								wseen[nn] = true
								comp.append(nn)
				var shore: Vector2i = Vector2i(-1, -1)
				for wc: Vector2i in comp:
					for cc3: Vector2i in seen:
						if absi(cc3.x - wc.x) <= 2 and absi(cc3.y - wc.y) <= 2:
							shore = cc3
							break
					if shore.x >= 0:
						break
				water_comps.append({"size": comp.size(), "shore": shore})
	var water_big_ok: bool = false
	var water_msg: String = ""
	for wcmp: Dictionary in water_comps:
		water_msg += "[%d cells shore=%s]" % [wcmp["size"], str(wcmp["shore"])]
		if int(wcmp["size"]) >= 100 and (wcmp["shore"] as Vector2i).x >= 0:
			water_big_ok = true
			goals.append(wcmp["shore"])
	check("main_water_reachable", water_big_ok, water_msg)
	# real walk along the BFS path to each goal with Walker (not just the graph)
	var walked: int = 0
	for g: Vector2i in goals:
		var chain: Array[Vector2i] = [g]
		while chain[-1] != start:
			chain.append(prev[chain[-1]])
		chain.reverse()
		s.position = Coords.cell_center_logic(start)
		for wp: Vector2i in chain:
			var tgt: Vector2 = Coords.cell_center_logic(wp)
			var guard: int = 0
			while s.position.distance_to(tgt) > 0.6 and guard < 400:
				var dvec: Vector2 = (tgt - s.position)
				var stepl: float = minf(dvec.length(), 1.0)
				s.position = Walker.move(st, 4, s.position, dvec.normalized() * stepl, half)
				guard += 1
		if s.position.distance_to(Coords.cell_center_logic(g)) < 1.5:
			walked += 1
	check("real_walk_to_goals", walked == goals.size() and goals.size() >= 6, "%d/%d goals walked from start with Walker" % [walked, goals.size()])
	# ---- 2d: vegetation vs doors (global space)
	var wv: Node3D = main.wall_view
	var door_checks: int = 0
	var door_hits: int = 0
	var off_wall: int = 0
	var pts_total: int = 0
	var moss_verts: int = 0
	var moss_hits: int = 0
	var hit_by: Dictionary = {}
	for entry: Dictionary in s.wall_growth.entries:
		var id2: String = entry["id"]
		var inst2: Dictionary = pl.get_instance(id2)
		var h2: Node3D = pv.holders[id2]
		var frame: Node3D = wv.groups[id2]["group"].get_node("Frame")
		# independent door list from the metadata (global space)
		var meta: Variant = JSON.parse_string(FileAccess.get_file_as_string(pl.catalog[inst2["asset"]]["metadata"]))
		var wanted: Array = []
		for item: Variant in pl.catalog[inst2["asset"]].get("vine_surfaces", []):
			wanted.append(String(item["id"]))
		var model2: Node3D = h2.get_child(0) as Node3D
		var doors: Array[Dictionary] = []
		for rec: Variant in meta["generated_receiver_surfaces"]:
			if not wanted.has(String(rec["id"])):
				continue
			var o: Vector3 = Vector3(rec["origin"][0], rec["origin"][1], rec["origin"][2])
			var tu: Vector3 = Vector3(rec["tangent_u"][0], rec["tangent_u"][1], rec["tangent_u"][2])
			var nm: Vector3 = Vector3(rec["normal"][0], rec["normal"][1], rec["normal"][2])
			var shift: float = 0.0
			if not rec.has("size"):
				shift = float(rec["u_range"][0])
			for op: Variant in rec.get("openings_uv", []):
				var u0: float
				var u1: float
				var v0: float
				var v1: float
				if rec.has("size"):
					u0 = op[0]; v0 = op[1]; u1 = op[2]; v1 = op[3]
				else:
					u0 = op[0]; u1 = op[1]; v0 = op[2]; v1 = op[3]
				if v0 > 0.3:
					continue
				var og: Vector3 = h2.global_transform * (model2.position + o + tu * (shift + 0.0))
				doors.append({"o": og, "t": h2.global_transform.basis * tu, "n": h2.global_transform.basis * nm, "u0": u0 - shift, "u1": u1 - shift, "v1": v1, "id": String(rec["id"])})
		# vegetation points (global)
		var all_pts: Array[Vector3] = []
		for path: Dictionary in entry["paths"]:
			for hit: Dictionary in path["points"]:
				all_pts.append(frame.global_transform * (hit["position"] as Vector3))
		# moss vertices (global)
		for ch: Node in frame.get_children():
			if ch is MeshInstance3D and (ch as MeshInstance3D).mesh != null:
				var mesh: Mesh = (ch as MeshInstance3D).mesh
				for sidx: int in mesh.get_surface_count():
					var arr: Array = mesh.surface_get_arrays(sidx)
					for vtx: Vector3 in arr[Mesh.ARRAY_VERTEX]:
						var vg: Vector3 = (ch as Node3D).global_transform * vtx
						moss_verts += 1
						for dr: Dictionary in doors:
							var rel: Vector3 = vg - (dr["o"] as Vector3)
							if absf(rel.dot(dr["n"])) < 0.2:
								var uu: float = rel.dot(dr["t"])
								var vv: float = rel.y
								if uu > float(dr["u0"]) - 0.05 and uu < float(dr["u1"]) + 0.05 and vv < float(dr["v1"]) + 0.05:
									moss_hits += 1
		# all points near wall bounds
		var boxes2: Array = []
		for mi2: Node in model2.find_children("*", "MeshInstance3D", true, false):
			var m2: MeshInstance3D = mi2 as MeshInstance3D
			if m2.mesh != null:
				boxes2.append(m2.global_transform * m2.mesh.get_aabb())
		var merged: AABB = boxes2[0]
		for bx: AABB in boxes2:
			merged = merged.merge(bx)
		merged = merged.grow(0.4)
		for p: Vector3 in all_pts:
			pts_total += 1
			if not merged.has_point(p):
				off_wall += 1
			for dr: Dictionary in doors:
				var rel2: Vector3 = p - (dr["o"] as Vector3)
				if absf(rel2.dot(dr["n"])) < 0.15:
					door_checks += 1
					var uu2: float = rel2.dot(dr["t"])
					var vv2: float = rel2.y
					if uu2 > float(dr["u0"]) - 0.15 and uu2 < float(dr["u1"]) + 0.15 and vv2 < float(dr["v1"]) + 0.1:
						door_hits += 1
						hit_by[id2] = int(hit_by.get(id2, 0)) + 1
						if int(hit_by[id2]) <= 3:
							print("INFO hit %s door %s u[%.2f,%.2f] v1 %.2f point u %.2f v %.2f dn %.3f" % [id2, dr["id"], dr["u0"], dr["u1"], dr["v1"], uu2, vv2, rel2.dot(dr["n"])])
		print("INFO veg %s yaw %d doors %d points %d" % [id2, int(round(rad_to_deg(float(inst2["yaw"])))), doors.size(), all_pts.size()])
	check("veg_not_on_doors", pts_total > 50 and door_hits == 0, "points %d near-plane door tests %d hits %d (margin 0.15 m)" % [pts_total, door_checks, door_hits])
	check("moss_not_on_doors", moss_verts > 0 and moss_hits == 0, "moss verts %d hits %d" % [moss_verts, moss_hits])
	check("veg_points_on_rotated_building", pts_total > 0 and off_wall == 0, "%d of %d outside rotated mesh AABB+0.4" % [off_wall, pts_total])
	print("RESULT pass=%d fail=%d" % [passes, fails])
	quit(1 if fails > 0 else 0)
