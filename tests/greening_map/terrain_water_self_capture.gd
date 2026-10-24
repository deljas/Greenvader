extends SceneTree
const Scene: PackedScene = preload("res://scenes/greening_map.tscn")
const Session: GDScript = preload("res://scripts/greening_map/session.gd")
const Geometry: GDScript = preload("res://scripts/render_study_3d/ruin_geometry.gd")
const OUT: String = "res://evidence/terrain-water/self/"
var lab: Node
var results: Array[Dictionary] = []
var raw: Array[Dictionary] = []
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
	var snapshot: Dictionary = lab.session.snapshot()
	snapshot["label"] = label_
	snapshot["reflection_size"] = str(lab.water_surface.reflection_view.size)
	raw.append(snapshot)
	print("IMAGE "+ProjectSettings.globalize_path(OUT+label_+"_ui_1920.png"))
	return image_

func pond_difference(a: Image, b: Image) -> int:
	var rect: Rect2 = lab.water_surface.pond_bounds
	var polygon: PackedVector2Array = PackedVector2Array()
	for p: Vector2 in [rect.position,rect.position+Vector2(rect.size.x,0),rect.end,rect.position+Vector2(0,rect.size.y)]:
		polygon.append(lab.camera.unproject_position(Vector3(p.x,0.006,p.y)))
	var count: int = 0
	for y: int in a.get_height():
		for x: int in a.get_width():
			if Geometry2D.is_point_in_polygon(Vector2(x+0.5,y+0.5),polygon) and a.get_pixel(x,y)!=b.get_pixel(x,y):
				count += 1
	return count

func set_fixture(stage: int, growth_: int) -> void:
	for rect: Rect2i in [Rect2i(24,23,10,3),Rect2i(24,31,10,3)]:
		for y: int in range(rect.position.y,rect.end.y):
			for x: int in range(rect.position.x,rect.end.x):
				var index: int = lab.session.state.index_of(x,y)
				lab.session.state.set_stage(index,stage)
				lab.session.state.growth[index] = growth_
	lab.ground_view.refresh(lab.session.state)
	lab.update_hud()

func run() -> void:
	lab = Scene.instantiate()
	lab.automatic = false
	root.add_child(lab)
	if DisplayServer.get_name()=="headless" or RenderingServer.get_video_adapter_name().is_empty():
		print("GPU NOT_RUN: structural parse only")
		quit(2)
		return
	var state_before: PackedByteArray = var_to_bytes(lab.session.state.to_dict())
	var landing_before: int = lab.session.play.landing_counter
	var normal_on: Image = await capture("pond_normal_reflection_ON",true)
	lab.water_surface.set_reflection(false)
	var normal_off: Image = await capture("pond_normal_reflection_OFF")
	check(pond_difference(normal_on,normal_off)>10,"pond.reflection_toggle_GPU")
	lab.water_surface.set_reflection(true)
	# Only a test fixture, located on the physical reflection ray into the existing pond.
	var fixture: MeshInstance3D = Geometry.box(lab.world,"ReflectionTestOnly",Vector3(-7.8,0.8,3.0),Vector3(0.5,1.6,0.5),Geometry.material(Color("c95343")))
	fixture.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var fixture_on: Image = await capture("pond_test_fixture_ON")
	fixture.hide()
	var fixture_off: Image = await capture("pond_test_fixture_OFF")
	var changes: int = pond_difference(fixture_on,fixture_off)
	check(changes>15,"pond.actual_geometry_reflection","test box changes %d pixels INSIDE the unchanged pond; box casts no shadow" % changes)
	fixture.free()
	check(state_before==var_to_bytes(lab.session.state.to_dict()) and landing_before==lab.session.play.landing_counter,"reflection.state_RNG_unchanged")
	for item: Vector2i in [Vector2i(1,0),Vector2i(2,45000),Vector2i(4,120000)]:
		set_fixture(item.x,item.y)
		await capture("soil_pavement_stage_"+str(item.x))
	var paved: int = lab.session.state.index_of(26,24)
	var soil: int = lab.session.state.index_of(26,32)
	check(lab.session.state.target[paved]==lab.session.state.target[soil] and lab.session.state.stage[paved]==lab.session.state.stage[soil] and lab.session.state.growth[paved]==lab.session.state.growth[soil],"terrain.same_logical_stage_rate")
	var counts: Array[int] = [0,0]
	for tile: int in [paved,soil]:
		for k: int in 3:
			for node: MultiMeshInstance3D in lab.ground_view.grass:
				if node.multimesh.get_instance_transform(tile*3+k).basis.get_scale().length()>0.01:
					counts[0 if tile==paved else 1] += 1
	check(counts==[1,3],"terrain.shared_grass_sparse_vs_soil","mature visible clumps pavement/soil = %s" % str(counts))
	var before_script: GDScript = load(OUT+"before/scripts/greening_map/ground_view.gd")
	var old_view: Node3D = before_script.new()
	lab.world.add_child(old_view)
	old_view.hide()
	old_view.setup(lab.session.state)
	var unchanged_soil: bool = old_view.samples==lab.ground_view.samples
	for k: int in 3:
		for variant: int in 2:
			unchanged_soil = unchanged_soil and old_view.grass[variant].multimesh.get_instance_transform(soil*3+k).is_equal_approx(lab.ground_view.grass[variant].multimesh.get_instance_transform(soil*3+k))
	check(unchanged_soil,"soil.original_samples_transforms_preserved")
	old_view.free()
	state_before = var_to_bytes(lab.session.state.to_dict())
	lab.ground_view.refresh(lab.session.state)
	lab.azimuth_slider.value = 135
	await capture("terrain_sun135")
	check(state_before==var_to_bytes(lab.session.state.to_dict()),"view_light.state_unchanged")
	lab.water_surface.reflection_view.get_texture().get_image().save_png(OUT+"reflection_pass_320.png")
	var f: FileAccess = FileAccess.open(OUT+"gpu-results.json",FileAccess.WRITE)
	f.store_string(JSON.stringify({"adapter":RenderingServer.get_video_adapter_name(),"results":results,"failures":failures},"\t"))
	f = FileAccess.open(OUT+"raw.json",FileAccess.WRITE)
	f.store_string(JSON.stringify(raw,"\t"))
	quit(0 if failures==0 else 1)
