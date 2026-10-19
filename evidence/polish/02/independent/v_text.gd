extends SceneTree
## POL-02 independent check. Input only via Input.parse_input_event.
const SAVE_DIR: String = "user://pol02v_save/"
const Coords: GDScript = preload("res://scripts/poc/poc_coords.gd")
var f: int = 0
var p: int = 0
var main: Node
var s: RefCounted
func check(n: String, ok: bool, d: String = "") -> void:
	print("PASS " if ok else "FAIL ", n, " ", d)
	if ok: p += 1
	else: f += 1
func frames(n: int) -> void:
	for i: int in n: await process_frame
func key(code: Key) -> void:
	for pr: bool in [true, false]:
		var ev: InputEventKey = InputEventKey.new()
		ev.physical_keycode = code
		ev.keycode = code
		ev.pressed = pr
		Input.parse_input_event(ev)
		await frames(2)
func click(pos: Vector2, btn: MouseButton) -> void:
	for pr: bool in [true, false]:
		var ev: InputEventMouseButton = InputEventMouseButton.new()
		ev.button_index = btn
		ev.position = pos
		ev.pressed = pr
		Input.parse_input_event(ev)
		await frames(2)
func texts_vis() -> Array:
	return [main.notice.is_visible_in_tree(), main.button_box.is_visible_in_tree(), main.ui.badge.is_visible_in_tree(), main.hud.is_visible_in_tree(), main.view_panel.is_visible_in_tree(), main.ui.toast.is_visible_in_tree()]
func _init() -> void:
	_run.call_deferred()
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
	main.close_menu()
	await frames(2)
	check("boot.menu_state", main.menu == &"", str(main.menu))
	check("boot.visible", texts_vis().slice(0, 4) == [true, true, true, true], str(texts_vis()))
	# F2 while hidden
	await key(KEY_T)
	var r0: Vector2i = main.current_resolution()
	await key(KEY_F2)
	check("f2.res_changed", main.current_resolution() != r0)
	check("f2.stays_hidden", not main.text_visible and texts_vis().slice(0, 4) == [false, false, false, false], str(texts_vis()))
	await key(KEY_F2)
	check("f2.back_hidden", main.current_resolution() == r0 and texts_vis().slice(0, 4) == [false, false, false, false])
	# hidden click at the button spot acts on ground
	var pos: Vector2 = main.pause_button.get_global_rect().get_center()
	var pk: Dictionary = main.pick_ground(pos)
	var before_launch: int = s.projectiles.launched
	var paused0: bool = s.paused
	await click(pos, MOUSE_BUTTON_LEFT)
	check("click.hidden_ground_pick", pk["ok"], str(pk))
	check("click.hidden_no_pause_toggle", s.paused == paused0)
	check("click.hidden_fired", s.projectiles.launched > before_launch or s.has_aim, "launched %d->%d aim=%s" % [before_launch, s.projectiles.launched, s.has_aim])
	# menu open/close while hidden through Esc
	await key(KEY_ESCAPE)
	check("menu.open_by_esc", main.menu == &"pause" and main.ui.pause_panel.is_visible_in_tree())
	await key(KEY_T)
	check("menu.T_ignored", not main.text_visible and main.ui.pause_panel.is_visible_in_tree())
	await key(KEY_ESCAPE)
	check("menu.closed_still_hidden", main.menu == &"" and texts_vis().slice(0, 4) == [false, false, false, false])
	# state change while hidden, restore shows latest
	main.show_notice("隠れ中A")
	for i: int in 20: main.tick(0.1, Vector2.ZERO)
	var hud_now: String = main.hud.text
	await key(KEY_T)
	check("restore.latest_hud", main.hud.is_visible_in_tree() and main.hud.text == hud_now and main.hud.text.contains(str(s.play.seeds)))
	check("restore.notice", main.notice.is_visible_in_tree() and main.notice.text.length() > 0, main.notice.text)
	# save/load while hidden
	await key(KEY_T)
	await key(KEY_F5)
	var files: PackedStringArray = DirAccess.get_files_at(SAVE_DIR)
	check("save.f5_hidden_file", files.size() > 0, str(files))
	check("save.toast_hidden", not main.ui.toast.is_visible_in_tree() and not main.text_visible)
	var lr: Dictionary = main.load_game(false)
	check("load.ok_hidden", lr["ok"] and not main.text_visible and texts_vis().slice(0, 4) == [false, false, false, false] and not main.ui.toast.is_visible_in_tree(), str(texts_vis()))
	s = main.session
	# viewpoint enter/leave via E while hidden
	var v: RefCounted = main.viewpoint
	s.position = Coords.cell_center_logic(v.cell) + Vector2(14, 0)
	main.tick(0.1, Vector2.ZERO)
	await key(KEY_E)
	check("view.enter_hidden", main.is_viewing() and not main.view_panel.is_visible_in_tree() and not main.hud.is_visible_in_tree(), str(texts_vis()))
	await key(KEY_F2)
	check("view.f2_hidden", main.is_viewing() and not main.view_panel.is_visible_in_tree())
	await key(KEY_F2)
	await key(KEY_T)
	check("view.T_shows_panel", main.view_panel.is_visible_in_tree() and not main.hud.is_visible_in_tree() and main.view_panel.label.text != "" and main.button_box.is_visible_in_tree())
	# other keys in view unchanged: F5 / Q / Tab do nothing
	var spd: float = s.multiplier
	await key(KEY_F3)
	check("view.F3_ignored", s.multiplier == spd)
	await key(KEY_T)
	await key(KEY_ESCAPE)
	check("view.esc_leaves_hidden", not main.is_viewing() and main.menu == &"" and not main.text_visible and not main.hud.is_visible_in_tree())
	await key(KEY_T)
	check("view.left_hud_back", main.hud.is_visible_in_tree() and not main.view_panel.is_visible_in_tree())
	# toast shown, hide, expire, show
	main.ui.show_toast("t", 0.5)
	await key(KEY_T)
	main.ui.tick(1.0)
	await key(KEY_T)
	check("toast.expired_not_resurrected", not main.ui.toast.is_visible_in_tree())
	# new game from title while hidden
	await key(KEY_T)
	main.open_title()
	await frames(1)
	await key(KEY_T)
	check("title.T_ignored", not main.text_visible)
	main.new_game()
	await frames(2)
	check("newgame.stays_hidden", not main.text_visible and texts_vis().slice(0, 4) == [false, false, false, false] and main.menu == &"")
	print("RESULT passes=%d failures=%d" % [p, f])
	quit(1 if f > 0 else 0)
