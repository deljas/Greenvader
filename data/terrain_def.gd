class_name TerrainDef
extends Resource
## Shared, read-only definition of one terrain kind. Editable as .tres in the editor.
## Never holds per-tile runtime state (that lives in WorldState).
## Only the region map data (not scenery props) decides what is a greening target.

## Terrain id. Must equal the index of this def in RegionDef.terrains.
@export var id: int = 0
@export var key: StringName = &""
@export var display_name: String = ""
## Legend: the exact RGB colour of this terrain in the region map PNG (1 px = 1 tile).
@export var map_color: Color = Color.WHITE
## Counts in the greening-rate denominator. (P1: every target is also plantable.)
@export var is_target: bool = false
## Seeds/plants may be placed here.
@export var plantable: bool = false
@export var is_waterside: bool = false
## The player can stand on / walk through this terrain (P1-06). Water and buildings block; shallows and ground do not.
@export var walkable: bool = true
## Tiles of this terrain that start mature (initial_stage) also produce seed fruits. False for the safe zone: its
## ready-made plants must not flood the start with fruits (P1-06); a tile that is cleared and regrows produces normally.
@export var initial_produces_fruit: bool = false
## Initial plant id / growth stage of every tile of this terrain when a region is loaded.
@export var initial_plant_id: int = 0
@export var initial_stage: int = 0
## Flat on-screen ground colour (no outline, no speckle).
@export var ground_color: Color = Color.WHITE
