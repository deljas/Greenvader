extends RefCounted
## Frame timeline of the adopted SPR-01 fire actions, read from the asset manifest
## (seed 4 frames / 400ms, release 66ms; water 7 frames / 800ms, release 400ms).
## Pure lookup: callers own the clock, so a paused game freezes the animation.
const MANIFEST_PATH: String = "res://assets/sprites/poc/player/fire-directions-v1/manifest.json"
static var _ends: Dictionary = {}
static var _release: Dictionary = {}

static func _load() -> void:
	if not _ends.is_empty():
		return
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	for key: String in ["seed", "water"]:
		var action: Dictionary = manifest.actions[key]
		var ends: Array[float] = []
		var at: float = 0.0
		for ms: Variant in action.durations_ms:
			at += float(ms)
			ends.append(at)
		_ends[StringName(key)] = ends
		_release[StringName(key)] = float(action.release_events[0].time_ms)

static func total_ms(kind: StringName) -> float:
	_load()
	return (_ends[kind] as Array[float])[-1] if _ends.has(kind) else 0.0

static func release_ms(kind: StringName) -> float:
	_load()
	return float(_release.get(kind, 0.0))

## Frame shown at elapsed_ms, or -1 once the action has finished.
static func frame_at(kind: StringName, elapsed_ms: float) -> int:
	_load()
	if not _ends.has(kind):
		return -1
	var ends: Array[float] = _ends[kind]
	for index: int in ends.size():
		if elapsed_ms < ends[index] - 1.0e-7:
			return index
	return -1
