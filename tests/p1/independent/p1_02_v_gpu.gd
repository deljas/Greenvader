extends SceneTree
## Independent GPU-window render check for P1-02 (real window, NOT headless; run with --screen 1).
## State is set from inside the engine (no OS input). Capture: PrintWindow (read-only, no focus change).
## Run: Godot --path <project> --screen 1 --script res://tests/p1/independent/p1_02_v_gpu.gd

const OUT: String = "res://evidence/p1/p1-02/independent/"
var results: Array[Dictionary] = []

func _initialize() -> void:
	run.call_deferred()

func rec(id: String, cond: String, ok: bool, observed: String) -> void:
	results.append({"id": id, "condition": cond, "status": "PASS" if ok else "FAIL", "observed": observed})
	print("%s [%s] %s :: %s" % ["PASS" if ok else "FAIL", id, cond, observed])

func run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var play: PlayState = main.play
	var player: FlowerPlayer = main.player
	# let the source drop all three fruits (game-time steps), away from the player
	for i: int in 110:
		play.advance(0.25, Vector2(0, 0))
	var src: Vector2 = play.sources[0].position
	player.simulation_position = src + Vector2(34, 26)
	play.seeds = 17
	play.water = 63.9
	for i: int in 4:
		await physics_frame
	var east: Vector2 = player.simulation_position
	for ang: int in [-30, -10, 12, 30]:
		main.fire(false, east + Vector2.RIGHT.rotated(deg_to_rad(ang)) * 56.0)
		await physics_frame
	main.fire(true, east + Vector2(30, 44))
	for i: int in 70:
		await physics_frame
	main.fire(false, east + Vector2.RIGHT.rotated(deg_to_rad(-40)) * 110.0)
	main.fire(true, east + Vector2.RIGHT.rotated(deg_to_rad(35)) * 110.0)
	for i: int in 12:
		await physics_frame
	paused = true
	for i: int in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var shots: int = main.projectile_view.shots.size()
	var fruits: int = play.pickups.count()
	var seeds_on_ground: int = 0
	for i: int in main.grid.tile_count():
		if main.grid.stage[i] == 1:
			seeds_on_ground += 1
	print("GPU_INFO renderer=%s window=%s size=%s scale=%s screen=%d shots=%d fruits=%d seed_tiles=%d seeds=%d water=%s player=%s src=%s" % [RenderingServer.get_current_rendering_method(), root.position, root.size, root.content_scale_size, root.current_screen, shots, fruits, seeds_on_ground, play.seeds, play.water, player.simulation_position, src])
	rec("gpu.state", "scene has shots in flight, fruits on the ground, scattered seed tiles", shots >= 2 and fruits >= 1 and seeds_on_ground >= 6, "shots=%d fruits=%d seed_tiles=%d" % [shots, fruits, seeds_on_ground])
	var vp: Image = root.get_texture().get_image()
	vp.convert(Image.FORMAT_RGBA8)
	vp.save_png(ProjectSettings.globalize_path(OUT + "gpu_viewport_640x360.png"))
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
	rec("gpu.size", "PrintWindow capture is 1280x720 (k=2), internal frame 640x360", native.get_size() == Vector2i(1280, 720) and vp.get_size() == Vector2i(640, 360), "native=%s vp=%s" % [native.get_size(), vp.get_size()])
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
	rec("gpu.k2_uniform", "every 2x2 block of the window image is one colour (no smoothing)", bad == 0, "non-uniform pixels=%d" % bad)
	rec("gpu.native_equals_internal", "each block equals the internal frame pixel", mism == 0, "mismatching=%d of 230400" % mism)
	# crops for my own eyes
	var cam: Vector2 = player.position
	var scr: Vector2i = Vector2i(320, 180) + Vector2i((src - cam).round())
	var c1: Image = vp.get_region(Rect2i(maxi(scr.x - 80, 0), maxi(scr.y - 70, 0), 200, 140))
	c1.resize(c1.get_width() * 6, c1.get_height() * 6, Image.INTERPOLATE_NEAREST)
	c1.save_png(ProjectSettings.globalize_path(OUT + "gpu_scene_crop_x6.png"))
	var c2: Image = vp.get_region(Rect2i(0, 326, 640, 34))
	c2.resize(c2.get_width() * 3, c2.get_height() * 3, Image.INTERPOLATE_NEAREST)
	c2.save_png(ProjectSettings.globalize_path(OUT + "gpu_hud_crop_x3.png"))
	var f: FileAccess = FileAccess.open(OUT + "checks_gpu.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(results, "  "))
	f.close()
	var fails: int = 0
	for r: Dictionary in results:
		if r["status"] != "PASS":
			fails += 1
	print("V_GPU_RESULT total=%d fails=%d" % [results.size(), fails])
	quit(1 if fails > 0 else 0)
