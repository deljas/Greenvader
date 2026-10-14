extends SceneTree
## P1-05 GPU render check (needs a real window, NOT headless). Engine-internal input injection and capture only.
## Run: Godot --path <project> --screen 1 --script res://tests/p1/p1_05_gpu.gd
## Scene: a mature field with a young and a mature carrot, a young and a mature kiwi (mature kiwi with two healing fruits),
## HP 6/10, the kiwi selected in the HUD. Plants are placed through injected Tab / mouse events; game time is stepped
## through the play state and the simulation clock.
## Saves gpu_viewport_640x360.png, gpu_plants_crop_x8.png, gpu_hud_crop_x3.png, gpu_window_native.png and prints the k x k
## uniformity results of the native window image.

const OUT: String = "res://evidence/p1/p1-05/"
const TILE: int = 4

var failures: int = 0
var main: Node
var player: FlowerPlayer
var mouse_screen: Vector2 = Vector2(320, 180)
var dry: bool = false

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

## Injected mouse events are in window pixels; the 640x360 content is scaled by k (window width / 640).
func window_scale() -> float:
	return float(root.size.x) / 640.0

func aim_at(world_point: Vector2) -> void:
	var k: float = window_scale()
	var guess: Vector2 = (world_point - player.position + Vector2(320, 180)) * k
	for attempt: int in 4:
		var motion: InputEventMouseMotion = InputEventMouseMotion.new()
		motion.position = guess
		motion.global_position = guess
		mouse_screen = guess
		Input.parse_input_event(motion)
		await process_frame
		await process_frame
		var achieved: Vector2 = player.get_global_mouse_position()
		if achieved.distance_to(world_point) < 0.6:
			break
		guess += (world_point - achieved) * k

func click() -> void:
	for pressed: bool in [true, false]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = mouse_screen
		event.global_position = mouse_screen
		Input.parse_input_event(event)
		await process_frame
		await process_frame

func wait_frames(count: int) -> void:
	for i: int in count:
		await process_frame

## Aims at a tile, clicks and waits until the shot has landed (not a fixed frame count: frame rates differ).
## Prints what happened. If the injected click did not produce a plant, the plant is placed through the same landing
## entry (PlayState.land_plant) so the picture can still be taken, and the failure is counted.
func shoot(tile: Vector2i) -> void:
	var play: PlayState = main.play
	var target: Vector2 = (Vector2(tile) + Vector2(0.5, 0.5)) * TILE
	var plants_before: int = play.cultivation.plants.size()
	var seeds_before: int = play.seeds
	await aim_at(target)
	var achieved: Vector2 = player.get_global_mouse_position()
	var shots_before: int = main.projectile_view.shots.size()
	await click()
	var waited: int = 0
	while waited < 600 and (main.projectile_view.shots.size() > 0 or waited < 3):
		await process_frame
		waited += 1
	await wait_frames(3)
	print("GPU_INFO shoot tile=%s aim_error=%.2f shots_before=%d shots_after=%d waited=%d plants %d->%d seeds %d->%d landings=%d failures=%d reserved=%d selected=%d" % [tile, achieved.distance_to(target), shots_before, main.projectile_view.shots.size(), waited, plants_before, play.cultivation.plants.size(), seeds_before, play.seeds, play.plant_landings, play.plant_failures, play.reserved_seeds, play.selected_index])
	if play.cultivation.plants.size() == plants_before:
		failures += 1
		print("FAIL the injected click at %s did not plant; placing through land_plant so the picture can still be taken" % tile)
		play.land_plant(play.selected_def().key, target) if play.reserved_seeds > 0 else play.cultivation.try_place(play.selected_def().key, target)

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
	var state: WorldState = main.grid
	var play: PlayState = main.play
	var block: Vector2i = find_wasteland_block(state, 44)
	check(block.x >= 0, "found an open wasteland block at %s" % block)
	state.debug_fill_stage(Rect2i(block.x - 14, block.y - 8, 28, 16), WorldState.STAGE_MATURE)
	player.simulation_position = (Vector2(block.x + 1, block.y + 5) + Vector2(0.5, 0.5)) * TILE
	await wait_frames(4)
	# Tab selects the carrot (injected), two shots; Tab again selects the kiwi, two shots.
	var plan: Array = [[1, Vector2i(block.x - 8, block.y - 4)], [2, Vector2i(block.x - 2, block.y - 4)]]
	for entry: Array in plan:
		while play.selected_index != int(entry[0]):
			send_key(KEY_TAB, true)
			await process_frame
			send_key(KEY_TAB, false)
			await process_frame
			await process_frame
		await shoot(entry[1])
	check(play.cultivation.plants.size() == 2, "first carrot and kiwi placed through injected input (%d plants)" % play.cultivation.plants.size())
	# Grow them up and let the kiwi drop its two fruits (game time through the play state and the simulation clock).
	for i: int in 328:
		play.advance(0.25, player.simulation_position)
	for i: int in 48:
		main.simulation.clock.advance(0.25)
	var mature_count: int = 0
	for plant: CultivatedPlant in play.cultivation.plants:
		mature_count += 1 if plant.mature else 0
	var fruits: int = play.pickups.count_kind(GroundPickups.KIND_HEAL_FRUIT)
	check(mature_count == 2 and fruits == 2, "after 82 s both are mature and the kiwi holds %d healing fruits" % fruits)
	# Young pair: planted now.
	var plan2: Array = [[1, Vector2i(block.x + 4, block.y - 4)], [2, Vector2i(block.x + 10, block.y - 4)]]
	for entry: Array in plan2:
		while play.selected_index != int(entry[0]):
			send_key(KEY_TAB, true)
			await process_frame
			send_key(KEY_TAB, false)
			await process_frame
			await process_frame
		await shoot(entry[1])
	check(play.cultivation.plants.size() == 4, "second carrot and kiwi placed (young), %d plants" % play.cultivation.plants.size())
	play.damage_player(4)
	await wait_frames(6)
	check(play.hp == 6 and play.pickups.count_kind(GroundPickups.KIND_HEAL_FRUIT) == 2, "HP 6/10 and the two healing fruits are still on the ground (player stays away)")
	check(main.hud.plant_label.text == "植物 通常 にんじん [キウイ:3]" and main.hud.hp_label.text == "HP 6/10", "HUD shows '%s' and '%s'" % [main.hud.plant_label.text, main.hud.hp_label.text])
	var footer: Control = main.hud.get_parent()
	check(main.hud.size.x <= footer.size.x + 0.5 and footer.size.x <= 624.5, "the HUD row fits the footer: HUD %s, footer %s" % [main.hud.size, footer.size])
	if dry:
		print("P1_05_GPU_DRY_RESULT failures=%d window=%s" % [failures, root.size])
		quit(failures)
		return
	paused = true
	for i: int in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	print("GPU_INFO renderer=%s screens=%d window_screen=%d window_pos=%s window_size=%s content_scale=%s" % [RenderingServer.get_current_rendering_method(), DisplayServer.get_screen_count(), root.current_screen, root.position, root.size, root.content_scale_size])
	var viewport_image: Image = root.get_texture().get_image()
	viewport_image.save_png(ProjectSettings.globalize_path(OUT + "gpu_viewport_640x360.png"))
	check(viewport_image.get_size() == Vector2i(640, 360), "internal frame is 640x360")
	# Crop around the four plants: tile coordinates -> viewport pixels (camera is centred on the player).
	var cam: Vector2 = player.position
	var origin: Vector2 = Vector2(320, 180) - cam
	var crop_min: Vector2 = Vector2(block.x - 10, block.y - 8) * TILE + origin
	var crop_rect: Rect2i = Rect2i(Vector2i(crop_min), Vector2i(26 * TILE, 8 * TILE)).intersection(Rect2i(0, 0, 640, 360))
	var plants_crop: Image = viewport_image.get_region(crop_rect)
	plants_crop.resize(plants_crop.get_width() * 8, plants_crop.get_height() * 8, Image.INTERPOLATE_NEAREST)
	plants_crop.save_png(ProjectSettings.globalize_path(OUT + "gpu_plants_crop_x8.png"))
	var hud_crop: Image = viewport_image.get_region(Rect2i(0, 328, 640, 32))
	hud_crop.resize(hud_crop.get_width() * 3, hud_crop.get_height() * 3, Image.INTERPOLATE_NEAREST)
	hud_crop.save_png(ProjectSettings.globalize_path(OUT + "gpu_hud_crop_x3.png"))
	print("GPU_INFO crop_rect=%s player=%s" % [crop_rect, player.position])
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
	print("P1_05_GPU_RESULT failures=%d" % failures)
	quit(failures)
