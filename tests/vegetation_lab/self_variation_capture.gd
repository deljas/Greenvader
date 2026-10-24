extends SceneTree
const Scene: PackedScene = preload("res://scenes/vegetation_lab.tscn")
const OUT: String = "res://evidence/vegetation-variation/self/"
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
		var img: Image = await capture("growth_%03d" % [i*50],i==2)
		if i==0:
			baseline = img
	var signatures: Array[String] = []
	for patch: Node3D in lab.patches:
		signatures.append(patch.layout_signature()+patch.pose_signature)
	lab.slider.value = 50
	lab.number.value = 100
	for i: int in 3:
		var patch: Node3D = lab.patches[i]
		check(signatures[i]==patch.layout_signature()+patch.pose_signature,"determinism_"+str(i))
		var straight: int = 0
		var curved: int = 0
		var order: bool = true
		var clear: bool = true
		var rows: Array[Dictionary] = []
		for path: Dictionary in patch.paths:
			var min_u: float = INF
			var max_u: float = -INF
			var points: Array[Dictionary] = []
			for hit: Dictionary in path["points"]:
				if hit["v"]<=path["surface"]["height"]:
					min_u = minf(min_u,hit["u"])
					max_u = maxf(max_u,hit["u"])
					for hole: Rect2 in path["surface"]["holes"]:
						clear = clear and not (hit["u"]>hole.position.x-0.33 and hit["u"]<hole.end.x+0.33 and hit["v"]>hole.position.y-0.33 and hit["v"]<hole.end.y+0.33)
				points.append({"position":[hit["position"].x,hit["position"].y,hit["position"].z],"u":hit["u"],"v":hit["v"],"distance":hit["distance"]})
			if path["parent"]<0:
				if max_u-min_u<0.06:
					straight += 1
				if max_u-min_u>0.15:
					curved += 1
			else:
				var parent: Dictionary = patch.paths[path["parent"]]
				var junction: int = path["junction"]
				var measured: float = 0.0
				for n: int in range(1,junction+1):
					measured += Vector3(parent["points"][n-1]["position"]).distance_to(parent["points"][n]["position"])
				order = order and absf(measured-float(path["start"]))<0.0001 and Vector3(parent["points"][junction]["position"]).is_equal_approx(path["points"][0]["position"])
			rows.append({"parent":path["parent"],"junction":path["junction"],"start":path["start"],"variation":path.get("variation",{}),"points":points})
		check(straight>0 and curved>0,"straight_curved_"+str(i),"straight %d / curved %d, measured wall UV range" % [straight,curved])
		check(clear and order,"openings_order_"+str(i))
		check(patch.leaf_node.multimesh.mesh==lab.library.leaves and patch.stem_node.multimesh.mesh==lab.library.stem and patch.grass_nodes[0].multimesh.mesh==lab.library.grasses[0] and patch.leaf_node.material_override==lab.library.foliage_material,"resources_"+str(i))
		var patches_: Array = lab.layers[i].patch_records
		var small: int = 0
		var large: int = 0
		for record: Dictionary in patches_:
			var span: Array = record["span"]
			if not record["roof"]:
				if span[0]<1.3 and span[1]<1.3:
					small += 1
				if span[0]>1.6 and span[1]>1.6:
					large += 1
		check(small>0 and large>0,"moss_sizes_"+str(i),"small %d / large %d" % [small,large])
		snapshots.append({"building":patch.definition["id"],"grass_signature":str(patch.grass_candidates).sha256_text(),"paths":rows,"patches":patches_})
	lab.presets[0].pressed.emit()
	lab.moss_slider.value = 100
	lab.moss_check.button_pressed = true
	var moss_on: Image = await capture("moss_only_100")
	check(differences(baseline,moss_on)>50 and lab.slider.value==0,"moss_independent_GPU")
	lab.moss_check.button_pressed = false
	var moss_off: Image = await capture("moss_OFF")
	check(baseline.get_data()==moss_off.get_data(),"moss_OFF_exact")
	lab.presets[2].pressed.emit()
	lab.moss_slider.value = 60
	lab.moss_check.button_pressed = true
	for index: int in [1,3]:
		lab.view_select.select(index)
		lab.view_select.item_selected.emit(index)
		await capture("A_closeup" if index==1 else "C_closeup")
	var result_file: FileAccess = FileAccess.open(OUT+"results.json",FileAccess.WRITE)
	result_file.store_string(JSON.stringify({"adapter":RenderingServer.get_video_adapter_name(),"results":results,"failures":failures,"NOT_RUN":["OS physical input","video","performance","all directions","normal game regression"]},"\t"))
	var raw_file: FileAccess = FileAccess.open(OUT+"raw.json",FileAccess.WRITE)
	raw_file.store_string(JSON.stringify(snapshots,"\t"))
	quit(0 if failures==0 else 1)

