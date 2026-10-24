extends "res://tests/poc2/view/view_followup.gd"
## The previous wheel fixture omitted viewport-to-window scaling; this checks only that condition.
func run() -> void:
	main=Main.instantiate()
	main.auto_process=false
	root.add_child(main)
	await frames()
	main.ui.map.set_expanded(true)
	wheel(main.ui.map.point(main.session.position))
	await frames()
	check("engine_wheel_zoom_window_coordinates",main.ui.map.zoom==2)
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://evidence/poc2/view/07_engine_zoom_corrected_ui.png"))
	var file: FileAccess=FileAccess.open("res://evidence/poc2/view/wheel_checks.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(checks,"  "))
	file.close()
	main.session.close()
	main.queue_free()
	await frames()
	quit(0 if checks[0].status=="PASS" else 1)
