extends SceneTree
## POC-08 UI / main-scene checks (headless OK): menus, input blocking, save / load through PocMain, display rebuild.
## godot --headless --path <repo> --script res://tests/poc/save/ui_logic.gd
## Own namespace user://poc_saves_test_ui/. No OS-level input: events are handed to the node directly.
const Session: GDScript = preload("res://scripts/poc/poc_session.gd")
const PocSave: GDScript = preload("res://scripts/poc/save/poc_save.gd")
const DIR: String = "user://poc_saves_test_ui/"

var failures: int = 0
var passes: int = 0

func check(name: String, ok: bool, detail: String = "") -> void:
	if ok:
		passes += 1
		print("PASS ", name, " ", detail)
	else:
		failures += 1
		print("FAIL ", name, " ", detail)

func _init() -> void:
	_run.call_deferred()

func clean() -> void:
	for file: String in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR + file)

func key(code: Key) -> InputEventKey:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	return event

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	clean()
	var main: Node = (load("res://scenes/poc.tscn") as PackedScene).instantiate()
	main.set_meta(&"poc_town", true)
	main.auto_process = false
	root.add_child(main)
	await process_frame
	main.save_dir = DIR
	check("start.no_title_for_embedded_instance", main.menu == &"" and not main.show_title_at_start and not main.ui.menu_open())
	check("start.keys_distinct", InputMap.has_action(&"poc_quick_save") and InputMap.has_action(&"poc_debug_refill") and InputMap.action_get_events(&"poc_quick_save")[0].physical_keycode != InputMap.action_get_events(&"poc_debug_refill")[0].physical_keycode)
	# --- pause menu
	main.tick(0.1, Vector2.ZERO)
	main._unhandled_input(key(KEY_ESCAPE))
	check("menu.esc_opens_pause", main.menu == &"pause" and main.session.paused and main.ui.menu_open() and main.ui.pause_panel.visible)
	var t0: float = main.session.clock.elapsed
	for i: int in 10:
		main.tick(0.1, Vector2(1, 0))
	check("menu.clock_frozen", main.session.clock.elapsed == t0)
	var blocked: Dictionary = main.click_fire(Vector2(300, 200), false)
	check("menu.click_is_not_game_input", not bool(blocked["ok"]) and String(blocked["reason"]) == "ui" and main.session.projectiles.shots.is_empty(), str(blocked))
	var seeds0: int = main.session.play.seeds
	main._unhandled_input(key(KEY_F9))
	main._unhandled_input(key(KEY_TAB))
	check("menu.keys_ignored_while_open", main.session.play.seeds == seeds0)
	check("menu.load_disabled_without_save", (main.ui.pause_buttons[&"load"] as Button).disabled)
	main._unhandled_input(key(KEY_ESCAPE))
	check("menu.esc_closes_and_resumes", main.menu == &"" and not main.session.paused and not main.ui.menu_open())
	# --- help
	main.open_pause_menu()
	main._on_ui_chosen(&"help")
	var help_text: String = "\n".join(main.ui.HELP_LINES)
	check("help.shows_controls", main.menu == &"help" and main.ui.help_panel.visible and not main.ui.pause_panel.visible and "W A S D" in help_text and "左クリック" in help_text and "右クリック" in help_text and "Tab" in help_text and "調べる　E" in help_text and "Esc" in help_text and "F2" in help_text and "F3" in help_text and "保存" in help_text and "読込" in help_text)
	main._unhandled_input(key(KEY_ESCAPE))
	check("help.esc_returns_to_pause", main.menu == &"pause" and main.ui.pause_panel.visible and not main.ui.help_panel.visible)
	main._unhandled_input(key(KEY_ESCAPE))
	# --- save through the UI, then play on and load
	for i: int in 30:
		main.tick(0.1, Vector2(1, 0))
	var saved_elapsed: float = main.session.clock.elapsed
	var saved_pos: Vector2 = main.session.position
	main.open_pause_menu()
	main._on_ui_chosen(&"save")
	await process_frame
	await process_frame
	check("save.slot_written_and_shown", PocSave.has_file(DIR, PocSave.SLOT_FILE) and main.ui.pause_message.text.contains("保存しました") and (main.ui.pause_buttons[&"load"] as Button).disabled == false, main.ui.pause_message.text)
	main.close_menu()
	main.ui.toast.visible = false
	main._unhandled_input(key(KEY_F5))
	check("save.f5_quick_save_toast", main.ui.toast.visible and main.ui.toast.text.contains("保存しました") and PocSave.has_file(DIR, PocSave.BACKUP_FILE), main.ui.toast.text)
	for i: int in 40:
		main.tick(0.1, Vector2(-1, 0))
	check("save.progressed_after_save", main.session.clock.elapsed > saved_elapsed + 3.0)
	var old_session: RefCounted = main.session
	var old_world: Node3D = main.world
	var old_placement: Node3D = main.placement_view
	main.open_pause_menu()
	main._on_ui_chosen(&"load")
	check("load.session_replaced", main.session != old_session and absf(main.session.clock.elapsed - (saved_elapsed + 0.0)) < 4.1 and main.menu == &"" and not main.session.paused, "elapsed %.3f saved %.3f" % [main.session.clock.elapsed, saved_elapsed])
	check("load.views_rebuilt", not is_instance_valid(old_world) and main.world != null and main.world.is_inside_tree() and main.placement_view != null and main.placement_view != old_placement and main.wall_view != null and main.enemy_view != null and main.occlusion_view != null and main.env_view != null and main.occlusion_view.is_inside_tree() and main.play_view != null)
	var f5_state: float = main.session.clock.elapsed
	main.tick(0.1, Vector2.ZERO)
	check("load.continues_from_game_clock", main.session.clock.elapsed > f5_state and main.session.clock.elapsed - f5_state < 0.11 and main.session.position.distance_to(saved_pos) < 400.0)
	main.tick(0.0, Vector2.ZERO)
	check("load.view_synced", main.enemy_view.snapshot_count() == main.session.enemies.boars.size() if main.enemy_view.has_method("snapshot_count") else true)
	# --- rejection keeps the running session
	var running: RefCounted = main.session
	var sig: String = PocSave.signature(running)
	var f: FileAccess = FileAccess.open(DIR + PocSave.SLOT_FILE, FileAccess.WRITE)
	f.store_string("{ not json")
	f.close()
	main.open_pause_menu()
	var rejected: Dictionary = main.load_game(false)
	check("reject.keeps_session_and_menu", not bool(rejected["ok"]) and main.session == running and PocSave.signature(running) == sig and main.menu == &"pause" and main.ui.pause_message.text.contains("読み込めません") and (main.ui.pause_buttons[&"backup"] as Button).visible, main.ui.pause_message.text)
	var rescued: Dictionary = main.load_game(true)
	check("reject.backup_loads", bool(rescued["ok"]) and main.session != running and main.menu == &"")
	# --- resolution setting round trip
	main.window_size_override = Vector2i(1920, 1080)
	main.set_resolution(1)
	main.save_game()
	main.set_resolution(0)
	var res_load: Dictionary = main.load_game(false)
	check("save.resolution_restored", main.resolution_index == 1 and main.render_view.size == Vector2i(960, 540), "index=%d load=%s" % [main.resolution_index, res_load.get("reason", "ok")])
	# --- title
	main.open_title()
	check("title.shows_with_continue_enabled", main.menu == &"title" and main.ui.title_panel.visible and not (main.ui.title_buttons[&"continue"] as Button).disabled and main.session.paused)
	var played: RefCounted = main.session
	main._on_ui_chosen(&"new_game")
	check("title.new_game_builds_fresh_session", main.menu == &"" and main.session != played and main.session.clock.elapsed == 0.0 and not main.session.paused and main.session.play.pickups.count() == 0)
	main.open_title()
	main._on_ui_chosen(&"continue")
	check("title.continue_loads", main.menu == &"" and main.session.clock.elapsed > 0.0, "elapsed %.2f" % main.session.clock.elapsed)
	clean()
	main.open_title()
	check("title.continue_disabled_without_save", (main.ui.title_buttons[&"continue"] as Button).disabled and main.ui.title_message.text.contains("ありません"))
	main.close_menu()
	# --- greening badge
	var st: WorldState = main.session.state
	main.tick(0.0, Vector2.ZERO)
	var badge_start: String = main.ui.badge.text
	check("badge.shows_floor_percent", badge_start.contains("内部緑化率 %d％" % st.greening_percent_floor()) and badge_start.contains("%d/%d" % [st.greened_count, st.target_count]) and not badge_start.contains("緑化完了★") , badge_start)
	for i: int in st.tile_count():
		if st.target[i] == 1 and st.stage[i] < WorldState.STAGE_SPROUT1:
			st.set_stage(i, WorldState.STAGE_MATURE)
	var last: int = -1
	for i: int in st.tile_count():
		if st.target[i] == 1 and st.stage[i] == WorldState.STAGE_MATURE:
			last = i
	st.set_stage(last, WorldState.STAGE_EMPTY)
	main.tick(0.0, Vector2.ZERO)
	check("badge.99_not_100", main.ui.badge.text.contains("内部緑化率 99％") and not main.ui.badge.text.contains("★"), main.ui.badge.text.get_slice("\n", 0))
	st.set_stage(last, WorldState.STAGE_MATURE)
	main.tick(0.0, Vector2.ZERO)
	check("badge.exact_100", main.ui.badge.text.contains("内部緑化率 100％") and main.ui.badge.text.contains("★"), main.ui.badge.text.get_slice("\n", 0))
	check("badge.zones_listed", main.ui.badge.text.contains(":") and main.zone_summary().length() > 0, main.zone_summary())
	clean()
	DirAccess.remove_absolute(DIR)
	main.queue_free()
	await process_frame
	print("RESULT passes=%d failures=%d" % [passes, failures])
	quit(1 if failures > 0 else 0)
