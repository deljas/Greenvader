extends SceneTree
## One noon GPU capture at 640x360; the existing scene/materials stay unchanged.
const Scene: PackedScene = preload("res://scenes/render_study_3d.tscn")
const OUT: String = "res://evidence/render-study-3d/640/"

func _initialize() -> void:
	root.unfocusable = true
	run.call_deferred()

func run() -> void:
	var study: Node = Scene.instantiate()
	root.add_child(study)
	study.render_view.size = Vector2i(640, 360)
	study.set_time(1)
	var device: String = RenderingServer.get_video_adapter_name()
	if DisplayServer.get_name() == "headless" or device.is_empty():
		push_error("NOT_RUN: real GPU required")
		quit(2)
		return
	await study.wait_render()
	var source: Image = study.render_view.get_texture().get_image()
	var output: Image = study.doubled_view.get_texture().get_image()
	var exact: Image = source.duplicate()
	exact.resize(1920, 1080, Image.INTERPOLATE_NEAREST)
	var same: bool = exact.get_data() == output.get_data()
	var sizes_ok: bool = source.get_size() == Vector2i(640,360) and output.get_size() == Vector2i(1920,1080)
	var saved: bool = source.save_png(OUT + "noon_640.png") == OK
	saved = output.save_png(OUT + "noon_640_at_1920.png") == OK and saved
	var result: Dictionary = {"device":device,"renderer":RenderingServer.get_current_rendering_method(),"source_size":source.get_size(),"output_size":output.get_size(),"exact_nearest_3x":same,"saved":saved,"time":"noon","camera_transform":study.camera.transform,"camera_size":study.camera.size,"native":"NOT_RUN; GPU viewport capture only","OS_input":"none"}
	var file: FileAccess = FileAccess.open(OUT + "capture-results.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"\t"))
	file.close()
	print("CAPTURE_DONE sizes_ok=%s exact_nearest_3x=%s saved=%s device=%s" % [sizes_ok,same,saved,device])
	quit(0 if sizes_ok and same and saved else 1)
