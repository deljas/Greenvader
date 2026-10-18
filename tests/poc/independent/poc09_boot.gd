extends SceneTree
## POC-09 independent verification, conditions 4 and 5 (headless): start-up path and display/internal separation.
##   godot --headless --path <repo> --script res://tests/poc/independent/poc09_boot.gd
## Condition 5 loads scenes/poc.tscn as the main scene with NO arguments (change_scene_to_file), presses the title's New Game button,
## and checks town_01 starts. Condition 4 compares a display-free session with the same session behind PocMain whose ground-cover density is 0.
const Session: GDScript = preload("res://scripts/poc/poc_session.gd")
const OUT: String = "res://evidence/poc/09/independent/"
var passes: int = 0
var fails: int = 0
var lines: PackedStringArray = PackedStringArray()

func check(name: String, ok: bool, detail: String = "") -> void:
	if ok:
		passes += 1
	else:
		fails += 1
	var line: String = "%s %s %s" % ["PASS" if ok else "FAIL", name, detail]
	lines.append(line)
	print(line)

func info(text: String) -> void:
	lines.append("INFO " + text)
	print("INFO ", text)

func _init() -> void:
	_run.call_deferred()

func sha(b: PackedByteArray) -> String:
	var c: HashingContext = HashingContext.new()
	c.start(HashingContext.HASH_SHA256)
	c.update(b)
	return c.finish().hex_encode().substr(0, 16)

func world_sig(m: RefCounted) -> String:
	var st: WorldState = m.state
	return JSON.stringify([sha(st.stage), sha(st.plant_id), sha(st.growth.to_byte_array()), sha(st.moisture), st.greened_count, st.target_count, Array(st.zone_state), m.clock.growth_ticks, m.clock.spread_ticks, m.far.ticks, m.enemies.boars.size()])

func _run() -> void:
	# ---------------- 5: launchers and entry points
	var proj: String = FileAccess.get_file_as_string("res://project.godot")
	var main_scene: String = ""
	for ln: String in proj.split("\n"):
		if ln.begins_with("run/main_scene="):
			main_scene = ln.substr(15).strip_edges().trim_prefix("\"").trim_suffix("\"")
	check("normal_entry_is_old_game", main_scene == "res://scenes/main.tscn", main_scene)
	var rg: String = FileAccess.get_file_as_string("res://run_game.bat")
	check("run_game_bat_is_old_game", not rg.contains("poc") and rg.contains("--path"), "no poc reference")
	var rp: String = FileAccess.get_file_as_string("res://launchers/run_poc.bat")
	check("run_poc_bat_launches_poc_scene", rp.contains("res://scenes/poc.tscn") and rp.contains("--path"), rp.replace("\n", " | ").replace("\r", ""))
	check("poc_scene_exists", ResourceLoader.exists("res://scenes/poc.tscn"))
	# Load poc.tscn as the main scene without any argument
	var err: int = change_scene_to_file("res://scenes/poc.tscn")
	check("change_scene_to_file_ok", err == OK)
	for i: int in 6:
		await process_frame
	var main: Node = current_scene
	check("poc_is_current_scene", main != null and main.scene_file_path == "res://scenes/poc.tscn", str(main))
	if main == null:
		_finish()
		return
	check("title_shown_at_start", main.menu == &"title" and main.show_title_at_start, "menu=%s" % str(main.menu))
	check("title_session_is_town_01", main.session.combat_mode and main.session.state.width == 112 and main.session.state.height == 112, "%dx%d" % [main.session.state.width, main.session.state.height])
	var game_clock0: float = main.session.clock.elapsed
	for i: int in 10:
		await process_frame
	check("game_time_frozen_on_title", main.session.clock.elapsed == game_clock0, "elapsed %.3f" % main.session.clock.elapsed)
	var btn: Button = main.ui.title_buttons[&"new_game"] as Button
	check("new_game_button_exists", btn != null and btn.visible and not btn.disabled)
	btn.pressed.emit()
	for i: int in 4:
		await process_frame
	check("title_closed_after_new_game", main.menu == &"")
	var start_cell: Vector2i = Vector2i(floori(main.session.position.x / 4.0), floori(main.session.position.y / 4.0))
	check("town_01_started", main.session.combat_mode and start_cell == Vector2i(88, 86) and main.session.enemies.nests.size() == 3 and main.session.state.zone_count == 2 and not main.session.debug_refill_enabled, "start cell %s nests=%d zones=%d" % [str(start_cell), main.session.enemies.nests.size(), main.session.state.zone_count])
	main.tick(0.25, Vector2.ZERO)
	check("game_runs_after_new_game", main.session.clock.elapsed > 0.0)
	check("map_identity_town_01", main.session.placement.instances.size() > 0 and Session.town_size() == Vector2i(112, 112))
	# ---------------- 4: internal greening vs display
	main.auto_process = false
	var ref: RefCounted = Session.new(112, 112)
	ref.paving = Session.paving_from(ref.env_tuning)
	ref.load_combat(Session.TOWN_SETUP)
	# fresh PocMain-session pair: reference without any view, and the main's session with ground density 0 and the full view pipeline
	main.new_game() # untouched => reuses; session already advanced 0.25 s, so a fresh one is built
	var gs: Node3D = main.play_view.ground
	check("ground_cover_present", gs != null)
	gs.set_density(0.0, 0.0)
	var shown0: int = gs.visible_count("soil")
	check("density0_hides_cover", shown0 == 0, "visible soil cells %d" % shown0)
	var live: RefCounted = main.session
	var sig_start: String = world_sig(live)
	check("start_state_same_as_reference", sig_start == world_sig(ref), "")
	# make zone 1 stable on both (engine-level setup) so that real greening happens while the view runs
	for sess: RefCounted in [live, ref]:
		for n: Nest in sess.enemies.nests.duplicate():
			sess.enemies.destroy_nest(n)
		for b: Boar in sess.enemies.boars.duplicate():
			sess.enemies.remove_boar(b)
	# play: both advance equally; the main one also runs every view each frame (display) with the player stepping behind a wall
	var total: float = 0.0
	while total < 600.0:
		main.tick(0.25, Vector2.ZERO)
		ref.advance_game(0.25)
		total += 0.25
	check("greening_progressed_in_run", live.state.greened_count > 484 + 50, "greened %d" % live.state.greened_count)
	check("greened_target_equal_with_hidden_ground", live.state.greened_count == ref.state.greened_count and live.state.target_count == ref.state.target_count and world_sig(live) == world_sig(ref), "greened %d vs %d (targets %d) after %.0f s; zones %s vs %s" % [live.state.greened_count, ref.state.greened_count, live.state.target_count, total, str(Array(live.state.zone_state)), str(Array(ref.state.zone_state))])
	var g_before: int = live.state.greened_count
	var t_before: int = live.state.target_count
	var visible_a: int = gs.visible_count("soil")
	gs.set_density(1.0, 1.0)
	var visible_b: int = gs.visible_count("soil")
	check("density_changes_only_display", live.state.greened_count == g_before and live.state.target_count == t_before and visible_b >= visible_a, "visible soil %d -> %d; greened %d" % [visible_a, visible_b, live.state.greened_count])
	gs.set_density(0.3, 0.3)
	check("density_0.3_no_count_change", live.state.greened_count == g_before and live.state.target_count == t_before and world_sig(live) == world_sig(ref))
	# day / night display: move the clock through a day on both and compare after (the sun factor is part of the game rule, so both see the same)
	for k: int in 4:
		for j: int in 80:
			main.tick(0.25, Vector2.ZERO)
			ref.advance_game(0.25)
		main.env_view.sync()
	check("day_night_display_cycle_no_divergence", world_sig(live) == world_sig(ref), "hour now %s" % main.env_view.hour_text())
	# percentage: 99.x must not read 100
	var st: WorldState = live.state
	var all_target: Array[int] = []
	for i: int in st.tile_count():
		if st.target[i] == 1:
			all_target.append(i)
	for i: int in all_target:
		st.set_stage(i, WorldState.STAGE_MATURE)
	var last: int = all_target[all_target.size() - 1]
	st.set_stage(last, WorldState.STAGE_EMPTY)
	main._refresh()
	var badge_99: String = main.ui.badge.text
	var hud_99: String = main.hud.text
	info("badge 99: " + badge_99.replace("\n", " / ") + " ratio=" + str(live.greening_ratio()))
	check("99_point_x_shows_99", live.greening_percent() == 99 and badge_99.contains("99％") and not badge_99.contains("100％") and not badge_99.contains("★") and not hud_99.contains("100%"), "ratio %.6f" % live.greening_ratio())
	st.set_stage(last, WorldState.STAGE_MATURE)
	main._refresh()
	var badge_100: String = main.ui.badge.text
	check("exact_all_shows_100_and_done", live.greening_percent() == 100 and badge_100.contains("100％") and badge_100.contains("★"), badge_100.replace("\n", " / "))
	_finish()

func _finish() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var f: FileAccess = FileAccess.open(OUT + "boot.log", FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(lines) + "\nRESULT passes=%d failures=%d\n" % [passes, fails])
		f.close()
	print("RESULT passes=%d failures=%d" % [passes, fails])
	quit(1 if fails > 0 else 0)
