extends SceneTree
## Independent GPU/input: items 10 (map left-drag) and 12 (relocation guidance), engine-injected input only.
const Coords: GDScript = preload("res://scripts/poc/poc_coords.gd")
const OUT: String = "res://evidence/poc3/playtest01/independent/gpu_c/"
var main: Node
var s: RefCounted
var capture: SubViewport
var ui: Control
var checks: Array[Dictionary] = []
var pointer: Vector2 = Vector2.ZERO
func _init() -> void: call_deferred("run")
func chk(n: String, ok: bool, d: Variant = "") -> void:
	checks.append({"name": n, "status": "PASS" if ok else "FAIL", "detail": d})
	print(JSON.stringify(checks.back()))
func frames(n: int = 2) -> void:
	for i: int in n: await process_frame
func motion(at: Vector2, held: bool = false) -> void:
	var e: InputEventMouseMotion = InputEventMouseMotion.new()
	e.position = at; e.global_position = at; e.relative = at - pointer
	e.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	pointer = at
	root.push_input(e, true)
func button(at: Vector2, pressed: bool, which: int = MOUSE_BUTTON_LEFT) -> void:
	var e: InputEventMouseButton = InputEventMouseButton.new()
	e.position = at; e.global_position = at; e.button_index = which; e.pressed = pressed
	root.push_input(e, true)
func key(code: int) -> void:
	for down: bool in [true, false]:
		var e: InputEventKey = InputEventKey.new()
		e.physical_keycode = code; e.keycode = code; e.pressed = down
		root.push_input(e, true)
		await frames(1)
func shot(file: String) -> void:
	await frames(2); RenderingServer.force_draw(false)
	capture.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT + file))
func scr(c: Vector2i) -> Vector2:
	return main.world.camera.unproject_position(Coords.ground3(Coords.logic_to_ground(Coords.cell_center_logic(c))))
func click(at: Vector2) -> void:
	motion(at); button(at, true); await frames(2); button(at, false); await frames(3)

func run() -> void:
	var safe: bool = root.unfocusable and root.mode == Window.MODE_MINIMIZED
	chk("startup_no_focus_minimized", safe)
	if not safe: quit(1); return
	change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene"))
	await frames()
	main = current_scene
	main.auto_process = false
	main._audio_changed(true, 0.0)
	main._on_action("new")
	root.notify_mouse_entered()
	s = main.session
	s.enemies.clear(); s.nests.clear(); s.fossils.clear()
	capture = SubViewport.new()
	capture.size = Vector2i(640, 360); capture.disable_3d = true
	capture.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(capture)
	main.view_rect.reparent(capture); main.ui.reparent(capture)
	ui = main.ui
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	s.unlocked["army"] = true; s.unlocked["sprinkler"] = true
	s.favorites.assign(["clover", "", "", "army", "sprinkler"])
	s.seeds = 1000
	main.tick(0.0); await frames(2)
	# ---- item 12a: first helper placement via real mouse click shows the one-time notice
	await key(KEY_4)
	main.tick(0.0)
	var pc: Vector2i = Coords.logic_to_cell(s.position)
	var cell: Vector2i = pc + Vector2i(4, 2)
	for _i: int in 6:
		if bool(s.can_place("army", cell).get("ok", false)): break
		cell += Vector2i(1, 1)
	var at: Vector2 = scr(cell)
	motion(at); await frames(1); main.tick(0.0)
	button(at, true); await frames(1); main.tick(0.016); button(at, false); await frames(2)
	chk("item12_first_helper_placement_notice", s.helpers.size() == 1 and ui.notice.visible and ui.notice.text.contains("配置換え") and ui.notice.text.contains("Tab") and ui.notice_time > 5.0, [ui.notice.text, ui.notice_time, s.helpers.size()])
	await shot("placement_notice.png")
	# second helper (sprinkler): no repeat
	ui.notice.text = ""; ui.notice_time = 0.0
	await key(KEY_ESCAPE)
	await key(KEY_5)
	var cell2: Vector2i = pc + Vector2i(-4, 3)
	for _i: int in 6:
		if bool(s.can_place("sprinkler", cell2).get("ok", false)): break
		cell2 += Vector2i(-1, 1)
	var at2: Vector2 = scr(cell2)
	motion(at2); await frames(1); main.tick(0.0)
	button(at2, true); await frames(1); main.tick(0.016); button(at2, false); await frames(2)
	chk("item12_notice_not_repeated", s.helpers.size() == 2 and not ui.notice.text.contains("配置換え"), [s.helpers.size(), ui.notice.text])
	main._placement_kind = ""; ui.clear_selection(); main.tick(0.0)
	# ---- map open, hint text follows state
	await key(KEY_TAB); await frames(4)
	chk("item12_map_hint_when_nothing_selected", ui.map.expanded and ui.map.hint.visible and ui.map.hint.text.contains("おたすけ植物を選ぶと移動先"), ui.map.hint.text)
	await shot("map_hint_none.png")
	var army: Dictionary = {}
	for h: Dictionary in s.helpers:
		if h.kind == "army": army = h
	var ia: Vector2 = ui.map.point(army.pos)
	await click(ia)
	chk("item12_hint_when_helper_selected", ui.map.selected_id == int(army.id) and ui.map.hint.text.contains("移動先を左クリック"), [ui.map.selected_id, ui.map.hint.text])
	await shot("map_hint_selected.png")
	# follow the hint exactly: left click a walkable destination on the map
	var dest: Vector2 = army.pos + Vector2(100, 40)
	var found: bool = false
	for off: Vector2 in [Vector2(100, 40), Vector2(-100, -40), Vector2(60, -90), Vector2(-60, 90), Vector2(150, 0)]:
		var c: Vector2i = Coords.logic_to_cell(army.pos + off)
		var mp: Vector2 = ui.map.point(army.pos + off)
		if s.state.in_bounds(c.x, c.y) and s.state.is_walkable(c.x, c.y) and ui.map.map_rect.grow(-8).has_point(mp):
			dest = army.pos + off; found = true; break
	var home0: Vector2 = army.home
	await click(ui.map.point(dest))
	chk("item12_following_the_hint_relocates_helper", found and army.home.distance_to(home0) > 4.0 and army.home.distance_to(dest) < 16.0, [home0, army.home, dest])
	# right click deselects as stated in hint
	await click(ui.map.point(army.pos))
	var sel: bool = ui.map.selected_id == int(army.id)
	button(Vector2(300, 170), true, MOUSE_BUTTON_RIGHT); await frames(1); button(Vector2(300, 170), false, MOUSE_BUTTON_RIGHT); await frames(2)
	chk("item12_right_click_deselects_as_hinted", sel and ui.map.selected_id == -1, ui.map.selected_id)
	# ---- item 10
	var c0: Vector2 = ui.map.map_center
	var p0: Vector2 = Vector2(320, 176)
	motion(p0); button(p0, true); await frames(1)
	motion(p0 + Vector2(50, 30), true); await frames(2)
	chk("item10_unzoomed_drag_does_not_slide", ui.map.map_center == c0, ui.map.map_center)
	button(p0 + Vector2(50, 30), false); await frames(2)
	for i: int in 2:
		motion(Vector2(320, 176)); button(Vector2(320, 176), true, MOUSE_BUTTON_WHEEL_UP); button(Vector2(320, 176), false, MOUSE_BUTTON_WHEEL_UP); await frames(2)
	chk("item10_zoomed", ui.map.zoom >= 2, ui.map.zoom)
	await frames(3)
	await shot("zoom_before.png")
	ui.map.deselect(); await frames(2)
	var cb: Vector2 = ui.map.map_center
	var st: Vector2 = Vector2(300, 170)
	motion(st); button(st, true); await frames(1)
	chk("dbg_press_state", true, {"press_active": ui.map._press_active, "popup": ui.map.popup.visible, "sel": ui.map.selected_id, "zoom": ui.map.zoom, "rb": ui.map.remove_button.visible, "paused": main.is_paused(), "menu": main.menu})
	motion(st + Vector2(3, 0), true); await frames(1)
	chk("item10_3px_is_not_a_drag", ui.map.map_center == cb and not ui.map.dragging)
	motion(st + Vector2(60, 30), true); await frames(2)
	var cm: Vector2 = ui.map.map_center
	chk("item10_60px_drag_moves_map", cm != cb and ui.map.dragging, [cb, cm])
	var shift: Vector2 = ui.map.point(cb) - ui.map.point(cm)
	chk("item10_map_follows_cursor_exact", shift.distance_to(Vector2(63, 30) - Vector2(3, 0)) < 2.5 or shift.distance_to(Vector2(60, 30)) < 2.5, [shift])
	await shot("zoom_dragged.png")
	button(st + Vector2(60, 30), false); await frames(2)
	chk("item10_release_after_drag_no_selection_no_command", ui.map.selected_id == -1 and not ui.map.dragging, ui.map.selected_id)
	# drag far in all directions: clamp
	for d: Vector2 in [Vector2(2000, 2000), Vector2(-2000, -2000)]:
		motion(Vector2(300, 170)); button(Vector2(300, 170), true); await frames(1); motion(Vector2(300, 170) + d, true); await frames(2); button(Vector2(300, 170) + d, false); await frames(2)
		var ctr: Vector2 = ui.map.map_center
		chk("item10_center_inside_world_after_extreme_drag_%d" % int(signf(d.x)), (ctr.x >= 0.0 and ctr.y >= 0.0 and ctr.x <= s.state.width * 4.0 and ctr.y <= s.state.height * 4.0), ctr)
	# click (<4px) on helper icon while zoomed selects it; click on ground relocates it
	ui.map.map_center = army.home; await frames(4)
	var ic: Vector2 = ui.map.point(army.pos)
	motion(ic); button(ic, true); await frames(1); motion(ic + Vector2(2, 1), true); await frames(1); button(ic + Vector2(2, 1), false); await frames(3)
	chk("item10_small_motion_click_selects_icon", ui.map.selected_id == int(army.id), ui.map.selected_id)
	var h0: Vector2 = army.home
	motion(ic); button(ic, true); await frames(1); motion(ic + Vector2(40, 0), true); await frames(1); button(ic + Vector2(40, 0), false); await frames(3)
	chk("item10_drag_starting_on_icon_does_not_relocate", army.home == h0, [h0, army.home])
	await key(KEY_TAB); await frames(2)
	chk("item10_map_closes_clean", not ui.map.expanded and not ui.map.dragging)
	# ---- F1 help text
	await key(KEY_F1); await frames(2)
	var help_text: String = ""
	for ch: Node in ui.help.find_children("*", "Label", true, false): help_text += (ch as Label).text
	chk("item12_help_text_mentions_relocation_and_drag", help_text.contains("配置換え") and help_text.contains("左ドラッグ"), help_text.length())
	await shot("help.png")
	var f: int = 0
	for r: Dictionary in checks:
		if r.status == "FAIL": f += 1
	var fa: FileAccess = FileAccess.open(OUT + "results.json", FileAccess.WRITE)
	fa.store_string(JSON.stringify({"checks": checks, "failures": f}, "  ")); fa.close()
	quit(1 if f else 0)
