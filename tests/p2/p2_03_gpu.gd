extends SceneTree
## P2-03 GPU render check (needs a real window, NOT headless). Engine-internal state and capture only; no OS input.
## Run: Godot --path <project> --screen 1 --script res://tests/p2/p2_03_gpu.gd -- --k2   (add --dry to skip the captures)
## One window, one stage: a boar and the player in a field of mature plants. Saves the dim and bright halves of the hit flicker and the downed
## picture (lying flower, message, HUD at HP 0). Each as the 640x360 viewport, the native window (PrintWindow) and an x6 crop,
## and checks that every k x k block of the window is one colour and equals the viewport pixel (pixel-perfect, no smoothing).

const OUT: String = "res://evidence/p2/p2-03/"
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
	var play: PlayState = main.play
	var player: FlowerPlayer = main.player
	# The game drivers stay off: the state is stepped here, so the picture is reproducible.
	main.enemy_driver.process_mode = Node.PROCESS_MODE_DISABLED
	main.play_driver.process_mode = Node.PROCESS_MODE_DISABLED
	main.simulation.process_mode = Node.PROCESS_MODE_DISABLED
	player.set_physics_process(false)
	var nest: Nest = enemies.nests[0]
	var centre: Vector2 = nest.center_px(TILE)
	var planted: int = 0
	for y: int in range(nest.tile.y - 16, nest.tile.y + 20):
		for x: int in range(nest.tile.x - 24, nest.tile.x + 28):
			var index: int = world.index_of(x, y)
			if world.occupant[index] == 0 and world.set_stage(index, WorldState.STAGE_MATURE):
				planted += 1
	for other: Nest in enemies.nests:
		enemies.destroy_nest(other)
	var boar: Boar = Boar.new()
	boar.id = enemies.next_boar_id
	enemies.next_boar_id += 1
	boar.pos = centre + Vector2(16, -22)
	boar.home = centre
	boar.hp = enemies.tuning.boar_hp
	boar.wait = 1 << 30
	boar.rng = 1
	boar.facing = -1
	enemies.boars.append(boar)
	var spot: Vector2 = boar.pos + Vector2(-9, 4)
	player.teleport(spot)
	await wait_frames(4)
	# Hit: the player is pushed, then the flicker; step until the dim half shows.
	var hit_ok: bool = play.health.hit(play, 2, enemies.boar_body_center(boar), player.simulation_position, boar.facing)
	check(hit_ok and play.hp == 8, "the player is hurt (HP 8)")
	var guard: int = 0
	while not play.health.flicker_dim() and guard < 40:
		play.advance(1.0 / 60.0, player.simulation_position)
		guard += 1
	player.update_look()
	await wait_frames(6)
	check(player.visual.modulate.a < 0.5 and main.hud.hp_label.text == "HP 8/10", "dim half of the flicker (alpha %.2f), HUD HP 8/10" % player.visual.modulate.a)
	var cam_origin: Vector2 = main.camera.get_screen_center_position() - Vector2(320, 180)
	var player_screen: Vector2 = player.position - cam_origin
	print("GPU_INFO camera_center=%s player=%s screen=%s hp_text=%s" % [main.camera.get_screen_center_position(), player.position, player_screen, main.hud.hp_label.text])
	var dim_image: Image = await capture("hit_dim") if not dry else null
	guard = 0
	while play.health.flicker_dim() and guard < 40:
		play.advance(1.0 / 60.0, player.simulation_position)
		guard += 1
	player.update_look()
	await wait_frames(6)
	check(player.visual.modulate.a == 1.0, "bright half of the flicker")
	var bright_image: Image = await capture("hit_bright") if not dry else null
	# Downed.
	play.damage_player(play.hp)
	play.advance(1.0 / 60.0, player.simulation_position)
	play.advance(1.0 / 60.0, player.simulation_position)
	player.update_look()
	await wait_frames(6)
	check(play.health.downed and main.down_panel.visible and main.hud.hp_label.text == "HP 0/10" and player.visual.texture == PlayArt.flower_down(), "downed: lying flower, message panel, HUD HP 0/10")
	var down_image: Image = await capture("downed") if not dry else null
	if not dry:
		var rect: Rect2i = Rect2i(Vector2i(player_screen) - Vector2i(48, 40), Vector2i(96, 64)).intersection(Rect2i(0, 0, 640, 360))
		for pair: Array in [["hit_dim", dim_image], ["hit_bright", bright_image], ["downed", down_image]]:
			var crop: Image = (pair[1] as Image).get_region(rect)
			crop.resize(crop.get_width() * 6, crop.get_height() * 6, Image.INTERPOLATE_NEAREST)
			crop.save_png(ProjectSettings.globalize_path(OUT + "gpu_%s_crop_x6.png" % String(pair[0])))
		var hud_rect: Rect2i = Rect2i(0, 320, 640, 40)
		var hud_crop: Image = down_image.get_region(hud_rect)
		hud_crop.resize(hud_crop.get_width() * 3, hud_crop.get_height() * 3, Image.INTERPOLATE_NEAREST)
		hud_crop.save_png(ProjectSettings.globalize_path(OUT + "gpu_downed_hud_x3.png"))
		var panel_rect: Rect2i = Rect2i(220, 128, 200, 72)
		var panel_crop: Image = down_image.get_region(panel_rect)
		panel_crop.resize(panel_crop.get_width() * 4, panel_crop.get_height() * 4, Image.INTERPOLATE_NEAREST)
		panel_crop.save_png(ProjectSettings.globalize_path(OUT + "gpu_downed_panel_x4.png"))
		report["crop_rect"] = [rect.position.x, rect.position.y, rect.size.x, rect.size.y]
	report["planted"] = planted
	var file: FileAccess = FileAccess.open(ProjectSettings.globalize_path(OUT + "gpu_report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	print("GPU_INFO renderer=%s screens=%d window_screen=%d window_pos=%s window_size=%s" % [RenderingServer.get_current_rendering_method(), DisplayServer.get_screen_count(), root.current_screen, root.position, root.size])
	print("P2_03_GPU_RESULT failures=%d" % failures)
	quit(failures)
