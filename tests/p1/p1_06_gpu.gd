extends SceneTree
## P1-06 GPU render check (needs a real window, NOT headless). Engine-internal input injection and capture only.
## Run: Godot --path <project> --screen 1 --script res://tests/p1/p1_06_gpu.gd -- --k2   (add --dry to skip the captures)
## One window, three stages (the player walks with injected D key events):
##   1. a ford: the player stands in the shallows between the water banks
##   2. the water's edge: the player has walked into the bank and stopped (water gauge refills there)
##   3. seed fruits: plant fruits (produced by the game logic) on mature green next to a seed-source fruit and a healing fruit
## then a frame-time measurement in a busy scene (vsync off). Each stage saves the 640x360 viewport and the native window
## (PrintWindow) and checks that every k x k block of the window is one colour and equals the viewport pixel.

const OUT: String = "res://evidence/p1/p1-06/"
const TILE: int = 4

var failures: int = 0
var main: Node
var player: FlowerPlayer
var dry: bool = false
var report: Dictionary = {}

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
	print("%s %s" % ["PASS" if ok else "FAIL", message])

func send_key(code: Key, pressed: bool) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)

func wait_frames(count: int) -> void:
	for i: int in count:
		await process_frame

func wait_physics(count: int) -> void:
	for i: int in count:
		await physics_frame

## Holds a key for `ticks` physics frames, then releases it (injected events only).
func hold(code: Key, ticks: int) -> void:
	send_key(code, true)
	await process_frame
	await wait_physics(ticks)
	send_key(code, false)
	await process_frame

func overlaps_blocked(world: WorldState, position: Vector2) -> bool:
	var half: Vector2 = player.walk_half
	for ty: int in range(floori((position.y - half.y) / TILE) - 1, ceili((position.y + half.y) / TILE) + 2):
		for tx: int in range(floori((position.x - half.x) / TILE) - 1, ceili((position.x + half.x) / TILE) + 2):
			var ox: float = minf(position.x + half.x, (tx + 1) * TILE) - maxf(position.x - half.x, tx * TILE)
			var oy: float = minf(position.y + half.y, (ty + 1) * TILE) - maxf(position.y - half.y, ty * TILE)
			if ox > 1.0e-3 and oy > 1.0e-3 and not world.is_walkable(tx, ty):
				return true
	return false

func terrain_key(world: WorldState, x: int, y: int) -> StringName:
	return world.terrain_defs[world.terrain[world.index_of(x, y)]].key

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

func find_wasteland_block(state: WorldState, size: int) -> Vector2i:
	for cx: int in range(120, 150, 6):
		for cy: int in range(40, 470, 6):
			var ok: bool = true
			for y: int in range(cy - size / 2, cy + size / 2):
				for x: int in range(cx - size / 2, cx + size / 2):
					if terrain_key(state, x, y) != &"wasteland" or state.stage[state.index_of(x, y)] != 0:
						ok = false
						break
				if not ok:
					break
			if ok:
				return Vector2i(cx, cy)
	return Vector2i(-1, -1)

func run() -> void:
	dry = OS.get_cmdline_user_args().has("--dry")
	if OS.get_cmdline_user_args().has("--k2"):
		root.size = Vector2i(1280, 720)
		await process_frame
		await process_frame
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	player = main.player
	var world: WorldState = main.grid
	var play: PlayState = main.play
	var fords: Array[Rect2i] = []
	# --- stage 1: ford -------------------------------------------------------------------------------------
	# The second band of the region (top row 200): find it from the tiles (shallows run on that row).
	var ford_row: int = 202
	var ford_first: int = -1
	var ford_last: int = -1
	for x: int in range(200, 320):
		if terrain_key(world, x, ford_row) == &"shallows":
			if ford_first < 0:
				ford_first = x
			ford_last = x
	check(ford_first > 0 and ford_last - ford_first >= 10, "found the ford on row %d: tiles %d..%d" % [ford_row, ford_first, ford_last])
	# Start 10 tiles west of the ford's west end, on the middle line of the band, and walk east with the injected D key.
	player.simulation_position = Vector2((ford_first - 10) * TILE, 203 * TILE)
	await wait_frames(3)
	check(not overlaps_blocked(world, player.simulation_position), "the player starts on dry ground west of the ford")
	var ticks_to_ford_middle: int = int(ceil(float(10 + (ford_last - ford_first) / 2) * TILE / (96.0 / float(Engine.physics_ticks_per_second))))
	await hold(KEY_D, ticks_to_ford_middle)
	var tile_x: int = floori(player.simulation_position.x / TILE)
	check(tile_x > ford_first + 4 and tile_x < ford_last - 4 and terrain_key(world, tile_x, 203) == &"shallows" and not overlaps_blocked(world, player.simulation_position), "the injected walk put the player in the middle of the ford (tile x %d, terrain %s)" % [tile_x, terrain_key(world, tile_x, 203)])
	report["ford_player_tile"] = [tile_x, floori(player.simulation_position.y / TILE)]
	var ford_image: Image = await capture("ford") if not dry else null
	# --- stage 2: stopped at the water's edge ------------------------------------------------------------------
	var row: int = 100
	var wall_x: int = -1
	for x: int in range(200, world.width):
		if not world.is_walkable(x, row):
			wall_x = x
			break
	player.simulation_position = Vector2((wall_x - 16) * TILE, row * TILE + 2)
	play.water = 20.0
	await wait_frames(3)
	var ticks_needed: int = int(ceil(16.0 * TILE / (96.0 / float(Engine.physics_ticks_per_second)))) + 40
	await hold(KEY_D, ticks_needed)
	var stop_x: float = float(wall_x * TILE) - player.walk_half.x
	check(absf(player.simulation_position.x - stop_x) < 1.0e-3 and not overlaps_blocked(world, player.simulation_position), "the injected walk stopped at the water's edge (x=%.3f, edge stop %.3f)" % [player.simulation_position.x, stop_x])
	await wait_physics(60)
	check(play.refilling and play.water > 20.0, "at the water's edge the gauge refills (water %.1f, refilling %s)" % [play.water, play.refilling])
	report["edge_player_x"] = player.simulation_position.x
	var edge_image: Image = await capture("edge") if not dry else null
	# --- stage 3: seed fruits on mature green -----------------------------------------------------------------
	var block: Vector2i = find_wasteland_block(world, 44)
	check(block.x >= 0, "found an open wasteland block at %s" % block)
	world.debug_fill_stage(Rect2i(block.x - 16, block.y - 9, 32, 18), WorldState.STAGE_MATURE)
	player.simulation_position = (Vector2(block) + Vector2(0.5, 4.5)) * TILE
	main.play_driver.process_mode = Node.PROCESS_MODE_DISABLED
	main.simulation.process_mode = Node.PROCESS_MODE_DISABLED
	await wait_frames(4)
	# Real production: the game logic drops the plant fruits around the player; run its game time until several lie around.
	var guard: int = 0
	while play.pickups.count_plant_owned() < 6 and guard < 2000:
		play.advance(0.25, player.simulation_position)
		guard += 1
	var plant_fruits: int = play.pickups.count_plant_owned()
	check(plant_fruits >= 6, "the game logic produced %d plant fruits on the mature field (%d s of game time)" % [plant_fruits, guard / 4])
	# Keep the fruits away from the player (no collection), and add a source-style fruit and a healing fruit next to them.
	var centre: Vector2 = (Vector2(block) + Vector2(0.5, -3.5)) * TILE
	for item: Dictionary in play.pickups.items:
		if GroundPickups.is_plant_owner(int(item["owner"])):
			var offset: Vector2 = Vector2(float(item["x"]), float(item["y"])) - player.simulation_position
			if offset.length() < 28.0:
				item["x"] = float(item["x"]) + (28.0 - offset.length() + 2.0) * (offset.normalized().x if offset.length() > 0.1 else 1.0)
	play.pickups.spawn(GroundPickups.KIND_SEED_FRUIT, centre + Vector2(-14, 0), 1)
	play.pickups.spawn(GroundPickups.KIND_HEAL_FRUIT, centre + Vector2(14, 0), GroundPickups.HEAL_OWNER_BASE + 99, 600.0)
	play.pickups.spawn(GroundPickups.KIND_SEED_FRUIT, centre + Vector2(0, 2), GroundPickups.PLANT_OWNER_BASE + world.index_of(block.x, block.y - 3), 600.0)
	for item: Dictionary in play.pickups.items:
		item["age"] = 0.0
	await wait_frames(4)
	report["fruits_on_ground"] = play.pickups.count()
	check(play.pickups.count_kind(GroundPickups.KIND_HEAL_FRUIT) == 1 and play.pickups.count_plant_owned() >= 6 and play.pickups.count() >= 8, "plant fruits, a source fruit and a healing fruit lie on the field (%d pickups)" % play.pickups.count())
	var fruit_image: Image = await capture("fruit") if not dry else null
	if not dry:
		# Crop around the three kinds and zoom x8 (nearest).
		var cam: Vector2 = player.position
		var origin: Vector2 = Vector2(320, 180) - cam
		var crop_min: Vector2 = centre + origin - Vector2(40, 22)
		var crop_rect: Rect2i = Rect2i(Vector2i(crop_min), Vector2i(80, 44)).intersection(Rect2i(0, 0, 640, 360))
		var crop: Image = fruit_image.get_region(crop_rect)
		crop.resize(crop.get_width() * 8, crop.get_height() * 8, Image.INTERPOLATE_NEAREST)
		crop.save_png(ProjectSettings.globalize_path(OUT + "gpu_fruit_crop_x8.png"))
		var ford_crop: Image = ford_image.get_region(Rect2i(Vector2i(160, 100), Vector2i(320, 160)))
		ford_crop.resize(ford_crop.get_width() * 3, ford_crop.get_height() * 3, Image.INTERPOLATE_NEAREST)
		ford_crop.save_png(ProjectSettings.globalize_path(OUT + "gpu_ford_crop_x3.png"))
		var edge_crop: Image = edge_image.get_region(Rect2i(Vector2i(160, 100), Vector2i(320, 160)))
		edge_crop.resize(edge_crop.get_width() * 3, edge_crop.get_height() * 3, Image.INTERPOLATE_NEAREST)
		edge_crop.save_png(ProjectSettings.globalize_path(OUT + "gpu_edge_crop_x3.png"))
	# --- frame time in a busy scene -----------------------------------------------------------------------------------
	main.play_driver.process_mode = Node.PROCESS_MODE_INHERIT
	main.simulation.process_mode = Node.PROCESS_MODE_INHERIT
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	await wait_frames(10)
	var busy_origin: Vector2i = Vector2i(60, 250)
	world.debug_fill_stage(Rect2i(busy_origin.x, busy_origin.y, 200, 120), WorldState.STAGE_MATURE)
	for y: int in range(40, 200):
		for x: int in range(20, 220):
			var index: int = world.index_of(x, y)
			if world.set_stage(index, WorldState.STAGE_SEED):
				world.set_moisture(index, 100)
	player.simulation_position = (Vector2(busy_origin) + Vector2(100, 60)) * TILE
	await wait_frames(5)
	var frame_ms: PackedFloat64Array = PackedFloat64Array()
	var last: int = Time.get_ticks_usec()
	for i: int in 600:
		await process_frame
		var now: int = Time.get_ticks_usec()
		frame_ms.append((now - last) / 1000.0)
		last = now
	var sorted_frames: PackedFloat64Array = frame_ms.duplicate()
	sorted_frames.sort()
	var over: int = 0
	var mean: float = 0.0
	for f: float in frame_ms:
		over += 1 if f >= 16.0 else 0
		mean += f
	mean /= frame_ms.size()
	var p99: float = sorted_frames[int(float(sorted_frames.size() - 1) * 0.99)]
	report["busy_frame_ms"] = {"mean": snappedf(mean, 0.01), "p99": snappedf(p99, 0.01), "max": snappedf(sorted_frames[-1], 0.01), "frames_ge_16ms": over, "frames": frame_ms.size(), "active_tiles": world.active_tiles.size(), "renderer": RenderingServer.get_current_rendering_method()}
	print("GPU_INFO busy scene (vsync off, %d frames, %d active tiles): frame mean %.2f ms, p99 %.2f ms, max %.2f ms, frames >= 16 ms: %d" % [frame_ms.size(), world.active_tiles.size(), mean, p99, sorted_frames[-1], over])
	print("GPU_INFO renderer=%s screens=%d window_screen=%d window_pos=%s window_size=%s" % [RenderingServer.get_current_rendering_method(), DisplayServer.get_screen_count(), root.current_screen, root.position, root.size])
	var file: FileAccess = FileAccess.open(ProjectSettings.globalize_path(OUT + "gpu_report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	print("P1_06_GPU_RESULT failures=%d" % failures)
	quit(failures)
