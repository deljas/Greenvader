class_name PlantDef
extends Resource
## Shared, read-only plant kind definition (stages are WorldState.STAGE_*).
## Only the container is provided in P1-01; carrot/kiwi/helper plants arrive in P1-05 and P3.

@export var id: int = 0
@export var key: StringName = &""
@export var display_name: String = ""
## Side length in tiles of the footprint: 1 normal, 2 cultivated, 4 helper plants.
@export var footprint_tiles: int = 1
