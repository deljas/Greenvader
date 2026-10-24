extends SceneTree
## Limited independent verification. Only engine input; isolated settings/save directory.
const Session: GDScript = preload("res://scripts/poc/poc_session.gd")
const Action: GDScript = preload("res://scripts/poc/poc_fire_action.gd")
const Coords: GDScript = preload("res://scripts/poc/poc_coords.gd")
const Audio: GDScript = preload("res://scripts/poc/audio/poc_audio.gd")
const OUT: String = "res://evidence/spr01/fire-directions/independent/"
const SRC: String = "res://assets/concepts/spr01/fire-directions-v1/"
var checks: Array[Dictionary] = []
var main: Node
var manifest: Dictionary

func _init() -> void:
	root.unfocusable = true
	_run.call_deferred()

func check(label: String, ok: bool, detail: Variant = null) -> void:
	checks.append({"name":label,"status":"PASS" if ok else "FAIL","detail":detail})
	print(checks.back())

func frames() -> void:
	for i: int in 3:
		await process_frame
	await RenderingServer.frame_post_draw

func capture(label: String) -> void:
	await frames()
	main.render_view.get_texture().get_image().save_png(OUT+label+".png")

func aim_screen(direction: Vector2) -> Vector2:
	return main.camera.unproject_position(main.player_ground3())-Vector2(0,10)+direction*40

func motion(point: Vector2) -> void:
	var ev: InputEventMouseMotion = InputEventMouseMotion.new()
	ev.position = root.get_final_transform()*point
	Input.parse_input_event(ev)
	await frames()

func click(point: Vector2, button: MouseButton) -> void:
	await motion(point)
	var ev: InputEventMouseButton = InputEventMouseButton.new()
	ev.position = root.get_final_transform()*point
	ev.button_index = button
	ev.pressed = true
	Input.parse_input_event(ev)
	await frames()
	ev.pressed = false
	Input.parse_input_event(ev)
	await frames()

func image_matches(kind: String, direction: String, index: int) -> bool:
	var f: Dictionary = manifest.actions[kind].frames_by_direction[direction][index]
	var expected: Image = Image.load_from_file(SRC+String(f.character.file))
	var actual: Image = main.actor.display_sprite.texture.get_image()
	expected.convert(Image.FORMAT_RGBA8)
	actual.convert(Image.FORMAT_RGBA8)
	return actual.get_data()==expected.get_data()

func pose_ok() -> bool:
	var a: Sprite3D = main.actor.display_sprite
	var b: Sprite3D = main.actor.shadow_board
	var top: Vector2 = main.camera.unproject_position(a.to_global(Vector3(-12,18,0)*a.pixel_size))
	var end: Vector2 = main.camera.unproject_position(a.to_global(Vector3(12,-18,0)*a.pixel_size))
	var foot: Vector2 = main.camera.unproject_position(main.actor.render_foot)
	return a.texture==b.texture and a.global_position.is_equal_approx(b.global_position) and not a.flip_h and not b.flip_h and (end-top).is_equal_approx(Vector2(24,36)) and (top+Vector2(12,34)).is_equal_approx(foot) and foot.distance_to(foot.round())<0.001

func logic_checks() -> void:
	var s: RefCounted = Session.new()
	var a: RefCounted = Action.new()
	s.play.select_index(0)
	var seeds: int = s.play.seeds
	var target: Vector2 = s.position+Vector2(25,0)
	var start: Dictionary = a.start(s,false,target)
	a.advance(0.065,s)
	var busy: Dictionary = a.start(s,true,target)
	check("seed65_pending_busy_no_cost",bool(start.ok) and a.active and not a.released and s.projectiles.launched==0 and s.play.seeds==seeds and busy.get("reason")=="busy" and is_equal_approx(a.elapsed_ms,65.0))
	var released: Dictionary = a.advance(0.001,s)
	check("seed66_one_release_cost",bool(released.ok) and s.projectiles.launched==1 and s.play.seeds==seeds-1 and a.frame_index()==1)
	a.advance(0.334,s)
	check("seed400_end",not a.active and s.projectiles.launched==1)
	a.start(s,true,target)
	var water: float = s.play.water
	a.advance(0.399,s)
	s.paused=true
	a.advance(0.5,s)
	s.paused=false
	a.advance(0.5,s,true)
	check("water399_pause_suspend_hold",not a.released and is_equal_approx(a.elapsed_ms,399.0) and s.play.water==water)
	released=a.advance(0.001,s)
	check("water400_one_release_cost",bool(released.ok) and s.projectiles.launched==2 and is_equal_approx(s.play.water,water-s.play.tuning.water_cost_per_shot) and a.frame_index()==4)
	a.advance(0.4,s)
	check("water800_end_once",not a.active and s.projectiles.launched==2)
	s.play.seeds=0
	s.play.water=0.0
	check("zero_resources_reject",not bool(a.start(s,false,target).ok) and not bool(a.start(s,true,target).ok) and not a.active)
	s.close()

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	manifest=JSON.parse_string(FileAccess.get_file_as_string(SRC+"manifest.json"))
	logic_checks()
	if DisplayServer.get_name()=="headless":
		quit(2)
		return
	Audio.use_settings_path(OUT+"audio-settings.json")
	main=load("res://scenes/poc.tscn").instantiate()
	main.auto_process=false
	main.save_dir=OUT+"save/"
	main.set_meta(&"poc_town",true)
	root.add_child(main)
	main.audio.muted=true
	main.set_text_visible(false)
	await frames()
	main.session.play.select_index(0)
	await click(aim_screen(Vector2.LEFT),MOUSE_BUTTON_RIGHT)
	check("input_water_left_start",main.fire_action.active and main.actor.direction==&"left" and image_matches("water","left",0) and pose_ok())
	main.tick(0.280,Vector2.ZERO)
	await capture("water_left_hold")
	var original_aim: Vector2=main.fire_action.aim
	await motion(aim_screen(Vector2.RIGHT))
	main.tick(0.0,Vector2.ZERO)
	check("live_mouse_facing_changes_without_aim_change",main.actor.direction==&"right" and image_matches("water","right",3) and main.fire_action.aim==original_aim and pose_ok())
	await capture("water_right_hold")
	var count: int=main.session.projectiles.launched
	main.tick(0.120,Vector2.RIGHT)
	var projectile: Dictionary=main.session.projectiles.shots.back()
	var flight: Sprite3D=main.play_view.flight_pool.back()
	var socket: Array=manifest.actions.water.release_events[0].socket_by_direction.right
	var expected: Vector2=main.camera.unproject_position(main.actor.render_foot)+Vector2(float(socket[0])-12,float(socket[1])-34)
	var actual: Vector2=main.camera.unproject_position(flight.global_position)
	check("water_right_release_current_socket_current_camera",main.session.projectiles.launched==count+1 and main.actor.direction==&"right" and image_matches("water","right",4) and actual.distance_to(expected)<0.001 and Vector2(projectile.target)==original_aim and Vector2(projectile.origin).is_equal_approx(main.session.position) and pose_ok(),{"expected":expected,"actual":actual})
	await capture("water_right_release")
	main.tick(0.400,Vector2.RIGHT)
	check("water_recovery_returns_directional_walk",not main.fire_action.active and main.actor.fire_kind==&"" and main.actor.walking and (main.actor.display_sprite.texture as AtlasTexture).atlas.resource_path.ends_with("walk-normal.png"))
	main.tick(0.0,Vector2.ZERO)
	await click(aim_screen(Vector2.UP),MOUSE_BUTTON_LEFT)
	check("up_seed_start_back_art",main.actor.direction==&"up" and image_matches("seed","up",0) and pose_ok())
	main.tick(0.066,Vector2.ZERO)
	flight=main.play_view.flight_pool.back()
	socket=manifest.actions.seed.release_events[0].socket_by_direction.up
	expected=main.camera.unproject_position(main.actor.render_foot)+Vector2(float(socket[0])-12,float(socket[1])-34)
	actual=main.camera.unproject_position(flight.global_position)
	check("up_seed_release_socket_shadow",main.actor.direction==&"up" and image_matches("seed","up",1) and actual.distance_to(expected)<0.001 and pose_ok(),{"expected":expected,"actual":actual})
	await capture("seed_up_release")
	main.tick(0.334,Vector2.ZERO)
	check("seed_end_restores_up_idle",not main.fire_action.active and main.actor.direction==&"up" and (main.actor.display_sprite.texture as AtlasTexture).atlas.resource_path.ends_with("idle.png"))
	await click(aim_screen(Vector2.LEFT),MOUSE_BUTTON_RIGHT)
	main.open_pause_menu()
	main.tick(0.5,Vector2.ZERO)
	check("menu_freezes_pending",main.fire_action.active and is_equal_approx(main.fire_action.elapsed_ms,0.0))
	main.close_menu()
	main.new_game()
	count=main.session.projectiles.launched
	main.tick(0.5,Vector2.ZERO)
	check("new_game_cancels_pending_no_ghost",not main.fire_action.active and main.session.projectiles.launched==count)
	var failures: int=checks.filter(func(c: Dictionary)->bool:return c.status=="FAIL").size()
	var file: FileAccess=FileAccess.open(OUT+"results.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"renderer":RenderingServer.get_video_adapter_name(),"display":DisplayServer.get_name(),"not_run":["Physical input and window pixels","Continuous playback feel and final art acceptance","Export, all weather/performance/full regression","Load/save and cultivated seed regression: unchanged files hash checked"]},"\t"))
	file.close()
	main.session.close()
	main.queue_free()
	await process_frame
	quit(1 if failures else 0)
