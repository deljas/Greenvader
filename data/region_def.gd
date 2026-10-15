class_name RegionDef
extends Resource
## Shared definition of one region: where its map PNG lives, the legend (terrain defs) and the start.

@export var id: StringName = &"region_01"
## 1 px of this PNG = 1 tile. The PNG colours are the legend (TerrainDef.map_color).
@export_file("*.png") var map_path: String = "res://data/region_01.png"
@export var width_tiles: int = 512
@export var height_tiles: int = 512
@export var tile_px: int = 4
## Legend. terrains[i].id must equal i.
@export var terrains: Array[TerrainDef] = []
@export var plants: Array[PlantDef] = []
@export var start_tile: Vector2i = Vector2i(184, 188)
## Tiles holding an indestructible seed source (must lie in the safe zone).
@export var seed_source_tiles: Array[Vector2i] = [Vector2i(189, 186)]
## Seed of the fixed per-tile sprout position hash.
@export var sprout_seed: int = 20261014

@export_group("Zones (P2-01)")
## Zone layer: 1 px = 1 tile, every tile coloured with its zone's map_color. Empty = no zones (one unconquered zone).
@export_file("*.png") var zone_map_path: String = ""
## Zone legend and nest sites; zones[i].id must equal i.
@export var zones: Array[ZoneDef] = []
