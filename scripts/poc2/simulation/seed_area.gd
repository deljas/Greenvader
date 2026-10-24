extends RefCounted
## Read-only area-sowing plan shared by future preview and ground-impact callers.
## Cells are Vector2i map coordinates, not logical pixels. No Session dependency.
const Coords: GDScript = preload("res://scripts/poc/poc_coords.gd")
const WIDTHS: Array[int] = [1, 3, 5, 7]

## budget is the total seeds available for this plan. At impact the caller includes
## the shot's one reserved seed; this function never reserves, spends or plants.
## Helpers use current logical-pixel pos and hp, never their old cell/home/owner.
## Each call reads current state. Do not cache a preview for later settlement.
static func plan(
	world: WorldState,
	center: Vector2i,
	width: int,
	budget: int,
	helpers: Array[Dictionary] = []
) -> Dictionary:
	var valid: Array[Vector2i] = []
	var affordable: Array[Vector2i] = []
	var unaffordable: Array[Vector2i] = []
	var result: Dictionary = {
		"ok": false, "reason": "", "center": center, "width": width,
		"rect": Rect2i(), "valid": valid, "affordable": affordable,
		"unaffordable": unaffordable, "cost": 0
	}
	if world == null:
		result.reason = "invalid_world"
		return result
	if not WIDTHS.has(width):
		result.reason = "invalid_width"
		return result

	var half: int = width >> 1
	var rect: Rect2i = Rect2i(center - Vector2i(half, half), Vector2i(width, width))
	result.rect = rect
	var helper_cells: Dictionary = {}
	for helper: Dictionary in helpers:
		if float(helper.hp) <= 0.0:
			continue
		var current: Vector2 = helper.pos
		if current.is_finite():
			helper_cells[Coords.logic_to_cell(current)] = true

	for y: int in range(rect.position.y, rect.end.y):
		for x: int in range(rect.position.x, rect.end.x):
			if not world.in_bounds(x, y):
				continue
			var cell: Vector2i = Vector2i(x, y)
			# can_plant rejects non-target/unplantable terrain, existing seed/grass
			# and occupied crop/helper footprints. Moving helpers may release owners.
			if not helper_cells.has(cell) and world.can_plant(world.index_of(x, y)):
				valid.append(cell)

	valid.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var distance_a: int = (a - center).length_squared()
		var distance_b: int = (b - center).length_squared()
		if distance_a != distance_b:
			return distance_a < distance_b
		if a.y != b.y:
			return a.y < b.y
		return a.x < b.x
	)
	var limit: int = mini(maxi(budget, 0), valid.size())
	for i: int in valid.size():
		if i < limit:
			affordable.append(valid[i])
		else:
			unaffordable.append(valid[i])
	result.ok = true
	result.cost = affordable.size()
	return result
