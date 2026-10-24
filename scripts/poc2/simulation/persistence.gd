extends RefCounted
## JSON-safe complete snapshots. Validate on a disposable candidate, adopt only after every check succeeds.
const SCALARS: Array[String] = ["position","aim","has_aim","seeds","hp","max_hp","water","max_water","next_id","income_fraction","last_damage","respawn_at","shot_ready","skill_ready","reveal_at","zone_check_at","skills","unlocked","favorites","sow_width"]
const ROWS: Array[String] = ["plants","helpers","enemies","nests","fossils","shots"]

static func encode(value: Variant) -> Variant:
 if value is Vector2: return {"_v2":[value.x,value.y]}
 if value is Vector2i: return {"_v2i":[value.x,value.y]}
 if value is Dictionary:
  var out: Dictionary={}
  for key: Variant in value:
   # Navigation caches are derived from terrain and orders, and rebuilt after restore.
   if String(key) in ["route","route_index","route_at","goal"]: continue
   out[String(key)]=encode(value[key])
  return out
 if value is Array:
  var out: Array=[]
  for item: Variant in value: out.append(encode(item))
  return out
 return value

static func decode(value: Variant) -> Variant:
 if value is Dictionary:
  if value.has("_v2"): return Vector2(value._v2[0],value._v2[1])
  if value.has("_v2i"): return Vector2i(value._v2i[0],value._v2i[1])
  var out: Dictionary={}
  for key: String in value: out[key]=decode(value[key])
  return out
 if value is Array:
  var out: Array=[]
  for item: Variant in value: out.append(decode(item))
  return out
 return value

static func capture(s: RefCounted) -> Dictionary:
 var data: Dictionary={"format":"greenvader-poc3","version":3,"map":s.MAP_PATH,"world":s.state.to_dict(),"clock":s.clock.to_dict(),"growth":s.growth.to_dict(),"spread":s.spread.to_dict(),"far":s.far.to_dict(),"walls":s.wall_growth.to_dict(),"rng_seed":str(s.rng.seed),"rng_state":str(s.rng.state),"known":Marshalls.raw_to_base64(s.known),"visible":Marshalls.raw_to_base64(s.visible),"values":{},"entities":{}}
 for key: String in SCALARS: data.values[key]=encode(s.get(key))
 for key: String in ROWS: data.entities[key]=encode(s.get(key))
 return data

static func _safe(value: Variant,depth: int = 0) -> bool:
 if depth>16: return false
 if value is float: return is_finite(value)
 if value is String: return value.length()<2000000
 if value is Dictionary:
  if value.size()>60000: return false
  for key: Variant in value:
   if not key is String or not _safe(value[key],depth+1): return false
  for vector_key: String in ["_v2","_v2i"]:
   if value.has(vector_key):
    var a: Variant=value[vector_key]
    if not a is Array or a.size()!=2: return false
    for number: Variant in a:
     if not (number is int or number is float): return false
  return true
 if value is Array:
  if value.size()>60000: return false
  for item: Variant in value:
   if not _safe(item,depth+1): return false
  return true
 return value is int or value is bool or value==null

static func _shape(data: Variant,template: Variant) -> bool:
 if template is Dictionary:
  if not data is Dictionary: return false
  for key: String in template:
   if not data.has(key) or not _shape(data[key],template[key]): return false
  return true
 if template is Array:
  if not data is Array: return false
  if not template.is_empty():
   for item: Variant in data:
    if not _shape(item,template[0]): return false
  return true
 if template is int or template is float: return data is int or data is float
 return typeof(data)==typeof(template)

static func restore(s: RefCounted,data: Dictionary) -> Dictionary:
 if not _safe(data) or data.get("format","")!="greenvader-poc3" or data.get("version",0)!=3 or data.get("map","")!=s.MAP_PATH:
  return s.result(false,"invalid_save")
 var baseline: Dictionary=capture(s)
 # Snapshot contents may differ, but every top-level structural field must exist.
 for key: String in baseline:
  if not data.has(key): return s.result(false,"incomplete_save")
 for key: String in ["clock","rng_seed","rng_state","known","visible"]:
  if not _shape(data[key],baseline[key]): return s.result(false,"invalid_header")
 var world_template: Dictionary=s.state.to_dict()
 world_template.occupancy_owners={}
 if not data.world is Dictionary or not _shape(data.world,world_template): return s.result(false,"invalid_world")
 if data.world.width!=224 or data.world.height!=224: return s.result(false,"invalid_size")
 for key: String in ["terrain","plant_id","stage","growth","moisture","fertility","sprout_slot","occupant","natural","fruitless"]:
  var bytes: int=50176*(4 if key in ["growth","occupant"] else 1)
  if data.world[key].n!=bytes: return s.result(false,"invalid_packed_size")
 for owner: Variant in data.world.occupancy_owners:
  if not owner is String or not owner.is_valid_int(): return s.result(false,"invalid_owner")
  var r: Variant=data.world.occupancy_owners[owner]
  if not r is Array or r.size()!=4: return s.result(false,"invalid_rect")
  for value: Variant in r:
   if not (value is int or value is float): return s.result(false,"invalid_rect")
 var candidate: RefCounted=s.get_script().new(false)
 candidate.map_data=s.map_data
 candidate.base_terrain=s.base_terrain
 candidate.placement=s.placement
 candidate.env_tuning=s.env_tuning
 candidate.state=WorldState.from_dict(data.world,s.state.terrain_defs)
 if candidate.state==null: return s.result(false,"invalid_world")
 # Occupancy must agree exactly with its owner rectangles and stay in bounds.
 var occupied: PackedInt32Array=PackedInt32Array()
 occupied.resize(candidate.state.tile_count())
 for owner: int in candidate.state.occupancy_owners:
  var rect: Rect2i=candidate.state.occupancy_owners[owner]
  if owner<=0 or rect.size.x<=0 or rect.size.y<=0 or not Rect2i(0,0,224,224).encloses(rect): return s.result(false,"invalid_occupancy")
  for y: int in range(rect.position.y,rect.end.y):
   for x: int in range(rect.position.x,rect.end.x):
    var index: int=candidate.state.index_of(x,y)
    if occupied[index]!=0: return s.result(false,"invalid_occupancy")
    occupied[index]=owner
 if occupied!=candidate.state.occupant: return s.result(false,"invalid_occupancy")
 candidate.known=Marshalls.base64_to_raw(data.known)
 candidate.visible=Marshalls.base64_to_raw(data.visible)
 if candidate.known.size()!=50176 or candidate.visible.size()!=50176: return s.result(false,"invalid_exploration")
 for index: int in 50176:
  if candidate.known[index]>1 or candidate.visible[index]>1 or candidate.state.growth[index]<0 or candidate.state.moisture[index]>100: return s.result(false,"invalid_tile")
 if not data.values is Dictionary or not data.entities is Dictionary: return s.result(false,"invalid_values")
 for key: String in SCALARS:
  if not data.values.has(key) and key not in ["favorites","sow_width"]: return s.result(false,"incomplete_values")
 var vals: Dictionary=decode(data.values)
 if not vals.has("favorites"): vals.favorites=["clover","","","",""]
 if not vals.has("sow_width"): vals.sow_width=1
 if not (vals.sow_width is int or vals.sow_width is float) or float(vals.sow_width) not in [1.0,3.0,5.0,7.0]: return s.result(false,"invalid_sow_width")
 vals.sow_width=int(vals.sow_width)
 for key: String in ["position","aim"]:
  if not vals[key] is Vector2: return s.result(false,"invalid_position")
 if not Rect2(0,0,896,896).has_point(vals.position): return s.result(false,"invalid_position")
 for key: String in ["seeds","next_id","income_fraction","hp","max_hp","water","max_water","last_damage","respawn_at","shot_ready","reveal_at","zone_check_at"]:
  if not (vals[key] is int or vals[key] is float): return s.result(false,"invalid_number")
 if vals.seeds<0 or vals.seeds>1000000000 or vals.next_id<1 or vals.next_id>=90000 or vals.income_fraction<0.0 or vals.income_fraction>=1.000001 or vals.hp<0.0 or vals.hp>100.0 or vals.water<0.0 or vals.water>100.0 or vals.max_hp!=100.0 or vals.max_water!=100.0: return s.result(false,"invalid_resource")
 if not vals.skills is Array or vals.skills.size()!=2 or not vals.skill_ready is Array or vals.skill_ready.size()!=2: return s.result(false,"invalid_skills")
 for skill: Variant in vals.skills:
  if not skill is String or skill not in ["tackle","bazooka"]: return s.result(false,"invalid_skill")
 for cooldown: Variant in vals.skill_ready:
  if not (cooldown is int or cooldown is float): return s.result(false,"invalid_skill_time")
 if not vals.unlocked is Dictionary: return s.result(false,"invalid_unlock")
 for key: String in vals.unlocked:
  if not s.CATALOG.has(key) or not vals.unlocked[key] is bool: return s.result(false,"invalid_unlock")
 if not vals.unlocked.get("clover",false): return s.result(false,"invalid_unlock")
 if not vals.favorites is Array or vals.favorites.size()!=5: return s.result(false,"invalid_favorites")
 for kind: Variant in vals.favorites:
  if not kind is String: return s.result(false,"invalid_favorites")
  if not kind.is_empty() and (not s.CATALOG.has(kind) or not vals.unlocked.get(kind,false)): return s.result(false,"invalid_favorites")
 var ids: Dictionary={}
 for category: String in ROWS:
  if not data.entities.has(category) or not data.entities[category] is Array or data.entities[category].size()>1000: return s.result(false,"invalid_entities")
  var decoded: Array=decode(data.entities[category])
  var typed: Array[Dictionary]=[]
  for entity: Variant in decoded:
   if not entity is Dictionary or not _valid_entity(entity,category,candidate,s.CATALOG): return s.result(false,"invalid_entity_"+category)
   # Earlier PoC3 working saves have no discovery field; never infer a discovery.
   if category in ["nests","fossils"] and not entity.has("discovered"): entity.discovered=false
   # Working PoC3 saves used a temporary wet_until before permanent watering.
   if category=="plants" and not entity.has("watered"):
    entity.watered=float(entity.wet_until)>float(data.clock.elapsed)
   # Earlier PoC3 seed shots already paid one seed at launch and used width 1.
   if category=="shots" and entity.kind=="seed":
    entity.sow_width=int(entity.get("sow_width",1))
    entity.reserved_seed=int(entity.get("reserved_seed",1))
   if ids.has(entity.id) or entity.id>=vals.next_id: return s.result(false,"invalid_entity_id")
   ids[entity.id]=true
   typed.append(entity)
  candidate.set(category,typed)
 for key: String in SCALARS:
  if key=="skills": candidate.skills.assign(vals.skills)
  elif key=="skill_ready": candidate.skill_ready.assign(vals.skill_ready)
  elif key=="favorites": candidate.favorites.assign(vals.favorites)
  else: candidate.set(key,vals[key])
 if not data.clock is Dictionary or not _shape(data.clock,candidate.clock.to_dict()) or data.clock.elapsed<0.0: return s.result(false,"invalid_clock")
 candidate.clock.load_dict(data.clock)
 if absf(float(candidate.clock.growth_ticks)*0.5-candidate.clock.elapsed)>0.50001 or absf(float(candidate.clock.spread_ticks)-candidate.clock.elapsed)>1.00001: return s.result(false,"invalid_clock_ticks")
 candidate._build_systems(false)
 for field: String in ["growth","spread","far","walls"]:
  var object: RefCounted=candidate.wall_growth if field=="walls" else candidate.get(field)
  if not data[field] is Dictionary or not _shape(data[field],object.to_dict()) or not object.load_dict(data[field]):
   candidate.close()
   return s.result(false,"invalid_"+field)
 if not data.rng_seed is String or not data.rng_state is String or not data.rng_seed.is_valid_int() or not data.rng_state.is_valid_int():
  candidate.close(); return s.result(false,"invalid_rng")
 candidate.rng.seed=int(data.rng_seed); candidate.rng.state=int(data.rng_state)
 # Validation succeeded. Disconnect candidate-bound callbacks before transferring ownership.
 var keep_paused: bool=s.paused
 s.close()
 for c: Dictionary in candidate.clock.growth_ticked.get_connections(): candidate.clock.growth_ticked.disconnect(c.callable)
 for c: Dictionary in candidate.clock.spread_ticked.get_connections(): candidate.clock.spread_ticked.disconnect(c.callable)
 for key: String in SCALARS: s.set(key,candidate.get(key))
 for key: String in ROWS: s.set(key,candidate.get(key))
 for key: String in ["state","clock","growth","spread","far","wall_growth","known","visible","rng","nav"]: s.set(key,candidate.get(key))
 s.placement.state=s.state
 s.clock.growth_ticked.connect(s._growth_tick)
 s.clock.spread_ticked.connect(s._spread_tick)
 s.combat_system=s.Combat.new(s)
 s.plant_system=s.Plants.new(s)
 s.paused=keep_paused
 s.state.mark_all_dirty()
 candidate.combat_system=null; candidate.plant_system=null
 return s.result(true,"loaded")

static func _valid_entity(e: Dictionary,category: String,candidate: RefCounted,catalog: Dictionary) -> bool:
 for key: String in ["id","kind","pos"]:
  if not e.has(key): return false
 if not (e.id is int or e.id is float) or e.id<1 or not e.kind is String or not e.pos is Vector2 or not Rect2(0,0,896,896).has_point(e.pos): return false
 var required: Array[String]=[]
 match category:
  "plants": required=["hp","max_hp","cell","size","cost","owner","last_combat","age","maturity","mature","wet_until"]
  "helpers": required=["hp","max_hp","cell","size","cost","owner","last_combat","home","status","ammo","water","capacity","attack_at","work_at","search_at","target_pos","moving","bank","refill_until"]
  "enemies": required=["hp","max_hp","home","initial","strong","source","phase","phase_until","attack_at","stun_until","charge_dir","hit_charge"]
  "nests": required=["hp","max_hp","home","scale","mother","active","last_contact","spawn_due","attack_at","status"]
  "fossils": required=["unlock","found","nest_id"]
  "shots": required=["target","direction","remaining","speed","damage"]
 for key: String in required:
  if not e.has(key): return false
 for key: String in ["hp","max_hp","cost","owner","last_combat","age","maturity","wet_until","ammo","water","capacity","attack_at","work_at","search_at","refill_until","source","phase_until","stun_until","last_contact","spawn_due","nest_id","remaining","speed","damage"]:
  if e.has(key) and not (e[key] is int or e[key] is float): return false
 for key: String in ["home","target_pos","bank","charge_dir","target","direction"]:
  if e.has(key) and not e[key] is Vector2: return false
 for key: String in ["mature","watered","moving","initial","strong","hit_charge","mother","active","found","discovered"]:
  if e.has(key) and not e[key] is bool: return false
 if category in ["plants","helpers"]:
  if not catalog.has(e.kind) or not e.cell is Vector2i or not e.size is Vector2i or e.max_hp!=catalog[e.kind].hp: return false
  # A crop's cost is its historical payment, independent of today's live count.
  # JSON numbers may arrive as floats; require an exact positive int64 value.
  if e.cost is int:
   if e.cost<=0: return false
  elif not is_finite(e.cost) or e.cost<=0.0 or e.cost>=9223372036854775808.0 or floorf(e.cost)!=e.cost:
   return false
  if category=="helpers" and e.cost!=catalog[e.kind].cost: return false
  if e.size!=Vector2i(catalog[e.kind].size[0],catalog[e.kind].size[1]) or not Rect2i(0,0,224,224).encloses(Rect2i(e.cell,e.size)): return false
  if e.hp<=0.0 or e.hp>e.max_hp: return false
  if category=="plants" and (catalog[e.kind].role!="crop" or e.age<0.0 or e.maturity!=catalog[e.kind].maturity or not candidate.state.occupancy_owners.has(int(e.owner))): return false
  if category=="helpers" and (catalog[e.kind].role!="helper" or e.ammo<0 or e.ammo>100 or e.water<0 or e.water>100 or e.capacity!=100): return false
 if category=="helpers":
  if e.has("blocked_order") and not e.blocked_order is bool: return false
  if e.has("water_task") and (not e.water_task is String or e.water_task not in ["","resupplying","refilling","returning_water"]): return false
 if category=="enemies" and (e.kind not in ["boar","spider"] or e.hp<=0 or e.hp>e.max_hp): return false
 if category=="nests" and (e.scale not in ["small","medium","large"] or e.kind not in ["boar","spider","mother"] or e.hp<=0 or e.hp>e.max_hp): return false
 if category=="fossils" and (not catalog.has(e.unlock) or not e.unlock is String): return false
 if category=="shots" and (e.kind not in ["seed","bazooka"] or e.remaining<0 or e.remaining>100 or e.speed!=160.0): return false
 if category=="shots" and e.kind=="seed":
  var width: Variant=e.get("sow_width",1)
  var reserved: Variant=e.get("reserved_seed",1)
  if not (width is int or width is float) or float(width) not in [1.0,3.0,5.0,7.0]: return false
  if not (reserved is int or reserved is float) or reserved!=1: return false
 return true
