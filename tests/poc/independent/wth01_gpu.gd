extends SceneTree
## WTH-01 independent GPU capture (real renderer, no OS input; root.unfocusable). Natural schedule only (no debug override).
const Config: GDScript = preload("res://scripts/poc/poc_config.gd")
const Coords: GDScript = preload("res://scripts/poc/poc_coords.gd")
const OUT: String = "res://evidence/weather/01/independent/"
var main: Node
var s: RefCounted

func _init() -> void:
	root.unfocusable = true
	_run.call_deferred()

func frames(n: int) -> void:
	for i: int in n: await process_frame
	await RenderingServer.frame_post_draw

func jump(t: float) -> void:
	s.clock.load_dict({"version": 1, "elapsed": t, "growth_ticks": int(t / s.clock.growth_period), "spread_ticks": int(t / s.clock.spread_period)})
	s.growth.ticks = s.clock.growth_ticks
	s.state.growth_tick = s.clock.growth_ticks
	s.weather.update(t)

func grab() -> Image:
	await frames(3)
	return main.render_view.get_texture().get_image()

func foot(img: Image, g: Vector3) -> Vector2:
	return main.camera.unproject_position(g) * (float(img.get_height()) / float(main.render_view.size.y))

func crop(img: Image, g: Vector3, name: String) -> void:
	var p: Vector2 = foot(img, g)
	var c: Image = img.get_region(Rect2i(clampi(int(p.x) - 40, 0, img.get_width() - 80), clampi(int(p.y) - 50, 0, img.get_height() - 80), 80, 80))
	c.resize(320, 320, Image.INTERPOLATE_NEAREST)
	c.save_png(ProjectSettings.globalize_path(OUT + name + ".png"))

func diff(a: Image, b: Image) -> float:
	var n: int = 0
	for y: int in a.get_height():
		for x: int in a.get_width():
			var ca: Color = a.get_pixel(x, y)
			var cb: Color = b.get_pixel(x, y)
			if absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b) > 0.06: n += 1
	return float(n) / float(a.get_width() * a.get_height())

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		print("NOT_RUN headless"); quit(2); return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	main = load("res://scenes/poc.tscn").instantiate()
	main.set_meta(&"poc_town", true)
	root.add_child(main)
	main.auto_process = false
	main.window_size_override = Vector2i(1920, 1080)
	await frames(3)
	s = main.session
	var cell: Vector2i = Coords.logic_to_cell(s.position)
	var boar: Boar = Boar.new()
	boar.id = 9200
	boar.zone = s.player_zone()
	boar.hp = 3
	boar.pos = s.position + Vector2(-16.0, 6.0)
	s.enemies.boars.append(boar)
	var seed_cell: Vector2i = Vector2i(-1, -1)
	for dx: int in range(2, 8):
		var c: Vector2i = cell + Vector2i(dx, 2)
		if s.state.can_plant(s.state.index_of(c.x, c.y)): seed_cell = c; break
	s.state.set_stage(s.state.index_of(seed_cell.x, seed_cell.y), WorldState.STAGE_SEED)
	main.set_resolution(0, Vector2i(1920, 1080))
	jump(400.0)
	s.state.growth[s.state.index_of(seed_cell.x, seed_cell.y)] = 0
	s.state.last_growth_tick[s.state.index_of(seed_cell.x, seed_cell.y)] = s.state.growth_tick
	for i: int in 20: main.tick(0.05, Vector2.ZERO)
	await frames(2)
	print("weather=", s.weather_text(), " hour=", s.day_hour(), " debug_override=", s.weather.override_type, " levels=", main.env_view.last_weather)
	var img: Image = await grab()
	img.save_png(ProjectSettings.globalize_path(OUT + "night_rain_640.png"))
	var g_boar: Vector3 = Vector3(Coords.logic_to_ground(boar.pos).x, 0, Coords.logic_to_ground(boar.pos).y)
	var gs: Vector2 = Coords.logic_to_ground((Vector2(seed_cell) + Vector2(0.5, 0.5)) * float(Config.TILE_PX))
	crop(img, g_boar, "night_rain_boar_zoom")
	crop(img, Vector3(gs.x, 0, gs.y), "night_rain_seed_zoom")
	crop(img, main.actor.render_foot, "night_rain_player_zoom")
	# rain layer is a local overlay
	main.rain_rect.visible = false
	var dry: Image = await grab()
	main.rain_rect.visible = true
	print("rain_overlay_pixels_changed=", diff(img, dry))
	# without enemy marker / enemy
	var mk: Node = main.readability.enemy_marker
	var mv: bool = mk.visible
	mk.visible = false
	var nomark: Image = await grab()
	mk.visible = mv
	crop(nomark, g_boar, "night_rain_boar_zoom_nomarker")
	# day cloud shadow motion/dynamic
	jump(1300.0)
	for i: int in 20: main.tick(0.05, Vector2.ZERO)
	var a: Image = await grab()
	a.save_png(ProjectSettings.globalize_path(OUT + "day_clear_a.png"))
	jump(1324.0)
	for i: int in 10: main.tick(0.05, Vector2.ZERO)
	var b: Image = await grab()
	b.save_png(ProjectSettings.globalize_path(OUT + "day_clear_b_24s_later.png"))
	print("cloud shadow weather=", s.weather_text(), " strength=", main.weather_view.last_cloud_strength, " moved_fraction=", diff(a, b))
	# check rain shader/canvas has no screen read
	var src: String = FileAccess.get_file_as_string("res://scripts/poc/environment/rain_screen.gdshader") + FileAccess.get_file_as_string("res://scripts/poc/environment/cloud_shadow.gdshader")
	print("shader_screen_texture_use=", src.contains("hint_screen_texture") or src.contains("SCREEN_TEXTURE") or src.contains("SCREEN_UV"))
	quit()
