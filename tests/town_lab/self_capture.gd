extends SceneTree
const Scene: PackedScene = preload("res://scenes/town_lab.tscn")
const Cycle: GDScript = preload("res://scripts/town_lab/day_cycle.gd")
const OUT: String = "res://evidence/town-lab/self/"
var lab: Node
var checks: Array[Dictionary] = []
var raw: Array[Dictionary] = []
var failures: int = 0

func _initialize() -> void:
	root.unfocusable = true
	create_timer(100).timeout.connect(func() -> void: quit(99))
	run.call_deferred()

func check(ok: bool, id: String, detail: String = "") -> void:
	checks.append({"id":id,"status":"PASS" if ok else "FAIL","detail":detail})
	if not ok: failures += 1
	print(checks[-1])

func key(code: Key, pressed: bool) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)

func capture(label: String) -> Image:
	await lab.wait_render()
	var image_: Image = lab.render_view.get_texture().get_image()
	image_.save_png(OUT+label+"_640.png")
	var ui: Image = root.get_texture().get_image()
	ui.resize(1920,1080,Image.INTERPOLATE_NEAREST)
	ui.save_png(OUT+label+"_ui_1920.png")
	raw.append({"label":label,"hour":lab.hour,"position":str(lab.position),"camera":str(lab.camera.global_position),"sun":str(lab.sun.position),"sun_visible":lab.sun.visible,"sun_energy":lab.sun.light_energy,"moon_energy":lab.moon.light_energy,"actor":lab.actor.snapshot()})
	return image_

func changed(a: Image,b: Image) -> int:
	var count: int = 0
	for y: int in range(a.get_height()):
		for x: int in range(a.get_width()):
			if a.get_pixel(x,y)!=b.get_pixel(x,y): count += 1
	return count

func brightness(image_: Image) -> float:
	var total: float = 0
	for y: int in range(image_.get_height()):
		for x: int in range(image_.get_width()):
			var c: Color = image_.get_pixel(x,y)
			total += (c.r+c.g+c.b)/3
	return total/(image_.get_width()*image_.get_height())

func run() -> void:
	lab = Scene.instantiate()
	lab.automatic = false
	root.add_child(lab)
	if lab.actor==null:
		quit(3)
		return
	# Stabilize initial unfocusable-window focus notifications before injecting keys.
	await lab.wait_render()
	if "--contact" in OS.get_cmdline_user_args():
		var previous: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(OUT+"results.json"))
		checks.assign(previous["checks"])
		await contact_run()
		return
	if "--repair" in OS.get_cmdline_user_args():
		var previous: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(OUT+"initial-results.json"))
		for old: Dictionary in previous["checks"]:
			if old["status"]=="PASS": checks.append(old)
		await repair_run()
		return
	check(not lab.blocked(lab.START),"start_clear")
	var buildings: Array[Dictionary] = []
	var unique: Dictionary = {}
	var placement_data: Array[Dictionary] = []
	for entry: Dictionary in lab.placements:
		var bounds: AABB = entry["bounds"]
		if entry["kind"]=="building":
			buildings.append(entry)
			unique[entry["id"]] = true
			check(absf(bounds.position.y)<0.001,entry["id"]+"_grounded")
			var point: Vector3 = entry["entry"]+entry["entry_direction"]*0.95
			check(not lab.blocked(Vector2(point.x,point.z)),entry["id"]+"_entry_approach",str(point))
		placement_data.append({"id":entry["id"],"kind":entry["kind"],"bounds_min":str(bounds.position),"bounds_size":str(bounds.size),"entry":str(entry["entry"]),"scale":str(entry["model"].scale),"collision_rectangles":entry["collision_rectangles"]})
	check(buildings.size()==7 and unique.size()>=4,"seven_diverse_buildings")
	var overlap: bool = false
	for i: int in range(buildings.size()):
		for j: int in range(i+1,buildings.size()):
			var a: AABB = buildings[i]["bounds"]
			var b: AABB = buildings[j]["bounds"]
			overlap = overlap or a.intersects(b)
	check(not overlap,"buildings_no_major_overlap")
	check(lab.water.surfaces.size()==4 and lab.lamps.size()==4,"four_irregular_puddles_four_lamps")
	# Actual input event path through the lab's _input, fixed short stepping.
	lab.set_playing(false)
	lab.position = Vector2.ZERO
	key(KEY_D,true)
	await process_frame
	lab.step(0.2)
	key(KEY_D,false)
	await process_frame
	var straight: float = lab.position.length()
	lab.position = Vector2.ZERO
	key(KEY_RIGHT,true)
	key(KEY_DOWN,true)
	await process_frame
	lab.step(0.2)
	key(KEY_RIGHT,false)
	key(KEY_DOWN,false)
	await process_frame
	check(absf(lab.position.length()-straight)<0.001 and straight>0.6,"normalized_diagonal_input",str(straight," / ",lab.position.length()))
	check(lab.actor.snapshot()["matching_texture"] and lab.actor.snapshot()["matching_feet"],"walking_sprite_shadow_sync")
	var car: Rect2 = Rect2()
	for entry: Dictionary in lab.placements:
		if entry["id"]=="PRP-041":
			var b: AABB = entry["bounds"]
			car = Rect2(Vector2(b.position.x,b.position.z),Vector2(b.size.x,b.size.z))
	lab.position = Vector2(car.position.x-lab.RADIUS-0.2,car.get_center().y)
	lab.move_world(Vector2(2,0))
	check(lab.position.x<car.position.x-lab.RADIUS and not lab.blocked(lab.position),"large_prop_collision")
	lab.position = Vector2(23.7,0)
	lab.move_world(Vector2(3,0))
	check(lab.position.x<=24.45-lab.RADIUS,"boundary_collision")
	lab.reset_position()
	var fixed: Vector3 = lab.camera.global_position
	lab.position += Vector2(0.5,0.5)
	lab._update_camera()
	check(lab.camera.global_position.distance_to(fixed)>0.4,"camera_follows")
	var height: float = lab.actor.snapshot()["height"]
	lab.zoom(0.85)
	check(absf(lab.actor.snapshot()["height"]-height)<0.001 and lab.actor.display_sprite.shaded,"zoom_fixed_human_height_shaded")
	lab.follow_size = 18.5
	lab.reset_position()
	# One complete 120s cycle using 1s simulation steps, not wall-clock wait.
	lab.set_hour(12)
	lab.set_playing(true)
	for i: int in range(120): lab.advance_time(1)
	check(absf(lab.hour-12)<0.001,"one_120_second_cycle_fixed_step")
	lab.set_playing(false)
	var paused: float = lab.hour
	lab.advance_time(10)
	check(lab.hour==paused,"time_pause")
	var dawn: Dictionary = Cycle.state(7)
	var noon: Dictionary = Cycle.state(12)
	var dusk: Dictionary = Cycle.state(17)
	check(dawn["source"].dot(Cycle.EAST)>0 and noon["source"].dot(Cycle.SOUTH)>0.5 and dusk["source"].dot(Cycle.WEST)>0,"east_south_west_source")
	check(-dawn["source"].dot(Cycle.EAST)<0 and -noon["source"].dot(Cycle.SOUTH)<0 and -dusk["source"].dot(Cycle.WEST)<0,"opposite_shadow_compass")
	check(Cycle.state(0)==Cycle.state(24),"wrap_and_determinism")
	lab.set_hour(22)
	check(not lab.sun.visible and lab.sun.light_energy==0 and lab.moon.visible and lab.lamps[0].light_energy>0,"night_no_underground_sun")
	FileAccess.open(OUT+"placements.json",FileAccess.WRITE).store_string(JSON.stringify(placement_data,"\t"))
	if DisplayServer.get_name()=="headless" or RenderingServer.get_video_adapter_name().is_empty():
		print("GPU NOT_RUN")
		quit(2)
		return
	lab.toggle_camera()
	var day: Image
	var night: Image
	for item: Array in [["morning",7.0],["noon",12.0],["evening",17.0],["night",22.0]]:
		lab.time_slider.value = item[1]
		var image_: Image = await capture(item[0]+"_overview")
		if item[0]=="noon": day=image_
		if item[0]=="night": night=image_
	check(brightness(night)<brightness(day)*0.8 and brightness(night)>0.02,"night_darker_but_visible",str(brightness(day)," / ",brightness(night)))
	var expected: Image = night.duplicate()
	expected.resize(1920,1080,Image.INTERPOLATE_NEAREST)
	check(expected.get_data()==lab.doubled_view.get_texture().get_image().get_data(),"nearest3_exact")
	lab.toggle_camera()
	lab.position = Vector2(2,0.8)+Vector2(Cycle.SOUTH.x,Cycle.SOUTH.z)*0.7
	lab.follow_size = 13.5
	lab._update_camera()
	lab.set_hour(12)
	var shadow_on: Image = await capture("water_day_shadow")
	lab.water.material_.set_shader_parameter("receive_shadow",false)
	var shadow_off: Image = await capture("water_day_shadow_OFF")
	check(changed(shadow_on,shadow_off)>3,"water_day_receives_shadow",str(changed(shadow_on,shadow_off)))
	lab.water.material_.set_shader_parameter("receive_shadow",true)
	lab.set_hour(22)
	var lamp_shadow: Image = await capture("water_night_lamps")
	lab.water.material_.set_shader_parameter("receive_shadow",false)
	var lamp_clear: Image = await capture("water_night_shadow_OFF")
	check(changed(lamp_shadow,lamp_clear)>3,"water_night_local_shadow",str(changed(lamp_shadow,lamp_clear)))
	lab.water.material_.set_shader_parameter("receive_shadow",true)
	lab.position = Vector2(-4.7,-10.7)
	lab._update_camera()
	lab.set_hour(12)
	var reflection: Image = await capture("water_building_reflection")
	lab.water.set_reflection(false)
	var no_reflection: Image = await capture("water_reflection_OFF")
	check(changed(reflection,no_reflection)>10,"building_reflection_present",str(changed(reflection,no_reflection)))
	lab.water.set_reflection(true)
	var matrix_before: Variant = lab.water.material_.get_shader_parameter("reflection_view_projection")
	lab.position += Vector2(1,0)
	lab._update_camera()
	check(matrix_before!=lab.water.material_.get_shader_parameter("reflection_view_projection"),"reflection_follows_camera")
	FileAccess.open(OUT+"results.json",FileAccess.WRITE).store_string(JSON.stringify({"adapter":RenderingServer.get_video_adapter_name(),"checks":checks,"failures":failures,"NOT_RUN":["physical_keyboard_OS","performance_full_angles","game_save_combat_growth_integration","user_art_approval"]},"\t"))
	FileAccess.open(OUT+"raw.json",FileAccess.WRITE).store_string(JSON.stringify(raw,"\t"))
	lab.free()
	await process_frame
	quit(0 if failures==0 else 1)

func repair_run() -> void:
	lab.set_playing(false)
	lab.position = Vector2.ZERO
	key(KEY_D,true)
	await process_frame
	lab.step(0.2)
	key(KEY_D,false)
	await process_frame
	var straight: float = lab.position.length()
	lab.position = Vector2.ZERO
	key(KEY_RIGHT,true)
	key(KEY_DOWN,true)
	await process_frame
	lab.step(0.2)
	key(KEY_RIGHT,false)
	key(KEY_DOWN,false)
	await process_frame
	check(absf(lab.position.length()-straight)<0.001 and straight>0.6,"normalized_diagonal_input",str(straight," / ",lab.position.length()))
	lab.reset_position()
	lab.toggle_camera()
	for item: Array in [["morning",7.0],["noon",12.0],["evening",17.0],["night",22.0]]:
		lab.set_hour(item[1])
		await capture(item[0]+"_overview")
	lab.toggle_camera()
	lab.position = Vector2(2,0.8)+Vector2(Cycle.SOUTH.x,Cycle.SOUTH.z)*0.7
	lab.follow_size = 13.5
	lab._update_camera()
	lab.set_hour(12)
	var day: Image = await capture("water_day_shadow")
	lab.water.material_.set_shader_parameter("receive_shadow",false)
	var day_off: Image = await capture("water_day_shadow_OFF")
	check(changed(day,day_off)>3,"water_day_receives_shadow",str(changed(day,day_off)))
	lab.water.material_.set_shader_parameter("receive_shadow",true)
	lab.set_hour(22)
	var night: Image = await capture("water_night_lamps")
	lab.water.material_.set_shader_parameter("receive_shadow",false)
	var night_off: Image = await capture("water_night_shadow_OFF")
	check(changed(night,night_off)>3,"water_night_local_shadow_repair",str(changed(night,night_off)))
	lab.water.material_.set_shader_parameter("receive_shadow",true)
	lab.position = Vector2(-4.7,-10.7)
	lab._update_camera()
	lab.set_hour(12)
	var reflection: Image = await capture("water_building_reflection")
	lab.water.set_reflection(false)
	var off: Image = await capture("water_reflection_OFF")
	check(changed(reflection,off)>10,"building_reflection_repair",str(changed(reflection,off)))
	lab.water.set_reflection(true)
	FileAccess.open(OUT+"results.json",FileAccess.WRITE).store_string(JSON.stringify({"adapter":RenderingServer.get_video_adapter_name(),"checks":checks,"failures":failures,"prior_pass_reused":true,"NOT_RUN":["physical_keyboard_OS","performance_full_angles","game_save_combat_growth_integration","user_art_approval"]},"\t"))
	FileAccess.open(OUT+"raw-repair.json",FileAccess.WRITE).store_string(JSON.stringify(raw,"\t"))
	lab.free()
	await process_frame
	quit(0 if failures==0 else 1)

func contact_run() -> void:
	lab.set_playing(false)
	lab.position = Vector2(-5.8,-12)
	var start: Vector2 = lab.position
	var motion: Vector2 = lab.move_world(Vector2(-3,0))
	check(motion.length()>0.1 and motion.length()<2 and not lab.blocked(lab.position),"known_building_wall_stops",str(start," -> ",lab.position))
	var wall_stop: Vector2 = lab.position
	lab.position = Vector2.ZERO
	var clear: bool = true
	var total: float = 0
	for point: Vector2 in [Vector2(0,10),Vector2(0,16),Vector2(6,16),Vector2(6,6),Vector2(0,6),Vector2.ZERO]:
		total += lab.move_world(point-lab.position).length()
		clear = clear and lab.position.distance_to(point)<0.01 and not lab.blocked(lab.position)
	check(clear and total>40 and lab.position.length()<0.01,"main_crossing_side_alley_short_loop",str(total))
	lab.position = wall_stop
	lab._update_camera()
	lab.set_hour(12)
	lab._update_actor(0.2)
	await capture("building_wall_contact")
	lab.position = Vector2(-4.7,-10.7)
	lab.follow_size = 13.5
	lab._update_camera()
	lab.set_hour(22)
	lab._update_actor(0.2)
	await capture("water_night_building_reflection")
	FileAccess.open(OUT+"results.json",FileAccess.WRITE).store_string(JSON.stringify({"adapter":RenderingServer.get_video_adapter_name(),"checks":checks,"failures":failures,"prior_pass_reused":true,"NOT_RUN":["physical_keyboard_OS","performance_full_angles","game_save_combat_growth_integration","user_art_approval"]},"\t"))
	FileAccess.open(OUT+"raw-contact.json",FileAccess.WRITE).store_string(JSON.stringify(raw,"\t"))
	lab.free()
	await process_frame
	quit(0 if failures==0 else 1)
