class_name SimTuning
extends Resource
## Shared tuning values (initial defaults, adjustable without code edits).
## Values marked (P1-0x) are consumed by later tickets.

## Fixed simulation periods in game time (seconds).
@export var growth_tick_seconds: float = 0.5
@export var spread_tick_seconds: float = 1.0
## One advance() call never adds more than this much game time (hitch guard), seconds.
@export var max_advance_seconds: float = 0.25

## Presentation colours of the plant stages (flat, no outline).
@export var seed_color: Color = Color("ffe5a0")
@export var sprout_color: Color = Color("86d65f")
@export var mature_color: Color = Color("3f9b4a")
## Alpha of the half-transparent 1px edge of a mature tile on sides without a mature neighbour.
@export_range(0.0, 1.0) var edge_alpha: float = 0.5

## (P1-03) Growth. Growth amount is an integer; one growth tick adds
## base_growth_per_tick * moisture factor * fertility factor * sunlight factor (rounded to an integer).
## With the defaults a seed needs mature_growth / base_growth_per_tick = 120 ticks = 60 s dry, 30 s at full moisture.
@export var base_growth_per_tick: int = 1000
## Growth amount at which a seed becomes sprout 1 / sprout 2 / mature.
@export var sprout1_growth: int = 40000
@export var sprout2_growth: int = 80000
@export var mature_growth: int = 120000
## Moisture factor: moisture_growth_min at moisture 0, moisture_growth_max at moisture_max (linear). Min must stay > 0.
@export var moisture_growth_min: float = 1.0
@export var moisture_growth_max: float = 2.0
## Fertility byte (0..fertility_max) adds up to this fraction of speed (factor 1 + bonus * fertility / fertility_max).
@export var fertility_max: int = 100
@export var fertility_growth_bonus: float = 0.5
## Moisture scale (0..moisture_max) and decay per growth tick (1 per 0.5 s tick = 2 per second).
@export var moisture_max: int = 100
@export var moisture_decay_per_tick: int = 1
## (P1-04) upper bound of tiles examined by one spread tick.
@export var max_spread_cells_per_tick: int = 16
