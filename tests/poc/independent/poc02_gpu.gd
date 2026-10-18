extends SceneTree
## Capture 960x540 of the placed block. GPU window only (not --headless). No OS input.
const Coords: GDScript = preload("res://scripts/poc/poc_coords.gd")
func _init() -> void:
	root.unfocusable = true
	_run.call_deferred()
func _frames(n: int) -> void:
	for i in n:
		await process_frame
	await RenderingServer.frame_post_draw
func _run() -> void:
	if DisplayServer.get_name() == "headless":
		print("NOT_RUN gpu")
		quit(2)
		return
	var main: Node = load("res://scenes/poc.tscn").instantiate()
	root.add_child(main)
	main.auto_process = false
	main.window_size_override = Vector2i(1920, 1080)
	await _frames(2)
	print("renderer=", RenderingServer.get_video_adapter_name(), " display=", DisplayServer.get_name())
	main.set_resolution(1, Vector2i(1920, 1080))
	main.session.position = Coords.cell_center_logic(Vector2i(24, 20))
	main.tick(0.0, Vector2.ZERO)
	await _frames(4)
	var img: Image = main.render_view.get_texture().get_image()
	print("size=", img.get_size())
	var colors: Dictionary = {}
	for y in range(0, img.get_height(), 4):
		for x in range(0, img.get_width(), 4):
			colors[img.get_pixel(x, y).to_html()] = true
	print("colors=", colors.size(), " holders=", main.placement_view.holders.size())
	img.save_png(ProjectSettings.globalize_path("res://evidence/poc/02/independent/render_960.png"))
	quit(0)
