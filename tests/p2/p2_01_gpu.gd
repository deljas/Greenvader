extends SceneTree
## P2-01 GPU render check (needs a real window, NOT headless). Engine-internal state and capture only; no OS input.
## Run: Godot --path <project> --screen 1 --script res://tests/p2/p2_01_gpu.gd -- --k2   (add --dry to skip the captures)
## One window, two stages:
##   1. a nest with a mature field around it and the boars that came out of it and have already bitten holes into the field
##   2. a boar close up at the edge of the bitten field (zoomed crop)
## Each stage saves the 640x360 viewport and the native window (PrintWindow) and checks that every k x k block of the window
## is one colour and equals the viewport pixel (pixel-perfect, no smoothing).

const OUT: String = "res://evidence/p2/p2-01/"
const TILE: int = 4

var failures: int = 0
var main: Node
var dry: bool = false
var report: Dictionary = {}

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
	print("%s %s" % ["PASS" if ok else "FAIL", message])

func wait_frames(count: int) -> void:
	for i: int in count:
		await process_frame

## Saves the viewport and the native window of the current frame and checks the k x k uniformity. Returns the viewport image.
func capture(label: String) -> Image:
	paused = true
	await wait_frames(3)
	await RenderingServer.frame_post_draw
	var viewport_image: Image = root.get_texture().get_image()
	viewport_image.save_png(ProjectSettings.globalize_path(OUT + "gpu_%s_viewport_640x360.png" % label))
	check(viewport_image.get_size() == Vector2i(640, 360), "%s: internal frame is 640x360" % label)
	var native_path: String = ProjectSettings.globalize_path(OUT + "gpu_%s_window_native.png" % label)
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
	print("GPU_INFO %s printwindow pid=%d frames_waited=%d code=%d" % [label, pid, waited, code])
	var native: Image = Image.load_from_file(native_path) if code == 0 else null
	if native == null or native.is_empty():
		print("NOT_RUN %s native window capture unavailable" % label)
	else:
		var k: int = root.size.x / 640
		viewport_image.convert(Image.FORMAT_RGBA8)
		native.convert(Image.FORMAT_RGBA8)
		if native.get_size() != Vector2i(640 * k, 360 * k):
			print("NOT_RUN %s window capture size %s != expected %dx%d" % [label, native.get_size(), 640 * k, 360 * k])
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
			check(distinct.size() > 15, "%s: window image is real content (%d distinct colours)" % [label, distinct.size()])
			check(non_uniform_blocks == 0, "%s: every %dx%d block of the window image is one colour (non-uniform blocks: %d)" % [label, k, k, non_uniform_blocks])
			check(mismatches == 0, "%s: each block equals the internal-frame pixel (mismatching blocks: %d of %d)" % [label, mismatches, 640 * 360])
			report[label + "_k"] = k
	paused = false
	return viewport_image

func run() -> void:
	dry = OS.get_cmdline_user_args().has("--dry")
	if OS.get_cmdline_user_args().has("--k2"):
		root.size = Vector2i(1280, 720)
		await process_frame
		await process_frame
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var world: WorldState = main.grid
	var enemies: EnemyField = main.enemies
	var player: FlowerPlayer = main.player
	# The game drivers stay off: the enemy simulation is stepped here, so the picture is reproducible.
	main.enemy_driver.process_mode = Node.PROCESS_MODE_DISABLED
	main.play_driver.process_mode = Node.PROCESS_MODE_DISABLED
	main.simulation.process_mode = Node.PROCESS_MODE_DISABLED
	player.set_physics_process(false)
	var nest: Nest = enemies.nests[0]
	check(nest.zone == 1 and enemies.nests.size() == 15, "the first nest (%s, zone %d) belongs to the unconquered zone north of the start" % [nest.tile, nest.zone])
	# Only this nest keeps spawning in this picture (the others would share the region-wide limit of 40 boars).
	for other: Nest in enemies.nests:
		if other != nest:
			enemies.destroy_nest(other)
	# A mature field around the nest (the nest's own tiles stay free), then 55 s of boars.
	var planted: int = 0
	for y: int in range(nest.tile.y - 12, nest.tile.y + 16):
		for x: int in range(nest.tile.x - 16, nest.tile.x + 20):
			var index: int = world.index_of(x, y)
			if world.occupant[index] == 0 and world.set_stage(index, WorldState.STAGE_MATURE):
				planted += 1
	var greened_before: int = world.greened_count
	for i: int in 60 * 55:
		enemies.advance(1.0 / 60.0)
	var nest_tiles_free: bool = true
	for y: int in range(nest.tile.y, nest.tile.y + 4):
		for x: int in range(nest.tile.x, nest.tile.x + 4):
			nest_tiles_free = nest_tiles_free and world.stage[world.index_of(x, y)] == WorldState.STAGE_EMPTY
	var mine: Array[Boar] = []
	for boar: Boar in enemies.boars:
		if boar.nest_id == nest.id:
			mine.append(boar)
	check(nest_tiles_free and mine.size() == 4 and enemies.total_gnawed > 20, "the nest is bare, its 4 boars came out and (with the other nests' boars) bit %d tiles of the %d planted (greened %d -> %d)" % [enemies.total_gnawed, planted, greened_before, world.greened_count])
	check(world.counters_consistent(), "counters match a recount")
	# Camera: the player stands south-west of the nest so nest, boars and bitten field are in the 640x360 view.
	var centre: Vector2 = nest.center_px(TILE)
	player.simulation_position = centre + Vector2(-60, 64)
	player.position = player.simulation_position.round()
	player.presentation_updated.emit(player.position)
	await wait_frames(6)
	report["nest_tile"] = [nest.tile.x, nest.tile.y]
	report["boars_total"] = enemies.boars.size()
	report["boars_of_nest"] = mine.size()
	report["tiles_gnawed"] = enemies.total_gnawed
	var near_ok: int = 0
	var cam_origin: Vector2 = main.camera.get_screen_center_position() - Vector2(320, 180)
	for boar: Boar in mine:
		near_ok += 1 if Rect2(cam_origin, Vector2(640, 360)).has_point(boar.pos) else 0
	print("GPU_INFO camera_center=%s player=%s simulation_position=%s boars=%s" % [main.camera.get_screen_center_position(), player.position, player.simulation_position, mine.map(func(b: Boar) -> Vector2: return b.pos)])
	check(near_ok >= 2, "%d of the 4 boars are inside the camera view" % near_ok)
	check(main.enemy_view.boar_sprites.size() == enemies.boars.size() and main.enemy_view.nest_sprites.has(nest.id), "the view shows the nest and one sprite per boar (%d)" % main.enemy_view.boar_sprites.size())
	var image: Image = await capture("nest") if not dry else null
	if not dry:
		# Crop of the nest area, zoomed x4 (nearest).
		var nest_screen: Vector2 = centre - cam_origin
		var rect: Rect2i = Rect2i(Vector2i(nest_screen) - Vector2i(80, 56), Vector2i(160, 112)).intersection(Rect2i(0, 0, 640, 360))
		var crop: Image = image.get_region(rect)
		crop.resize(crop.get_width() * 4, crop.get_height() * 4, Image.INTERPOLATE_NEAREST)
		crop.save_png(ProjectSettings.globalize_path(OUT + "gpu_nest_crop_x4.png"))
		if mine.size() > 0:
			var boar: Boar = mine[0]
			var boar_screen: Vector2 = boar.pos - cam_origin
			var brect: Rect2i = Rect2i(Vector2i(boar_screen) - Vector2i(32, 28), Vector2i(64, 40)).intersection(Rect2i(0, 0, 640, 360))
			var boar_crop: Image = image.get_region(brect)
			boar_crop.resize(boar_crop.get_width() * 8, boar_crop.get_height() * 8, Image.INTERPOLATE_NEAREST)
			boar_crop.save_png(ProjectSettings.globalize_path(OUT + "gpu_boar_crop_x8.png"))
	var file: FileAccess = FileAccess.open(ProjectSettings.globalize_path(OUT + "gpu_report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	print("GPU_INFO renderer=%s screens=%d window_screen=%d window_pos=%s window_size=%s" % [RenderingServer.get_current_rendering_method(), DisplayServer.get_screen_count(), root.current_screen, root.position, root.size])
	print("P2_01_GPU_RESULT failures=%d" % failures)
	quit(failures)
