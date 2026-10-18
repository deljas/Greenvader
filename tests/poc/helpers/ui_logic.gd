extends SceneTree
## HLP-01 input / HUD wiring checks (headless OK): godot --headless --path <repo> --script res://tests/poc/helpers/ui_logic.gd
## Q (mode), left click (place), right click (leave mode), E (lift) through PocMain's own handlers; HUD text; old save v1 notice;
## the new action does not collide with existing ones. Injected engine events only (no OS input).
const Config: GDScript = preload("res://scripts/poc/poc_config.gd")
const Coords: GDScript = preload("res://scripts/poc/poc_coords.gd")
var failures: int = 0
var passes: int = 0
var main: Node

func check(name: String, ok: bool, detail: String = "") -> void:
	print("PASS " if ok else "FAIL ", name, " ", detail)
	if ok:
		passes += 1
	else:
		failures += 1

func _init() -> void:
	_run.call_deferred()

func key(code: Key) -> InputEventKey:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	return event

func click(button: MouseButton, at: Vector2) -> InputEventMouseButton:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = button
	event.pressed = true
	event.position = at
	return event

func _run() -> void:
	main = load("res://scenes/poc.tscn").instantiate()
	main.set_meta(&"poc_town", true)
	root.add_child(main)
	main.auto_process = false
	main.window_size_override = Vector2i(1920, 1080)
	await process_frame
	await process_frame
	var s: RefCounted = main.session
	var h: RefCounted = s.helpers
	# the action is new and nothing else uses Q
	var owners: int = 0
	for action: StringName in InputMap.get_actions():
		for event: InputEvent in InputMap.action_get_events(action):
			if event is InputEventKey and (event as InputEventKey).physical_keycode == KEY_Q:
				owners += 1
	check("input.q_only_helper_mode", InputMap.has_action(&"poc_helper_mode") and owners == 1, "owners=%d" % owners)
	check("hud.shows_helper_line", main.hud.text.contains("おたすけたね 0/20") and main.hud.text.contains("Q=設置モード"), main.hud.text.get_slice("\n", 3))
	# find a free block near the start and aim at it through the camera
	var origin: Vector2i = Vector2i(-1, -1)
	for oy: int in range(Coords.logic_to_cell(s.position).y - 8, Coords.logic_to_cell(s.position).y + 8):
		for ox: int in range(Coords.logic_to_cell(s.position).x - 8, Coords.logic_to_cell(s.position).x + 8):
			var ok: bool = origin.x < 0
			for y: int in range(oy, oy + 4):
				for x: int in range(ox, ox + 4):
					var i: int = s.state.index_of(x, y)
					ok = ok and s.state.is_walkable(x, y) and s.state.target[i] == 1 and s.state.occupant[i] == 0 and s.state.stage[i] == WorldState.STAGE_MATURE
			if ok:
				origin = Vector2i(ox, oy)
	check("ui.found_block", origin.x >= 0)
	var centre_logic: Vector2 = h.block_center_px(origin)
	s.position = centre_logic + Vector2(8, 0)
	main.tick(0.0, Vector2.ZERO)
	var content: Vector2 = main.camera.unproject_position(Coords.ground3(Coords.logic_to_ground(centre_logic)))
	h.seeds = 6
	main._unhandled_input(key(KEY_Q))
	check("ui.q_enters_mode_and_hud", s.helper_mode == 0 and main.hud.text.contains("設置モード：ガトリンガー"), main.hud.text.get_slice("\n", 3))
	var shots_before: int = s.projectiles.launched
	main._unhandled_input(click(MOUSE_BUTTON_LEFT, content))
	check("ui.left_click_places_not_fires", h.plants.size() == 1 and s.projectiles.launched == shots_before and h.seeds == 4, str(h.plants.size()))
	main.tick(0.0, Vector2.ZERO)
	check("hud.counts_after_place", main.hud.text.contains("おたすけ植物 1/6") and main.hud.text.contains("おたすけたね 4/20"))
	main._unhandled_input(click(MOUSE_BUTTON_RIGHT, content))
	check("ui.right_click_leaves_mode_no_water", s.helper_mode == -1 and s.projectiles.launched == shots_before)
	main._unhandled_input(key(KEY_E))
	main.tick(0.0, Vector2.ZERO)
	check("ui.e_lifts_nearby", h.is_carrying() and h.plants.is_empty() and main.hud.text.contains("持ち上げ中"), main.hud.text.get_slice("\n", 3))
	main._unhandled_input(key(KEY_E))
	check("ui.e_while_carrying_hint_no_double", h.is_carrying() and h.total_count() == 1)
	main._unhandled_input(key(KEY_Q))
	var seeds_now: int = h.seeds
	main._unhandled_input(click(MOUSE_BUTTON_LEFT, content))
	check("ui.replace_free_by_click", h.plants.size() == 1 and not h.is_carrying() and h.seeds == seeds_now)
	main.queue_free()
	await process_frame
	print("RESULT passes=%d failures=%d" % [passes, failures])
	quit(1 if failures > 0 else 0)
