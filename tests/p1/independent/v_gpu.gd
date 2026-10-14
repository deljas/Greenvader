extends SceneTree
## Independent GPU-window verification for P1-01 (needs a real window, run with --screen 1, NOT headless).
## Engine-internal state changes only; capture via PrintWindow (read-only, no input, no focus change).
## Run: Godot --path <project> --screen 1 --script res://tests/p1/independent/v_gpu.gd

const OUT: String = "res://evidence/p1/p1-01/independent/"
var results: Array[Dictionary] = []

func _initialize() -> void:
	run.call_deferred()

func rec(id: String, cond: String, ok: bool, observed: String) -> void:
	results.append({"id": id, "condition": cond, "status": "PASS" if ok else "FAIL", "observed": observed})
	print("%s [%s] %s :: %s" % ["PASS" if ok else "FAIL", id, cond, observed])

func find_clear_origin(world: WorldState) -> Vector2i:
	# a 90x50 tile rectangle that is entirely wasteland (terrain id 0) and nothing else
	for cy: int in range(300, 440, 4):
		for cx: int in range(300, 440, 4):
			var ok: bool = true
			for y: int in range(cy - 25, cy + 25, 2):
				for x: int in range(cx - 45, cx + 45, 2):
					if world.terrain[y * 512 + x] != 0:
						ok = false
						break
				if not ok:
					break
			if ok:
				return Vector2i(cx, cy)
	return Vector2i(-1, -1)

func put(world: WorldState, o: Vector2i, x: int, y: int, st: int) -> void:
	world.set_stage((o.y + y) * 512 + o.x + x, st)

func run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	var world: WorldState = main.grid
	var c: Vector2i = find_clear_origin(world)
	rec("6.site", "found an all-wasteland 90x50 site away from scenery for the pattern", c.x > 0, str(c))
	if c.x < 0:
		quit(1)
		return
	main.player.simulation_position = Vector2(c * 4) + Vector2(2, 2)
	var o: Vector2i = Vector2i(c.x - 40, c.y - 16)
	# Pattern (my own layout)
	for i: int in 16:
		put(world, o, i, 0, 1)  # seeds
		put(world, o, i, 2, 2)  # sprout1
		put(world, o, i, 4, 3)  # sprout2
	put(world, o, 1, 7, 4)  # isolated mature
	put(world, o, 4, 7, 4)  # pair
	put(world, o, 5, 7, 4)
	for dy: int in 3:  # 3x3 block
		for dx: int in 3:
			put(world, o, 8 + dx, 7 + dy, 4)
	put(world, o, 14, 7, 4)  # diagonal pair
	put(world, o, 15, 8, 4)
	for p: Vector2i in [Vector2i(18, 7), Vector2i(18, 8), Vector2i(19, 8)]:  # L shape
		put(world, o, p.x, p.y, 4)
	# scattered mixed field
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 8
	for n: int in 120:
		put(world, o, 22 + rng.randi_range(0, 8), rng.randi_range(0, 12), rng.randi_range(1, 4))
	for i: int in 40:
		await process_frame
	await RenderingServer.frame_post_draw
	var vp: Image = root.get_texture().get_image()
	vp.convert(Image.FORMAT_RGBA8)
	vp.save_png(ProjectSettings.globalize_path(OUT + "gpu_viewport.png"))
	print("GPU_INFO renderer=%s window=%s size=%s scale=%s screen=%d" % [RenderingServer.get_current_rendering_method(), root.position, root.size, root.content_scale_size, root.current_screen])
	# Native capture
	var native_path: String = ProjectSettings.globalize_path(OUT + "gpu_window_native.png")
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
	rec("6.native_size", "PrintWindow capture is 1280x720 (k=2) and internal frame 640x360", native.get_size() == Vector2i(1280, 720) and vp.get_size() == Vector2i(640, 360), "native=%s vp=%s waited=%d" % [native.get_size(), vp.get_size(), waited])
	var nd: PackedByteArray = native.get_data()
	var vd: PackedByteArray = vp.get_data()
	var bad_blocks: int = 0
	var mism: int = 0
	var w: int = native.get_width()
	for y: int in 360:
		for x: int in 640:
			var o0: int = ((y * k) * w + x * k) * 4
			var uniform: bool = true
			for dy: int in k:
				for dx: int in k:
					var oo: int = ((y * k + dy) * w + x * k + dx) * 4
					if nd[oo] != nd[o0] or nd[oo + 1] != nd[o0 + 1] or nd[oo + 2] != nd[o0 + 2]:
						uniform = false
			if not uniform:
				bad_blocks += 1
			var vo: int = (y * 640 + x) * 4
			if nd[o0] != vd[vo] or nd[o0 + 1] != vd[vo + 1] or nd[o0 + 2] != vd[vo + 2]:
				mism += 1
	rec("6.k2_uniform", "every 2x2 block of the 1280x720 window image is a single colour", bad_blocks == 0, "non-uniform blocks=%d of 230400" % bad_blocks)
	rec("6.native_equals_internal", "each block equals the internal frame pixel (no filtering)", mism == 0, "mismatching=%d" % mism)
	# Screen vs CPU block images: pattern area compare
	var view: RegionView = main.region_view
	var sx0: int = o.x * 4 - int(main.player.position.x) + 320
	var sy0: int = o.y * 4 - int(main.player.position.y) + 180
	var diffs: int = 0
	var compared: int = 0
	var sample_bad: String = ""
	for py: int in 22 * 4:
		for px: int in 34 * 4:
			var wx: int = o.x * 4 + px
			var wy: int = o.y * 4 + py
			var bi: Image = view.block_images[(wy / 256) * view.blocks_x + (wx / 256)]
			var cpu: Color = bi.get_pixel(wx % 256, wy % 256)
			var sx: int = sx0 + px
			var sy: int = sy0 + py
			if sx < 0 or sy < 40 or sx >= 640 or sy >= 330:
				continue
			var scr: Color = vp.get_pixel(sx, sy)
			compared += 1
			if absf(scr.r - cpu.r) > 0.004 or absf(scr.g - cpu.g) > 0.004 or absf(scr.b - cpu.b) > 0.004:
				diffs += 1
				if sample_bad == "":
					sample_bad = "world(%d,%d) screen(%d,%d) gpu=%s cpu=%s" % [wx, wy, sx, sy, scr, cpu]
	rec("6.screen_equals_state", "on-screen pixels of the pattern area equal the CPU block images (GPU upload and camera offset are exact; the pattern area is %d px)" % compared, diffs == 0 and compared > 8000, "compared=%d diffs=%d %s" % [compared, diffs, sample_bad])
	# Zoomed crops for my own eyes
	var crop: Image = native.get_region(Rect2i(sx0 * k - 8, sy0 * k - 8, 34 * 4 * k + 16, 22 * 4 * k + 16))
	crop.resize(crop.get_width() * 3, crop.get_height() * 3, Image.INTERPOLATE_NEAREST)
	crop.save_png(ProjectSettings.globalize_path(OUT + "gpu_pattern_native_x3.png"))
	var crop2: Image = vp.get_region(Rect2i(sx0 + 0, sy0 + 28, 84, 20))
	crop2.resize(crop2.get_width() * 16, crop2.get_height() * 16, Image.INTERPOLATE_NEAREST)
	crop2.save_png(ProjectSettings.globalize_path(OUT + "gpu_mature_row_x16.png"))
	var crop3: Image = vp.get_region(Rect2i(sx0, sy0, 66, 22))
	crop3.resize(crop3.get_width() * 16, crop3.get_height() * 16, Image.INTERPOLATE_NEAREST)
	crop3.save_png(ProjectSettings.globalize_path(OUT + "gpu_stage_rows_x16.png"))
	# Whole-frame outline hint: count distinct colours in the pattern area (no dark outline colour expected)
	var colours: Dictionary = {}
	var darkest: float = 1.0
	for py: int in range(0, 88):
		for px: int in range(0, 136):
			var sc: Color = vp.get_pixel(sx0 + px, sy0 + py)
			colours[sc.to_html(false)] = true
			darkest = minf(darkest, sc.get_luminance())
	rec("6.no_outline_colours", "pattern area uses only terrain/seed/sprout/mature/blend colours (no outline colour)", colours.size() <= 12 and darkest > 0.3, "distinct=%d darkest_luma=%.3f %s" % [colours.size(), darkest, colours.keys()])
	# Performance in a real window: 1000 scattered tile changes across all blocks
	var rng2: RandomNumberGenerator = RandomNumberGenerator.new()
	rng2.seed = 21
	var picked: Array[int] = []
	while picked.size() < 1000:
		var i: int = rng2.randi_range(0, 512 * 512 - 1)
		if world.target[i] == 1 and world.stage[i] == 0:
			picked.append(i)
	var frame_times: Array[float] = []
	var t_prev: float = Time.get_ticks_usec() / 1000.0
	for i: int in 5:
		await process_frame
		var t_now: float = Time.get_ticks_usec() / 1000.0
		frame_times.append(t_now - t_prev)
		t_prev = t_now
	var t0: float = Time.get_ticks_usec() / 1000.0
	for i: int in picked:
		world.set_stage(i, 2)
	var t1: float = Time.get_ticks_usec() / 1000.0
	view.flush()
	var t2: float = Time.get_ticks_usec() / 1000.0
	await process_frame
	await RenderingServer.frame_post_draw
	var t3: float = Time.get_ticks_usec() / 1000.0
	rec("7.perf_gpu_1000", "1000 scattered changes in the live scene: state=%.2f ms, repaint+texture update=%.2f ms (tiles=%d blocks=%d), until next frame drawn=%.2f ms; baseline frame interval %s ms" % [t1 - t0, t2 - t1, view.last_flush_tiles, view.last_flush_blocks, t3 - t2, frame_times], (t2 - t0) <= 16.0, "repaint+upload %.2f ms (16 ms budget)" % (t2 - t0))
	# Also the more typical case: 50 changes in one area
	var t4: float = Time.get_ticks_usec() / 1000.0
	for i: int in 50:
		world.set_stage(picked[i], 4)
	view.flush()
	var t5: float = Time.get_ticks_usec() / 1000.0
	rec("7.perf_gpu_50", "50 changes: set+repaint+upload", true, "%.3f ms tiles=%d blocks=%d" % [t5 - t4, view.last_flush_tiles, view.last_flush_blocks])
	var f: FileAccess = FileAccess.open(OUT + "checks_gpu.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(results, "  "))
	f.close()
	var fails: int = 0
	for r: Dictionary in results:
		if r["status"] != "PASS":
			fails += 1
	print("V_GPU_RESULT total=%d fails=%d" % [results.size(), fails])
	quit(fails)
