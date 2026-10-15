class_name Boar
extends RefCounted
## One boar (P2-01). Display-free state; EnemyField drives it. All timers are counted in fixed enemy steps (integers).

const MODE_WANDER: int = 0
const MODE_CHASE: int = 1

var id: int = 0
var nest_id: int = 0
var zone: int = 0
## Feet position in world pixels.
var pos: Vector2 = Vector2.ZERO
## Centre of the nest block (px): the tether is measured from here (kept when the nest is destroyed).
var home: Vector2 = Vector2.ZERO
var hp: int = 1
## 1 = looks right, -1 = looks left.
var facing: int = 1
var mode: int = MODE_WANDER
## Where it walks to (Vector2.INF = nowhere) and, when chasing, the plant tile it aims at (-1 = none).
var goal: Vector2 = Vector2.INF
var goal_tile: int = -1
var think: int = 0
var gnaw_cooldown: int = 0
var wait: int = 0
## Plant tile given up as unreachable (-1 = none) and the steps it stays excluded.
var blocked_tile: int = -1
var blocked_steps: int = 0
## Stuck detection: steps and position of the current observation window.
var window_steps: int = 0
var window_pos: Vector2 = Vector2.ZERO
var rng: int = 1
## Hit flash: fixed steps left (0 = none).
var flash_steps: int = 0

func next_int(bound: int) -> int:
	rng = (rng * 1103515245 + 12345) & 0x7FFFFFFF
	return (rng >> 8) % maxi(bound, 1)

func to_dict() -> Dictionary:
	return {
		"id": id, "nest_id": nest_id, "zone": zone, "pos": [pos.x, pos.y], "home": [home.x, home.y], "hp": hp, "facing": facing,
		"mode": mode, "goal": ([] if goal == Vector2.INF else [goal.x, goal.y]), "goal_tile": goal_tile, "think": think, "gnaw_cooldown": gnaw_cooldown, "wait": wait,
		"blocked_tile": blocked_tile, "blocked_steps": blocked_steps, "window_steps": window_steps, "window_pos": [window_pos.x, window_pos.y], "rng": rng, "flash": flash_steps,
	}

static func from_dict(data: Dictionary) -> Boar:
	var boar: Boar = Boar.new()
	boar.id = int(data["id"])
	boar.nest_id = int(data["nest_id"])
	boar.zone = int(data["zone"])
	boar.pos = Vector2(float(data["pos"][0]), float(data["pos"][1]))
	boar.home = Vector2(float(data["home"][0]), float(data["home"][1]))
	boar.hp = int(data["hp"])
	boar.facing = int(data["facing"])
	boar.mode = int(data["mode"])
	var g: Array = data["goal"]
	boar.goal = Vector2.INF if g.is_empty() else Vector2(float(g[0]), float(g[1]))
	boar.goal_tile = int(data["goal_tile"])
	boar.think = int(data["think"])
	boar.gnaw_cooldown = int(data["gnaw_cooldown"])
	boar.wait = int(data["wait"])
	boar.blocked_tile = int(data["blocked_tile"])
	boar.blocked_steps = int(data["blocked_steps"])
	boar.window_steps = int(data["window_steps"])
	boar.window_pos = Vector2(float(data["window_pos"][0]), float(data["window_pos"][1]))
	boar.rng = int(data["rng"])
	boar.flash_steps = maxi(int(data.get("flash", 0)), 0)
	return boar
