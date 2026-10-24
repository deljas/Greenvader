extends SceneTree
const Scene: PackedScene = preload("res://scenes/asset_showcase.tscn")
const OUT: String = "res://evidence/asset-showcase/self/"
var lab: Node
var results: Array[Dictionary] = []
var failures: int = 0

func _initialize() -> void:
	root.unfocusable = true
	create_timer(90).timeout.connect(func() -> void: quit(99))
	run.call_deferred()

func check(ok: bool, label: String, detail: String = "") -> void:
	results.append({"id":label,"status":"PASS" if ok else "FAIL","detail":detail})
	if not ok: failures += 1
	print(results[-1])

func capture(label: String) -> Image:
	await lab.wait_render()
	var image_: Image = lab.render_view.get_texture().get_image()
	image_.save_png(OUT+label+"_640.png")
	var ui: Image = root.get_texture().get_image()
	ui.resize(1920,1080,Image.INTERPOLATE_NEAREST)
	ui.save_png(OUT+label+"_ui_1920.png")
	var labels: Array[Dictionary] = []
	for i: int in range(lab.category_index*4,lab.category_index*4+4):
		labels.append({"id":lab.id_labels[i].text,"visible":lab.id_labels[i].visible,"position":str(lab.id_labels[i].position)})
	print(label+" labels: "+str(labels))
	return image_

func key_event(code: Key, pressed: bool) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)

func run() -> void:
	lab = Scene.instantiate()
	root.add_child(lab)
	if DisplayServer.get_name()=="headless" or RenderingServer.get_video_adapter_name().is_empty():
		print("GPU NOT_RUN")
		quit(2)
		return
	check(lab.assets.size()==24,"24_models_loaded")
	var state: Array[Dictionary] = []
	for entry: Dictionary in lab.assets:
		var model: Node3D = entry["node"]
		var bounds: AABB = entry["bounds"]
		var mesh_count: int = model.find_children("*","MeshInstance3D",true,false).size()
		check(mesh_count>0 and model.scale.is_equal_approx(Vector3.ONE),entry["id"]+"_mesh_native_scale",str(mesh_count))
		var min_y: float = (model.global_transform*bounds.position).y
		check(min_y>=-0.03,entry["id"]+"_not_below_floor",str(min_y))
		state.append({"id":entry["id"],"mesh_count":mesh_count,"bounds_min":str(bounds.position),"bounds_size":str(bounds.size),"position":str(model.global_position),"rotation":str(model.rotation),"scale":str(model.scale),"contact":entry["contact_type"]})
	for i: int in range(6):
		lab.category_select.item_selected.emit(i)
		check(lab.category_index==i and lab.asset_select.item_count==5,"category_"+str(i)+"_UI")
		await capture(lab.CATEGORIES[i]+"_category")
	# One actual delivered tiny surface is focused through the same UI path.
	lab.category_select.item_selected.emit(2)
	lab.asset_select.item_selected.emit(1)
	check(lab.selected_index==8,"individual_UI_focus")
	await capture("MOS003_individual")
	var expected: Image = lab.render_view.get_texture().get_image()
	expected.resize(1920,1080,Image.INTERPOLATE_NEAREST)
	var displayed: Image = lab.doubled_view.get_texture().get_image()
	check(expected.get_data()==displayed.get_data(),"nearest3_exact")
	key_event(KEY_4,true)
	await process_frame
	key_event(KEY_4,false)
	check(lab.category_index==3,"category_key_internal")
	var before: Vector3 = lab.camera_target
	key_event(KEY_D,true)
	await create_timer(0.12).timeout
	key_event(KEY_D,false)
	await process_frame
	check(lab.camera_target.distance_to(before)>0.01,"camera_input_internal")
	var before_size: float = lab.camera.size
	key_event(KEY_Q,true)
	await process_frame
	key_event(KEY_Q,false)
	check(lab.camera.size<before_size,"zoom_input_internal")
	lab.focus_asset(3)
	var old: Image = await capture("BLD123_sun52")
	lab.azimuth_slider.value = 225
	lab.elevation_slider.value = 15
	var altered: Image = await capture("BLD123_sun15")
	check(lab.sun_azimuth==225 and lab.sun_elevation==15 and old.get_data()!=altered.get_data(),"sun_UI_changes_render")
	check(lab.camera.projection==Camera3D.PROJECTION_ORTHOGONAL and is_equal_approx(lab.camera.rotation_degrees.x,-30),"orthographic_30degree")
	FileAccess.open(OUT+"gpu-results.json",FileAccess.WRITE).store_string(JSON.stringify({"adapter":RenderingServer.get_video_adapter_name(),"head":"99013702eaf36db72a64d60d284680fb834f13c5+uncommitted","results":results,"failures":failures,"NOT_RUN":["physical_keyboard_OS_path","full_angle_performance","water_reflection_growth_collision_integration","user_art_approval"]},"\t"))
	FileAccess.open(OUT+"placements.json",FileAccess.WRITE).store_string(JSON.stringify(state,"\t"))
	lab.free()
	await process_frame
	quit(0 if failures==0 else 1)
