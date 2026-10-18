extends RefCounted
## POC-06 occlusion judgement (no Node dependency except the optional builders). The camera is orthographic, so every
## view ray has the same direction: from a sample point on the player (feet / torso / head, plus two lateral torso points)
## a segment runs towards the camera. An object is "occluding" when that segment meets its triangles (coarse: world AABB
## per MeshInstance, fine: TriangleMesh.intersect_segment in the mesh's local space, so open doorways, eaves and gaps
## between walls are not hit). Results are per occlusion group; hysteresis (release hold) + a fade value per group
## are kept here so the state never flips frame by frame.
##
## entries: Array of {group: String, ids: Array[String], parts: Array of {node, xf: Transform3D, aabb: AABB, tri: TriangleMesh}}
const DEFAULTS: Dictionary = {
	"enabled": true, "target_alpha": 0.4, "fade_out_seconds": 0.15, "fade_in_seconds": 0.25, "release_hold_seconds": 0.35,
	"ray_length_m": 70.0, "ray_start_offset_m": 0.03, "foot_lift_m": 0.1, "head_fraction": 0.92, "torso_fraction": 0.5,
	"lateral_m": 0.2, "follow_vegetation": true, "depth_draw": "opaque_only", "transparency": "alpha", "single_layer": true,
}

var tuning: Dictionary = DEFAULTS.duplicate()
var entries: Array = []
## group -> {occluded: bool, hold: float, alpha: float}
var state: Dictionary = {}
var _snap_next: bool = true

static func load_tuning(path: String = "res://data/poc/occlusion.json") -> Dictionary:
	var merged: Dictionary = DEFAULTS.duplicate()
	if FileAccess.file_exists(path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary:
			merged.merge(parsed as Dictionary, true)
	return merged

## Group key of an instance: asset occlusion_group "instance" (default) = the instance itself, otherwise the named group.
static func group_key(instance_id: String, occlusion_group: String) -> String:
	return instance_id if occlusion_group == "" or occlusion_group == "instance" else occlusion_group

## One part for a MeshInstance3D (needs to be inside the tree for its global transform).
static func make_part(node: MeshInstance3D, cache: Dictionary) -> Dictionary:
	var key: int = node.mesh.get_instance_id()
	if not cache.has(key):
		cache[key] = node.mesh.generate_triangle_mesh()
	var part: Dictionary = {"node": node, "tri": cache[key], "xf": Transform3D.IDENTITY, "aabb": AABB()}
	refresh_part(part)
	return part

static func refresh_part(part: Dictionary) -> void:
	var node: MeshInstance3D = part["node"] as MeshInstance3D
	part["xf"] = node.global_transform
	part["aabb"] = node.global_transform * node.get_aabb()

func set_entries(new_entries: Array) -> void:
	entries = new_entries
	state.clear()
	for entry: Dictionary in entries:
		state[entry["group"]] = {"occluded": false, "hold": 0.0, "alpha": 1.0}
	_snap_next = true

func refresh_parts() -> void:
	for entry: Dictionary in entries:
		for part: Dictionary in entry["parts"]:
			if is_instance_valid(part["node"]):
				refresh_part(part)

## Player sample points: feet (lifted slightly), torso and head on the centre line, torso left/right (camera right).
func sample_points(foot: Vector3, height_m: float, right: Vector3) -> PackedVector3Array:
	var points: PackedVector3Array = PackedVector3Array()
	var lateral: float = float(tuning["lateral_m"])
	var torso: Vector3 = foot + Vector3.UP * height_m * float(tuning["torso_fraction"])
	points.append(foot + Vector3.UP * float(tuning["foot_lift_m"]))
	points.append(torso)
	points.append(foot + Vector3.UP * height_m * float(tuning["head_fraction"]))
	if lateral > 0.0:
		points.append(torso + right * lateral)
		points.append(torso - right * lateral)
	return points

static func part_hit(part: Dictionary, from: Vector3, to: Vector3) -> bool:
	if (part["aabb"] as AABB).intersects_segment(from, to) == null:
		return false
	var inverse: Transform3D = (part["xf"] as Transform3D).affine_inverse()
	var hit: Dictionary = (part["tri"] as TriangleMesh).intersect_segment(inverse * from, inverse * to)
	return not hit.is_empty()

## Raw (un-smoothed) result: group -> true for every group whose triangles lie on a segment player point -> camera.
func raw_occluders(points: PackedVector3Array, toward_camera: Vector3) -> Dictionary:
	var result: Dictionary = {}
	var dir: Vector3 = toward_camera.normalized()
	var offset: float = float(tuning["ray_start_offset_m"])
	var length: float = float(tuning["ray_length_m"])
	for entry: Dictionary in entries:
		var group: String = entry["group"]
		if result.has(group):
			continue
		var found: bool = false
		for part: Dictionary in entry["parts"]:
			for point: Vector3 in points:
				if part_hit(part, point + dir * offset, point + dir * length):
					found = true
					break
			if found:
				break
		if found:
			result[group] = true
	return result

## Hysteresis + fade. A group enters at once and leaves only after `release_hold_seconds` without a hit. After
## reset/set_entries the first step snaps to the raw result (no fade across a rebuild / resolution change).
func step(raw: Dictionary, delta: float) -> void:
	var target_alpha: float = clampf(float(tuning["target_alpha"]), 0.0, 1.0)
	var out_rate: float = INF if float(tuning["fade_out_seconds"]) <= 0.0 else (1.0 - target_alpha) / float(tuning["fade_out_seconds"])
	var in_rate: float = INF if float(tuning["fade_in_seconds"]) <= 0.0 else (1.0 - target_alpha) / float(tuning["fade_in_seconds"])
	for group: String in state:
		var s: Dictionary = state[group]
		if raw.has(group):
			s["occluded"] = true
			s["hold"] = float(tuning["release_hold_seconds"])
		elif s["occluded"]:
			s["hold"] = float(s["hold"]) - delta
			if float(s["hold"]) <= 0.0 or _snap_next:
				s["occluded"] = false
				s["hold"] = 0.0
		var goal: float = target_alpha if s["occluded"] else 1.0
		if _snap_next:
			s["alpha"] = goal
		else:
			var rate: float = out_rate if goal < float(s["alpha"]) else in_rate
			s["alpha"] = goal if is_inf(rate) else move_toward(float(s["alpha"]), goal, rate * delta)
	_snap_next = false

func reset_state() -> void:
	for group: String in state:
		state[group] = {"occluded": false, "hold": 0.0, "alpha": 1.0}
	_snap_next = true

func is_occluded(group: String) -> bool:
	return state.has(group) and bool(state[group]["occluded"])

func alpha_of(group: String) -> float:
	return float(state[group]["alpha"]) if state.has(group) else 1.0

## Groups currently held as occluded (after hysteresis), sorted.
func occluded_groups() -> PackedStringArray:
	var groups: PackedStringArray = PackedStringArray()
	for group: String in state:
		if bool(state[group]["occluded"]):
			groups.append(group)
	groups.sort()
	return groups
