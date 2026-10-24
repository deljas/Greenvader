extends SceneTree
## Single real-GPU integration pass. Hidden/unfocusable window; only engine input injection.
const Coords: GDScript = preload("res://scripts/poc/poc_coords.gd")
const Save: GDScript = preload("res://scripts/poc/save/poc_save.gd")
const OUT: String = "res://evidence/spr01/fire-integration/self/"
const SAVE_DIR: String = OUT + "save-sandbox/"
var main: Node
var checks: Array[Dictionary] = []
var failures: int = 0
func _init() -> void:
	root.unfocusable = true
	_run.call_deferred()
func check(name: String, ok: bool, detail: Variant = null) -> void:
	checks.append({"name":name,"ok":ok,"detail":detail})
	print("PASS " if ok else "FAIL ",name," ",detail)
	if not ok:
		failures += 1
func frames() -> void:
	for i: int in 3:
		await process_frame
	await RenderingServer.frame_post_draw
func capture(name: String) -> void:
	await frames()
	main.render_view.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT+name+".png"))
func ground_screen(offset: Vector2 = Vector2(0, 30)) -> Vector2:
	return main.camera.unproject_position(Coords.ground3(Coords.logic_to_ground(main.session.position+offset)))
func click(pos: Vector2, button: MouseButton) -> void:
	var ev: InputEventMouseButton=InputEventMouseButton.new()
	ev.position=root.get_final_transform()*pos
	ev.button_index=button
	ev.pressed=true
	Input.parse_input_event(ev)
	await frames()
	ev.pressed=false
	Input.parse_input_event(ev)
	await frames()
func atlas_image(sprite: Sprite3D) -> Image:
	var t: AtlasTexture=sprite.texture as AtlasTexture
	return t.atlas.get_image().get_region(Rect2i(t.region))
func _run() -> void:
	if DisplayServer.get_name()=="headless":
		print("NOT_RUN GPU")
		quit(2)
		return
	main=load("res://scenes/poc.tscn").instantiate()
	main.set_meta(&"poc_town",true)
	root.add_child(main)
	main.auto_process=false
	main.audio.muted=true
	main.save_dir=SAVE_DIR
	main.set_text_visible(false)
	await frames()
	var point: Vector2=ground_screen()
	var launched: int=main.session.projectiles.launched
	await click(point,MOUSE_BUTTON_RIGHT)
	check("right_mouse_starts_water_pose0_without_shot",main.fire_action.active and main.fire_action.kind==&"water" and main.actor.frame==0 and main.actor.direction==&"down" and main.session.projectiles.launched==launched)
	await capture("water_000")
	var sync_ok: bool=true
	var grid_ok: bool=true
	for ms: int in [80,180,280,399]:
		var delta: float=(float(ms)-main.fire_action.elapsed_ms)/1000.0
		main.tick(delta,Vector2.ZERO)
		await capture("water_%03d"%ms)
		var snap: Dictionary=main.actor.snapshot()
		sync_ok=sync_ok and snap.matching_texture and snap.matching_feet
		var p: Vector2=main.camera.unproject_position(main.actor.formation_sprite.global_position)
		var c: Vector2=main.camera.unproject_position(main.actor.display_sprite.global_position)
		grid_ok=grid_ok and p.distance_to(c)<0.001 and c.distance_to(c.round())<0.001
	check("water_399ms_growing_formation_and_matching_anchor",main.actor.frame==3 and not atlas_image(main.actor.formation_sprite).get_used_rect().size==Vector2i.ZERO and sync_ok and grid_ok)
	var muted_before: int=main.audio.dropped_muted
	main.tick(0.001,Vector2.ZERO)
	await capture("water_400")
	var shot: Dictionary=main.session.projectiles.shots.back()
	var sprite: Sprite3D=main.play_view.flight_pool[0]
	var socket: Vector2=main.camera.unproject_position(main.actor.render_foot)-Vector2(0,20)
	var visual: Vector2=main.camera.unproject_position(sprite.global_position)
	check("water_release_400_native_flight_socket_and_sound",main.session.projectiles.launched==launched+1 and main.actor.frame==4 and atlas_image(main.actor.formation_sprite).get_used_rect().size==Vector2i.ZERO and sprite.texture.get_size()==Vector2(8,8) and visual.distance_to(socket)<0.001 and main.audio.dropped_muted==muted_before+1,{"socket":socket,"projectile":visual,"logical_origin":shot.origin})
	main.tick(0.1,Vector2.ZERO)
	await capture("water_500")
	main.tick(0.12,Vector2.ZERO)
	await capture("water_620")
	main.tick(0.18,Vector2.ZERO)
	await capture("water_800")
	check("water_returns_idle_after_800",not main.fire_action.active and main.actor.fire_kind==&"" and not main.actor.formation_sprite.visible and (main.actor.display_sprite.texture as AtlasTexture).atlas.resource_path.ends_with("idle.png"))
	# Seed release keeps the authored small burst in its formation layer.
	await click(ground_screen(Vector2(30,0)),MOUSE_BUTTON_LEFT)
	await capture("seed_000")
	main.tick(0.066,Vector2.RIGHT)
	await capture("seed_066")
	check("seed_release_burst_and_move_preserved",main.walking and main.actor.fire_kind==&"seed" and main.actor.frame==1 and atlas_image(main.actor.formation_sprite).get_used_rect().size!=Vector2i.ZERO)
	main.tick(0.1,Vector2.ZERO)
	await capture("seed_166")
	main.tick(0.1,Vector2.ZERO)
	await capture("seed_266")
	main.tick(0.134,Vector2.RIGHT)
	await capture("seed_400")
	check("seed_returns_directional_walk",not main.fire_action.active and main.actor.walking and main.actor.fire_kind==&"" and (main.actor.display_sprite.texture as AtlasTexture).atlas.resource_path.ends_with("walk-normal.png"))
	# All actual aim directions temporarily share this front art and preserve their logical target.
	var directions_ok: bool=true
	var foot: Vector2=main.camera.unproject_position(main.player_ground3())
	for vector: Vector2 in [Vector2.LEFT,Vector2.RIGHT,Vector2.UP,Vector2.DOWN]:
		main._cancel_fire()
		var pos: Vector2=foot+vector*40.0
		main.place_aim_at(pos)
		var picked: Dictionary=main.pick_ground(pos)
		var result: Dictionary=main.click_fire(pos,false)
		directions_ok=directions_ok and bool(result.ok) and main.actor.direction==&"down" and main.fire_action.aim==picked.logic and main.actor.snapshot().matching_texture
	main._cancel_fire()
	main.tick(0.0,Vector2.ZERO)
	check("four_aim_directions_share_front_only_while_firing",directions_ok and main.actor.fire_kind==&"")
	# Stop/resume via actual menu and viewpoint paths.
	main.click_fire(ground_screen(),true)
	main.tick(0.08,Vector2.ZERO)
	var before: float=main.fire_action.elapsed_ms
	main.open_pause_menu()
	main.tick(0.5,Vector2.ZERO)
	var menu_ok: bool=main.fire_action.elapsed_ms==before
	main.close_menu()
	main.session.position=Coords.cell_center_logic(main.viewpoint.cell)+Vector2(10,0)
	main.tick(0.0,Vector2.ZERO)
	var entered: bool=main.enter_viewpoint()
	main.tick(0.5,Vector2.ZERO)
	check("menu_and_viewpoint_pause_action",menu_ok and entered and main.fire_action.elapsed_ms==before)
	main.leave_viewpoint()
	main._cancel_fire()
	# Save contains no action clock; a successful load cancels the live pending charge.
	main.save_game()
	main.click_fire(ground_screen(),true)
	var load_result: Dictionary=main.load_game(false)
	var count: int=main.session.projectiles.launched
	main.tick(0.5,Vector2.ZERO)
	check("successful_load_cancels_pending_no_ghost",bool(load_result.ok) and not main.fire_action.active and main.session.projectiles.launched==count)
	main.click_fire(ground_screen(),true)
	main.new_game()
	check("new_game_cancels_pending",not main.fire_action.active)
	main.click_fire(ground_screen(),true)
	main.session.play.health.hit(main.session.play,main.session.play.hp,main.session.position,main.session.position)
	check("actual_death_signal_cancels_pending",main.session.play.health.downed and not main.fire_action.active)
	var file: FileAccess=FileAccess.open(OUT+"gpu-results.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"renderer":RenderingServer.get_video_adapter_name(),"not_run":["Physical mouse/keyboard OS path","Art adoption and live playback feel","Performance and full weather/angle matrix"]},"\t"))
	file.close()
	for name: String in DirAccess.get_files_at(SAVE_DIR):
		DirAccess.remove_absolute(SAVE_DIR+name)
	main.session.close()
	main.queue_free()
	await process_frame
	quit(failures)
