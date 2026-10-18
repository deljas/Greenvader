extends SceneTree
## Captures the title and the pause menu of PocMain at 960x540 (GPU window, never focused). Own save namespace only.
const DIR: String = "user://poc_saves_indep/"
func _init() -> void:
	_run.call_deferred()
func _run() -> void:
	root.unfocusable = true
	DirAccess.make_dir_recursive_absolute(DIR)
	var main: Node = (load("res://scenes/poc.tscn") as PackedScene).instantiate()
	main.set_meta(&"poc_town", true)
	main.save_dir = DIR
	main.auto_process = false
	root.add_child(main)
	for i: int in 5:
		await process_frame
	main.window_size_override = Vector2i(1920, 1080)
	main.set_resolution(1)
	main.session.advance_game(10.0)
	main.tick(0.016, Vector2.ZERO)
	main.open_title()
	for i: int in 6:
		await process_frame
	root.get_texture().get_image().save_png("res://evidence/poc/08/independent/title_960.png")
	main.close_menu()
	main.open_help()
	for i: int in 6:
		await process_frame
	root.get_texture().get_image().save_png("res://evidence/poc/08/independent/help_960.png")
	main._help_back()
	main.close_menu()
	main.session.state.greened_count = main.session.state.target_count - 1
	main.tick(0.016, Vector2.ZERO)
	for i: int in 6:
		await process_frame
	root.get_texture().get_image().save_png("res://evidence/poc/08/independent/hud_99_960.png")
	print("DONE size=", root.get_texture().get_size())
	for f: String in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR + f)
	quit(0)
