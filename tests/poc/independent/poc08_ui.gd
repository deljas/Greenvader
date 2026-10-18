extends SceneTree
## POC-08 independent verification (PocMain / UI level, headless). Own namespace user://poc_saves_indep/ only.
const Config: GDScript = preload("res://scripts/poc/poc_config.gd")
const PocSave: GDScript = preload("res://scripts/poc/save/poc_save.gd")
const DIR: String = "user://poc_saves_indep/"
var fails: int = 0
var passes: int = 0
var main: Node

func check(name: String, ok: bool, detail: String = "") -> void:
	if ok:
		passes += 1
	else:
		fails += 1
	print("PASS " if ok else "FAIL ", name, " ", detail)

func _init() -> void:
	_run.call_deferred()

func count_nodes(n: Node) -> int:
	var c: int = 1
	for ch: Node in n.get_children():
		c += count_nodes(ch)
	return c

func clean() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	for f: String in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR + f)

func write(file: String, text: String) -> void:
	var f: FileAccess = FileAccess.open(DIR + file, FileAccess.WRITE)
	f.store_string(text)
	f.close()

func click(pos: Vector2, button: int = MOUSE_BUTTON_LEFT) -> void:
	for pressed: bool in [true, false]:
		var e: InputEventMouseButton = InputEventMouseButton.new()
		e.button_index = button as MouseButton
		e.pressed = pressed
		e.position = pos
		e.global_position = pos
		e.button_mask = (1 << (button - 1)) if pressed else 0
		Input.parse_input_event(e)

func key(code: int) -> void:
	for pressed: bool in [true, false]:
		var e: InputEventKey = InputEventKey.new()
		e.physical_keycode = code as Key
		e.keycode = code as Key
		e.pressed = pressed
		Input.parse_input_event(e)

func frames(n: int) -> void:
	for i: int in n:
		await process_frame

func _run() -> void:
	clean()
	var scene: PackedScene = load("res://scenes/poc.tscn")
	main = scene.instantiate()
	main.set_meta(&"poc_town", true)
	main.save_dir = DIR
	main.auto_process = false
	root.add_child(main)
	await frames(3)
	var ui: Node = main.ui
	check("boot.town_session", main.session.combat_mode and main.session.state.target_count > 0, "targets=%d" % main.session.state.target_count)
	# --- title
	main.open_title()
	await frames(1)
	var cont: Button = ui.title_buttons[&"continue"]
	check("title.menu_and_paused", main.menu == &"title" and main.session.paused and ui.title_panel.visible and ui.dim.visible)
	check("title.continue_disabled_without_save", cont.disabled, cont.text)
	check("title.new_game_enabled", not (ui.title_buttons[&"new_game"] as Button).disabled)
	check("title.help_button", (ui.title_buttons[&"help"] as Button).visible)
	main.close_menu()
	# --- save a state, title enables continue
	main.session.play.add_seeds(10)
	main.session.advance_game(20.0)
	main.window_size_override = Vector2i(1920, 1080)
	check("res.set_960", main.set_resolution(1))
	var sr: Dictionary = main.save_game()
	check("save.ok", bool(sr["ok"]))
	main.open_title()
	check("title.continue_enabled_with_save", not cont.disabled, cont.text)
	main.close_menu()
	# --- help
	main.open_pause_menu()
	main.open_help()
	var label_text: String = ""
	for ch: Node in ui.help_panel.get_child(0).get_children():
		if ch is Label:
			label_text += (ch as Label).text
	check("help.visible_and_content", ui.help_panel.visible and label_text.contains("左クリック") and label_text.contains("Esc") and label_text.contains("100"), label_text.left(40))
	main._help_back()
	check("help.back_to_pause", main.menu == &"pause" and ui.pause_panel.visible and not ui.help_panel.visible)
	main.close_menu()
	# --- Esc via injected events
	await frames(2)
	key(KEY_ESCAPE)
	await frames(2)
	check("esc.opens_pause_menu", main.menu == &"pause" and main.session.paused, "menu=%s" % main.menu)
	key(KEY_ESCAPE)
	await frames(2)
	check("esc.closes_pause_menu", main.menu == &"" and not main.session.paused, "menu=%s paused=%s" % [main.menu, main.session.paused])
	# --- clicks
	main.session.play.add_seeds(20)
	var launched0: int = main.session.projectiles.launched
	var seeds0: int = main.session.play.seeds
	var center: Vector2 = Vector2(Config.RESOLUTIONS[main.resolution_index]) * 0.5
	click(center)
	await frames(2)
	var positive: int = main.session.projectiles.launched - launched0
	check("click.positive_control_fires_in_game", positive >= 1, "launched +%d (pos %s, res %s)" % [positive, center, Config.RESOLUTIONS[main.resolution_index]])
	main.open_pause_menu()
	print("DBG menu after open=", main.menu)
	await frames(2)
	print("DBG menu after frames=", main.menu)
	var l1: int = main.session.projectiles.launched
	var seeds1: int = main.session.play.seeds
	var w1: float = main.session.play.water
	var away: Vector2 = Vector2(100, 100)
	click(away)
	click(away, MOUSE_BUTTON_RIGHT)
	click(Vector2(860, 480))
	await frames(2)
	check("click.pause_menu_does_not_fire", main.session.projectiles.launched == l1 and main.session.play.seeds == seeds1 and main.session.play.water == w1, "launched %d->%d seeds %d->%d water %s->%s menu=%s dimrect=%s panel=%s" % [l1, main.session.projectiles.launched, seeds1, main.session.play.seeds, w1, main.session.play.water, main.menu, ui.dim.get_global_rect(), ui.pause_panel.get_global_rect()])
	main.open_help()
	click(away)
	await frames(2)
	check("click.help_does_not_fire", main.session.projectiles.launched == l1)
	main._help_back()
	main.close_menu()
	main.open_title()
	click(away)
	click(away, MOUSE_BUTTON_RIGHT)
	await frames(2)
	check("click.title_does_not_fire", main.session.projectiles.launched == l1 and main.menu == &"title")
	main.close_menu()
	# click on always-visible HUD buttons (resolution/pause button) must not fire
	var l2: int = main.session.projectiles.launched
	var btn: Button = main.pause_button
	var bp: Vector2 = btn.get_global_rect().get_center()
	click(bp)
	await frames(2)
	check("click.hud_button_does_not_fire", main.session.projectiles.launched == l2, "button at %s" % bp)
	main.session.paused = false
	# --- badge 99.x
	var st: WorldState = main.session.state
	var gc: int = st.greened_count
	st.greened_count = st.target_count - 1
	main._refresh()
	var t99: String = ui.badge.text.split("\n")[0]
	st.greened_count = st.target_count
	main._refresh()
	var t100: String = ui.badge.text.split("\n")[0]
	st.greened_count = gc
	main._refresh()
	check("badge.99x_not_shown_as_100", t99.contains("99") and not t99.contains("100") and not t99.contains("完了"), t99.replace("\n", " | ").left(70))
	check("badge.100_shows_complete", t100.contains("100") and t100.contains("完了"), t100.replace("\n", " | ").left(70))
	check("badge.shows_counts", t99.contains("%d/%d" % [st.target_count - 1, st.target_count]))
	# --- rejection via main: nothing changes
	main.session.advance_game(30.0)
	main.save_game()
	var good_text: String = FileAccess.get_file_as_string(DIR + "slot.json")
	var base_sig: String = PocSave.signature(main.session)
	var base_nodes: int = count_nodes(main)
	var base_session: RefCounted = main.session
	var base_occ: PackedInt32Array = main.session.state.occupant.duplicate()
	var base_views: Array = [main.world, main.enemy_view, main.play_view, main.wall_view]
	var bad: Dictionary = {}
	var d: Dictionary = JSON.parse_string(good_text)
	d["format_version"] = 9
	bad["version"] = JSON.stringify(d)
	d = JSON.parse_string(good_text)
	d["map_hash"] = "f".repeat(32)
	bad["map_hash"] = JSON.stringify(d)
	d = JSON.parse_string(good_text)
	d["map_id"] = "other_map"
	bad["map_id"] = JSON.stringify(d)
	bad["corrupt"] = good_text.left(good_text.length() / 3)
	d = JSON.parse_string(good_text)
	d["world"].erase("occupant")
	bad["missing_key"] = JSON.stringify(d)
	d = JSON.parse_string(good_text)
	d["session"]["position"] = [-100.0, -100.0]
	bad["pos_out"] = JSON.stringify(d)
	d = JSON.parse_string(good_text)
	var raw: PackedByteArray = WorldState._unpack_bytes(d["world"]["stage"])
	raw[200] = 222
	d["world"]["stage"] = WorldState._pack_bytes(raw)
	bad["stage_out"] = JSON.stringify(d)
	for name: String in bad:
		write("slot.json", String(bad[name]))
		main.open_pause_menu()
		var res: Dictionary = main.load_game(false)
		var msg: String = ui.pause_message.text
		var same: bool = main.session == base_session and PocSave.signature(main.session) == base_sig and main.session.state.occupant == base_occ and count_nodes(main) == base_nodes and main.world == base_views[0] and main.enemy_view == base_views[1] and main.play_view == base_views[2] and main.wall_view == base_views[3]
		check("reject_in_main." + name, not bool(res["ok"]) and same and main.menu == &"pause" and msg.begins_with("読み込めません"), "msg=%s nodes %d/%d" % [msg.left(40), count_nodes(main), base_nodes])
		main.close_menu()
	# --- good load rebuilds views without accumulating nodes
	write("slot.json", good_text)
	var counts: Array[int] = []
	var sig_ok: bool = true
	for k: int in 3:
		var res2: Dictionary = main.load_game(false)
		counts.append(count_nodes(main))
		sig_ok = sig_ok and bool(res2["ok"]) and PocSave.signature(main.session) == base_sig
	check("load_in_main.session_equal_and_node_count_stable", sig_ok and counts[0] == counts[1] and counts[1] == counts[2], "nodes %s (before %d)" % [str(counts), base_nodes])
	check("load_in_main.resolution_restored", main.resolution_index == 1, "idx=%d" % main.resolution_index)
	check("load_in_main.menu_closed_and_running", main.menu == &"" and not main.session.paused)
	# --- time through main
	main.open_pause_menu()
	var e0: float = main.session.clock.elapsed
	main.tick(5.0, Vector2.ZERO)
	main.tick(5.0, Vector2.ZERO)
	check("time.menu_open_clock_frozen", main.session.clock.elapsed == e0)
	main.close_menu()
	main.tick(5.0, Vector2.ZERO)
	var dt: float = main.session.clock.elapsed - e0
	check("time.resume_no_lump_sum", dt > 0.0 and dt <= Config.MAX_STEP_S * main.session.multiplier + 0.001, "advanced %.3f" % dt)
	# new game via button
	(ui.pause_buttons[&"title"] as Button).pressed.emit()
	await frames(1)
	check("title.from_pause_menu", main.menu == &"title")
	(ui.title_buttons[&"new_game"] as Button).pressed.emit()
	await frames(2)
	check("newgame.fresh_session", main.menu == &"" and main.session != base_session and main.session.clock.elapsed < 1.0 and main.session.state.greened_count < st.target_count, "elapsed=%.2f" % main.session.clock.elapsed)
	var f1: String = FileAccess.get_file_as_string(DIR + "slot.json")
	check("newgame.keeps_save_file", f1 == good_text)
	clean()
	main.queue_free()
	await frames(2)
	print("RESULT passes=%d failures=%d" % [passes, fails])
	quit(1 if fails > 0 else 0)
