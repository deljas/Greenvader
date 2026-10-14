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
## (P1-04) Growth tick split: at most this many active tiles are processed per growth tick. A larger active set is
## processed in sweeps (a tile waits at most ceil(active / limit) ticks; the elapsed ticks are applied in one go).
@export var max_growth_tiles_per_tick: int = 3000

@export_group("Natural spread (P1-04)")
## Candidate tiles: empty plantable tiles within this distance (tiles, Euclidean) of a mature tile.
@export var spread_radius_tiles: float = 2.0
## At most this many queued candidates are examined per spread tick (B).
@export var spread_candidates_per_tick: int = 1500
## At most this many newly mature / no longer mature tiles update the candidate data per spread tick.
@export var spread_mature_events_per_tick: int = 1000
## A candidate becomes a seed when its progress reaches the threshold.
@export var spread_progress_threshold: int = 100000
## Progress gained per spread tick (1 s) with one mature tile in range, plus this much for each further one.
@export var spread_progress_per_tick: int = 10000
@export var spread_progress_per_extra_neighbor: int = 2500
## Growth speed multiplier of seeds and sprouts planted by natural spread (the front speed knob).
@export var natural_growth_multiplier: float = 3.0

@export_group("Rendering (P1-04)")
## RegionView repaints at most this many dirty tiles per frame (the rest waits for the next frame, oldest first).
@export var render_tiles_per_frame: int = 6000
