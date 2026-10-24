extends RefCounted
## Derive presentation from a read-only action dictionary. No session, orders or saved state are changed.
const Coords: GDScript = preload("res://scripts/poc/poc_coords.gd")
const STATES: Dictionary = {
	"enemies":["idle","move","windup","attack","hit","eat"],
	"helpers":["idle","move","attack","sow","water","flee"],
	"plants":["planted","growing","mature"],
	"nests":["idle","move","windup","attack","hit","eat"]}
var last_position: Vector2 = Vector2.ZERO
var last_hp: float = 0.0
var initialized: bool = false
var hit_until: float = -1.0
var direction: StringName = &"down"

func resolve(category: String, item: Dictionary, elapsed: float) -> Dictionary:
	var position_: Vector2 = item.pos
	var movement: Vector2 = position_ - last_position if initialized else Vector2.ZERO
	var moving: bool = movement.length_squared() > 0.00001
	var hp: float = float(item.get("hp",1.0))
	if initialized and hp < last_hp: hit_until = elapsed + 0.14
	last_position = position_
	last_hp = hp
	initialized = true
	var heading: Vector2 = Coords.ground_dir_to_screen(movement)
	if moving:
		direction = (&"right" if heading.x > 0 else &"left") if absf(heading.x)>absf(heading.y) else (&"down" if heading.y>0 else &"up")
	var supplied_direction: StringName = StringName(item.get("visual_direction",direction))
	if supplied_direction in [&"down",&"left",&"right",&"up"]: direction = supplied_direction
	var state: String = _state(category,item,elapsed,moving)
	# LOCUST/HELPERS can later supply presentation explicitly without changing this renderer.
	var supplied: String = String(item.get("visual_state",""))
	if supplied in STATES.get(category,[]): state = supplied
	return {"state":state,"direction":direction,"moving":moving}

func _state(category: String, item: Dictionary, elapsed: float, moving: bool) -> String:
	if category=="plants":
		if bool(item.get("mature",false)): return "mature"
		return "planted" if float(item.get("age",0.0))<=0.0 else "growing"
	if category=="helpers":
		var status: String = String(item.get("status",""))
		if status in ["flee","fleeing","retreating"]: return "flee"
		if moving: return "move"
		if status in ["watering","water"]: return "water"
		if status in ["fighting","attack"]: return "attack"
		if status=="sowing" or (item.get("kind","")=="gatlinger" and float(item.get("work_at",0.0))>elapsed): return "sow"
		return "idle"
	if hit_until>elapsed or float(item.get("stun_until",0.0))>elapsed: return "hit"
	var phase: String = String(item.get("phase",item.get("status","")))
	if phase in ["windup","tell"]: return "windup"
	if phase in ["attack","charge"]: return "attack"
	if phase in ["eat","eating"]: return "eat"
	return "move" if moving else "idle"
