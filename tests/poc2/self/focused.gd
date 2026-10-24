extends SceneTree
const Session: GDScript=preload("res://scripts/poc2/poc2_session.gd")
var checks: Array[Dictionary]=[]
func check(name: String,condition: bool,detail: Variant = "") -> void:
 checks.append({"name":name,"pass":condition,"detail":detail})
 print("PASS " if condition else "FAIL ",name," ",detail)
func _initialize() -> void:
 var s: RefCounted=Session.new()
 s.enemies.clear();s.nests.clear();s.known.fill(1)
 s.unlocked.sprinkler=true;s.unlocked.army=true;s.seeds=500
 var bank: Vector2=s.nav.bank(s.position)
 s.place_helper("sprinkler",Session.Coords.logic_to_cell(bank))
 var sprinkler: Dictionary=s.helpers.back();sprinkler.water=0.0
 s.advance_game(5.25)
 check("refill_exact_five_seconds_after_arrival",sprinkler.water==100.0 and sprinkler.status=="returning_water",sprinkler.water)
 s.place_helper("army",Vector2i(185,186))
 var army: Dictionary=s.helpers.back()
 var initial: Dictionary=JSON.parse_string(JSON.stringify(s.to_dict()))
 s.remove_helper(int(army.id))
 check("restore_different_live_occupancy",s.restore(initial).ok)
 check("semantic_snapshot_exact",JSON.parse_string(JSON.stringify(s.to_dict()))==initial)
 s.close()
 # Combat action assertions use actual travel/impact, not direct damage formulas.
 s=Session.new();s.enemies.clear();s.nests.clear()
 var origin: Vector2=s.position
 var nest: Dictionary={"id":999,"kind":"spider","home":origin,"pos":origin+Vector2(-20,0)}
 s.combat_system.spawn(nest,false)
 var enemy: Dictionary=s.enemies.back();enemy.pos=origin+Vector2(-20,0);enemy.home=enemy.pos
 s.set_aim(enemy.pos)
 s.fire();s.advance_game(0.25)
 check("normal_seed_hits_enemy",enemy.hp==15.0,enemy.hp)
 s.skill(1);s.advance_game(0.25)
 check("bazooka_kills_and_produced_no_reward",s.enemies.is_empty() and s.seeds==56)
 s.combat_system.spawn(nest,true)
 enemy=s.enemies.back();enemy.pos=s.position+Vector2(-12,0);enemy.home=enemy.pos
 s.set_aim(enemy.pos);s.skill(0)
 check("tackle_free_hit_and_dash",enemy.hp==12.0 and s.position.distance_to(origin)>0 and s.seeds==56)
 # Start safe-zone is impassable to the hostile navigation graph.
 var safe: Vector2=Session.Coords.cell_center_logic(Vector2i(191,188))
 check("hostile_route_cannot_enter_safe",s.nav.route(Session.Coords.cell_center_logic(Vector2i(179,188)),safe,true).is_empty())
 s.close()
 var failures: int=0
 for c: Dictionary in checks:
  if not c.pass: failures+=1
 var f: FileAccess=FileAccess.open("res://evidence/poc2/self/focused_results.json",FileAccess.WRITE)
 f.store_string(JSON.stringify({"checks":checks,"pass":checks.size()-failures,"fail":failures,"notes":"Affected save/refill assertions corrected; added actual combat impact and stable-zone path checks. Full 3500s stable sweep not repeated."}," "));f.close()
 quit(1 if failures else 0)
