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

## (P1-03) growth amount thresholds for sprout / mature, in growth units.
@export var sprout_growth: int = 100
@export var mature_growth: int = 400
## (P1-03) growth units per growth tick, and multiplier while watered.
@export var base_growth_per_tick: int = 10
@export var watered_growth_multiplier: float = 2.0
## (P1-02/03) moisture scale (0..moisture_max) and decay per growth tick.
@export var moisture_max: int = 100
@export var moisture_decay_per_tick: int = 2
## (P1-04) upper bound of tiles examined by one spread tick.
@export var max_spread_cells_per_tick: int = 16
