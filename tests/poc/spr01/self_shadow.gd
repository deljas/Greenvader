extends SceneTree
## Focused retest after fixing crossed display/shadow card self-shadowing.
const Coords: GDScript = preload("res://scripts/poc/poc_coords.gd")
const OUT: String = "res://evidence/spr01/walk-compare/self/"
var main: Node
var checks: Array[Dictionary] = []
var failures: int = 0
func _init() -> void:
	root.unfocusable = true
	_run.call_deferred()
func check(name: String, ok: bool, detail: Variant = null) -> void:
	checks.append({"name": name, "ok": ok, "detail": detail})
	print("PASS " if ok else "FAIL ", name, " ", detail)
	if not ok:
		failures += 1
func frames() -> void:
	for i: int in 4:
		await process_frame
	await RenderingServer.frame_post_draw
func image(name: String) -> Image:
	await frames()
	var result: Image = main.render_view.get_texture().get_image()
	result.save_png(OUT + name + ".png")
	return result
func region_difference(a: Image, b: Image, rect: Rect2i) -> float:
	var difference: float = 0.0
	for y: int in range(rect.position.y, rect.end.y):
		for x: int in range(rect.position.x, rect.end.x):
			var ca: Color = a.get_pixel(x,y)
			var cb: Color = b.get_pixel(x,y)
			difference += absf(ca.r-cb.r)+absf(ca.g-cb.g)+absf(ca.b-cb.b)
	return difference
func synced() -> bool:
	var a: DirectionalLight3D = main.actor.receiver_light
	var b: DirectionalLight3D = main.sun
	return a.global_transform.is_equal_approx(b.global_transform) and a.light_color.is_equal_approx(b.light_color) and is_equal_approx(a.light_energy,b.light_energy) and a.visible==b.visible and a.shadow_enabled==b.shadow_enabled and is_equal_approx(a.shadow_bias,b.shadow_bias) and is_equal_approx(a.shadow_normal_bias,b.shadow_normal_bias) and a.light_angular_distance==b.light_angular_distance
func _run() -> void:
	main=load("res://scenes/poc.tscn").instantiate()
	main.set_meta(&"poc_town",true)
	root.add_child(main)
	main.auto_process=false
	main.audio.muted=true
	await frames()
	main.set_text_visible(false)
	main.facing=&"down"
	main._cursor_known=false
	main.tick(0.0,Vector2.ZERO)
	var foot: Vector3=main.player_ground3()+Vector3.UP*0.04
	var screen: Vector2=main.camera.unproject_position(main.actor.render_foot)
	var rect: Rect2i=Rect2i(Vector2i(screen)-Vector2i(12,34),Vector2i(24,36))
	var face_rect: Rect2i=Rect2i(rect.position+Vector2i(6,20),Vector2i(12,9))
	check("separate_player_light_masks", main.actor.display_sprite.layers==64 and main.actor.shadow_board.layers==8 and main.sun.light_cull_mask & 64 == 0 and main.actor.receiver_light.light_cull_mask==64 and main.actor.receiver_light.shadow_caster_mask==1)
	check("day_light_parameters_synced",synced())
	var with_card: Image=await image("self_shadow_fixed")
	if OS.get_cmdline_user_args().has("--diagnose"):
		main.sun.light_energy = 0.0
		await image("diagnose_main_energy_zero")
		main.sun.light_energy = main.actor.receiver_light.light_energy
		main.sun.shadow_caster_mask = 1
		await image("diagnose_main_no_sprite_caster")
		main.sun.shadow_caster_mask = 1 | 8
		main.actor.receiver_light.shadow_enabled = false
		await image("diagnose_receiver_no_shadows")
		main.session.close()
		main.queue_free()
		await process_frame
		quit()
		return
	# Hide it completely: switching SHADOWS_ONLY to OFF would display its colour card.
	main.actor.shadow_board.visible=false
	var without_card: Image=await image("card_off")
	var card_diff: float=region_difference(with_card,without_card,face_rect)
	check("own_shadow_does_not_cross_face",card_diff<0.05,card_diff)
	var world_diff: float=region_difference(with_card,without_card,Rect2i(0,0,640,360))
	check("shadow_card_still_projects_ground_shadow",world_diff>0.1,world_diff)
	main.actor.shadow_board.visible=true
	# A shadow-only 3D cube is a controlled building-shadow fixture without camera occlusion.
	var box: MeshInstance3D=MeshInstance3D.new()
	var mesh: BoxMesh=BoxMesh.new()
	mesh.size=Vector3(3.0,4.0,3.0)
	box.mesh=mesh
	box.layers=1
	box.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	main.world.add_child(box)
	box.global_position=foot+main.sun.global_basis.z*3.0+Vector3.UP*0.8
	var building_shadow: Image=await image("building_shadow_received")
	var building_diff: float=region_difference(with_card,building_shadow,face_rect)
	check("player_receives_other_3d_shadows",building_diff>0.5,building_diff)
	box.free()
	# One night + rain condition confirms no daytime key is left behind on the sprite.
	var original_clock: Dictionary=main.session.clock.to_dict()
	main.session.clock.elapsed=360.0
	main.session.debug_weather_enabled=true
	main.session.set_debug_weather(2)
	main.env_view.sync()
	main._update_actor()
	check("night_rain_light_parameters_synced",synced(),{"hour":main.session.day_hour(),"moon":main.env_view.last_is_moon,"main_energy":main.sun.light_energy,"receiver_energy":main.actor.receiver_light.light_energy})
	await image("night_rain")
	main.sun.visible=false
	main._update_actor()
	check("hidden_source_hides_receiver",not main.actor.receiver_light.visible)
	main.sun.visible=true
	main.session.clock.load_dict(original_clock)
	main.session.set_debug_weather(-1)
	main.env_view.sync()
	main._update_actor()
	check("reflection_includes_player_both_masks",main.water_view.reflection_camera.cull_mask & 64 != 0 and main.occlusion_view.reflection_mask_during_draw() & 64 != 0)
	# Update comparison frames after the lighting fix; no movement / clock advancement here.
	for mode: int in 2:
		main.walk_mode=mode
		main.walking=true
		for f: int in 4:
			main.animation_time=float(f)/8.0
			main._update_actor()
			await image(("normal" if mode==0 else "hop")+"_"+str(f))
	main.walking=false
	main.walk_mode=0
	main._update_actor()
	main.set_text_visible(true)
	await frames()
	root.get_texture().get_image().save_png(OUT+"game_controls.png")
	var file: FileAccess=FileAccess.open(OUT+"shadow_results.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures},"\t"))
	file.close()
	main.session.close()
	main.queue_free()
	await process_frame
	quit(failures)
