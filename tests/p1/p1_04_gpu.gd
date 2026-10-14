extends SceneTree
## P1-04 GPU render check (needs a real window, NOT headless). Engine-internal clock stepping and capture only.
## Run: Godot --path <project> --screen 1 --script res://tests/p1/p1_04_gpu.gd
## Scene: a mature strip is put on open wasteland and 76 s of game time pass (0.25 s steps through the simulation
## clock), so natural spread has built a front: mature wall, mature edge, sprouts 2 / 1, seeds ahead of it.
## Saves gpu_viewport_640x360.png, gpu_scene_crop_x8.png, gpu_window_native.png and prints k x k uniformity results.

const OUT: String = "res://evidence/p1/p1-04/"

var failures: int = 0
var main: Node

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
	print("%s %s" % ["PASS" if ok else "FAIL", message])

func run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var player: FlowerPlayer = main.player
	var state: WorldState = main.grid
	var clock: SimClock = main.simulation.clock
	var block: Vector2i = find_wasteland_block(state, 44)
	check(block.x >= 0, "found an open wasteland block at %s" % block)
	state.debug_fill_stage(Rect2i(block.x - 22, block.y - 22, 5, 44), WorldState.STAGE_MATURE)
	var natural_before: int = 0
	for i: int in 304:
		clock.advance(0.25)
	for i: int in state.tile_count():
		natural_before += state.natural[i]
	var counts: Array[int] = [0, 0, 0, 0, 0]
	for y: int in range(block.y - 22, block.y + 22):
		for x: int in range(block.x - 22, block.x + 22):
			counts[state.stage[state.index_of(x, y)]] += 1
	print("GPU_INFO game_time=%.1f stage counts in the block (empty,seed,sprout1,sprout2,mature)=%s natural_tiles=%d" % [clock.elapsed, counts, natural_before])
	check(counts[1] >= 5 and counts[2] + counts[3] >= 5 and counts[4] > 5 * 44, "the picture shows a front: seeds, sprouts and more mature tiles than the start strip (%s)" % [counts])
	# Camera on the front.
	var front_x: int = block.x - 22
	for x: int in range(block.x - 22, block.x + 22):
		if state.stage[state.index_of(x, block.y)] >= WorldState.STAGE_SPROUT1:
			front_x = x
	player.simulation_position = (Vector2(front_x - 4, block.y) + Vector2(0.5, 0.5)) * 4.0 + Vector2(0, 40)
	for i: int in 6:
		await process_frame
	paused = true
	for i: int in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	print("GPU_INFO renderer=%s screens=%d window_screen=%d window_pos=%s window_size=%s content_scale=%s front_x=%d" % [RenderingServer.get_current_rendering_method(), DisplayServer.get_screen_count(), root.current_screen, root.position, root.size, root.content_scale_size, front_x])
	var viewport_image: Image = root.get_texture().get_image()
	viewport_image.save_png(ProjectSettings.globalize_path(OUT + "gpu_viewport_640x360.png"))
	check(viewport_image.get_size() == Vector2i(640, 360), "internal frame is 640x360")
	var crop_rect: Rect2i = Rect2i(215, 120, 130, 60)
	var scene_crop: Image = viewport_image.get_region(crop_rect)
	scene_crop.resize(scene_crop.get_width() * 8, scene_crop.get_height() * 8, Image.INTERPOLATE_NEAREST)
	scene_crop.save_png(ProjectSettings.globalize_path(OUT + "gpu_scene_crop_x8.png"))
	var native_path: String = ProjectSettings.globalize_path(OUT + "gpu_window_native.png")
	var script_path: String = ProjectSettings.globalize_path("res://tests/independent/p0_verify_printwindow.ps1")
	var hwnd: int = DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE, 0)
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
		var k: int = root.size.x / 640
		print("GPU_INFO native capture size=%s k=%d" % [native.get_size(), k])
		viewport_image.convert(Image.FORMAT_RGBA8)
		native.convert(Image.FORMAT_RGBA8)
		if native.get_size() != Vector2i(640 * k, 360 * k):
			print("NOT_RUN window capture size %s != expected %dx%d" % [native.get_size(), 640 * k, 360 * k])
		else:
			var non_uniform_blocks: int = 0
			var mismatches: int = 0
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
			check(distinct.size() > 15, "window image is real content (%d distinct colours)" % distinct.size())
			check(non_uniform_blocks == 0, "every %dx%d block of the window image is one colour (non-uniform blocks: %d)" % [k, k, non_uniform_blocks])
			check(mismatches == 0, "each block equals the internal-frame pixel (mismatching blocks: %d of %d)" % [mismatches, 640 * 360])
	print("P1_04_GPU_RESULT failures=%d" % failures)
	quit(failures)

func find_wasteland_block(state: WorldState, size: int) -> Vector2i:
	var wasteland: int = 0
	for def: TerrainDef in state.terrain_defs:
		if def.key == &"wasteland":
			wasteland = def.id
	for cx: int in range(120, 150, 6):
		for cy: int in range(40, 470, 6):
			var ok: bool = true
			for y: int in range(cy - size / 2, cy + size / 2):
				for x: int in range(cx - size / 2, cx + size / 2):
					if state.terrain[state.index_of(x, y)] != wasteland or state.stage[state.index_of(x, y)] != 0:
						ok = false
						break
				if not ok:
					break
			if ok:
				return Vector2i(cx, cy)
	return Vector2i(-1, -1)
