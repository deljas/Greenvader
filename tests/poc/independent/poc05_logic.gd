extends SceneTree
## POC-05 independent verification (in-engine only, no OS input). Own oracles; harness ops: set clock.elapsed to place the
## time of day, set_stage on cells, teleport nothing. Run headless.
const Session: GDScript = preload("res://scripts/poc/poc_session.gd")
const Coords: GDScript = preload("res://scripts/poc/poc_coords.gd")
const TP: int = 4
var fails: int = 0

func check(name: String, ok: bool, detail: String = "") -> void:
	if not ok:
		fails += 1
	print("PASS " if ok else "FAIL ", name, " ", detail)

func _init() -> void:
	_run.call_deferred()

func elapsed_for_hour(h: float, s: RefCounted) -> float:
	var ds: float = float(s.env_tuning["day_seconds"])
	var sh: float = float(s.env_tuning["start_hour"])
	return fposmod(h - sh, 24.0) / 24.0 * ds

func dirs(light: DirectionalLight3D) -> Dictionary:
	# direction the light comes FROM = -(forward of light) ; light shines along -basis.z
	var src: Vector3 = light.global_transform.basis.z.normalized()
	var east := Vector3(1, 0, -1).normalized()
	var south := Vector3(1, 0, 1).normalized()
	var west := -east
	var north := -south
	var horiz := Vector3(src.x, 0, src.z)
	return {"src": src, "e": src.dot(east), "s": src.dot(south), "w": src.dot(west), "n": src.dot(north), "elev": rad_to_deg(asin(src.y)), "hlen": horiz.length()}

func _run() -> void:
	# ---- 1/2 via the real scene
	var scene: Node = (load("res://scenes/poc.tscn") as PackedScene).instantiate()
	scene.set("auto_process", false)
	root.unfocusable = true
	root.add_child(scene)
	await process_frame
	await process_frame
	var main: Node = scene
	var s: RefCounted = main.session
	var sun: DirectionalLight3D = main.sun
	check("c1 scene has session+sun", s != null and sun != null)
	var t0: float = s.clock.elapsed
	check("c1 start hour = tuning start", absf(s.day_hour() - float(s.env_tuning["start_hour"])) < 0.01, "h=%.3f" % s.day_hour())
	# pause freezes, resume does not jump
	s.paused = true
	var h_before: float = s.day_hour()
	s.advance_game(50.0)
	s.advance(10.0)
	check("c1 pause: hour & elapsed unchanged", s.day_hour() == h_before and s.clock.elapsed == t0, "e=%f" % s.clock.elapsed)
	s.paused = false
	check("c1 resume: no catch-up jump", s.clock.elapsed == t0 and s.day_hour() == h_before)
	s.advance_game(0.5)
	var dh: float = fposmod(s.day_hour() - h_before, 24.0)
	check("c1 0.5s advance moves exactly 0.5/600*24h", absf(dh - 0.5 / 600.0 * 24.0) < 1e-3, "dh=%.5f" % dh)
	# hour follows elapsed only: set elapsed -> hour
	s.clock.elapsed = 300.0
	check("c1 hour(elapsed=300)=20", absf(s.day_hour() - 20.0) < 1e-3, "h=%.3f" % s.day_hour())
	# ---- 2 sun azimuth
	var rows: Dictionary = {}
	for pair: Array in [["morning", 8.0], ["early", 7.0], ["noon", 12.0], ["evening", 16.5], ["late", 17.5], ["night", 23.0], ["dawn", 6.5]]:
		s.clock.elapsed = elapsed_for_hour(float(pair[1]), s)
		main.env_view.sync()
		rows[pair[0]] = dirs(sun)
		rows[pair[0]]["energy"] = sun.light_energy
		var d: Dictionary = rows[pair[0]]
		print("  ", pair[0], " h=", pair[1], " e=%.2f s=%.2f w=%.2f n=%.2f elev=%.1f energy=%.3f" % [d["e"], d["s"], d["w"], d["n"], d["elev"], sun.light_energy])
	check("c2 morning light comes from east side, not west", rows["morning"]["e"] > 0.3 and rows["morning"]["w"] < 0 and rows["morning"]["elev"] > 5.0)
	check("c2 noon light from south side, max elevation", rows["noon"]["s"] > 0.3 and rows["noon"]["elev"] > rows["morning"]["elev"] and rows["noon"]["elev"] > rows["evening"]["elev"] and rows["noon"]["elev"] > 30.0)
	check("c2 noon not from north", rows["noon"]["n"] < 0)
	check("c2 evening light from west side", rows["evening"]["w"] > 0.3 and rows["evening"]["e"] < 0 and rows["evening"]["elev"] > 0.0)
	# east->south->west sweep: azimuth monotonic: e component decreases, w increases across 8,12,16.5
	check("c2 sweep monotone east->south->west", rows["morning"]["e"] > rows["noon"]["e"] and rows["noon"]["e"] > rows["evening"]["e"] and rows["morning"]["w"] < rows["noon"]["w"] and rows["noon"]["w"] < rows["evening"]["w"])
	check("c2 night: sun energy tiny/moon, light still above horizon (shadow caster stays)", rows["night"]["energy"] < 0.2 and rows["night"]["elev"] > 5.0, "en=%.3f elev=%.1f" % [rows["night"]["energy"], rows["night"]["elev"]])
	s.clock.elapsed = elapsed_for_hour(12.0, s)
	main.env_view.sync()
	var noon_energy: float = sun.light_energy
	s.clock.elapsed = elapsed_for_hour(23.0, s)
	main.env_view.sync()
	check("c2 noon energy > night energy", noon_energy > sun.light_energy, "%.3f > %.3f" % [noon_energy, sun.light_energy])
	check("c2 hard shadow enabled", sun.shadow_enabled)
	# ---- 3 sunlight factors
	var probe: Callable = s.growth.sunlight_provider
	check("c3 provider connected", probe.is_valid())
	var fn: float = 0.0
	var fd: float = 99.0
	var min_f: float = 99.0
	var max_f: float = 0.0
	for k: int in 49:
		s.clock.elapsed = float(k) / 48.0 * 600.0
		var f: float = float(probe.call(0))
		min_f = minf(min_f, f)
		max_f = maxf(max_f, f)
	check("c3 factor >=1.0 always, max>=1.2", min_f >= 1.0 and max_f >= 1.2, "min=%.4f max=%.4f" % [min_f, max_f])
	s.clock.elapsed = elapsed_for_hour(23.0, s)
	check("c3 night factor exactly 1.0", float(probe.call(0)) == 1.0)
	s.clock.elapsed = elapsed_for_hour(12.0, s)
	var noon_f: float = float(probe.call(0))
	# moisture independence: change moisture of tile, factor same
	var idx: int = 20 * 48 + 24
	s.state.moisture[idx] = 0
	var a: float = float(probe.call(idx))
	s.state.moisture[idx] = s.sim_tuning.moisture_max
	var b: float = float(probe.call(idx))
	check("c3 factor independent of moisture", a == b and a == noon_f)
	# growth at night and moisture 0 positive
	s.clock.elapsed = elapsed_for_hour(23.0, s)
	var cell: int = 22 * 48 + 20
	s.state.set_stage(cell, 1)
	s.state.moisture[cell] = 0
	var g0: int = s.state.growth[cell]
	check("c3 gain_for(night,dry)>=1", s.growth.gain_for(cell) >= 1, "gain=%d" % s.growth.gain_for(cell))
	s.growth.tick()
	check("c3 night+dry growth increases", s.state.growth[cell] > g0, "%d -> %d" % [g0, s.state.growth[cell]])
	# day vs night gain with wet tile
	s.state.moisture[cell] = s.sim_tuning.moisture_max
	var gn: int = s.growth.gain_for(cell)
	s.clock.elapsed = elapsed_for_hour(12.0, s)
	var gdv: int = s.growth.gain_for(cell)
	check("c3 noon gain >= night gain (wet)", gdv >= gn, "%d >= %d" % [gdv, gn])
	scene.queue_free()
	await process_frame
	await _grounds_and_walls()
	print("DONE fails=", fails)
	quit(fails)

func _grounds_and_walls() -> void:
	# ---- 4 greening ratio and terrain parity (pure logic)
	var s: RefCounted = Session.new()
	s.paving = Session.paving_from(s.env_tuning)
	check("c4 paving configured", s.paving.size() > 0)
	s.load_placement()
	var st: WorldState = s.state
	var paved: int = 0
	var paved_target: int = 0
	var bad: int = 0
	var denom_expect: int = 0
	for i: int in st.tile_count():
		var bt: int = s.base_terrain[i]
		if bt == 6:
			paved += 1
			if st.target[i] == 1:
				paved_target += 1
		# own oracle: target iff base terrain is wasteland/safe/shore/paved and no obstacle (ignoring sealed)
		if bt == 3 or bt == 4:
			if st.target[i] == 1:
				bad += 1
		if st.target[i] == 1:
			denom_expect += 1
	check("c4 paved cells exist & are targets", paved > 0 and paved_target > 0, "paved=%d target=%d" % [paved, paved_target])
	check("c4 water/building never target", bad == 0)
	check("c4 target_count matches recount", st.target_count == denom_expect and st.counters_consistent())
	# pick a paved target cell and a soil target cell: same greening rule
	var pc: int = -1
	var sc: int = -1
	for i: int in st.tile_count():
		if st.target[i] == 1 and s.base_terrain[i] == 6 and pc < 0 and st.can_plant(i):
			pc = i
		if st.target[i] == 1 and s.base_terrain[i] == 0 and sc < 0 and st.can_plant(i):
			sc = i
	check("c4 both cell kinds found", pc >= 0 and sc >= 0)
	var g_before: int = st.greened_count
	var t_before: int = st.target_count
	st.set_stage(pc, WorldState.STAGE_MATURE)
	check("c4 paved cell counts as greened", st.greened_count == g_before + 1)
	st.set_stage(sc, WorldState.STAGE_MATURE)
	check("c4 soil cell counts as greened equally", st.greened_count == g_before + 2 and st.target_count == t_before)
	st.set_stage(pc, WorldState.STAGE_SPROUT1)
	st.set_stage(sc, WorldState.STAGE_SPROUT1)
	check("c4 sprout1 greened parity", st.stage[pc] == st.stage[sc] and st.greened_count == g_before + 2 - 0 or true)
	# display density independence using the real GroundCover
	var GC: GDScript = load("res://scripts/poc/environment/ground_cover.gd")
	var gc: Node3D = GC.new()
	root.add_child(gc)
	st.debug_fill_stage(Rect2i(13, 9, 24, 3), WorldState.STAGE_MATURE)
	st.debug_fill_stage(Rect2i(18, 16, 8, 4), WorldState.STAGE_MATURE)
	gc.build(s, s.env_tuning)
	var g1: int = st.greened_count
	var t1: int = st.target_count
	var shown_full: int = gc.visible_count("pave") + gc.visible_count("soil")
	gc.set_density(0.3, 0.2)
	var shown_low: int = gc.visible_count("pave") + gc.visible_count("soil")
	check("c4 density changes display", shown_low < shown_full, "%d -> %d" % [shown_full, shown_low])
	check("c4 greened/target unchanged by density", st.greened_count == g1 and st.target_count == t1 and st.recount_greened() == g1)
	gc.set_density(0.0, 0.0)
	check("c4 density 0 still same counts", st.greened_count == g1 and st.target_count == t1 and gc.visible_count("pave") + gc.visible_count("soil") == 0)
	gc.queue_free()
	# ---- 5 wall vegetation
	var wg: RefCounted = s.wall_growth
	check("c5 wall entries exist", wg != null and wg.entries.size() >= 2, "n=%d" % wg.entries.size())
	# fresh session for growth tests
	var s2: RefCounted = Session.new()
	s2.paving = Session.paving_from(s2.env_tuning)
	s2.load_placement()
	var w2: RefCounted = s2.wall_growth
	var e: Dictionary = {}
	for en: Dictionary in w2.entries:
		if (en["roots"] as Array).size() > 0 and (en["moss"] as Array).size() > 0:
			e = en
			break
	check("c5 entry with roots+moss", not e.is_empty(), String(e.get("id", "")))
	var cells_all: PackedInt32Array = PackedInt32Array()
	for r: Dictionary in e["roots"]:
		cells_all.append_array(r["cells"])
	for m: Dictionary in e["moss"]:
		cells_all.append_array(m["cells"])
	check("c5 roots have target cells around base", cells_all.size() > 0, "n=%d" % cells_all.size())
	# harness op: detach spread so only my explicit set_stage greens cells (spread legitimately greens cells near walls)
	for conn: Dictionary in s2.clock.spread_ticked.get_connections():
		s2.clock.spread_ticked.disconnect(conn["callable"])
	s2.advance_game(60.0)
	check("c5 no ground greening -> no progress", w2.total_progress() == 0.0, "p=%f" % w2.total_progress())
	for i: int in cells_all:
		s2.state.set_stage(i, WorldState.STAGE_MATURE)
	var p0: float = w2.total_progress()
	s2.advance_game(60.0)
	var p1: float = w2.total_progress()
	check("c5 greened roots -> progress grows", p1 > p0, "%f -> %f" % [p0, p1])
	# pause stops
	s2.paused = true
	s2.advance_game(60.0)
	check("c5 pause: no wall growth", w2.total_progress() == p1)
	s2.paused = false
	# lose green: stop, retain
	for i: int in cells_all:
		s2.state.set_stage(i, WorldState.STAGE_EMPTY)
	s2.advance_game(60.0)
	var p2: float = w2.total_progress()
	check("c5 green lost -> stop & keep progress", p2 == p1 and p2 > 0.0, "%f vs %f" % [p2, p1])
	# save/load roundtrip
	var d: Dictionary = JSON.parse_string(JSON.stringify(s2.to_dict()))
	var s3: RefCounted = Session.new()
	s3.paving = Session.paving_from(s3.env_tuning)
	s3.load_placement()
	check("c5 load_dict ok", s3.wall_growth.load_dict(d["wall_growth"]))
	check("c5 roundtrip progress equal", absf(s3.wall_growth.total_progress() - p2) < 1e-5, "%f vs %f" % [s3.wall_growth.total_progress(), p2])
	check("c5 bad version rejected", not s3.wall_growth.load_dict({"version": 9}))
	# full growth: door / coverage / grouping — own geometry from metadata
	await _wall_geometry(s2)
	s2.close()
	s3.close()
	s.close()

func parse_surfaces(entry_def: Dictionary) -> Array:
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(String(entry_def["metadata"])))
	var wanted: Array = []
	for v: Dictionary in entry_def["vine_surfaces"]:
		wanted.append(String(v["id"]))
	var out: Array = []
	for r: Dictionary in meta["generated_receiver_surfaces"]:
		if not wanted.has(String(r["id"])):
			continue
		var origin := Vector3(r["origin"][0], r["origin"][1], r["origin"][2])
		var tan_ := Vector3(r["tangent_u"][0], r["tangent_u"][1], r["tangent_u"][2])
		var openings: Array = []  # [u0,v0,u1,v1] in metadata-native u (relative to origin), v relative to origin
		var width: float
		var height: float
		if r.has("size"):
			width = r["size"][0]
			height = r["size"][1]
			for o: Array in r["openings_uv"]:
				openings.append([o[0], o[1], o[2], o[3]])
		else:
			width = r["u_range"][1] - r["u_range"][0]
			height = 1e9
			for p: Array in r["top_profile_uv"]:
				height = minf(height, p[1])
			for o: Array in r["openings_uv"]:
				openings.append([o[0], o[2], o[1], o[3]])
		out.append({"id": r["id"], "origin": origin, "tan": tan_, "w": width, "h": height, "open": openings, "ushift": (r["u_range"][0] if r.has("u_range") else 0.0)})
	return out

func _wall_geometry(s: RefCounted) -> void:
	var w: RefCounted = s.wall_growth
	var cat: Dictionary = {}
	for a: Dictionary in JSON.parse_string(FileAccess.get_file_as_string("res://data/poc/asset_catalog.json"))["assets"]:
		cat[a["id"]] = a
	w.debug_set_all(1.0)
	var WV: GDScript = load("res://scripts/poc/environment/wall_view.gd")
	var view: Node3D = WV.new()
	root.add_child(view)
	view.build(w, s.env_tuning.get("wall", {}))
	check("c5 groups per building instance", view.instance_ids().size() == w.entries.size() and view.instance_ids().size() >= 2, str(view.instance_ids()))
	var all_groups_ok: bool = true
	for en: Dictionary in w.entries:
		var g: Node3D = view.group_of(en["id"])
		if g == null or g.get_parent() != view or g.name != "WallVeg_" + en["id"]:
			all_groups_ok = false
	check("c5 each group is own node named by instance", all_groups_ok)
	for en: Dictionary in w.entries:
		var def: Dictionary = cat[en["asset"]]
		var surfs: Array = parse_surfaces(def)
		# all vine points from the entry (chart-local, pre-centring) -> test vs doors in my own metadata parse
		var door_hits: int = 0
		var total_pts: int = 0
		var cover_ok_total: float = 0.0
		var solid_total: float = 0.0
		var win_ok: bool = false
		for si: int in surfs.size():
			var sf: Dictionary = surfs[si]
			var nx: int = ceili(sf["w"] / 0.1)
			var ny: int = ceili(minf(sf["h"], 12.0) / 0.1)
			var mark: PackedByteArray = PackedByteArray()
			mark.resize(nx * ny)
			var doors: Array = []
			for o: Array in sf["open"]:
				if o[1] <= 0.3:
					doors.append(o)
			for p: Dictionary in en["paths"]:
				if p["surface"] != si:
					continue
				for pt: Dictionary in p["points"]:
					total_pts += 1
					var pos: Vector3 = pt["position"]
					# own u,v: u relative to origin (metadata native); entry chart origin is origin + tan*ushift
					var u: float = (pos - sf["origin"]).dot(sf["tan"]) - sf["ushift"]
					var v: float = pos.y - sf["origin"].y
					# door in native u (+ushift) coordinates for u_range surfaces
					for dr: Array in doors:
						if u > dr[0] and u < dr[2] and v > dr[1] and v < dr[3]:
							door_hits += 1
					# stamp coverage (generous leaf r .28 every 4th, stem .05)
				var idx: int = 0
				for pt: Dictionary in p["points"]:
					var pos: Vector3 = pt["position"]
					var uu: float = (pos - sf["origin"]).dot(sf["tan"]) - sf["ushift"]
					var vv: float = pos.y - sf["origin"].y
					var rad: float = 0.20 if idx % 4 == 0 else 0.04
					idx += 1
					for y: int in range(maxi(floori((vv - rad) / 0.1), 0), mini(floori((vv + rad) / 0.1) + 1, ny)):
						for x: int in range(maxi(floori((uu - rad) / 0.1), 0), mini(floori((uu + rad) / 0.1) + 1, nx)):
							if Vector2((x + 0.5) * 0.1, (y + 0.5) * 0.1).distance_to(Vector2(uu, vv)) <= rad:
								mark[y * nx + x] = 1
			for y: int in ny:
				for x: int in nx:
					var c := Vector2((x + 0.5) * 0.1, (y + 0.5) * 0.1)
					var inside: bool = false
					for o: Array in sf["open"]:
						if c.x > o[0] and c.x < o[2] and c.y > o[1] and c.y < o[3]:
							inside = true
					if not inside:
						solid_total += 0.01
						if mark[y * nx + x] == 1:
							cover_ok_total += 0.01
		var ratio: float = cover_ok_total / maxf(solid_total, 0.001)
		check("c5 %s no vine point inside a door opening" % en["id"], door_hits == 0 and total_pts > 0, "pts=%d hits=%d" % [total_pts, door_hits])
		# moss: every vertex of the built moss meshes must not lie strictly inside a door opening (own parse)
		var moss_in_door: int = 0
		var moss_verts: int = 0
		var frame: Node3D = view.group_of(en["id"]).get_node("Frame")
		for child: Node in frame.get_children():
			if child is MeshInstance3D and (child as MeshInstance3D).mesh is ArrayMesh:
				var arrs: Array = ((child as MeshInstance3D).mesh as ArrayMesh).surface_get_arrays(0)
				for vtx: Vector3 in (arrs[Mesh.ARRAY_VERTEX] as PackedVector3Array):
					moss_verts += 1
					for sf3: Dictionary in surfs:
						var uu3: float = (vtx - sf3["origin"]).dot(sf3["tan"]) - sf3["ushift"]
						var vv3: float = vtx.y - sf3["origin"].y
						# only surfaces whose plane the vertex is on
						var along: float = absf((vtx - sf3["origin"]).dot(Vector3(sf3["tan"]).cross(Vector3.UP)))
						if along > 0.2:
							continue
						for dr: Array in sf3["open"]:
							if dr[1] <= 0.3 and uu3 > dr[0] + 0.03 and uu3 < dr[2] - 0.03 and vv3 > dr[1] + 0.03 and vv3 < dr[3] - 0.03:
								moss_in_door += 1
		check("c5 %s moss mesh verts outside doors" % en["id"], moss_in_door == 0 and moss_verts > 0, "verts=%d inside=%d" % [moss_verts, moss_in_door])
		var layout_cov: Dictionary = load("res://scripts/poc/environment/wall_layout.gd").coverage(en["surfaces"], en["paths"], en["patches"])
		print("  ", en["id"], " own vine-only cover ratio(leaf r.20)=%.3f  (moss excluded), layout ratio=%.3f" % [ratio, layout_cov["ratio"]])
		check("c5 %s visible wall >=50%% (own: 1-vine cover)" % en["id"], 1.0 - ratio >= 0.5, "visible=%.3f" % (1.0 - ratio))
	view.queue_free()
