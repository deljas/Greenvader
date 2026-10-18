extends SceneTree
## POC-05 GPU capture checks (real renderer, NOT --headless):
## godot --path <repo> --script res://tests/poc/environment/gpu.gd
## No OS-level input / cursor movement; the window is marked unfocusable. Images go to evidence/poc/05/.
## FIXTURE STAGING (not play): scene A uses the POC-04 combat fixture (open ground, lake, paved road) with all nests and boars
## removed through the game rules; the ground is matured in bands (left mature, middle sprouts, right bare) and game time is
## fast-forwarded so the wall vegetation really grows from that ground; the clock is then moved to the hour of each picture.
## Scene B (default placement fixture) shows the chapel wall the same way. The lake is the water surface.
const Config: GDScript = preload("res://scripts/poc/poc_config.gd")
const Coords: GDScript = preload("res://scripts/poc/poc_coords.gd")
const Day: GDScript = preload("res://scripts/poc/environment/poc_day.gd")
const OUT: String = "res://evidence/poc/05/"

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
	await _frames(4)
	return main.render_view.get_texture().get_image()

func _save(image: Image, name: String) -> void:
	image.save_png(ProjectSettings.globalize_path(OUT + name))

func _zoom(image: Image, center: Vector2, size: Vector2i, factor: int, name: String) -> Image:
	var origin: Vector2i = Vector2i(clampi(int(center.x) - size.x / 2, 0, image.get_width() - size.x), clampi(int(center.y) - size.y / 2, 0, image.get_height() - size.y))
	var crop: Image = image.get_region(Rect2i(origin, size))
	var big: Image = crop.duplicate()
	big.resize(size.x * factor, size.y * factor, Image.INTERPOLATE_NEAREST)
	big.save_png(ProjectSettings.globalize_path(OUT + name))
	return crop

func _diff(a: Image, b: Image) -> int:
	var count: int = 0
	for y: int in a.get_height():
		for x: int in a.get_width():
			if a.get_pixel(x, y) != b.get_pixel(x, y):
				count += 1
	return count

func _mean(image: Image) -> float:
	var total: float = 0.0
	for y: int in range(0, image.get_height(), 2):
		for x: int in range(0, image.get_width(), 2):
			var c: Color = image.get_pixel(x, y)
			total += (c.r + c.g + c.b) / 3.0
	return total / float((image.get_height() / 2) * (image.get_width() / 2))

func set_hour(hour: float) -> void:
	var s: RefCounted = main.session
	var elapsed: float = fposmod(hour - float(s.env_tuning["start_hour"]), 24.0) / 24.0 * float(s.env_tuning["day_seconds"])
	s.clock.load_dict({"version": 1, "elapsed": elapsed, "growth_ticks": int(elapsed / s.clock.growth_period), "spread_ticks": int(elapsed / s.clock.spread_period)})
	s.growth.ticks = s.clock.growth_ticks
	s.state.growth_tick = s.clock.growth_ticks
	main.tick(0.0, Vector2.ZERO)

func screen_of(cell: Vector2i) -> Vector2:
	var g: Vector2 = Coords.cell_center_ground(cell)
	return main.camera.unproject_position(Vector3(g.x, 0.0, g.y))

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		print("NOT_RUN gpu (headless display server)")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	await _scene_a()
	await _scene_b()
	print("RESULT passes=%d failures=%d" % [passes, failures])
	quit(1 if failures > 0 else 0)

func _open(combat: bool) -> void:
	main = load("res://scenes/poc.tscn").instantiate()
	if combat:
		main.set_meta(&"poc_combat", true)
	root.add_child(main)
	main.auto_process = false
	main.window_size_override = Vector2i(1920, 1080)
	await _frames(3)

func _stage_ground(player_cell: Vector2i) -> void:
	var s: RefCounted = main.session
	for y: int in s.state.height:
		for x: int in s.state.width:
			var i: int = s.state.index_of(x, y)
			if s.state.target[i] == 0:
				continue
			var stage: int = WorldState.STAGE_MATURE if x < 24 else (WorldState.STAGE_SPROUT2 if x < 32 else (WorldState.STAGE_SPROUT1 if x < 38 else WorldState.STAGE_EMPTY))
			s.state.set_stage(i, stage)
	s.position = Coords.cell_center_logic(player_cell)
	for i: int in 560:
		s.advance_game(0.25)
		s.position = Coords.cell_center_logic(player_cell)
	main.tick(0.0, Vector2.ZERO)

func _scene_a() -> void:
	await _open(true)
	print("renderer=", RenderingServer.get_video_adapter_name(), " display=", DisplayServer.get_name(), " window=", root.size)
	var s: RefCounted = main.session
	for n: Nest in s.enemies.nests:
		s.enemies.damage_nest(n, 99)
	for boar: Boar in s.enemies.boars.duplicate():
		s.enemies.damage_boar(boar, 99)
	s.placement.move_instance("tree_01", Vector2(-4.4, -5.0), 0.0)
	main.placement_view.refresh_transforms()
	# Picture staging only: the tall container ruin is hidden (it would cover the middle of the map from this camera).
	main.placement_view.holders["ruin_01"].visible = false
	_stage_ground(Vector2i(24, 15))
	var grown: float = s.wall_growth.total_progress()
	check("gpu.wall_grew_from_ground", grown > 1.0, "progress sum=%f of %d" % [grown, s.wall_growth.entries.size()])
	var mill_cell: Vector2i = Vector2i(9, 30)
	var pond_cell: Vector2i = Vector2i(8, 9)
	# ---- shots: resolution x hour
	var shots: Dictionary = {}
	for res_index: int in 2:
		main.set_resolution(res_index, Vector2i(1920, 1080))
		var res: Vector2i = Config.RESOLUTIONS[res_index]
		for pair: Array in [["noon", 12.0], ["night", 0.0], ["morning", 7.0], ["evening", 17.5]]:
			set_hour(float(pair[1]))
			var image: Image = await _grab()
			shots["%s_%d" % [pair[0], res.x]] = image
			_save(image, "scene_%s_%d.png" % [pair[0], res.x])
			print("INFO ", pair[0], " ", res.x, " hour=", main.env_view.hour_text(), " light_energy=", main.sun.light_energy, " mean=", _mean(image))
		check("gpu.size_%d" % res.x, (shots["noon_%d" % res.x] as Image).get_size() == res)
	check("gpu.noon_brighter_than_night_640", _mean(shots["noon_640"]) > _mean(shots["night_640"]) * 1.5, "%f vs %f" % [_mean(shots["noon_640"]), _mean(shots["night_640"])])
	check("gpu.noon_brighter_than_night_960", _mean(shots["noon_960"]) > _mean(shots["night_960"]) * 1.5, "%f vs %f" % [_mean(shots["noon_960"]), _mean(shots["night_960"])])
	check("gpu.morning_differs_from_evening", _diff(shots["morning_640"], shots["evening_640"]) > 3000, "diff=%d" % _diff(shots["morning_640"], shots["evening_640"]))
	# ---- sprite shadow at day and at night (player zoom)
	for res_index: int in 2:
		main.set_resolution(res_index, Vector2i(1920, 1080))
		for pair: Array in [["noon", 12.0], ["night", 0.0]]:
			set_hour(float(pair[1]))
			var image: Image = await _grab()
			var foot: Vector2 = main.camera.unproject_position(main.player_ground3())
			var snap: Dictionary = main.actor.snapshot()
			check("gpu.sprite_shadow_synced_%s_%d" % [pair[0], Config.RESOLUTIONS[res_index].x], bool(snap["matching_texture"]) and bool(snap["matching_feet"]) and absf(Vector3(main.actor.shadow_board.global_basis.z.x, 0, main.actor.shadow_board.global_basis.z.z).normalized().dot(Vector3(main.sun.global_basis.z.x, 0, main.sun.global_basis.z.z).normalized()) - 1.0) < 0.001, "light_toward=%s" % str(main.sun.global_basis.z))
			_zoom(image, foot, Vector2i(96, 54), 6 if res_index == 0 else 4, "player_%s_%d_zoom.png" % [pair[0], Config.RESOLUTIONS[res_index].x])
	# ---- wall vegetation (noon, both resolutions), grown wall vs no vegetation
	for res_index: int in 2:
		main.set_resolution(res_index, Vector2i(1920, 1080))
		set_hour(12.0)
		var with_wall: Image = await _grab()
		main.wall_view.visible = false
		var without_wall: Image = await _grab()
		main.wall_view.visible = true
		var res_x: int = Config.RESOLUTIONS[res_index].x
		var centre: Vector2 = screen_of(mill_cell)
		_zoom(with_wall, centre + Vector2(0, -20 * (res_x / 640)), Vector2i(160, 90) * res_x / 640, 5 if res_index == 0 else 3, "wall_mill_%d_zoom.png" % res_x)
		check("gpu.wall_vegetation_visible_%d" % res_x, _diff(with_wall, without_wall) > 400, "diff=%d" % _diff(with_wall, without_wall))
	# ---- ground cover and pavement (noon 640)
	main.set_resolution(0, Vector2i(1920, 1080))
	set_hour(12.0)
	var covered: Image = await _grab()
	main.play_view.ground.visible = false
	var bare: Image = await _grab()
	main.play_view.ground.visible = true
	_save(covered, "scene_ground_cover_on_640.png")
	_save(bare, "scene_ground_cover_off_640.png")
	check("gpu.ground_cover_visible", _diff(covered, bare) > 3000, "diff=%d" % _diff(covered, bare))
	var paved_cell: Vector2i = Vector2i(20, 10)
	check("gpu.fixture_has_pavement", s.state.terrain[s.state.index_of(paved_cell.x, paved_cell.y)] == s.T_PAVED)
	_zoom(covered, screen_of(paved_cell), Vector2i(160, 90), 5, "pavement_cracks_640_zoom.png")
	_zoom(covered, screen_of(Vector2i(24, 17)), Vector2i(160, 90), 5, "soil_carpet_640_zoom.png")
	# ---- water: reflection (noon) and receiving the sun's shadow (morning), both resolutions
	for res_index: int in 2:
		main.set_resolution(res_index, Vector2i(1920, 1080))
		var res_x: int = Config.RESOLUTIONS[res_index].x
		var factor: int = res_x / 640
		set_hour(12.0)
		var water_on: Image = await _grab()
		main.water_view.set_reflection(false)
		var water_off: Image = await _grab()
		main.water_view.set_reflection(true)
		_zoom(water_on, screen_of(pond_cell), Vector2i(120, 68) * factor, 6 if res_index == 0 else 4, "water_reflection_%d_zoom.png" % res_x)
		_zoom(water_off, screen_of(pond_cell), Vector2i(120, 68) * factor, 6 if res_index == 0 else 4, "water_no_reflection_%d_zoom.png" % res_x)
		check("gpu.water_reflection_%d" % res_x, _diff(water_on, water_off) > 200, "diff=%d reflection viewport=%s" % [_diff(water_on, water_off), str(main.water_view.reflection_view.size)])
		set_hour(8.0)
		var shadow_on: Image = await _grab()
		main.water_view.material_.set_shader_parameter("receive_shadow", false)
		var shadow_off: Image = await _grab()
		main.water_view.material_.set_shader_parameter("receive_shadow", true)
		_zoom(shadow_on, screen_of(pond_cell), Vector2i(120, 68) * factor, 6 if res_index == 0 else 4, "water_shadow_%d_zoom.png" % res_x)
		_save(shadow_on, "scene_water_shadow_%d.png" % res_x)
		check("gpu.water_receives_shadow_%d" % res_x, _diff(shadow_on, shadow_off) > 50, "diff=%d" % _diff(shadow_on, shadow_off))
	main.queue_free()
	await _frames(2)

func _scene_b() -> void:
	await _open(false)
	_stage_ground(Vector2i(24, 17))
	var s: RefCounted = main.session
	check("gpu.chapel_vegetation_grew", s.wall_growth.entry_of("chapel_01").has("roots") and s.wall_growth.total_progress() > 1.0, "progress sum=%f" % s.wall_growth.total_progress())
	for res_index: int in 2:
		main.set_resolution(res_index, Vector2i(1920, 1080))
		set_hour(12.0)
		var with_wall: Image = await _grab()
		main.wall_view.visible = false
		var without_wall: Image = await _grab()
		main.wall_view.visible = true
		var res_x: int = Config.RESOLUTIONS[res_index].x
		_save(with_wall, "scene_chapel_noon_%d.png" % res_x)
		_zoom(with_wall, screen_of(Vector2i(18, 9)) + Vector2(0, 10 * (res_x / 640)), Vector2i(200, 112) * res_x / 640, 4 if res_index == 0 else 3, "wall_chapel_%d_zoom.png" % res_x)
		check("gpu.chapel_wall_visible_%d" % res_x, _diff(with_wall, without_wall) > 400, "diff=%d" % _diff(with_wall, without_wall))
	main.queue_free()
	await _frames(2)
