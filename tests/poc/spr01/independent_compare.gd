extends SceneTree
## Independent SPR-01 GPU acceptance. Engine input only; isolated res:// save folder.
const Save: GDScript = preload("res://scripts/poc/save/poc_save.gd")
const OUT: String = "res://evidence/spr01/independent/walk-compare-gpu/"
const SAVE_DIR: String = "res://evidence/spr01/independent/walk-compare-save/"
var main: Node
var checks: Array[Dictionary] = []
var failed: int = 0

func _init() -> void:
	root.unfocusable = true
	_run.call_deferred()

func check(label: String, ok: bool, detail: Variant = null) -> void:
	checks.append({"name": label, "status": "PASS" if ok else "FAIL", "detail": detail})
	failed += 0 if ok else 1
	print("PASS " if ok else "FAIL ", label, " ", detail)

func wait_draw() -> void:
	for i: int in 4:
		await process_frame
	await RenderingServer.frame_post_draw

func shot(label: String) -> Image:
	await wait_draw()
	var im: Image = main.render_view.get_texture().get_image()
	im.save_png(OUT + label + ".png")
	return im

func game_state() -> Dictionary:
	var value: Dictionary = Save.capture(main.session)
	value.erase("saved_at")
	return value

func mouse(content: Vector2) -> void:
	var ev: InputEventMouseMotion = InputEventMouseMotion.new()
	ev.position = root.get_final_transform() * content
	Input.parse_input_event(ev)
	await wait_draw()
	main.tick(0.0, Vector2.ZERO)

func key(code: Key) -> void:
	var ev: InputEventKey = InputEventKey.new()
	ev.physical_keycode = code
	ev.pressed = true
	Input.parse_input_event(ev)
	await wait_draw()
	ev.pressed = false
	Input.parse_input_event(ev)
	await wait_draw()

func luminance(im: Image, rect: Rect2i) -> float:
	var total: float = 0.0
	for y: int in range(rect.position.y, rect.end.y):
		for x: int in range(rect.position.x, rect.end.x):
			var c: Color = im.get_pixel(x,y)
			total += c.r + c.g + c.b
	return total

func difference(a: Image, b: Image, rect: Rect2i) -> float:
	var total: float = 0.0
	for y: int in range(rect.position.y, rect.end.y):
		for x: int in range(rect.position.x, rect.end.x):
			var c: Color = a.get_pixel(x,y) - b.get_pixel(x,y)
			total += absf(c.r) + absf(c.g) + absf(c.b)
	return total

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		print("NOT_RUN GPU: headless display")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(OUT)
	main = load("res://scenes/poc.tscn").instantiate()
	main.auto_process = false
	main.save_dir = SAVE_DIR
	main.set_meta(&"poc_town", true)
	root.add_child(main)
	main.audio.muted = true
	await wait_draw()
	check("startup_640_default_normal", main.current_resolution()==Vector2i(640,360) and main.render_view.size==Vector2i(640,360) and main.walk_mode==0)
	check("integer_window_nearest", root.content_scale_size==Vector2i(640,360) and root.content_scale_stretch==Window.CONTENT_SCALE_STRETCH_INTEGER and main.actor.display_sprite.texture_filter==BaseMaterial3D.TEXTURE_FILTER_NEAREST)
	check("old_resolution_cannot_be_selected", not main.set_resolution(1) and main.current_resolution()==Vector2i(640,360))
	var origin: Vector2 = main.session.position
	main.tick(0.125, Vector2.RIGHT)
	var delta_normal: Vector2 = main.session.position-origin
	check("moving_8fps_frame1", main.walking and main.actor.frame==1 and delta_normal.length()>0.0)
	var state_before: Dictionary = game_state()
	var foot_before: Vector3 = main.actor.render_foot
	var phase_before: float = main.animation_time
	await key(KEY_F6)
	check("F6_display_only", main.walk_mode==1 and game_state()==state_before and main.actor.render_foot.is_equal_approx(foot_before) and main.animation_time==phase_before)
	main.session.position = origin
	main.animation_time = 0.0
	main.tick(0.125, Vector2.RIGHT)
	var delta_hop: Vector2 = main.session.position-origin
	check("same_motion_and_collision_configuration", delta_hop.is_equal_approx(delta_normal), {"normal":delta_normal,"hop":delta_hop})
	main.walk_button.pressed.emit()
	check("button_returns_normal", main.walk_mode==0)
	var face: Vector2 = main.camera.unproject_position(main.player_ground3()+Vector3.UP*0.04)-Vector2(0,10)
	var dirs: Array[StringName] = [&"up", &"right", &"down", &"left"]
	var offsets: Array[Vector2] = [Vector2(0,-60),Vector2(60,0),Vector2(0,60),Vector2(-60,0)]
	var directions_ok: bool = true
	for i: int in 4:
		var target: Vector2 = face+offsets[i]
		await mouse(target)
		directions_ok = directions_ok and main._cursor_screen.distance_to(target)<0.01 and main.actor.direction==dirs[i] and not main.actor.display_sprite.flip_h
	check("engine_mouse_four_directions", directions_ok)
	main.tick(0.125, Vector2.RIGHT)
	check("left_facing_right_movement", main.actor.direction==&"left" and main.walking)
	main.tick(0.0, Vector2.ZERO)
	check("stop_uses_adopted_idle", main.actor.frame==0 and not main.actor.walking and (main.actor.display_sprite.texture as AtlasTexture).atlas.resource_path.ends_with("idle.png"))
	var pose_ok: bool = true
	var grid_ok: bool = true
	var pose_foot: Vector3 = main.player_ground3()+Vector3.UP*0.04
	for mode: int in 2:
		for direction: StringName in [&"down",&"left",&"right",&"up"]:
			for frame: int in 4:
				main.actor.pose(pose_foot,frame,direction,main.sun,mode,true)
				var display: Sprite3D = main.actor.display_sprite
				var shadow: Sprite3D = main.actor.shadow_board
				var folder: String = "walk-normal-v1" if mode==0 else "walk-v1"
				var expected: Image = Image.load_from_file("res://assets/concepts/spr01/%s/%s-%d.png" % [folder,direction,frame])
				var actual: Image = display.texture.get_image()
				actual.convert(Image.FORMAT_RGBA8)
				expected.convert(Image.FORMAT_RGBA8)
				pose_ok = pose_ok and actual.get_data()==expected.get_data() and display.texture==shadow.texture and display.global_position.is_equal_approx(shadow.global_position) and not display.flip_h and not shadow.flip_h
				var top: Vector2 = main.camera.unproject_position(display.to_global(Vector3(-12,18,0)*display.pixel_size))
				var bottom: Vector2 = main.camera.unproject_position(display.to_global(Vector3(12,-18,0)*display.pixel_size))
				var anchor: Vector2 = main.camera.unproject_position(main.actor.render_foot)
				grid_ok = grid_ok and (bottom-top).is_equal_approx(Vector2(24,36)) and anchor.distance_to(anchor.round())<0.001 and (top+Vector2(12,34)).is_equal_approx(anchor)
	check("32_poses_match_original_and_shadow", pose_ok)
	check("native_24x36_fixed_integer_ground_anchor", grid_ok)
	main._cursor_known = false
	main.facing = &"down"
	main.set_text_visible(false)
	main.tick(0.0,Vector2.ZERO)
	for mode: int in 2:
		main.walk_mode=mode
		main.walking=true
		main.animation_time=0.25
		main._update_actor()
		await shot("normal_phase2" if mode==0 else "hop_phase2")
	main.walking=false
	main.walk_mode=0
	main._update_actor()
	var screen: Vector2 = main.camera.unproject_position(main.actor.render_foot)
	var face_rect: Rect2i = Rect2i(Vector2i(screen)-Vector2i(8,14),Vector2i(16,10))
	var lit: Image = await shot("day_card_on")
	main.actor.shadow_board.visible=false
	var no_card: Image = await shot("day_card_off")
	var self_diff: float = difference(lit,no_card,face_rect)
	var ground_diff: float = difference(lit,no_card,Rect2i(0,0,640,360))
	check("no_crossed_self_shadow_on_face", self_diff<0.1,self_diff)
	check("player_casts_world_shadow",ground_diff>0.1,ground_diff)
	main.actor.shadow_board.visible=true
	var caster: MeshInstance3D = MeshInstance3D.new()
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size=Vector3(3,5,3)
	caster.mesh=mesh
	caster.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	caster.layers=1
	main.world.add_child(caster)
	caster.global_position=pose_foot+main.sun.global_basis.z*3.0+Vector3.UP
	var shade: Image=await shot("external_mesh_shadow")
	var darkening: float=luminance(lit,face_rect)-luminance(shade,face_rect)
	check("receives_external_3d_shadow",darkening>0.5,darkening)
	caster.free()
	var prior_clock: Dictionary=main.session.clock.to_dict()
	main.session.clock.elapsed=360.0
	main.env_view.sync()
	main._update_actor()
	var receiver: DirectionalLight3D=main.actor.receiver_light
	check("night_light_and_reflection_masks", receiver.global_transform.is_equal_approx(main.sun.global_transform) and receiver.light_color.is_equal_approx(main.sun.light_color) and is_equal_approx(receiver.light_energy,main.sun.light_energy) and receiver.visible==main.sun.visible and receiver.shadow_caster_mask==1 and receiver.light_cull_mask==64 and main.sun.light_cull_mask & 64 == 0 and main.water_view.reflection_camera.cull_mask & 64 != 0 and main.occlusion_view.reflection_mask_during_draw() & 64 != 0)
	await shot("night")
	main.session.clock.load_dict(prior_clock)
	main.env_view.sync()
	main._update_actor()
	var save_result: Dictionary=Save.save(main.session,SAVE_DIR,{"resolution_index":1})
	var pos_before: Vector2=main.session.position
	var load_result: Dictionary=main.load_game(false)
	check("legacy_index1_save_load_640",bool(save_result.ok) and bool(load_result.ok) and main.current_resolution()==Vector2i(640,360) and main.session.position.is_equal_approx(pos_before))
	main.session.paused=true
	var paused: Dictionary=game_state()
	main.tick(0.125,Vector2.RIGHT)
	check("pause_keeps_logic_and_idle",game_state()==paused and main.actor.frame==0 and not main.actor.walking)
	main.session.paused=false
	main.session.play.seeds=0
	main.session.play.water=0.0
	var seed: Dictionary=main.session.fire(false,main.session.position+Vector2(4,0))
	var water: Dictionary=main.session.fire(true,main.session.position+Vector2(4,0))
	check("zero_resources_still_block_fire",not bool(seed.ok) and not bool(water.ok))
	main.set_text_visible(true)
	await wait_draw()
	root.get_texture().get_image().save_png(OUT+"controls.png")
	check("controls_fit_internal_width",main.button_box.get_global_rect().end.x<=640.0 and main.button_box.position.x>=0.0)
	var file: FileAccess=FileAccess.open(OUT+"results.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failed,"renderer":RenderingServer.get_video_adapter_name(),"display":DisplayServer.get_name(),"face_rect":face_rect,"frame_screen_anchor":screen},"\t"))
	file.close()
	main.session.close()
	main.queue_free()
	await process_frame
	print("RESULT failures=",failed)
	quit(1 if failed else 0)
