extends SceneTree
const Session: GDScript=preload("res://scripts/poc2/poc2_session.gd")
const Save: GDScript=preload("res://scripts/poc2/save/poc2_save.gd")
var diffs: Array[String]=[]
func _init() -> void:
 call_deferred("run")
func compare(a: Variant,b: Variant,path: String) -> void:
 if a==b: return
 if (a is float or a is int) and (b is float or b is int) and absf(float(a)-float(b))<=0.000000001: return
 if a is Dictionary and b is Dictionary:
  for key: Variant in a:
   if not b.has(key): diffs.append(path+"/"+str(key)+": missing")
   else: compare(a[key],b[key],path+"/"+str(key))
 elif a is Array and b is Array and a.size()==b.size():
  for i: int in a.size(): compare(a[i],b[i],path+"/"+str(i))
 else: diffs.append(path+": "+str(a)+" != "+str(b))
func run() -> void:
 var s: RefCounted=Session.new()
 s.advance_game(0.35)
 var directory: String="user://poc2_view_save_probe"
 var saved: Dictionary=Save.save_game(s,directory)
 var loaded: Dictionary=Save.load_game(directory)
 if loaded.ok:
  compare(s.to_dict(),loaded.session.to_dict(),"")
  loaded.session.close()
 else: diffs.append(str(loaded))
 var out: Dictionary={"save_ok":saved.ok,"load_ok":loaded.ok,"diffs":diffs}
 print(JSON.stringify(out))
 var file: FileAccess=FileAccess.open("res://evidence/poc2/view/save_probe.json",FileAccess.WRITE)
 file.store_string(JSON.stringify(out,"  "))
 file.close()
 s.close()
 quit(0 if saved.ok and loaded.ok and diffs.is_empty() else 1)

