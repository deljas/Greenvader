extends RefCounted
## Unconnected PoC3 helper decisions. Static calls retain no Session/World reference
## and mutate neither the helper nor its candidate snapshots. Distances: logic px.
const WORK_RADIUS: float = 60.0 # 6m at 0.1m per logic px.
const CHASE_RADIUS: float = 80.0
const HOME_EPSILON: float = 3.0
const DANGER_ENTER: float = 35.0
const DANGER_EXIT: float = 45.0
const SUPPORT_RADIUS: float = 60.0
const REAR_OFFSET: float = 20.0
const IDLE_SECONDS: float = 3.0
const TARGET_DISTANCE_HYSTERESIS: float = 1.25
const NO_SLEEP_STATUSES: Array[String] = ["empty","no_water","no_water_route","unreachable","blocked","stranded","waiting_water","fleeing","resupplying","refilling","returning_water","moving","exploring"]

static func _alive(item: Dictionary) -> bool:
	return float(item.get("hp",1.0))>0.0

static func _reachable(at: Vector2, reachable: Callable) -> bool:
	return at.is_finite() and (not reachable.is_valid() or bool(reachable.call(at)))

static func _army_priority(enemy: Dictionary, helper: Dictionary, allies: Array[Dictionary]) -> int:
	var target_type: String=String(enemy.get("attack_target_type",""))
	if target_type in ["plants","helpers"] and String(enemy.get("phase","")) in ["attack","charge","windup"]:
		for ally: Dictionary in allies:
			if _alive(ally) and int(ally.get("id",-1))==int(enemy.get("attack_target_id",-2)) and ally.pos.distance_to(helper.home)<=WORK_RADIUS:
				return 0
	if String(enemy.get("phase","")) in ["eat","eating"]: return 1
	return 2

## New targets must be within 6m of home; an existing target can be pursued to 8m.
## Lost/dead/out-of-range current targets return -1: the adapter returns home and
## clears target_id only on arrival, before permitting a new acquisition.
static func army_target(helper: Dictionary, enemies: Array[Dictionary], allies: Array[Dictionary]) -> int:
	if helper.pos.distance_to(helper.home)>CHASE_RADIUS: return -1
	var current_id: int=int(helper.get("target_id",-1))
	var current: Dictionary={}
	var best: Dictionary={}
	var best_priority: int=3
	var best_distance: float=INF
	for enemy: Dictionary in enemies:
		if not _alive(enemy) or String(enemy.get("kind",""))=="mother" or String(enemy.get("category","enemies"))!="enemies": continue
		var from_home: float=enemy.pos.distance_to(helper.home)
		if int(enemy.id)==current_id and from_home<=CHASE_RADIUS: current=enemy
		if from_home>WORK_RADIUS: continue
		var priority: int=_army_priority(enemy,helper,allies)
		var distance: float=helper.pos.distance_squared_to(enemy.pos)
		if priority<best_priority or (priority==best_priority and (distance<best_distance or (is_equal_approx(distance,best_distance) and int(enemy.id)<int(best.get("id",2147483647))))):
			best=enemy; best_priority=priority; best_distance=distance
	if current_id>=0 and current.is_empty(): return -1
	if not current.is_empty():
		var current_priority: int=_army_priority(current,helper,allies)
		var current_distance: float=helper.pos.distance_to(current.pos)
		if best.is_empty() or current_priority<best_priority or (current_priority==best_priority and current_distance<=sqrt(best_distance)*TARGET_DISTANCE_HYSTERESIS):
			return int(current.id)
	return int(best.get("id",-1))

## Candidate records: id/pos/mature/watered for crops; tile/pos/growing/watered
## for grass. The adapter derives them from WorldState without storing a reference.
static func sprinkler_target(helper: Dictionary, crops: Array[Dictionary], grass: Array[Dictionary], reachable: Callable = Callable()) -> Dictionary:
	var candidates: Array[Dictionary]=[]
	for crop: Dictionary in crops:
		if _alive(crop) and not bool(crop.get("mature",false)) and not bool(crop.get("watered",false)):
			candidates.append({"kind":"crop","id":int(crop.id),"pos":crop.pos,"priority":0})
	for tile: Dictionary in grass:
		if bool(tile.get("growing",false)) and not bool(tile.get("watered",false)):
			candidates.append({"kind":"grass","id":int(tile.tile),"pos":tile.pos,"priority":1})
	var best: Dictionary={}
	var distance: float=INF
	for candidate: Dictionary in candidates:
		if candidate.pos.distance_to(helper.home)>WORK_RADIUS or not _reachable(candidate.pos,reachable): continue
		if String(helper.get("job_kind",""))==candidate.kind and int(helper.get("job_id",-1))==candidate.id:
			return candidate.duplicate()
		var d: float=helper.pos.distance_squared_to(candidate.pos)
		if best.is_empty() or candidate.priority<best.priority or (candidate.priority==best.priority and (d<distance or (is_equal_approx(d,distance) and candidate.id<best.id))):
			best=candidate; distance=d
	return best.duplicate()

## Candidate records: tile/pos/plantable/green_distance. The distance to existing
## green is provided by the adapter's local frontier search (INF if none exists).
## Reservations include flying helper shots, including those restored from saves.
static func sow_target(helper: Dictionary, candidates: Array[Dictionary], reserved: PackedInt32Array, reachable: Callable = Callable()) -> Dictionary:
	if int(helper.get("ammo",0))<=0: return {}
	var best: Dictionary={}
	var green_distance: float=INF
	var helper_distance: float=INF
	for candidate: Dictionary in candidates:
		if not bool(candidate.get("plantable",false)) or int(candidate.tile) in reserved: continue
		if candidate.pos.distance_to(helper.home)>WORK_RADIUS or not _reachable(candidate.pos,reachable): continue
		var green: float=float(candidate.get("green_distance",INF))
		var distance: float=helper.pos.distance_squared_to(candidate.pos)
		if best.is_empty() or green<green_distance or (green==green_distance and (distance<helper_distance or (is_equal_approx(distance,helper_distance) and int(candidate.tile)<int(best.tile)))):
			best=candidate; green_distance=green; helper_distance=distance
	return best.duplicate()

## Hysteresis applies to actual enemy distance, not to presentation alone.
static func danger(helper: Dictionary, threats: Array[Dictionary]) -> Dictionary:
	var threshold: float=DANGER_EXIT if String(helper.get("status",""))=="fleeing" else DANGER_ENTER
	var best: Dictionary={}
	var distance: float=threshold
	for enemy: Dictionary in threats:
		if not _alive(enemy): continue
		var d: float=helper.pos.distance_to(enemy.pos)
		if d<distance:
			best=enemy; distance=d
	return best.duplicate()

## Every accepted retreat target moves away from the threat. Unsafe home is
## never a fallback. Reachability is injected; the adapter must also check its
## first route step does not turn toward the threat to bypass an obstacle.
static func retreat_goal(helper: Dictionary, threat: Vector2, armies: Array[Dictionary], reachable: Callable = Callable()) -> Vector2:
	var away: Vector2=(helper.pos-threat).normalized()
	if away==Vector2.ZERO: away=Vector2.UP
	var current_distance: float=helper.pos.distance_to(threat)
	var rear: Vector2=helper.pos
	var nearest_army: float=INF
	for army: Dictionary in armies:
		if not _alive(army) or String(army.get("kind","army"))!="army": continue
		var distance: float=helper.pos.distance_to(army.pos)
		if distance>SUPPORT_RADIUS or distance>=nearest_army: continue
		var direction: Vector2=(army.pos-threat).normalized()
		if direction==Vector2.ZERO: direction=away
		var candidate: Vector2=army.pos+direction*REAR_OFFSET
		if (candidate-helper.pos).dot(away)>0.0 and candidate.distance_to(threat)>current_distance and _reachable(candidate,reachable):
			rear=candidate; nearest_army=distance
	if nearest_army<INF: return rear
	var home: Vector2=helper.home
	if (home-helper.pos).dot(away)>0.0 and home.distance_to(threat)>current_distance and _reachable(home,reachable): return home
	for angle: float in [0.0,PI/4.0,-PI/4.0]:
		var candidate: Vector2=helper.pos+away.rotated(angle)*30.0
		if _reachable(candidate,reachable): return candidate
	return helper.pos

## Return values are applied by the adapter and optionally saved with the helper.
static func idle_state(helper: Dictionary, elapsed: float, has_job: bool) -> Dictionary:
	var stopped: bool=String(helper.get("status","")) in NO_SLEEP_STATUSES
	var at_home: bool=helper.pos.distance_to(helper.home)<=HOME_EPSILON
	if String(helper.get("kind",""))=="army" or has_job or stopped or not at_home:
		return {"idle_since":-1.0,"sleeping":false}
	var since: float=float(helper.get("idle_since",-1.0))
	if since<0.0 or since>elapsed: since=elapsed
	return {"idle_since":since,"sleeping":elapsed-since>=IDLE_SECONDS}
