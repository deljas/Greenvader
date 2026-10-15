extends SceneTree
## Regenerates data/region_01_zones.png (512x512, 1 px = 1 tile, colour = ZoneDef.map_color) from data/region_01.png.
## Deterministic, no randomness. Run:
##   Godot --headless --path <project> --script res://scripts/tools/gen_zones_region_01.gd [-- --out=<png path>] [--suggest]
## Zone rule: the river splits the map into a west and an east bank at the centre line of the river's water in every row
## (water and shallows tiles between x = RIVER_X_FROM and RIVER_X_TO; the lake / pond lie outside that range). Each bank is
## cut into bands by row:
##   west: 0..124 north (1), 125..259 start (0, stable), 260..389 south 1 (2), 390.. south 2 (3)
##   east: 0..179 north (4), 180..339 middle (5), 340.. south (6)
## --suggest prints, for each nest anchor below, the nearest valid 4x4 nest site (all 16 tiles plantable, a 2-tile margin that
## is plantable ground too, the whole block inside the anchor's zone, 24+ tiles from earlier suggestions); the result is
## copied into data/zones/*.tres by hand, the tests verify it.

const W: int = 512
const H: int = 512
const RIVER_X_FROM: int = 200
const RIVER_X_TO: int = 330
const C_WATER: int = 0x4080e0
const C_SHALLOWS: int = 0x70b0e0
const C_WASTELAND: int = 0xb0a060
const C_SHORE: int = 0xe0d090
const WEST_CUTS: Array[int] = [125, 260, 390]
const WEST_IDS: Array[int] = [1, 0, 2, 3]
const EAST_CUTS: Array[int] = [180, 340]
const EAST_IDS: Array[int] = [4, 5, 6]
## Anchors of the nest sites: [zone id, x, y].
const ANCHORS: Array = [[1, 170, 100], [1, 70, 45], [2, 175, 300], [2, 60, 350], [3, 80, 430], [3, 190, 425], [4, 320, 95], [4, 440, 40], [4, 480, 150], [5, 335, 225], [5, 450, 260], [5, 400, 320], [6, 335, 380], [6, 400, 410], [6, 450, 480]]

func _initialize() -> void:
	var def: RegionDef = load("res://data/region_01.tres") as RegionDef
	var image: Image = Image.load_from_file(ProjectSettings.globalize_path(def.map_path))
	image.convert(Image.FORMAT_RGB8)
	var colors: PackedInt32Array = PackedInt32Array()
	colors.resize(W * H)
	for y: int in H:
		for x: int in W:
			var c: Color = image.get_pixel(x, y)
			colors[y * W + x] = (roundi(c.r * 255.0) << 16) | (roundi(c.g * 255.0) << 8) | roundi(c.b * 255.0)
	var zone_of: PackedByteArray = PackedByteArray()
	zone_of.resize(W * H)
	for y: int in H:
		var low: int = W
		var high: int = -1
		for x: int in range(RIVER_X_FROM, RIVER_X_TO):
			if colors[y * W + x] == C_WATER or colors[y * W + x] == C_SHALLOWS:
				low = mini(low, x)
				high = maxi(high, x)
		var centre: int = (low + high) / 2 if high >= 0 else (RIVER_X_FROM + RIVER_X_TO) / 2
		var band_west: int = 0
		while band_west < WEST_CUTS.size() and y >= WEST_CUTS[band_west]:
			band_west += 1
		var band_east: int = 0
		while band_east < EAST_CUTS.size() and y >= EAST_CUTS[band_east]:
			band_east += 1
		for x: int in W:
			zone_of[y * W + x] = WEST_IDS[band_west] if x < centre else EAST_IDS[band_east]
	var legend: Array[Color] = []
	for zone: ZoneDef in def.zones:
		legend.append(zone.map_color)
	if legend.size() < 7:
		legend = [Color8(96, 176, 96), Color8(224, 128, 96), Color8(224, 192, 64), Color8(192, 96, 160), Color8(96, 160, 224), Color8(160, 128, 224), Color8(64, 192, 192)]
	var out: Image = Image.create(W, H, false, Image.FORMAT_RGB8)
	var counts: Dictionary = {}
	for y: int in H:
		for x: int in W:
			var id: int = zone_of[y * W + x]
			var c: Color = legend[id]
			out.set_pixel(x, y, Color8(roundi(c.r * 255.0), roundi(c.g * 255.0), roundi(c.b * 255.0)))
			counts[id] = int(counts.get(id, 0)) + 1
	var out_path: String = ProjectSettings.globalize_path(def.zone_map_path if not def.zone_map_path.is_empty() else "res://data/region_01_zones.png")
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			out_path = argument.trim_prefix("--out=")
	var error: Error = out.save_png(out_path)
	print("GEN_ZONES result=%s path=%s counts=%s" % [error, out_path, counts])
	if OS.get_cmdline_user_args().has("--suggest"):
		suggest(colors, zone_of)
	quit(0)

func ground_ok(colors: PackedInt32Array, x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < W and y < H and (colors[y * W + x] == C_WASTELAND or colors[y * W + x] == C_SHORE)

func site_ok(colors: PackedInt32Array, zone_of: PackedByteArray, zone: int, tx: int, ty: int) -> bool:
	for y: int in range(ty - 2, ty + 6):
		for x: int in range(tx - 2, tx + 6):
			if not ground_ok(colors, x, y) or zone_of[y * W + x] != zone:
				return false
	return true

func suggest(colors: PackedInt32Array, zone_of: PackedByteArray) -> void:
	var taken: Array[Vector2i] = []
	for anchor: Array in ANCHORS:
		var best: Vector2i = Vector2i(-1, -1)
		var best_d: int = 1 << 30
		for ty: int in range(int(anchor[2]) - 40, int(anchor[2]) + 41):
			for tx: int in range(int(anchor[1]) - 40, int(anchor[1]) + 41):
				var d: int = (tx - int(anchor[1])) * (tx - int(anchor[1])) + (ty - int(anchor[2])) * (ty - int(anchor[2]))
				if d >= best_d or not site_ok(colors, zone_of, int(anchor[0]), tx, ty):
					continue
				var far: bool = true
				for other: Vector2i in taken:
					if Vector2(other).distance_to(Vector2(tx, ty)) < 24.0:
						far = false
				if far:
					best = Vector2i(tx, ty)
					best_d = d
		taken.append(best)
		print("NEST zone=%d tile=%s" % [anchor[0], best])
