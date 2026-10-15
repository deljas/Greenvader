extends SceneTree
## Independent GPU-window render check for P1-06 (real window, NOT headless; run once with --screen 1). Input is injected
## inside the engine only (key events through Input.parse_input_event); capture = viewport read-back plus PrintWindow of
## the client area (no focus change, no OS input).
## Stages: (1) the player walked into the river edge and stopped, (2) standing in the ford shallows, (3) plant seed fruits on
## mature green / sprout green / wasteland / shore / shallows next to a seed-source fruit and a healing fruit.
## Expected pixels are composed here from the art rows I transcribed from the diff, not by calling PlayArt.
## Run: Godot --path <project> --screen 1 --script res://tests/p1/independent/p1_06_v_gpu.gd [-- --dry]   (--dry: headless logic dry run, no capture)

const OUT: String = "res://evidence/p1/p1-06/independent/"
const T: int = 4
const PLANT_OWNER_BASE: int = 1000000
var results: Array[Dictionary] = []
var main: Node
var dry: bool = false
var observations: Dictionary = {}

const PLANT_ROWS: Array[String] = [".ww.", "wwwr", "rRRR", ".RR."]
const PLANT_PAL: Dictionary = {"w": "ffd6de", "r": "e4566b", "R": "a82746"}
const SRC_ROWS: Array[String] = [".yy.", "yyye", "yees", ".ss."]
const SRC_PAL: Dictionary = {"y": "ffe5a0", "e": "f7d5a0", "s": "dcab72"}
const HEAL_ROWS: Array[String] = [".bb.", "bkKb", "bKkb", ".bb."]
const HEAL_PAL: Dictionary = {"b": "9c7469", "k": "a8d65a", "K": "6fa83a"}

func _initialize() -> void:
	run.call_deferred()

func rec(id: String, cond: String, ok: bool, observed: String) -> void:
	results.append({"id": id, "condition": cond, "status": "PASS" if ok else "FAIL", "observed": observed})
	print("%s [%s] %s :: %s" % ["PASS" if ok else "FAIL", id, cond, observed])

func hex_rgb(h: String) -> Array:
	return [h.substr(0, 2).hex_to_int(), h.substr(2, 2).hex_to_int(), h.substr(4, 2).hex_to_int()]

func lin(c: float) -> float:
	var v: float = c / 255.0
	return v / 12.92 if v <= 0.04045 else pow((v + 0.055) / 1.055, 2.4)

func lum(rgb: Array) -> float:
	return 0.2126 * lin(rgb[0]) + 0.7152 * lin(rgb[1]) + 0.0722 * lin(rgb[2])

func contrast(a: Array, b: Array) -> float:
	var la: float = lum(a)
	var lb: float = lum(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)

func rgb_dist(a: Array, b: Array) -> float:
	return sqrt(pow(a[0] - b[0], 2) + pow(a[1] - b[1], 2) + pow(a[2] - b[2], 2))

func px(img: Image, x: int, y: int) -> Array:
	var c: Color = img.get_pixel(x, y)
	return [roundi(c.r * 255.0), roundi(c.g * 255.0), roundi(c.b * 255.0)]

func key_event(code: Key, pressed: bool) -> void:
	var e: InputEventKey = InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = pressed
	Input.parse_input_event(e)

func frames(n: int) -> void:
	for i: int in n:
		await process_frame

func ticks(n: int) -> void:
	for i: int in n:
		await physics_frame

func capture(name: String) -> Dictionary:
	await frames(6)
	await RenderingServer.frame_post_draw
	var info: Dictionary = {"name": name}
	if dry:
		return info
	var vp: Image = root.get_texture().get_image()
	vp.convert(Image.FORMAT_RGBA8)
	vp.save_png(ProjectSettings.globalize_path(OUT + "gpu_%s_viewport_640x360.png" % name))
	var native_path: String = ProjectSettings.globalize_path(OUT + "gpu_%s_window_native.png" % name)
	var script_path: String = ProjectSettings.globalize_path("res://tests/independent/p0_verify_printwindow.ps1")
	var hwnd: int = DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE, 0)
	var pid: int = OS.create_process("powershell", ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", script_path, "-Hwnd", str(hwnd), "-Out", native_path])
	var waited: int = 0
	while pid > 0 and OS.is_process_running(pid) and waited < 1800:
		await process_frame
		waited += 1
	var native: Image = Image.load_from_file(native_path)
	native.convert(Image.FORMAT_RGBA8)
	var k: int = native.get_width() / 640
	var nd: PackedByteArray = native.get_data()
	var vd: PackedByteArray = vp.get_data()
	var bad: int = 0
	var mism: int = 0
	var w: int = native.get_width()
	for y: int in 360:
		for x: int in 640:
			var o0: int = ((y * k) * w + x * k) * 4
			for dy: int in k:
				for dx: int in k:
					var oo: int = ((y * k + dy) * w + x * k + dx) * 4
					if nd[oo] != nd[o0] or nd[oo + 1] != nd[o0 + 1] or nd[oo + 2] != nd[o0 + 2]:
						bad += 1
			var vo: int = (y * 640 + x) * 4
			if nd[o0] != vd[vo] or nd[o0 + 1] != vd[vo + 1] or nd[o0 + 2] != vd[vo + 2]:
				mism += 1
	rec("gpu.%s.size" % name, "%s: PrintWindow capture is 1280x720 (k=2) and the internal frame 640x360" % name, native.get_size() == Vector2i(1280, 720) and vp.get_size() == Vector2i(640, 360), "native=%s vp=%s" % [native.get_size(), vp.get_size()])
	rec("gpu.%s.k2_uniform" % name, "%s: every 2x2 block of the window image is a single colour" % name, bad == 0, "non-uniform samples %d" % bad)
	rec("gpu.%s.native_equals_internal" % name, "%s: each block equals the internal frame pixel" % name, mism == 0, "mismatching %d of 230400" % mism)
	info["vp"] = vp
	return info

func screen_tl(world_px: Vector2) -> Vector2i:
	var s: Vector2 = main.get_viewport().get_canvas_transform() * world_px
	return Vector2i(roundi(s.x), roundi(s.y))

func check_art(vp: Image, world_center: Vector2, rows: Array[String], pal: Dictionary) -> Dictionary:
	var tl: Vector2i = screen_tl((world_center - Vector2(2, 2)).round())
	var bad: int = 0
	var first: String = ""
	var bgs: Array = []
	for y: int in 4:
		for x: int in 4:
			var ch: String = rows[y].substr(x, 1)
			var got: Array = px(vp, tl.x + x, tl.y + y)
			if ch != ".":
				var want: Array = hex_rgb(pal[ch])
				if got != want:
					bad += 1
					if first == "":
						first = "(%d,%d) '%s' want %s got %s" % [x, y, ch, str(want), str(got)]
	# ring of 1 px around the 4x4 for background and outline check
	var ring: Array = []
	for y: int in range(-1, 5):
		for x: int in range(-1, 5):
			if x >= 0 and x < 4 and y >= 0 and y < 4:
				continue
			ring.append(px(vp, tl.x + x, tl.y + y))
	# corner pixels of the 4x4 art ('.') show the background too
	for y: int in 4:
		for x: int in 4:
			if rows[y].substr(x, 1) == ".":
				ring.append(px(vp, tl.x + x, tl.y + y))
	var mean: Array = [0.0, 0.0, 0.0]
	var darkest: float = 1.0
	for c: Array in ring:
		for i: int in 3:
			mean[i] += float(c[i]) / ring.size()
		darkest = minf(darkest, lum(c))
	return {"tl": str(tl), "bad": bad, "first": first, "bg": [roundi(mean[0]), roundi(mean[1]), roundi(mean[2])], "ring_darkest_lum": snappedf(darkest, 0.001), "ring_n": ring.size()}

func run() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a == "--dry":
			dry = true
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await frames(3)
	var w: WorldState = main.grid
	var play: PlayState = main.play
	var player: FlowerPlayer = main.player
	print("GPU_INFO renderer=%s window=%s size=%s screen=%d dry=%s" % [RenderingServer.get_current_rendering_method(), root.position, root.size, root.current_screen, dry])
	# ---- stage 1: the water's edge (row 100): walk east with an injected D key until stopped
	player.simulation_position = Vector2(940.0, 402.0)
	await ticks(4)
	key_event(KEY_D, true)
	await ticks(150)
	key_event(KEY_D, false)
	await ticks(10)
	rec("gpu.edge.stopped", "the player walked east and stopped with the feet at the water edge x=981 (injected D held 2.5 s)", absf(player.simulation_position.x - 981.0) < 0.01, str(player.simulation_position))
	var cap1: Dictionary = await capture("edge")
	if not dry:
		var vp1: Image = cap1["vp"]
		# pixel left of the water edge vs right of it, at the player's row
		var left_px: Array = px(vp1, screen_tl(Vector2(982.0, 402.0)).x, screen_tl(Vector2(982.0, 402.0)).y)
		var right_px: Array = px(vp1, screen_tl(Vector2(985.0, 402.0)).x, screen_tl(Vector2(985.0, 402.0)).y)
		var water_ground: Array = [roundi(0.224 * 255.0), roundi(0.525 * 255.0), roundi(0.604 * 255.0)]
		observations["edge_pixels"] = {"left_982": left_px, "right_985": right_px}
		rec("gpu.edge.water_beyond", "the screen pixel just beyond the feet (x=985) is water-coloured, the pixel under the feet's right edge (x=982) is not", rgb_dist(right_px, water_ground) < 40.0 and rgb_dist(left_px, water_ground) > 40.0, "left %s right %s water %s" % [left_px, right_px, water_ground])
		var crop: Image = vp1.get_region(Rect2i(screen_tl(player.position).x - 40, screen_tl(player.position).y - 30, 100, 60))
		crop.resize(crop.get_width() * 8, crop.get_height() * 8, Image.INTERPOLATE_NEAREST)
		crop.save_png(ProjectSettings.globalize_path(OUT + "gpu_edge_crop_x8.png"))
	# ---- stage 2: standing in the ford
	player.simulation_position = Vector2(258.5 * T, 202.5 * T)
	await ticks(20)
	var cap2: Dictionary = await capture("ford")
	rec("gpu.ford.on_shallows", "the player stands on a shallows tile", w.terrain[202 * w.width + 258] == 5 and not main.player.walk_world.is_walkable(246, 195), "")
	if not dry:
		var vp2: Image = cap2["vp"]
		var crop2: Image = vp2.get_region(Rect2i(screen_tl(player.position).x - 60, screen_tl(player.position).y - 40, 120, 80))
		crop2.resize(crop2.get_width() * 6, crop2.get_height() * 6, Image.INTERPOLATE_NEAREST)
		crop2.save_png(ProjectSettings.globalize_path(OUT + "gpu_ford_crop_x6.png"))
	# ---- stage 3: fruits
	var layout: Dictionary = {}
	w.debug_fill_stage(Rect2i(224, 52, 10, 5), WorldState.STAGE_MATURE)
	w.debug_fill_stage(Rect2i(224, 58, 10, 3), WorldState.STAGE_SPROUT1)
	var spots: Array = [
		["mature", Vector2i(226, 54), Vector2i(229, 54), Vector2i(232, 54)],
		["sprout", Vector2i(226, 59), Vector2i(229, 59), Vector2i(232, 59)],
		["wasteland", Vector2i(226, 64), Vector2i(229, 64), Vector2i(232, 64)],
		["shore", Vector2i(243, 50), Vector2i(243, 53), Vector2i(243, 56)],
		["shallows", Vector2i(250, 62), Vector2i(253, 62), Vector2i(256, 62)],
	]
	player.simulation_position = Vector2(238.5 * T, 61.5 * T)
	await ticks(10)
	var expect_terrain: Dictionary = {"mature": 0, "sprout": 0, "wasteland": 0, "shore": 2, "shallows": 5}
	var terrain_ok: bool = true
	for entry: Array in spots:
		for i: int in 3:
			var tile: Vector2i = entry[1 + i]
			if w.terrain[tile.y * w.width + tile.x] != int(expect_terrain[entry[0]]):
				terrain_ok = false
		var t0: Vector2i = entry[1]
		var c0: Vector2 = (Vector2(t0) + Vector2(0.5, 0.5)) * T
		play.pickups.spawn(GroundPickups.KIND_SEED_FRUIT, c0, PLANT_OWNER_BASE + t0.y * w.width + t0.x, 1000.0)
		var t1: Vector2i = entry[2]
		play.pickups.spawn(GroundPickups.KIND_SEED_FRUIT, (Vector2(t1) + Vector2(0.5, 0.5)) * T, 1, 1000.0)
		var t2: Vector2i = entry[3]
		play.pickups.spawn(GroundPickups.KIND_HEAL_FRUIT, (Vector2(t2) + Vector2(0.5, 0.5)) * T, 2000000 + 1, 1000.0)
	rec("gpu.fruit.layout", "fruit test layout: the chosen tiles have the intended terrain; nothing else picked up (player 20+ px from all fruits)", terrain_ok and play.pickups.items.size() == 15, "items %d" % play.pickups.items.size())
	await ticks(5)
	var cap3: Dictionary = await capture("fruit")
	if not dry:
		var vp3: Image = cap3["vp"]
		var summary: Dictionary = {}
		var all_art_ok: bool = true
		var readable: bool = true
		var min_dist_plant_src: float = 1000.0
		for entry: Array in spots:
			var name: String = entry[0]
			var t0: Vector2i = entry[1]
			var c0: Vector2 = (Vector2(t0) + Vector2(0.5, 0.5)) * T
			var r0: Dictionary = check_art(vp3, c0, PLANT_ROWS, PLANT_PAL)
			var t1: Vector2i = entry[2]
			var r1: Dictionary = check_art(vp3, (Vector2(t1) + Vector2(0.5, 0.5)) * T, SRC_ROWS, SRC_PAL)
			var t2: Vector2i = entry[3]
			var r2: Dictionary = check_art(vp3, (Vector2(t2) + Vector2(0.5, 0.5)) * T, HEAL_ROWS, HEAL_PAL)
			if int(r0["bad"]) != 0 or int(r1["bad"]) != 0 or int(r2["bad"]) != 0:
				all_art_ok = false
			# readability of the plant fruit on this background (measured from the rendered pixels around it)
			var bg: Array = r0["bg"]
			var good: int = 0
			var mind: float = 1000.0
			var det: Dictionary = {}
			for key: String in PLANT_PAL:
				var col: Array = hex_rgb(PLANT_PAL[key])
				var cr: float = contrast(col, bg)
				var dd: float = rgb_dist(col, bg)
				det[key] = {"contrast": snappedf(cr, 0.01), "dist": snappedf(dd, 1.0)}
				if cr >= 1.8:
					good += 1
				mind = minf(mind, dd)
			if good < 2 or mind < 80.0:
				readable = false
			summary[name] = {"plant": r0, "source": r1, "heal": r2, "plant_vs_bg": det}
			rec("gpu.fruit.readable_" + name, "plant fruit on %s: >= 2 of its 3 colours have luminance contrast >= 1.8 against the rendered surroundings and all 3 are >= 80 away in RGB" % name, good >= 2 and mind >= 80.0, JSON.stringify(det) + " bg=" + str(bg))
			rec("gpu.fruit.pixels_" + name, "on %s the three fruits are drawn pixel-exact (plant, seed-source, healing) with no dark outline ring (ring luminance >= 0.2)" % name, int(r0["bad"]) == 0 and int(r1["bad"]) == 0 and int(r2["bad"]) == 0 and float(r0["ring_darkest_lum"]) >= 0.2, "plant %s | source %s | heal %s" % [JSON.stringify(r0), JSON.stringify(r1), JSON.stringify(r2)])
		# colour distinctness between the three fruit kinds
		var distinct: bool = true
		var worst: float = 1000.0
		for pk: String in PLANT_PAL:
			for sk: String in SRC_PAL:
				worst = minf(worst, rgb_dist(hex_rgb(PLANT_PAL[pk]), hex_rgb(SRC_PAL[sk])))
			for hk: String in HEAL_PAL:
				worst = minf(worst, rgb_dist(hex_rgb(PLANT_PAL[pk]), hex_rgb(HEAL_PAL[hk])))
		distinct = worst >= 60.0
		rec("gpu.fruit.distinct_kinds", "no colour of the plant fruit is within 60 RGB units of any colour of the seed-source fruit or the healing fruit", distinct, "closest pair %.1f" % worst)
		observations["fruit_summary"] = summary
		# crop of each row for my eyes: x8
		var tl: Vector2i = screen_tl(Vector2(222 * T, 50 * T))
		var crop3: Image = vp3.get_region(Rect2i(tl.x, tl.y, 130, 80))
		crop3.resize(crop3.get_width() * 6, crop3.get_height() * 6, Image.INTERPOLATE_NEAREST)
		crop3.save_png(ProjectSettings.globalize_path(OUT + "gpu_fruit_west_crop_x6.png"))
		var tl2: Vector2i = screen_tl(Vector2(240 * T, 48 * T))
		var crop4: Image = vp3.get_region(Rect2i(tl2.x, tl2.y, 80, 85))
		crop4.resize(crop4.get_width() * 6, crop4.get_height() * 6, Image.INTERPOLATE_NEAREST)
		crop4.save_png(ProjectSettings.globalize_path(OUT + "gpu_fruit_bank_crop_x6.png"))
	# ---- stage 4: frame cost in the real window with the stress fixture (vsync off)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	w.debug_fill_stage(Rect2i(30, 220, 150, 160), WorldState.STAGE_MATURE)
	for y: int in range(400, 500):
		for x: int in range(30, 150):
			var idx: int = y * w.width + x
			if w.set_stage(idx, WorldState.STAGE_SEED):
				w.set_moisture(idx, 100)
	player.simulation_position = Vector2(100 * T, 390 * T)
	var proc: PackedFloat64Array = PackedFloat64Array()
	var wall: PackedFloat64Array = PackedFloat64Array()
	var last: int = 0
	for i: int in 400:
		if i % 10 == 0:
			play.add_seeds(1)
			play.add_water(10.0)
			main.fire(i % 30 == 0, player.simulation_position + Vector2.from_angle(i * 0.5) * 80.0)
		await process_frame
		var now: int = Time.get_ticks_usec()
		if last > 0 and i > 20:
			wall.append((now - last) / 1000.0)
			proc.append((Performance.get_monitor(Performance.TIME_PROCESS) + Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0)
		last = now
	wall.sort()
	proc.sort()
	var mean_wall: float = 0.0
	for v: float in wall:
		mean_wall += v / wall.size()
	observations["gpu_stress_frame"] = {"frames": wall.size(), "wall_mean_ms": mean_wall, "wall_p99_ms": wall[int(wall.size() * 0.99)], "wall_max_ms": wall[wall.size() - 1], "script_p99_ms": proc[int(proc.size() * 0.99)], "script_max_ms": proc[proc.size() - 1]}
	rec("gpu.stress_frame", "real window (vsync off), stress fixture: wall time per frame stays under 16 ms (p99) and the script CPU (process+physics monitors) max under 16 ms", dry or (wall[int(wall.size() * 0.99)] < 16.0 and proc[proc.size() - 1] < 16.0), JSON.stringify(observations["gpu_stress_frame"]))
	var f: FileAccess = FileAccess.open(OUT + ("checks_gpu_dry.json" if dry else "checks_gpu.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify({"results": results, "observations": observations}, "  "))
	f.close()
	var fails: int = 0
	for r: Dictionary in results:
		if r["status"] != "PASS":
			fails += 1
	print("V_RESULT total=%d fails=%d" % [results.size(), fails])
	quit(1 if fails > 0 else 0)
