extends RefCounted
## Proximity-activated production and readable boar/spider combat.
const Coords: GDScript = preload("res://scripts/poc/poc_coords.gd")
var s: RefCounted
func _init(session: RefCounted) -> void:
 s = session

func add_nest(row: Dictionary) -> void:
 var scale: String = row.scale
 var maximum: float = {"small":40.0,"medium":100.0,"large":240.0}[scale]
 var pos: Vector2 = Coords.cell_center_logic(Vector2i(row.cell[0],row.cell[1]))
 pos = free_position(pos)
 var nest: Dictionary = {"id":s.allocate_id(),"kind":row.kind,"pos":pos,"home":pos,"hp":maximum,"max_hp":maximum,"scale":scale,"mother":row.kind=="mother","active":false,"last_contact":-100.0,"spawn_due":0.0,"attack_at":0.0,"status":"dormant","route_at":-1.0}
 s.nests.append(nest)
 var unlock: String = row.get("unlock","")
 if not unlock.is_empty():
  s.fossils.append({"id":s.allocate_id(),"kind":"fossil","pos":pos,"unlock":unlock,"found":false,"nest_id":nest.id})
 for i: int in (2 if scale=="small" else 3):
  spawn(nest,true,i==0 and scale!="small")

func free_position(pos: Vector2) -> Vector2:
 var cell: Vector2i = Coords.logic_to_cell(pos)
 for radius: int in 16:
  for y: int in range(cell.y-radius,cell.y+radius+1):
   for x: int in range(cell.x-radius,cell.x+radius+1):
    if s.state.in_bounds(x,y) and s.state.is_walkable(x,y) and s.state.zone_state[s.state.zone_at(s.state.index_of(x,y))] < 2:
     return Coords.cell_center_logic(Vector2i(x,y))
 return pos

func spawn(nest: Dictionary,initial: bool,strong: bool = false) -> void:
 var pos: Vector2 = free_position(nest.pos+Vector2(s.rng.randf_range(-10,10),s.rng.randf_range(-10,10)))
 var maximum: float = 40.0 if strong else 20.0
 var kind: String = "spider" if nest.kind in ["spider","mother"] else "boar"
 s.enemies.append({"id":s.allocate_id(),"kind":kind,"pos":pos,"home":nest.home,"hp":maximum,"max_hp":maximum,"initial":initial,"strong":strong,"source":nest.id,"phase":"idle","phase_until":0.0,"attack_at":0.0,"stun_until":0.0,"route_at":-1.0,"charge_dir":Vector2.ZERO,"hit_charge":false})

func player_in_combat() -> bool:
 for e: Dictionary in s.enemies:
  if e.pos.distance_to(s.position) < 35.0:
   return true
 return false

func fire(bazooka: bool) -> Dictionary:
 if s.paused or s.hp<=0.0:
  return s.result(false,"paused_or_downed")
 if not s.has_aim:
  return s.result(false,"aim_required")
 if not bazooka and s.clock.elapsed<s.shot_ready:
  return s.result(false,"cooldown")
 var cost: int = 3 if bazooka else 1
 if s.seeds<cost:
  return s.result(false,"not_enough_seeds")
 var direction: Vector2 = (s.aim-s.position).normalized()
 if direction==Vector2.ZERO:
  return s.result(false,"aim_required")
 var distance: float = minf(s.position.distance_to(s.aim),100.0 if bazooka else 80.0)
 s.seeds-=cost
 s.shot_ready=s.clock.elapsed+0.28
 s.shots.append({"id":s.allocate_id(),"kind":"bazooka" if bazooka else "seed","pos":s.position,"target":s.position+direction*distance,"direction":direction,"remaining":distance,"speed":160.0,"damage":25.0 if bazooka else 5.0})
 return s.result(true)

func skill(slot: int) -> Dictionary:
 if s.paused or s.hp<=0.0 or s.clock.elapsed<float(s.skill_ready[slot]):
  return s.result(false,"cooldown_or_paused")
 if s.skills[slot]=="bazooka":
  var out: Dictionary = fire(true)
  if out.ok:
   s.skill_ready[slot]=s.clock.elapsed+3.0
  return out
 if not s.has_aim:
  return s.result(false,"aim_required")
 var direction: Vector2=(s.aim-s.position).normalized()
 var old: Vector2=s.position
 s.position=Walker.move(s.state,4,s.position,direction*16.0,Vector2(2,2))
 for e: Dictionary in s.enemies.duplicate():
  if _distance_segment(e.pos,old,s.position)<9.0 and not s.placement.blocks_projectile(s.position,e.pos):
   damage_enemy(e,8.0,0.5)
 for n: Dictionary in s.nests.duplicate():
  if n.pos.distance_to(s.position)<11.0 and not s.placement.blocks_projectile(s.position,n.pos):
   damage_nest(n,8.0)
 s.skill_ready[slot]=s.clock.elapsed+1.2
 return s.result(true)

func _distance_segment(point: Vector2,a: Vector2,b: Vector2) -> float:
 return point.distance_to(Geometry2D.get_closest_point_to_segment(point,a,b))

func advance(dt: float) -> void:
 _shots(dt)
 for nest: Dictionary in s.nests:
  var contact: bool = nest.pos.distance_to(s.position)<=90.0
  if not contact:
   for idx: int in Landing.tiles_in_radius(s.state,4,nest.pos,65.0):
    if s.state.stage[idx]>=WorldState.GREENED_MIN_STAGE:
     contact=true
     break
  if contact:
   nest.last_contact=s.clock.elapsed
  nest.active=s.clock.elapsed-float(nest.last_contact)<8.0
  nest.status="active" if nest.active else "dormant"
  if nest.active:
   var count: int=0
   for e: Dictionary in s.enemies:
    if int(e.source)==int(nest.id) and not e.initial:
     count+=1
   var interval: float={"small":20.0,"medium":12.0,"large":7.0}[nest.scale]
   var cap: int={"small":2,"medium":4,"large":7}[nest.scale]
   if s.clock.elapsed>=float(nest.spawn_due) and count<cap:
    spawn(nest,false)
    nest.spawn_due=s.clock.elapsed+interval
  else:
   nest.spawn_due=s.clock.elapsed+3.0
  if nest.mother and nest.active:
   var target: Vector2=_bounded_goal(nest,s.position,65.0)
   s.nav.move(nest,target,8.0,dt,s.clock.elapsed,true)
   if nest.pos.distance_to(s.position)<15.0 and s.clock.elapsed>=float(nest.attack_at):
    hurt_player(10.0)
    nest.attack_at=s.clock.elapsed+1.5
 for enemy: Dictionary in s.enemies.duplicate():
  _enemy(enemy,dt)

func _shots(dt: float) -> void:
 for shot: Dictionary in s.shots.duplicate():
  var old: Vector2=shot.pos
  var travel: float=minf(float(shot.remaining),float(shot.speed)*dt)
  var next: Vector2=old+shot.direction*travel
  var blocked: bool=s.placement.blocks_projectile(old,next)
  var hit: Dictionary={}
  var is_nest: bool=false
  var closest: float=INF
  if not blocked:
   for e: Dictionary in s.enemies:
    var along: float=old.distance_to(e.pos)
    if _distance_segment(e.pos,old,next)<5.0 and along<closest:
     hit=e
     closest=along
   for n: Dictionary in s.nests:
    var along: float=old.distance_to(n.pos)
    if _distance_segment(n.pos,old,next)<7.0 and along<closest:
     hit=n
     is_nest=true
     closest=along
  shot.pos=next
  shot.remaining=float(shot.remaining)-travel
  if not hit.is_empty():
   shot.pos=hit.pos
  if blocked or not hit.is_empty() or float(shot.remaining)<=0.01:
   if not blocked:
    if shot.kind=="bazooka":
     for e: Dictionary in s.enemies.duplicate():
      if e.pos.distance_to(shot.pos)<=24.0 and not s.placement.blocks_projectile(shot.pos,e.pos):
       damage_enemy(e,float(shot.damage),1.2)
     for n: Dictionary in s.nests.duplicate():
      if n.pos.distance_to(shot.pos)<=24.0 and not s.placement.blocks_projectile(shot.pos,n.pos):
       damage_nest(n,float(shot.damage))
    elif not hit.is_empty():
     if is_nest: damage_nest(hit,float(shot.damage))
     else: damage_enemy(hit,float(shot.damage),0.12)
    else:
     Landing.scatter_seeds(s.state,4,shot.pos,5.0,1,s.rng.randi())
   s.shots.erase(shot)

func damage_enemy(e: Dictionary,amount: float,stun: float = 0.0) -> void:
 e.hp=float(e.hp)-amount
 e.stun_until=s.clock.elapsed+stun
 if e.hp<=0.0:
  if e.initial:
   s.seeds+=15 if e.strong else 6
  # A defeated animal accelerates local growth without creating repeatable seed income.
  for index: int in Landing.tiles_in_radius(s.state,4,e.pos,12.0):
   if s.state.target[index]==1:
    s.state.fertility[index]=100
  s.enemies.erase(e)

func damage_nest(n: Dictionary,amount: float) -> void:
 n.hp=float(n.hp)-amount
 if n.hp<=0.0:
  s.seeds+={"small":30,"medium":80,"large":200}[n.scale]
  for fossil: Dictionary in s.fossils:
   if int(fossil.nest_id)==int(n.id):
    s.unlock_fossil(fossil)
  s.nests.erase(n)

func hurt_player(amount: float) -> void:
 if s.hp<=0.0:
  return
 s.hp=maxf(0.0,s.hp-amount)
 s.last_damage=s.clock.elapsed
 if s.hp<=0.0:
  s.respawn_at=s.clock.elapsed+3.0

func _bounded_goal(e: Dictionary,goal: Vector2,radius: float) -> Vector2:
 var home: Vector2=e.home
 if home.distance_to(goal)>radius:
  return home
 var c: Vector2i=Coords.logic_to_cell(goal)
 if not s.state.in_bounds(c.x,c.y) or s.state.zone_state[s.state.zone_at(s.state.index_of(c.x,c.y))]>=2:
  return home
 return goal

func _enemy(e: Dictionary,dt: float) -> void:
 if s.clock.elapsed<float(e.stun_until):
  e.phase="stunned"
  return
 var target: Vector2=e.home
 var victim: Dictionary={}
 var target_player: bool=false
 var dist: float=80.0
 if s.hp>0.0 and e.pos.distance_to(s.position)<dist:
  target=s.position
  dist=e.pos.distance_to(target)
  target_player=true
 for h: Dictionary in s.helpers:
  var d: float=e.pos.distance_to(h.pos)
  if d<dist:
   dist=d; target=h.pos; victim=h; target_player=false
 for p: Dictionary in s.plants:
  var d: float=e.pos.distance_to(p.pos)
  var preference: float=1.0
  if p.mature and p.kind=="wheat": preference=0.55
  if p.mature and p.kind=="rafflesia":
   preference=0.45 if e.kind=="spider" else 4.0
  if d*preference<dist and d<85.0:
   dist=d*preference; target=p.pos; victim=p; target_player=false
 target=_bounded_goal(e,target,100.0)
 if target==e.home:
  victim={}; target_player=false
 # Rafflesia causes beasts to prefer a route away from its local scent.
 if e.kind=="boar":
  for p: Dictionary in s.plants:
   if p.mature and p.kind=="rafflesia" and e.pos.distance_to(p.pos)<30.0:
    target=e.pos+(e.pos-p.pos).normalized()*28.0
    target=_bounded_goal(e,target,100.0)
    target_player=false; victim={}
    break
 var actual: float=e.pos.distance_to(target)
 var phase: String=e.phase
 if e.kind=="boar" and target_player and actual<65.0:
  if phase in ["idle","chase","stunned"] and s.clock.elapsed>=float(e.attack_at):
   e.phase="windup"; e.phase_until=s.clock.elapsed+0.7; e.charge_dir=(target-e.pos).normalized(); e.hit_charge=false
  elif phase=="windup" and s.clock.elapsed>=float(e.phase_until):
   e.phase="charge"; e.phase_until=s.clock.elapsed+0.65
  elif phase=="charge":
   var next: Vector2=e.pos+e.charge_dir*65.0*dt
   var c: Vector2i=Coords.logic_to_cell(next)
   if s.state.in_bounds(c.x,c.y) and s.state.is_walkable(c.x,c.y) and s.state.zone_state[s.state.zone_at(s.state.index_of(c.x,c.y))]<2:
    e.pos=Walker.move(s.state,4,e.pos,e.charge_dir*65.0*dt,Vector2(1.5,1.5))
   if e.pos.distance_to(s.position)<9.0 and not e.hit_charge:
    hurt_player(12.0); e.hit_charge=true
   if s.clock.elapsed>=float(e.phase_until):
    e.phase="recover"; e.phase_until=s.clock.elapsed+1.5; e.attack_at=s.clock.elapsed+2.0
  elif phase=="recover" and s.clock.elapsed>=float(e.phase_until):
   e.phase="chase"
  if e.phase in ["windup","charge","recover"]:
   return
 if actual<9.0 and (target_player or not victim.is_empty()) and not s.placement.blocks_projectile(e.pos,target):
  e.phase="attack"
  if s.clock.elapsed>=float(e.attack_at):
   if target_player:
    hurt_player(5.0)
   else:
    victim.hp=maxf(0.0,float(victim.hp)-5.0)
    victim.last_combat=s.clock.elapsed
   e.attack_at=s.clock.elapsed+1.0
 else:
  e.phase="chase" if target!=e.home else "idle"
  s.nav.move(e,target,14.0 if e.kind=="spider" else 18.0,dt,s.clock.elapsed,true)
