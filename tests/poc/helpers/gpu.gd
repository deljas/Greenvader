extends SceneTree
## HLP-01 GPU captures (real renderer, NOT --headless): godot --path <repo> --script res://tests/poc/helpers/gpu.gd
## No OS-level input / cursor / foregrounding (root.unfocusable). Town session; the three helper plants are placed through the
## session API (the same path the click uses). Images -> evidence/helper/01/ : *_640.png / *_960.png = root viewport (game + HUD),
## *_view_zoom.png = the 3D view crop x3 (nearest).
const Config: GDScript = preload("res://scripts/poc/poc_config.gd")
const Coords: GDScript = preload("res://scripts/poc/poc_coords.gd")
const OUT: String = "res://evidence/helper/01/"
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
	var start: Vector2i = Coords.logic_to_cell(s.position)
	var spots: Array[Vector2i] = []
	var first: Vector2i = free_block(start, spots)
	spots.append(first)
	var second: Vector2i = free_block(first + Vector2i(7, 0), spots)
	spots.append(second)
	var third: Vector2i = free_block(first + Vector2i(3, 7), spots)
	spots.append(third)
	var centre_cell: Vector2 = (Vector2(first) + Vector2(second) + Vector2(third)) / 3.0 + Vector2(2, 2)
	s.position = centre_cell * float(Config.TILE_PX)
	h.seeds = 14
	h.max_helpers = 6
	for i: int in 3:
		s.set_aim((Vector2(spots[i]) + Vector2(2, 2)) * float(Config.TILE_PX))
		s.helper_mode = i
		check("place_%d" % i, bool(s.place_helper()["ok"]), String(s.last_message))
	h.plants[1]["hp"] = 3
	# seeds lying on the ground near the player (the ground item is a cyan octahedron; yellow = ordinary seed fruit)
	for k: int in 3:
		h.pickups.append({"x": s.position.x - 22.0 + float(k) * 7.0, "y": s.position.y + 14.0, "age": 0.0})
	s.helper_mode = -1
	s.say("おたすけ植物を3つ設置した")
	var ground_center: Vector2 = Coords.logic_to_ground(s.position)
	await shoot("helpers", 0, ground_center)
	check("cards_and_areas", int(main.helper_view.snapshot()["plants"]) == 3 and int(main.helper_view.snapshot()["areas"]) == 3 and int(main.helper_view.snapshot()["pickups_visible"]) == 3)
	check("shadow_pairs_match", bool(main.helper_view.snapshot()["shadow_pairs_match"]))
	check("texels_28x36_at_640", main.helper_view.snapshot()["texels"] == [28, 36])
	# placement mode: ghost at a valid spot and a rejected one
	var spot: Vector2i = free_block(start + Vector2i(0, -9), spots)
	s.helper_mode = 0
	var spot_logic: Vector2 = (Vector2(spot) + Vector2(2, 2)) * float(Config.TILE_PX)
	var saved_position: Vector2 = s.position
	s.position = spot_logic + Vector2(22.0, 0.0)
	s.set_aim(spot_logic)
	await shoot("ghost_ok", 0, Coords.logic_to_ground(spot_logic))
	var ghost_ok_preview: bool = bool(s.helper_preview().get("ok", false))
	s.position = saved_position
	check("ghost_visible_and_valid_in_range", bool(main.helper_view.snapshot()["ghost_visible"]) and spot.x >= 0 and ghost_ok_preview, str(ghost_ok_preview))
	s.set_aim(s.position)
	await shoot("ghost_blocked", 0, ground_center)
	check("ghost_rejected_on_occupied", not bool(s.helper_preview()["ok"]), String(s.helper_preview()["reason"]))
	s.helper_mode = -1
	main.hud.text = main.hud.text
	await shoot("helpers", 1, ground_center)
	check("texels_42x54_at_960", main.helper_view.snapshot()["texels"] == [42, 54])
	# carried
	s.position = (Vector2(spots[0]) + Vector2(2, 2)) * float(Config.TILE_PX) + Vector2(10, 0)
	s.lift_helper()
	s.helper_mode = 0
	main.set_resolution(0, Vector2i(1920, 1080))
	await shoot("carried", 0, ground_center)
	check("carried_hud", main.hud.text.contains("持ち上げ中") and main.hud.text.contains("おたすけたね"), main.hud.text.get_slice("\n", 3))
	print("RESULT passes=%d failures=%d" % [passes, failures])
	quit(1 if failures > 0 else 0)
