extends SceneTree
## HLP-01 independent verification (PocMain, headless): condition 6 with Input.parse_input_event only (no OS-level input).
##   godot --headless --path <repo> --script res://tests/poc/independent/hlp01_input.gd
const Coords: GDScript = preload("res://scripts/poc/poc_coords.gd")
const Config: GDScript = preload("res://scripts/poc/poc_config.gd")
const DIR: String = "user://poc_saves_indep_hlp01_ui/"
const OUT: String = "res://evidence/helper/01/independent/"
var passes: int = 0
var fails: int = 0
var lines: PackedStringArray = PackedStringArray()
var main: Node

func check(name: String, ok: bool, detail: String = "") -> void:
	if ok:
		passes += 1
	else:
		fails += 1
	var line: String = "%s %s %s" % ["PASS" if ok else "FAIL", name, detail]
	lines.append(line)
	print(line)

func _init() -> void:
	_run.call_deferred()

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

func block_free(st: WorldState, ox: int, oy: int) -> bool:
	for y: int in range(oy, oy + 4):
		for x: int in range(ox, ox + 4):
			var i: int = st.index_of(x, y)
			if not st.is_walkable(x, y) or st.target[i] == 0 or st.occupant[i] != 0 or st.stage[i] != WorldState.STAGE_MATURE:
				return false
	return true

func screen_of(logic: Vector2) -> Vector2:
	var g: Vector2 = Coords.logic_to_ground(logic)
	return main.camera.unproject_position(Vector3(g.x, 0.0, g.y))

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var scene: PackedScene = load("res://scenes/poc.tscn")
	main = scene.instantiate()
	main.set_meta(&"poc_town", true)
	main.save_dir = DIR
	main.auto_process = false
	root.add_child(main)
	await frames(3)
	var s: RefCounted = main.session
	var h: RefCounted = s.helpers
	var st: WorldState = s.state
	# key map: Q and E belong to exactly the intended actions
	var q_actions: Array[String] = []
	var e_actions: Array[String] = []
	var dup: Dictionary = {}
	for a: StringName in InputMap.get_actions():
		for ev: InputEvent in InputMap.action_get_events(a):
			if ev is InputEventKey:
				var code: int = (ev as InputEventKey).physical_keycode if (ev as InputEventKey).physical_keycode != 0 else (ev as InputEventKey).keycode
				if code == KEY_Q:
					q_actions.append(String(a))
				if code == KEY_E:
					e_actions.append(String(a))
				if String(a).begins_with("poc_"):
					dup[code] = int(dup.get(code, 0)) + 1
	var poc_dup: bool = false
	for c: Variant in dup:
		poc_dup = poc_dup or int(dup[c]) > 1
	check("keys.q_only_helper_mode", q_actions == ["poc_helper_mode"], str(q_actions))
	var e_game: Array[String] = e_actions.filter(func(n: String) -> bool: return not n.begins_with("ui_"))
	check("keys.e_only_interact", e_game == ["poc_interact"], "all=%s (ui_text_caret_line_end.macos is a Godot built-in text-edit action, not a game action)" % str(e_actions))
	check("keys.no_duplicate_poc_keys", not poc_dup)
	# a block to work with
	var spot: Vector2i = Vector2i(-1, -1)
	var best: float = INF
	for oy: int in range(1, st.height - 5):
		for ox: int in range(1, st.width - 5):
			if block_free(st, ox, oy) and (Vector2(ox + 2, oy + 2) - Vector2(88, 86)).length() < best:
				best = (Vector2(ox + 2, oy + 2) - Vector2(88, 86)).length()
				spot = Vector2i(ox, oy)
	var logic: Vector2 = (Vector2(spot) + Vector2(2, 2)) * 4.0
	s.position = logic + Vector2(8, 0)
	main.tick(0.0, Vector2.ZERO)
	await frames(2)
	var scr: Vector2 = screen_of(logic)
	var pick: Dictionary = main.pick_ground(scr)
	check("ui.screen_round_trip", bool(pick["ok"]) and (pick["logic"] as Vector2).distance_to(logic) < 1.0, "scr %s -> %s vs %s" % [str(scr), str(pick.get("logic")), str(logic)])
	h.add_seeds(15)
	var water0: float = s.play.water
	var launched0: int = s.projectiles.launched
	var seeds_plain0: int = s.play.seeds
	# Q cycles
	var modes: Array[int] = []
	for i: int in 4:
		key(KEY_Q)
		await frames(2)
		modes.append(s.helper_mode)
	check("input.q_cycles_modes_off", modes == [0, 1, 2, -1], str(modes))
	# mode 1 (sprinkler), left click places and does not shoot
	key(KEY_Q)
	await frames(2)
	var seeds0: int = h.seeds
	click(scr)
	await frames(2)
	check("input.left_click_places", h.plants.size() == 1 and seeds0 - h.seeds == 2 and String(h.plants[0]["kind"]) == "gatlinger", "plants=%d seeds %d->%d kind=%s" % [h.plants.size(), seeds0, h.seeds, str(h.plants[0]["kind"]) if h.plants.size() > 0 else ""])
	check("input.left_click_no_shot_no_plain_seed_spent", s.projectiles.launched == launched0 and s.play.seeds == seeds_plain0 and s.play.water == water0)
	# UI click does not place: click on the pause button center in mode
	var another: Vector2i = Vector2i(-1, -1)
	for oy: int in range(1, st.height - 5):
		for ox: int in range(1, st.width - 5):
			if another.x < 0 and block_free(st, ox, oy) and absi(ox - spot.x) > 6 and (Vector2(ox + 2, oy + 2) - Vector2(spot) - Vector2(2, 2)).length() < 10:
				another = Vector2i(ox, oy)
	var ui_pos: Vector2 = Vector2(-1, -1)
	for c: Control in main.ui_controls:
		var r: Rect2 = c.get_global_rect()
		lines.append("INFO ui control %s visible=%s rect=%s" % [c.name, str(c.is_visible_in_tree()), str(r)])
		if ui_pos.x < 0.0 and c.is_visible_in_tree() and Rect2(Vector2.ZERO, Vector2(main.render_view.size)).has_point(r.get_center()):
			ui_pos = r.get_center()
	check("ui.control_inside_view_found", ui_pos.x >= 0.0, str(ui_pos))
	var before: int = h.plants.size()
	var seeds_b: int = h.seeds
	# aim for the UI click: place the player so that, were the ground picked, the block would be valid is not possible; the check is that nothing happens
	var pr: Dictionary = main.click_place(ui_pos)
	click(ui_pos)
	await frames(2)
	check("input.click_on_ui_does_not_place", h.plants.size() == before and h.seeds == seeds_b and not bool(pr["ok"]) and String(pr["code"]) == "ui", "code=%s" % str(pr["code"]))
	# right click leaves the mode, no water
	click(scr, MOUSE_BUTTON_RIGHT)
	await frames(2)
	check("input.right_click_ends_mode_no_water", s.helper_mode == -1 and s.play.water == water0 and s.projectiles.launched == launched0, "mode=%d water %.1f/%.1f launched %d/%d" % [s.helper_mode, s.play.water, water0, s.projectiles.launched, launched0])
	# control: right click outside the mode still waters
	click(scr + Vector2(0, 40), MOUSE_BUTTON_RIGHT)
	await frames(2)
	check("input.right_click_outside_mode_still_waters", s.projectiles.launched == launched0 + 1 or s.play.water < water0, "launched %d water %.1f" % [s.projectiles.launched, s.play.water])
	# control: left click outside the mode shoots a seed (existing behaviour intact) and places nothing
	var l1: int = s.projectiles.launched
	var hp1: int = h.plants.size()
	click(scr + Vector2(0, 40))
	await frames(2)
	check("input.left_click_outside_mode_fires_not_places", s.projectiles.launched > l1 and h.plants.size() == hp1)
	# E lifts the nearby plant
	s.position = logic + Vector2(14, 0)
	main.tick(0.0, Vector2.ZERO)
	key(KEY_E)
	await frames(2)
	check("input.e_lifts_nearby", h.is_carrying() and h.plants.is_empty() and h.total_count() == 1)
	key(KEY_E)
	await frames(2)
	check("input.e_again_while_carrying_does_not_duplicate", h.total_count() == 1 and h.is_carrying())
	# Q then left click re-places for free at the same aim
	var seeds_c: int = h.seeds
	key(KEY_Q)
	await frames(2)
	check("input.q_while_carrying_enters_carried_kind", s.helper_mode >= 0 and s.helper_active_kind() == "gatlinger")
	click(scr)
	await frames(2)
	check("input.click_replaces_free", h.plants.size() == 1 and not h.is_carrying() and h.seeds == seeds_c, "seeds %d->%d" % [seeds_c, h.seeds])
	# E with nothing near: no lift, no crash
	key(KEY_Q)
	await frames(2)
	s.position = logic + Vector2(120, 0) if s.is_walkable_logic(logic + Vector2(120, 0)) else logic - Vector2(120, 0)
	key(KEY_E)
	await frames(2)
	check("input.e_far_no_lift", h.plants.size() == 1 and not h.is_carrying())
	# HUD shows the helper status
	main.tick(0.0, Vector2.ZERO)
	check("hud.shows_helper_seeds", main.hud.text.contains("おたすけたね") and main.hud.text.contains("Q"), main.hud.text.right(120))
	var f: FileAccess = FileAccess.open(OUT + "input.log", FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\nRESULT passes=%d failures=%d\n" % [passes, fails])
	f.close()
	print("RESULT passes=%d failures=%d" % [passes, fails])
	for fl: String in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR + fl)
	main.session.close()
	quit(1 if fails > 0 else 0)
