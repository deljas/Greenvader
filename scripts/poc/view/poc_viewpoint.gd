extends RefCounted
## WTH-02 viewpoint logic (no Node, display/pause only). One spot per map (town_01.json "viewpoint": {cell, name}); tuning in
## data/poc/viewpoint.json. Entering stops the world exactly like a pause (the one SimClock does not move, so nothing is banked
## and nothing is added on return); leaving restores the pause flag it found. It never touches the simulation otherwise.
const Config: GDScript = preload("res://scripts/poc/poc_config.gd")
const Coords: GDScript = preload("res://scripts/poc/poc_coords.gd")
const Day: GDScript = preload("res://scripts/poc/environment/poc_day.gd")
const TUNING_PATH: String = "res://data/poc/viewpoint.json"

var tuning: Dictionary = {}
var has_spot: bool = false
var cell: Vector2i = Vector2i.ZERO
var spot_name: String = ""
var active: bool = false
var _prev_paused: bool = false
## Number of times the view was entered / left (observability).
var entered: int = 0
var left: int = 0

static func load_tuning(path: String = TUNING_PATH) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}

func _init(session: RefCounted = null, tuning_: Dictionary = {}) -> void:
	tuning = tuning_ if not tuning_.is_empty() else load_tuning()
	if session != null:
		var spot: Variant = (session.combat_setup as Dictionary).get("viewpoint", null)
		if spot is Dictionary and (spot as Dictionary).has("cell"):
			var c: Array = (spot as Dictionary)["cell"]
			cell = Vector2i(int(c[0]), int(c[1]))
			spot_name = String((spot as Dictionary).get("name", "展望地点"))
			has_spot = true

func spot_ground() -> Vector2:
	return Coords.cell_center_ground(cell)

func distance_m(logic_position: Vector2) -> float:
	return Coords.cell_center_logic(cell).distance_to(logic_position) * Config.M_PER_LOGIC_PX

func is_near(logic_position: Vector2) -> bool:
	return has_spot and distance_m(logic_position) <= float(tuning.get("interact_radius_m", 1.8))

func is_hint_range(logic_position: Vector2) -> bool:
	return has_spot and distance_m(logic_position) <= float(tuning.get("hint_radius_m", 3.0))

func camera_size() -> float:
	return float(tuning.get("camera_size_m", 38.0))

## Ground point (with the view height) the wide camera looks at.
func focus_point() -> Vector3:
	var fc: Array = tuning.get("focus_cell", [56, 56])
	var ground: Vector2 = Coords.cell_center_ground(Vector2i(int(fc[0]), int(fc[1])))
	return Vector3(ground.x, float(tuning.get("focus_height_m", 0.6)), ground.y)

## Enters the view when the player is at the spot. Returns false (and changes nothing) otherwise.
func enter(session: RefCounted) -> bool:
	if active or not is_near(session.position):
		return false
	_prev_paused = session.paused
	session.paused = true
	active = true
	entered += 1
	return true

func leave(session: RefCounted) -> bool:
	if not active:
		return false
	session.paused = _prev_paused
	active = false
	left += 1
	return true

## Values the panorama panel shows, all read from the session (nothing of its own).
func panel_values(session: RefCounted) -> Dictionary:
	var day: Dictionary = session.day_state()
	return {
		"percent": session.greening_percent(),
		"greened": session.state.greened_count,
		"targets": session.state.target_count,
		"clock": Day.clock_text(session.day_hour()),
		"phase": Day.phase_label(day),
		"weather": session.weather_text(),
	}

func panel_text(session: RefCounted) -> String:
	var v: Dictionary = panel_values(session)
	return "%s｜展望\n内部緑化率 %d％（%d/%d）\n時刻 %s（%s）　天気 %s\nEsc / E で戻る" % [spot_name, v["percent"], v["greened"], v["targets"], v["clock"], v["phase"], v["weather"]]
