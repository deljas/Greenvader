extends SceneTree
## One focus-safe GPU title check; the normal scene must not import old progress.
const OUT: String = "res://evidence/poc3/save_base/self/"

func _init() -> void:
	root.unfocusable = true
	call_deferred("run")

func run() -> void:
	# The engine initializes the native root window after SceneTree._init.
	root.unfocusable = true
	var entry: String = ProjectSettings.get_setting("application/run/main_scene", "")
	change_scene_to_file(entry)
	for index: int in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var main: Node = current_scene
	main.auto_process = false
	var label: Label = main.ui.menu.get_child(0).get_child(0)
	var passed: bool = root.unfocusable and root.title == "グリーンベーダー｜PoC3 作業版" and label.text == "グリーンベーダー PoC3 作業版" and main.menu == "title" and main.session.paused and main.session.seeds == 60 and main.save_dir == "user://poc3_saves"
	var image_error: Error = root.get_texture().get_image().save_png(OUT + "title.png")
	var result: Dictionary = {"status": "PASS" if passed and image_error == OK else "FAIL", "window_title": root.title, "ui_title": label.text, "seed_count": main.session.seeds, "save_dir": main.save_dir, "root_unfocusable": root.unfocusable, "entry": entry, "old_fixture_not_loaded": main.session.seeds != 987}
	var file: FileAccess = FileAccess.open(OUT + "title_result.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "  "))
	file.close()
	print(result)
	main.session.close()
	quit(0 if passed and image_error == OK else 1)
