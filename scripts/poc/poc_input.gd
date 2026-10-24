extends RefCounted
## Registers the PoC InputMap actions. Existing actions are never touched; only missing ones are added.

const KEYS: Dictionary = {
	&"poc_up": [KEY_W, KEY_UP],
	&"poc_down": [KEY_S, KEY_DOWN],
	&"poc_left": [KEY_A, KEY_LEFT],
	&"poc_right": [KEY_D, KEY_RIGHT],
	&"poc_pause": [KEY_ESCAPE],
	&"poc_cycle_speed": [KEY_F3],
	&"poc_interact": [KEY_E],
	&"poc_plant_next": [KEY_TAB],
	&"poc_debug_refill": [KEY_F9],
	&"poc_quick_save": [KEY_F5],
	&"poc_helper_mode": [KEY_Q],
	# WTH-02 sound on / off.
	&"poc_mute": [KEY_M],
	# POL-02 screen text on / off (play screen only; menus stay readable).
	&"poc_toggle_text": [KEY_T],
	# WTH-01 development keys: handled only when the game is started with --debug-weather.
	&"poc_debug_weather_clear": [KEY_1],
	&"poc_debug_weather_cloudy": [KEY_2],
	&"poc_debug_weather_rain": [KEY_3],
	&"poc_debug_weather_auto": [KEY_0],
}
const MOUSE: Dictionary = {
	&"poc_primary": MOUSE_BUTTON_LEFT,
	&"poc_secondary": MOUSE_BUTTON_RIGHT,
	&"poc_plant_wheel_next": MOUSE_BUTTON_WHEEL_DOWN,
	&"poc_plant_wheel_prev": MOUSE_BUTTON_WHEEL_UP,
}

static func register() -> void:
	for action: StringName in KEYS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action, 0.5)
		for code: int in KEYS[action]:
			var key: InputEventKey = InputEventKey.new()
			key.physical_keycode = code as Key
			InputMap.action_add_event(action, key)
	for action: StringName in MOUSE:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action, 0.5)
		var button: InputEventMouseButton = InputEventMouseButton.new()
		button.button_index = MOUSE[action] as MouseButton
		InputMap.action_add_event(action, button)

## Screen-direction input from the held keys (x right, y down, length <= 1).
static func move_vector() -> Vector2:
	return Input.get_vector(&"poc_left", &"poc_right", &"poc_up", &"poc_down")
