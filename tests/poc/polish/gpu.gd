extends SceneTree
## POL-01 GPU captures (real renderer, NOT --headless): godot --path <repo> --script res://tests/poc/polish/gpu.gd [-- --tag=after]
## No OS-level input / cursor / foregrounding (root.unfocusable). Town session, clock moved to the hour of each picture.
## Images -> evidence/poc-polish/01/<tag>_*.png (full 3D view) and <tag>_*_zoom.png (player crop x4, nearest).
const Config: GDScript = preload("res://scripts/poc/poc_config.gd")
const Coords: GDScript = preload("res://scripts/poc/poc_coords.gd")
const OUT: String = "res://evidence/poc-polish/01/"
var main: Node
var s: RefCounted
var tag: String = "after"
var failures: int = 0
var passes: int = 0

func check(name: String, ok: bool, detail: String = "") -> void:
	print("PASS " if ok else "FAIL ", name, " ", detail)
	if ok:
		passes += 1
	else:
		failures += 1

func _init() -> void:
	root.unfocusable = true
	_run.call_deferred()

func _frames(n: int) -> void:
	for i: int in n:
		await process_frame
	await RenderingServer.frame_post_draw

func set_hour(hour: float) -> void:
	var elapsed: float = fposmod(hour - float(s.env_tuning["start_hour"]), 24.0) / 24.0 * float(s.env_tuning["day_seconds"])
	s.clock.load_dict({"version": 1, "elapsed": elapsed, "growth_ticks": int(elapsed / s.clock.growth_period), "spread_ticks": int(elapsed / s.clock.spread_period)})
	s.growth.ticks = s.clock.growth_ticks
	s.state.growth_tick = s.clock.growth_ticks

func shoot(name: String, res_index: int, hour: float, ground: Vector2, zoom_player: bool = true, zoom_at: Vector2 = Vector2.INF) -> Image:
	set_hour(hour)
	s.position = Coords.ground_to_logic(ground)
	main.set_resolution(res_index, Vector2i(1920, 1080))
	for i: int in 30:
		main.tick(0.05, Vector2.ZERO)
	await _frames(4)
	var image: Image = main.render_view.get_texture().get_image()
	var file: String = "%s_%s_%d" % [tag, name, Config.RESOLUTIONS[res_index].x]
	image.save_png(ProjectSettings.globalize_path(OUT + file + ".png"))
	if zoom_player or zoom_at != Vector2.INF:
		var focus: Vector3 = main.actor.render_foot if zoom_at == Vector2.INF else Vector3(zoom_at.x, 0.0, zoom_at.y)
		var foot: Vector2 = main.camera.unproject_position(focus) * (float(image.get_height()) / float(main.render_view.size.y))
		var size: Vector2i = Vector2i(image.get_width() / 4, image.get_height() / 4)
		var origin: Vector2i = Vector2i(clampi(int(foot.x) - size.x / 2, 0, image.get_width() - size.x), clampi(int(foot.y) - size.y * 2 / 3, 0, image.get_height() - size.y))
		var crop: Image = image.get_region(Rect2i(origin, size))
		crop.resize(size.x * 4, size.y * 4, Image.INTERPOLATE_NEAREST)
		crop.save_png(ProjectSettings.globalize_path(OUT + file + "_zoom.png"))
	print("INFO ", file, " hour=", snappedf(s.day_hour(), 0.01), " readability=", main.readability.snapshot() if main.readability != null else "none")
	return image

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		print("NOT_RUN gpu (headless display server)")
		quit(2)
		return
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--tag="):
			tag = a.substr(6)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	print("renderer=", RenderingServer.get_video_adapter_name(), " window=", root.size)
	main = load("res://scenes/poc.tscn").instantiate()
	main.set_meta(&"poc_town", true)
	root.add_child(main)
	main.auto_process = false
	main.window_size_override = Vector2i(1920, 1080)
	await _frames(3)
	s = main.session
	for res_index: int in 2:
		await shoot("night_lamp", res_index, 0.0, Vector2(7.6, 11.2))
		await shoot("night_dark", res_index, 0.0, Vector2(-3.0, 8.0))
		await shoot("day_lamp", res_index, 12.0, Vector2(7.6, 11.2))
	# occlusion: stand behind a building from the camera
	var ov: Node = main.occlusion_view
	var half: Vector2 = Config.player_half_px()
	var spot: Vector2 = Vector2.INF
	for entry: Dictionary in ov.occlusion.entries:
		var inst: Dictionary = s.placement.get_instance(String(entry["ids"][0]))
		if String(inst["kind"]) != "building":
			continue
		var p: Vector2 = inst["pos"]
		for k: int in range(3, 12):
			var foot: Vector3 = Vector3(p.x - 0.5 * float(k) * 0.707107, 0.04, p.y - 0.5 * float(k) * 0.707107)
			var logic: Vector2 = Coords.ground_to_logic(Vector2(foot.x, foot.z))
			var keys: Array = ov.occlusion.raw_occluders(ov.occlusion.sample_points(foot, 1.42, main.camera.global_basis.x), main.camera.global_basis.z).keys()
			if Walker.is_clear(s.state, Config.TILE_PX, logic, half) and keys == [String(entry["group"])]:
				spot = Vector2(foot.x, foot.z)
				break
		if spot != Vector2.INF:
			break
	check("occlusion_spot", spot != Vector2.INF, str(spot))
	for res_index: int in 2:
		await shoot("occluded_day", res_index, 12.0, spot)
		check("occluded_fading_%d" % res_index, not ov.faded_instances().is_empty(), str(ov.faded_instances()))
		await shoot("occluded_night", res_index, 0.0, spot)
	# water by the pond, day and night
	var bank: Vector2 = Coords.cell_center_ground(Vector2i(44, 55))
	for res_index: int in 2:
		var pond: Vector2 = Coords.cell_center_ground(Vector2i(54, 55))
		await shoot("water_day", res_index, 12.0, bank, false, pond)
		await shoot("water_night", res_index, 0.0, bank, false, pond)
		await shoot("water_dusk", res_index, 17.5, bank, false, pond)
	# whole-town overview (camera widened for this picture only; the player sprite is hidden because its size follows the camera)
	set_hour(12.0)
	main.set_resolution(0, Vector2i(1920, 1080))
	s.position = Coords.ground_to_logic(Vector2(21.0, 20.0))
	main.camera.size = 40.0
	main.actor.visible = false
	for i: int in 10:
		main.tick(0.05, Vector2.ZERO)
		main.camera.size = 40.0
	await _frames(4)
	var whole: Image = main.render_view.get_texture().get_image()
	whole.save_png(ProjectSettings.globalize_path(OUT + tag + "_overview_day_640.png"))
	print("INFO overview saved")
	print("RESULT passes=%d failures=%d" % [passes, failures])
	quit(1 if failures > 0 else 0)
