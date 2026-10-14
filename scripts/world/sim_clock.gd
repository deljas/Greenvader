class_name SimClock
extends RefCounted
## Fixed-period simulation clock driven by game time (never by render frames).
## Ticks fire from the total elapsed game time, so splitting the same time into
## 1/30, 1/60 or 1/144 s steps yields identical tick counts.

signal growth_ticked(tick_index: int)
signal spread_ticked(tick_index: int)

## Tolerance for floating point accumulation of the step sum (seconds).
const EPSILON: float = 1.0e-9

var growth_period: float = 0.5
var spread_period: float = 1.0
## One advance() never adds more than this (hitch guard), seconds.
var max_advance: float = 0.25
## While true advance() ignores its argument: no time passes, and none is banked for later.
var paused: bool = false
var elapsed: float = 0.0
var growth_ticks: int = 0
var spread_ticks: int = 0

func configure(tuning: SimTuning) -> void:
	growth_period = tuning.growth_tick_seconds
	spread_period = tuning.spread_tick_seconds
	max_advance = tuning.max_advance_seconds

## Advances game time. Returns the game time actually consumed.
func advance(delta: float) -> float:
	if paused or delta <= 0.0:
		return 0.0
	delta = minf(delta, max_advance)
	elapsed += delta
	while true:
		var next_growth: float = float(growth_ticks + 1) * growth_period
		var next_spread: float = float(spread_ticks + 1) * spread_period
		var growth_due: bool = next_growth <= elapsed + EPSILON
		var spread_due: bool = next_spread <= elapsed + EPSILON
		if not growth_due and not spread_due:
			break
		# Time order; growth first when both are due at the same instant.
		if growth_due and (not spread_due or next_growth <= next_spread + EPSILON):
			growth_ticks += 1
			growth_ticked.emit(growth_ticks)
		else:
			spread_ticks += 1
			spread_ticked.emit(spread_ticks)
	return delta
