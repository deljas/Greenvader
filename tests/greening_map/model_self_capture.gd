extends SceneTree
const Scene: PackedScene = preload("res://scenes/greening_map.tscn")
const Session: GDScript = preload("res://scripts/greening_map/session.gd")
const OUT: String = "res://evidence/building-model/self/"
var lab: Node
var checks: Array[Dictionary] = []
var raw: Array[Dictionary] = []
var failures: int = 0

func _initialize() -> void:
	root.unfocusable = true
	create_timer(80).timeout.connect(func() -> void: quit(99))
	run.call_deferred()

func check(ok: bool, id: String, detail: String = "") -> void:
	checks.append({"id":id,"status":"PASS" if ok else "FAIL","detail":detail})
	if not ok:
		failures += 1
	print(checks[-1])

func capture(label_: String, representative: bool = false) -> Image:
	await lab.wait_render()
	var image_: Image = lab.render_view.get_texture().get_image()
	image_.save_png(OUT+label_+"_640.png")
	var ui: Image = root.get_texture().get_image()
	ui.resize(1920,1080,Image.INTERPOLATE_NEAREST)
	ui.save_png(OUT+label_+"_ui_1920.png")
	if representative:
		var output: Image = lab.doubled_view.get_texture().get_image()
		output.save_png(OUT+label_+"_1920.png")
		var expected: Image = image_.duplicate()
		expected.resize(1920,1080,Image.INTERPOLATE_NEAREST)
		check(expected.get_data()==output.get_data(),"nearest3_exact")
	var state: Dictionary = lab.wall_growth.snapshot()
	state["label"] = label_
	state["clock"] = lab.session.clock.elapsed
	state["elevation"] = lab.sun_elevation
	state["azimuth"] = lab.sun_azimuth
	raw.append(state)
	print("IMAGE "+ProjectSettings.globalize_path(OUT+label_+"_ui_1920.png"))
	return image_

func changed(a: Image, b: Image) -> int:
	var count: int = 0
	for y: int in a.get_height():
		for x: int in a.get_width():
			if a.get_pixel(x,y)!=b.get_pixel(x,y):
				count += 1
	return count

func run() -> void:
	lab = Scene.instantiate()
	lab.automatic = false
	root.add_child(lab)
	if DisplayServer.get_name()=="headless" or RenderingServer.get_video_adapter_name().is_empty():
		print("GPU NOT_RUN")
		quit(2)
		return
	lab.session.spread.allow_hook = func(_index: int) -> bool: return false
	await capture("model_initial",true)
	# Only the fixed root/patch neighborhoods are made mature, then the real clock advances.
	for entry: Dictionary in lab.wall_growth.entries:
		for group: Array in [entry["roots"],entry["moss"]]:
			for item: Dictionary in group:
				for index: int in item["cells"]:
					lab.session.state.set_stage(index,WorldState.STAGE_MATURE)
					lab.session.state.growth[index] = 120000
	lab.ground_view.refresh(lab.session.state)
	var counter: Vector2i = Vector2i(lab.session.state.greened_count,lab.session.state.target_count)
	lab.session.advance_game(45)
	lab.update_hud()
	await capture("model_growth45")
	lab.session.advance_game(90)
	lab.update_hud()
	var maximum: Image = await capture("model_growth135")
	var full: bool = true
	for entry: Dictionary in lab.wall_growth.entries:
		for root_: Dictionary in entry["roots"]:
			full = full and is_equal_approx(root_["progress"],1)
	check(full and counter==Vector2i(lab.session.state.greened_count,lab.session.state.target_count),"maximum_root_one_counter_invariant")
	lab.ground_view.pavement_cracks.hide()
	var pavement_off: Image = await capture("pavement_cracks_OFF")
	check(changed(maximum,pavement_off)>8,"pavement_cracks_actual_pixels",str(changed(maximum,pavement_off)))
	lab.ground_view.pavement_cracks.show()
	lab.pause_check.button_pressed = true
	var before: String = str(lab.wall_growth.snapshot())
	# Keep the known pond-shore sprite pose; camera, reflections and caster update through product code.
	lab.session.position = Session.to_logic(Vector2(-7.9,3.5))
	lab.azimuth_slider.value = 225
	lab.elevation_slider.value = 15
	var low: Image = await capture("elevation15")
	lab.elevation_number.value = 80
	var high: Image = await capture("elevation80")
	check(changed(low,high)>100 and lab.elevation_slider.value==80 and lab.elevation_number.value==80 and before==str(lab.wall_growth.snapshot()),"elevation_UI_real_shadow_no_growth")
	lab.elevation_number.value = 52
	lab.azimuth_number.value = 320
	var target: Vector3 = Vector3(-3.2,1.2,-2.0)
	lab.camera.size = 9.0
	lab.camera.position = target+Vector3(22,22*sqrt(2.0/3.0),22)
	lab.camera.look_at(target)
	var on: Image = await capture("A_window_cracks_closeup")
	for entry: Dictionary in lab.wall_growth.entries:
		entry["cracks"].hide()
	var off: Image = await capture("A_wall_cracks_OFF")
	check(changed(on,off)>4,"wall_cracks_independent_GPU_pixels",str(changed(on,off)))
	FileAccess.open(OUT+"gpu-results.json",FileAccess.WRITE).store_string(JSON.stringify({"adapter":RenderingServer.get_video_adapter_name(),"results":checks,"failures":failures},"\t"))
	FileAccess.open(OUT+"gpu-raw.json",FileAccess.WRITE).store_string(JSON.stringify(raw,"\t"))
	lab.free()
	await process_frame
	quit(0 if failures==0 else 1)
