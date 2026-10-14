class_name PlantDef
extends Resource
## Shared, read-only plant kind definition (stages are WorldState.STAGE_*). Add a plant by adding a .tres of this
## class to data/plants/ and listing it in the region's `plants` (the selection order of the HUD is the list order).
## P1-05 uses the cultivated plants (footprint 2): carrot and kiwi. Helper plants (footprint 4) arrive in P3.

## Effect kinds (PlantDef.effect).
const EFFECT_NONE: StringName = &""
## Mature plants multiply the natural spread progress of candidate tiles within effect_radius_tiles.
const EFFECT_SPREAD_BOOST: StringName = &"spread_boost"
## Mature plants drop healing fruits.
const EFFECT_HEAL_FRUIT: StringName = &"heal_fruit"

@export var id: int = 0
@export var key: StringName = &""
@export var display_name: String = ""
## Side length in tiles of the footprint: 1 normal, 2 cultivated, 4 helper plants.
@export var footprint_tiles: int = 1
@export var effect: StringName = &""

@export_group("Planting")
## Ordinary seeds spent when the plant is placed (only a successful placement spends them).
@export var seed_cost: int = 1
## Plants of this kind that may exist at once (in-flight shots count).
@export var max_count: int = 32
## Game seconds from planting (young) to mature. The effect works only when mature.
@export var grow_seconds: float = 40.0

@export_group("Spread boost effect")
## Tiles (Euclidean, from the footprint centre to the candidate tile centre).
@export var effect_radius_tiles: float = 12.0
## Multiplier of the natural spread progress inside the radius. Overlaps do not stack: the largest wins.
@export var effect_multiplier: float = 1.0

@export_group("Healing fruit effect")
@export var fruit_interval_seconds: float = 20.0
## Fruits of one plant lying on the ground at once.
@export var fruit_cap: int = 2
@export var fruit_lifetime_seconds: float = 30.0
## HP restored by one fruit.
@export var fruit_heal: int = 2
## A fruit drops this far (px) from the footprint centre.
@export var fruit_drop_radius_min_px: float = 6.0
@export var fruit_drop_radius_max_px: float = 12.0

func is_cultivated() -> bool:
	return footprint_tiles > 1
