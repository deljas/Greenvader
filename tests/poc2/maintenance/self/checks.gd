extends SceneTree
const Session: GDScript=preload("res://scripts/poc2/poc2_session.gd")
var checks: Array[Dictionary]=[]
func check(label: String,ok: bool,detail: Variant="") -> void:
 checks.append({"name":label,"pass":ok,"detail":detail})
 print("PASS " if ok else "FAIL ",label," ",detail)
func fresh() -> RefCounted:
 var s: RefCounted=Session.new()
 s.enemies.clear();s.nests.clear();s.seeds=1000
 s.unlocked.army=true;s.unlocked.gatlinger=true;s.unlocked.sprinkler=true
 return s
func roundtrip(s: RefCounted) -> bool:
 var restored: Dictionary=s.restore(JSON.parse_string(JSON.stringify(s.to_dict())))
 return restored.ok
func _initialize() -> void:
 # Each helper: hidden blocked target, persistent wait, save/load, fresh command.
 for kind: String in ["army","gatlinger","sprinkler"]:
  var s: RefCounted=fresh()
  s.place_helper(kind,Vector2i(185,186),10 if kind=="gatlinger" else 0)
  var h: Dictionary=s.helpers[0]
  var id: int=int(h.id)
  var hidden: Vector2i=Vector2i(110,100)
  s.known[s.state.index_of(hidden.x,hidden.y)]=0
  var ordered: bool=s.move_helper(id,Session.Coords.cell_center_logic(hidden)).ok
  s.advance_game(0.25)
  check(kind+"_hidden_obstacle_not_leaked",ordered and h.status=="exploring" and h.moving)
  h.pos=s.nav.closest_reachable(h.pos,h.home);s.reveal();s.advance_game(0.25)
  var waiting: Vector2=h.pos
  s.advance_game(1.0)
  check(kind+"_blocked_wait_persists",h.status=="unreachable" and h.pos==waiting and not h.moving,h.status)
  var saved: bool=roundtrip(s);h=s.helpers[0]
  s.advance_game(0.5)
  check(kind+"_blocked_wait_saved",saved and h.status=="unreachable" and h.pos==waiting)
  var valid: Vector2=Session.Coords.cell_center_logic(Vector2i(185,186))
  var resumed: bool=s.move_helper(id,valid).ok
  s.advance_game(0.25)
  check(kind+"_new_order_recovers",resumed and not h.blocked_order and h.status!="unreachable")
  s.close()
 # Interrupted partial refill must travel back, finish the existing 100-water budget,
 # then return to the original home. A mid-retreat snapshot must preserve intent.
 var s: RefCounted=fresh();s.known.fill(1)
 var bank: Vector2=s.nav.bank(s.position)
 var home: Vector2=Session.Coords.cell_center_logic(Vector2i(185,186))
 s.place_helper("sprinkler",Session.Coords.logic_to_cell(bank))
 var h: Dictionary=s.helpers[0];h.home=home;h.bank=bank;h.water=35.0;h.status="refilling";h.water_task="refilling"
 s.enemies.append({"id":999,"pos":h.pos+Vector2(10,0)})
 s.plant_system.advance(0.25)
 check("partial_refill_flees_preserving_water",h.status=="fleeing" and h.water==35.0 and h.water_task=="refilling")
 # Artificial proximity enemy served only as a danger sensor; clear before full snapshot schema validation.
 s.enemies.clear()
 var saved: bool=roundtrip(s);h=s.helpers[0]
 s.plant_system.advance(0.25)
 check("partial_refill_restore_returns_to_bank",saved and h.water==35.0 and h.water_task in ["resupplying","refilling"] and h.status!="watering",h.status)
 # Arrived at the bank: 65 units take 3.25s at the unchanged 20 units/s.
 h.pos=bank;h.status="refilling";h.water_task="refilling"
 for step: int in 13:
  s.plant_system.advance(0.25)
 check("partial_refill_finishes_at_existing_rate",h.water==100.0 and h.water_task=="returning_water",h.water)
 s.enemies.append({"id":999,"pos":h.pos+Vector2(10,0)})
 s.plant_system.advance(0.25)
 check("return_trip_survives_flee",h.status=="fleeing" and h.water_task=="returning_water" and h.home==home)
 s.enemies.clear();saved=roundtrip(s);h=s.helpers[0]
 s.plant_system.advance(0.25)
 check("return_trip_restores_original_home",saved and h.status=="returning_water" and h.home==home and h.water==100.0)
 # Put it at the actual destination, then verify the order completes without losing water.
 h.pos=home;s.plant_system.advance(0.25)
 check("return_trip_completes",h.water_task=="" and h.status=="working" and h.water==100.0)
 # Older first-PoC2 saves omit the added optional intent fields.
 var legacy: Dictionary=JSON.parse_string(JSON.stringify(s.to_dict()))
 legacy.entities.helpers[0].erase("blocked_order");legacy.entities.helpers[0].erase("water_task")
 check("older_save_compatible",s.restore(legacy).ok)
 var corrupt: Dictionary=JSON.parse_string(JSON.stringify(s.to_dict()))
 corrupt.entities.helpers[0].water_task="not_a_task"
 var intact: Dictionary=JSON.parse_string(JSON.stringify(s.to_dict()))
 check("invalid_task_save_rejected_atomically",not s.restore(corrupt).ok and JSON.parse_string(JSON.stringify(s.to_dict()))==intact)
 s.close()
 for helper: bool in [false,true]:
  s=fresh();s.known.fill(1)
  var cell: Vector2i=Vector2i(180,180)
  s.state.set_stage(s.state.index_of(cell.x,cell.y),WorldState.STAGE_MATURE)
  if helper: s.place_helper("army",cell)
  else: s.place_plant("clover",cell)
  var rows: Array=s.helpers if helper else s.plants
  var victim: Dictionary=rows[0];victim.hp=5.0;victim.last_combat=0.0
  if helper: victim.attack_at=1000.0
  s.combat_system.spawn({"id":999,"kind":"boar","pos":victim.pos+Vector2(4,0),"home":victim.pos+Vector2(30,0)},false)
  s.enemies.back().pos=victim.pos+Vector2(4,0)
  var seeds_before: int=s.seeds
  var owner: int=int(victim.owner)
  s.advance_game(0.25)
  check(("helper" if helper else "crop")+"_combat_cleanup_same_tick",victim.hp==0.0 and rows.is_empty() and not s.state.occupancy_owners.has(owner) and s.seeds==seeds_before)
  check(("helper" if helper else "crop")+"_save_after_fatal_tick",roundtrip(s))
  s.close()
 var failures: int=0
 for c: Dictionary in checks:
  if not c.pass: failures+=1
 var f: FileAccess=FileAccess.open("res://evidence/poc2/maintenance/self/results.json",FileAccess.WRITE)
 f.store_string(JSON.stringify({"checks":checks,"pass":checks.size()-failures,"fail":failures,"not_run":["GPU rendering","OS physical input","3500s full sweep (unchanged)"]}," "));f.close()
 print("RESULT ",checks.size()-failures," PASS / ",failures," FAIL")
 quit(1 if failures else 0)
