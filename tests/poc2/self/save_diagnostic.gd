extends SceneTree
const Session: GDScript=preload("res://scripts/poc2/poc2_session.gd")
func _initialize() -> void:
 var s: RefCounted=Session.new()
 s.enemies.clear(); s.nests.clear(); s.unlocked.army=true
 s.place_plant("clover",Vector2i(184,186))
 s.place_helper("army",Vector2i(185,186))
 s.advance_game(1.0)
 s.set_aim(s.position+Vector2(20,0));s.fire()
 var data: Dictionary=JSON.parse_string(JSON.stringify(s.to_dict()))
 var f: FileAccess=FileAccess.open("res://evidence/poc2/self/save_before.json",FileAccess.WRITE); f.store_string(JSON.stringify(data));f.close()
 print(s.restore(data))
 f=FileAccess.open("res://evidence/poc2/self/save_after.json",FileAccess.WRITE); f.store_string(JSON.stringify(s.to_dict()));f.close()
 s.close();quit()
