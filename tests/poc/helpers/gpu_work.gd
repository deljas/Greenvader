extends SceneTree
## HLP-02 GPU captures (real renderer, NOT --headless): godot --path <repo> --script res://tests/poc/helpers/gpu_work.gd
## No OS-level input / cursor / foregrounding (root.unfocusable). Town session; the three helper plants are placed through the
## session API (the same path the click uses) and left working: Gatlinger flights, Sprinkler pulse, Army unit fighting a boar. Images -> evidence/helper/02/ : *_640.png / *_960.png = root viewport (game + HUD),
## *_view_zoom.png = the 3D view crop x3 (nearest).
const Config: GDScript = preload("res://scripts/poc/poc_config.gd")
const Coords: GDScript = preload("res://scripts/poc/poc_coords.gd")
const OUT: String = "res://evidence/helper/02/"
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

func free_block(near: Vector2i, skip: Array[Vector2i]) -> Vector2i:
	var st: WorldState = s.state
	var best: Vector2i = Vector2i(-1, -1)
	var best_d: int = 1 << 30
	for oy: int in range(1, st.height - 5):
		for ox: int in range(1, st.width - 5):
			var ok: bool = true
			for y: int in range(oy, oy + 4):
				for x: int in range(ox, ox + 4):
					var i: int = st.index_of(x, y)
					ok = ok and st.is_walkable(x, y) and st.target[i] == 1 and st.occupant[i] == 0 and st.stage[i] == WorldState.STAGE_MATURE
			for other: Vector2i in skip:
				ok = ok and (absi(other.x - ox) >= 6 or absi(other.y - oy) >= 6)
			var d: int = absi(ox - near.x) + absi(oy - near.y)
			if ok and d < best_d:
				best_d = d
				best = Vector2i(ox, oy)
	return best

func shoot(name: String, res_index: int, zoom_center: Vector2) -> void:
	main.set_resolution(res_index, Vector2i(1920, 1080))
	for i: int in 8:
		main.tick(0.05, Vector2.ZERO)
	await _frames(4)
	var image: Image = root.get_texture().get_image()
	image.save_png(ProjectSettings.globalize_path(OUT + "%s_%d.png" % [name, Config.RESOLUTIONS[res_index].x]))
	var view: Image = main.render_view.get_texture().get_image()
	var px: Vector2 = main.camera.unproject_position(Vector3(zoom_center.x, 0.0, zoom_center.y))
	var size: Vector2i = Vector2i(view.get_width() / 2, view.get_height() / 2)
	var origin: Vector2i = Vector2i(clampi(int(px.x) - size.x / 2, 0, view.get_width() - size.x), clampi(int(px.y) - size.y / 2, 0, view.get_height() - size.y))
	var crop: Image = view.get_region(Rect2i(origin, size))
	crop.resize(size.x * 3, size.y * 3, Image.INTERPOLATE_NEAREST)
	crop.save_png(ProjectSettings.globalize_path(OUT + "%s_%d_view_zoom.png" % [name, Config.RESOLUTIONS[res_index].x]))
	print("INFO ", name, " ", image.get_width(), "x", image.get_height(), " view=", main.render_view.size, " helper_view=", main.helper_view.snapshot())

func tick_until(cond: Callable, max_steps: int) -> bool:
	for i: int in max_steps:
		main.tick(0.05, Vector2.ZERO)
		if cond.call():
			return true
	return false

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		print("NOT_RUN gpu (headless display server)")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	print("renderer=", RenderingServer.get_video_adapter_name(), " window=", root.size)
	main = load("res://scenes/poc.tscn").instantiate()
	main.set_meta(&"poc_town", true)
	main.auto_process = false
	root.add_child(main)
	main.window_size_override = Vector2i(1920, 1080)
	await _frames(3)
	s = main.session
	var h: RefCounted = s.helpers
	s.enemy_tuning.boar_cap = 0
	s.enemy_tuning.nest_boar_cap = 0
	var start: Vector2i = Coords.logic_to_cell(s.position)
	var spots: Array[Vector2i] = []
	var first: Vector2i = free_block(start, spots)
	spots.append(first)
	var second: Vector2i = free_block(first + Vector2i(8, 0), spots)
	spots.append(second)
	var third: Vector2i = free_block(first + Vector2i(0, 8), spots)
	spots.append(third)
	h.seeds = 14
	var plants: Array[Dictionary] = []
	for i: int in 3:
		var centre: Vector2 = (Vector2(spots[i]) + Vector2(2, 2)) * float(Config.TILE_PX)
		s.position = centre
		s.set_aim(centre)
		s.helper_mode = i
		check("place_%d" % i, bool(s.place_helper()["ok"]), String(s.last_message))
		plants.append(h.plants[h.plants.size() - 1])
	s.helper_mode = -1
	var gat: Dictionary = plants[0]
	var spr: Dictionary = plants[1]
	var army: Dictionary = plants[2]
	# Gatlinger: stocked, shooting onto the wasteland around the patch
	gat["stock"] = 12.0
	gat["timer"] = 0.0
	h.gat["min_mature_cells"] = 1000000.0
	s.position = h.plant_center_px(gat) + Vector2(0.0, 22.0)
	var got_flight: bool = tick_until(func() -> bool: return h.flights.size() >= 2 and float((h.flights[0] as Dictionary)["age"]) > 0.15, 200)
	check("gatlinger_flights_in_air", got_flight and true, "flights=%d" % h.flights.size())
	main.tick(0.01, Vector2.ZERO)
	await shoot("gatlinger_640", 0, Coords.logic_to_ground(h.plant_center_px(gat)))
	check("flights_visible_in_view", int(main.helper_view.snapshot()["flights_visible"]) >= 1, str(main.helper_view.snapshot()))
	# Sprinkler: seeds in range, a pulse just happened
	spr["stock"] = 40.0
	spr["timer"] = 0.0
	var sprc: Vector2 = h.plant_center_px(spr)
	var sown: int = 0
	for y: int in s.state.height:
		for x: int in s.state.width:
			var i: int = s.state.index_of(x, y)
			if sown < 14 and s.state.can_plant(i) and Vector2((x + 0.5) * 4.0, (y + 0.5) * 4.0).distance_to(sprc) <= 24.0:
				s.state.set_stage(i, WorldState.STAGE_SEED)
				sown += 1
	s.position = sprc + Vector2(0.0, 22.0)
	var pulsed: bool = tick_until(func() -> bool: return h.pulse_fx.has(int(spr["uid"])), 120)
	main.tick(0.01, Vector2.ZERO)
	await shoot("sprinkler_640", 0, Coords.logic_to_ground(sprc))
	check("sprinkler_pulse_shown", pulsed and sown > 0 and h.pulses_total >= 1, "sown=%d pulses=%d" % [sown, h.pulses_total])
	# Army: a boar inside the defence radius, the unit has left its post
	var home: Vector2 = h.plant_center_px(army)
	var boar: Boar = Boar.new()
	boar.id = 9300
	boar.zone = 1
	boar.hp = 3
	boar.pos = home + Vector2(26.0, 6.0)
	s.enemies.boars.append(boar)
	s.position = home + Vector2(-8.0, 24.0)
	var fighting: bool = tick_until(func() -> bool: return h.unit_pos(army).distance_to(home) > 12.0, 120)
	main.tick(0.01, Vector2.ZERO)
	var mid: Vector2 = (h.unit_pos(army) + boar.pos) * 0.5
	await shoot("army_640", 0, Coords.logic_to_ground(mid))
	check("army_unit_out_at_boar", fighting and int(main.helper_view.snapshot()["units"]) == 1, "unit offset %.1f hp=%d" % [h.unit_pos(army).distance_to(home), boar.hp])
	await shoot("army_960", 1, Coords.logic_to_ground(mid))
	check("texels_960", main.helper_view.snapshot()["texels"] == [42, 54])
	var killed: bool = tick_until(func() -> bool: return not s.enemies.boars.has(boar), 200)
	check("army_kills_boar_in_game_view", killed and h.kills_total == 1)
	main.set_resolution(0, Vector2i(1920, 1080))
	await shoot("all_640", 0, Coords.logic_to_ground(home))
	check("hud_shows_work_state", main.hud.text.contains("ガトリンガー在庫") and main.hud.text.contains("スプリンクラー"), main.hud.text.get_slice("\n", 3))
	print("RESULT passes=%d failures=%d" % [passes, failures])
	quit(1 if failures > 0 else 0)
