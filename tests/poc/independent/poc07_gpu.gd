extends SceneTree
## POC-07 independent: default launch of scenes/poc.tscn as the current scene (no args), first frames. Real renderer, no OS input,
## window unfocusable. Saves evidence/poc/07/independent/first_frame.png
func _init() -> void:
	root.unfocusable = true
	_run.call_deferred()

func _run() -> void:
	change_scene_to_file("res://scenes/poc.tscn")
	for i: int in 3:
		await process_frame
	var main: Node = current_scene
	print("current_scene=", main.name, " has session=", main.get("session") != null)
	for i: int in 12:
		await process_frame
	await RenderingServer.frame_post_draw
	var s: RefCounted = main.get("session")
	print("size=", s.state.width, "x", s.state.height, " combat=", s.combat_mode, " nests=", s.enemies.nests.size(), " pos=", s.position, " instances=", s.placement.instances.size())
	var img: Image = root.get_texture().get_image()
	print("img ", img.get_size())
	img.save_png(ProjectSettings.globalize_path("res://evidence/poc/07/independent/first_frame.png"))
	var rv: Variant = main.get("render_view")
	if rv != null:
		(rv as SubViewport).get_texture().get_image().save_png(ProjectSettings.globalize_path("res://evidence/poc/07/independent/first_frame_render.png"))
	quit()
