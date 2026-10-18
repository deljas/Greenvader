extends SceneTree
## POC-02 GPU capture checks (real renderer, NOT --headless):
## godot --path <repo> --script res://tests/poc/assets/gpu.gd
## No OS-level input / cursor movement; the window is marked unfocusable. Images go to evidence/poc/02/.
const Config: GDScript = preload("res://scripts/poc/poc_config.gd")
const Coords: GDScript = preload("res://scripts/poc/poc_coords.gd")
const OUT: String = "res://evidence/poc/02/"

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

func _count_diff_near(a: Image, b: Image, center: Vector2, radius: float) -> int:
	var count: int = 0
	var x0: int = maxi(0, floori(center.x - radius))
	var x1: int = mini(a.get_width() - 1, ceili(center.x + radius))
	var y0: int = maxi(0, floori(center.y - radius))
	var y1: int = mini(a.get_height() - 1, ceili(center.y + radius))
	for y: int in range(y0, y1 + 1):
		for x: int in range(x0, x1 + 1):
			if Vector2(x, y).distance_to(center) <= radius and a.get_pixel(x, y) != b.get_pixel(x, y):
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
	check("gpu.placement_view_built", main.placement_view != null and main.placement_view.holders.size() == main.session.placement.instances.size(), "holders=%d" % main.placement_view.holders.size())
	main.session.position = Coords.cell_center_logic(Vector2i(24, 20))
	main.tick(0.0, Vector2.ZERO)
	var image: Image = await _grab()
	check("gpu.size_640", image.get_size() == Vector2i(640, 360), str(image.get_size()))
	_save(image, "fixture_640.png")
	var colors: Dictionary = {}
	for y: int in range(0, 360, 2):
		for x: int in range(0, 640, 2):
			colors[image.get_pixel(x, y).to_html(false)] = true
	check("gpu.scene_not_flat", colors.size() > 60, "sampled unique colours=%d" % colors.size())
	# Buildings are drawn: each building's projected centre area is not background/ground coloured.
	var placement: RefCounted = main.session.placement
	var drawn: int = 0
	var building_total: int = 0
	var bg: Color = Color("29332f")
	for inst: Dictionary in placement.instances:
		if inst["kind"] != "building":
			continue
		building_total += 1
		var top: Vector2 = main.camera.unproject_position(Vector3(inst["pos"].x, 2.5, inst["pos"].y))
		if top.x >= 0 and top.y >= 0 and top.x < 640 and top.y < 360 and image.get_pixel(int(top.x), int(top.y)).to_html(false) != bg.to_html(false):
			drawn += 1
	check("gpu.buildings_visible", drawn == building_total and building_total >= 3, "%d/%d building centres drawn" % [drawn, building_total])
	main.placement_view.set_overlay(true)
	var overlay_image: Image = await _grab()
	_save(overlay_image, "fixture_640_obstacle_overlay.png")
	var overlay_diff: int = _count_diff_near(image, overlay_image, Vector2(320, 180), 400.0)
	check("gpu.overlay_changes_image", overlay_diff > 500, "differing px=%d" % overlay_diff)
	main.placement_view.set_overlay(false)
	var plain: Image = await _grab()
	check("gpu.overlay_off_restores", _count_diff_near(image, plain, Vector2(320, 180), 400.0) == 0)
	# Per-instance transparency: the two TRE-001 instances share one GLB, only tree_01 is faded.
	main.placement_view.set_instance_alpha("tree_01", 0.25)
	var faded: Image = await _grab()
	_save(faded, "fixture_640_tree_01_faded.png")
	var tree_a: Vector2 = main.camera.unproject_position(Vector3(6.4, 2.6, -1.8))
	var tree_b: Vector2 = main.camera.unproject_position(Vector3(-8.0, 2.6, -0.2))
	var near_a: int = _count_diff_near(image, faded, tree_a, 45.0)
	var near_b: int = _count_diff_near(image, faded, tree_b, 45.0)
	check("gpu.fade_only_tree_01", near_a > 40 and near_b == 0, "tree_01 diff px=%d at %s, tree_02 diff px=%d at %s" % [near_a, tree_a, near_b, tree_b])
	main.placement_view.set_instance_alpha("tree_01", 1.0)
	# Top-down picture of the logical layer (8 px per cell): obstacle red, outer ring grey, water blue, puddle cyan, target green-ish.
	var flat: Image = Image.create(placement.width * 8, placement.height * 8, false, Image.FORMAT_RGB8)
	for y: int in placement.height:
		for x: int in placement.width:
			var i: int = y * placement.width + x
			var c: Color = Color("6b8f4e")
			if placement.obstacle[i] == 1:
				c = Color("d9382a")
			elif placement.state.terrain[i] == placement.building_id:
				c = Color("666666")
			elif not placement.state.is_walkable(x, y):
				c = Color("3a6fd8")
			elif placement.puddle[i] == 1:
				c = Color("5fd0e0")
			elif placement.state.target[i] == 0:
				c = Color("c8c8c8")
			flat.fill_rect(Rect2i(x * 8, y * 8, 8, 8), c)
	_save(flat, "fixture_obstacle_cells_topdown.png")
	main.queue_free()
	await _frames(2)
	print("RESULT passes=%d failures=%d" % [passes, failures])
	quit(1 if failures > 0 else 0)
