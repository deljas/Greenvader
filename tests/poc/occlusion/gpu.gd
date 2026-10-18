extends SceneTree
## POC-06 GPU capture checks (real renderer, NOT --headless):
## godot --path <repo> --script res://tests/poc/occlusion/gpu.gd
## No OS-level input / cursor movement; the window is marked unfocusable. Images go to evidence/poc/06/.
## FIXTURE STAGING (not play): the default placement fixture, ground matured and game time fast-forwarded so the wall
## vegetation really grows; the player is put (display position only) on a walkable cell behind the mill (mill_01 has vegetation).
const Config: GDScript = preload("res://scripts/poc/poc_config.gd")
const Coords: GDScript = preload("res://scripts/poc/poc_coords.gd")
const OUT: String = "res://evidence/poc/06/"
const PLAYER_CELL: Vector2i = Vector2i(7, 20)

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

## Count of differing pixels; `outside` (optional) excludes that rect.
func _diff(a: Image, b: Image, exclude: Rect2i = Rect2i()) -> int:
	var count: int = 0
	for y: int in a.get_height():
		for x: int in a.get_width():
			if exclude.has_point(Vector2i(x, y)):
				continue
			if a.get_pixel(x, y) != b.get_pixel(x, y):
				count += 1
	return count

func _diff_in(a: Image, b: Image, rect: Rect2i) -> int:
	var count: int = 0
	for y: int in range(rect.position.y, rect.end.y):
		for x: int in range(rect.position.x, rect.end.x):
			if a.get_pixel(x, y) != b.get_pixel(x, y):
				count += 1
	return count

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

## Screen rect (render pixels) of the holder's world AABB corners.
func _screen_rect(id: String) -> Rect2i:
	var lo: Vector2 = Vector2(1e9, 1e9)
	var hi: Vector2 = Vector2(-1e9, -1e9)
	for child: Node in main.placement_view.holders[id].find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = child as MeshInstance3D
		var box: AABB = mi.global_transform * mi.get_aabb()
		for i: int in 8:
			var p: Vector2 = main.camera.unproject_position(box.get_endpoint(i))
			lo = lo.min(p)
			hi = hi.max(p)
	return Rect2i(Vector2i(lo) - Vector2i(2, 2), Vector2i(hi - lo) + Vector2i(4, 4))

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		print("NOT_RUN gpu (headless display server)")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	print("renderer=", RenderingServer.get_video_adapter_name(), " display=", DisplayServer.get_name(), " window=", root.size)
	main = load("res://scenes/poc.tscn").instantiate()
	root.add_child(main)
	main.auto_process = false
	main.window_size_override = Vector2i(1920, 1080)
	await _frames(3)
	var s: RefCounted = main.session
	for y: int in s.state.height:
		for x: int in s.state.width:
			var i: int = s.state.index_of(x, y)
			if s.state.target[i] != 0:
				s.state.set_stage(i, WorldState.STAGE_MATURE)
	s.position = Coords.cell_center_logic(PLAYER_CELL)
	for i: int in 560:
		s.advance_game(0.25)
		s.position = Coords.cell_center_logic(PLAYER_CELL)
	var ov: Node = main.occlusion_view
	main.tick(0.0, Vector2.ZERO)
	check("gpu.vegetation_grown", s.wall_growth.total_progress() > 1.0, "progress=%f" % s.wall_growth.total_progress())
	check("gpu.player_cell_walkable", s.state.is_walkable(PLAYER_CELL.x, PLAYER_CELL.y))
	_settle()
	check("gpu.occluded_by_mill_only", ov.occlusion.occluded_groups() == PackedStringArray(["mill_01"]), str(ov.occlusion.occluded_groups()))
	var mill_rect_cache: Dictionary = {}
	for res_index: int in 2:
		main.set_resolution(res_index, Vector2i(1920, 1080))
		var res: Vector2i = Config.RESOLUTIONS[res_index]
		var factor: int = res.x / 640
		for pair: Array in [["noon", 12.0], ["night", 0.0]]:
			set_hour(float(pair[1]))
			_settle()
			var tag: String = "%s_%d" % [pair[0], res.x]
			var on: Image = await _grab()
			var mill_rect: Rect2i = _screen_rect("mill_01")
			var player_screen: Vector2 = main.camera.unproject_position(main.player_ground3() + Vector3.UP * 0.7)
			var player_rect: Rect2i = Rect2i(Vector2i(player_screen) - Vector2i(10, 18) * factor, Vector2i(20, 36) * factor)
			# sprite hidden: what remains is the faded building only
			main.actor.visible = false
			var on_no_sprite: Image = await _grab()
			main.actor.visible = true
			# occlusion off (restores the opaque building)
			ov.set_enabled(false)
			main.tick(0.0, Vector2.ZERO)
			var off: Image = await _grab()
			main.actor.visible = false
			var off_no_sprite: Image = await _grab()
			main.actor.visible = true
			ov.set_enabled(true)
			_settle()
			_save(on, "occluded_on_%s.png" % tag)
			_save(off, "occluded_off_%s.png" % tag)
			_zoom(on, player_screen, Vector2i(64, 48) * factor, 10 if factor == 1 else 7, "zoom_on_%s.png" % tag)
			_zoom(off, player_screen, Vector2i(64, 48) * factor, 10 if factor == 1 else 7, "zoom_off_%s.png" % tag)
			_zoom(on_no_sprite, player_screen, Vector2i(64, 48) * factor, 10 if factor == 1 else 7, "zoom_on_no_sprite_%s.png" % tag)
			check("gpu.player_visible_through_faded_%s" % tag, _diff_in(on, on_no_sprite, player_rect) > 60 * factor * factor, "sprite px=%d" % _diff_in(on, on_no_sprite, player_rect))
			check("gpu.player_hidden_without_fade_%s" % tag, _diff_in(off, off_no_sprite, player_rect) < 5, "sprite px=%d (opaque building covers him)" % _diff_in(off, off_no_sprite, player_rect))
			check("gpu.building_changes_%s" % tag, _diff_in(on_no_sprite, off_no_sprite, mill_rect) > 500, "diff=%d" % _diff_in(on_no_sprite, off_no_sprite, mill_rect))
			var margin: Rect2i = mill_rect.grow(3 * factor)
			var outside: int = _diff(on_no_sprite, off_no_sprite, margin)
			check("gpu.outside_building_unchanged_%s" % tag, outside < 40 * factor * factor, "outside px diff=%d (ground, shadow, water, other objects)" % outside)
			mill_rect_cache[tag] = mill_rect
	# ---- shadow and reflection copies matter (noon, 640)
	main.set_resolution(0, Vector2i(1920, 1080))
	set_hour(12.0)
	_settle()
	var with_copies: Image = await _grab()
	var reflect_with: Image = main.water_view.reflection_view.get_texture().get_image()
	var shadow_nodes: Array = main.placement_view.find_children("OccShadow*", "MeshInstance3D", true, false)
	var reflect_nodes: Array = main.placement_view.find_children("OccReflect*", "MeshInstance3D", true, false)
	for node: Node in shadow_nodes:
		(node as MeshInstance3D).visible = false
	var no_shadow: Image = await _grab()
	for node: Node in shadow_nodes:
		(node as MeshInstance3D).visible = true
	check("gpu.shadow_copy_keeps_ground_shadow", shadow_nodes.size() > 0 and _diff(with_copies, no_shadow) > 150, "shadow copies=%d px diff without them=%d" % [shadow_nodes.size(), _diff(with_copies, no_shadow)])
	_save(no_shadow, "debug_shadow_copy_hidden_640.png")
	for node: Node in reflect_nodes:
		(node as MeshInstance3D).visible = false
	await _frames(3)
	var reflect_without: Image = main.water_view.reflection_view.get_texture().get_image()
	for node: Node in reflect_nodes:
		(node as MeshInstance3D).visible = true
	check("gpu.reflection_copy_keeps_building_in_reflection", reflect_nodes.size() > 0 and _diff(reflect_with, reflect_without) > 100, "reflection px diff without copies=%d" % _diff(reflect_with, reflect_without))
	reflect_with.save_png(ProjectSettings.globalize_path(OUT + "reflection_view_with_copies_640.png"))
	reflect_without.save_png(ProjectSettings.globalize_path(OUT + "reflection_view_without_copies_640.png"))
	# ---- depth variants (picture comparison of the faded mill, noon 960)
	main.set_resolution(1, Vector2i(1920, 1080))
	set_hour(12.0)
	var pv: Node3D = main.placement_view
	var mill_center: Vector2 = main.camera.unproject_position(Vector3(-6.0, 2.0, 4.0))
	for variant: Array in [["always", BaseMaterial3D.TRANSPARENCY_ALPHA, BaseMaterial3D.DEPTH_DRAW_ALWAYS, false], ["pre_pass", BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS, BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY, false], ["opaque_only", BaseMaterial3D.TRANSPARENCY_ALPHA, BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY, false], ["single_layer", BaseMaterial3D.TRANSPARENCY_ALPHA, BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY, true]]:
		ov.set_enabled(false)
		pv.fade_transparency_mode = variant[1]
		pv.fade_depth_draw_mode = variant[2]
		ov.occlusion.tuning["single_layer"] = variant[3]
		ov.set_enabled(true)
		main.tick(0.0, Vector2.ZERO)
		_settle()
		var image: Image = await _grab()
		_zoom(image, mill_center, Vector2i(240, 135), 4, "depth_variant_%s_960.png" % variant[0])
	ov.set_enabled(false)
	pv.fade_transparency_mode = BaseMaterial3D.TRANSPARENCY_ALPHA
	pv.fade_depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY
	ov.occlusion.tuning["single_layer"] = true
	ov.set_enabled(true)
	main.tick(0.0, Vector2.ZERO)
	_settle()
	# ---- walking out in front restores the opaque look (real tick path)
	s.position = Coords.cell_center_logic(Vector2i(24, 38))
	for i: int in 40:
		main.tick(0.05, Vector2.ZERO)
	var restored: Image = await _grab()
	check("gpu.restored_after_leaving", ov.faded_instances().is_empty() and ov.occlusion.occluded_groups().is_empty())
	_save(restored, "restored_open_ground_960.png")
	main.queue_free()
	await _frames(2)
	print("RESULT passes=%d failures=%d" % [passes, failures])
	quit(1 if failures > 0 else 0)
