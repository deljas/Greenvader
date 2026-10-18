extends SceneTree
## POC-06 independent GPU capture (no OS input, window unfocusable). Staging: vegetation grown, player teleported (display
## position, harness op) behind the mill (found by search) and in front of it.
const Coords: GDScript = preload("res://scripts/poc/poc_coords.gd")
const OUT: String = "res://evidence/poc/06/independent/"
var main: Node
var s: RefCounted
var ov: Node

func _init() -> void:
	root.unfocusable = true
	_run.call_deferred()

func frames(n: int) -> void:
	for i: int in n:
		await process_frame
	await RenderingServer.frame_post_draw

func grab() -> Image:
	await frames(4)
	return main.render_view.get_texture().get_image()

func place(cell: Vector2i) -> void:
	s.position = Coords.cell_center_logic(cell)
	ov.reset()
	for i: int in 14:
		main.tick(0.05, Vector2.ZERO)

func set_hour(h: float) -> void:
	var el: float = fposmod(h - float(s.env_tuning["start_hour"]), 24.0) / 24.0 * float(s.env_tuning["day_seconds"])
	s.clock.load_dict({"version": 1, "elapsed": el, "growth_ticks": int(el / s.clock.growth_period), "spread_ticks": int(el / s.clock.spread_period)})
	s.growth.ticks = s.clock.growth_ticks
	s.state.growth_tick = s.clock.growth_ticks
	main.tick(0.0, Vector2.ZERO)

func diff_in(a: Image, b: Image, r: Rect2i) -> int:
	var n: int = 0
	r = r.intersection(Rect2i(Vector2i.ZERO, a.get_size()))
	for y: int in range(r.position.y, r.end.y):
		for x: int in range(r.position.x, r.end.x):
			if a.get_pixel(x, y).is_equal_approx(b.get_pixel(x, y)) == false:
				n += 1
	return n

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		print("NOT_RUN headless")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	print("renderer=", RenderingServer.get_video_adapter_name())
	main = (load("res://scenes/poc.tscn") as PackedScene).instantiate()
	root.add_child(main)
	main.auto_process = false
	main.window_size_override = Vector2i(1920, 1080)
	await frames(3)
	s = main.session
	ov = main.occlusion_view
	for y: int in s.state.height:
		for x: int in s.state.width:
			var i: int = s.state.index_of(x, y)
			if s.state.target[i] != 0:
				s.state.set_stage(i, WorldState.STAGE_MATURE)
	for i: int in 560:
		s.advance_game(0.25)
	print("veg progress ", s.wall_growth.total_progress())
	# find a cell where only mill_01 occludes, and an open cell in front of the mill
	var behind: Vector2i = Vector2i(-1, -1)
	for y: int in s.state.height:
		for x: int in s.state.width:
			if behind.x < 0 and s.state.is_walkable(x, y):
				s.position = Coords.cell_center_logic(Vector2i(x, y))
				ov.reset()
				main.tick(0.0, Vector2.ZERO)
				if ov.occlusion.occluded_groups() == PackedStringArray(["mill_01"]):
					behind = Vector2i(x, y)
	print("behind cell ", behind)
	# front: mill at ground (-6,4); the camera is toward +x,+z of it -> try cells nearer the camera
	var front: Vector2i = Vector2i(-1, -1)
	var mill_ground: Vector2 = Vector2(-6.0, 4.0)
	var best: float = 1e9
	for y: int in s.state.height:
		for x: int in s.state.width:
			if s.state.is_walkable(x, y):
				var g: Vector2 = Coords.cell_center_ground(Vector2i(x, y))
				var d: float = g.distance_to(mill_ground + Vector2(5.0, 5.0))
				if d < best:
					s.position = Coords.cell_center_logic(Vector2i(x, y))
					ov.reset()
					main.tick(0.0, Vector2.ZERO)
					if ov.occlusion.occluded_groups().is_empty():
						best = d
						front = Vector2i(x, y)
	print("front cell ", front)
	for cfg: Array in [[0, "noon", 12.0], [1, "night", 0.0]]:
		main.set_resolution(int(cfg[0]), Vector2i(1920, 1080))
		set_hour(float(cfg[2]))
		var tag: String = "%s_%d" % [cfg[1], 640 * (int(cfg[0]) + 1) if int(cfg[0]) == 0 else 960]
		place(behind)
		var on: Image = await grab()
		var psp: Vector2 = main.camera.unproject_position(main.player_ground3() + Vector3.UP * 0.7)
		var fac: int = 1 if int(cfg[0]) == 0 else 1.5
		var prect: Rect2i = Rect2i(Vector2i(psp) - Vector2i(10, 18) * (1 if int(cfg[0]) == 0 else 2), Vector2i(20, 36) * (1 if int(cfg[0]) == 0 else 2))
		main.actor.visible = false
		var on_ns: Image = await grab()
		main.actor.visible = true
		ov.set_enabled(false)
		main.tick(0.0, Vector2.ZERO)
		var off: Image = await grab()
		main.actor.visible = false
		var off_ns: Image = await grab()
		main.actor.visible = true
		ov.set_enabled(true)
		on.save_png(ProjectSettings.globalize_path(OUT + "behind_on_%s.png" % tag))
		off.save_png(ProjectSettings.globalize_path(OUT + "behind_off_%s.png" % tag))
		print(tag, " sprite px visible while faded=", diff_in(on, on_ns, prect), " sprite px with opaque building=", diff_in(off, off_ns, prect), " rect=", prect)
		# whole-image diff on vs off without sprite, excluding region around mill: ground shadow retained?
		var total: int = diff_in(on_ns, off_ns, Rect2i(Vector2i.ZERO, on.get_size()))
		print(tag, " total px differing on/off (no sprite)=", total)
		# front: sprite in front of building drawn normally
		place(front)
		var fr: Image = await grab()
		main.actor.visible = false
		var fr_ns: Image = await grab()
		main.actor.visible = true
		var fsp: Vector2 = main.camera.unproject_position(main.player_ground3() + Vector3.UP * 0.7)
		var frect: Rect2i = Rect2i(Vector2i(fsp) - Vector2i(10, 18) * (1 if int(cfg[0]) == 0 else 2), Vector2i(20, 36) * (1 if int(cfg[0]) == 0 else 2))
		print(tag, " front: faded=", ov.faded_instances(), " sprite px=", diff_in(fr, fr_ns, frect))
		fr.save_png(ProjectSettings.globalize_path(OUT + "front_%s.png" % tag))
		# crop zoom of behind
		var origin: Vector2i = Vector2i(clampi(int(psp.x) - 64 * (1 if int(cfg[0]) == 0 else 2), 0, on.get_width() - 128 * (1 if int(cfg[0]) == 0 else 2)), clampi(int(psp.y) - 48 * (1 if int(cfg[0]) == 0 else 2), 0, on.get_height() - 96 * (1 if int(cfg[0]) == 0 else 2)))
		var crop: Image = on.get_region(Rect2i(origin, Vector2i(128, 96) * (1 if int(cfg[0]) == 0 else 2)))
		crop.resize(crop.get_width() * 4, crop.get_height() * 4, Image.INTERPOLATE_NEAREST)
		crop.save_png(ProjectSettings.globalize_path(OUT + "behind_zoom_%s.png" % tag))
	main.queue_free()
	await frames(2)
	quit(0)
