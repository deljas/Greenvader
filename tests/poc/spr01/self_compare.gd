extends SceneTree
## SPR-01 targeted self-check and real-renderer evidence. No OS input or foreground access.
const Config: GDScript = preload("res://scripts/poc/poc_config.gd")
const Coords: GDScript = preload("res://scripts/poc/poc_coords.gd")
const Save: GDScript = preload("res://scripts/poc/save/poc_save.gd")
const OUT: String = "res://evidence/spr01/walk-compare/self/"
const SAVE_DIR: String = OUT + "save-sandbox/"
var main: Node
var results: Array[Dictionary] = []
var failures: int = 0

func _init() -> void:
	root.unfocusable = true
	_run.call_deferred()

func check(name: String, ok: bool, detail: Variant = null) -> void:
	results.append({"name": name, "ok": ok, "detail": detail})
	print("PASS " if ok else "FAIL ", name, " ", detail)
	if not ok:
		failures += 1

func frames(count: int = 2) -> void:
	for i: int in count:
		await process_frame
	await RenderingServer.frame_post_draw

func pointer(pos: Vector2) -> void:
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	# parse_input_event enters before the root window's integer content transform.
	event.position = root.get_final_transform() * pos
	Input.parse_input_event(event)
	await frames()
	main.tick(0.0, Vector2.ZERO)

func f6() -> void:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = KEY_F6
	event.pressed = true
	Input.parse_input_event(event)
	await frames()
	event.pressed = false
	Input.parse_input_event(event)
	await frames()

func shot(name: String) -> void:
	await frames(3)
	main.render_view.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT + name + ".png"))

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		print("NOT_RUN: GPU requires real rendering")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	main = load("res://scenes/poc.tscn").instantiate()
	main.set_meta(&"poc_town", true)
	root.add_child(main)
	main.auto_process = false
	main.audio.muted = true
	main.save_dir = SAVE_DIR
	main.window_size_override = Vector2i(1280, 720)
	await frames(5)
	if OS.get_cmdline_user_args().has("--layout-only"):
		check("buttons_fit_640_after_labels", main.button_box.get_global_rect().end.x <= 640.0 and main.button_box.position.x >= 0.0, main.button_box.get_global_rect())
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT + "game_controls.png"))
		main.session.close()
		main.queue_free()
		await process_frame
		quit(failures)
		return
	check("default_normal_640", main.walk_mode == 0 and main.current_resolution() == Vector2i(640, 360) and main.actor.direction == &"down")
	check("fixed_resolution", Config.RESOLUTIONS.size() == 1 and not main.set_resolution(1) and root.content_scale_stretch == Window.CONTENT_SCALE_STRETCH_INTEGER)
	var initial: Vector2 = main.session.position
	main.tick(0.125, Vector2.RIGHT)
	check("walk_real_movement_8fps", main.walking and main.actor.frame == 1 and main.session.position.distance_to(initial) > 0.0)
	var saved: Dictionary = Save.capture(main.session)
	var anchor_before: Vector3 = main.actor.render_foot
	var phase_before: float = main.animation_time
	await f6()
	check("engine_F6_toggles_without_game_change", main.walk_mode == 1 and saved == Save.capture(main.session) and main.actor.render_foot.is_equal_approx(anchor_before) and main.animation_time == phase_before)
	main.walk_button.pressed.emit()
	check("button_toggles_back", main.walk_mode == 0 and saved == Save.capture(main.session))
	var face: Vector2 = main.camera.unproject_position(main.player_ground3() + Vector3.UP * 0.04) - Vector2(0, 10)
	var dirs: Array[StringName] = [&"down", &"left", &"right", &"up"]
	var vectors: Array[Vector2] = [Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT, Vector2.UP]
	for i: int in dirs.size():
		await pointer(face + vectors[i] * 55.0)
		check("mouse_direction_" + String(dirs[i]), main.actor.direction == dirs[i] and not main.actor.display_sprite.flip_h, {"cursor": main._cursor_screen, "expected": dirs[i], "actual": main.actor.direction})
	await pointer(face + Vector2.LEFT * 55.0)
	main.tick(0.125, Vector2.RIGHT)
	check("facing_independent_of_move", main.walking and main.actor.direction == &"left")
	main.tick(0.0, Vector2.ZERO)
	check("idle_adopted_frame_zero", not main.actor.walking and main.actor.frame == 0 and (main.actor.display_sprite.texture as AtlasTexture).atlas.resource_path.ends_with("idle.png"))
	var all_cards_ok: bool = true
	var spans_ok: bool = true
	var projected: Dictionary = {}
	for mode: int in 2:
		for direction: StringName in dirs:
			for frame: int in 4:
				main.actor.pose(main.player_ground3() + Vector3.UP * 0.04, frame, direction, main.sun, mode, true)
				var snap: Dictionary = main.actor.snapshot()
				all_cards_ok = all_cards_ok and snap.matching_texture and snap.matching_feet and not main.actor.display_sprite.flip_h and not main.actor.shadow_board.flip_h
				var card: Sprite3D = main.actor.display_sprite
				var center: Vector2 = main.camera.unproject_position(card.global_position)
				var top_left: Vector2 = main.camera.unproject_position(card.to_global(Vector3(-12, 18, 0) * card.pixel_size))
				var bottom_right: Vector2 = main.camera.unproject_position(card.to_global(Vector3(12, -18, 0) * card.pixel_size))
				var span: Vector2 = bottom_right - top_left
				spans_ok = spans_ok and span.is_equal_approx(Vector2(24, 36)) and (center + Vector2(0, 16)).is_equal_approx(snap.foot_screen) and Vector2(snap.foot_screen).distance_to(Vector2(snap.foot_screen).round()) < 0.001
				projected = {"span": span, "center": center, "ground_anchor": snap.foot_screen}
	check("all_32_poses_shadow_sync_no_mirror", all_cards_ok)
	check("projection_24x36_integer_ground_anchor", spans_ok, projected)
	main.session.paused = true
	var paused_pos: Vector2 = main.session.position
	var paused_time: float = main.session.clock.elapsed
	main.tick(0.125, Vector2.RIGHT)
	check("paused_stops_walk_and_time", not main.walking and main.actor.frame == 0 and main.session.position == paused_pos and main.session.clock.elapsed == paused_time)
	main.session.paused = false
	var save_result: Dictionary = Save.save(main.session, SAVE_DIR, {"resolution_index": 1})
	var before_load: Vector2 = main.session.position
	var load_result: Dictionary = main.load_game(false)
	check("legacy_960_save_restores_640", bool(save_result.ok) and bool(load_result.ok) and main.current_resolution() == Vector2i(640, 360) and main.session.position == before_load, load_result.get("reason", ""))
	# Regress the real gameplay boundary without a long full-game sweep.
	var play: PlayState = main.session.play
	play.seeds = 0
	var dry_seed: Dictionary = main.session.fire(false, main.session.position + Vector2(4, 0))
	play.water = 0.0
	var dry_water: Dictionary = main.session.fire(true, main.session.position + Vector2(4, 0))
	check("resource_zero_still_blocks_shots", not bool(dry_seed.ok) and dry_seed.reason == "no_seed" and not bool(dry_water.ok) and dry_water.reason == "no_water")
	# Same location, same facing, same ground anchor: four real-rendered frames for each mode.
	main.set_text_visible(false)
	main.session.position = before_load
	main.tick(0.0, Vector2.ZERO)
	face = main.camera.unproject_position(main.player_ground3() + Vector3.UP * 0.04) - Vector2(0, 10)
	await pointer(face + Vector2.DOWN * 55.0)
	for mode: int in 2:
		main.walk_mode = mode
		main.walking = true
		for frame: int in 4:
			main.animation_time = float(frame) / 8.0
			main._update_actor()
			await shot(("normal" if mode == 0 else "hop") + "_" + str(frame))
	main.walking = false
	main._update_actor()
	main.set_text_visible(true)
	await frames(3)
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT + "game_controls.png"))
	var report: Dictionary = {"checks": results, "failures": failures, "renderer": RenderingServer.get_video_adapter_name(), "display": DisplayServer.get_name(), "not_run": ["Physical keyboard/mouse OS path", "User art preference", "Full play-through and all weather/time conditions"]}
	var file: FileAccess = FileAccess.open(OUT + "results.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	for name: String in DirAccess.get_files_at(SAVE_DIR):
		DirAccess.remove_absolute(SAVE_DIR + name)
	main.session.close()
	main.queue_free()
	await process_frame
	print("RESULT failures=", failures)
	quit(1 if failures > 0 else 0)

