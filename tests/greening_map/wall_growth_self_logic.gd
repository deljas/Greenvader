extends SceneTree
const Scene: PackedScene = preload("res://scenes/greening_map.tscn")
const Definitions: GDScript = preload("res://scripts/vegetation_lab/building_defs.gd")
const Geometry: GDScript = preload("res://scripts/vegetation_lab/building_geometry.gd")
const Patch: GDScript = preload("res://scripts/vegetation_lab/growth_patch.gd")
const Layers: GDScript = preload("res://scripts/vegetation_lab/surface_layers.gd")
const Parts: GDScript = preload("res://scripts/vegetation_lab/plant_parts.gd")
const Session: GDScript = preload("res://scripts/greening_map/session.gd")
const OUT: String = "res://evidence/wall-growth/self/"
var checks: Array[Dictionary] = []
var failures: int = 0
var snapshots: Array[Dictionary] = []

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, id: String, detail: String = "") -> void:
	checks.append({"id":id,"status":"PASS" if ok else "FAIL","detail":detail})
	if not ok:
		failures += 1
	print(checks[-1])

func run() -> void:
	# Saved original scripts vs extended defaults, once at 50% for each building.
	var old_patch: GDScript = load(OUT+"before/scripts/vegetation_lab/growth_patch.gd")
	var old_layer: GDScript = load(OUT+"before/scripts/vegetation_lab/surface_layers.gd")
	var library: RefCounted = Parts.new()
	var moss: ShaderMaterial = ShaderMaterial.new()
	moss.shader = Layers.Moss
	var cracks: ShaderMaterial = ShaderMaterial.new()
	cracks.shader = Layers.Cracks
	var signatures: Array[Dictionary] = []
	for def: Dictionary in Definitions.all():
		var holder: Node3D = Node3D.new()
		Geometry.build(holder,def)
		var before_patch: Node3D = old_patch.new()
		var after_patch: Node3D = Patch.new()
		holder.add_child(before_patch)
		holder.add_child(after_patch)
		before_patch.setup(def,library)
		after_patch.setup(def,library)
		before_patch.set_growth(50)
		after_patch.set_growth(50)
		var before_layer: Node3D = old_layer.new()
		var after_layer: Node3D = Layers.new()
		holder.add_child(before_layer)
		holder.add_child(after_layer)
		before_layer.setup(def,moss,cracks)
		after_layer.setup(def,moss,cracks)
		var same: bool = before_patch.layout_signature()==after_patch.layout_signature() and before_patch.pose_signature==after_patch.pose_signature and before_layer.patch_records==after_layer.patch_records and before_layer.moss.get_child_count()==after_layer.moss.get_child_count() and before_layer.cracks.get_child_count()==after_layer.cracks.get_child_count()
		check(same,"default_compatibility_"+str(def["id"]))
		signatures.append({"id":def["id"],"old_layout":before_patch.layout_signature(),"new_layout":after_patch.layout_signature(),"old_pose50":before_patch.pose_signature,"new_pose50":after_patch.pose_signature,"old_moss_records":str(before_layer.patch_records).sha256_text(),"new_moss_records":str(after_layer.patch_records).sha256_text()})
		holder.free()
	var lab: Node = Scene.instantiate()
	lab.automatic = false
	root.add_child(lab)
	var controller: Node = lab.wall_growth
	var model: RefCounted = lab.session
	model.spread.allow_hook = func(_index: int) -> bool: return false # isolate the local fixture
	var entry: Dictionary = controller.entries[0]
	var chosen: Dictionary
	for item: Dictionary in entry["roots"]:
		if absf(item["anchor"].y-1.0)<0.01 and item["anchor"].x> -4.0 and item["anchor"].x< -2.0:
			chosen = item
			break
	check(not chosen.is_empty(),"fixture_front_root")
	if chosen.is_empty():
		lab.free()
		quit(1)
		return
	var init_zero: bool = true
	var no_extras: bool = true
	for item: Dictionary in controller.entries:
		no_extras = no_extras and item["patch"].grass_nodes.is_empty() and item["layer"].cracks.get_child_count()==0
		for path: Dictionary in item["patch"].paths:
			for hit: Dictionary in path["points"]:
				no_extras = no_extras and float(hit["v"])<=float(path["surface"]["height"])-0.30
		for value: Dictionary in item["roots"]:
			init_zero = init_zero and value["progress"]==0
			for index: int in value["cells"]:
				no_extras = no_extras and model.state.target[index]==1
		for value: Dictionary in item["moss"]:
			init_zero = init_zero and value["progress"]==0
		for value: Dictionary in item["layer"].moss_entries:
			no_extras = no_extras and not value["roof"]
	check(init_zero and no_extras,"initial_zero_wall_only_no_ground_roof_cracks")
	model.position = Session.to_logic(chosen["anchor"]+Vector2(0,1.0))
	check(model.scatter(chosen["anchor"],false),"actual_session_seed_landing")
	model.advance_game(10)
	check(chosen["progress"]==0,"seed_stage_no_wall_input")
	model.advance_game(25)
	check(chosen["progress"]>0 and controller.tick_count==model.clock.growth_ticks,"sprout_and_real_clock_connection")
	snapshots.append(controller.snapshot())
	for index: int in chosen["cells"]:
		model.state.set_stage(index,WorldState.STAGE_MATURE)
		model.state.growth[index] = 120000
	var counters: Vector2i = Vector2i(model.state.greened_count,model.state.target_count)
	model.advance_game(45)
	check(chosen["progress"]>0.49 and chosen["progress"]<1,"mature_ground_has_delayed_wall_growth")
	check(Vector2i(model.state.greened_count,model.state.target_count)==counters,"wall_progress_no_greening_counter_gain")
	var other_zero: bool = true
	for item: Dictionary in controller.entries[1]["roots"]:
		other_zero = other_zero and item["progress"]==0
	check(other_zero,"other_building_unaffected")
	var materials: Dictionary = {}
	for item: Dictionary in controller.entries:
		for value: Dictionary in item["layer"].moss_entries:
			var id: int = value["mesh"].material_override.get_instance_id()
			materials[id] = true
	check(materials.size()==controller.entries[0]["layer"].moss_entries.size()+controller.entries[1]["layer"].moss_entries.size(),"individual_patch_materials")
	var moss_growing: bool = false
	for item: Dictionary in entry["moss"]:
		moss_growing = moss_growing or (item["progress"]>0 and item["progress"]<chosen["progress"])
	check(moss_growing,"moss_separate_slower_progress")
	var held: float = chosen["progress"]
	for index: int in chosen["cells"]:
		model.state.set_stage(index,WorldState.STAGE_EMPTY)
	model.advance_game(5)
	check(chosen["progress"]==held,"green_loss_holds_not_reverses")
	model.paused = true
	var saved: String = str(controller.snapshot())
	model.advance_game(100)
	lab.azimuth_slider.value = 135
	lab.ground_view.refresh(model.state)
	check(str(controller.snapshot())==saved,"pause_sun_refresh_no_progress")
	model.paused = false
	for index: int in chosen["cells"]:
		model.state.set_stage(index,WorldState.STAGE_MATURE)
		model.state.growth[index] = 120000
	model.advance_game(45)
	check(chosen["progress"]==1.0,"resume_reaches_full_without_input_cap")
	var soil: int = model.state.index_of(26,32)
	var pavement: int = model.state.index_of(26,24)
	for index: int in [soil,pavement]:
		model.state.set_stage(index,WorldState.STAGE_SPROUT1)
		model.state.growth[index] = 50000
	check(controller.local_input(PackedInt32Array([soil]))==controller.local_input(PackedInt32Array([pavement])),"soil_pavement_equal_internal_input")
	snapshots.append(controller.snapshot())
	var f: FileAccess = FileAccess.open(OUT+"logic-results.json",FileAccess.WRITE)
	f.store_string(JSON.stringify({"results":checks,"failures":failures,"default_signatures":signatures},"\t"))
	f = FileAccess.open(OUT+"logic-raw.json",FileAccess.WRITE)
	f.store_string(JSON.stringify(snapshots,"\t"))
	lab.free()
	quit(0 if failures==0 else 1)
