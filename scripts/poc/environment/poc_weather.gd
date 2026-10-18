extends RefCounted
## WTH-01 weather state machine (clear / cloudy / rain). The weather is a function of the one game clock (SimClock.elapsed)
## and data/poc/weather.json only: a fixed-seed RNG draws, segment after segment, the next weather and its length, so the
## schedule is identical however the game time is split into steps, and it does not move while the game is paused (the clock
## does not move). Segments are generated lazily and only forward; the state to save is (seed, current segment, RNG position).
## Display levels (overcast, rain) blend from the previous weather over `blend_seconds` after a segment starts.
const TUNING_PATH: String = "res://data/poc/weather.json"
const CLEAR: int = 0
const CLOUDY: int = 1
const RAIN: int = 2
const KEYS: Array[String] = ["clear", "cloudy", "rain"]
const LABELS: Array[String] = ["晴れ", "曇り", "雨"]
const SAVE_VERSION: int = 1
## Upper bound accepted when loading (a segment is at most this long / the index at most this).
const MAX_INDEX: int = 1000000

var tuning: Dictionary = {}
var seed_value: int = 0
## Generated segments: {type, start, duration, rng_after (RNG state string after drawing this segment)}.
var segments: Array[Dictionary] = []
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _cursor: int = 0
## Index of the segment at the latest update(); what to_dict() saves.
var current_index: int = 0
## Development override (-1 = off). Never saved; set by `--debug-weather` keys only.
var override_type: int = -1

static func load_tuning(path: String = TUNING_PATH) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}

func _init(tuning_: Dictionary = {}) -> void:
	tuning = tuning_ if not tuning_.is_empty() else load_tuning()
	seed_value = int(tuning.get("seed", 1))
	_rng.seed = seed_value
	var first: int = KEYS.find(String(tuning.get("initial", "clear")))
	_append(maxi(first, 0), 0.0)

func _duration(type: int) -> float:
	var range_: Array = (tuning.get("durations", {}) as Dictionary).get(KEYS[type], [120.0, 120.0])
	var low: float = maxf(float(range_[0]), 1.0)
	var high: float = maxf(float(range_[1]), low)
	return low + _rng.randf() * (high - low)

func _append(type: int, start: float) -> void:
	var duration: float = _duration(type)
	segments.append({"type": type, "start": start, "duration": duration, "rng_after": str(_rng.state)})

func _next_type(from: int) -> int:
	var row: Dictionary = (tuning.get("transitions", {}) as Dictionary).get(KEYS[from], {})
	var roll: float = _rng.randf()
	var total: float = 0.0
	for key: Variant in row:
		total += maxf(float(row[key]), 0.0)
	var acc: float = 0.0
	var pick: int = from
	for key: Variant in row:
		var weight: float = maxf(float(row[key]), 0.0)
		if weight <= 0.0:
			continue
		pick = KEYS.find(String(key))
		acc += weight / maxf(total, 0.000001)
		if roll < acc:
			break
	return pick

func _extend_until(t: float) -> void:
	while true:
		var last: Dictionary = segments[segments.size() - 1]
		var end: float = float(last["start"]) + float(last["duration"])
		if end > t:
			return
		_append(_next_type(int(last["type"])), end)

## Index of the segment that contains game time `t` (>= 0).
func index_at(t: float) -> int:
	var time: float = maxf(t, 0.0)
	_extend_until(time)
	while _cursor > 0 and float(segments[_cursor]["start"]) > time:
		_cursor -= 1
	while _cursor < segments.size() - 1 and float(segments[_cursor]["start"]) + float(segments[_cursor]["duration"]) <= time:
		_cursor += 1
	return _cursor

## Advances the observed position to game time `t` (monotonic use; going back is allowed and exact). Returns the type.
func update(t: float) -> int:
	current_index = index_at(t)
	return type_at(t)

func type_at(t: float) -> int:
	if override_type >= 0:
		return override_type
	return int(segments[index_at(t)]["type"])

func prev_type_at(t: float) -> int:
	var index: int = index_at(t)
	return int(segments[index - 1]["type"]) if index > 0 else int(segments[0]["type"])

## Seconds left in the segment that contains `t`.
func remaining_at(t: float) -> float:
	var segment: Dictionary = segments[index_at(t)]
	return float(segment["start"]) + float(segment["duration"]) - maxf(t, 0.0)

func _blend_at(t: float) -> float:
	var index: int = index_at(t)
	if index == 0:
		return 1.0
	var segment: Dictionary = segments[index]
	var blend_seconds: float = maxf(float(tuning.get("blend_seconds", 20.0)), 0.001)
	return smoothstep(0.0, 1.0, clampf((maxf(t, 0.0) - float(segment["start"])) / blend_seconds, 0.0, 1.0))

func _level(table_name: String, type: int) -> float:
	return float((tuning.get(table_name, {}) as Dictionary).get(KEYS[type], 0.0))

## Display / growth levels at game time `t`: overcast 0..1 (0 = clear sky), rain 0..1, the weather type and the blend.
func levels_at(t: float) -> Dictionary:
	if override_type >= 0:
		return {"type": override_type, "prev": override_type, "blend": 1.0, "overcast": _level("overcast", override_type), "rain": _level("rain_level", override_type), "index": index_at(t)}
	var index: int = index_at(t)
	var type: int = int(segments[index]["type"])
	var prev: int = int(segments[index - 1]["type"]) if index > 0 else type
	var blend: float = _blend_at(t)
	return {
		"type": type, "prev": prev, "blend": blend, "index": index,
		"overcast": lerpf(_level("overcast", prev), _level("overcast", type), blend),
		"rain": lerpf(_level("rain_level", prev), _level("rain_level", type), blend),
	}

## Fraction of the sunlight bonus that is left under this weather (1 = clear sky, 0 = overcast).
func clear_amount_at(t: float) -> float:
	return clampf(1.0 - float(levels_at(t)["overcast"]), 0.0, 1.0)

func is_raining_at(t: float) -> bool:
	return float(levels_at(t)["rain"]) >= float((tuning.get("rain", {}) as Dictionary).get("min_level", 0.5))

func label_at(t: float) -> String:
	return LABELS[type_at(t)]

# ---------------------------------------------------------------- save

func to_dict() -> Dictionary:
	var segment: Dictionary = segments[current_index]
	return {
		"version": SAVE_VERSION,
		"seed": str(seed_value),
		"index": current_index,
		"type": int(segment["type"]),
		"prev_type": int(segments[current_index - 1]["type"]) if current_index > 0 else int(segment["type"]),
		"start": float(segment["start"]),
		"duration": float(segment["duration"]),
		"rng_state": String(segment["rng_after"]),
	}

## Restores/validates a saved state for the clock position `elapsed`. The schedule is replayed from the seed; the file is
## accepted only when its numbers are in range and equal the replayed ones (so a tampered or stale state is rejected).
## Returns "" on success, otherwise a short reason.
func load_dict(data: Dictionary, elapsed: float) -> String:
	for key: String in ["version", "seed", "index", "type", "prev_type", "start", "duration", "rng_state"]:
		if not data.has(key):
			return "missing " + key
	if int(data["version"]) != SAVE_VERSION:
		return "version"
	for key: String in ["index", "type", "prev_type"]:
		if not (data[key] is int or data[key] is float):
			return key + " type"
	for key: String in ["start", "duration"]:
		if not (data[key] is int or data[key] is float) or is_nan(float(data[key])) or is_inf(float(data[key])):
			return key + " type"
	if not (data["seed"] is String and String(data["seed"]).is_valid_int()):
		return "seed"
	if not (data["rng_state"] is String and String(data["rng_state"]).is_valid_int()):
		return "rng_state"
	var index: int = int(data["index"])
	if index < 0 or index > MAX_INDEX:
		return "index range"
	for key: String in ["type", "prev_type"]:
		if int(data[key]) < 0 or int(data[key]) >= KEYS.size():
			return key + " range"
	if float(data["start"]) < 0.0 or float(data["duration"]) <= 0.0 or float(data["duration"]) > 1.0e6:
		return "time range"
	if elapsed < float(data["start"]) - 0.001 or elapsed > float(data["start"]) + float(data["duration"]) + 0.001:
		return "elapsed outside the saved segment"
	if int(String(data["seed"])) != seed_value:
		return "seed differs"
	var replay_index: int = index_at(elapsed)
	var replay: Dictionary = segments[replay_index]
	if replay_index != index or int(replay["type"]) != int(data["type"]):
		return "schedule differs"
	var prev: int = int(segments[replay_index - 1]["type"]) if replay_index > 0 else int(replay["type"])
	if prev != int(data["prev_type"]) or absf(float(replay["start"]) - float(data["start"])) > 0.001 or absf(float(replay["duration"]) - float(data["duration"])) > 0.001 or String(replay["rng_after"]) != String(data["rng_state"]):
		return "schedule differs"
	current_index = replay_index
	return ""
