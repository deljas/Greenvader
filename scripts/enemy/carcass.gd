class_name Carcass
extends RefCounted
## One carcass / bone left by a defeated boar (P2-02). Display-free state; EnemyField drives it.
## age_steps counts fixed enemy steps since the boar fell (integer, so the timing is frame-rate independent).

const STAGE_CORPSE: int = 0
const STAGE_BONE: int = 1

var id: int = 0
## Where the boar fell (feet position, world px).
var pos: Vector2 = Vector2.ZERO
var age_steps: int = 0
var stage: int = STAGE_CORPSE

func to_dict() -> Dictionary:
	return {"id": id, "x": pos.x, "y": pos.y, "age": age_steps}
