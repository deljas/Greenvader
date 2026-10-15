class_name EnemyTuning
extends Resource
## P2-01 tuning: nests, spawning and the boar. Initial values; adjust here (data), not in code.
## All times are game seconds. The enemy simulation runs in fixed steps of 1 / step_hz seconds, so the result does not
## depend on the frame rate.

@export_group("Switch")
## False = no enemy ever acts (advance does nothing). A test switch, e.g. for the bot regressions of P1.
@export var enabled: bool = true
@export var step_hz: int = 60
## One advance() never adds more than this (hitch guard), seconds.
@export var max_step_seconds: float = 0.25
## Base of the fixed pseudo-random sequences (spawn positions, wandering).
@export var rng_seed: int = 20261016

@export_group("Nest")
## A nest occupies a size x size block of tiles (WorldState.occupy) until it is destroyed.
@export var nest_size_tiles: int = 4
@export var nest_hp: int = 30
## No more nests than this are placed (performance bound).
@export var nest_max_count: int = 15

@export_group("Spawning")
@export var spawn_interval_seconds: float = 12.0
## Boars alive at once per nest and in the whole region. The spawn timer only runs while both limits have room.
@export var nest_boar_cap: int = 4
@export var boar_cap: int = 40
## Spawn points lie on a ring of this distance (px) outside the nest block.
@export var spawn_ring_px: float = 8.0

@export_group("Boar")
@export var boar_hp: int = 3
@export var boar_speed_px: float = 36.0
## Feet rectangle (half size, px) used for walking: it cannot enter water or buildings (same rule as Walker).
@export var boar_half_width_px: float = 5.0
@export var boar_half_height_px: float = 3.0
## A boar never goes farther than this from its nest (tiles).
@export var tether_tiles: int = 48
@export var wander_radius_tiles: int = 10
@export var wander_wait_seconds: float = 2.0
## Seconds between two choices of what to do (nearest plant or wandering). Boars are staggered.
@export var think_interval_seconds: float = 0.75
## A boar removes the plants within gnaw_radius_tiles of itself (tile centres) once per interval.
@export var gnaw_interval_seconds: float = 0.6
@export var gnaw_radius_tiles: float = 1.0
## A chase goal counts as reached within this distance (px).
@export var arrival_px: float = 2.0
## A chasing boar that moved less than a quarter of its way in this time gives the goal up for blocked_seconds.
@export var stuck_check_seconds: float = 1.0
@export var blocked_seconds: float = 10.0
## Plants within this many tiles (Chebyshev) of a given-up goal are not chosen while it is blocked.
@export var blocked_radius_tiles: int = 6
## Radius (px) of the circle around the boar body that shots hit (P2-02 uses it) and the body's centre height above the feet.
@export var hit_radius_px: float = 8.0
@export var hit_center_height_px: float = 6.0

@export_group("Contact (P2-03)")
## HP the player loses when the feet touch the body circle (hit_radius_px) of a boar (once per invulnerability period).
@export var contact_damage: int = 2

@export_group("Combat (P2-02)")
## Hit points a shot takes away. A seed shot hurts; a cultivated plant shot (carrot / kiwi) is stopped by the enemy but
## does no damage by default (its held-back seeds go back to the player). Water shots pass through enemies unless this is on.
@export var seed_damage: int = 1
@export var plant_shot_damage: int = 0
@export var water_hits_enemies: bool = false
## A hit that does not kill makes the boar / nest flash for this long; the flash toggles every flash_toggle_seconds.
@export var hit_flash_seconds: float = 0.25
@export var hit_flash_toggle_seconds: float = 0.05
## Seed fruits dropped on defeat (as many as the ground pickup rules leave room for) and where they lie around the spot (px).
@export var boar_drop_fruits: int = 2
@export var nest_drop_fruits: int = 4
@export var drop_radius_min_px: float = 3.0
@export var drop_radius_max_px: float = 8.0
@export var drop_fruit_lifetime_seconds: float = 60.0

@export_group("Carcass and bones (P2-02)")
## A defeated boar leaves a carcass; it raises the fertility of every tile whose centre is within this radius (tiles).
@export var carcass_radius_tiles: float = 4.0
## Carcass stage, then bone stage, then it vanishes (game seconds).
@export var carcass_seconds: float = 60.0
@export var bone_seconds: float = 40.0
## Fertility (WorldState.fertility byte, GrowthSim: factor 1 + bonus * fertility / fertility_max) a carcass / bone adds.
## When the carcass becomes bone the effect drops to the bone value; when the bone vanishes it is taken away completely.
@export var carcass_fertility: int = 40
@export var bone_fertility: int = 20
## Overlapping carcasses add up but never beyond this (carcass effect per tile).
@export var carcass_fertility_cap: int = 60
## Carcasses and bones together; beyond it the oldest one goes (through bone) to nothing.
@export var carcass_cap: int = 24
