extends SceneTree
## P1-03 GPU render check (needs a real window, NOT headless). Engine-internal input injection and capture only.
## Run: Godot --path <project> --screen 1 --script res://tests/p1/p1_02_gpu.gd
## Scene: four seed batches planted on open wasteland at different game times (0, 70, 90 and 108 s of 110 s), so the
## picture holds mature plants with seed fruits, sprout 2, sprout 1 and plain seeds side by side. The input path
## and the whole flow are covered by the headless scene checks; here game time is advanced through the same
## clock / play code paths, in 0.25 s steps.
## Saves gpu_viewport_640x360.png, gpu_scene_crop_x8.png, gpu_window_native.png and prints k x k uniformity results.

const OUT: String = "res://evidence/p1/p1-03/"

var failures: int = 0
var main: Node
var player: FlowerPlayer

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
	player = main.player
	var play: PlayState = main.play
	var state: WorldState = main.grid
	var clock: SimClock = main.simulation.clock
	var block: Vector2i = find_wasteland_block(state, 40)
	check(block.x >= 0, "found an open wasteland block at %s" % block)
	var origin: Vector2 = (Vector2(block) + Vector2(0.5, 0.5)) * 4.0
	player.simulation_position = origin + Vector2(-40, 30)
	play.seeds = play.tuning.seed_max
	# Test-only override (process-local): 4x the default fruit rate so that the 50 s of mature time shows fruits.
	play.tuning.plant_fruit_rate_per_tile_second = 0.005
	var player_at: Vector2 = player.simulation_position
	var batches: Array[Dictionary] = [
		{"t": 0.0, "points": [Vector2(-8, -6), Vector2(-4, 2), Vector2(2, -4), Vector2(0, 6)]},
		{"t": 70.0, "points": [Vector2(26, -6), Vector2(30, 4)]},
		{"t": 90.0, "points": [Vector2(52, -4), Vector2(56, 6)]},
		{"t": 108.0, "points": [Vector2(78, -6), Vector2(82, 4)]},
	]
	var next_batch: int = 0
	var game_time: float = 0.0
	while game_time < 110.0 - 1.0e-6:
		while next_batch < batches.size() and game_time >= float(batches[next_batch]["t"]) - 1.0e-6:
			for offset: Vector2 in batches[next_batch]["points"]:
				play.land_seed(origin + offset)
			next_batch += 1
		clock.advance(0.25)
		play.advance(0.25, player_at)
		game_time += 0.25
	for i: int in 4:
		await physics_frame
	var counts: Array[int] = [0, 0, 0, 0, 0]
	for index: int in state.tile_count():
		counts[state.stage[index]] += 1
	var safe_mature: int = 0
	var plant_fruits: int = play.pickups.count_plant_owned()
	print("GPU_INFO game_time=%.2f clock=%.2f stage counts (empty,seed,sprout1,sprout2,mature)=%s plant_fruits=%d total_pickups=%d greened=%d" % [game_time, clock.elapsed, counts, plant_fruits, play.pickups.count(), state.greened_count])
	check(counts[1] >= 4 and counts[2] >= 4 and counts[3] >= 4, "the picture shows seeds, sprout 1 and sprout 2 tiles at once (%s)" % [counts])
	check(plant_fruits >= 1, "mature plants have dropped seed fruits that lie on the ground (%d)" % plant_fruits)
	for i: int in 3:
		await process_frame
	# Freeze the tree (no overlay) so the internal frame and the later window capture show the same picture.
	paused = true
	for i: int in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	print("GPU_INFO renderer=%s screens=%d window_screen=%d window_pos=%s window_size=%s content_scale=%s" % [RenderingServer.get_current_rendering_method(), DisplayServer.get_screen_count(), root.current_screen, root.position, root.size, root.content_scale_size])
	var viewport_image: Image = root.get_texture().get_image()
	viewport_image.save_png(ProjectSettings.globalize_path(OUT + "gpu_viewport_640x360.png"))
	check(viewport_image.get_size() == Vector2i(640, 360), "internal frame is 640x360")
	var focus: Vector2 = main.player.position
	var crop_rect: Rect2i = Rect2i(135, 125, 130, 45)
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
	print("P1_03_GPU_RESULT failures=%d" % failures)
	quit(failures)

func count_seed_tiles(state: WorldState) -> int:
	var total: int = 0
	for index: int in state.tile_count():
		if state.stage[index] == WorldState.STAGE_SEED:
			total += 1
	return total

func find_wasteland_block(state: WorldState, size: int) -> Vector2i:
	var wasteland: int = 0
	for def: TerrainDef in state.terrain_defs:
		if def.key == &"wasteland":
			wasteland = def.id
	for cx: int in range(40, 150, 6):
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
