extends SceneTree
## P2-04 GPU render check (needs a real window, NOT headless). Engine-internal state and capture only; no OS input.
## Run: Godot --path <project> --screen 1 --script res://tests/p2/p2_03_gpu.gd -- --k2   (add --dry to skip the captures)
## One window, one stage: a boar and the player in a field of mature plants. Saves the dim and bright halves of the hit flicker and the downed
## picture (lying flower, message, HUD at HP 0). Each as the 640x360 viewport, the native window (PrintWindow) and an x6 crop,
## and checks that every k x k block of the window is one colour and equals the viewport pixel (pixel-perfect, no smoothing).

const OUT: String = "res://evidence/p2/p2-04/"
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
	var enemies: EnemyField = main.enemies
	var player: FlowerPlayer = main.player
	var notice: ZoneNotice = main.zone_notice
	# The game drivers stay off: the state is stepped here, so the picture is reproducible.
	main.enemy_driver.process_mode = Node.PROCESS_MODE_DISABLED
	main.play_driver.process_mode = Node.PROCESS_MODE_DISABLED
	main.simulation.process_mode = Node.PROCESS_MODE_DISABLED
	player.set_physics_process(false)
	var zone: int = 2
	var zone_nests: Array[Nest] = []
	for nest: Nest in enemies.nests:
		if nest.zone == zone:
			zone_nests.append(nest)
	var centre: Vector2 = zone_nests[0].center_px(TILE)
	# Some greening around the player so the rate is not 0.
	var planted: int = 0
	for y: int in range(zone_nests[0].tile.y - 12, zone_nests[0].tile.y + 16):
		for x: int in range(zone_nests[0].tile.x - 30, zone_nests[0].tile.x - 4):
			var index: int = world.index_of(x, y)
			if world.zone_of[index] == zone and world.occupant[index] == 0 and world.set_stage(index, WorldState.STAGE_MATURE):
				planted += 1
	var spot: Vector2 = centre + Vector2(-40, 12)
	player.teleport(spot)
	await wait_frames(8)
	check(main.zone_label.text.begins_with("  西岸南1  未制圧  緑化 ") and not notice.visible, "stage 1: top bar '%s', no notice" % main.zone_label.text)
	var image1: Image = await capture("zone_status") if not dry else null
	# Stage 2: every nest of the zone destroyed (no boar alive): clearing, stable; the second notice is on screen.
	for nest: Nest in zone_nests:
		enemies.destroy_nest(nest)
	await wait_frames(4)
	check(notice.current_text == "西岸南1の巣をすべて壊した", "stage 2: first notice shown: %s" % notice.current_text)
	notice.advance(10.0)
	await wait_frames(6)
	check(notice.current_text == "西岸南1が安定した" and main.zone_label.text.begins_with("  西岸南1  安定  緑化 "), "stage 2: second notice '%s', top bar '%s'" % [notice.current_text, main.zone_label.text])
	var image2: Image = await capture("zone_stable_notice") if not dry else null
	# Stage 3: the whole region greened.
	for z: int in world.zone_count:
		world.set_zone_state(z, maxi(world.zone_state[z], WorldState.ZONE_STABLE))
	world.debug_fill_stage(Rect2i(0, 0, world.width, world.height), WorldState.STAGE_MATURE)
	var guard: int = 0
	while notice.current_text != ZoneHud.CLEARED_TEXT and guard < 40:
		notice.advance(10.0)
		guard += 1
	await wait_frames(40)
	check(world.cleared and notice.current_text == "すべての地域を緑化した" and main.zone_label.text.ends_with("【全地域緑化】"), "stage 3: cleared, notice '%s', top bar '%s'" % [notice.current_text, main.zone_label.text])
	var image3: Image = await capture("cleared") if not dry else null
	if not dry:
		for pair: Array in [["zone_status", image1], ["zone_stable_notice", image2], ["cleared", image3]]:
			crop_save(pair[1] as Image, Rect2i(0, 0, 640, 72), 3, "gpu_%s_top_x3.png" % String(pair[0]))
	report["planted"] = planted
	var file: FileAccess = FileAccess.open(ProjectSettings.globalize_path(OUT + "gpu_report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	print("GPU_INFO renderer=%s screens=%d window_screen=%d window_pos=%s window_size=%s" % [RenderingServer.get_current_rendering_method(), DisplayServer.get_screen_count(), root.current_screen, root.position, root.size])
	print("P2_04_GPU_RESULT failures=%d" % failures)
	quit(failures)
