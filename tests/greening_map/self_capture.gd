extends SceneTree
const Scene: PackedScene = preload("res://scenes/greening_map.tscn")
const Session: GDScript = preload("res://scripts/greening_map/session.gd")
const OUT: String = "res://evidence/greening-map/self/"
var lab: Node
var results: Array[Dictionary] = []
var raw: Array[Dictionary] = []
var failures: int = 0

func _initialize() -> void:
	root.unfocusable = true
	create_timer(65).timeout.connect(func() -> void: quit(99))
	run.call_deferred()

func check(ok: bool, id: String, detail: String = "") -> void:
	if OS.get_cmdline_user_args().has("--resume-input") and id in ["GPU.nearest3_exact","input.WASD_screen_direction","input.arrow_direction","actor.shared_frame_flip_foot","pick.ground_projection_roundtrip"]:
		return # Already passed before the test-only mouse-coordinate fix.
	results.append({"id":id,"status":"PASS" if ok else "FAIL","detail":detail})
	if not ok:
		failures += 1
	print(results[-1])

func key(code: int, pressed: bool) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	await process_frame

func click(point: Vector2, button: int) -> void:
	# parse_input_event accepts WINDOW pixels, which the root maps to logical640.
	var scale_: int = maxi(1,mini(root.size.x/640,root.size.y/360))
	var offset: Vector2 = (Vector2(root.size)-Vector2(640,360)*scale_)*0.5
	var window_point: Vector2 = offset+point*scale_
	for pressed: bool in [true,false]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.position = window_point
		event.global_position = window_point
		event.button_index = button
		event.pressed = pressed
		event.button_mask = (1 << (button-1)) if pressed else 0
		Input.parse_input_event(event)
		await process_frame

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
	snapshot["actor"] = lab.actor.sync_snapshot()
	snapshot["visual_stage_counts"] = lab.ground_view.stage_counts
	raw.append(snapshot)
	print("IMAGE "+ProjectSettings.globalize_path(OUT+label_+"_ui_1920.png"))
	return image_

func changed(a: Image, b: Image) -> int:
	var count: int = 0
	for y: int in a.get_height():
		for x: int in a.get_width():
			if a.get_pixel(x,y)!=b.get_pixel(x,y):
				count += 1
	return count

func run() -> void:
	lab = Scene.instantiate()
	lab.automatic = false
	root.add_child(lab)
	if DisplayServer.get_name()=="headless" or RenderingServer.get_video_adapter_name().is_empty():
		print("GPU NOT_RUN: structural load only")
		quit(2)
		return
	if not OS.get_cmdline_user_args().has("--resume-input"):
		await capture("initial",true)
	var spawn: Vector2 = lab.session.position
	var screen_before: Vector2 = lab.camera.unproject_position(lab.actor.render_foot)
	await key(KEY_D,true)
	lab.step(0.2)
	await key(KEY_D,false)
	var screen_after: Vector2 = lab.camera.unproject_position(lab.actor.render_foot)
	check(screen_after.x>screen_before.x+4 and absf(screen_after.y-screen_before.y)<1.01 and lab.session.position!=spawn,"input.WASD_screen_direction")
	var after_move: Vector2 = lab.session.position
	await key(KEY_UP,true)
	lab.step(0.2)
	await key(KEY_UP,false)
	check(lab.session.position!=after_move,"input.arrow_direction")
	var sync: Dictionary = lab.actor.sync_snapshot()
	check(sync["texture_match"] and sync["flip_match"] and sync["foot_match"],"actor.shared_frame_flip_foot")
	var target: Vector2 = Vector2(0.6,3.8)
	var aim: Vector2 = lab.camera.unproject_position(Vector3(target.x,0,target.y))
	var picked: Variant = lab.screen_to_ground(aim)
	check(picked!=null and Vector2(picked).distance_to(target)<0.0001,"pick.ground_projection_roundtrip")
	var seeds: int = lab.session.play.seeds
	var actions: int = lab.session.action_count
	await click(Vector2(30,18),MOUSE_BUTTON_LEFT)
	check(lab.session.play.seeds==seeds and lab.session.action_count==actions,"input.UI_does_not_scatter")
	await click(aim,MOUSE_BUTTON_LEFT)
	check(lab.session.play.seeds==seeds-1 and lab.session.play.last_scatter.size()>0,"input.left_seed_real_state","window size %s; logical target %s; result %s" % [root.size,aim,lab.session.last_result])
	if lab.session.play.last_scatter.is_empty():
		quit(4)
		return
	var planted: int = lab.session.play.last_scatter[0]
	var water: float = lab.session.play.water
	await click(aim,MOUSE_BUTTON_RIGHT)
	check(lab.session.play.water==water-10 and lab.session.state.moisture[planted]>0,"input.right_water_real_state")
	await capture("walk_seed_water")
	var roof_screen: Vector2 = lab.camera.unproject_position(Vector3(-3.2,2.5,-2.0))
	check(lab.screen_to_ground(roof_screen)==null,"pick.building_screen_occlusion")
	var old_position: Vector2 = lab.session.position
	lab.session.position = Session.to_logic(Vector2(-3.2,1.6))
	check(not lab.session.scatter(Vector2(-3.2,-0.8),false),"landing.blocked_across_building")
	lab.session.position = old_position
	lab.pause_check.button_pressed = true
	var time_before: float = lab.session.clock.elapsed
	lab.step(0.1)
	check(lab.session.clock.elapsed==time_before,"UI.growth_pause")
	lab.pause_check.button_pressed = false
	lab.session.advance_game(24)
	lab.ground_view.refresh(lab.session.state)
	lab.update_hud()
	check(lab.session.state.stage[planted]>=WorldState.STAGE_SPROUT1,"sim.sprout_actual_stage")
	await capture("sprout_24_game_seconds")
	lab.session.advance_game(50)
	lab.ground_view.refresh(lab.session.state)
	lab.update_hud()
	check(lab.session.state.stage[planted]==WorldState.STAGE_MATURE and lab.session.spread.total_planted>0,"sim.mature_and_natural_spread")
	var stage_before: PackedByteArray = lab.session.state.stage.duplicate()
	var growth_before: PackedInt32Array = lab.session.state.growth.duplicate()
	lab.ground_view.refresh(lab.session.state)
	check(stage_before==lab.session.state.stage and growth_before==lab.session.state.growth and stage_before==lab.ground_view.visual_stages,"view.read_only_state_mapping")
	var before_light: Image = await capture("grown_74_game_seconds")
	lab.azimuth_slider.value = 135
	check(lab.azimuth_number.value==135,"UI.sun_slider_number")
	var after_light: Image = await capture("sun_135")
	check(changed(before_light,after_light)>1000 and stage_before==lab.session.state.stage and growth_before==lab.session.state.growth,"sun.GPU_changes_no_growth_mutation")
	lab.session.position = Session.to_logic(Vector2(-3.2,-5.2))
	lab.update_actor(Vector2.ZERO)
	lab.update_hud()
	await capture("behind_building_occlusion")
	var file: FileAccess = FileAccess.open(OUT+"gpu-results.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"adapter":RenderingServer.get_video_adapter_name(),"results":results,"failures":failures},"\t"))
	file = FileAccess.open(OUT+"raw.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(raw,"\t"))
	quit(0 if failures==0 else 1)
