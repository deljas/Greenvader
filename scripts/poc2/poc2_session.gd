extends RefCounted
## PoC2 owns all gameplay mutations and one clock. Rendering is a read-only client.
const Config: GDScript = preload("res://scripts/poc/poc_config.gd")
const Coords: GDScript = preload("res://scripts/poc/poc_coords.gd")
const CameraGeometry: GDScript = preload("res://scripts/poc2/view/camera_geometry.gd")
const PlacementScript: GDScript = preload("res://scripts/poc/assets/placement.gd")
const Day: GDScript = preload("res://scripts/poc/environment/poc_day.gd")
const Walls: GDScript = preload("res://scripts/poc/environment/wall_growth.gd")
const Navigation: GDScript = preload("res://scripts/poc2/simulation/navigation.gd")
const Combat: GDScript = preload("res://scripts/poc2/simulation/combat.gd")
const Plants: GDScript = preload("res://scripts/poc2/simulation/plants.gd")
const Persistence: GDScript = preload("res://scripts/poc2/simulation/persistence.gd")
const MAP_PATH: String = "res://data/poc2/maps/town_02.json"
const CATALOG: Dictionary = {
 "clover":{"cost":10,"rate":2.0,"size":[1,1],"footprint":[1,1],"maturity":20.0,"hp":30.0,"role":"crop"},
 "carrot":{"cost":15,"rate":1.0,"size":[1,1],"footprint":[1,1],"maturity":15.0,"hp":30.0,"role":"crop"},
 "wheat":{"cost":40,"rate":12.0,"size":[2,2],"footprint":[2,2],"maturity":45.0,"hp":50.0,"role":"crop"},
 "rafflesia":{"cost":40,"rate":2.0,"size":[2,2],"footprint":[2,2],"maturity":30.0,"hp":60.0,"role":"crop"},
 "watermelon":{"cost":120,"rate":30.0,"size":[3,4],"footprint":[3,4],"maturity":90.0,"hp":80.0,"role":"crop"},
 "army":{"cost":25,"rate":0.0,"size":[1,1],"footprint":[1,1],"maturity":0.0,"hp":80.0,"role":"helper"},
 "gatlinger":{"cost":30,"rate":0.0,"size":[1,1],"footprint":[1,1],"maturity":0.0,"hp":50.0,"role":"helper"},
 "sprinkler":{"cost":20,"rate":0.0,"size":[1,1],"footprint":[1,1],"maturity":0.0,"hp":50.0,"role":"helper"}}
var state: WorldState
var placement: RefCounted
var base_terrain: PackedByteArray
var env_tuning: Dictionary = {}
var weather: RefCounted = null
var wall_growth: RefCounted
var clock: SimClock = SimClock.new()
var sim_tuning: SimTuning = SimTuning.new()
var growth: GrowthSim
var spread: SpreadSim
var far: FarSeedSim
var nav: RefCounted
var combat_system: RefCounted
var plant_system: RefCounted
var position: Vector2
var aim: Vector2 = Vector2.ZERO
var has_aim: bool = false
var seeds: int = 60
var hp: float = 100.0
var max_hp: float = 100.0
var water: float = 100.0
var max_water: float = 100.0
var plants: Array[Dictionary] = []
var helpers: Array[Dictionary] = []
var enemies: Array[Dictionary] = []
var nests: Array[Dictionary] = []
var fossils: Array[Dictionary] = []
var shots: Array[Dictionary] = []
var unlocked: Dictionary = {"clover":true}
var favorites: Array[String] = ["clover","","","",""]
const SOW_WIDTHS: Array[int] = [1,3,5,7]
var sow_width: int = 1
var known: PackedByteArray = PackedByteArray()
var visible: PackedByteArray = PackedByteArray()
var skills: Array[String] = ["tackle","bazooka"]
var last_message: String = ""
var message_serial: int = 0
var multiplier: float = 1.0
var next_id: int = 1
var income_fraction: float = 0.0
var last_damage: float = -100.0
var respawn_at: float = -1.0
var shot_ready: float = 0.0
var skill_ready: Array[float] = [0.0,0.0]
var reveal_at: float = 0.0
var zone_check_at: float = 0.0
var map_data: Dictionary = {}
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var paused: bool:
 get: return clock.paused
 set(value): clock.paused = value

func _init(initialize: bool = true) -> void:
 if initialize:
  _setup()

func _setup() -> void:
 rng.seed = 20261021
 map_data = JSON.parse_string(FileAccess.get_file_as_string(MAP_PATH))
 var defs: Array[TerrainDef] = []
 for key: String in ["wasteland","safe","shore","water","building","shallows","paved"]:
  defs.append(load(("res://data/poc/terrain/" if key == "paved" else "res://data/terrain/") + key + ".tres") as TerrainDef)
 state = WorldState.new(224,224,defs,20261021)
 var keys: Array[String] = ["wasteland","safe","shore","water","building","shallows","paved"]
 for paint: Dictionary in map_data.paint:
  var r: Array = paint.rect
  for y: int in range(int(r[1]),int(r[1])+int(r[3])):
   for x: int in range(int(r[0]),int(r[0])+int(r[2])):
    state.terrain[state.index_of(x,y)] = keys.find(paint.terrain)
 base_terrain = state.terrain.duplicate()
 placement = PlacementScript.new()
 placement.load_map(MAP_PATH)
 for p: Array in map_data.open_cells:
  placement.reach_seeds.append(Vector2i(p[0],p[1]))
 placement.attach(state,base_terrain)
 # The start patch is deliberately clear of placed objects: exactly 250 initial green cells.
 var zone_ids: PackedByteArray = PackedByteArray()
 zone_ids.resize(state.tile_count())
 zone_ids.fill(1)
 for y: int in range(183,193):
  for x: int in range(180,205):
   zone_ids[state.index_of(x,y)] = 0
 state.set_zones(zone_ids,PackedByteArray([2,0]))
 position = Coords.cell_center_logic(Vector2i(191,188))
 env_tuning = Day.load_tuning()
 _build_systems()
 for row: Dictionary in map_data.nests:
  combat_system.add_nest(row)
 for row: Dictionary in map_data.fossils:
  fossils.append({"id":allocate_id(),"kind":"fossil","pos":Coords.cell_center_logic(Vector2i(row.cell[0],row.cell[1])),"unlock":row.unlock,"found":false,"discovered":false,"nest_id":-1})
 known.resize(state.tile_count())
 visible.resize(state.tile_count())
 reveal()

func _build_systems(sync_spread: bool = true) -> void:
 sim_tuning.max_advance_seconds = 0.25
 sim_tuning.mature_growth = 60000
 sim_tuning.sprout1_growth = 15000
 sim_tuning.sprout2_growth = 35000
 clock.configure(sim_tuning)
 growth = GrowthSim.new(state,sim_tuning)
 spread = SpreadSim.new(state,sim_tuning,sync_spread)
 far = FarSeedSim.new(state,sim_tuning)
 nav = Navigation.new()
 nav.setup(state)
 combat_system = Combat.new(self)
 plant_system = Plants.new(self)
 wall_growth = Walls.new()
 wall_growth.setup(state,placement,env_tuning.get("wall_growth",{}),sim_tuning)
 clock.growth_ticked.connect(_growth_tick)
 clock.spread_ticked.connect(_spread_tick)

func _growth_tick(_tick: int) -> void:
 growth.tick()
 wall_growth.on_growth_tick()

func _spread_tick(_tick: int) -> void:
 spread.tick()
 far.tick()

func allocate_id() -> int:
 var result: int = next_id
 next_id += 1
 return result

func result(ok: bool, reason: String = "", extra: Dictionary = {}) -> Dictionary:
 var out: Dictionary = {"ok":ok,"reason":reason}
 out.merge(extra)
 if not reason.is_empty():
  last_message = reason
  message_serial += 1
 return out

func walk(screen_dir: Vector2, dt: float) -> Vector2:
 if paused or hp <= 0.0 or dt <= 0.0:
  return Vector2.ZERO
 var old: Vector2 = position
 position = Walker.move(state,4,position,Coords.screen_dir_to_ground(screen_dir)*48.0*minf(dt,0.25),Vector2(2.0,2.0))
 return position-old

func advance(real_delta: float) -> void:
 advance_game(minf(maxf(real_delta,0.0),0.25)*multiplier)

func advance_game(seconds: float) -> void:
 if paused or not is_finite(seconds) or seconds <= 0.0:
  return
 var left: float = seconds
 while left > 0.000001:
  var dt: float = minf(left,0.25)
  clock.advance(dt)
  plant_system.advance(dt)
  combat_system.advance(dt)
  plant_system.cleanup_defeated()
  income_fraction += (land_rate()+crop_rate())*dt/60.0
  var earned: int = floori(income_fraction+0.0000001)
  seeds += earned
  income_fraction = maxf(0.0,income_fraction-earned)
  if hp > 0.0 and clock.elapsed-last_damage >= 8.0 and not combat_system.player_in_combat():
   hp = minf(max_hp,hp+dt*(3.0 if plant_system.carrot_near(position) else 1.0))
  if hp <= 0.0 and clock.elapsed >= respawn_at:
   position = Coords.cell_center_logic(Vector2i(191,188))
   hp = max_hp
   respawn_at = -1.0
  if clock.elapsed >= reveal_at:
   reveal()
   reveal_at = clock.elapsed+0.5
  if clock.elapsed >= zone_check_at:
   _check_zone()
   zone_check_at = clock.elapsed+1.0
  left -= dt
 # Record every state that can be presented, even between periodic terrain reveals.
 _remember_discoveries()

func _check_zone() -> void:
 if nests.is_empty() and enemies.is_empty() and state.zone_state[1] < 2:
  state.set_zone_state(1,WorldState.ZONE_STABLE)
  # FarSeedSim was created before the transition, so it sweeps the newly stable zone.
  nav.setup(state)
 for z: int in state.zone_count:
  if state.zone_state[z] >= 2 and state.zone_fully_greened(z):
   state.set_zone_state(z,WorldState.ZONE_COMPLETE)
 state.cleared = state.all_zones_complete()

func reveal() -> void:
 visible.fill(0)
 var camera_inverse: Transform3D = CameraGeometry.transform_for(position).affine_inverse()
 # Terrain history remains persistent; current detection also covers green land.
 for i: int in state.tile_count():
  var cell: Vector2i = Vector2i(i % state.width,i / state.width)
  if state.stage[i] >= WorldState.GREENED_MIN_STAGE or CameraGeometry.contains_ground(Coords.cell_center_logic(cell),camera_inverse):
   visible[i] = 1
   known[i] = 1
 for h: Dictionary in helpers:
  if float(h.get("hp",1.0)) <= 0.0: continue
  for i: int in Landing.tiles_in_radius(state,4,h.pos,72.0):
   visible[i] = 1
   known[i] = 1
 _remember_discoveries()
 for fossil: Dictionary in fossils:
  if not fossil.found and int(fossil.nest_id) < 0 and position.distance_to(fossil.pos) <= 12.0:
   unlock_fossil(fossil)

func _remember_discoveries() -> void:
 for nest: Dictionary in nests:
  if not bool(nest.mother) and float(nest.hp) > 0.0 and detected(nest.pos):
   nest.discovered = true
 for fossil: Dictionary in fossils:
  if not fossil.found and int(fossil.nest_id) < 0 and detected(fossil.pos):
   fossil.discovered = true

func detected(logic: Vector2) -> bool:
 var cell: Vector2i = Coords.logic_to_cell(logic)
 if not state.in_bounds(cell.x,cell.y): return false
 if state.stage[state.index_of(cell.x,cell.y)] >= WorldState.GREENED_MIN_STAGE: return true
 if CameraGeometry.contains_ground(logic,CameraGeometry.transform_for(position).affine_inverse()): return true
 for helper: Dictionary in helpers:
  if float(helper.get("hp",1.0)) > 0.0 and helper.pos.distance_squared_to(logic) <= 72.0*72.0: return true
 return false

func unlock_fossil(fossil: Dictionary) -> void:
 fossil.found = true
 unlocked[String(fossil.unlock)] = true
 result(true,"化石を発見: "+String(fossil.unlock))

func land_rate() -> float:
 return float(state.greened_count)*0.02

func crop_rate() -> float:
 var value: float = 0.0
 for p: Dictionary in plants:
  if p.mature:
   value += float(CATALOG[p.kind].rate)
 return value

func current_cost(kind: String) -> int:
 # All placement UI uses this entry point; crop price scaling is a later feature.
 return int(CATALOG[kind].cost) if CATALOG.has(kind) else 0

func adjust_sow_width(direction: int) -> int:
 var index: int = SOW_WIDTHS.find(sow_width)
 sow_width = SOW_WIDTHS[clampi(index+signi(direction),0,SOW_WIDTHS.size()-1)]
 return sow_width

func plant_stats(kind: String) -> Dictionary:
 var count: int = 0
 var rate: float = 0.0
 if not CATALOG.has(kind): return {"count":0,"rate_per_second":0.0}
 var rows: Array[Dictionary] = helpers if CATALOG[kind].role=="helper" else plants
 for item: Dictionary in rows:
  if item.kind!=kind or float(item.hp)<=0.0: continue
  count += 1
  if CATALOG[kind].role=="crop" and bool(item.mature): rate += float(CATALOG[kind].rate)/60.0
 return {"count":count,"rate_per_second":rate}

func set_favorite(index: int, kind: String) -> Dictionary:
 if index<0 or index>=5: return result(false,"invalid_slot")
 if not kind.is_empty() and (not CATALOG.has(kind) or not bool(unlocked.get(kind,false))): return result(false,"locked")
 favorites[index] = kind
 return result(true)

func set_aim(logic: Vector2) -> void:
 if logic.is_finite():
  aim = logic
  has_aim = true

func clear_aim() -> void:
 has_aim = false

func fire() -> Dictionary:
 return combat_system.fire(false)

func sow_preview() -> Dictionary:
 return combat_system.sow_preview()

func skill(slot: int) -> Dictionary:
 if slot < 0 or slot >= skills.size():
  return result(false,"invalid_slot")
 return combat_system.skill(slot)

func water_at(logic: Vector2) -> Dictionary:
 return plant_system.water_at(logic)

func can_place(kind: String,cell: Vector2i) -> Dictionary:
 return plant_system.can_place(kind,cell)

func place_plant(kind: String,cell: Vector2i) -> Dictionary:
 return plant_system.place(kind,cell,0,false)

func place_helper(kind: String,cell: Vector2i,ammo: int = 0) -> Dictionary:
 return plant_system.place(kind,cell,ammo,true)

func move_helper(id: int,destination: Vector2) -> Dictionary:
 return plant_system.move_helper(id,destination)

func supply_helper(id: int,amount: int) -> Dictionary:
 return plant_system.supply(id,amount)

func remove_plant(id: int) -> Dictionary:
 return plant_system.remove(id,false)

func remove_helper(id: int) -> Dictionary:
 return plant_system.remove(id,true)

func removal_refund(id: int,helper: bool) -> int:
 var rows: Array[Dictionary] = helpers if helper else plants
 for p: Dictionary in rows:
  if int(p.id) == id:
   return floori(float(p.cost)/5.0)+(int(p.ammo) if helper else 0)
 return 0

func is_walkable_logic(logic: Vector2) -> bool:
 var c: Vector2i = Coords.logic_to_cell(logic)
 return state.is_walkable(c.x,c.y)

func greening_percent() -> float:
 return 100.0*float(state.greened_count)/maxi(state.target_count,1)

func day_hour() -> float:
 return Day.hour_at(clock.elapsed,env_tuning)

func day_state() -> Dictionary:
 return Day.state(day_hour(),env_tuning)

func sunlight_factor(_index: int = 0) -> float:
 return 1.0

func weather_text() -> String:
 return "晴れ"

func snapshot() -> Dictionary:
 return {"seeds":seeds,"hp":hp,"water":water,"green_percent":greening_percent(),"land_rate":land_rate(),"crop_rate":crop_rate(),"elapsed_game":clock.elapsed,"stable":state.zone_state[1]>=2,"nests":nests.size(),"enemies":enemies.size()}

func to_dict() -> Dictionary:
 return Persistence.capture(self)

func restore(data: Dictionary) -> Dictionary:
 return Persistence.restore(self,data)

func close() -> void:
 if combat_system != null: combat_system.s = null
 if plant_system != null: plant_system.s = null
 state.tile_listener = Callable()
 for c: Dictionary in clock.growth_ticked.get_connections():
  clock.growth_ticked.disconnect(c.callable)
 for c: Dictionary in clock.spread_ticked.get_connections():
  clock.spread_ticked.disconnect(c.callable)
