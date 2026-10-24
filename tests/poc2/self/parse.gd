extends SceneTree
const Session: GDScript=preload("res://scripts/poc2/poc2_session.gd")
func _initialize() -> void:
 var s: RefCounted=Session.new()
 print("POC2_INITIAL ",s.snapshot())
 s.advance_game(2.0)
 var saved: Dictionary=s.to_dict()
 print("POC2_RESTORE ",s.restore(JSON.parse_string(JSON.stringify(saved))))
 print("POC2_POST ",s.snapshot())
 s.close()
 quit()
