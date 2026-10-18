extends SceneTree
## WTH-01 GPU captures (real renderer, NOT --headless): godot --path <repo> --script res://tests/poc/weather/gpu.gd
## No OS-level input / cursor / foregrounding (root.unfocusable). Town session; the clock is moved to the time of each picture and
## the game ticks a little so the weather settles. Images -> evidence/weather/01/*.png (full 3D view = SubViewport texture) and
## *_zoom.png (player crop x4, nearest). Objective checks compare the same frame with a layer hidden (rain overlay, cloud shadow,
## player, enemy, seeds) to prove the aids change the picture only locally and that the actors still differ from the ground.
const Config: GDScript = preload("res://scripts/poc/poc_config.gd")
const Coords: GDScript = preload("res://scripts/poc/poc_coords.gd")
const Weather: GDScript = preload("res://scripts/poc/environment/poc_weather.gd")
const OUT: String = "res://evidence/weather/01/"
var main: Node
var s: RefCounted
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

func set_time(t: float) -> void:
	s.clock.load_dict({"version": 1, "elapsed": t, "growth_ticks": int(t / s.clock.growth_period), "spread_ticks": int(t / s.clock.spread_period)})
	s.growth.ticks = s.clock.growth_ticks
	s.state.growth_tick = s.clock.growth_ticks
	s.weather.update(t)

func find_time(type: int, offset: float) -> float:
	var w: RefCounted = s.weather
	for k: int in 400:
		var t: float = offset + 600.0 * float(k)
		var index: int = w.index_at(t)
		var segment: Dictionary = w.segments[index]
		if index > 0 and int(segment["type"]) == type and t - float(segment["start"]) >= 30.0 and float(segment["start"]) + float(segment["duration"]) - t >= 60.0:
			return t
	return -1.0

func _v3(v: Vector2) -> Vector3:
	return Vector3(v.x, 0.0, v.y)

func luma(c: Color) -> float:
	return 0.299 * c.r + 0.587 * c.g + 0.114 * c.b

## Fraction of pixels (inside `rect`) whose colour (mean RGB distance) differs by more than `threshold`.
func diff_fraction(a: Image, b: Image, rect: Rect2i, threshold: float = 0.06) -> float:
	var count: int = 0
	for y: int in range(rect.position.y, rect.end.y):
		for x: int in range(rect.position.x, rect.end.x):
			var ca: Color = a.get_pixel(x, y)
			var cb: Color = b.get_pixel(x, y)
			if absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b) > threshold * 3.0:
				count += 1
	return float(count) / float(maxi(rect.size.x * rect.size.y, 1))

func grab() -> Image:
	await _frames(3)
	return main.render_view.get_texture().get_image()

func foot_px(image: Image, ground: Vector3) -> Vector2:
	return main.camera.unproject_position(ground) * (float(image.get_height()) / float(main.render_view.size.y))

func save(image: Image, file: String, zoom_ground: Vector3) -> void:
	image.save_png(ProjectSettings.globalize_path(OUT + file + ".png"))
	var foot: Vector2 = foot_px(image, zoom_ground)
	var size: Vector2i = Vector2i(image.get_width() / 4, image.get_height() / 4)
	var origin: Vector2i = Vector2i(clampi(int(foot.x) - size.x / 2, 0, image.get_width() - size.x), clampi(int(foot.y) - size.y * 2 / 3, 0, image.get_height() - size.y))
	var crop: Image = image.get_region(Rect2i(origin, size))
	crop.resize(size.x * 4, size.y * 4, Image.INTERPOLATE_NEAREST)
	crop.save_png(ProjectSettings.globalize_path(OUT + file + "_zoom.png"))

## weather: -1 = natural schedule at time t; otherwise the debug override (night pictures).
func settle(res_index: int, t: float, override_type: int = -1) -> void:
	main.set_resolution(res_index, Vector2i(1920, 1080))
	s.set_debug_weather(override_type)
	set_time(t)
	# the clock jumped: put the demo seeds / sprouts back (and their growth bookkeeping) so every picture shows the same plants
	for i: int in plant_cells.size():
		var index: int = s.state.index_of(plant_cells[i].x, plant_cells[i].y)
		s.state.set_stage(index, stages[i])
		s.state.growth[index] = 0
		s.state.last_growth_tick[index] = s.state.growth_tick
	for i: int in 20:
		main.tick(0.05, Vector2.ZERO)
	await _frames(2)

func actor_region(image: Image, ground: Vector3, half: Vector2i) -> Rect2i:
	var foot: Vector2 = foot_px(image, ground)
	return Rect2i(clampi(int(foot.x) - half.x, 0, image.get_width() - 2 * half.x), clampi(int(foot.y) - half.y * 2, 0, image.get_height() - 2 * half.y), half.x * 2, half.y * 2)

var fractions: Dictionary = {}
var plant_cells: Array[Vector2i] = []
var stages: Array[int] = [WorldState.STAGE_SEED, WorldState.STAGE_SPROUT1, WorldState.STAGE_SPROUT2]

func readable(name: String, image: Image, res_index: int, ground_player: Vector3, ground_boar: Vector3, ground_seed: Vector3) -> void:
	var scale_: float = float(Config.RESOLUTIONS[res_index].x) / 640.0
	var half: Vector2i = Vector2i(int(12.0 * scale_), int(14.0 * scale_))
	var views: Array = [["player", main.actor, ground_player], ["enemy", main.enemy_view, ground_boar], ["seeds", main.play_view, ground_seed]]
	for entry: Array in views:
		var node: Node = entry[1]
		var was: bool = node.visible
		var marker: Node = main.readability.enemy_marker
		var marker_was: bool = marker.visible
		node.visible = false
		if String(entry[0]) == "enemy":
			marker.visible = false # the enemy's foot marker counts as part of what makes it readable
		var without: Image = await grab()
		node.visible = was
		marker.visible = marker_was
		var region: Rect2i = actor_region(image, entry[2], half)
		var frac: float = diff_fraction(image, without, region)
		fractions[name + "." + String(entry[0])] = frac
		if String(entry[0]) == "player":
			check("%s.player_differs_from_ground" % name, frac >= 0.08, "%.1f%% of %s px differ" % [frac * 100.0, str(region.size)])
		else:
			if String(entry[0]) == "enemy" and name.begins_with("night"):
				check("%s.enemy_with_marker_clearly_differs_from_ground" % name, frac >= 0.08, "%.1f%%" % (frac * 100.0))
			print("INFO ", name, ".", String(entry[0]), " differs from the ground in ", snappedf(frac * 100.0, 0.1), "% of ", region.size, " px")

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		print("NOT_RUN gpu (headless display server)")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	print("renderer=", RenderingServer.get_video_adapter_name(), " window=", root.size)
	main = load("res://scenes/poc.tscn").instantiate()
	main.set_meta(&"poc_town", true)
	root.add_child(main)
	main.auto_process = false
	main.window_size_override = Vector2i(1920, 1080)
	await _frames(3)
	s = main.session
	# scene: player on open ground, a boar and a few seeds / sprouts / a seed shot close by
	var cell: Vector2i = Coords.logic_to_cell(s.position)
	var boar: Boar = Boar.new()
	boar.id = 9100
	boar.zone = s.player_zone()
	boar.hp = 3
	boar.pos = s.position + Vector2(14.0, 4.0)
	s.enemies.boars.append(boar)
	for radius: int in range(3, 14):
		for dy: int in range(-radius, radius + 1):
			for dx: int in range(-radius, radius + 1):
				var c: Vector2i = cell + Vector2i(dx, dy)
				if plant_cells.size() < 3 and s.state.in_bounds(c.x, c.y) and s.state.can_plant(s.state.index_of(c.x, c.y)) and (plant_cells.is_empty() or plant_cells[plant_cells.size() - 1].distance_to(c) >= 2.0) and Vector2(dx, dy).length() >= float(radius) - 0.5 and dy >= 0:
					plant_cells.append(c)
	check("plant_cells_found", plant_cells.size() == 3, str(plant_cells))
	for i: int in plant_cells.size():
		s.state.set_stage(s.state.index_of(plant_cells[i].x, plant_cells[i].y), stages[i])
	s.play.seeds = 9
	var t_clear: float = find_time(Weather.CLEAR, 100.0)
	var t_cloudy: float = find_time(Weather.CLOUDY, 100.0)
	var t_rain: float = find_time(Weather.RAIN, 100.0)
	check("times_found", t_clear >= 0.0 and t_cloudy >= 0.0 and t_rain >= 0.0, "%s %s %s" % [t_clear, t_cloudy, t_rain])
	var g_player: Vector3 = Vector3.ZERO
	var g_boar: Vector3 = Vector3.ZERO
	var g_seed: Vector3 = Vector3.ZERO
	var plan: Array = [
		["day_clear_640", 0, t_clear, -1],
		["day_cloudy_640", 0, t_cloudy, -1],
		["day_rain_640", 0, t_rain, -1],
		["day_rain_960", 1, t_rain, -1],
		["night_clear_640", 0, 400.0, 0],
		["night_rain_640", 0, 400.0, 2],
		["night_rain_960", 1, 400.0, 2],
	]
	for entry: Array in plan:
		var name: String = String(entry[0])
		await settle(int(entry[1]), float(entry[2]), int(entry[3]))
		s.fire(false, s.position + Vector2(-30.0, 18.0))
		main.tick(0.02, Vector2.ZERO)
		g_player = main.actor.render_foot
		g_boar = _v3(Coords.logic_to_ground(boar.pos))
		g_seed = _v3(Coords.logic_to_ground((Vector2(plant_cells[1]) + Vector2(0.5, 0.5)) * float(Config.TILE_PX)))
		var image: Image = await grab()
		save(image, name, g_player)
		if name != "day_cloudy_640":
			var boar_crop: Image = image.get_region(Rect2i(clampi(int(foot_px(image, g_boar).x) - 40, 0, image.get_width() - 80), clampi(int(foot_px(image, g_boar).y) - 50, 0, image.get_height() - 80), 80, 80))
			boar_crop.resize(320, 320, Image.INTERPOLATE_NEAREST)
			boar_crop.save_png(ProjectSettings.globalize_path(OUT + name + "_boar_zoom.png"))
			var seed_px: Vector2 = foot_px(image, g_seed)
			var seed_crop: Image = image.get_region(Rect2i(clampi(int(seed_px.x) - 40, 0, image.get_width() - 80), clampi(int(seed_px.y) - 50, 0, image.get_height() - 80), 80, 80))
			seed_crop.resize(320, 320, Image.INTERPOLATE_NEAREST)
			seed_crop.save_png(ProjectSettings.globalize_path(OUT + name + "_seed_zoom.png"))
		print("INFO ", name, " weather=", s.weather_text(), " levels=", main.env_view.last_weather, " hour=", snappedf(s.day_hour(), 0.01), " sun=", snappedf(s.sunlight_factor(), 0.001), " light=", snappedf(main.sun.light_energy, 0.001), " ambient=", snappedf(main.world_environment.ambient_light_energy, 0.001))
		if name != "day_cloudy_640":
			await readable(name, image, int(entry[1]), g_player, g_boar, g_seed)
		if name.contains("rain"):
			main.rain_rect.visible = false
			var dry: Image = await grab()
			main.rain_rect.visible = true
			var frac: float = diff_fraction(image, dry, Rect2i(0, 0, image.get_width(), image.get_height()), 0.02)
			check(name + ".rain_streaks_local_not_a_full_screen_effect", frac > 0.003 and frac < 0.2, "%.2f%% of pixels touched" % (frac * 100.0))
		else:
			check(name + ".no_rain_overlay", not main.rain_rect.visible)
	# enemy / seeds: rain must not make them much harder to read than the same time of day without rain
	for pair: Array in [["day_clear_640", "day_rain_640"], ["night_clear_640", "night_rain_640"]]:
		# natural seeds / sprouts are small ground-cover tufts: judged only at night here (by eye in the day pictures)
		for kind: String in (["enemy", "seeds"] if String(pair[0]).begins_with("night") else ["enemy"]):
			var base: float = float(fractions[String(pair[0]) + "." + kind])
			var wet: float = float(fractions[String(pair[1]) + "." + kind])
			check("%s.%s_not_much_worse_than_%s" % [pair[1], kind, pair[0]], wet >= base * 0.3 - 0.005, "%.1f%% vs %.1f%% without rain" % [wet * 100.0, base * 100.0])
	# cloud shadows: the same clear noon at two times; patches move; hidden quad shows they are an overlay and not in the terrain
	await settle(0, t_clear, -1)
	var a: Image = await grab()
	save(a, "cloudshadow_a_640", main.actor.render_foot)
	var with_shadow: Image = a
	main.weather_view.cloud_mesh.visible = false
	var no_shadow: Image = await grab()
	main.weather_view.cloud_mesh.visible = true
	var shadowed: float = diff_fraction(with_shadow, no_shadow, Rect2i(0, 0, a.get_width(), a.get_height()), 0.03)
	no_shadow.save_png(ProjectSettings.globalize_path(OUT + "cloudshadow_off_640.png"))
	check("cloudshadow.dark_patches_cover_part_of_the_ground", shadowed > 0.03 and shadowed < 0.7, "%.1f%% of the picture" % (shadowed * 100.0))
	set_time(t_clear + 24.0)
	for i: int in 10:
		main.tick(0.05, Vector2.ZERO)
	var b: Image = await grab()
	save(b, "cloudshadow_b_640", main.actor.render_foot)
	var moved: float = diff_fraction(a, b, Rect2i(0, 0, a.get_width(), a.get_height()), 0.03)
	check("cloudshadow.patches_move_with_the_game_clock", moved > 0.02, "%.1f%% differ after 24 s" % (moved * 100.0))
	# water: rain ripples vs a clear day, at the pond
	var bank: Vector2 = Coords.cell_center_ground(Vector2i(44, 55))
	var pond: Vector2 = Coords.cell_center_ground(Vector2i(54, 55))
	s.position = Coords.ground_to_logic(bank)
	var water_images: Dictionary = {}
	for pair: Array in [["water_clear_640", t_clear], ["water_rain_640", t_rain]]:
		await settle(0, float(pair[1]), -1)
		var img: Image = await grab()
		save(img, String(pair[0]), Vector3(pond.x, 0.0, pond.y))
		water_images[pair[0]] = img
	var with_ripples: Image = water_images["water_rain_640"]
	main.water_view.material_.set_shader_parameter("rain_level", 0.0)
	var no_ripples: Image = await grab()
	var pond_px: Vector2 = foot_px(with_ripples, Vector3(pond.x, 0.0, pond.y))
	var pond_rect: Rect2i = Rect2i(clampi(int(pond_px.x) - 60, 0, 520), clampi(int(pond_px.y) - 40, 0, 280), 120, 80)
	var wd: float = diff_fraction(with_ripples, no_ripples, pond_rect, 0.03)
	check("water.rain_ripples_change_the_pond_surface", wd > 0.005, "%.2f%% of the pond window differ" % (wd * 100.0))
	print("RESULT passes=%d failures=%d" % [passes, failures])
	quit(1 if failures > 0 else 0)
