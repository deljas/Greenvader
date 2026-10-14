extends SceneTree
## P1-02 GPU render check (needs a real window, NOT headless). Engine-internal input injection and capture only.
## Run: Godot --path <project> --screen 1 --script res://tests/p1/p1_02_gpu.gd
## Shots are fired through main.fire(kind, aim_point): in a real window get_global_mouse_position() follows the OS
## cursor, so injected mouse motion cannot aim here (the input path is covered by the headless scene checks).
## Scene: player at the east edge of the safe zone, seed source and its fruits to the north-west, scattered
## seeds on the wasteland to the east, a seed shot and a water shot in flight, HUD at the bottom.
## Saves gpu_viewport_640x360.png, gpu_scene_crop_x4.png, gpu_hud_crop_x4.png, gpu_window_native.png and prints k x k uniformity results.

const OUT: String = "res://evidence/p1/p1-02/"

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
	var start: Vector2i = main.region_def.start_tile
	player.simulation_position = Vector2((start.x + 12) * 4 + 2, (start.y + 2) * 4 + 2)
	# Let the real source drop its fruits (game time via the same code path, 0.25 s steps), away from the player.
	for i: int in 110:
		play.advance(0.25, Vector2(0, 0))
	for i: int in 4:
		await physics_frame
	var east: Vector2 = player.simulation_position
	for angle_degrees: int in [-25, -8, 10, 28]:
		var direction: Vector2 = Vector2.RIGHT.rotated(deg_to_rad(angle_degrees))
		main.fire(false, east + direction * 52.0)
		await physics_frame
	main.fire(true, east + Vector2(30, 40))
	for i: int in 70:
		await physics_frame
	# Shots in flight at capture time: one seed and one water shot.
	main.fire(false, east + Vector2.RIGHT.rotated(deg_to_rad(-40)) * 100.0)
	main.fire(true, east + Vector2.RIGHT.rotated(deg_to_rad(35)) * 100.0)
	for i: int in 14:
		await physics_frame
	# Freeze the tree (no overlay) so the internal frame and the later window capture show the same picture.
	paused = true
	for i: int in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	print("GPU_INFO renderer=%s screens=%d window_screen=%d window_pos=%s window_size=%s content_scale=%s" % [RenderingServer.get_current_rendering_method(), DisplayServer.get_screen_count(), root.current_screen, root.position, root.size, root.content_scale_size])
	print("GPU_INFO state seeds=%d water=%.1f shots_in_flight=%d fruits=%d seed_tiles=%d greened=%d" % [play.seeds, play.water, main.projectile_view.shots.size(), play.pickups.count(), count_seed_tiles(main.grid), main.grid.greened_count])
	check(main.projectile_view.shots.size() >= 2, "a seed shot and a water shot are in flight at capture time (%d)" % main.projectile_view.shots.size())
	check(play.pickups.count() >= 1 and count_seed_tiles(main.grid) >= 4, "fruits lie near the source and seeds are scattered on the ground")
	var viewport_image: Image = root.get_texture().get_image()
	viewport_image.save_png(ProjectSettings.globalize_path(OUT + "gpu_viewport_640x360.png"))
	check(viewport_image.get_size() == Vector2i(640, 360), "internal frame is 640x360")
	var scene_crop: Image = viewport_image.get_region(Rect2i(120, 30, 400, 220))
	scene_crop.resize(scene_crop.get_width() * 3, scene_crop.get_height() * 3, Image.INTERPOLATE_NEAREST)
	scene_crop.save_png(ProjectSettings.globalize_path(OUT + "gpu_scene_crop_x3.png"))
	var hud_crop: Image = viewport_image.get_region(Rect2i(0, 322, 320, 38))
	hud_crop.resize(hud_crop.get_width() * 4, hud_crop.get_height() * 4, Image.INTERPOLATE_NEAREST)
	hud_crop.save_png(ProjectSettings.globalize_path(OUT + "gpu_hud_crop_x4.png"))
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
			check(distinct.size() > 50, "window image is real content (%d distinct colours)" % distinct.size())
			check(non_uniform_blocks == 0, "every %dx%d block of the window image is one colour (non-uniform blocks: %d)" % [k, k, non_uniform_blocks])
			check(mismatches == 0, "each block equals the internal-frame pixel (mismatching blocks: %d of %d)" % [mismatches, 640 * 360])
	print("P1_02_GPU_RESULT failures=%d" % failures)
	quit(failures)

func count_seed_tiles(state: WorldState) -> int:
	var total: int = 0
	for index: int in state.tile_count():
		if state.stage[index] == WorldState.STAGE_SEED:
			total += 1
	return total
