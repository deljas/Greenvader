extends SceneTree
const Session: GDScript=preload("res://scripts/poc2/poc2_session.gd")
func _initialize() -> void:
 var s: RefCounted=Session.new();s.enemies.clear();s.nests.clear();s.known.fill(1);s.unlocked.army=true
 var out: Dictionary=s.place_helper("army",Vector2i(180,180))
 var h: Dictionary=s.helpers.back();h.hp=5.0;h.attack_at=1000.0;h.last_combat=0.0
 s.combat_system.spawn({"id":999,"kind":"boar","pos":h.pos+Vector2(4,0),"home":h.pos+Vector2(30,0)},false)
 var enemy: Dictionary=s.enemies.back();enemy.pos=h.pos+Vector2(4,0)
 s.advance_game(0.25)
 var hp_after: float=h.hp
 var save: Dictionary=JSON.parse_string(JSON.stringify(s.to_dict()))
 var restored: Dictionary=s.restore(save)
 var result: Dictionary={"placed":out,"hp_after_combat":hp_after,"dead_helper_still_saved":save.entities.helpers.size(),"restore":restored,"reproduced":hp_after==0 and not restored.ok}
 var f: FileAccess=FileAccess.open("res://evidence/poc2/maintenance/self/death_save_reproduction.json",FileAccess.WRITE);f.store_string(JSON.stringify(result," "));f.close()
 print(JSON.stringify(result));s.close();quit()


