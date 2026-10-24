extends RefCounted
## Grass-only AI. Caller supplies the locust cohort; no player/crop combat API is used.
const Coords: GDScript = preload("res://scripts/poc/poc_coords.gd")
const INITIAL_GROUP: int = 6
const ALIVE_CAP: int = 12
const BASE_HP: float = 5.0
const BASE_REWARD: int = 1
const SPAWN_INTERVAL_S: float = 20.0
const SPEED_LOGIC: float = 14.0
const HOME_RADIUS_LOGIC: float = 100.0
const SEARCH_INTERVAL_S: float = 1.0
const EAT_SECONDS: float = 3.0
const ARRIVAL_LOGIC: float = 1.0
const ATTRACTOR_RANGE_LOGIC: float = 30.0
const ATTRACTOR_GRASS_LOGIC: float = 12.0
const ATTRACTOR_WEIGHT: float = 0.45
var state: WorldState
var nav: RefCounted
var reservations: Dictionary = {} # tile index -> live locust id; derived, never serialized.

func setup(world: WorldState, navigation: RefCounted) -> void:
	state=world
	nav=navigation
	reservations.clear()

static func spawn_count(alive_from_nest: int) -> int:
	# Initial members count towards the cap, as do surviving later offspring.
	return mini(INITIAL_GROUP,maxi(ALIVE_CAP-alive_from_nest,0))

func release(actor: Dictionary) -> void:
	var tile: int=int(actor.get("eat_tile",-1))
	if reservations.get(tile,-1)==int(actor.id): reservations.erase(tile)
	actor.eat_tile=-1
	actor.eat_elapsed=0.0
	actor.route_at=-1.0
	actor.phase="idle"

func _open(cell: Vector2i) -> bool:
	if not state.in_bounds(cell.x,cell.y) or not state.is_walkable(cell.x,cell.y): return false
	return state.zone_state[state.zone_at(state.index_of(cell.x,cell.y))]<WorldState.ZONE_STABLE

func _edible(tile: int) -> bool:
	if tile<0 or tile>=state.tile_count(): return false
	return state.target[tile]!=0 and state.stage[tile]>=WorldState.GREENED_MIN_STAGE and state.occupant[tile]==0 and _open(Vector2i(tile%state.width,tile/state.width))

func _path_open(path: Array) -> bool:
	if path.is_empty(): return false
	for cell: Vector2i in path:
		if not _open(cell): return false
	return true

func _goal(tile: int) -> Vector2:
	return Coords.cell_center_logic(Vector2i(tile%state.width,tile/state.width))

func _score(actor: Dictionary, tile: int, crops: Array[Dictionary]) -> float:
	var goal: Vector2=_goal(tile)
	var score: float=actor.pos.distance_squared_to(goal)
	for crop: Dictionary in crops:
		if crop.get("kind","")!="rafflesia" or not bool(crop.get("mature",false)) or float(crop.get("hp",0.0))<=0.0: continue
		if actor.pos.distance_to(crop.pos)<=ATTRACTOR_RANGE_LOGIC and goal.distance_to(crop.pos)<=ATTRACTOR_GRASS_LOGIC:
			return score*ATTRACTOR_WEIGHT
	return score

func _find(actor: Dictionary, crops: Array[Dictionary], now: float) -> int:
	var center: Vector2i=Coords.logic_to_cell(actor.home)
	var candidates: Array[Dictionary]=[]
	var radius: int=ceili(HOME_RADIUS_LOGIC/4.0)
	for y: int in range(maxi(0,center.y-radius),mini(state.height,center.y+radius+1)):
		for x: int in range(maxi(0,center.x-radius),mini(state.width,center.x+radius+1)):
			var tile: int=state.index_of(x,y)
			if reservations.has(tile) or not _edible(tile): continue
			if actor.home.distance_to(_goal(tile))>HOME_RADIUS_LOGIC: continue
			candidates.append({"tile":tile,"score":_score(actor,tile,crops)})
	candidates.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return a.score<b.score if a.score!=b.score else a.tile<b.tile)
	for candidate: Dictionary in candidates:
		var path: Array[Vector2i]=nav.route(actor.pos,_goal(candidate.tile),true)
		if not _path_open(path): continue
		actor.route=path
		actor.route_index=1
		actor.route_at=now+SEARCH_INTERVAL_S
		actor.goal=_goal(candidate.tile)
		return int(candidate.tile)
	return -1

func advance(actors: Array[Dictionary], crops: Array[Dictionary], dt: float, now: float) -> void:
	if not is_finite(dt) or dt<=0.0: return
	# Rebuild only the small cohort's claims. Death/removal/invalid grass cannot leave a stale reservation.
	reservations.clear()
	for actor: Dictionary in actors:
		if actor.get("kind","")!="locust": continue
		var tile: int=int(actor.get("eat_tile",-1))
		if float(actor.get("hp",0.0))<=0.0 or not _edible(tile) or reservations.has(tile): release(actor)
		else: reservations[tile]=int(actor.id)
	for actor: Dictionary in actors:
		if actor.get("kind","")=="locust" and float(actor.get("hp",0.0))>0.0: _advance_actor(actor,crops,dt,now)

func _advance_actor(actor: Dictionary, crops: Array[Dictionary], dt: float, now: float) -> void:
	if not _open(Coords.logic_to_cell(actor.pos)):
		release(actor)
		return
	if float(actor.get("stun_until",0.0))>now:
		actor.eat_elapsed=0.0
		actor.phase="stunned"
		return
	var tile: int=int(actor.get("eat_tile",-1))
	if tile<0:
		if now<float(actor.get("eat_search_at",0.0)): return
		actor.eat_search_at=now+SEARCH_INTERVAL_S
		tile=_find(actor,crops,now)
		if tile<0: return
		actor.eat_tile=tile
		actor.eat_elapsed=0.0
		reservations[tile]=int(actor.id)
	var goal: Vector2=_goal(tile)
	if actor.pos.distance_to(goal)>ARRIVAL_LOGIC:
		# Check the current route against live stable-zone state, even if nav's cached grid is older.
		var path: Array=actor.get("route",[])
		if not _path_open(path):
			release(actor)
			return
		actor.phase="chase"
		actor.eat_elapsed=0.0
		nav.move(actor,goal,SPEED_LOGIC,dt,now,true)
		return
	actor.phase="eat"
	actor.eat_elapsed=float(actor.get("eat_elapsed",0.0))+dt
	if float(actor.eat_elapsed)>=EAT_SECONDS:
		# set_stage also updates counts/income, dirty state and permanent-water reset/listeners.
		state.set_stage(tile,WorldState.STAGE_EMPTY)
		release(actor)
