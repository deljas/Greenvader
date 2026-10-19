extends SceneTree
## POL-02 text toggle (T) checks (headless OK): godot --headless --path <repo> --script res://tests/poc/polish/text_toggle.gd
## Input is injected inside Godot only (Input.parse_input_event); no OS input, cursor or window focus.
const SAVE_DIR: String = "user://pol02_save/"
const Config: GDScript = preload("res://scripts/poc/poc_config.gd")
const Coords: GDScript = preload("res://scripts/poc/poc_coords.gd")
var failures: int = 0
var passes: int = 0
var main: Node
var s: RefCounted

func check(name: String, ok: bool, detail: String = "") -> void:
	print("PASS " if ok else "FAIL ", name, " ", detail)
	if ok:
		passes += 1
	else:
		failures += 1

func _init() -> void:
	_run.call_deferred()

func frames(n: int) -> void:
	for i: int in n:
		await process_frame

func press(code: Key) -> void:
	var ev: InputEventKey = InputEventKey.new()
	ev.physical_keycode = code
	ev.keycode = code
	ev.pressed = true
	Input.parse_input_event(ev)
	await frames(2)
	ev = InputEventKey.new()
	ev.physical_keycode = code
	ev.keycode = code
	ev.pressed = false
	Input.parse_input_event(ev)
	await frames(1)

## The nine texts: true when all are shown (visible in tree), false when all are hidden; null when mixed.
func state(viewing: bool) -> Variant:
	var list: Array[bool] = [main.notice.is_visible_in_tree(), main.button_box.is_visible_in_tree(), main.ui.badge.is_visible_in_tree()]
	list.append(main.view_panel.is_visible_in_tree() if viewing else main.hud.is_visible_in_tree())
	for v: bool in list:
		if v != list[0]:
			return null
	return list[0]

func sig() -> String:
	return "%d/%d/%d/%d" % [hash(s.state.terrain), hash(s.state.plant_id), s.state.greened_count, s.play.seeds]

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SAVE_DIR))
	main = load("res://scenes/poc.tscn").instantiate()
	main.set_meta(&"poc_town", true)
	main.save_dir = SAVE_DIR
	root.add_child(main)
	main.auto_process = false
	main.window_size_override = Vector2i(1920, 1080)
	await frames(3)
	s = main.session
	check("input.action_registered", InputMap.has_action(&"poc_toggle_text") and InputMap.action_get_events(&"poc_toggle_text")[0].physical_keycode == KEY_T)
	check("help.has_T_line", "\n".join(main.ui.HELP_LINES).contains("T　画面の文字"))
	check("start.visible", main.text_visible and state(false) == true)
	for res_index: int in 2:
		main.set_resolution(res_index, Vector2i(1920, 1080))
		main.show_notice("テスト通知")
		main.tick(0.05, Vector2.ZERO)
		var tag: String = "res%d." % Config.RESOLUTIONS[res_index].x
		check(tag + "shown", state(false) == true)
		await press(KEY_T)
		check(tag + "T_hides", not main.text_visible and state(false) == false, "hud=%s notice=%s btn=%s badge=%s" % [main.hud.visible, main.notice.visible, main.button_box.visible, main.ui.badge.visible])
		main.tick(0.05, Vector2.ZERO)
		check(tag + "stays_hidden_after_tick", state(false) == false)
		await press(KEY_T)
		check(tag + "T_shows", main.text_visible and state(false) == true and main.notice.text == "テスト通知")
	# hidden notice / toast do not show, and come back with the current content
	await press(KEY_T)
	main.show_notice("隠れ中の通知")
	main.ui.show_toast("隠れ中のトースト", 30.0)
	main.tick(0.05, Vector2.ZERO)
	check("hidden.notice_toast_not_shown", not main.notice.is_visible_in_tree() and not main.ui.toast.is_visible_in_tree())
	await press(KEY_T)
	check("hidden.restored_current", main.notice.is_visible_in_tree() and main.notice.text == "隠れ中の通知" and main.ui.toast.is_visible_in_tree() and main.ui.toast.text == "隠れ中のトースト" and main.hud.is_visible_in_tree() and main.hud.text.contains("種"))
	main.ui.show_toast("x", 0.01)
	main.ui.tick(0.1)
	check("toast.expires", not main.ui.toast.visible)
	# click on the top-right button position
	var pos: Vector2 = main.pause_button.get_global_rect().get_center()
	var shown_pick: Dictionary = main.pick_ground(pos)
	check("click.visible_blocks", not shown_pick["ok"] and shown_pick["reason"] == "ui", str(shown_pick.get("reason")))
	await press(KEY_T)
	var hidden_pick: Dictionary = main.pick_ground(pos)
	check("click.hidden_passes_to_ground", hidden_pick["ok"] or String(hidden_pick["reason"]) != "ui", str(hidden_pick.get("reason")))
	if hidden_pick["ok"]:
		var seeds_before: int = s.play.seeds
		var ev: InputEventMouseButton = InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_RIGHT
		ev.position = pos
		ev.pressed = true
		Input.parse_input_event(ev)
		await frames(2)
		check("click.hidden_acts_on_ground", s.has_aim and s.aim.distance_to(hidden_pick["logic"]) < 1.0, "aim=%s" % str(s.aim))
		ev = InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_RIGHT
		ev.position = pos
		ev.pressed = false
		Input.parse_input_event(ev)
		await frames(1)
	var paused_before: bool = s.paused
	await press(KEY_T)
	check("click.shown_again_blocks", String(main.pick_ground(pos)["reason"]) == "ui" and s.paused == paused_before)
	# menus: T ignored, menu readable, hidden setting kept
	await press(KEY_T)  # hidden
	main.open_pause_menu()
	await frames(2)
	await press(KEY_T)
	check("menu.T_ignored", not main.text_visible and main.ui.pause_panel.is_visible_in_tree() and main.ui.dim.is_visible_in_tree())
	main.open_help()
	await press(KEY_T)
	check("menu.help_readable", main.ui.help_panel.is_visible_in_tree() and not main.text_visible)
	main.close_menu()
	check("menu.hidden_kept_after_close", not main.text_visible and state(false) == false)
	await press(KEY_T)
	main.open_title()
	await press(KEY_T)
	check("menu.title_T_ignored", main.text_visible and main.ui.title_panel.is_visible_in_tree())
	main.close_menu()
	# viewpoint
	var v: RefCounted = main.viewpoint
	s.position = Coords.cell_center_logic(v.cell) + Vector2(14, 0)
	main.tick(0.1, Vector2.ZERO)
	for res_index: int in 2:
		main.set_resolution(res_index, Vector2i(1920, 1080))
		var tag2: String = "view%d." % Config.RESOLUTIONS[res_index].x
		check(tag2 + "enter", main.enter_viewpoint() and main.is_viewing())
		check(tag2 + "panel_shown", state(true) == true and not main.hud.visible)
		var before: String = sig()
		await press(KEY_T)
		check(tag2 + "T_hides_panel", not main.text_visible and state(true) == false and not main.view_panel.visible)
		main.tick(0.1, Vector2.ZERO)
		check(tag2 + "stays_hidden", state(true) == false and main.is_viewing())
		await press(KEY_T)
		check(tag2 + "T_shows_panel", main.text_visible and state(true) == true and main.view_panel.label.text != "")
		# hide, leave, re-enter: still hidden
		await press(KEY_T)
		main.leave_viewpoint()
		check(tag2 + "leave_keeps_hidden", not main.text_visible and state(false) == false and not main.view_panel.visible)
		check(tag2 + "enter_hidden_no_panel", main.enter_viewpoint() and not main.view_panel.is_visible_in_tree())
		await press(KEY_T)
		check(tag2 + "restore_panel", main.view_panel.is_visible_in_tree() and main.view_panel.label.text != "")
		check(tag2 + "world_unchanged", sig() == before)
		main.leave_viewpoint()
	# save / load: format v2 unchanged, state not saved
	var save_res: Dictionary = main.save_game()
	check("save.ok", bool(save_res["ok"]), str(save_res.get("reason", "")))
	var files: PackedStringArray = DirAccess.get_files_at(SAVE_DIR)
	var text: String = ""
	for name_: String in files:
		if name_.ends_with(".json") and not name_.contains("backup"):
			text = FileAccess.get_file_as_string(SAVE_DIR + name_)
			break
	var data: Variant = JSON.parse_string(text)
	check("save.format_v2_no_text_key", data is Dictionary and int((data as Dictionary).get("format_version", -1)) == 2 and not text.contains("text_visible") and not text.contains("toggle_text"), "files=%s" % str(files))
	if data is Dictionary:
		check("save.sections_unchanged", (data as Dictionary).has("ui") and ((data as Dictionary)["ui"] as Dictionary).keys().size() <= 3, str(((data as Dictionary)["ui"] as Dictionary).keys()))
	await press(KEY_T)  # hidden
	var lr: Dictionary = main.load_game(false)
	check("load.ok", bool(lr["ok"]))
	check("load.hidden_kept", not main.text_visible and state(false) == false)
	await press(KEY_T)
	check("load.shown_again", main.text_visible and state(false) == true)
	# fresh boot is visible
	var main2: Node = load("res://scenes/poc.tscn").instantiate()
	main2.set_meta(&"poc_town", true)
	main2.save_dir = SAVE_DIR
	root.add_child(main2)
	main2.auto_process = false
	await frames(2)
	check("boot.visible_default", main2.text_visible and main2.hud.visible and main2.button_box.visible)
	print("RESULT passes=%d failures=%d" % [passes, failures])
	quit(1 if failures > 0 else 0)
