class_name ZoneProgress
extends RefCounted
## Zone state transitions (P2-04). Display-free; moves the zone states of a WorldState forward from events only (a nest or a
## boar leaving the field, a tile becoming greened, a state being set from outside), never by scanning every frame:
##   unconquered -> clearing : every nest of the zone is destroyed
##   clearing    -> stable   : no boar of the zone is left
##   stable      -> complete : greened tiles of the zone == its greening targets (integer equality)
## A zone never goes back (a complete zone stays complete even if its greened count drops). A zone that starts without any nest
## settles at start() (the start zone is stable already). Stable / complete zones are closed to enemies: EnemyField removes the
## boars of a zone that becomes stable and never lets any enemy enter or bite one. When every zone is complete the region is
## cleared (WorldState.cleared, signal `cleared`); play goes on (the clear screen is P5-02).
##
## Notification is by signal: WorldState.zone_state_changed (every change, whoever made it) and this class's `cleared`.

## Every zone is complete (emitted once; not emitted again for a loaded, already cleared world).
signal cleared

var world: WorldState
var enemies: EnemyField
## True while settle() runs: the state changes it makes are reported in order and need no nested settling.
var _settling: bool = false

func _init(world_state: WorldState, enemy_field: EnemyField) -> void:
	world = world_state
	enemies = enemy_field
	enemies.enemies_changed.connect(settle)
	world.zone_state_changed.connect(_on_state_changed)
	world.zone_greened_listener = _on_greened

## Settles every zone once (initial state, or after a load).
func start() -> void:
	for zone: int in world.zone_count:
		settle(zone)
	_check_cleared()

## Moves the zone forward as far as its counts allow. Cheap: a few integer comparisons.
func settle(zone: int) -> void:
	if zone < 0 or zone >= world.zone_count:
		return
	if _settling:
		return
	_settling = true
	while true:
		var state: int = world.zone_state[zone]
		if state == WorldState.ZONE_UNCONQUERED and enemies.alive_nest_count(zone) == 0:
			world.set_zone_state(zone, WorldState.ZONE_CLEARING)
		elif state == WorldState.ZONE_CLEARING and enemies.boar_count_in_zone(zone) == 0:
			world.set_zone_state(zone, WorldState.ZONE_STABLE)
		elif state == WorldState.ZONE_STABLE and world.zone_fully_greened(zone):
			world.set_zone_state(zone, WorldState.ZONE_COMPLETE)
		else:
			break
	_settling = false
	_check_cleared()

## A tile of `zone` became greened: only a stable zone can complete by it (two integer reads).
func _on_greened(zone: int) -> void:
	if world.zone_state[zone] == WorldState.ZONE_STABLE and world.zone_greened_count[zone] == world.zone_target_count[zone]:
		settle(zone)

func _on_state_changed(zone: int, _old_state: int, new_state: int) -> void:
	# A state set from outside (tests, a load) may allow the next step at once; a complete zone may complete the region.
	if _settling:
		return
	if new_state == WorldState.ZONE_COMPLETE:
		_check_cleared()
	else:
		settle(zone)

func _check_cleared() -> void:
	if not world.cleared and world.all_zones_complete():
		world.cleared = true
		cleared.emit()
