extends SceneTree
## P2-02 GPU render check (needs a real window, NOT headless). Engine-internal state and capture only; no OS input.
## Run: Godot --path <project> --screen 1 --script res://tests/p2/p2_02_gpu.gd -- --k2   (add --dry to skip the captures)
## One window, one stage: the ruin of a destroyed nest, a bone, a fresh carcass, a boar in the bright half of its hit flash and an
## unhurt boar side by side, in a field of mature plants. Saves the 640x360 viewport, the native window (PrintWindow) and x8 crops,
## and checks that every k x k block of the window is one colour and equals the viewport pixel (pixel-perfect, no smoothing).

const OUT: String = "res://evidence/p2/p2-02/"
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
	var centre: Vector2 = nest.center_px(TILE)
	# A field of mature plants around the nest (the nest's own tiles stay free), then the nests are destroyed (ruins).
	var planted: int = 0
	for y: int in range(nest.tile.y - 16, nest.tile.y + 20):
		for x: int in range(nest.tile.x - 24, nest.tile.x + 28):
			var index: int = world.index_of(x, y)
			if world.occupant[index] == 0 and world.set_stage(index, WorldState.STAGE_MATURE):
				planted += 1
	for other: Nest in enemies.nests:
		enemies.destroy_nest(other)
	# Carcass A is 61 s old (a bone); carcass B is fresh. All nests are gone, so nothing spawns during the 61 s.
	var bone_at: Vector2 = centre + Vector2(34, 30)
	var corpse_at: Vector2 = centre + Vector2(-34, 30)
	enemies.add_carcass(bone_at)
	for i: int in 60 * 61:
		enemies.advance(1.0 / 60.0)
	enemies.add_carcass(corpse_at)
	# Boar C is hit once (bright flash), boar D is unhurt. They stand still.
	var hurt: Boar = Boar.new()
	var calm: Boar = Boar.new()
	var spots: Array[Vector2] = [centre + Vector2(-10, -26), centre + Vector2(34, -26)]
	for pair: Array in [[hurt, spots[0]], [calm, spots[1]]]:
		var boar: Boar = pair[0]
		boar.id = enemies.next_boar_id
		enemies.next_boar_id += 1
		boar.pos = pair[1]
		boar.home = centre
		boar.hp = enemies.tuning.boar_hp
		boar.wait = 1 << 30
		boar.rng = 1
		boar.facing = 1
		enemies.boars.append(boar)
	enemies.damage_boar(hurt, 1)
	check(hurt.flash_steps == 15 and enemies.flash_bright(hurt.flash_steps) and calm.flash_steps == 0, "the hurt boar is in the bright half of its flash, the other one is not")
	check(enemies.carcass_count(0) == 1 and enemies.carcass_count(1) == 1, "one carcass and one bone are lying there")
	player.simulation_position = centre + Vector2(0, 60)
	player.position = player.simulation_position.round()
	player.presentation_updated.emit(player.position)
	await wait_frames(6)
	var cam_origin: Vector2 = main.camera.get_screen_center_position() - Vector2(320, 180)
	print("GPU_INFO camera_center=%s centre=%s" % [main.camera.get_screen_center_position(), centre])
	check(main.enemy_view.ruin_sprites.size() == 15 and main.enemy_view.carcass_sprites.size() == 2, "the view shows 15 ruins, a carcass and a bone")
	var hurt_sprite: Sprite2D = main.enemy_view.boar_sprites[hurt.id]
	var calm_sprite: Sprite2D = main.enemy_view.boar_sprites[calm.id]
	check(hurt_sprite.modulate.r > 1.5 and calm_sprite.modulate == Color.WHITE, "the hurt boar sprite is brightened, the other one is plain")
	var image: Image = await capture("scene") if not dry else null
	if not dry:
		var rect: Rect2i = Rect2i(Vector2i(centre - cam_origin) - Vector2i(64, 44), Vector2i(128, 100)).intersection(Rect2i(0, 0, 640, 360))
		var crop: Image = image.get_region(rect)
		crop.resize(crop.get_width() * 6, crop.get_height() * 6, Image.INTERPOLATE_NEAREST)
		crop.save_png(ProjectSettings.globalize_path(OUT + "gpu_scene_crop_x6.png"))
		report["crop_rect"] = [rect.position.x, rect.position.y, rect.size.x, rect.size.y]
	report["planted"] = planted
	report["bone_at"] = [bone_at.x, bone_at.y]
	report["corpse_at"] = [corpse_at.x, corpse_at.y]
	var file: FileAccess = FileAccess.open(ProjectSettings.globalize_path(OUT + "gpu_report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	print("GPU_INFO renderer=%s screens=%d window_screen=%d window_pos=%s window_size=%s" % [RenderingServer.get_current_rendering_method(), DisplayServer.get_screen_count(), root.current_screen, root.position, root.size])
	print("P2_02_GPU_RESULT failures=%d" % failures)
	quit(failures)
