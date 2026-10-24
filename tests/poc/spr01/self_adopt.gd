extends SceneTree
## One short adoption smoke. No OS input, focus change or cursor movement.
const OUT: String = "res://evidence/spr01/walk-adopt/self/"
var main: Node
var checks: Array[Dictionary] = []
var failures: int = 0
func _init() -> void:
	root.unfocusable = true
	_run.call_deferred()
func frames() -> void:
	for i: int in 3:
		await process_frame
	await RenderingServer.frame_post_draw
func check(name: String, ok: bool) -> void:
	checks.append({"name": name, "ok": ok})
	print("PASS " if ok else "FAIL ", name)
	if not ok:
		failures += 1
func capture(name: String) -> void:
	await frames()
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT + name + ".png"))
func _run() -> void:
	if DisplayServer.get_name() == "headless":
		print("NOT_RUN GPU")
		quit(2)
		return
	main = load("res://scenes/poc.tscn").instantiate()
	main.set_meta(&"poc_town", true)
	root.add_child(main)
	main.auto_process = false
	main.audio.muted = true
	await frames()
	var start: Vector2 = main.session.position
	main.tick(0.125, Vector2.RIGHT)
	check("adopted_normal_walks", main.walking and main.actor.walk_mode == 0 and main.actor.frame == 1 and main.session.position.distance_to(start) > 0.0 and (main.actor.display_sprite.texture as AtlasTexture).atlas.resource_path.ends_with("walk-normal.png"))
	await capture("walking")
	var pos: Vector2 = main.session.position
	var elapsed: float = main.session.clock.elapsed
	var phase: float = main.animation_time
	var key: InputEventKey = InputEventKey.new()
	key.physical_keycode = KEY_F6
	key.pressed = true
	Input.parse_input_event(key)
	await frames()
	key.pressed = false
	Input.parse_input_event(key)
	await frames()
	check("F6_does_not_change_walk_or_game", not InputMap.has_action(&"poc_toggle_walk") and main.actor.walk_mode == 0 and main.actor.frame == 1 and main.session.position == pos and main.session.clock.elapsed == elapsed and main.animation_time == phase)
	var comparison_button: bool = false
	for child: Node in main.button_box.get_children():
		if child is Button:
			comparison_button = comparison_button or "歩行" in (child as Button).text or "F6" in (child as Button).text
	check("no_comparison_button_or_hud_help", not comparison_button and not "F6" in main.hud.text and not "歩行比較" in main.hud.text and not "F6" in "\n".join(main.ui.HELP_LINES) and not main.has_method(&"toggle_walk_mode"))
	main.tick(0.0, Vector2.ZERO)
	check("stopped_uses_adopted_idle", not main.walking and main.actor.frame == 0 and main.actor.walk_mode == 0 and (main.actor.display_sprite.texture as AtlasTexture).atlas.resource_path.ends_with("idle.png"))
	await capture("idle")
	var report: Dictionary = {"checks": checks, "failures": failures, "renderer": RenderingServer.get_video_adapter_name(), "not_run": ["Physical keyboard/mouse OS path", "Full regression; intentionally not repeated", "User art preference already approved; no substitute assessment"]}
	var file: FileAccess = FileAccess.open(OUT + "results.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	main.session.close()
	main.queue_free()
	await process_frame
	print("RESULT failures=", failures)
	quit(failures)
