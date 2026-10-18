extends SceneTree
## POC-03 GPU capture checks (real renderer, NOT --headless):
## godot --path <repo> --script res://tests/poc/play/gpu.gd
## No OS-level input / cursor movement; the window is marked unfocusable. Images go to evidence/poc/03/.
const Config: GDScript = preload("res://scripts/poc/poc_config.gd")
const Coords: GDScript = preload("res://scripts/poc/poc_coords.gd")
const OUT: String = "res://evidence/poc/03/"

var failures: int = 0
var passes: int = 0
var main: Node

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
	await _frames(3)
	return main.render_view.get_texture().get_image()

func _save(image: Image, name: String) -> void:
	image.save_png(ProjectSettings.globalize_path(OUT + name))

func _count_color(image: Image, html: String) -> int:
	var total: int = 0
	var target: Color = Color(html)
	for y: int in image.get_height():
		for x: int in image.get_width():
			var c: Color = image.get_pixel(x, y)
			if absf(c.r - target.r) < 0.02 and absf(c.g - target.g) < 0.02 and absf(c.b - target.b) < 0.02:
				total += 1
	return total

func _count_diff(a: Image, b: Image) -> int:
	var count: int = 0
	for y: int in a.get_height():
		for x: int in a.get_width():
			if a.get_pixel(x, y) != b.get_pixel(x, y):
				count += 1
	return count

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		print("NOT_RUN gpu (headless display server)")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	main = load("res://scenes/poc.tscn").instantiate()
	root.add_child(main)
	main.auto_process = false
	main.window_size_override = Vector2i(1920, 1080)
	await _frames(3)
	print("renderer=", RenderingServer.get_video_adapter_name(), " display=", DisplayServer.get_name(), " window=", root.size)
	var s: RefCounted = main.session
	# Open ground in the north-east corner (beside the pond; no tall object between it and the camera).
	s.position = Coords.cell_center_logic(Vector2i(38, 11))
	main.tick(0.0, Vector2.ZERO)
	var base: Image = await _grab()
	_save(base, "base_640.png")
	var spot: Vector2i = Vector2i(42, 11)
	var ok_spot: bool = true
	for dy: int in range(-2, 3):
		for dx: int in range(-2, 3):
			var n: Vector2i = spot + Vector2i(dx, dy)
			ok_spot = ok_spot and s.state.is_walkable(n.x, n.y) and s.state.target[s.state.index_of(n.x, n.y)] == 1 and not s.placement.projectile_blocked_cell(n)
	check("gpu.spot_open", ok_spot and not s.shot_blocked(s.position, Coords.cell_center_logic(spot)), str(spot))
	var ground: Vector2 = Coords.cell_center_ground(spot)
	var screen: Vector2 = main.camera.unproject_position(Vector3(ground.x, 0.0, ground.y))
	var fired: Dictionary = main.click_fire(screen, false)
	check("gpu.click_fires_seed", fired["ok"], str(fired))
	main.tick(0.05, Vector2.ZERO)
	var flight: Image = await _grab()
	_save(flight, "scene0_shot_in_flight_640.png")
	check("gpu.shot_visible_in_flight", main.play_view.snapshot()["shots_visible"] == 1 and _count_color(flight, "fff1c2") > 3, "pale shot px=%d" % _count_color(flight, "fff1c2"))
	for i: int in 30:
		main.tick(0.1, Vector2.ZERO)
	var seeded: Image = await _grab()
	_save(seeded, "scene1_seeded_640.png")
	var seed_px: int = _count_color(seeded, "ffe5a0")
	check("gpu.seed_cells_visible", s.play.last_scatter.size() > 0 and _count_diff(base, seeded) > 20, "(lit colour, px=%d) scattered=%d diff vs base=%d" % [seed_px, s.play.last_scatter.size(), _count_diff(base, seeded)])
	s.advance_game(130.0)
	main.tick(0.0, Vector2.ZERO)
	var mature: Image = await _grab()
	_save(mature, "scene2_mature_640.png")
	var mature_px: int = _count_color(mature, "ffe5a0")
	check("gpu.growth_changes_look", _count_diff(seeded, mature) > 200, "diff=%d seed px %d -> %d" % [_count_diff(seeded, mature), seed_px, mature_px])
	# Pickups, cultivated plants, the seed source and a water shot together (on a mature patch so carrot / kiwi can be placed).
	s.state.debug_fill_stage(Rect2i(33, 13, 3, 3), WorldState.STAGE_MATURE)
	s.state.debug_fill_stage(Rect2i(36, 13, 3, 3), WorldState.STAGE_MATURE)
	s.position = Coords.cell_center_logic(Vector2i(38, 10))
	s.play.pickups.spawn("seed_fruit", s.position + Vector2(10, 6), 1)
	s.play.pickups.spawn("seed_fruit", s.position + Vector2(-14, 4), 1)
	s.play.pickups.spawn("heal_fruit", s.position + Vector2(4, 14), 2000001, 30.0)
	s.cycle_plant(1)
	s.play.cultivation.try_place(&"carrot", Coords.cell_center_logic(Vector2i(34, 14)))
	s.cycle_plant(1)
	s.play.cultivation.try_place(&"kiwi", Coords.cell_center_logic(Vector2i(37, 14)))
	s.fire(true, s.position + Vector2(40, -6))
	main.tick(0.05, Vector2.ZERO)
	var pick640: Image = await _grab()
	_save(pick640, "scene3_pickups_640.png")
	var snap: Dictionary = main.play_view.snapshot()
	check("gpu.pickups_visible", snap["pickups_visible"] >= 3 and snap["cultivated"] == 2 and snap["sources"] == 1 and _count_color(pick640, "ffd34a") > 4, str(snap))
	check("gpu.water_shot_visible", _count_color(pick640, "63b8cf") > 3, "water px=%d" % _count_color(pick640, "63b8cf"))
	main.set_resolution(1, Vector2i(1920, 1080))
	main.tick(0.0, Vector2.ZERO)
	var pick960: Image = await _grab()
	_save(pick960, "scene4_pickups_960.png")
	check("gpu.size_960", pick960.get_size() == Vector2i(960, 540) and _count_color(pick960, "ffd34a") > 8, "yellow px=%d" % _count_color(pick960, "ffd34a"))
	main.queue_free()
	await _frames(2)
	print("RESULT passes=%d failures=%d" % [passes, failures])
	quit(1 if failures > 0 else 0)
