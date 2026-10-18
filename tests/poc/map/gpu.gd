extends SceneTree
## POC-07 GPU capture of the town (real renderer, NOT --headless):
## godot --path <repo> --script res://tests/poc/map/gpu.gd
## No OS-level input / cursor movement / foregrounding; the window is marked unfocusable. Images go to evidence/poc/07/.
## STAGING (not play), stated on purpose: "before" = the game start state (only the safe zone is green) at noon. "after" =
## nests and boars removed, every greening target set to mature and game time fast-forwarded 560 s so the wall vegetation
## really grows. Nothing is hidden or moved in the scenery. The overview uses a wider camera (camera.size) than play
## (18.5 m) and a fixed look-at on the middle of the town; the follow shots use the normal play camera with the player
## put (display position only) on a walkable cell.
const Config: GDScript = preload("res://scripts/poc/poc_config.gd")
const Coords: GDScript = preload("res://scripts/poc/poc_coords.gd")
const OUT: String = "res://evidence/poc/07/"
const OVERVIEW_SIZE_M: float = 38.0
const SPOTS: Dictionary = {
	"start": Vector2i(88, 86),
	"pool": Vector2i(40, 54),
	"alley": Vector2i(57, 24),
	"nest": Vector2i(84, 46),
}

var failures: int = 0
var passes: int = 0
var main: Node
var stats: PackedStringArray = []

func check(name: String, ok: bool, detail: String = "") -> void:
	if ok:
		passes += 1
		print("PASS ", name, " ", detail)
	else:
		failures += 1
		print("FAIL ", name, " ", detail)

func _init() -> void:
	root.unfocusable = true
	_run.call_deferred()

func _frames(n: int) -> void:
	for i: int in n:
		await process_frame
	await RenderingServer.frame_post_draw

func _grab() -> Image:
	await _frames(4)
	return main.render_view.get_texture().get_image()

func _save(image: Image, name: String) -> void:
	image.save_png(ProjectSettings.globalize_path(OUT + name))

func set_hour(hour: float) -> void:
	var s: RefCounted = main.session
	var elapsed: float = fposmod(hour - float(s.env_tuning["start_hour"]), 24.0) / 24.0 * float(s.env_tuning["day_seconds"])
	s.clock.load_dict({"version": 1, "elapsed": elapsed, "growth_ticks": int(elapsed / s.clock.growth_period), "spread_ticks": int(elapsed / s.clock.spread_period)})
	s.growth.ticks = s.clock.growth_ticks
	s.state.growth_tick = s.clock.growth_ticks
	main.tick(0.0, Vector2.ZERO)

func _settle() -> void:
	for i: int in 14:
		main.tick(0.05, Vector2.ZERO)

## Share of pixels that are clearly green (g above r and b) and of the image that is not almost black; and the mean colour.
func _measure(image: Image) -> Dictionary:
	var green: int = 0
	var dark: int = 0
	var sum: Color = Color(0, 0, 0)
	var count: int = image.get_width() * image.get_height()
	for y: int in image.get_height():
		for x: int in image.get_width():
			var c: Color = image.get_pixel(x, y)
			sum += c
			if c.g > c.r + 0.04 and c.g > c.b + 0.04:
				green += 1
			if c.get_luminance() < 0.05:
				dark += 1
	return {"green": float(green) / float(count), "dark": float(dark) / float(count), "mean": sum / float(count)}

func _overview(res_index: int) -> void:
	main.set_resolution(res_index, Vector2i(1920, 1080))
	main.camera.size = OVERVIEW_SIZE_M
	var center_ground: Vector2 = Coords.logic_to_ground(Vector2(56.0, 56.0) * float(Config.TILE_PX))
	var focus: Vector3 = Vector3(center_ground.x, 1.0, center_ground.y)
	main.camera.position = focus + main._offset
	main.camera.look_at(focus, Vector3.UP)
	main.water_view.sync_camera()

func _follow(cell: Vector2i) -> void:
	main.camera.size = Config.CAMERA_SIZE_M
	main.session.position = Coords.cell_center_logic(cell)
	_settle()

func _shot(name: String, tag: String, overview: bool, res_index: int, cell: Vector2i = Vector2i(88, 86)) -> Image:
	if overview:
		main.session.position = Coords.cell_center_logic(cell)
		_settle()
		_overview(res_index)
	else:
		main.set_resolution(res_index, Vector2i(1920, 1080))
		_follow(cell)
	var image: Image = await _grab()
	_save(image, name)
	var m: Dictionary = _measure(image)
	stats.append("%s: %dx%d green=%.3f dark=%.3f mean=%s" % [name, image.get_width(), image.get_height(), m["green"], m["dark"], m["mean"]])
	print("INFO ", stats[stats.size() - 1])
	m["tag"] = tag
	return image

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		print("NOT_RUN gpu (headless display server)")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	print("renderer=", RenderingServer.get_video_adapter_name(), " display=", DisplayServer.get_name(), " window=", root.size)
	main = load("res://scenes/poc.tscn").instantiate()
	main.set_meta(&"poc_town", true)
	root.add_child(main)
	main.auto_process = false
	main.window_size_override = Vector2i(1920, 1080)
	await _frames(3)
	var s: RefCounted = main.session
	check("gpu.town_loaded", s.combat_mode and s.state.width == 112 and main.occlusion_view != null and main.wall_view != null, "targets=%d" % s.state.target_count)
	set_hour(12.0)
	_settle()
	var before: Dictionary = {}
	var after: Dictionary = {}
	# ---------------- before greening, noon
	var img_before: Image = await _shot("overview_day_before_640.png", "before", true, 0)
	await _shot("follow_start_day_before_640.png", "before", false, 0, SPOTS["start"])
	await _shot("follow_pool_day_before_640.png", "before", false, 0, SPOTS["pool"])
	await _shot("follow_nest_day_before_640.png", "before", false, 0, SPOTS["nest"])
	before = _measure(img_before)
	var green_before: int = s.state.greened_count
	# ---------------- staging "after": nests and boars removed, all targets mature, wall vegetation grown
	for nest: Nest in s.enemies.nests.duplicate():
		s.enemies.destroy_nest(nest)
	for boar: Boar in s.enemies.boars.duplicate():
		s.enemies.remove_boar(boar)
	s.enemy_tuning.enabled = false
	for i: int in s.state.tile_count():
		if s.state.target[i] != 0:
			s.state.set_stage(i, WorldState.STAGE_MATURE)
	for i: int in 560:
		s.advance_game(0.25)
	set_hour(12.0)
	_settle()
	check("gpu.greened_100", s.state.greened_count == s.state.target_count and s.wall_growth.total_progress() > 1.0, "greened %d -> %d/%d, wall progress %.1f" % [green_before, s.state.greened_count, s.state.target_count, s.wall_growth.total_progress()])
	var img_after: Image = await _shot("overview_day_after_640.png", "after", true, 0)
	after = _measure(img_after)
	await _shot("overview_day_after_960.png", "after", true, 1)
	await _shot("follow_start_day_after_640.png", "after", false, 0, SPOTS["start"])
	await _shot("follow_pool_day_after_640.png", "after", false, 0, SPOTS["pool"])
	await _shot("follow_alley_day_after_640.png", "after", false, 0, SPOTS["alley"])
	set_hour(0.0)
	_settle()
	var img_night: Image = await _shot("overview_night_after_640.png", "night", true, 0)
	await _shot("follow_pool_night_after_640.png", "night", false, 0, SPOTS["pool"])
	var night: Dictionary = _measure(img_night)
	check("gpu.greening_visible_overview", float(after["green"]) > float(before["green"]) * 1.5, "green share before %.3f after %.3f" % [before["green"], after["green"]])
	check("gpu.night_darker_than_day", (night["mean"] as Color).get_luminance() < (after["mean"] as Color).get_luminance() * 0.8, "luminance day %.3f night %.3f" % [(after["mean"] as Color).get_luminance(), (night["mean"] as Color).get_luminance()])
	check("gpu.images_not_blank", float(before["dark"]) < 0.6 and float(after["dark"]) < 0.6, "dark share before %.3f after %.3f" % [before["dark"], after["dark"]])
	print("RESULT passes=%d failures=%d" % [passes, failures])
	for line: String in stats:
		print("STAT ", line)
	quit(1 if failures > 0 else 0)
