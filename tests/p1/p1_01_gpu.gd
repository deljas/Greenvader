extends SceneTree
## P1-01 GPU render check (needs a real window, NOT headless). Engine-internal capture only; no OS input.
## Run: Godot --path <project> --screen 1 --script res://tests/p1/p1_01_gpu.gd
## Saves: gpu_viewport_640x360.png (internal frame), gpu_layout_crop_x8.png (crop of the debug layout, 8x nearest),
## gpu_window_native.png (screen pixels of the window rect, when the OS allows it) and prints k x k uniformity results.

const OUT: String = "res://evidence/p1/p1-01/"

var failures: int = 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
	print("%s %s" % ["PASS" if ok else "FAIL", message])

func run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	var origin: Vector2i = main.region_def.start_tile + Vector2i(-8, -28)
	DebugLayout.apply(main.grid, origin)
	main.player.simulation_position = Vector2(origin * 4) + Vector2(24, -8)
	for i: int in 30:
		await process_frame
	await RenderingServer.frame_post_draw
	print("GPU_INFO renderer=%s screens=%d window_screen=%d window_pos=%s window_size=%s content_scale=%s" % [RenderingServer.get_current_rendering_method(), DisplayServer.get_screen_count(), root.current_screen, root.position, root.size, root.content_scale_size])
	var viewport_image: Image = root.get_texture().get_image()
	print("GPU_INFO viewport texture size=%s" % viewport_image.get_size())
	viewport_image.save_png(ProjectSettings.globalize_path(OUT + "gpu_viewport_640x360.png"))
	check(viewport_image.get_size() == Vector2i(640, 360), "internal frame is 640x360")
	# Debug layout crop at 8x for inspection. The camera follows the player at the screen centre.
	var centre: Vector2i = Vector2i(320, 180)
	var player_px: Vector2i = Vector2i(main.player.position)
	var layout_px: Vector2i = origin * 4 - player_px + centre
	var crop_rect: Rect2i = Rect2i(layout_px - Vector2i(8, 8), Vector2i(104, 80)).intersection(Rect2i(0, 0, 640, 360))
	var crop: Image = viewport_image.get_region(crop_rect)
	crop.resize(crop.get_width() * 8, crop.get_height() * 8, Image.INTERPOLATE_NEAREST)
	crop.save_png(ProjectSettings.globalize_path(OUT + "gpu_layout_crop_x8.png"))
	print("GPU_INFO layout origin on screen=%s crop=%s" % [layout_px, crop_rect])
	# k x k uniformity of the window image.
	var window_size: Vector2i = root.size
	# Window pixels via Win32 PrintWindow (client area only; read-only, no input, no focus change).
	# DisplayServer.screen_get_image_rect returned an all-black image on this machine, so it is not used.
	var native_path: String = ProjectSettings.globalize_path(OUT + "gpu_window_native.png")
	var script_path: String = ProjectSettings.globalize_path("res://tests/independent/p0_verify_printwindow.ps1")
	var hwnd: int = DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE, 0)
	# Non-blocking: PrintWindow needs this window's message loop to keep running.
	var pid: int = OS.create_process("powershell", ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", script_path, "-Hwnd", str(hwnd), "-Out", native_path])
	var waited: int = 0
	while pid > 0 and OS.is_process_running(pid) and waited < 1200:
		await process_frame
		waited += 1
	var code: int = 0 if pid > 0 and not OS.is_process_running(pid) else -1
	if pid > 0 and OS.is_process_running(pid):
		OS.kill(pid)
	print("GPU_INFO printwindow pid=%d frames_waited=%d code=%d" % [pid, waited, code])
	var native: Image = Image.load_from_file(native_path) if code == 0 else null
	if native == null or native.is_empty():
		print("NOT_RUN native window capture unavailable")
	else:
		var k: int = window_size.x / 640
		print("GPU_INFO native capture size=%s k=%d" % [native.get_size(), k])
		viewport_image.convert(Image.FORMAT_RGBA8)
		native.convert(Image.FORMAT_RGBA8)
		if native.get_size() != Vector2i(640 * k, 360 * k):
			print("NOT_RUN window capture size %s != expected %dx%d" % [native.get_size(), 640 * k, 360 * k])
		else:
			var mismatches: int = 0
			var non_uniform_blocks: int = 0
			var distinct: Dictionary = {}
			for y: int in 360:
				for x: int in 640:
					var first: Color = native.get_pixel(x * k, y * k)
					distinct[first] = true
					var uniform: bool = true
					for dy: int in k:
						for dx: int in k:
							if native.get_pixel(x * k + dx, y * k + dy) != first:
								uniform = false
					if not uniform:
						non_uniform_blocks += 1
					if first != viewport_image.get_pixel(x, y):
						mismatches += 1
			check(distinct.size() > 50, "window image is real content, not blank (%d distinct colours)" % distinct.size())
			check(non_uniform_blocks == 0, "every %dx%d block of the %dx%d window image is one colour (non-uniform blocks: %d)" % [k, k, window_size.x, window_size.y, non_uniform_blocks])
			check(mismatches == 0, "each block equals the internal-frame pixel (mismatching blocks: %d of %d)" % [mismatches, 640 * 360])
	print("P1_01_GPU_RESULT failures=%d" % failures)
	quit(failures)
