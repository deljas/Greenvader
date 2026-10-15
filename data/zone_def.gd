class_name ZoneDef
extends Resource
## Shared, read-only definition of one zone (P2-01) of a region. The zone layer PNG (RegionDef.zone_map_path,
## 1 px = 1 tile) colours every tile with the map_color of its zone; zones[i].id must equal i.
## Runtime state (state, counters) lives in WorldState; this resource only holds the initial values and the nest sites.

@export var id: int = 0
@export var key: StringName = &""
@export var display_name: String = ""
## Legend of the zone layer PNG (exact RGB).
@export var map_color: Color = Color.WHITE
## Initial state, one of WorldState.ZONE_* (0 unconquered, 1 clearing, 2 stable, 3 complete). The start zone is stable.
@export var initial_state: int = 0
## Top-left tile of each nest (EnemyTuning.nest_size_tiles square). Nests are placed in unconquered zones only.
@export var nest_tiles: Array[Vector2i] = []
