class_name RegionLoader
extends RefCounted
## Builds a WorldState from a RegionDef and its map PNG (1 px = 1 tile, colour = terrain legend).
##
## Loading choice: the PNG is imported by Godot (lossless) and read back with Texture2D.get_image().
## This keeps working in an exported build, where the source .png is not packed unless it is
## explicitly included, and it needs no file-system access. Image.load_from_file() is only a
## fallback for an un-imported project (e.g. before the first editor import).

static func load_map_image(path: String) -> Image:
	if ResourceLoader.exists(path):
		var texture: Texture2D = load(path) as Texture2D
		if texture != null:
			var image: Image = texture.get_image()
			if image != null and not image.is_empty():
				return image
	return Image.load_from_file(path)

static func color_key(r: int, g: int, b: int) -> int:
	return (r << 16) | (g << 8) | b

static func legend_key(color: Color) -> int:
	return color_key(roundi(color.r * 255.0), roundi(color.g * 255.0), roundi(color.b * 255.0))

## Returns null (after push_error) when the definition or the map is invalid.
static func load_region(def: RegionDef) -> WorldState:
	var image: Image = load_map_image(def.map_path)
	if image == null or image.is_empty():
		push_error("RegionLoader: cannot read map %s" % def.map_path)
		return null
	return build_state(def, image)

static func build_state(def: RegionDef, source: Image) -> WorldState:
	if source.get_width() != def.width_tiles or source.get_height() != def.height_tiles:
		push_error("RegionLoader: map is %dx%d but the region expects %dx%d" % [source.get_width(), source.get_height(), def.width_tiles, def.height_tiles])
		return null
	var legend: Dictionary = {}
	for index: int in def.terrains.size():
		var terrain_def: TerrainDef = def.terrains[index]
		if terrain_def.id != index:
			push_error("RegionLoader: terrain %s has id %d but sits at index %d" % [terrain_def.key, terrain_def.id, index])
			return null
		var key: int = legend_key(terrain_def.map_color)
		if legend.has(key):
			push_error("RegionLoader: duplicate legend colour for terrain %s" % terrain_def.key)
			return null
		legend[key] = index
	var image: Image = source.duplicate()
	image.convert(Image.FORMAT_RGBA8)
	var data: PackedByteArray = image.get_data()
	var state: WorldState = WorldState.new(def.width_tiles, def.height_tiles, def.terrains, def.sprout_seed)
	var last_key: int = -1
	var last_id: int = 0
	for index: int in state.tile_count():
		var base: int = index * 4
		var key: int = color_key(data[base], data[base + 1], data[base + 2])
		if key != last_key or data[base + 3] != 255:
			if not legend.has(key) or data[base + 3] != 255:
				push_error("RegionLoader: tile (%d,%d) has colour %06x/alpha %d that is not in the legend" % [index % state.width, index / state.width, key, data[base + 3]])
				return null
			last_key = key
			last_id = legend[key]
		state.terrain[index] = last_id
	if not def.zones.is_empty() and not _load_zones(def, state):
		return null
	state.apply_terrain_defs()
	return state

## Reads the zone layer (1 px = 1 tile, colour = ZoneDef.map_color) into the state. Every tile must have a zone.
static func _load_zones(def: RegionDef, state: WorldState) -> bool:
	var zone_image: Image = load_map_image(def.zone_map_path)
	if zone_image == null or zone_image.is_empty() or zone_image.get_width() != def.width_tiles or zone_image.get_height() != def.height_tiles:
		push_error("RegionLoader: cannot read a %dx%d zone layer from %s" % [def.width_tiles, def.height_tiles, def.zone_map_path])
		return false
	var legend: Dictionary = {}
	var states: PackedByteArray = PackedByteArray()
	for index: int in def.zones.size():
		var zone: ZoneDef = def.zones[index]
		if zone.id != index:
			push_error("RegionLoader: zone %s has id %d but sits at index %d" % [zone.key, zone.id, index])
			return false
		var key: int = legend_key(zone.map_color)
		if legend.has(key):
			push_error("RegionLoader: duplicate legend colour for zone %s" % zone.key)
			return false
		legend[key] = index
		states.append(zone.initial_state)
	var image: Image = zone_image.duplicate()
	image.convert(Image.FORMAT_RGBA8)
	var data: PackedByteArray = image.get_data()
	var ids: PackedByteArray = PackedByteArray()
	ids.resize(state.tile_count())
	for index: int in state.tile_count():
		var base: int = index * 4
		var key: int = color_key(data[base], data[base + 1], data[base + 2])
		if not legend.has(key) or data[base + 3] != 255:
			push_error("RegionLoader: zone layer tile (%d,%d) has colour %06x that is not in the zone legend" % [index % state.width, index / state.width, key])
			return false
		ids[index] = legend[key]
	return state.set_zones(ids, states)
