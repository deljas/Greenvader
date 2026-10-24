extends "res://tests/greening_map/terrain_water_self_capture.gd"
## Only reflection affected by actual World3D sharing; terrain checks already passed.
func run() -> void:
	lab = Scene.instantiate()
	lab.automatic = false
	root.add_child(lab)
	if DisplayServer.get_name()=="headless":
		quit(2)
		return
	var state_before: PackedByteArray = var_to_bytes(lab.session.state.to_dict())
	var normal_on: Image = await capture("normal_reflection_ON",true)
	lab.water_surface.reflection_view.get_texture().get_image().save_png(OUT+"reflection_pass_320.png")
	lab.water_surface.set_reflection(false)
	var normal_off: Image = await capture("normal_reflection_OFF")
	check(pond_difference(normal_on,normal_off)>10,"pond.reflection_toggle_GPU")
	lab.water_surface.set_reflection(true)
	var fixture: MeshInstance3D = Geometry.box(lab.world,"ReflectionTestOnly",Vector3(-7.8,0.8,3.0),Vector3(0.5,1.6,0.5),Geometry.material(Color("c95343")))
	fixture.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var fixture_on: Image = await capture("pond_test_fixture_ON")
	lab.water_surface.reflection_view.get_texture().get_image().save_png(OUT+"reflection_test_fixture_320.png")
	fixture.hide()
	var fixture_off: Image = await capture("pond_test_fixture_OFF")
	var changed: int = pond_difference(fixture_on,fixture_off)
	check(changed>15,"pond.actual_geometry_reflection","box changes %d pixels inside pond, no shadow" % changed)
	fixture.free()
	# A sample point on the water plane must share projected horizontal location,
	# with vertical mirror reversal between main and reflection cameras.
	var point: Vector3 = Vector3(0.2,0.006,2.2)
	var main_uv: Vector2 = lab.camera.unproject_position(point)/Vector2(640,360)
	var reflection_uv: Vector2 = lab.water_surface.reflection_camera.unproject_position(point)/Vector2(320,180)
	check(absf(main_uv.x-reflection_uv.x)<0.00001 and absf(main_uv.y+reflection_uv.y-1.0)<0.00001,"reflection.plane_projection_mapping")
	check(lab.water_surface.reflection_view.find_world_3d()==lab.render_view.find_world_3d() and lab.water_surface.reflection_camera.cull_mask==1,"reflection.actual_world_and_exclusions")
	var puddle: MeshInstance3D = lab.water_surface.puddle
	var p: Vector3 = puddle.global_position
	var logic: Vector2 = Session.to_logic(Vector2(p.x,p.z))
	var index: int = lab.session.state.index_of(floori(logic.x/4),floori(logic.y/4))
	check(lab.session.state.terrain[index]==6 and lab.session.state.is_walkable(index%48,index/48) and puddle.material_override==lab.water_surface.surfaces[0].material_override,"puddle.visual_only_shared_texture")
	lab.azimuth_slider.value = 135
	await capture("normal_sun135")
	lab.water_surface.reflection_view.get_texture().get_image().save_png(OUT+"reflection_sun135_320.png")
	check(state_before==var_to_bytes(lab.session.state.to_dict()),"reflection_light_puddle.state_unchanged")
	var f: FileAccess = FileAccess.open(OUT+"reflection-results.json",FileAccess.WRITE)
	f.store_string(JSON.stringify({"results":results,"failures":failures,"pond_bounds":str(lab.water_surface.pond_bounds),"puddle_position":str(p),"reflection_mask":lab.water_surface.reflection_camera.cull_mask},"\t"))
	f = FileAccess.open(OUT+"reflection-raw.json",FileAccess.WRITE)
	f.store_string(JSON.stringify(raw,"\t"))
	quit(0 if failures==0 else 1)
