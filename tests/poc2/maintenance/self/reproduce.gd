extends SceneTree
const Session: GDScript=preload("res://scripts/poc2/poc2_session.gd")
func _initialize() -> void:
 var s: RefCounted=Session.new()
 s.enemies.clear();s.nests.clear();s.unlocked.army=true;s.unlocked.sprinkler=true;s.seeds=500
 s.place_helper("army",Vector2i(185,186))
 var h: Dictionary=s.helpers[0]
 var target: Vector2i=Vector2i(110,100)
 s.known[s.state.index_of(target.x,target.y)]=0
 s.move_helper(int(h.id),Session.Coords.cell_center_logic(target))
 h.pos=s.nav.closest_reachable(h.pos,h.home);s.reveal()
 s.advance_game(0.25)
 var first: String=h.status
 s.advance_game(0.25)
 var second: String=h.status
 s.remove_helper(int(h.id));s.known.fill(1)
 var bank: Vector2=s.nav.bank(s.position)
 s.place_helper("sprinkler",Session.Coords.logic_to_cell(bank))
 var sprinkler: Dictionary=s.helpers.back()
 sprinkler.water=35.0;sprinkler.bank=bank;sprinkler.status="refilling"
 s.enemies.append({"id":999,"pos":sprinkler.pos+Vector2(10,0)})
 s.plant_system.advance(0.25)
 var fleeing: String=sprinkler.status
 s.enemies.clear();s.plant_system.advance(0.25)
 var after: String=sprinkler.status
 var out: Dictionary={"unreachable":{"first":first,"next_tick":second,"reproduced":first=="unreachable" and second!="unreachable"},"refill_interrupted":{"before":"refilling","danger":fleeing,"after":after,"water":sprinkler.water,"reproduced":after not in ["resupplying","refilling","returning_water"]}}
 var f: FileAccess=FileAccess.open("res://evidence/poc2/maintenance/self/reproduction.json",FileAccess.WRITE);f.store_string(JSON.stringify(out," "));f.close()
 print(JSON.stringify(out));s.close();quit()

