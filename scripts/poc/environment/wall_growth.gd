extends RefCounted
## POC-05 wall vegetation growth state (logic only, no rendering). One entry per placed building that has vine_surfaces in the
## material ledger. Each vine root / moss patch grows with the average greening of the target cells around its base:
##   progress += growth_tick_seconds * input / seconds   (never decreases: lost green stops growth but keeps progress)
## The input is the mean of mature (1.0) / growing (growth / mature_growth) cells of the target cells within `radius_m` of the
## anchor point just outside the wall; target cells that are still empty stay in the denominator. Sunlight is not an input.
## Driven only by SimClock.growth_ticked (so an overall pause stops it). Display lives in wall_view.gd.
const Layout: GDScript = preload("res://scripts/poc/environment/wall_layout.gd")
const Coords: GDScript = preload("res://scripts/poc/poc_coords.gd")

var state: WorldState
var sim_tuning: SimTuning
var tuning: Dictionary = {}
## One per building instance: {id, asset, pos: Vector2, yaw, offset: Vector3, surfaces, paths, durations, patches,
## roots: [{path, cells, progress, input}], moss: [{patch, cells, progress, input}]}.
var entries: Array[Dictionary] = []
var tick_count: int = 0
## Increments whenever any progress value changed (views redraw only then).
var serial: int = 0

func setup(world: WorldState, placement: RefCounted, wall_tuning: Dictionary, sim: SimTuning) -> void:
	state = world
	sim_tuning = sim
	tuning = wall_tuning
	entries.clear()
	if placement == null:
		return
	var stand_off: float = float(tuning.get("stand_off_m", 0.05))
	for inst: Dictionary in placement.instances:
		if inst["kind"] == "puddle":
			continue
		var entry_def: Dictionary = placement.catalog[inst["asset"]]
		var surfaces: Array[Dictionary] = Layout.surfaces_for(entry_def)
		if surfaces.is_empty():
			continue
		var seed_value: int = String(inst["id"]).hash() & 0x7fffffff
		var paths: Array[Dictionary] = Layout.vine_paths(surfaces, seed_value, stand_off)
		var patches: Array[Dictionary] = Layout.moss_patches(surfaces, seed_value, float(tuning.get("moss_span_scale", 0.4)))
		var entry: Dictionary = {
			"id": String(inst["id"]), "asset": String(inst["asset"]), "pos": inst["pos"], "yaw": float(inst["yaw"]),
			"offset": placement.asset_shape(inst["asset"])["offset"], "surfaces": surfaces, "paths": paths,
			"durations": Layout.root_durations(paths), "patches": patches, "roots": [], "moss": [],
		}
		for path_index: int in paths.size():
			var path: Dictionary = paths[path_index]
			if int(path["parent"]) >= 0:
				continue
			var hit: Dictionary = (path["points"] as Array)[0]
			entry["roots"].append({"path": path_index, "cells": _cells_near(entry, surfaces[int(path["surface"])], hit["position"]), "progress": 0.0, "input": 0.0})
		for patch_index: int in patches.size():
			var patch: Dictionary = patches[patch_index]
			var surface: Dictionary = surfaces[int(patch["surface"])]
			var base: Dictionary = Layout.sample(surface, patch["center"].x, 0.0)
			entry["moss"].append({"patch": patch_index, "cells": _cells_near(entry, surface, base["position"]), "progress": 0.0, "input": 0.0})
		entries.append(entry)

## Chart-local point -> world position (metres).
static func to_world(entry: Dictionary, local_point: Vector3) -> Vector3:
	var holder: Vector3 = Vector3(entry["pos"].x, 0.0, entry["pos"].y)
	return holder + Basis(Vector3.UP, float(entry["yaw"])) * (local_point + (entry["offset"] as Vector3))

static func normal_to_world(entry: Dictionary, local_normal: Vector3) -> Vector3:
	return Basis(Vector3.UP, float(entry["yaw"])) * local_normal

## Target cells within the radius of the anchor point (the wall point at the ground pushed `anchor_offset_m` outward).
func _cells_near(entry: Dictionary, surface: Dictionary, local_point: Vector3) -> PackedInt32Array:
	var world: Vector3 = to_world(entry, local_point)
	var normal: Vector3 = normal_to_world(entry, surface["normal"])
	var anchor: Vector2 = Vector2(world.x, world.z) + Vector2(normal.x, normal.z).normalized() * float(tuning.get("anchor_offset_m", 0.35))
	var radius: float = float(tuning.get("radius_m", 0.65))
	var cells: PackedInt32Array = PackedInt32Array()
	var centre: Vector2i = Coords.ground_to_cell(anchor)
	var reach: int = ceili(radius / 0.4) + 1
	for y: int in range(centre.y - reach, centre.y + reach + 1):
		for x: int in range(centre.x - reach, centre.x + reach + 1):
			if not state.in_bounds(x, y):
				continue
			var index: int = state.index_of(x, y)
			if state.target[index] == 1 and Coords.cell_center_ground(Vector2i(x, y)).distance_to(anchor) <= radius:
				cells.append(index)
	return cells

## Mean greening of the cells (0..1): mature = 1, growing = growth / mature_growth, empty = 0 (kept in the denominator).
func local_input(cells: PackedInt32Array) -> float:
	if cells.is_empty():
		return 0.0
	var total: float = 0.0
	for index: int in cells:
		var stage: int = state.stage[index]
		if stage == WorldState.STAGE_MATURE:
			total += 1.0
		elif stage >= WorldState.STAGE_SPROUT1:
			total += clampf(float(state.growth[index]) / float(sim_tuning.mature_growth), 0.0, 1.0)
	return total / float(cells.size())

func on_growth_tick(_tick: int = 0) -> void:
	tick_count += 1
	var dt: float = sim_tuning.growth_tick_seconds
	var vine_seconds: float = float(tuning.get("vine_seconds", 90.0))
	var moss_seconds: float = float(tuning.get("moss_seconds", 135.0))
	var changed: bool = false
	for entry: Dictionary in entries:
		for root: Dictionary in entry["roots"]:
			root["input"] = local_input(root["cells"])
			var next: float = minf(1.0, float(root["progress"]) + dt * float(root["input"]) / vine_seconds)
			if next != float(root["progress"]):
				root["progress"] = next
				changed = true
		for moss: Dictionary in entry["moss"]:
			moss["input"] = local_input(moss["cells"])
			var next_moss: float = minf(1.0, float(moss["progress"]) + dt * float(moss["input"]) / moss_seconds)
			if next_moss != float(moss["progress"]):
				moss["progress"] = next_moss
				changed = true
	if changed:
		serial += 1

func entry_of(instance_id: String) -> Dictionary:
	for entry: Dictionary in entries:
		if entry["id"] == instance_id:
			return entry
	return {}

## Sum of all progress values (observability for tests).
func total_progress() -> float:
	var total: float = 0.0
	for entry: Dictionary in entries:
		for root: Dictionary in entry["roots"]:
			total += float(root["progress"])
		for moss: Dictionary in entry["moss"]:
			total += float(moss["progress"])
	return total

## Fixture/test helper: sets every progress value (not used by the game).
func debug_set_all(value: float) -> void:
	for entry: Dictionary in entries:
		for root: Dictionary in entry["roots"]:
			root["progress"] = value
		for moss: Dictionary in entry["moss"]:
			moss["progress"] = value
	serial += 1

# ---- Save structure ----------------------------------------------------------------------------------------

func to_dict() -> Dictionary:
	var rows: Dictionary = {}
	for entry: Dictionary in entries:
		var roots: Array = []
		for root: Dictionary in entry["roots"]:
			roots.append(float(root["progress"]))
		var moss: Array = []
		for item: Dictionary in entry["moss"]:
			moss.append(float(item["progress"]))
		rows[entry["id"]] = {"roots": roots, "moss": moss}
	return {"version": 1, "ticks": tick_count, "entries": rows}

## Restores progress onto an entry layout that was rebuilt from the same placement. False when the data does not fit.
func load_dict(data: Dictionary) -> bool:
	if int(data.get("version", 0)) != 1:
		return false
	var rows: Dictionary = data.get("entries", {})
	if rows.size() != entries.size():
		return false
	for entry: Dictionary in entries:
		if not rows.has(entry["id"]):
			return false
		var row: Dictionary = rows[entry["id"]]
		if (row["roots"] as Array).size() != (entry["roots"] as Array).size() or (row["moss"] as Array).size() != (entry["moss"] as Array).size():
			return false
	for entry: Dictionary in entries:
		var row: Dictionary = rows[entry["id"]]
		for i: int in (entry["roots"] as Array).size():
			entry["roots"][i]["progress"] = clampf(float(row["roots"][i]), 0.0, 1.0)
		for i: int in (entry["moss"] as Array).size():
			entry["moss"][i]["progress"] = clampf(float(row["moss"][i]), 0.0, 1.0)
	tick_count = int(data.get("ticks", 0))
	serial += 1
	return true
