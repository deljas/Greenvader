extends SceneTree
## Independent GPU: item 7 fade of tall building parts, measured from rendered pixels (not shader parameters).
const Coords: GDScript = preload("res://scripts/poc/poc_coords.gd")
const OUT: String = "res://evidence/poc3/playtest01/independent/gpu_b/"
var main: Node
var s: RefCounted
var capture: SubViewport
var checks: Array[Dictionary] = []
func _init() -> void: call_deferred("run")
func chk(n: String, ok: bool, d: Variant = "") -> void:
	checks.append({"name": n, "status": "PASS" if ok else "FAIL", "detail": d})
	print(JSON.stringify(checks.back()))
func frames(n: int = 2) -> void:
	for i: int in n: await process_frame
func grab() -> Image:
	await frames(2); RenderingServer.force_draw(false)
	return capture.get_texture().get_image()
func scrp(p: Vector2) -> Vector2:
	return main.world.camera.unproject_position(Coords.ground3(Coords.logic_to_ground(p)))
func region_diff(a: Image, b: Image, r: Rect2i) -> float:
	var sum: float = 0.0; var n: int = 0
	for y: int in range(r.position.y, r.end.y):
		for x: int in range(r.position.x, r.end.x):
			if x < 0 or y < 0 or x >= a.get_width() or y >= a.get_height(): continue
			var ca: Color = a.get_pixel(x, y); var cb: Color = b.get_pixel(x, y)
			sum += absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b); n += 1
	return sum / float(maxi(n, 1)) * 255.0
func run() -> void:
	var safe: bool = root.unfocusable and root.mode == Window.MODE_MINIMIZED
	chk("startup_no_focus_minimized", safe)
	if not safe: quit(1); return
	change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene"))
	await frames()
	main = current_scene
	main.auto_process = false
	main._audio_changed(true, 0.0)
	main._on_action("new")
	s = main.session
	s.enemies.clear(); s.nests.clear(); s.fossils.clear()
	capture = SubViewport.new()
	capture.size = Vector2i(640, 360); capture.disable_3d = true
	capture.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(capture)
	main.view_rect.reparent(capture); main.ui.reparent(capture)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var occ: Node = main.world.occlusion
	var judge: RefCounted = occ.judge
	var camera: Camera3D = main.world.camera
	# find a tall building and a floor point directly behind its centre that the judge says is occluded
	var spot: Vector2 = Vector2(-1, -1); var group: String = ""; var height: float = 0.0
	for entry: Dictionary in judge.entries:
		var box: AABB = AABB(); var first: bool = true
		for part: Dictionary in entry.parts:
			box = (part.aabb as AABB) if first else box.merge(part.aabb); first = false
		if box.size.y < 5.0 or box.size.x > 14.0 or box.size.z > 14.0: continue
		var c: Vector3 = box.get_center()
		var logic: Vector2 = Coords.ground_to_logic(Vector2(c.x, c.z))
		var pts: PackedVector3Array = judge.sample_points(Vector3(c.x, 0.0, c.z), main.world.actor.pixel_size * 34.0, camera.global_basis.x)
		if judge.raw_occluders(pts, camera.global_basis.z).has(entry.group):
			spot = logic; group = entry.group; height = box.size.y; break
	chk("found_tall_building_with_hidden_spot", group != "", {"group": group, "spot": spot, "height_m": height})
	if group == "": quit(1); return
	var away: Vector2 = spot + Vector2(70, 50)
	s.position = away
	for i: int in 40: main.world.sync(0.05)
	var ref: Image = await grab()
	ref.save_png(ProjectSettings.globalize_path(OUT + "ref_opaque.png"))
	s.position = spot
	var foot: Vector2 = scrp(spot)
	var upper: Rect2i = Rect2i(200, 15, 230, 95)  # building roof area on screen (camera is fixed in this scene)
	var lower: Rect2i = Rect2i(Vector2i(foot) + Vector2i(-30, -50), Vector2i(60, 40))
	var imgs: Array[Image] = []
	for i: int in 24:
		main.world.sync(0.012)
		imgs.append(await grab())
	imgs[0].save_png(ProjectSettings.globalize_path(OUT + "out_00.png"))
	for i: int in [1, 2, 3, 4, 5, 6, 8, 12, 23]:
		imgs[i].save_png(ProjectSettings.globalize_path(OUT + "out_%02d.png" % i))
	var final: Image = imgs[23]
	var up_total: float = region_diff(imgs[0], final, upper)
	var lo_total: float = region_diff(ref, final, lower)
	var up_prog: Array = []; var lo_prog: Array = []
	for i: int in 24:
		up_prog.append(snappedf(region_diff(imgs[0], imgs[i], upper) / maxf(up_total, 0.001), 0.01))
		lo_prog.append(snappedf(region_diff(ref, imgs[i], lower) / maxf(lo_total, 0.001), 0.01))
	var mid_up: int = 0
	for v: float in up_prog:
		if v > 0.1 and v < 0.9: mid_up += 1
	var mono: bool = true
	for i: int in range(1, 24): mono = mono and up_prog[i] >= up_prog[i - 1] - 0.08
	chk("item7_fade_out_upper_region_has_intermediate_frames", up_total > 3.0 and mid_up >= 3 and up_prog[0] < 0.5 and up_prog[23] > 0.95, {"up_total": up_total, "mid": mid_up, "prog": up_prog})
	chk("item7_fade_out_upper_roughly_monotone", mono)
	# return fade (own pace: 0.03 s steps for 1.5 s)
	s.position = away
	var back: Array[Image] = []
	for i: int in 50:
		main.world.sync(0.03)
		back.append(await grab())
	for i: int in [0, 3, 6, 9, 12, 16, 20, 30, 49]: back[i].save_png(ProjectSettings.globalize_path(OUT + "in_%02d.png" % i))
	var in_total: float = region_diff(back[6], back[49], upper)
	var in_prog: Array = []
	for i: int in range(6, 50): in_prog.append(snappedf(1.0 - region_diff(back[49], back[i], upper) / maxf(in_total, 0.001), 0.01))
	var mid_in: int = 0
	for v: float in in_prog:
		if v > 0.1 and v < 0.9: mid_in += 1
	var seq_ok: bool = true
	for i: int in range(1, in_prog.size()): seq_ok = seq_ok and in_prog[i] >= in_prog[i - 1] - 0.08
	chk("item7_fade_in_upper_region_has_intermediate_frames_and_monotone", in_total > 10.0 and mid_in >= 3 and in_prog[-1] > 0.97 and in_prog[0] < 0.1 and seq_ok, {"total": in_total, "mid": mid_in, "prog": in_prog})
	chk("item7_restored_matches_original_opaque_frame", region_diff(ref, back[49], Rect2i(0, 0, 640, 360)) < 0.5, region_diff(ref, back[49], Rect2i(0, 0, 640, 360)))
	# contact sheet of upper region
	var sel: Array = [0, 1, 2, 3, 4, 6, 8, 23]
	var sheet: Image = Image.create(240 * sel.size(), 160, false, imgs[0].get_format())
	for k: int in sel.size():
		var part: Image = imgs[sel[k]].get_region(Rect2i(200, 15, 120, 80))
		part.resize(240, 160, Image.INTERPOLATE_NEAREST)
		sheet.blit_rect(part, Rect2i(0, 0, 240, 160), Vector2i(k * 240, 0))
	sheet.save_png(ProjectSettings.globalize_path(OUT + "fade_out_sheet.png"))
	var f: int = 0
	for r: Dictionary in checks:
		if r.status == "FAIL": f += 1
	var fa: FileAccess = FileAccess.open(OUT + "results.json", FileAccess.WRITE)
	fa.store_string(JSON.stringify({"checks": checks, "failures": f}, "  ")); fa.close()
	quit(1 if f else 0)
