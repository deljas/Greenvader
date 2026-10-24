extends RefCounted
## Two mouse buttons only. A press chooses its action once; releases permit the next press.
const SEED: StringName = &"seed"
const WATER: StringName = &"water"
const SPENT: StringName = &"spent"
const BLOCKED: StringName = &"blocked"
var _down: Dictionary = {}
var _mode: Dictionary = {}
var _shift_down: bool = false

func _supported(button: int) -> bool:
	return button == MOUSE_BUTTON_LEFT or button == MOUSE_BUTTON_RIGHT

func set_shift(pressed: bool) -> void:
	if pressed and not _shift_down:
		# Shift during a normal hold stops it. It never starts a skill by itself.
		for button: Variant in _mode:
			if _mode[button] in [SEED,WATER]:
				_mode[button] = BLOCKED
	_shift_down = pressed

func press(button: int, shifted: bool, placement_selected: bool = false) -> StringName:
	if not _supported(button) or bool(_down.get(button,false)):
		return &""
	set_shift(shifted)
	_down[button] = true
	if shifted:
		_mode[button] = SPENT
		return &"skill1" if button == MOUSE_BUTTON_LEFT else &"skill2"
	if placement_selected:
		_mode[button] = SPENT
		return &"place" if button == MOUSE_BUTTON_LEFT else &"cancel_placement"
	var action: StringName = SEED if button == MOUSE_BUTTON_LEFT else WATER
	_mode[button] = action
	return action

func held_action(button: int) -> StringName:
	var action: StringName = _mode.get(button,&"")
	return action if bool(_down.get(button,false)) and action in [SEED,WATER] else &""

func release(button: int) -> void:
	_down.erase(button)
	_mode.erase(button)

func block_press(button: int) -> void:
	# Used for UI-consumed presses; closing that UI cannot turn them into world input.
	if _supported(button):
		_down[button] = true
		_mode[button] = BLOCKED

func cancel_holds() -> void:
	# Mode/placement changes suppress held buttons until their actual release.
	for button: Variant in _down:
		_mode[button] = BLOCKED

func reset() -> void:
	# For a new session or lost focus, where an OS release may never be delivered.
	_down.clear()
	_mode.clear()
	_shift_down = false
