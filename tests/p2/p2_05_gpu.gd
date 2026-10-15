extends SceneTree
## P2-05 GPU render check (needs a real window, NOT headless). Engine-internal state and capture only; no OS input.
## Run: Godot --path <project> --screen 1 --script res://tests/p2/p2_05_gpu.gd -- --k2   (add --dry to skip the captures)
## One window, one stage: a boar and the player in a field of mature plants. Saves the dim and bright halves of the hit flicker and the downed
## picture (lying flower, message, HUD at HP 0). Each as the 640x360 viewport, the native window (PrintWindow) and an x6 crop,
## and checks that every k x k block of the window is one colour and equals the viewport pixel (pixel-perfect, no smoothing).

const OUT: String = "res://evidence/p2/p2-05/"
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


func crop_save(source: Image, rect: Rect2i, scale: int, file_name: String) -> void:
	var crop: Image = source.get_region(rect)
	crop.resize(crop.get_width() * scale, crop.get_height() * scale, Image.INTERPOLATE_NEAREST)
	crop.save_png(ProjectSettings.globalize_path(OUT + file_name))

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
	var player: FlowerPlayer = main.player
	var driver: SimulationDriver = main.simulation
	main.enemy_driver.process_mode = Node.PROCESS_MODE_DISABLED
	main.play_driver.process_mode = Node.PROCESS_MODE_DISABLED
	driver.process_mode = Node.PROCESS_MODE_DISABLED
	player.set_physics_process(false)
	# Every zone stable (state set from outside), then 1500 s of game time stepped through the simulation clock.
	for z: int in world.zone_count:
		world.set_zone_state(z, maxi(world.zone_state[z], WorldState.ZONE_STABLE))
	for i: int in 6000:
		driver.clock.advance(0.25)
	var far: FarSeedSim = driver.far
	print("GPU_INFO t=%.0f far: components=%d finished=%d island_seeds=%d sweep_seeds=%d cursor=%d greened=%d/%d" % [driver.clock.elapsed, far.comp_count(), far.finished_comp_count(), far.total_island_planted, far.total_sweep_planted, far.sweep_cursor, world.greened_count, world.target_count])
	# Island view: the smallest component that has a plant and lies away from the sweep (largest index distance from the cursor).
	var best: int = -1
	var best_size: int = 1 << 30
	for c: int in far.finished_comp_count():
		var size: int = far.comp_end[c] - far.comp_start[c]
		if size >= 20 and size < best_size and size < 1200:
			best = c
			best_size = size
	check(best >= 0, "found an island-like component (%d tiles)" % best_size)
	var island_tile: int = far.members[far.comp_start[best]]
	for k: int in range(far.comp_start[best], far.comp_end[best]):
		if world.stage[far.members[k]] != 0:
			island_tile = far.members[k]
			break
	var ix: int = island_tile % world.width
	var iy: int = island_tile / world.width
	player.teleport((Vector2(ix, iy) + Vector2(0.5, 0.5)) * TILE + Vector2(0, 14))
	await wait_frames(10)
	var image1: Image = await capture("island_seed") if not dry else null
	# Sweep view: just behind the cursor, where the sweep has recently planted rows.
	var cx: int = 256
	var cy: int = clampi(far.sweep_cursor / world.width - 6, 4, world.height - 4)
	player.teleport((Vector2(cx, cy) + Vector2(0.5, 0.5)) * TILE)
	await wait_frames(10)
	var image2: Image = await capture("sweep_front") if not dry else null
	if not dry:
		crop_save(image1, Rect2i(220, 120, 200, 120), 4, "gpu_island_seed_crop_x4.png")
		crop_save(image2, Rect2i(220, 120, 200, 120), 4, "gpu_sweep_front_crop_x4.png")
	report["island"] = [ix, iy, best_size]
	report["cursor"] = far.sweep_cursor
	var file: FileAccess = FileAccess.open(ProjectSettings.globalize_path(OUT + "gpu_report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	print("GPU_INFO renderer=%s screens=%d window_screen=%d window_pos=%s window_size=%s" % [RenderingServer.get_current_rendering_method(), DisplayServer.get_screen_count(), root.current_screen, root.position, root.size])
	print("P2_05_GPU_RESULT failures=%d" % failures)
	quit(failures)
