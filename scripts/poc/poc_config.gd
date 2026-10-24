extends RefCounted
## PoC constants in one place. Everything here is expressed in physical units (metres, seconds) or
## logical pixels; nothing depends on the screen resolution. Reversible initial values.

## One logical cell is 0.4 m and 4 logical px wide (existing 4 px tile -> cell connection).
const CELL_M: float = 0.4
const TILE_PX: int = 4
const M_PER_LOGIC_PX: float = 0.1

## Adopted internal pixel grid. Window presentation uses nearest integer scaling.
const RESOLUTIONS: Array[Vector2i] = [Vector2i(640, 360)]
const DEFAULT_RESOLUTION: int = 0
const MIN_WINDOW: Vector2i = Vector2i(640, 360)
## Adopted bulb frames: 1 texel = 1 internal screen pixel.
const SPRITE_FRAME_PX: Array[Vector2i] = [Vector2i(24, 36)]

## Fixed orthographic quarter view. Screen up = north = ground (-1,0,-1).
const ELEVATION_DEG: float = 30.0
const AZIMUTH_DEG: float = 45.0
## Vertical extent of the view in metres (camera.size with KEEP_HEIGHT).
const CAMERA_SIZE_M: float = 18.5
## The camera looks at the player's position raised by this height (roughly torso).
const CAMERA_TARGET_HEIGHT_M: float = 1.2
const CAMERA_DISTANCE_M: float = 49.0
const CAMERA_FAR_M: float = 150.0

## Player movement (m/s, POL-01: 2.4 -> 4.8; unaffected by time multiplier) and feet half size.
const WALK_SPEED_MPS: float = 4.8
const PLAYER_HALF_M: float = 0.28
## Reserved ranges for later PoC steps (seed throw range, pickup distance).
const THROW_RANGE_M: float = 3.0
const PICKUP_RADIUS_M: float = 1.0

## Time. One advance never exceeds MAX_STEP_S of game time; multiplier fast-forwards.
const MAX_STEP_S: float = 0.25
const MULTIPLIERS: Array[float] = [1.0, 4.0, 16.0]

static func m_to_px(metres: float) -> float:
	return metres / M_PER_LOGIC_PX

static func px_to_m(logic_px: float) -> float:
	return logic_px * M_PER_LOGIC_PX

static func walk_speed_px() -> float:
	return m_to_px(WALK_SPEED_MPS)

static func player_half_px() -> Vector2:
	var half: float = m_to_px(PLAYER_HALF_M)
	return Vector2(half, half)

static func throw_range_px() -> float:
	return m_to_px(THROW_RANGE_M)

static func pickup_radius_px() -> float:
	return m_to_px(PICKUP_RADIUS_M)

## True when `resolution` fits in a window of `window_size` (no silent downscale).
static func fits(resolution: Vector2i, window_size: Vector2i) -> bool:
	return window_size.x >= resolution.x and window_size.y >= resolution.y

## Largest integer scale of `resolution` inside `window_size` (0 when it does not fit).
static func integer_scale(resolution: Vector2i, window_size: Vector2i) -> int:
	return mini(window_size.x / resolution.x, window_size.y / resolution.y)
