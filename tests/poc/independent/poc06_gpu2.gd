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
	main.set_resolution(0, Vector2i(1920, 1080))
	set_hour(12.0)
	place(behind)
	main.actor.visible = false
	var on_ns: Image = await grab()
	var sh: Array = main.placement_view.find_children("OccShadow*", "MeshInstance3D", true, false)
	for n: Node in sh:
		(n as MeshInstance3D).visible = false
	var on_noshadow: Image = await grab()
	for n: Node in sh:
		(n as MeshInstance3D).visible = true
	ov.set_enabled(false)
	main.tick(0.0, Vector2.ZERO)
	var off_ns: Image = await grab()
	var lo: Vector2 = Vector2(1e9, 1e9)
	var hi: Vector2 = Vector2(-1e9, -1e9)
	for child: Node in main.placement_view.holders["mill_01"].find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = child as MeshInstance3D
		var box: AABB = mi.global_transform * mi.get_aabb()
		for i: int in 8:
			var p: Vector2 = main.camera.unproject_position(box.get_endpoint(i))
			lo = lo.min(p)
			hi = hi.max(p)
	var mr: Rect2i = Rect2i(Vector2i(lo) - Vector2i(4, 4), Vector2i(hi - lo) + Vector2i(8, 8))
	var full: Rect2i = Rect2i(Vector2i.ZERO, on_ns.get_size())
	var outside_on_off: int = diff_in(on_ns, off_ns, full) - diff_in(on_ns, off_ns, mr)
	var outside_shadowcopy: int = diff_in(on_ns, on_noshadow, full) - diff_in(on_ns, on_noshadow, mr)
	print("inside rect: shadowcopy px=", diff_in(on_ns, on_noshadow, mr), " on-vs-off px=", diff_in(on_ns, off_ns, mr))
	print("shadow: shadow copies=", sh.size(), " px diff outside mill rect on-vs-off=", outside_on_off, " ; without shadow copies vs with (outside)=", outside_shadowcopy, " mill rect=", mr)
	on_noshadow.save_png(ProjectSettings.globalize_path(OUT + "noon_640_shadowcopies_hidden.png"))
	on_ns.save_png(ProjectSettings.globalize_path(OUT + "noon_640_on_nosprite.png"))
	off_ns.save_png(ProjectSettings.globalize_path(OUT + "noon_640_off_nosprite.png"))
	main.queue_free()
	await frames(2)
	quit(0)
