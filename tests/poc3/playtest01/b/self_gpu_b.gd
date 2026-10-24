extends SceneTree
## POC3-PLAYTEST-01 work B real GPU images at 640x360 (offscreen composite; window stays minimized, no focus).
## Item 5 gatlinger volley, item 6 price display, item 7 upper-part fade of the building cutaway.
const Coords: GDScript = preload("res://scripts/poc/poc_coords.gd")
const OUT: String = "res://evidence/poc3/playtest01/self/b_gpu/"
var main: Node
var s: RefCounted
var capture: SubViewport
var checks: Array[Dictionary] = []
var data: Dictionary = {}

func _init() -> void: call_deferred("run")
func check(name_: String, ok: bool, detail: Variant = "") -> void:
	checks.append({"name": name_, "status": "PASS" if ok else "FAIL", "detail": detail})
	print(JSON.stringify(checks.back()))
func frames(n: int = 3) -> void:
	for i: int in n: await process_frame
func grab() -> Image:
	await frames(2); RenderingServer.force_draw(false)
	return capture.get_texture().get_image()
func screen_of(pos: Vector2) -> Vector2:
	return main.world.camera.unproject_position(Coords.ground3(Coords.logic_to_ground(pos)))
func crop_scaled(image: Image, center: Vector2, size: Vector2i, factor: int) -> Image:
	var rect: Rect2i = Rect2i(Vector2i(center) - size / 2, size).intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	var part: Image = image.get_region(rect)
	part.resize(rect.size.x * factor, rect.size.y * factor, Image.INTERPOLATE_NEAREST)
	return part

func gatling_case(label: String, interval: float, volley: int) -> Dictionary:
	s.plant_system.gatling_interval = interval
	s.plant_system.gatling_volley = volley
	s.seeds = 500
	var placed: Dictionary = s.place_helper("gatlinger", Vector2i(117, 112), 100)
	var h: Dictionary = s.helpers.back()
	var id: int = int(h.id)
	var ammo0: int = int(h.ammo)
	var t: float = 0.0
	var best: Image = null
	var best_n: int = 0
	var centre: Vector2 = screen_of(h.pos)
	var last_ammo: int = ammo0
	var fired_at: Array = []
	while t < 6.0:
		main.tick(0.04); t += 0.04
		if int(h.ammo) != last_ammo:
			fired_at.append([snappedf(t, 0.01), last_ammo - int(h.ammo)])
			last_ammo = int(h.ammo)
		var in_flight: int = 0
		for shot: Dictionary in s.shots:
			if shot.get("source_type", "") == "helper": in_flight += 1
		if in_flight > best_n and t > 0.1:
			best_n = in_flight
			best = await grab()
	var rate: float = float(ammo0 - int(h.ammo)) / t
	if best != null:
		var big: Image = crop_scaled(best, centre, Vector2i(200, 150), 4)
		check("img_gatling_" + label, big.save_png(OUT + "gatling_" + label + ".png") == OK)
	s.remove_helper(id)
	return {"label": label, "interval": interval, "volley": volley, "placed": placed.ok, "ammo_used_6s": ammo0 - last_ammo, "seeds_per_second": rate, "max_in_flight": best_n, "fire_times": fired_at.slice(0, 8)}

func price_section() -> void:
	s.unlocked["watermelon"] = true; s.unlocked["wheat"] = true; s.seeds = 100000
	var table: Dictionary = {"clover": [], "carrot": [], "watermelon": []}
	var shown: Array = []
	var imgs: Array = []
	for kind: String in ["clover", "carrot", "watermelon"]:
		s.plants.clear()
		for n: int in 6:
			table[kind].append(s.current_cost(kind))
			s.plants.append({"kind": kind, "hp": 10.0, "mature": false})
	s.plants.clear()
	for n: int in 6:
		if n > 0:
			var placed: Dictionary = s.place_plant("clover", Vector2i(106 + n * 2, 106))
			if not placed.ok: check("price_real_placement_" + str(n), false, placed); return
		main.ui.clear_selection()
		main.ui.select_slot(0)
		main.ui.refresh()
		shown.append([n, s.current_cost("clover"), main.ui.status.text])
		if n == 0 or n == 5:
			var img: Image = await grab()
			imgs.append(img)
			img.save_png(OUT + "price_clover_n" + str(n) + ".png")
	main.ui.clear_selection()
	var expected: Array = [10, 11, 13, 14, 15, 17]
	check("price_table_clover_ceil_1_1", table.clover == expected, table)
	check("price_table_carrot_watermelon", table.carrot == [15, 17, 19, 20, 22, 25] and table.watermelon == [120, 132, 146, 160, 176, 194], table)
	var ok_text: bool = true
	for row: Array in shown:
		ok_text = ok_text and String(row[2]).contains("●" + str(expected[row[0]]))
	check("price_ui_status_matches_formula_n0_to_5", ok_text, shown)
	data["price_table"] = table
	data["price_ui_status"] = shown
	s.plants.clear()
	main.tick(0.0)

func fade_section() -> void:
	var occ: Node = main.world.occlusion
	var judge: RefCounted = occ.judge
	# Find a building (height > 4 m) and a ground point behind it that the occlusion judge hits.
	var spot: Vector2 = Vector2(-1, -1)
	var group: String = ""
	var camera: Camera3D = main.world.camera
	for entry: Dictionary in judge.entries:
		var box: AABB = AABB()
		var first: bool = true
		for part: Dictionary in entry.parts:
			box = (part.aabb as AABB) if first else box.merge(part.aabb)
			first = false
		if box.size.y < 4.0 or box.size.x > 14.0 or box.size.z > 14.0: continue
		var c: Vector3 = box.get_center()
		var back: Vector3 = -camera.global_basis.z
		back.y = 0.0
		back = back.normalized()
		for d: float in [0.5, 1.0, 1.5, 2.0]:
			var p: Vector3 = Vector3(c.x, 0.0, c.z) + back * (box.size.length() * 0.0) + back * (d + 0.3 * maxf(box.size.x, box.size.z)) * 0.0
			p = Vector3(c.x, 0.0, c.z)
			var logic: Vector2 = Coords.ground_to_logic(Vector2(p.x, p.z))
			var pts: PackedVector3Array = judge.sample_points(p, main.world.actor.pixel_size * 34.0, camera.global_basis.x)
			var raw: Dictionary = judge.raw_occluders(pts, camera.global_basis.z)
			if raw.has(entry.group):
				spot = logic; group = entry.group
				break
		if group != "": break
	data["fade_spot"] = [spot.x, spot.y, group]
	check("fade_found_hidden_spot_behind_building", group != "", data["fade_spot"])
	if group == "": return
	var away: Vector2 = spot + Vector2(60, 40)
	s.position = away
	for i: int in 30: main.world.sync(0.05)
	await frames(2)
	s.position = spot
	var log: Array = []
	var crops: Array = []
	var in_log: Array = []
	var in_crops: Array = []
	var centre: Vector2 = screen_of(spot)
	data["fade_centre"] = [centre.x, centre.y]
	# Frame 0: fully opaque reference (before the player steps behind the building).
	s.position = away
	main.world.sync(0.0)
	var reference: Image = await grab()
	reference.save_png(OUT + "fade_reference_opaque.png")
	s.position = spot
	# Fade out: several small steps, every one captured.
	for i: int in 8:
		main.world.sync(0.03)
		var a: float = judge.alpha_of(group)
		var u: float = float(occ.last_upper_fade.get(group, 0.0))
		var shader_u: float = -1.0
		if occ.records.has(group):
			for item: Dictionary in occ.records[group]:
				if not (item.cut as Array).is_empty():
					shader_u = float((item.cut[0] as ShaderMaterial).get_shader_parameter("upper_fade"))
					break
		log.append({"phase": "out", "step": i, "alpha_lower": a, "upper_fade": u, "upper_opacity": 1.0 - u, "shader_upper_fade": shader_u})
		var img: Image = await grab()
		crops.append(crop_scaled(img, screen_of(s.position) + Vector2(0, -50), Vector2i(150, 150), 2))
	# Fade in: step away and capture every step.
	s.position = away
	for i: int in 16:
		main.world.sync(0.05)
		var a: float = judge.alpha_of(group)
		var u: float = float(occ.last_upper_fade.get(group, 0.0))
		in_log.append({"step": i, "alpha_lower": a, "upper_opacity": 1.0 - u})
		var img: Image = await grab()
		if i >= 6 and i <= 13:
			in_crops.append(crop_scaled(img, screen_of(spot) + Vector2(0, -50), Vector2i(150, 150), 2))
	data["fade_log_out"] = log
	data["fade_log_in"] = in_log
	var out_u: Array = []
	for row: Dictionary in log:
		if row.phase == "out": out_u.append(snappedf(float(row.upper_opacity), 0.001))
	var mids: int = 0
	for v: float in out_u:
		if v > 0.02 and v < 0.98: mids += 1
	check("upper_opacity_goes_gradually_not_abrupt", mids >= 3 and out_u[0] > 0.5 and out_u[-1] < 0.02, out_u)
	var monotone: bool = true
	for i: int in range(1, out_u.size()):
		monotone = monotone and out_u[i] <= out_u[i - 1] + 0.0001
	check("upper_opacity_monotone_during_fade_out", monotone, out_u)
	var in_u: Array = []
	for row: Dictionary in in_log: in_u.append(snappedf(float(row.upper_opacity), 0.001))
	var inc_mid: int = 0
	for v: float in in_u:
		if v > 0.02 and v < 0.98: inc_mid += 1
	check("upper_opacity_returns_gradually", inc_mid >= 2 and in_u[-1] > 0.99, in_u)
	check("lower_and_upper_share_progress", abs((1.0 - float(log[3].alpha_lower)) / 0.76 - float(log[3].upper_fade)) < 0.01, log[3])
	# Contact sheets
	for pair: Array in [["fade_out_sheet.png", crops], ["fade_in_sheet.png", in_crops]]:
		var list: Array = pair[1]
		if list.is_empty(): continue
		var w: int = (list[0] as Image).get_width()
		var h: int = (list[0] as Image).get_height()
		var sheet: Image = Image.create(w * list.size(), h, false, (list[0] as Image).get_format())
		for i: int in list.size():
			sheet.blit_rect(list[i], Rect2i(Vector2i.ZERO, Vector2i(w, h)), Vector2i(i * w, 0))
		check("img_" + pair[0], sheet.save_png(OUT + pair[0]) == OK)
	# Pixel evidence: consecutive out frames must differ
	var hashes: Array = []
	for img: Image in crops: hashes.append(hash(img.get_data()))
	var distinct: Dictionary = {}
	for hv: Variant in hashes: distinct[hv] = true
	check("out_frames_are_distinct_images", distinct.size() >= 4, distinct.size())

func run() -> void:
	var safe: bool = root.unfocusable and root.mode == Window.MODE_MINIMIZED and ProjectSettings.get_setting("display/window/size/no_focus", false)
	check("startup_no_focus_minimized", safe)
	if not safe or not OS.get_user_data_dir().replace("\\", "/").contains("evidence/poc3/playtest01/self/b_gpu/profile/"):
		quit(1); return
	change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene"))
	await frames()
	main = current_scene
	main.auto_process = false
	main._audio_changed(true, 0.0)
	main._on_action("new")
	root.notify_mouse_entered()
	s = main.session
	s.enemies.clear(); s.nests.clear(); s.fossils.clear()
	s.known.fill(1)
	capture = SubViewport.new()
	capture.size = Vector2i(640, 360); capture.disable_3d = true
	capture.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(capture)
	main.view_rect.reparent(capture); main.ui.reparent(capture)
	s.unlocked["gatlinger"] = true
	s.position = Coords.cell_center_logic(Vector2i(112, 112))
	main.tick(0.0)
	var after: Dictionary = await gatling_case("after", 1.2, 4)
	var before: Dictionary = await gatling_case("before", 3.0, 1)
	s.plant_system.gatling_interval = 1.2; s.plant_system.gatling_volley = 4
	data["gatling"] = {"before": before, "after": after}
	check("gatling_rate_before_vs_after", float(after.seeds_per_second) >= 3.0 * float(before.seeds_per_second) and int(before.ammo_used_6s) <= 3, data["gatling"])
	await price_section()
	await fade_section()
	check("integer_nearest_rendering", main.render_view.size == Vector2i(640, 360) and main.view_rect.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST)
	check("stayed_no_focus_minimized", root.unfocusable and root.mode == Window.MODE_MINIMIZED)
	var failures: int = 0
	for row: Dictionary in checks:
		if row.status == "FAIL": failures += 1
	var file: FileAccess = FileAccess.open(OUT + "gpu_results.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": checks, "failures": failures, "data": data, "input": "engine-internal only; no OS input"}, "  "))
	file.close()
	s.close()
	quit(1 if failures else 0)
