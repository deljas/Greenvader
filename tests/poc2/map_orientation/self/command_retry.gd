extends "res://tests/poc2/map_orientation/self/view.gd"
func run() -> void:
 change_scene_to_packed(Main); await frames()
 main=current_scene; main.auto_process=false; main.save_dir="user://poc2_map_orientation_self_unused"
 main._on_action("new"); await frames()
 var s: RefCounted=main.session
 var map: Control=main.ui.map
 s.seeds=1000; s.unlocked.gatlinger=true; s.known.fill(1)
 s.place_helper("gatlinger",Vector2i(196,188),40)
 var helper: Dictionary=s.helpers[0]
 key(KEY_M); await frames()
 mouse(map.point(helper.pos),MOUSE_BUTTON_WHEEL_UP); await frames()
 mouse(map.point(helper.pos),MOUSE_BUTTON_WHEEL_UP); await frames()
 mouse(map.point(helper.pos)); await frames()
 var target: Vector2=Vector2.ZERO
 # Choose one walkable, visible point outside controls; no repeated gameplay trials.
 for cy: int in range(172,199):
  for cx: int in range(174,199):
   var candidate: Vector2=Coords.cell_center_logic(Vector2i(cx,cy))
   var at: Vector2=map.point(candidate)
   if not s.is_walkable_logic(candidate): continue
   if not map.map_rect.grow(-8).has_point(at): continue
   if at.distance_to(map.point(helper.pos))<16: continue
   if map.remove_button.get_global_rect().has_point(at) or map.supply_button.get_global_rect().has_point(at): continue
   target=candidate
   break
  if target!=Vector2.ZERO: break
 var pixel: Vector2=map.point(target)
 var expected: Vector2=map.logic_at(pixel)
 check("corrected_fixture_walkable_outside_controls",target!=Vector2.ZERO and s.is_walkable_logic(expected),str(pixel))
 mouse(pixel); await frames()
 check("projected_helper_command",helper.home.distance_to(expected)<0.001,{"home":str(helper.home),"clicked":str(expected)})
 map.zoom=2; map.map_center=Vector2(448,448); map.refresh_terrain()
 mouse(Vector2(320,176),MOUSE_BUTTON_WHEEL_DOWN); await frames()
 check("zoom_one_refits_world",map.zoom==1 and map.map_center==Vector2(448,448),{"zoom":map.zoom,"center":str(map.map_center)})
 var failures: int=0
 for row: Dictionary in checks:
  if row.status=="FAIL": failures+=1
 var file: FileAccess=FileAccess.open(OUT+"command-retry-results.json",FileAccess.WRITE)
 file.store_string(JSON.stringify({"checks":checks,"failures":failures,"reason":"Initial target overlapped remove button, first replacement was water. Choose a single valid walkable point before the command."}," "))
 file.close()
 s.close(); main.queue_free(); await frames(); quit(1 if failures else 0)
