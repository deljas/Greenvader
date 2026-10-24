extends RefCounted
## Read-only area-watering plan, the water counterpart of SeedArea.plan.
## A cell is "effective" when watering it changes something: a growing (seed/sprout)
## grass cell that is still dry, or an unwatered, immature cultivated plant. A crop
## counts as ONE effective unit however large its footprint is; the unit is shown
## on the footprint cell nearest the centre. Nothing here mutates or reserves water.
const WIDTHS: Array[int] = [1, 3, 5, 7]

static func plan(
	world: WorldState,
	plants: Array[Dictionary],
	center: Vector2i,
	width: int,
	budget: int
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
	var crop_cells: Dictionary = {}
	for p: Dictionary in plants:
		if float(p.hp) <= 0.0 or bool(p.get("mature", false)) or bool(p.get("watered", false)):
			continue
		var footprint: Rect2i = Rect2i(Vector2i(p.cell), Vector2i(p.size)).intersection(rect)
		if not footprint.has_area():
			continue
		var best: Vector2i = footprint.position
		var best_distance: int = -1
		for y: int in range(footprint.position.y, footprint.end.y):
			for x: int in range(footprint.position.x, footprint.end.x):
				var distance: int = (Vector2i(x, y) - center).length_squared()
				if best_distance < 0 or distance < best_distance:
					best = Vector2i(x, y)
					best_distance = distance
		crop_cells[best] = true
	for y: int in range(rect.position.y, rect.end.y):
		for x: int in range(rect.position.x, rect.end.x):
			if not world.in_bounds(x, y):
				continue
			var cell: Vector2i = Vector2i(x, y)
			if crop_cells.has(cell):
				valid.append(cell)
				continue
			var index: int = world.index_of(x, y)
			if world.target[index] == 1 and world.stage[index] > WorldState.STAGE_EMPTY and world.stage[index] < WorldState.STAGE_MATURE and world.moisture[index] == 0:
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
