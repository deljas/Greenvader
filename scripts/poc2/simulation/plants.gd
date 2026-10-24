extends RefCounted
const Coords: GDScript = preload("res://scripts/poc/poc_coords.gd")
const Work: GDScript = preload("res://scripts/poc2/simulation/helper_work.gd")
const WaterArea: GDScript = preload("res://scripts/poc2/simulation/water_area.gd")
const WATER_RANGE: float = 50.0
## POC3-PLAYTEST-01 item 5: gatlinger volley. Was one seed every 3.0 s; now a fan of GATLING_VOLLEY seeds every GATLING_INTERVAL s.
const GATLING_INTERVAL: float = 1.2
const GATLING_VOLLEY: int = 4
const GATLING_SPREAD_CELLS: int = 5
var s: RefCounted
## Instance copies so a measurement can restore the pre-item-5 values (3.0 s, 1 seed).
var gatling_interval: float = GATLING_INTERVAL
var gatling_volley: int = GATLING_VOLLEY
func _init(session: RefCounted) -> void:
 s=session

func can_place(kind: String,cell: Vector2i) -> Dictionary:
 if not s.CATALOG.has(kind): return {"ok":false,"reason":"unknown_kind"}
 if not s.unlocked.get(kind,false): return {"ok":false,"reason":"locked"}
 var def: Dictionary=s.CATALOG[kind]
 var size: Vector2i=Vector2i(def.size[0],def.size[1])
 var rect: Rect2i=Rect2i(cell,size)
 for y: int in range(rect.position.y,rect.end.y):
  for x: int in range(rect.position.x,rect.end.x):
   if not s.state.in_bounds(x,y): return {"ok":false,"reason":"outside_map"}
   var index: int=s.state.index_of(x,y)
   if s.known.size()>index and s.known[index]==0: return {"ok":false,"reason":"unexplored"}
   if not s.state.is_walkable(x,y) or s.state.target[index]==0: return {"ok":false,"reason":"blocked_ground"}
   if s.state.occupant[index]!=0: return {"ok":false,"reason":"occupied"}
   if def.role=="crop" and s.state.stage[index]<WorldState.GREENED_MIN_STAGE: return {"ok":false,"reason":"requires_green"}
 for h: Dictionary in s.helpers:
  if rect.has_point(Coords.logic_to_cell(h.pos)): return {"ok":false,"reason":"occupied"}
 return {"ok":true,"reason":""}

func place(kind: String,cell: Vector2i,ammo: int,helper: bool) -> Dictionary:
 var check: Dictionary=can_place(kind,cell)
 if not check.ok: return s.result(false,check.reason)
 var def: Dictionary=s.CATALOG[kind]
 if (def.role=="helper")!=helper: return s.result(false,"wrong_category")
 if ammo<0 or ammo>100 or (kind!="gatlinger" and ammo!=0): return s.result(false,"invalid_ammo")
 var cost: int=s.current_cost(kind)
 # Compare by subtraction so even an unrepresentable-price sentinel plus ammo
 # cannot overflow into a free / negative purchase.
 if cost<=0 or cost>s.seeds-ammo: return s.result(false,"not_enough_seeds")
 var id: int=s.allocate_id()
 var size: Vector2i=Vector2i(def.size[0],def.size[1])
 var owner: int=(100000 if helper else 1000)+id
 if not s.state.occupy(Rect2i(cell,size),owner): return s.result(false,"occupied")
 s.seeds-=cost+ammo
 var pos: Vector2=(Vector2(cell)+Vector2(size)*0.5)*4.0
 var p: Dictionary={"id":id,"kind":kind,"pos":pos,"hp":float(def.hp),"max_hp":float(def.hp),"cell":cell,"size":size,"cost":cost,"owner":owner,"last_combat":-100.0}
 if helper:
  var underlying: int=s.state.index_of(cell.x,cell.y)
  if s.state.stage[underlying]==WorldState.STAGE_EMPTY:
   s.state.set_stage(underlying,WorldState.STAGE_SEED)
  p.merge({"home":pos,"status":"working","ammo":ammo,"water":100.0 if kind=="sprinkler" else 0.0,"capacity":100,"attack_at":0.0,"work_at":0.0,"search_at":0.0,"target_pos":pos,"route_at":-1.0,"moving":false,"blocked_order":false,"water_task":"","bank":Vector2(-1,-1),"refill_until":-1.0})
  p.merge({"job_kind":"","job_id":-1,"target_id":-1,"idle_since":-1.0,"sleeping":false,"action_until":-1.0,"action_kind":""})
  s.helpers.append(p)
 else:
  p.merge({"age":0.0,"maturity":float(def.maturity),"mature":false,"wet_until":0.0,"watered":false})
  s.plants.append(p)
 return s.result(true,"",{"id":id})

func supply(id: int,amount: int) -> Dictionary:
 for h: Dictionary in s.helpers:
  if int(h.id)==id:
   if h.kind!="gatlinger" or amount<=0 or amount>100-int(h.ammo): return s.result(false,"invalid_amount")
   if s.seeds<amount: return s.result(false,"not_enough_seeds")
   s.seeds-=amount; h.ammo=int(h.ammo)+amount
   h.search_at=0.0
   return s.result(true)
 return s.result(false,"not_found")

func move_helper(id: int,dest: Vector2) -> Dictionary:
 if not dest.is_finite(): return s.result(false,"invalid_destination")
 var c: Vector2i=Coords.logic_to_cell(dest)
 if not s.state.in_bounds(c.x,c.y): return s.result(false,"outside_map")
 var index: int=s.state.index_of(c.x,c.y)
 # Unknown destinations are accepted without leaking hidden obstacle information.
 if s.known[index]==1 and not s.state.is_walkable(c.x,c.y): return s.result(false,"blocked_ground")
 for h: Dictionary in s.helpers:
  if int(h.id)==id:
   s.state.release(int(h.owner))
   h.home=Coords.cell_center_logic(c)
   h.approach=s.nav.closest_reachable(h.pos,h.home) if s.known[index]==0 else h.home
   h.moving=true
   h.blocked_order=false
   h.water_task=""
   h.job_kind=""; h.job_id=-1; h.target_id=-1; h.sleeping=false; h.idle_since=-1.0
   h.status="moving"
   h.route_at=-1.0
   h.search_at=0.0
   return s.result(true)
 return s.result(false,"not_found")

func remove(id: int,helper: bool) -> Dictionary:
 var rows: Array[Dictionary]=s.helpers if helper else s.plants
 for p: Dictionary in rows:
  if int(p.id)==id:
   var refund: int=s.removal_refund(id,helper)
   s.seeds+=refund
   s.state.release(int(p.owner))
   rows.erase(p)
   return s.result(true,"",{"refund":refund})
 return s.result(false,"not_found")

func carrot_near(pos: Vector2) -> bool:
 for p: Dictionary in s.plants:
  if p.kind=="carrot" and p.mature and p.pos.distance_to(pos)<=30.0:
   return true
 return false

## The aimed point is limited to the watering reach, exactly like the seed shot target.
func water_target(pos: Vector2) -> Vector2:
 return s.position+(pos-s.position).limit_length(WATER_RANGE)

## Read-only plan for the current range setting (shared with area sowing). Never spends water.
func water_preview(pos: Vector2) -> Dictionary:
 if s.hp<=0.0 or not pos.is_finite(): return {}
 var target: Vector2=water_target(pos)
 var plan: Dictionary=WaterArea.plan(s.state,s.plants,Coords.logic_to_cell(target),s.sow_width,int(floorf(maxf(s.water,0.0))))
 plan.target=target
 plan.blocked=s.placement.blocks_projectile(s.position,target)
 plan.no_effect=(plan.valid as Array).is_empty()
 if plan.blocked:
  plan.affordable=[]
  plan.unaffordable=[]
  plan.cost=0
 return plan

## Dry-run of water_at: the same checks in the same order, no mutation. Used before the
## animation starts so a useless or impossible watering never plays or spends anything.
func water_check(pos: Vector2) -> Dictionary:
 if s.paused or s.hp<=0.0 or not pos.is_finite(): return s.result(false,"paused_or_downed")
 if s.water<1.0: return s.result(false,"no_water")
 var plan: Dictionary=water_preview(pos)
 if plan.blocked: return s.result(false,"blocked")
 if plan.no_effect: return s.result(false,"no_effect")
 return s.result(true,"",{"cost":int(plan.cost)})

## Waters the effective cells of the area centred on the aimed cell. Water is spent per
## cell that actually changed (nearest to the centre first when short); nothing is spent
## and nothing happens when no cell in the area would change.
func water_at(pos: Vector2) -> Dictionary:
 if s.paused or s.hp<=0.0 or not pos.is_finite(): return s.result(false,"paused_or_downed")
 if s.water<1.0: return s.result(false,"no_water")
 var target: Vector2=water_target(pos)
 if s.placement.blocks_projectile(s.position,target): return s.result(false,"blocked")
 if not s.state.permanent_water:
  s.water-=1.0
  _wet(target,14.0,5.0)
  return s.result(true)
 var plan: Dictionary=WaterArea.plan(s.state,s.plants,Coords.logic_to_cell(target),s.sow_width,int(floorf(s.water)))
 if (plan.valid as Array).is_empty(): return s.result(false,"no_effect")
 var changed: int=_water_cells(plan.affordable)
 if changed<=0: return s.result(false,"no_effect")
 s.water-=float(changed)
 return s.result(true,"",{"cost":changed})

func _water_cells(cells: Array) -> int:
 var changed: int=0
 var dry_grass: bool=false
 for cell: Vector2i in cells:
  var index: int=s.state.index_of(cell.x,cell.y)
  if s.state.stage[index]>0 and s.state.stage[index]<4 and s.state.moisture[index]==0: dry_grass=true
 # A first grass watering settles split-sweep lag; the catch-up may mature a candidate,
 # so every cell is re-read below before it is changed or charged.
 if dry_grass: s.growth.catch_up()
 for cell: Vector2i in cells:
  var index: int=s.state.index_of(cell.x,cell.y)
  if s.state.target[index]==1 and s.state.stage[index]>0 and s.state.stage[index]<4:
   if s.state.moisture[index]==0 and s.state.set_moisture(index,100):
    s.state.mark_dirty(index)
    changed+=1
   continue
  for p: Dictionary in s.plants:
   if not p.mature and not p.get("watered",false) and Rect2i(Vector2i(p.cell),Vector2i(p.size)).has_point(cell):
    p.watered=true
    changed+=1
    break
 return changed

func _wet(pos: Vector2,radius: float,duration: float) -> int:
 var changed: int=0
 if s.state.permanent_water:
  var tiles: PackedInt32Array=Landing.tiles_in_radius(s.state,4,pos,radius)
  # Only a first grass watering needs to settle split-sweep lag. Repeated water,
  # bare / mature terrain and crops must not force a whole-active-set sweep.
  for index: int in tiles:
   if s.state.stage[index]>0 and s.state.stage[index]<4 and s.state.moisture[index]==0:
    s.growth.catch_up()
    break
  # Catch-up may have matured a candidate; recheck before applying water.
  for index: int in tiles:
   if s.state.stage[index]>0 and s.state.stage[index]<4 and s.state.moisture[index]==0:
    if s.state.set_moisture(index,100):
     s.state.mark_dirty(index)
     changed+=1
  for p: Dictionary in s.plants:
   if not p.mature and not p.get("watered",false) and p.pos.distance_to(pos)<=radius:
    p.watered=true
    changed+=1
  return changed
 Landing.splash_water(s.state,4,pos,radius,100,100)
 for p: Dictionary in s.plants:
  if not p.mature and p.pos.distance_to(pos)<=radius:
   p.wet_until=maxf(float(p.wet_until),s.clock.elapsed+duration)
 return changed

func cleanup_defeated() -> void:
 # Also called after combat, before this tick can be saved.
 for rows: Array[Dictionary] in [s.plants,s.helpers]:
  for p: Dictionary in rows.duplicate():
   if p.hp<=0.0:
    s.state.release(int(p.owner))
    rows.erase(p)

func advance(dt: float) -> void:
 cleanup_defeated()
 for p: Dictionary in s.plants.duplicate():
  if not p.mature:
   var speed: float=(1.0 if p.get("watered",false) else 0.5) if s.state.permanent_water else (2.0 if float(p.wet_until)>s.clock.elapsed else 1.0)
   p.age=float(p.age)+dt*speed
   p.mature=float(p.age)>=float(p.maturity)
 for h: Dictionary in s.helpers.duplicate():
  if s.clock.elapsed-float(h.last_combat)>=8.0:
   h.hp=minf(float(h.max_hp),float(h.hp)+dt)
  _helper(h,dt)
  var idle: Dictionary=Work.idle_state(h,s.clock.elapsed,not String(h.get("job_kind","")).is_empty())
  h.idle_since=idle.idle_since; h.sleeping=idle.sleeping
 # Player refills by standing at a water edge, without consuming the shared seed account.
 if s.water<s.max_water:
  var c: Vector2i=Coords.logic_to_cell(s.position)
  for d: Vector2i in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
   var n: Vector2i=c+d
   if s.state.in_bounds(n.x,n.y) and s.state.terrain[s.state.index_of(n.x,n.y)]==3:
    s.water=minf(s.max_water,s.water+20.0*dt)
    break

func _nearest_enemy(pos: Vector2,radius: float) -> Dictionary:
 var result: Dictionary={}
 var best: float=radius
 for e: Dictionary in s.enemies:
  var d: float=pos.distance_to(e.pos)
  if d<best:
   result=e; best=d
 return result

func _helper(h: Dictionary,dt: float) -> void:
 var pos: Vector2=h.pos
 if h.kind=="army":
  if h.get("blocked_order",h.status=="unreachable"):
   h.status="unreachable"
   return
  _army(h,dt)
  return
 var threats: Array[Dictionary]=s.enemies.duplicate()
 for nest: Dictionary in s.nests:
  if nest.mother: threats.append(nest)
 var danger: Dictionary=Work.danger(h,threats)
 if danger.is_empty() and h.get("water_task","")=="returning_water": danger=Work.danger({"pos":h.home,"status":"working"},threats)
 if not danger.is_empty():
  # Presentation status may change while the underlying order must survive.
  if h.kind=="sprinkler" and h.status in ["refilling","resupplying","returning_water"]:
   h.water_task=h.status
  if h.status=="unreachable": h.blocked_order=true
  h.status="fleeing"
  var retreat: Vector2=Work.retreat_goal(h,danger.pos,s.helpers,func(at: Vector2) -> bool: return _reachable(h.pos,at))
  var path: Array=s.nav.route(h.pos,retreat)
  # An obstacle detour must not begin by approaching the nearest threat.
  if path.size()>1 and Coords.cell_center_logic(path[1]).distance_to(danger.pos)>=h.pos.distance_to(danger.pos)-0.01:
   h.target_pos=retreat
   s.nav.move(h,retreat,24.0,dt,s.clock.elapsed)
  h.search_at=0.0
  return
 if h.get("blocked_order",h.status=="unreachable"):
  h.status="unreachable"
  return
 if h.moving:
  _move_home(h,dt)
  return
 if h.kind=="gatlinger":
  _gatlinger(h,dt)
 else:
  _sprinkler(h,dt)

func _move_home(h: Dictionary,dt: float) -> void:
 var c: Vector2i=Coords.logic_to_cell(h.home)
 var undiscovered: bool=s.known[s.state.index_of(c.x,c.y)]==0
 var goal: Vector2=h.get("approach",h.home) if undiscovered else h.home
 h.status="exploring" if undiscovered else "moving"
 if not undiscovered and not s.is_walkable_logic(h.home):
  h.status="unreachable"; h.moving=false; h.blocked_order=true
  return
 if s.nav.move(h,goal,30.0 if h.kind=="army" else 20.0,dt,s.clock.elapsed):
  if not undiscovered:
   h.moving=false; h.status="working"; h.search_at=0.0
 elif (h.get("route",[]) as Array).is_empty() and not undiscovered:
  h.status="unreachable"; h.moving=false; h.blocked_order=true

func _army(h: Dictionary,dt: float) -> void:
 if h.moving:
  _move_home(h,dt)
  return
 if h.status=="returning":
  _return_home(h,dt,"guarding")
  return
 var allies: Array[Dictionary]=s.plants.duplicate()
 allies.append_array(s.helpers)
 var target_id: int=Work.army_target(h,s.enemies,allies)
 var enemy: Dictionary={}
 for e: Dictionary in s.enemies:
  if int(e.id)==target_id: enemy=e; break
 if enemy.is_empty():
  _return_home(h,dt,"guarding")
  return
 var best: float=enemy.pos.distance_to(h.pos)
 h.target_id=enemy.id
 h.job_kind="enemy"; h.job_id=enemy.id; h.target_pos=enemy.pos
 h.status="fighting"
 h.last_combat=s.clock.elapsed
 if best<=10.0 and not s.placement.blocks_projectile(h.pos,enemy.pos):
  if s.clock.elapsed>=float(h.attack_at):
   s.combat_system.damage_enemy(enemy,8.0,0.12)
   h.attack_at=s.clock.elapsed+1.0
   h.action_kind="attack"; h.action_until=s.clock.elapsed+0.22
 else:
  var old: Vector2=h.pos
  s.nav.move(h,enemy.pos,30.0,dt,s.clock.elapsed)
  if h.pos.distance_to(h.home)>Work.CHASE_RADIUS:
   h.pos=old; _return_home(h,dt,"guarding")

func _reachable(from: Vector2,to: Vector2) -> bool:
 var a: Vector2i=Coords.logic_to_cell(from)
 var b: Vector2i=Coords.logic_to_cell(to)
 if not s.state.in_bounds(a.x,a.y) or not s.state.in_bounds(b.x,b.y): return false
 var component: int=s.nav.components[s.state.index_of(a.x,a.y)]
 return component>0 and s.nav.components[s.state.index_of(b.x,b.y)]==component

func _return_home(h: Dictionary,dt: float,arrived: String="idle") -> void:
 h.job_kind=""; h.job_id=-1
 if h.kind!="army":
  var threats: Array[Dictionary]=s.enemies.duplicate()
  for nest: Dictionary in s.nests:
   if nest.mother: threats.append(nest)
  var threat: Dictionary=Work.danger({"pos":h.home,"status":"working"},threats)
  if not threat.is_empty():
   h.status="fleeing"
   var retreat: Vector2=Work.retreat_goal(h,threat.pos,s.helpers,func(at: Vector2) -> bool: return _reachable(h.pos,at))
   var route: Array=s.nav.route(h.pos,retreat)
   if route.size()>1 and Coords.cell_center_logic(route[1]).distance_to(threat.pos)>=h.pos.distance_to(threat.pos)-0.01:
    h.target_pos=retreat; s.nav.move(h,retreat,24.0,dt,s.clock.elapsed)
   return
 h.target_pos=h.home
 if h.pos.distance_to(h.home)<=Work.HOME_EPSILON or s.nav.move(h,h.home,30.0 if h.kind=="army" else 20.0,dt,s.clock.elapsed):
  h.status=arrived; h.target_id=-1
 else:
  h.status="returning" if _reachable(h.pos,h.home) else "unreachable"

func _job_target(h: Dictionary,growing: bool) -> Dictionary:
 var tiles: PackedInt32Array=Landing.tiles_in_radius(s.state,4,h.home,Work.SPRINKLER_WORK_RADIUS if growing else Work.WORK_RADIUS)
 var grass: Array[Dictionary]=[]
 var candidates: Array[Dictionary]=[]
 var frontier: Array[int]=[]
 var distances: Dictionary={}
 var local: Dictionary={}
 for index: int in tiles:
  local[index]=true
  if s.state.stage[index]>0: distances[index]=0; frontier.append(index)
  if growing and s.state.stage[index]>0 and s.state.stage[index]<4:
   grass.append({"tile":index,"pos":Coords.cell_center_logic(Vector2i(index%s.state.width,index/s.state.width)),"growing":true,"watered":s.state.moisture[index]>0})
 if growing:
  return Work.sprinkler_target(h,s.plants,grass,func(at: Vector2) -> bool: return _reachable(h.pos,at))
 var head: int=0
 while head<frontier.size():
  var index: int=frontier[head]; head+=1
  var cell: Vector2i=Vector2i(index%s.state.width,index/s.state.width)
  for d: Vector2i in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
   var next: Vector2i=cell+d
   if not s.state.in_bounds(next.x,next.y): continue
   var ni: int=s.state.index_of(next.x,next.y)
   if local.has(ni) and not distances.has(ni) and s.state.is_walkable(next.x,next.y):
    distances[ni]=int(distances[index])+1; frontier.append(ni)
 var reserved: PackedInt32Array=PackedInt32Array()
 for shot: Dictionary in s.shots:
  if shot.get("source_type","player")=="helper": reserved.append(int(shot.target_tile))
 for index: int in tiles:
  if not s.state.can_plant(index): continue
  var blocked: bool=false
  for helper: Dictionary in s.helpers:
   var cell: Vector2i=Coords.logic_to_cell(helper.pos)
   if s.state.in_bounds(cell.x,cell.y) and s.state.index_of(cell.x,cell.y)==index: blocked=true; break
  if blocked: continue
  candidates.append({"tile":index,"pos":Coords.cell_center_logic(Vector2i(index%s.state.width,index/s.state.width)),"plantable":true,"green_distance":float(distances.get(index,INF))})
 return Work.sow_target(h,candidates,reserved,func(at: Vector2) -> bool: return _reachable(h.pos,at))

func _work_target(h: Dictionary,growing: bool) -> Vector2:
 var target: Dictionary=_job_target(h,growing)
 return target.get("pos",Vector2(-1,-1))

func _gatlinger(h: Dictionary,dt: float) -> void:
 if int(h.ammo)<=0:
  _return_home(h,dt,"empty")
  return
 if s.clock.elapsed>=float(h.search_at):
  var job: Dictionary=_job_target(h,false)
  h.target_pos=job.get("pos",Vector2(-1,-1))
  h.job_kind="grass" if not job.is_empty() else ""; h.job_id=int(job.get("tile",-1))
  h.search_at=s.clock.elapsed+2.0
 if h.get("job_kind","")!="grass":
  _return_home(h,dt); return
 var target: Vector2=h.target_pos
 if target.x<0.0:
  _return_home(h,dt); return
 h.status="working"
 if h.pos.distance_to(target)>18.0:
  h.status="working"; s.nav.move(h,target,18.0,dt,s.clock.elapsed)
 elif s.clock.elapsed>=float(h.work_at):
  if not s.placement.blocks_projectile(h.pos,target):
   var c: Vector2i=Coords.logic_to_cell(target)
   if s.state.can_plant(s.state.index_of(c.x,c.y)):
    if s.combat_system.helper_seed(h,target):
     h.work_at=s.clock.elapsed+gatling_interval
     _gatling_fan(h,c)
     h.action_kind="sow"; h.action_until=s.clock.elapsed+0.22
     h.status="sowing"
  h.search_at=0.0

## Scatter the rest of a volley around the main target cell. Deterministic order (hash of helper id, time and cell).
func _gatling_fan(h: Dictionary,center: Vector2i) -> void:
 var order: Array[Dictionary]=[]
 var tick: int=int(s.clock.elapsed*10.0)
 for dy: int in range(-GATLING_SPREAD_CELLS,GATLING_SPREAD_CELLS+1):
  for dx: int in range(-GATLING_SPREAD_CELLS,GATLING_SPREAD_CELLS+1):
   if dx==0 and dy==0: continue
   var key: int=((dx+64)*73856093) ^ ((dy+64)*19349663) ^ (int(h.id)*83492791) ^ (tick*2654435761)
   order.append({"cell":center+Vector2i(dx,dy),"key":key&0x7fffffff})
 order.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return int(a.key)<int(b.key))
 var fired: int=1
 for item: Dictionary in order:
  if fired>=gatling_volley or int(h.ammo)<=0: break
  var cell: Vector2i=item.cell
  if not s.state.in_bounds(cell.x,cell.y): continue
  if s.combat_system.helper_seed(h,Coords.cell_center_logic(cell)): fired+=1

func _sprinkler(h: Dictionary,dt: float) -> void:
 # water_task is durable intent; status only describes the current visible action.
 # Infer the intent for first-version saves that predate this optional field.
 var task: String=String(h.get("water_task",""))
 if task.is_empty() and h.status in ["refilling","resupplying","returning_water"]:
  task=h.status
 if task.is_empty() and float(h.water)<=0.0001:
  task="resupplying"
 h.water_task=task
 if not task.is_empty():
  if task=="returning_water":
   h.status="returning_water"
   h.target_pos=h.home
   if s.nav.move(h,h.home,20.0,dt,s.clock.elapsed):
    h.water_task=""; h.status="working"; h.search_at=0.0
   return
  if task=="refilling" and h.pos.distance_to(h.bank)<=1.0:
   h.status="refilling"
   h.target_pos=h.bank
   h.water=minf(100.0,float(h.water)+20.0*dt)
   if float(h.water)>=100.0:
    h.water_task="returning_water"; h.status="returning_water"
   return
  # An interrupted refill may have fled away from its bank. Travel back before
  # resuming refill, preserving the partially filled store and original home.
  h.water_task="resupplying"
  if h.status=="no_water_route" and s.clock.elapsed<float(h.search_at): return
  if h.bank.x<0.0:
   h.search_at=s.clock.elapsed+5.0
   h.bank=s.nav.bank(h.pos)
   if h.bank.x<0.0:
    h.status="no_water_route"
    return
  h.status="resupplying"
  h.target_pos=h.bank
  if s.nav.move(h,h.bank,20.0,dt,s.clock.elapsed):
   h.water_task="refilling"; h.status="refilling"
  return
 if s.clock.elapsed>=float(h.search_at):
  var job: Dictionary=_job_target(h,true)
  h.target_pos=job.get("pos",Vector2(-1,-1))
  h.job_kind=String(job.get("kind","")); h.job_id=int(job.get("id",-1))
  h.search_at=s.clock.elapsed+2.0
 if h.get("job_kind","") not in ["crop","grass"]:
  _return_home(h,dt); return
 var target: Vector2=h.target_pos
 if target.x<0.0:
  _return_home(h,dt); return
 if h.pos.distance_to(target)>14.0:
  h.status="working"; s.nav.move(h,target,20.0,dt,s.clock.elapsed)
 else:
  h.status="watering"
  var changed: int=_wet(h.pos,20.0,1.0)
  if s.state.permanent_water:
   if changed>0:
    h.water=maxf(0.0,float(h.water)-1.0)
    h.action_kind="water"; h.action_until=s.clock.elapsed+0.3
   h.search_at=0.0
   h.target_pos=Vector2(-1,-1)
  else:
   h.water=maxf(0.0,float(h.water)-dt)
