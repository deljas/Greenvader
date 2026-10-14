class_name PlayTuning
extends Resource
## P1-02 tuning: seeds, water, projectiles, landing, water refill, seed source and ground pickups.
## Initial values; adjust here (data), not in code.

@export_group("Seeds")
@export var seed_start: int = 20
@export var seed_max: int = 40

@export_group("Water gauge")
@export var water_max: float = 100.0
@export var water_start: float = 100.0
## Gauge spent by one water shot.
@export var water_cost_per_shot: float = 10.0
## Gauge recovered per second while near a waterside / water tile.
@export var water_refill_per_second: float = 25.0
## Refill applies while the player's tile is within this many tiles (Euclidean, tile units) of a waterside tile.
@export var water_refill_distance_tiles: float = 2.0

@export_group("Projectiles")
@export var projectile_speed: float = 160.0
## A target farther than this lands at this distance along the aim direction.
@export var projectile_range_px: float = 120.0
@export var max_projectiles: int = 64
## Safety lifetime of one projectile in seconds.
@export var projectile_max_age: float = 1.8

@export_group("Seed landing")
## Tiles whose centre lies within this radius (px) of the landing point are candidates.
@export var seed_scatter_radius_px: float = 10.0
## At most this many candidate tiles become seeds per landing.
@export var seed_scatter_max: int = 6
## Base of the fixed random sequence (landing n uses a generator seeded from this and n).
@export var scatter_seed: int = 20261015

@export_group("Water landing")
@export var water_splash_radius_px: float = 12.0
## Moisture added to each target tile in range (capped at SimTuning.moisture_max).
@export var water_moisture_add: int = 40

@export_group("Seed source")
## Seconds between fruit drops while the source has room for more.
@export var source_interval_seconds: float = 8.0
## Fruits owned by one source that may lie on the ground at once.
@export var source_fruit_cap: int = 3
@export var source_drop_radius_min_px: float = 10.0
@export var source_drop_radius_max_px: float = 18.0

@export_group("Ground pickups (shared by sources and mature plants)")
@export var pickup_collect_radius_px: float = 12.0
@export var pickup_lifetime_seconds: float = 60.0
## Upper bound on pickups lying on the ground in the whole region.
@export var pickup_total_cap: int = 24
## Seeds granted by one collected seed fruit.
@export var seed_fruit_seeds: int = 1

@export_group("Time")
## One advance never adds more than this (hitch guard), seconds. Same value as SimTuning.max_advance_seconds.
@export var max_step_seconds: float = 0.25
