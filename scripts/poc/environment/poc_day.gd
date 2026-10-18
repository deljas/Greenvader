extends RefCounted
## POC-05 day cycle (ported from the town lab's day_cycle.gd). Pure functions: the time of day is a function of the one game
## clock (SimClock.elapsed) and data/poc/environment.json; nothing here holds an hour of its own.
## Compass is aligned to the screen: north = screen up = ground (-1,0,-1); the sun rises in the east, passes south at noon
## (maximum elevation) and sets in the west.
const TUNING_PATH: String = "res://data/poc/environment.json"
const NORTH: Vector3 = Vector3(-0.70710678, 0, -0.70710678)
const EAST: Vector3 = Vector3(0.70710678, 0, -0.70710678)
const SOUTH: Vector3 = Vector3(0.70710678, 0, 0.70710678)
const WEST: Vector3 = Vector3(-0.70710678, 0, 0.70710678)

static func load_tuning(path: String = TUNING_PATH) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}

## Hour of day in [0, 24) at game time `elapsed` seconds.
static func hour_at(elapsed: float, tuning: Dictionary) -> float:
	var day_seconds: float = maxf(float(tuning.get("day_seconds", 600.0)), 1.0)
	return fposmod(float(tuning.get("start_hour", 8.0)) + elapsed / day_seconds * 24.0, 24.0)

## Sine of the sun altitude (-1..1): 0 at 06:00 and 18:00, 1 at noon.
static func altitude_at(hour: float) -> float:
	return sin((fposmod(hour, 24.0) - 6.0) / 12.0 * PI)

static func state(hour: float, tuning: Dictionary = {}) -> Dictionary:
	var h: float = fposmod(hour, 24.0)
	var phase: float = (h - 6.0) / 12.0 * PI
	var altitude: float = sin(phase)
	var light: Dictionary = tuning.get("light", {})
	var elevation: float = deg_to_rad(float(light.get("max_elevation_deg", 55.0))) * altitude
	var horizontal: Vector3 = EAST * cos(phase) + SOUTH * sin(phase)
	var source: Vector3 = horizontal * cos(elevation) + Vector3.UP * sin(elevation)
	var daylight: float = smoothstep(-0.18, 0.25, altitude)
	var sun_power: float = smoothstep(0.0, 0.25, altitude)
	var night: float = 1.0 - smoothstep(-0.1, 0.3, altitude)
	var moon_fade: float = maxf(float(light.get("moon_fade", 0.15)), 0.001)
	return {
		"hour": h,
		"altitude": altitude,
		"source": source,
		"sun_elevation": rad_to_deg(elevation),
		"sun_power": sun_power,
		"daylight": daylight,
		"night": night,
		"sun_color": Color("f0a169").lerp(Color("fff8e7"), smoothstep(0.02, 0.6, altitude)),
		"moon_source": Vector3(-source.x, -source.y, -source.z),
		"moon_power": night * smoothstep(0.0, moon_fade, -altitude),
	}

## Sunlight growth factor: exactly night (1.0) when the sun is down, rising to day_max at noon. Never below 1.0.
static func sunlight_factor(day_state: Dictionary, tuning: Dictionary) -> float:
	var sun: Dictionary = tuning.get("sunlight", {})
	var night_factor: float = maxf(float(sun.get("night", 1.0)), 1.0)
	var day_max: float = maxf(float(sun.get("day_max", 1.25)), night_factor)
	return lerpf(night_factor, day_max, float(day_state["sun_power"]))

static func sunlight_factor_at(elapsed: float, tuning: Dictionary) -> float:
	return sunlight_factor(state(hour_at(elapsed, tuning), tuning), tuning)

static func clock_text(hour: float) -> String:
	var minutes: int = int(floor(fposmod(hour, 24.0) * 60.0))
	return "%02d:%02d" % [minutes / 60, minutes % 60]

static func phase_label(day_state: Dictionary) -> String:
	if float(day_state["sun_power"]) > 0.5:
		return "昼"
	if float(day_state["altitude"]) > 0.0:
		return "朝夕"
	return "夜"
