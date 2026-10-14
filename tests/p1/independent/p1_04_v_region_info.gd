extends SceneTree
## Extra observation for P1-04: where the large unreached component of region_01 lies relative to the reached one.
func _initialize() -> void:
	run.call_deferred()
func run() -> void:
	var def: RegionDef = load("res://data/region_01.tres") as RegionDef
	var s: WorldState = RegionLoader.load_region(def)
	var reach: Dictionary = {}
	var fr: Array = []
	for i: int in s.tile_count():
		if s.stage[i] == 4:
			reach[i] = true
			fr.append(i)
	while not fr.is_empty():
		var nx: Array = []
		for i: int in fr:
			for dy: int in range(-2, 3):
				for dx: int in range(-2, 3):
					if (dx != 0 or dy != 0) and dx * dx + dy * dy <= 4:
						var x: int = i % s.width + dx
						var y: int = i / s.width + dy
						if x < 0 or y < 0 or x >= s.width or y >= s.height:
							continue
						var j: int = y * s.width + x
						if not reach.has(j) and s.target[j] == 1 and s.terrain_defs[s.terrain[j]].plantable:
							reach[j] = true
							nx.append(j)
		fr = nx
	var rb: Rect2i = Rect2i(-1, -1, 0, 0)
	var minx: int = 999
	var maxx: int = -1
	var miny: int = 999
	var maxy: int = -1
	var umin: Vector2i = Vector2i(999, 999)
	var umax: Vector2i = Vector2i(-1, -1)
	var ucount: int = 0
	for i: int in s.tile_count():
		var x: int = i % s.width
		var y: int = i / s.width
		if reach.has(i):
			minx = mini(minx, x); maxx = maxi(maxx, x); miny = mini(miny, y); maxy = maxi(maxy, y)
		elif s.target[i] == 1:
			umin = Vector2i(mini(umin.x, x), mini(umin.y, y)); umax = Vector2i(maxi(umax.x, x), maxi(umax.y, y)); ucount += 1
	print("REACHED bbox x %d..%d y %d..%d ; UNREACHED target bbox %s..%s count %d" % [minx, maxx, miny, maxy, umin, umax, ucount])
	# terrain counts and water share
	var counts: Dictionary = {}
	for i: int in s.tile_count():
		counts[s.terrain[i]] = int(counts.get(s.terrain[i], 0)) + 1
	print("TERRAIN counts ", counts)
	# for each unreached target tile, smallest Chebyshev distance to a reached tile (scan windows up to 40)
	var best: int = 999
	var where: Vector2i = Vector2i.ZERO
	for i: int in s.tile_count():
		if s.target[i] == 1 and not reach.has(i):
			var x: int = i % s.width
			var y: int = i / s.width
			for k: int in range(1, mini(best, 41)):
				var hit: bool = false
				for dd: int in range(-k, k + 1):
					for p: Vector2i in [Vector2i(x + dd, y - k), Vector2i(x + dd, y + k), Vector2i(x - k, y + dd), Vector2i(x + k, y + dd)]:
						if p.x >= 0 and p.y >= 0 and p.x < s.width and p.y < s.height and reach.has(p.y * s.width + p.x):
							hit = true
				if hit:
					if k < best:
						best = k
						where = Vector2i(x, y)
					break
	print("MIN Chebyshev gap between an unreached target tile and the reached region = %d at %s" % [best, where])
	# can the player stand on water? player has no terrain collision; just report
	quit(0)
