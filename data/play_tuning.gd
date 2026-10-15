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
## Upper bound on seed fruits lying on the ground in the whole region. It is the sum of the separate slots (P2-03):
## seed sources (3 each) + plants (plant_fruit_cap) + defeated enemies (enemy_fruit_cap), so no kind can crowd another out
## (1 source: 3 + 20 + 12 = 35). Healing fruits have their own budget on top of it.
@export var pickup_total_cap: int = 35
## Seeds granted by one collected seed fruit.
@export var seed_fruit_seeds: int = 1

@export_group("Plant seed production (P1-03)")
## Seconds between production ticks (game time).
@export var plant_production_interval_seconds: float = 2.0
## Only mature tiles whose centre is within this radius (px) of the player produce fruits.
@export var plant_production_radius_px: float = 160.0
## Expected fruits per mature tile per second (the per-tick expectation is tiles * rate * interval).
@export var plant_fruit_rate_per_tile_second: float = 0.00125
## At most this many fruits per production tick.
@export var plant_fruit_max_per_tick: int = 3
## A tile holds at most this many of its own fruits on the ground.
@export var plant_fruit_per_tile_cap: int = 1
## Plant fruits on the ground in the whole region (kept below pickup_total_cap so seed-source fruits keep their slots).
@export var plant_fruit_cap: int = 20
## Seed fruits dropped by defeated boars / nests that lie on the ground in the whole region (their own slot: plant fruits,
## the seed sources' reservation and healing fruits never compete with it). When it is full, the reward is added to the
## player's seeds directly instead (anything above seed_max is lost).
@export var enemy_fruit_cap: int = 12
@export var plant_fruit_lifetime_seconds: float = 45.0
## Random jitter of the drop position inside the tile (px, +-).
@export var plant_fruit_jitter_px: float = 1.5

@export_group("HP and healing fruits (P1-05)")
@export var hp_max: int = 10
@export var hp_start: int = 10
## Healing fruits on the ground in the whole region. They live in their own budget on top of pickup_total_cap, so they
## can never take a slot of a seed fruit (seed sources keep their reserved slots, plants keep theirs).
@export var heal_fruit_total_cap: int = 16
## Used for a healing fruit whose own lifetime is not stored.
@export var heal_fruit_lifetime_seconds: float = 30.0
## HP restored by a healing fruit whose plant no longer exists.
@export var heal_fruit_fallback_heal: int = 2

@export_group("Walking (P1-06)")
## The player's feet are a rectangle of this half size (px) around the position; it cannot enter water or buildings.
@export var walk_half_width_px: float = 3.0
@export var walk_half_height_px: float = 2.0

@export_group("Damage and being downed (P2-03)")
## Seconds of invulnerability after a hit (the player flickers) and after returning from being downed.
@export var invuln_seconds: float = 1.2
@export var respawn_invuln_seconds: float = 2.0
## The flicker is dim / bright in turns of this length.
@export var flicker_toggle_seconds: float = 0.08
## A hit pushes the player away from the boar by this many px, spread over knockback_seconds (the Walker rules still hold).
@export var knockback_px: float = 12.0
@export var knockback_seconds: float = 0.1
## Seconds the player lies there (no control, the world goes on) before returning to the start with full HP.
@export var downed_seconds: float = 1.5
## Share of the carried seeds / water that is lost when returning from being downed (0 = everything is kept).
@export var downed_seed_loss_fraction: float = 0.0
@export var downed_water_loss_fraction: float = 0.0
## The damage state runs in fixed steps of 1 / health_step_hz seconds counted from the total time (frame rate independent).
@export var health_step_hz: int = 60

@export_group("Time")
## One advance never adds more than this (hitch guard), seconds. Same value as SimTuning.max_advance_seconds.
@export var max_step_seconds: float = 0.25
