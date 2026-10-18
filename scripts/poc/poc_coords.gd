extends RefCounted
## Conversions between logical px (Walker/WorldState space), ground metres (X,Z) and cells.
## Ground (X,Z) = ORIGIN + logical * M_PER_LOGIC_PX. Screen up = (-1,-1), right = (+1,-1), down = (+1,+1).
const Config: GDScript = preload("res://scripts/poc/poc_config.gd")

## Ground position (metres) of logical (0,0). The 48x40 fixture is centred on the ground origin.
const ORIGIN: Vector2 = Vector2(-9.6, -8.0)
const INV_SQRT2: float = 0.70710678118654752

static func logic_to_ground(logic: Vector2) -> Vector2:
	return ORIGIN + logic * Config.M_PER_LOGIC_PX

static func ground_to_logic(ground: Vector2) -> Vector2:
	return (ground - ORIGIN) / Config.M_PER_LOGIC_PX

static func ground3(ground: Vector2, y: float = 0.0) -> Vector3:
	return Vector3(ground.x, y, ground.y)

static func logic_to_cell(logic: Vector2) -> Vector2i:
	return Vector2i(floori(logic.x / Config.TILE_PX), floori(logic.y / Config.TILE_PX))

static func cell_center_logic(cell: Vector2i) -> Vector2:
	return (Vector2(cell) + Vector2(0.5, 0.5)) * Config.TILE_PX

static func cell_center_ground(cell: Vector2i) -> Vector2:
	return logic_to_ground(cell_center_logic(cell))

static func ground_to_cell(ground: Vector2) -> Vector2i:
	return logic_to_cell(ground_to_logic(ground))

## Screen direction (x right, y down; length clamped to 1) -> ground direction (X,Z), same length.
## A screen diagonal has the same length as an axis direction, so speed is not sqrt(2) faster.
static func screen_dir_to_ground(screen_dir: Vector2) -> Vector2:
	var d: Vector2 = screen_dir.limit_length(1.0)
	return Vector2(d.x + d.y, -d.x + d.y) * INV_SQRT2

static func ground_dir_to_screen(ground_dir: Vector2) -> Vector2:
	return Vector2(ground_dir.x - ground_dir.y, ground_dir.x + ground_dir.y) * INV_SQRT2
