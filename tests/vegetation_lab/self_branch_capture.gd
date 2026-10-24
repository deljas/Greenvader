extends SceneTree
const Scene: PackedScene = preload("res://scenes/vegetation_lab.tscn")
const OUT: String = "res://evidence/vegetation-branches/self/"
var lab: Node
var results: Array[Dictionary] = []
var snapshots: Array[Dictionary] = []
var failures: int = 0

func _initialize() -> void:
	root.unfocusable = true
	create_timer(70).timeout.connect(func() -> void: quit(99))
	run.call_deferred()

func check(ok: bool, id: String, detail: String = "") -> void:
	results.append({"id":id,"status":"PASS" if ok else "FAIL","detail":detail})
	if not ok:
		failures += 1
	print(results[-1])

func capture(label_: String, representative: bool = false) -> Image:
	await lab.wait_render()
	var image_: Image = lab.render_view.get_texture().get_image()
	image_.save_png(OUT+label_+"_world_640.png")
	var ui: Image = root.get_texture().get_image()
	ui.save_png(OUT+label_+"_ui_640.png")
	ui.resize(1920,1080,Image.INTERPOLATE_NEAREST)
	ui.save_png(OUT+label_+"_ui_1920.png")
	if representative:
		var gpu3: Image = lab.doubled_view.get_texture().get_image()
		gpu3.save_png(OUT+label_+"_world_1920.png")
		var expected: Image = image_.duplicate()
		expected.resize(1920,1080,Image.INTERPOLATE_NEAREST)
		check(expected.get_data()==gpu3.get_data(),"GPU.nearest3_exact")
	print("IMAGE "+ProjectSettings.globalize_path(OUT+label_+"_ui_1920.png"))
	return image_

func differences(a: Image, b: Image) -> int:
	var total: int = 0
	for y: int in a.get_height():
		for x: int in a.get_width():
			if a.get_pixel(x,y)!=b.get_pixel(x,y):
				total += 1
	return total

func run() -> void:
	lab = Scene.instantiate()
	root.add_child(lab)
	if DisplayServer.get_name()=="headless" or RenderingServer.get_video_adapter_name().is_empty():
		print("GPU NOT_RUN: structural load only")
		quit(2)
		return
	lab.moss_check.button_pressed = false
	var baseline: Image
	for i: int in 3:
		lab.presets[i].pressed.emit()
		var image_: Image = await capture("growth_%03d" % [i*50],i==2)
		if i==0:
			baseline = image_
	var poses: Array[String] = []
	var layouts: Array[String] = []
	for patch: Node3D in lab.patches:
		poses.append(patch.pose_signature)
		layouts.append(patch.layout_signature())
	lab.slider.value = 50
	lab.number.value = 100
	for i: int in 3:
		var patch: Node3D = lab.patches[i]
		check(poses[i]==patch.pose_signature and layouts[i]==patch.layout_signature(),"restore_"+str(i),"CPU poses/layout; no headless MultiMesh getters")
		var shared: bool = patch.leaf_node.multimesh.mesh==lab.library.leaves and patch.stem_node.multimesh.mesh==lab.library.stem and patch.stem_node.material_override==lab.library.stem_material
		for j: int in 2:
			shared = shared and patch.grass_nodes[j].multimesh.mesh==lab.library.grasses[j] and patch.grass_nodes[j].material_override==lab.library.foliage_material
		check(shared and patch.leaf_node.material_override==lab.library.foliage_material,"resources_"+str(i))
		var order_ok: bool = true
		var spread: float = 0
		var branches: int = 0
		var path_rows: Array[Dictionary] = []
		for path: Dictionary in patch.paths:
			var row: Dictionary = {"parent":path["parent"],"start":path["start"],"length":path["length"],"junction":path["junction"],"points":[]}
			for point: Dictionary in path["points"]:
				row["points"].append({"position":[point["position"].x,point["position"].y,point["position"].z],"u":point["u"],"v":point["v"],"distance":point["distance"]})
			path_rows.append(row)
			if path["parent"]>=0:
				branches += 1
				var parent: Dictionary = patch.paths[path["parent"]]
				var join: Dictionary = parent["points"][path["junction"]]
				order_ok = order_ok and Vector3(path["points"][0]["position"]).is_equal_approx(join["position"]) and absf(float(path["start"])-float(parent["start"])-float(join["distance"]))<0.00001
				# Independently measure actual path lengths against scheduling values.
				var measured: float = 0
				for n: int in range(1,int(path["junction"])+1):
					measured += Vector3(parent["points"][n-1]["position"]).distance_to(parent["points"][n]["position"])
				order_ok = order_ok and absf(float(path["start"])-measured)<0.0001
				spread = maxf(spread,absf(float(path["points"][-1]["u"])-float(path["points"][0]["u"])))
		check(order_ok and branches>0 and spread>0.5,"branch_order_spread_"+str(i),"branches %d, max lateral UV %.2f" % [branches,spread])
		snapshots.append({"building":patch.definition["id"],"duration":patch.duration,"leaf_resource":patch.leaf_node.multimesh.mesh.get_instance_id(),"stem_resource":patch.stem_node.multimesh.mesh.get_instance_id(),"paths":path_rows})
	# UI moss amount is independent of growth; compare actual world pixels.
	lab.presets[0].pressed.emit()
	lab.moss_slider.value = 100
	lab.moss_check.button_pressed = true
	var moss_on: Image = await capture("moss_only_100")
	check(lab.slider.value==0 and lab.moss_number.value==100 and differences(baseline,moss_on)>50,"moss.independent_GPU")
	lab.moss_number.value = 0
	var moss_zero: Image = await capture("moss_amount_000")
	check(baseline.get_data()==moss_zero.get_data(),"moss.zero_no_effect")
	lab.moss_slider.value = 100
	lab.moss_check.button_pressed = false
	var moss_off: Image = await capture("moss_OFF")
	check(baseline.get_data()==moss_off.get_data(),"moss.OFF_baseline")
	lab.crack_check.button_pressed = true
	var cracks_on: Image = await capture("cracks_only")
	check(differences(baseline,cracks_on)>5,"cracks.independent_GPU")
	lab.crack_check.button_pressed = false
	var cracks_off: Image = await capture("cracks_OFF")
	check(baseline.get_data()==cracks_off.get_data(),"cracks.OFF_baseline")
	lab.presets[2].pressed.emit()
	lab.moss_slider.value = 60
	lab.moss_check.button_pressed = true
	lab.view_select.select(1)
	lab.view_select.item_selected.emit(1)
	await capture("A_roof_branches_closeup")
	lab.view_select.select(3)
	lab.view_select.item_selected.emit(3)
	await capture("C_branches_closeup")
	var result_file: FileAccess = FileAccess.open(OUT+"results.json",FileAccess.WRITE)
	result_file.store_string(JSON.stringify({"adapter":RenderingServer.get_video_adapter_name(),"results":results,"failures":failures,"NOT_RUN":["OS physical input","video","normal game regression"]},"\t"))
	var geometry_file: FileAccess = FileAccess.open(OUT+"path-snapshot.json",FileAccess.WRITE)
	geometry_file.store_string(JSON.stringify(snapshots,"\t"))
	quit(0 if failures==0 else 1)
