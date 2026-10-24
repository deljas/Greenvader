extends SceneTree
## POC2-06 independent boundary tests. Run only on the parent's frozen target.
const Session: GDScript=preload("res://scripts/poc2/poc2_session.gd")
const Coords: GDScript=preload("res://scripts/poc/poc_coords.gd")
const OUT: String="res://evidence/poc2/maintenance/independent/"
var checks: Array[Dictionary]=[]
func _init() -> void:
 call_deferred("run")
func check(name_: String,ok: bool,detail: Variant="") -> void:
 checks.append({"name":name_,"status":"PASS" if ok else "FAIL","detail":detail})
 print(checks.back())
func quiet() -> RefCounted:
 var s: RefCounted=Session.new()
 s.enemies.clear(); s.nests.clear(); s.seeds=500; s.known.fill(1)
 for kind: String in ["army","gatlinger","sprinkler"]: s.unlocked[kind]=true
 return s
func reloaded(s: RefCounted,name_: String) -> RefCounted:
 var other: RefCounted=Session.new()
 var result: Dictionary=other.restore(JSON.parse_string(JSON.stringify(s.to_dict())))
 check(name_,result.ok,result)
 return other
func run() -> void:
 blocked_order()
 interrupted_water()
 defeat_save()
 var failures: int=0
 for row: Dictionary in checks:
  if row.status=="FAIL": failures+=1
 var f: FileAccess=FileAccess.open(OUT+"logic-results.json",FileAccess.WRITE)
 f.store_string(JSON.stringify({"checks":checks,"failures":failures}," ")); f.close()
 quit(1 if failures else 0)
func blocked_order() -> void:
 var s: RefCounted=quiet()
 var placed: Dictionary=s.place_helper("army",Vector2i(185,186))
 check("blocked_fixture",placed.ok,placed)
 if not placed.ok: s.close(); return
 var h: Dictionary=s.helpers[0]
 var original: Vector2=h.home
 var hidden: Vector2i=Vector2i(110,100)
 var index: int=s.state.index_of(hidden.x,hidden.y)
 s.known[index]=0
 var accepted: Dictionary=s.move_helper(h.id,Coords.cell_center_logic(hidden))
 var start: Vector2=h.pos
 s.advance_game(0.25)
 check("unknown_obstacle_not_disclosed",accepted.ok and h.status=="exploring" and h.pos!=start,{"accepted":accepted,"status":h.status})
 s.known[index]=1
 s.advance_game(0.25)
 var stopped: Vector2=h.pos
 s.advance_game(1.0)
 check("unreachable_persists_across_ticks",h.status=="unreachable" and not h.moving and h.pos==stopped,{"status":h.status,"stationary":h.pos==stopped})
 var restored: RefCounted=reloaded(s,"save_unreachable_restores")
 s.close(); s=restored
 if s.helpers.is_empty(): s.close(); return
 h=s.helpers[0]; stopped=h.pos
 s.advance_game(1.0)
 check("restored_unreachable_waits",h.status=="unreachable" and not h.moving and h.pos==stopped,h.status)
 var valid: Dictionary=s.move_helper(h.id,original)
 s.advance_game(2.0)
 check("new_valid_order_recovers",valid.ok and h.status!="unreachable" and h.pos.distance_to(original)<4.0,{"result":valid,"status":h.status,"distance":h.pos.distance_to(original)})
 s.close()
func interrupted_water() -> void:
 var s: RefCounted=quiet()
 var placed: Dictionary=s.place_helper("sprinkler",Vector2i(194,188))
 check("refill_fixture",placed.ok,placed)
 if not placed.ok: s.close(); return
 var h: Dictionary=s.helpers[0]
 var home: Vector2=h.home
 h.water=0.0
 var steps: int=0
 while steps<240 and h.status!="refilling":
  s.advance_game(0.25); steps+=1
 check("refill_arrives_at_bank",h.status=="refilling",h.status)
 s.advance_game(1.75)
 var partial: float=h.water
 # Threat is needed only for one worker-decision tick; do not serialize an incomplete enemy fixture.
 s.enemies.append({"id":999,"pos":h.pos+Vector2(10,0)})
 s.plant_system.advance(0.25)
 check("partial_refill_flees_without_spending_water",h.status=="fleeing" and h.water==partial and h.home==home,{"status":h.status,"water":h.water,"partial":partial})
 s.enemies.clear()
 var restored: RefCounted=reloaded(s,"save_during_refill_retreat_restores")
 s.close(); s=restored
 if s.helpers.is_empty(): s.close(); return
 h=s.helpers[0]
 steps=0
 while steps<320 and h.status!="returning_water":
  s.advance_game(0.25); steps+=1
 check("retreat_resume_completes_refill",h.status=="returning_water" and h.water==100.0 and h.home==home,{"status":h.status,"water":h.water,"home":str(h.home)})
 restored=reloaded(s,"save_during_refill_return_restores")
 s.close(); s=restored
 if s.helpers.is_empty(): s.close(); return
 h=s.helpers[0]; steps=0
 while steps<320 and h.status=="returning_water":
  s.advance_game(0.25); steps+=1
 check("restored_refill_returns_original_home",h.pos.distance_to(home)<4.0 and h.water==100.0 and h.status!="fleeing",{"status":h.status,"water":h.water,"distance":h.pos.distance_to(home)})
 s.close()
func defeat_save() -> void:
 for helper: bool in [true,false]:
  var s: RefCounted=quiet()
  var cell: Vector2i=Vector2i(180,180)
  if not helper: s.state.set_stage(s.state.index_of(cell.x,cell.y),WorldState.STAGE_SPROUT1)
  var placed: Dictionary=s.place_helper("gatlinger",cell,19) if helper else s.place_plant("clover",cell)
  var label: String="helper" if helper else "crop"
  check(label+"_death_fixture",placed.ok,placed)
  if not placed.ok: s.close(); continue
  var victim: Dictionary=s.helpers[0] if helper else s.plants[0]
  victim.hp=5.0; victim.last_combat=s.clock.elapsed
  var owner: int=victim.owner
  s.combat_system.spawn({"id":999,"kind":"spider","pos":victim.pos,"home":victim.pos+Vector2(30,0)},false)
  s.enemies.back().pos=victim.pos
  var before: int=s.seeds
  s.advance_game(0.25)
  var dead_removed: bool=(s.helpers.is_empty() if helper else s.plants.is_empty())
  check(label+"_defeat_same_tick_no_refund",victim.hp==0.0 and dead_removed and s.seeds==before and not s.state.occupancy_owners.has(owner),{"victim_hp":victim.hp,"removed":dead_removed,"seeds_before":before,"seeds_after":s.seeds,"owner_released":not s.state.occupancy_owners.has(owner)})
  var other: RefCounted=reloaded(s,label+"_death_tick_save_restores")
  check(label+"_restored_defeat_keeps_enemy_and_no_refund",other.seeds==before and other.enemies.size()==1 and (other.helpers.is_empty() if helper else other.plants.is_empty()),{"seeds":other.seeds,"enemies":other.enemies.size()})
  s.close(); other.close()
