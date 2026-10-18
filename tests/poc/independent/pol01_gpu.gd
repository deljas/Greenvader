extends SceneTree
## POL-01 independent check 5: own 960x540 night captures (real renderer, unfocusable window, no OS input).
##   godot --path <repo> --script res://tests/poc/independent/pol01_gpu.gd
const Coords: GDScript = preload("res://scripts/poc/poc_coords.gd")
const OUT: String = "res://evidence/poc-polish/01/independent/"

func _init() -> void:
	root.unfocusable = true
	_run.call_deferred()

func shot(main: Node, name: String) -> void:
	for i: int in 8:
		main.tick(0.016, Vector2.ZERO)
		await process_frame
	await RenderingServer.frame_post_draw
	var img: Image = (main.render_view as SubViewport).get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(OUT + name))
	print("saved ", name, " ", img.get_size(), " snapshot ", main.readability.snapshot())

func _run() -> void:
	change_scene_to_file("res://scenes/poc.tscn")
	for i: int in 6:
		await process_frame
	var main: Node = current_scene
	main.auto_process = false
	(main.ui.title_buttons[&"new_game"] as Button).pressed.emit()
	for i: int in 4:
		await process_frame
	print("set_resolution 960: ", main.set_resolution(1, Vector2i(1920, 1080)))
	var s: RefCounted = main.session
	s.advance_game(425.0) # 08:00 -> 01:00
	await shot(main, "own_night_960_start.png")
	# next to a street lamp (lamp_03 at ground (6.4, 18.4)) and then walk under a building roof edge (gallery)
	s.position = Coords.ground_to_logic(Vector2(8.0, 19.6))
	await shot(main, "own_night_960_lamp.png")
	s.position = Coords.ground_to_logic(Vector2(4.4, 6.4)) # just south of the gallery, on the hidden side
	await shot(main, "own_night_960_behind_gallery.png")
	quit()
