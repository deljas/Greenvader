extends RefCounted
const Coords: GDScript = preload("res://scripts/poc/poc_coords.gd")
var s: RefCounted
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
 var cost: int=int(def.cost)
 if s.seeds<cost+ammo: return s.result(false,"not_enough_seeds")
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
  s.helpers.append(p)
 else:
  p.merge({"age":0.0,"maturity":float(def.maturity),"mature":false,"wet_until":0.0})
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

func water_at(pos: Vector2) -> Dictionary:
 if s.paused or s.hp<=0.0 or s.position.distance_to(pos)>50.0: return s.result(false,"out_of_range")
 if s.water<1.0: return s.result(false,"no_water")
 if s.placement.blocks_projectile(s.position,pos): return s.result(false,"blocked")
 s.water-=1.0
 _wet(pos,14.0,5.0)
 return s.result(true)

func _wet(pos: Vector2,radius: float,duration: float) -> void:
 Landing.splash_water(s.state,4,pos,radius,100,100)
 for p: Dictionary in s.plants:
  if not p.mature and p.pos.distance_to(pos)<=radius:
   p.wet_until=maxf(float(p.wet_until),s.clock.elapsed+duration)

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
   p.age=float(p.age)+dt*(2.0 if float(p.wet_until)>s.clock.elapsed else 1.0)
   p.mature=float(p.age)>=float(p.maturity)
 for h: Dictionary in s.helpers.duplicate():
  if s.clock.elapsed-float(h.last_combat)>=8.0:
   h.hp=minf(float(h.max_hp),float(h.hp)+dt)
  _helper(h,dt)
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
 var danger: Dictionary=_nearest_enemy(pos,35.0)
 if not danger.is_empty():
  # Presentation status may change while the underlying order must survive.
  if h.kind=="sprinkler" and h.status in ["refilling","resupplying","returning_water"]:
   h.water_task=h.status
  if h.status=="unreachable": h.blocked_order=true
  h.status="fleeing"
  var retreat: Vector2=pos+(pos-danger.pos).normalized()*30.0
  if s.is_walkable_logic(retreat):
   s.nav.move(h,retreat,24.0,dt,s.clock.elapsed)
  else:
   s.nav.move(h,h.home,24.0,dt,s.clock.elapsed)
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
 var enemy: Dictionary={}
 var best: float=INF
 for e: Dictionary in s.enemies:
  if int(e.id)==int(h.get("target_id",-1)) and e.pos.distance_to(h.home)<=60.0:
   enemy=e; best=e.pos.distance_to(h.pos)
   break
 for e: Dictionary in s.enemies:
  if enemy.is_empty() and e.pos.distance_to(h.home)<=40.0 and e.pos.distance_to(h.pos)<best:
   enemy=e; best=e.pos.distance_to(h.pos)
 if enemy.is_empty() or h.pos.distance_to(h.home)>60.0:
  h.status="returning" if h.pos.distance_to(h.home)>3.0 else "guarding"
  s.nav.move(h,h.home,30.0,dt,s.clock.elapsed)
  return
 h.target_id=enemy.id
 h.status="fighting"
 h.last_combat=s.clock.elapsed
 if best<=10.0 and not s.placement.blocks_projectile(h.pos,enemy.pos):
  if s.clock.elapsed>=float(h.attack_at):
   s.combat_system.damage_enemy(enemy,8.0,0.12)
   h.attack_at=s.clock.elapsed+1.0
 else:
  s.nav.move(h,enemy.pos,30.0,dt,s.clock.elapsed)

func _work_target(h: Dictionary,growing: bool) -> Vector2:
 var radius: float=40.0 if growing else 60.0
 var best: float=INF
 var answer: Vector2=Vector2(-1,-1)
 if growing:
  for p: Dictionary in s.plants:
   if not p.mature and p.pos.distance_to(h.home)<=radius and p.pos.distance_squared_to(h.pos)<best:
    var route: Array=s.nav.route(h.pos,p.pos)
    if not route.is_empty():
     best=p.pos.distance_squared_to(h.pos); answer=p.pos
 for index: int in Landing.tiles_in_radius(s.state,4,h.home,radius):
  var valid: bool=s.state.stage[index]>0 and s.state.stage[index]<4 if growing else s.state.can_plant(index)
  if not valid: continue
  var p: Vector2=Coords.cell_center_logic(Vector2i(index%s.state.width,index/s.state.width))
  var distance: float=h.pos.distance_squared_to(p)
  if distance<best:
   if not s.nav.route(h.pos,p).is_empty():
    best=distance; answer=p
 return answer

func _gatlinger(h: Dictionary,dt: float) -> void:
 if int(h.ammo)<=0:
  h.status="empty"
  return
 if s.clock.elapsed>=float(h.search_at):
  h.target_pos=_work_target(h,false)
  h.search_at=s.clock.elapsed+2.0
 var target: Vector2=h.target_pos
 if target.x<0.0:
  h.status="idle"; return
 if h.pos.distance_to(target)>18.0:
  h.status="working"; s.nav.move(h,target,18.0,dt,s.clock.elapsed)
 elif s.clock.elapsed>=float(h.work_at):
  if not s.placement.blocks_projectile(h.pos,target):
   var c: Vector2i=Coords.logic_to_cell(target)
   if s.state.can_plant(s.state.index_of(c.x,c.y)):
    s.state.set_stage(s.state.index_of(c.x,c.y),WorldState.STAGE_SEED)
    h.ammo=int(h.ammo)-1
    h.work_at=s.clock.elapsed+3.0
  h.search_at=0.0

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
   if s.nav.move(h,h.home,20.0,dt,s.clock.elapsed):
    h.water_task=""; h.status="working"; h.search_at=0.0
   return
  if task=="refilling" and h.pos.distance_to(h.bank)<=1.0:
   h.status="refilling"
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
  if s.nav.move(h,h.bank,20.0,dt,s.clock.elapsed):
   h.water_task="refilling"; h.status="refilling"
  return
 if s.clock.elapsed>=float(h.search_at):
  h.target_pos=_work_target(h,true)
  h.search_at=s.clock.elapsed+2.0
 var target: Vector2=h.target_pos
 if target.x<0.0:
  h.status="idle"; return
 if h.pos.distance_to(target)>14.0:
  h.status="working"; s.nav.move(h,target,20.0,dt,s.clock.elapsed)
 else:
  h.status="watering"
  _wet(h.pos,20.0,1.0)
  h.water=maxf(0.0,float(h.water)-dt)
