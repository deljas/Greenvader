extends SceneTree
const Scene: PackedScene = preload("res://scenes/vine_compare.tscn")
const OUT: String = "res://evidence/vine-compare/self/"
var lab: Node
var results: Array[Dictionary] = []
var smoke: Array[Dictionary] = []
var details: Array[Dictionary] = []
var failures: int = 0

func _initialize() -> void:
	root.unfocusable = true
	create_timer(110).timeout.connect(func() -> void: quit(99))
	run.call_deferred()

func check(ok: bool, id: String, detail: String = "") -> void:
	results.append({"id":id,"status":"PASS" if ok else "FAIL","detail":detail})
	if not ok: failures += 1
	print(results[-1])

func capture(label: String) -> Image:
	await lab.wait_render()
	var image_: Image = lab.render_view.get_texture().get_image()
	image_.save_png(OUT+label+"_640.png")
	var ui: Image = root.get_texture().get_image()
	ui.resize(1920,1080,Image.INTERPOLATE_NEAREST)
	ui.save_png(OUT+label+"_ui_1920.png")
	return image_

func original_ok() -> bool:
	for record: Dictionary in lab.reveal.records:
		var node: MeshInstance3D = record["node"]
		if node.mesh!=record["original"] or not node.visible: return false
	return lab.model.scale.is_equal_approx(Vector3.ONE)

func run() -> void:
	lab = Scene.instantiate()
	root.add_child(lab)
	if not "inventory" in lab:
		quit(3)
		return
	check(lab.inventory.size()==63,"inventory_63",str(lab.inventory.size()))
	if lab.inventory.is_empty():
		_save()
		quit(3)
		return
	check(lab.current_id==7 and lab.density_select.selected==0,"initial_007_old_sparse")
	check(lab.old_patch.get_script().resource_path.ends_with("growth_patch.gd") and lab.old_patch.leaf_node.multimesh.mesh==lab.library.leaves,"actual_old_library")
	# Exactly one inventory smoke pass. Endpoint tests below are separate.
	for entry: Dictionary in lab.inventory:
		var number: int = entry["number"]
		var ok: bool = lab.select_id(number)
		var state: Dictionary = lab.reveal.snapshot()
		ok = ok and state["vertices"]>0 and state["triangles"]>0 and state["distance"]>0 and original_ok()
		smoke.append({"id":entry["id"],"status":"PASS" if ok else "FAIL","stats":state})
		if not ok: failures += 1
	check(smoke.size()==63 and failures==0,"all_ID_single_smoke")
	for id_: int in [7,32,47,60,24]:
		check(lab.select_id(id_),"select_"+str(id_))
		var fixed: Transform3D = lab.model.transform
		var counts: Array[int] = []
		for percent: int in [0,25,50,75,100]:
			lab.growth_slider.value = percent
			counts.append(lab.reveal.shown_triangles)
			if percent==0:
				var none: bool = not lab.old_patch.visible
				for record: Dictionary in lab.reveal.records: none = none and not record["node"].visible
				check(none,"zero_empty_"+str(id_))
			if percent==100: check(original_ok(),"original_finish_"+str(id_))
		var monotonic: bool = counts[0]==0 and counts[1]>0 and counts[1]<=counts[2] and counts[2]<=counts[3] and counts[3]<=counts[4]
		check(monotonic and lab.model.transform==fixed,"root_fixed_path_growth_"+str(id_),str(counts))
		lab.set_growth(50)
		lab.set_growth(100)
		check(original_ok(),"material_roundtrip_"+str(id_))
		details.append({"id":id_,"counts":counts,"stats":lab.reveal.snapshot(),"fixed_transform":str(fixed)})
	check(not lab.select_id(999) and lab.current_id==24 and "999" in lab.last_error,"missing_ID_keeps_previous")
	check(lab.select_text("VIN-007") and lab.last_error.is_empty(),"recover_valid_ID")
	lab.growth_slider.value = 50
	lab.asset_select.item_selected.emit(lab._index(32))
	check(lab.current_id==32 and lab.growth==50 and lab.reveal.progress==50,"ID_change_preserves_growth")
	var before: int = lab.reveal.shown_triangles
	await create_timer(0.1).timeout
	check(lab.growth==50 and before==lab.reveal.shown_triangles,"paused_state_fixed")
	lab.play_button.pressed.emit()
	await create_timer(0.15).timeout
	lab.play_button.pressed.emit()
	check(lab.growth>50 and not lab.playing,"play_stop_UI")
	lab.path_field.text = "C:/__missing_vine_compare_folder__"
	check(not lab.reload_inventory() and lab.current_id==32,"path_error_keeps_previous")
	lab.path_field.text = lab.DEFAULT_PATH
	check(lab.reload_inventory() and lab.inventory.size()==63 and lab.last_error.is_empty(),"path_reload_recovery")
	lab.density_select.select(1)
	lab.density_select.item_selected.emit(1)
	check(not lab.old_patch.sparse_windows,"old_lab_density_option")
	lab.density_select.select(0)
	lab.density_select.item_selected.emit(0)
	if DisplayServer.get_name()=="headless" or RenderingServer.get_video_adapter_name().is_empty():
		print("GPU NOT_RUN")
		_save()
		quit(2)
		return
	lab.select_id(7)
	lab.set_growth(0)
	await capture("007_zero")
	lab.set_growth(50)
	await capture("007_half")
	lab.set_growth(100)
	var full: Image = await capture("007_full")
	var expected: Image = full.duplicate()
	expected.resize(1920,1080,Image.INTERPOLATE_NEAREST)
	check(expected.get_data()==lab.doubled_view.get_texture().get_image().get_data(),"nearest3_exact")
	for id_: int in [47,60,24]:
		lab.select_id(id_)
		lab.set_growth(50)
		await capture("%03d_half"%id_)
	lab.select_id(7)
	lab.set_growth(100)
	lab.azimuth_slider.value = 225
	lab.elevation_slider.value = 15
	var changed: Image = await capture("007_low_sun")
	check(changed.get_data()!=full.get_data() and lab.sun_elevation==15,"sun_controls_GPU")
	lab.receiver_select.select(2)
	lab.receiver_select.item_selected.emit(2)
	check(lab.left_receiver.get_child_count()==0 and lab.right_receiver.get_child_count()==0,"receiver_off")
	_save()
	lab.free()
	await process_frame
	quit(0 if failures==0 else 1)

func _save() -> void:
	FileAccess.open(OUT+"results.json",FileAccess.WRITE).store_string(JSON.stringify({"adapter":RenderingServer.get_video_adapter_name(),"results":results,"failures":failures,"NOT_RUN":["physical_input_OS","game_growth_save_integration","all_angles_performance","user_art_review"]},"\t"))
	FileAccess.open(OUT+"smoke.json",FileAccess.WRITE).store_string(JSON.stringify(smoke,"\t"))
	FileAccess.open(OUT+"representatives.json",FileAccess.WRITE).store_string(JSON.stringify(details,"\t"))
