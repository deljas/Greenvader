extends SceneTree
const Scene: PackedScene = preload("res://scenes/greening_map.tscn")
const Definitions: GDScript = preload("res://scripts/vegetation_lab/building_defs.gd")
const Geometry: GDScript = preload("res://scripts/vegetation_lab/building_geometry.gd")
const Patch: GDScript = preload("res://scripts/vegetation_lab/growth_patch.gd")
const Layers: GDScript = preload("res://scripts/vegetation_lab/surface_layers.gd")
const Parts: GDScript = preload("res://scripts/vegetation_lab/plant_parts.gd")
const Session: GDScript = preload("res://scripts/greening_map/session.gd")
const OUT: String = "res://evidence/building-model/self/"
var checks: Array[Dictionary] = []
var failures: int = 0
var raw: Dictionary = {}

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, id: String, detail: String = "") -> void:
	checks.append({"id":id,"status":"PASS" if ok else "FAIL","detail":detail})
	if not ok:
		failures += 1
	print(checks[-1])

func bounds(node: Node3D, transform_: Transform3D = Transform3D.IDENTITY) -> AABB:
	var result: AABB = AABB()
	var first: bool = true
	var here: Transform3D = transform_*node.transform
	if node is MeshInstance3D:
		result = here*(node as MeshInstance3D).get_aabb()
		first = false
	for child: Node in node.get_children():
		if child is Node3D:
			var box: AABB = bounds(child,here)
			if box.size.length_squared()>0:
				result = box if first else result.merge(box)
				first = false
	return result

func run() -> void:
	var old_patch: GDScript = load(OUT+"before/scripts/vegetation_lab/growth_patch.gd")
	var old_layer: GDScript = load(OUT+"before/scripts/vegetation_lab/surface_layers.gd")
	var library: RefCounted = Parts.new()
	var signatures: Array[Dictionary] = []
	for def: Dictionary in ([] if "--impact" in OS.get_cmdline_user_args() else Definitions.all()):
		var holder: Node3D = Node3D.new()
		root.add_child(holder)
		Geometry.build(holder,def)
		var a: Node3D = old_patch.new()
		var b: Node3D = Patch.new()
		holder.add_child(a)
		holder.add_child(b)
		a.setup(def,library)
		b.setup(def,library)
		a.set_growth(50)
		b.set_growth(50)
		var moss: ShaderMaterial = ShaderMaterial.new()
		moss.shader = Layers.Moss
		var cracks: ShaderMaterial = ShaderMaterial.new()
		cracks.shader = Layers.Cracks
		var la: Node3D = old_layer.new()
		var lb: Node3D = Layers.new()
		holder.add_child(la)
		holder.add_child(lb)
		la.setup(def,moss,cracks)
		lb.setup(def,moss,cracks)
		check(a.layout_signature()==b.layout_signature() and a.pose_signature==b.pose_signature and la.patch_records==lb.patch_records,"old_default_"+def["id"])
		signatures.append({"id":def["id"],"old_layout":a.layout_signature(),"new_layout":b.layout_signature(),"old_pose50":a.pose_signature,"new_pose50":b.pose_signature,"old_moss":str(la.patch_records).sha256_text(),"new_moss":str(lb.patch_records).sha256_text()})
		holder.free()
	raw["default_signatures"] = signatures
	var model: PackedScene = load("res://assets/models/ruin_house/ruin_house.glb")
	var instance: Node3D = model.instantiate()
	var box: AABB = bounds(instance)
	check(box.position.x>= -3.2 and box.end.x<=3.2 and box.position.z>= -2.8 and box.end.z<=2.8,"imported_model_inside_foundation",str(box))
	raw["model_bounds"] = {"position":box.position,"size":box.size,"children":instance.get_child_count()}
	instance.free()
	var lab: Node = Scene.instantiate()
	lab.automatic = false
	root.add_child(lab)
	lab.session.spread.allow_hook = func(_index: int) -> bool: return false
	var zero: bool = true
	var resources: bool = true
	var exclusions: bool = true
	var overlap: int = 0
	for entry: Dictionary in lab.wall_growth.entries:
		resources = resources and entry["patch"].leaf_node.multimesh.mesh==lab.ground_view.library.leaves and entry["patch"].grass_nodes.is_empty()
		for path: Dictionary in entry["patch"].paths:
			for hit: Dictionary in path["points"]:
				var uv: Vector2 = Vector2(hit["u"],hit["v"])
				for hole: Rect2 in path["surface"]["holes"]:
					if hole.position.y<0.05:
						exclusions = exclusions and not hole.grow(0.25).has_point(uv)
					elif hole.has_point(uv):
						overlap += 1
				for awning: Rect2 in path["surface"].get("awnings",[]):
					exclusions = exclusions and not awning.grow(0.25).has_point(uv)
		for root_: Dictionary in entry["roots"]:
			zero = zero and root_["progress"]==0
	check(zero and resources,"initial_zero_shared_no_duplicate_ground")
	check(exclusions and overlap>0,"window_partial_routes_door_awning_clear","window path samples="+str(overlap))
	for index: int in lab.session.state.tile_count():
		var p: Vector2 = Session.cell_center(index)
		if lab.session.state.target[index]==1 and p.x> -6.3 and p.x< -0.1 and p.y>0.8 and p.y<1.8:
			lab.session.state.set_stage(index,WorldState.STAGE_MATURE)
			lab.session.state.growth[index] = 120000
	var counters: Vector2i = Vector2i(lab.session.state.greened_count,lab.session.state.target_count)
	lab.session.advance_game(45)
	raw["local45"] = lab.wall_growth.snapshot()
	lab.session.advance_game(90)
	raw["local135"] = lab.wall_growth.snapshot()
	var local_only: bool = true
	var reached: bool = false
	for entry: Dictionary in lab.wall_growth.entries:
		for root_: Dictionary in entry["roots"]:
			if entry["id"]=="A" and root_["anchor"].y>0.9:
				reached = reached or root_["progress"]==1
			else:
				local_only = local_only and root_["progress"]==0
	check(reached and local_only and counters==Vector2i(lab.session.state.greened_count,lab.session.state.target_count),"local_clock_growth_counter_unchanged")
	var coverage: Array[Dictionary] = []
	for entry: Dictionary in lab.wall_growth.entries:
		var values: Dictionary = {}
		for root_: Dictionary in entry["roots"]:
			values[root_["path"]] = 1.0
		entry["patch"].set_root_progress(values)
		for surface: Dictionary in entry["patch"].definition["surfaces"]:
			var area: float = float(surface["width"])*float(surface["height"])
			for hole: Rect2 in surface["holes"]:
				area -= hole.get_area()
			var upper_bound: float = 0
			for leaf: Dictionary in entry["patch"].leaf_records:
				if leaf["surface"]!=surface:
					continue
				var min_: Vector2 = Vector2(INF,INF)
				var max_: Vector2 = Vector2(-INF,-INF)
				for vertex: Vector3 in library.leaves.get_faces():
					var v: Vector3 = leaf["transform"]*vertex
					var uv: Vector2 = Vector2((v-Vector3(surface["origin"])).dot(surface["tangent"]),v.y)
					min_ = min_.min(uv)
					max_ = max_.max(uv)
				upper_bound += (max_.x-min_.x)*(max_.y-min_.y)
			for path: Dictionary in entry["patch"].paths:
				if path["surface"]==surface:
					upper_bound += float(path["length"])*0.048 # Full tube diameter, overlaps counted repeatedly.
			for patch: Dictionary in entry["layer"].patch_records:
				if patch["surface_width"]==surface["width"]:
					upper_bound += float(patch["span"][0])*float(patch["span"][1]) # Entire sheet, incl discarded fragments.
			coverage.append({"building":entry["id"],"normal":surface["normal"],"solid_wall_area_m2":area,"vegetation_upper_bound_m2":upper_bound,"upper_ratio":upper_bound/area})
			check(upper_bound/area<0.5,"wall_bare_half_"+entry["id"]+str(surface["normal"]),str(upper_bound/area))
	raw["coverage_conservative_sum"] = coverage
	lab.session.paused = true
	var before: String = str(lab.wall_growth.snapshot())
	lab.elevation_slider.value = 15
	check(lab.elevation_number.value==15 and lab.sun_elevation==15,"elevation_slider_sync")
	lab.elevation_number.value = 80
	check(lab.elevation_slider.value==80 and before==str(lab.wall_growth.snapshot()),"elevation_number_sync_no_growth")
	FileAccess.open(OUT+"logic-results.json",FileAccess.WRITE).store_string(JSON.stringify({"results":checks,"failures":failures},"\t"))
	FileAccess.open(OUT+"logic-raw.json",FileAccess.WRITE).store_string(JSON.stringify(raw,"\t"))
	lab.free()
	await process_frame
	quit(0 if failures==0 else 1)
