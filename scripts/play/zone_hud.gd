class_name ZoneHud
extends RefCounted
## Texts of the zone display (P2-04): the status of the zone the player stands in (top bar) and the notice texts of the state
## changes. Display-free and static, so tests can read the exact strings. Japanese; the percent is an integer (floor).

const STATE_NAMES: Array[String] = ["未制圧", "掃討中", "安定", "緑化完了"]

static func state_name(state: int) -> String:
	return STATE_NAMES[clampi(state, 0, STATE_NAMES.size() - 1)]

static func zone_name(zones: Array[ZoneDef], zone: int) -> String:
	if zone >= 0 and zone < zones.size() and not zones[zone].display_name.is_empty():
		return zones[zone].display_name
	return "地域%d" % zone

## Zone id of the tile under `position` (world px), -1 outside the map.
static func zone_at_position(world: WorldState, tile_px: int, position: Vector2) -> int:
	var x: int = floori(position.x / tile_px)
	var y: int = floori(position.y / tile_px)
	if not world.in_bounds(x, y):
		return -1
	return world.zone_of[world.index_of(x, y)]

## "西岸北  掃討中  緑化 12％" (plus the clear mark once every zone is complete).
static func status_text(world: WorldState, zones: Array[ZoneDef], zone: int) -> String:
	var text: String = ""
	if zone >= 0 and zone < world.zone_count:
		text = "%s  %s  緑化 %d％" % [zone_name(zones, zone), state_name(world.zone_state[zone]), world.zone_greening_percent_floor(zone)]
	if world.cleared:
		text += "  【全地域緑化】"
	return text

## The notice for a zone that reached `new_state` ("" for states that need none).
static func change_text(zones: Array[ZoneDef], zone: int, new_state: int) -> String:
	var name: String = zone_name(zones, zone)
	match new_state:
		WorldState.ZONE_CLEARING:
			return "%sの巣をすべて壊した" % name
		WorldState.ZONE_STABLE:
			return "%sが安定した" % name
		WorldState.ZONE_COMPLETE:
			return "%sの緑化が完了した" % name
	return ""

const CLEARED_TEXT: String = "すべての地域を緑化した"
