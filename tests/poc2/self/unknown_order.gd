extends SceneTree
const Session: GDScript=preload("res://scripts/poc2/poc2_session.gd")
func _initialize() -> void:
 var s: RefCounted=Session.new()
 s.enemies.clear();s.nests.clear();s.unlocked.army=true
 s.place_helper("army",Vector2i(185,186))
 var h: Dictionary=s.helpers[0]
 var target: Vector2i=Vector2i(110,100)
 s.known[s.state.index_of(target.x,target.y)]=0
 var accepted: bool=s.move_helper(int(h.id),Session.Coords.cell_center_logic(target)).ok
 var old: Vector2=h.pos
 s.advance_game(0.25)
 var concealed: bool=h.moving and h.status=="exploring" and h.pos!=old
 h.pos=s.nav.closest_reachable(h.pos,h.home)
 s.reveal();s.advance_game(0.25)
 var discovered: bool=not h.moving and h.status=="unreachable"
 print("UNKNOWN_MOVE ",accepted," / ",concealed," / ",discovered)
 var f: FileAccess=FileAccess.open("res://evidence/poc2/self/unknown_order_results.json",FileAccess.WRITE)
 f.store_string(JSON.stringify({"accepted":accepted,"concealed_while_approaching":concealed,"unreachable_only_after_reveal":discovered}," "));f.close()
 s.advance_game(60.0)
 var fraction_ok: bool=s.income_fraction>=0.0 and s.restore(JSON.parse_string(JSON.stringify(s.to_dict()))).ok
 print("INCOME_BOUNDARY_SAVE ",fraction_ok)
 s.close();quit(0 if accepted and concealed and discovered and fraction_ok else 1)

