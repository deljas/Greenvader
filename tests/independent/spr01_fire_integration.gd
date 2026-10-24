extends SceneTree
## Independent limited SPR-01 logic+GPU pass. No OS input or normal save data.
const Session: GDScript=preload("res://scripts/poc/poc_session.gd")
const Action: GDScript=preload("res://scripts/poc/poc_fire_action.gd")
const Coords: GDScript=preload("res://scripts/poc/poc_coords.gd")
const Audio: GDScript=preload("res://scripts/poc/audio/poc_audio.gd")
const OUT: String="res://evidence/spr01/fire-integration/independent/"
const SAVE_DIR: String=OUT+"save/"
var checks: Array[Dictionary]=[]
var failed: int=0
var main: Node

func _init() -> void:
	root.unfocusable=true
	_run.call_deferred()

func check(name: String,ok: bool,detail: Variant=null) -> void:
	checks.append({"name":name,"status":"PASS" if ok else "FAIL","detail":detail})
	failed+=0 if ok else 1
	print("PASS " if ok else "FAIL ",name," ",detail)

func frames() -> void:
	for i: int in 3:
		await process_frame
	await RenderingServer.frame_post_draw

func shot(name: String) -> void:
	await frames()
	main.render_view.get_texture().get_image().save_png(OUT+name+".png")

func pointer_button(content: Vector2,button: MouseButton) -> void:
	var ev: InputEventMouseButton=InputEventMouseButton.new()
	ev.position=root.get_final_transform()*content
	ev.button_index=button
	ev.pressed=true
	Input.parse_input_event(ev)
	await frames()
	ev.pressed=false
	Input.parse_input_event(ev)
	await frames()

func screen_target(offset: Vector2=Vector2(0,30)) -> Vector2:
	return main.camera.unproject_position(Coords.ground3(Coords.logic_to_ground(main.session.position+offset)))

func action_image_matches(action: String,index: int) -> bool:
	var texture: Texture2D=main.actor.display_sprite.texture
	var actual: Image=texture.get_image()
	var expected: Image=Image.load_from_file("res://assets/concepts/spr01/fire-front-v3/%s-character-%d.png"%[action,index])
	actual.convert(Image.FORMAT_RGBA8)
	expected.convert(Image.FORMAT_RGBA8)
	return actual.get_data()==expected.get_data()

func pose_ok() -> bool:
	var a: Sprite3D=main.actor.display_sprite
	var b: Sprite3D=main.actor.shadow_board
	var fx: Sprite3D=main.actor.formation_sprite
	var p: Vector2=main.camera.unproject_position(main.actor.render_foot)
	var top: Vector2=main.camera.unproject_position(a.to_global(Vector3(-12,18,0)*a.pixel_size))
	var end: Vector2=main.camera.unproject_position(a.to_global(Vector3(12,-18,0)*a.pixel_size))
	return a.texture==b.texture and a.global_position.is_equal_approx(b.global_position) and not a.flip_h and not b.flip_h and (end-top).is_equal_approx(Vector2(24,36)) and (top+Vector2(12,34)).is_equal_approx(p) and p.distance_to(p.round())<0.001 and main.camera.unproject_position(fx.global_position).distance_to(main.camera.unproject_position(a.global_position))<0.001

func logic_checks() -> void:
	var s: RefCounted=Session.new()
	var a: RefCounted=Action.new()
	s.play.select_index(1)
	var chosen: PlantDef=s.play.selected_def()
	var target: Vector2=s.position+Vector2(25,0)
	var seeds: int=s.play.seeds
	var started: Dictionary=a.start(s,false,target)
	a.advance(0.065,s)
	var busy: Dictionary=a.start(s,true,target+Vector2(0,10))
	check("seed65_no_release_busy_does_not_restart",bool(started.ok) and s.projectiles.launched==0 and s.play.seeds==seeds and busy.get("reason")=="busy" and is_equal_approx(a.elapsed_ms,65.0))
	s.play.select_index(2)
	s.set_aim(s.position+Vector2(-20,0))
	s.position+=Vector2(1,0)
	var released: Dictionary=a.advance(0.001,s)
	var seedshot: Dictionary=s.projectiles.shots.back()
	check("seed66_input_selection_aim_and_release_origin",bool(released.ok) and s.projectiles.launched==1 and seedshot.kind==String(chosen.key) and Vector2(seedshot.target).is_equal_approx(target) and Vector2(seedshot.origin).is_equal_approx(s.position) and s.play.seeds==seeds and s.play.reserved_seeds==chosen.seed_cost and s.play.available_seeds()==seeds-chosen.seed_cost and s.play.selected_def().key!=chosen.key)
	a.advance(0.1,s)
	check("logical_release_cost_once",s.projectiles.launched==1 and s.play.seeds==seeds and s.play.reserved_seeds==chosen.seed_cost and s.play.available_seeds()==seeds-chosen.seed_cost)
	var next: Dictionary=a.start(s,true,target)
	var water: float=s.play.water
	a.advance(0.399,s)
	s.paused=true
	a.advance(1.0,s)
	s.paused=false
	a.advance(1.0,s,true)
	check("recovery_interrupt_water399_pause_hold",bool(next.ok) and a.kind==&"water" and a.frame_index()==3 and is_equal_approx(a.elapsed_ms,399.0) and is_equal_approx(s.play.water,water))
	released=a.advance(0.001,s)
	check("water400_and_800_boundaries",bool(released.ok) and a.frame_index()==4 and s.projectiles.launched==2 and is_equal_approx(s.play.water,water-s.play.tuning.water_cost_per_shot))
	a.advance(0.4,s)
	check("water800_end_no_second_release",not a.active and s.projectiles.launched==2)
	s.close()
	var z: RefCounted=Session.new()
	var b: RefCounted=Action.new()
	z.play.seeds=0
	z.play.water=0.0
	check("resource0_preflight_rejects_both",not bool(b.start(z,false,z.position+Vector2(20,0)).ok) and not bool(b.start(z,true,z.position+Vector2(20,0)).ok) and not b.active)
	z.play.seeds=10
	b.start(z,false,z.position+Vector2(20,0))
	z.play.seeds=0
	var denied: Dictionary=b.advance(0.066,z)
	check("resource_recheck_at_release",not bool(denied.ok) and not b.active and z.projectiles.launched==0 and z.play.seeds==0)
	z.play.seeds=10
	z.projectiles.max_count=0
	var blocked: Dictionary=b.start(z,false,z.position+Vector2(20,0))
	z.projectiles.max_count=64
	b.start(z,false,z.position+Vector2(20,0))
	z.projectiles.max_count=0
	denied=b.advance(0.066,z)
	check("full_preflight_and_release_recheck",not bool(blocked.ok) and not bool(denied.ok) and z.projectiles.launched==0 and z.play.seeds==10)
	z.projectiles.max_count=64
	var direct: Dictionary=z.fire(false,z.position+Vector2(20,0))
	check("session_fire_immediate_compatibility",bool(direct.ok) and z.projectiles.launched==1 and z.play.seeds==9)
	z.close()

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	logic_checks()
	if DisplayServer.get_name()=="headless":
		print("NOT_RUN GPU: headless")
		quit(2)
		return
	Audio.use_settings_path(OUT+"audio-settings.json")
	main=load("res://scenes/poc.tscn").instantiate()
	main.auto_process=false
	main.save_dir=SAVE_DIR
	main.set_meta(&"poc_town",true)
	root.add_child(main)
	main.audio.muted=true
	main.set_text_visible(false)
	await frames()
	var count: int=main.session.projectiles.launched
	var amount: float=main.session.play.water
	var sounds: int=main.audio.dropped_muted
	await pointer_button(screen_target(),MOUSE_BUTTON_RIGHT)
	check("engine_input_starts_front_v3_immediately",main.fire_action.active and main.fire_action.kind==&"water" and main.actor.direction==&"down" and action_image_matches("water",0) and main.session.projectiles.launched==count and main.audio.dropped_muted==sounds)
	main.tick(0.399,Vector2.ZERO)
	check("water399_gpu_hold",main.actor.frame==3 and main.session.projectiles.launched==count and is_equal_approx(main.session.play.water,amount) and action_image_matches("water",3) and pose_ok())
	await shot("water399")
	main.open_pause_menu()
	main.tick(0.5,Vector2.ZERO)
	check("menu_freezes_pending",is_equal_approx(main.fire_action.elapsed_ms,399.0) and main.session.projectiles.launched==count)
	main.close_menu()
	main.tick(0.001,Vector2.ZERO)
	var formation: Image=main.actor.formation_sprite.texture.get_image()
	var flight: Sprite3D=main.play_view.flight_pool[0]
	var socket: Vector2=main.camera.unproject_position(main.actor.render_foot)-Vector2(0,20)
	check("water400_gpu_release_socket_and_one_sound",main.session.projectiles.launched==count+1 and main.actor.frame==4 and action_image_matches("water",4) and formation.get_used_rect().size==Vector2i.ZERO and flight.texture.get_size()==Vector2(8,8) and main.camera.unproject_position(flight.global_position).distance_to(socket)<0.001 and main.audio.dropped_muted==sounds+1 and pose_ok())
	await shot("water400")
	main.tick(0.01,Vector2.ZERO)
	check("water_release_not_repeated",main.session.projectiles.launched==count+1 and main.audio.dropped_muted==sounds+1)
	# Interrupt recovery with an actual left click, then change selection and aim while charging.
	main.session.play.select_index(0)
	var initial_target: Vector2=screen_target(Vector2(25,0))
	await pointer_button(initial_target,MOUSE_BUTTON_LEFT)
	var aim_snapshot: Vector2=main.fire_action.aim
	var start_pos: Vector2=main.session.position
	count=main.session.projectiles.launched
	main.session.play.select_index(1)
	main.tick(0.065,Vector2.RIGHT)
	await pointer_button(screen_target(Vector2(-25,0)),MOUSE_BUTTON_RIGHT)
	check("seed_busy_aim_selection_snapshot_and_movement",main.fire_action.kind==&"seed" and is_equal_approx(main.fire_action.elapsed_ms,65.0) and main.fire_action.aim==aim_snapshot and main.session.position.distance_to(start_pos)>0.0 and main.session.projectiles.launched==count)
	main.tick(0.001,Vector2.RIGHT)
	var projectile: Dictionary=main.session.projectiles.shots.back()
	check("seed66_gpu_native_front_and_actual_aim",main.session.projectiles.launched==count+1 and projectile.kind=="seed" and Vector2(projectile.target).is_equal_approx(aim_snapshot) and Vector2(projectile.origin).is_equal_approx(main.session.position) and action_image_matches("seed",1) and main.actor.formation_sprite.texture.get_image().get_used_rect().size!=Vector2i.ZERO and pose_ok())
	await shot("seed66")
	main.tick(0.334,Vector2.RIGHT)
	check("seed400_restores_directional_walking",not main.fire_action.active and main.actor.fire_kind==&"" and main.actor.walking and (main.actor.display_sprite.texture as AtlasTexture).atlas.resource_path.ends_with("walk-normal.png"))
	await shot("walk_return")
	main.tick(0.0,Vector2.ZERO)
	check("stop_restores_directional_idle",not main.actor.walking and (main.actor.display_sprite.texture as AtlasTexture).atlas.resource_path.ends_with("idle.png"))
	var front_ok: bool=true
	var screen_foot: Vector2=main.camera.unproject_position(main.player_ground3())
	for direction: Vector2 in [Vector2.UP,Vector2.LEFT,Vector2.DOWN,Vector2.RIGHT]:
		main._cancel_fire()
		var target: Vector2=screen_foot+direction*35
		var picked: Dictionary=main.pick_ground(target)
		var result: Dictionary=main.click_fire(target,false)
		front_ok=front_ok and bool(picked.ok) and bool(result.ok) and main.fire_action.aim==picked.logic and main.actor.direction==&"down" and action_image_matches("seed",0)
	check("four_actual_aims_share_front_art_only",front_ok)
	main._cancel_fire()
	var invalid: Dictionary=main.click_fire(Vector2(-10,-10),false)
	check("invalid_point_does_not_start",not bool(invalid.ok) and not main.fire_action.active)
	main.session.position=Coords.cell_center_logic(main.viewpoint.cell)+Vector2(10,0)
	main.tick(0.0,Vector2.ZERO)
	main.click_fire(screen_target(),true)
	main.tick(0.08,Vector2.ZERO)
	var held: float=main.fire_action.elapsed_ms
	var entered: bool=main.enter_viewpoint()
	main.tick(0.5,Vector2.ZERO)
	check("viewpoint_freezes_pending",entered and main.fire_action.elapsed_ms==held)
	main.leave_viewpoint()
	main._cancel_fire()
	var saved: Dictionary=main.save_game()
	main.click_fire(screen_target(),true)
	var loaded: Dictionary=main.load_game(false)
	count=main.session.projectiles.launched
	main.tick(0.45,Vector2.ZERO)
	check("load_cancels_unsaved_pending_no_ghost",bool(saved.ok) and bool(loaded.ok) and not main.fire_action.active and main.session.projectiles.launched==count)
	main.click_fire(screen_target(),true)
	main.new_game()
	check("new_game_cancels_pending",not main.fire_action.active)
	main.click_fire(screen_target(),true)
	main.session.play.health.hit(main.session.play,main.session.play.hp,main.session.position,main.session.position)
	count=main.session.projectiles.launched
	main.tick(0.45,Vector2.ZERO)
	check("death_cancels_pending_no_ghost",not main.fire_action.active and main.session.projectiles.launched==count)
	var file: FileAccess=FileAccess.open(OUT+"results.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failed,"renderer":RenderingServer.get_video_adapter_name(),"display":DisplayServer.get_name(),"not_run":["Physical input","Continuous playback feel and art approval","Full game/weather/performance/export regression"]},"\t"))
	file.close()
	main.session.close()
	main.queue_free()
	await process_frame
	print("RESULT failures=",failed)
	quit(1 if failed else 0)
