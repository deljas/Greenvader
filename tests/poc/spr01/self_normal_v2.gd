extends SceneTree
## Focused normal-v2 GPU poses / idle / comparison switch; no OS input.
const OUT: String = "res://evidence/spr01/walk-normal-v2/self/"
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
	for index: int in 4:
		await process_frame
	await RenderingServer.frame_post_draw

func shot(name: String) -> void:
	await frames()
	var picture: Image = main.render_view.get_texture().get_image()
	picture.save_png(ProjectSettings.globalize_path(OUT + name + ".png"))

func toggle_f6() -> void:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = KEY_F6
	event.pressed = true
	Input.parse_input_event(event)
	await frames()
	event.pressed = false
	Input.parse_input_event(event)
	await frames()

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		print("NOT_RUN: real rendering required")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	main = load("res://scenes/poc.tscn").instantiate()
	main.set_meta(&"poc_town", true)
	root.add_child(main)
	main.auto_process = false
	main.audio.muted = true
	main.save_dir = OUT + "unused-save/"
	await frames()
	main.set_text_visible(false)
	main.facing = &"down"
	main._cursor_known = false
	main.walk_mode = 0
	main.tick(0.0, Vector2.ZERO)
	check("normal_mode_640", main.walk_mode == 0 and main.current_resolution() == Vector2i(640,360))
	var expected: Image = Image.load_from_file("res://assets/concepts/spr01/walk-normal-v2/sheet.png")
	var atlas: AtlasTexture = main.actor.frame_texture(0, &"down", 0, true) as AtlasTexture
	var imported: Image = atlas.atlas.get_image()
	imported.convert(Image.FORMAT_RGBA8)
	expected.convert(Image.FORMAT_RGBA8)
	check("imported_runtime_pixels_match_v2", imported.get_size() == Vector2i(96,144) and imported.get_data() == expected.get_data())
	var foot: Vector3 = main.actor.render_foot
	var common: bool = true
	for phase: int in 4:
		main.walking = true
		main.animation_time = float(phase) / 8.0
		main._update_actor()
		var texture: AtlasTexture = main.actor.display_sprite.texture as AtlasTexture
		common = common and texture.region == Rect2(24 * phase,0,24,36) and texture.atlas.resource_path.ends_with("walk-normal.png") and main.actor.render_foot.is_equal_approx(foot)
		await shot("normal_" + str(phase))
	check("four_normal_frames_same_ground", common)
	main.tick(0.0, Vector2.ZERO)
	check("stop_is_adopted_idle", not main.actor.walking and main.actor.frame == 0 and (main.actor.display_sprite.texture as AtlasTexture).atlas.resource_path.ends_with("idle.png"))
	await shot("idle")
	var before: Vector2 = main.session.position
	await toggle_f6()
	check("engine_F6_switches_to_preserved_hop", main.walk_mode == 1 and main.session.position == before)
	main.walking = true
	main.animation_time = 0.25
	main._update_actor()
	check("hop_atlas_still_selected", (main.actor.display_sprite.texture as AtlasTexture).atlas.resource_path.ends_with("walk-hop.png"))
	await shot("hop")
	await toggle_f6()
	main.tick(0.0, Vector2.ZERO)
	check("switch_back_normal_and_idle", main.walk_mode == 0 and not main.actor.walking)
	var file: FileAccess = FileAccess.open(OUT + "results.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": checks, "failures": failures, "renderer": RenderingServer.get_video_adapter_name(), "display": DisplayServer.get_name(), "not_run": ["Physical OS input", "Continuous animation feel / final art preference", "Save / all weather / full shadow regression"]}, "\t"))
	file.close()
	main.session.close()
	main.queue_free()
	await process_frame
	print("RESULT failures=", failures)
	quit(1 if failures > 0 else 0)
