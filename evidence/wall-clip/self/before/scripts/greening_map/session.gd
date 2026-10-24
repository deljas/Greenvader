extends RefCounted
## Lab composition over the actual game state/simulators; no rendering dependency.
const WIDTH: int = 48
const HEIGHT: int = 40
const TILE_PX: int = 4
const CELL: float = 0.4
const ORIGIN: Vector2 = Vector2(-9.6,-8.0)
const SPEED: float = 24.0 # logical px/s = 2.4 metres/s, unaffected by sim multiplier
const HALF: Vector2 = Vector2.ONE
const BUILDINGS: Array[Dictionary] = [
	{"definition":0,"center":Vector2(-3.2,-2.0),"footprint":Rect2i(8,8,16,14)},
	{"definition":1,"center":Vector2(4.0,-3.8),"footprint":Rect2i(30,6,8,9)}
]
var state: WorldState
var clock: SimClock = SimClock.new()
var growth: GrowthSim
var spread: SpreadSim
var play: PlayState
var sim_tuning: SimTuning = SimTuning.new()
var play_tuning: PlayTuning = PlayTuning.new()
var position: Vector2
var paused: bool = false
var multiplier: float = 4.0
var last_result: String = "左クリックで種、右クリックで水"
var action_count: int = 0

func _init() -> void:
	var defs: Array[TerrainDef] = []
	for key: String in ["wasteland","safe","shore","water","building","shallows"]:
		defs.append(load("res://data/terrain/"+key+".tres"))
	var pavement: TerrainDef = defs[0].duplicate()
	pavement.id = 6
	pavement.key = &"lab_pavement"
	defs.append(pavement)
	state = WorldState.new(WIDTH,HEIGHT,defs,81026)
	for y: int in HEIGHT:
		for x: int in WIDTH:
			var index: int = state.index_of(x,y)
			state.terrain[index] = 6 if y>=21 and y<=26 or x>=18 and x<=21 else 0
			if x==0 or y==0 or x==WIDTH-1 or y==HEIGHT-1:
				state.terrain[index] = 4
			if x>=4 and x<=10 and y>=27 and y<=34:
				state.terrain[index] = 2
			if x>=5 and x<=9 and y>=28 and y<=33:
				state.terrain[index] = 3
			if x>=19 and x<=22 and y>=31 and y<=33:
				state.terrain[index] = 1
	for item: Dictionary in BUILDINGS:
		var rect: Rect2i = item["footprint"]
		for y: int in range(rect.position.y,rect.end.y):
			for x: int in range(rect.position.x,rect.end.x):
				state.terrain[state.index_of(x,y)] = 4
	state.apply_terrain_defs()
	position = to_logic(Vector2(0.4,3.6))
	# Fresh local resources only. Existing growth thresholds/periods remain intact.
	clock.configure(sim_tuning)
	growth = GrowthSim.new(state,sim_tuning)
	spread = SpreadSim.new(state,sim_tuning)
	clock.growth_ticked.connect(func(_tick: int) -> void: growth.tick())
	clock.spread_ticked.connect(func(_tick: int) -> void: spread.tick())
	play_tuning.seed_scatter_radius_px = 4.4
	play_tuning.water_splash_radius_px = 7.0
	play_tuning.projectile_range_px = 30.0
	play_tuning.walk_half_width_px = HALF.x
	play_tuning.walk_half_height_px = HALF.y
	# Production/pickups are out of scope; preserve real finite spending/refill.
	play_tuning.plant_fruit_rate_per_tile_second = 0.0
	play = PlayState.new(state,play_tuning,sim_tuning,TILE_PX,[])

static func to_logic(point: Vector2) -> Vector2:
	return (point-ORIGIN)*(TILE_PX/CELL)

static func to_ground(point: Vector2) -> Vector2:
	return ORIGIN+point*(CELL/TILE_PX)

static func cell_center(index: int) -> Vector2:
	return ORIGIN+Vector2(index%WIDTH+0.5,index/WIDTH+0.5)*CELL

func walk(screen_direction: Vector2, delta: float) -> Vector2:
	var old: Vector2 = position
	# Camera's horizontal screen-right=(+x,-z), screen-down=(+x,+z).
	var direction: Vector2 = screen_direction.limit_length(1)
	var ground_direction: Vector2 = Vector2(direction.x+direction.y,-direction.x+direction.y)/sqrt(2.0)
	position = Walker.move(state,TILE_PX,position,ground_direction*SPEED*delta,HALF)
	return position-old

func advance_game(seconds: float) -> void:
	if paused:
		return
	var remaining: float = maxf(seconds,0)
	while remaining>0.000001:
		var step: float = minf(remaining,0.25)
		clock.advance(step)
		play.advance(step,position)
		remaining -= step

func advance(real_delta: float) -> void:
	advance_game(minf(real_delta,0.1)*multiplier)

func visible_path(target: Vector2) -> bool:
	var distance: float = target.distance_to(position)
	for n: int in range(1,ceili(distance/0.5)+1):
		var sample_: Vector2 = position.lerp(target,minf(float(n)*0.5/maxf(distance,0.001),1))
		if not state.is_walkable(floori(sample_.x/TILE_PX),floori(sample_.y/TILE_PX)):
			return false
	return true

func scatter(ground: Vector2, water: bool) -> bool:
	var point: Vector2 = to_logic(ground)
	if position.distance_to(point)>play_tuning.projectile_range_px:
		last_result = "射程外（3m以内）"
		return false
	var cell: Vector2i = Vector2i(floori(point.x/TILE_PX),floori(point.y/TILE_PX))
	if not state.in_bounds(cell.x,cell.y) or not state.is_walkable(cell.x,cell.y) or state.target[state.index_of(cell.x,cell.y)]==0 or not visible_path(point):
		last_result = "建物・水・遮蔽物には散布できません"
		return false
	if water:
		if not play.spend_water():
			last_result = "水不足：水辺か補給を利用"
			return false
		var changed: int = play.land_water(point)
		last_result = "水 +%dセル（成長促進）" % changed
	else:
		if not play.spend_seed():
			last_result = "種不足：補給を利用"
			return false
		var changed: PackedInt32Array = play.land_seed(point)
		last_result = "種 → %dセル" % changed.size()
	action_count += 1
	return true

func refill() -> void:
	play.add_seeds(play_tuning.seed_max)
	play.add_water(play_tuning.water_max)
	last_result = "試作用補給（種・水を上限まで）"

func snapshot() -> Dictionary:
	return {"size":[WIDTH,HEIGHT],"cell_metres":CELL,"position_logic":[position.x,position.y],"seeds":play.seeds,"water":play.water,"elapsed_game":clock.elapsed,"green":state.greened_count,"targets":state.target_count,"mature":state.mature_count,"natural_total":spread.total_planted,"stages":Array(state.stage),"growth":Array(state.growth),"terrain":Array(state.terrain),"moisture":Array(state.moisture)}

func close() -> void:
	# Break RefCounted observer cycles owned by this short-lived lab session.
	state.tile_listener = Callable()
	for connection: Dictionary in clock.growth_ticked.get_connections():
		clock.growth_ticked.disconnect(connection["callable"])
	for connection: Dictionary in clock.spread_ticked.get_connections():
		clock.spread_ticked.disconnect(connection["callable"])
