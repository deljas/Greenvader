extends SceneTree
const Scene: PackedScene = preload("res://scenes/greening_map.tscn")
const Session: GDScript = preload("res://scripts/greening_map/session.gd")
const OUT: String = "res://evidence/wall-growth/self/"
var lab: Node
var checks: Array[Dictionary] = []
var raw: Array[Dictionary] = []
var failures: int = 0

func _initialize() -> void:
	root.unfocusable = true
	create_timer(75).timeout.connect(func() -> void: quit(99))
	run.call_deferred()

func check(ok: bool, id: String, detail: String = "") -> void:
	checks.append({"id":id,"status":"PASS" if ok else "FAIL","detail":detail})
	if not ok:
		failures += 1
	print(checks[-1])

func capture(label_: String, representative: bool = false) -> Image:
	await lab.wait_render()
	var image_: Image = lab.render_view.get_texture().get_image()
	image_.save_png(OUT+label_+"_world_640.png")
	var ui: Image = root.get_texture().get_image()
	ui.resize(1920,1080,Image.INTERPOLATE_NEAREST)
	ui.save_png(OUT+label_+"_ui_1920.png")
	if representative:
		var output: Image = lab.doubled_view.get_texture().get_image()
		output.save_png(OUT+label_+"_world_1920.png")
		var expected: Image = image_.duplicate()
		expected.resize(1920,1080,Image.INTERPOLATE_NEAREST)
		check(expected.get_data()==output.get_data(),"nearest3_exact")
	var snapshot: Dictionary = lab.wall_growth.snapshot()
	snapshot["label"] = label_
	snapshot["clock"] = lab.session.clock.elapsed
	snapshot["green"] = lab.session.state.greened_count
	snapshot["target"] = lab.session.state.target_count
	raw.append(snapshot)
	print("IMAGE "+ProjectSettings.globalize_path(OUT+label_+"_ui_1920.png"))
	return image_

func pond_delta(a: Image, b: Image) -> Dictionary:
	var rect: Rect2 = lab.water_surface.pond_bounds
	var polygon: PackedVector2Array = PackedVector2Array()
	for p: Vector2 in [rect.position,rect.position+Vector2(rect.size.x,0),rect.end,rect.position+Vector2(0,rect.size.y)]:
		polygon.append(lab.camera.unproject_position(Vector3(p.x,0.006,p.y)))
	var count: int = 0
	var sum_a: float = 0
	var sum_b: float = 0
	for y: int in a.get_height():
		for x: int in a.get_width():
			if Geometry2D.is_point_in_polygon(Vector2(x+0.5,y+0.5),polygon):
				var ca: Color = a.get_pixel(x,y)
				var cb: Color = b.get_pixel(x,y)
				if ca!=cb:
					count += 1
					sum_a += ca.r+ca.g+ca.b
					sum_b += cb.r+cb.g+cb.b
	return {"pixels":count,"first_rgb_sum":sum_a,"second_rgb_sum":sum_b}

func run() -> void:
	lab = Scene.instantiate()
	lab.automatic = false
	root.add_child(lab)
	if DisplayServer.get_name()=="headless" or RenderingServer.get_video_adapter_name().is_empty():
		print("GPU NOT_RUN")
		quit(2)
		return
	lab.session.spread.allow_hook = func(_index: int) -> bool: return false # isolate one front only
	await capture("initial_wall_zero",true)
	# Explicit mature-ground fixture only in front of A, not its right wall or B.
	for index: int in lab.session.state.tile_count():
		var p: Vector2 = Session.cell_center(index)
		if lab.session.state.target[index]==1 and p.x> -6.3 and p.x< -0.1 and p.y>0.8 and p.y<1.8:
			lab.session.state.set_stage(index,WorldState.STAGE_MATURE)
			lab.session.state.growth[index] = 120000
	lab.ground_view.refresh(lab.session.state)
	lab.update_hud()
	var counter: Vector2i = Vector2i(lab.session.state.greened_count,lab.session.state.target_count)
	lab.session.advance_game(45)
	lab.update_hud()
	await capture("front_wall_after45")
	lab.session.advance_game(90)
	lab.update_hud()
	await capture("front_wall_after135")
	var local_only: bool = true
	var front_full: bool = false
	for entry: Dictionary in lab.wall_growth.entries:
		for root: Dictionary in entry["roots"]:
			if entry["id"]=="A" and root["anchor"].y>0.8:
				front_full = front_full or root["progress"]==1
			else:
				local_only = local_only and root["progress"]==0
	check(front_full and local_only,"GPU_fixture_front_local_only")
	check(Vector2i(lab.session.state.greened_count,lab.session.state.target_count)==counter,"wall_no_counter_gain")
	# Existing character stands on valid shore; its real shadow crosses the edge.
	lab.session.paused = true
	lab.session.position = Session.to_logic(Vector2(-7.9,3.5))
	lab.azimuth_slider.value = 225
	lab.update_actor(Vector2.ZERO)
	var both_on: Image = await capture("water_reflection_shadow_ON")
	lab.water_surface.set_reflection(false)
	var shadow_only: Image = await capture("water_shadow_only")
	lab.actor.shadow_board.hide()
	var neither: Image = await capture("water_reflection_shadow_OFF")
	lab.water_surface.set_reflection(true)
	var reflection_only: Image = await capture("water_reflection_only")
	var shadow: Dictionary = pond_delta(shadow_only,neither)
	var reflected: Dictionary = pond_delta(reflection_only,neither)
	check(shadow["pixels"]>15 and shadow["first_rgb_sum"]<shadow["second_rgb_sum"],"water_real_cast_shadow_without_reflection",str(shadow))
	check(reflected["pixels"]>15,"water_reflection_without_caster_shadow",str(reflected))
	lab.actor.shadow_board.show()
	lab.azimuth_slider.value = 270
	var moved: Image = await capture("water_sun270")
	lab.water_surface.set_reflection(false)
	var shadow_270: Image = await capture("water_shadow_only_sun270")
	check(pond_delta(shadow_only,shadow_270)["pixels"]>15,"water_shadow_follows_sun")
	lab.water_surface.set_reflection(true)
	var f: FileAccess = FileAccess.open(OUT+"gpu-results.json",FileAccess.WRITE)
	f.store_string(JSON.stringify({"adapter":RenderingServer.get_video_adapter_name(),"results":checks,"failures":failures},"\t"))
	f = FileAccess.open(OUT+"gpu-raw.json",FileAccess.WRITE)
	f.store_string(JSON.stringify(raw,"\t"))
	quit(0 if failures==0 else 1)
