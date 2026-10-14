extends SceneTree
## Regenerates data/region_01.png (512x512 tiles, 1 px = 1 tile, colours = TerrainDef.map_color).
## Deterministic. Run: Godot --headless --path <project> --script res://scripts/tools/gen_region_01.gd
## The P0 landscape composition (river bed, ruin, start) is reused, shifted by OFFSET_PX; the P0 decorative
## props (trees / rocks) are NOT used here. What counts as a greening target comes only from this map.

const W: int = 512
const H: int = 512
## P0 pixel coordinates -> region pixel coordinates.
const OFFSET_PX: Vector2 = Vector2(256, 384)
const TILE: float = 4.0
const START: Vector2i = Vector2i(184, 188)

var map: PackedByteArray = PackedByteArray()
var id_wasteland: int = 0
var id_safe: int = 0
var id_shore: int = 0
var id_water: int = 0
var id_building: int = 0
var seed_state: int = 12345

func _initialize() -> void:
	var def: RegionDef = load("res://data/region_01.tres") as RegionDef
	for terrain: TerrainDef in def.terrains:
		match terrain.key:
			&"wasteland": id_wasteland = terrain.id
			&"safe": id_safe = terrain.id
			&"shore": id_shore = terrain.id
			&"water": id_water = terrain.id
			&"building": id_building = terrain.id
	map.resize(W * H)
	map.fill(id_wasteland)
	# River: the P0 stream, extended straight to both map edges.
	var stream: Array[Vector2] = [Vector2(716, -400), Vector2(732, 150), Vector2(687, 232), Vector2(651, 285), Vector2(662, 338), Vector2(724, 418), Vector2(775, 482), Vector2(799, 554), Vector2(768, 666), Vector2(740, 1700), Vector2(835, 1700), Vector2(863, 673), Vector2(884, 554), Vector2(853, 465), Vector2(800, 399), Vector2(735, 321), Vector2(728, 292), Vector2(774, 239), Vector2(811, 157), Vector2(792, -400)]
	var tile_points: Array[Vector2] = []
	for point: Vector2 in stream:
		tile_points.append((point + OFFSET_PX) / TILE)
	fill_polygon(tile_points, id_water)
	# Lake with an island, and a pond.
	fill_ellipse(Vector2i(400, 150), Vector2i(40, 26), id_water, [])
	fill_ellipse(Vector2i(150, 470), Vector2i(18, 11), id_water, [])
	fill_ellipse(Vector2i(400, 150), Vector2i(7, 5), id_wasteland, [])
	# Shore: wasteland within 2 tiles of water.
	var shore_tiles: Array[int] = []
	for y: int in H:
		for x: int in W:
			if map[y * W + x] != id_water:
				continue
			for dy: int in range(-2, 3):
				for dx: int in range(-2, 3):
					var nx: int = x + dx
					var ny: int = y + dy
					if nx >= 0 and ny >= 0 and nx < W and ny < H and map[ny * W + nx] == id_wasteland:
						shore_tiles.append(ny * W + nx)
	for index: int in shore_tiles:
		map[index] = id_shore
	# Ruined buildings: the P0 ruin footprint, closed ring enclosures (isolated pockets), scattered blocks.
	fill_rect(Rect2i(int((292 + OFFSET_PX.x) / TILE), int((320 + OFFSET_PX.y) / TILE), 21, 8), id_building, [id_wasteland])
	for centre: Vector2i in [Vector2i(330, 300), Vector2i(450, 420), Vector2i(160, 300), Vector2i(400, 60), Vector2i(120, 60), Vector2i(330, 440), Vector2i(60, 210)]:
		fill_rect(Rect2i(centre.x - 6, centre.y - 6, 12, 12), id_building, [id_wasteland])
		fill_rect(Rect2i(centre.x - 4, centre.y - 4, 8, 8), id_wasteland, [id_building])
	var placed: int = 0
	var attempts: int = 0
	while placed < 30 and attempts < 4000:
		attempts += 1
		var w: int = 4 + next_random(11)
		var h: int = 3 + next_random(7)
		var x: int = 8 + next_random(W - 16 - w)
		var y: int = 8 + next_random(H - 16 - h)
		if Vector2(x + w / 2.0, y + h / 2.0).distance_to(Vector2(START)) < 50.0:
			continue
		if rect_only(Rect2i(x - 1, y - 1, w + 2, h + 2), id_wasteland):
			fill_rect(Rect2i(x, y, w, h), id_building, [id_wasteland])
			placed += 1
	# Safe zone around the start: starts fully mature.
	fill_ellipse(START, Vector2i(12, 9), id_safe, [id_wasteland, id_shore])
	write_png(def)
	quit(0)

func next_random(bound: int) -> int:
	seed_state = (seed_state * 1103515245 + 12345) & 0x7FFFFFFF
	return (seed_state >> 8) % bound

func rect_only(rect: Rect2i, id: int) -> bool:
	for y: int in range(rect.position.y, rect.end.y):
		for x: int in range(rect.position.x, rect.end.x):
			if x < 0 or y < 0 or x >= W or y >= H or map[y * W + x] != id:
				return false
	return true

func fill_rect(rect: Rect2i, id: int, only_over: Array) -> void:
	for y: int in range(maxi(rect.position.y, 0), mini(rect.end.y, H)):
		for x: int in range(maxi(rect.position.x, 0), mini(rect.end.x, W)):
			if only_over.is_empty() or map[y * W + x] in only_over:
				map[y * W + x] = id

func fill_ellipse(centre: Vector2i, radii: Vector2i, id: int, only_over: Array) -> void:
	for y: int in range(centre.y - radii.y, centre.y + radii.y + 1):
		for x: int in range(centre.x - radii.x, centre.x + radii.x + 1):
			if x < 0 or y < 0 or x >= W or y >= H:
				continue
			var dx: float = float(x - centre.x) / float(radii.x)
			var dy: float = float(y - centre.y) / float(radii.y)
			if dx * dx + dy * dy <= 1.0 and (only_over.is_empty() or map[y * W + x] in only_over):
				map[y * W + x] = id

## Even-odd scanline fill sampled at tile centres.
func fill_polygon(points: Array[Vector2], id: int) -> void:
	for y: int in H:
		var sample_y: float = y + 0.5
		var crossings: Array[float] = []
		for index: int in points.size():
			var a: Vector2 = points[index]
			var b: Vector2 = points[(index + 1) % points.size()]
			if (a.y <= sample_y and b.y > sample_y) or (b.y <= sample_y and a.y > sample_y):
				crossings.append(a.x + (sample_y - a.y) * (b.x - a.x) / (b.y - a.y))
		crossings.sort()
		for pair: int in range(0, crossings.size() - 1, 2):
			var from_x: int = maxi(ceili(crossings[pair] - 0.5), 0)
			var to_x: int = mini(ceili(crossings[pair + 1] - 0.5), W)
			for x: int in range(from_x, to_x):
				map[y * W + x] = id

func write_png(def: RegionDef) -> void:
	var image: Image = Image.create(W, H, false, Image.FORMAT_RGB8)
	var counts: Dictionary = {}
	for y: int in H:
		for x: int in W:
			var id: int = map[y * W + x]
			var legend_color: Color = def.terrains[id].map_color
			image.set_pixel(x, y, Color8(roundi(legend_color.r * 255.0), roundi(legend_color.g * 255.0), roundi(legend_color.b * 255.0)))
			counts[id] = int(counts.get(id, 0)) + 1
	var error: Error = image.save_png(ProjectSettings.globalize_path(def.map_path))
	print("GEN_REGION result=%s path=%s counts=%s" % [error, def.map_path, counts])
