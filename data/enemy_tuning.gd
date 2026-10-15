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
@export var nest_hp: int = 20
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
