extends SceneTree
const Scene: PackedScene = preload("res://scenes/vegetation_lab.tscn")
const Geometry: GDScript = preload("res://scripts/vegetation_lab/building_geometry.gd")
const OUT: String = "res://evidence/vegetation-lab/self/"
var lab: Node
var results: Array[Dictionary] = []
var failures: int = 0

func _initialize() -> void:
	root.unfocusable = true
	create_timer(55).timeout.connect(func() -> void: quit(99))
	run.call_deferred()

func check(ok: bool, id: String, detail: String = "") -> void:
	results.append({"id":id,"status":"PASS" if ok else "FAIL","detail":detail})
	if not ok:
		failures += 1
	print(results[-1])

func capture(label_: String, representative: bool = false) -> void:
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
		image_.resize(1920,1080,Image.INTERPOLATE_NEAREST)
		check(image_.get_data()==gpu3.get_data(),"GPU.nearest3_exact")

func run() -> void:
	lab = Scene.instantiate()
	root.add_child(lab)
	if DisplayServer.get_name()=="headless" or RenderingServer.get_video_adapter_name().is_empty():
		print("GPU NOT_RUN: structural load only")
		quit(2)
		return
	for i: int in 3:
		lab.presets[i].pressed.emit()
		await capture("growth_%03d" % [i*50],i==2)
		print("IMAGE "+ProjectSettings.globalize_path(OUT+"growth_%03d_ui_1920.png" % [i*50]))
	var signatures: Array[String] = []
	var mature_transforms: Array[PackedByteArray] = []
	for patch: Node3D in lab.patches:
		signatures.append(patch.layout_signature())
		mature_transforms.append(var_to_bytes(patch.leaf_node.multimesh.buffer))
	lab.slider.value = 50
	lab.number.value = 100
	check(lab.slider.value==100 and lab.number.value==100,"UI.slider_number_presets")
	for i: int in 3:
		var patch: Node3D = lab.patches[i]
		check(signatures[i]==patch.layout_signature() and mature_transforms[i]==var_to_bytes(patch.leaf_node.multimesh.buffer),"layout.restore_"+str(i))
		var shared: bool = patch.leaf_node.multimesh.mesh==lab.library.leaves and patch.stem_node.multimesh.mesh==lab.library.stem and patch.leaf_node.material_override==lab.library.foliage_material
		for j: int in 2:
			shared = shared and patch.grass_nodes[j].multimesh.mesh==lab.library.grasses[j] and patch.grass_nodes[j].material_override==lab.library.foliage_material
		check(shared,"resource.shared_"+str(i))
		var excluded: bool = true
		for candidate: Dictionary in patch.grass_candidates:
			var p: Vector3 = candidate["position"]
			excluded = excluded and Geometry.ground_allowed(patch.definition,Vector2(p.x,p.z),0.34)
		for path: Dictionary in patch.paths:
			for hit: Dictionary in path["points"]:
				if hit["distance"]<=path["surface"]["height"]:
					excluded = excluded and not Geometry.blocked_surface(path["surface"],hit["u"],hit["distance"],0.32)
		check(excluded,"exclusions_"+str(i),"grass clump margin .34; vine opening margin .32")
		var finite: bool = true
		for node: MultiMeshInstance3D in [patch.leaf_node,patch.stem_node,patch.grass_nodes[0],patch.grass_nodes[1]]:
			for n: int in node.multimesh.instance_count:
				finite = finite and node.multimesh.get_instance_transform(n).is_finite()
		check(finite,"finite_"+str(i),"grass %d / vine paths %d" % [patch.grass_candidates.size(),patch.paths.size()])
	lab.view_select.select(3)
	lab.view_select.item_selected.emit(3)
	await capture("C_mature_closeup")
	var file: FileAccess = FileAccess.open(OUT+"results.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"adapter":RenderingServer.get_video_adapter_name(),"results":results,"failures":failures,"NOT_RUN":["OS physical input","video","normal game regression"]},"\t"))
	quit(0 if failures==0 else 1)
