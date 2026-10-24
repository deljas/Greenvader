extends "res://tests/poc2/map_orientation/self/view.gd"
func run() -> void:
 change_scene_to_packed(Main); await frames()
 main=current_scene; main.auto_process=false; main.save_dir="user://poc2_map_orientation_corner_unused"
 main._on_action("new"); await frames()
 var s: RefCounted=main.session
 var map: Control=main.ui.map
 s.seeds=1000; s.unlocked.gatlinger=true
 s.place_helper("gatlinger",Vector2i(196,188),40)
 var helper: Dictionary=s.helpers[0]
 helper.pos=Vector2(894,894); helper.home=helper.pos
 key(KEY_M); await frames()
 var at: Vector2=map.point(helper.pos)
 mouse(at); await frames()
 check("last_cell_drawn_icon_selectable",map.selected_id==helper.id and map.selected_helper and map.remove_button.visible and map.supply_button.visible,{"logic":str(helper.pos),"pixel":str(at),"inverse":str(map.logic_at(at))})
 capture("corner-selected")
 var before: Vector2=helper.home
 var outside: Vector2=map.map_rect.position+Vector2(10,10)
 mouse(outside); await frames()
 check("world_exterior_still_cannot_receive_order",helper.home==before and not map._world_contains(map.logic_at(outside)),{"home":str(helper.home),"outside_inverse":str(map.logic_at(outside))})
 var failures: int=0
 for row: Dictionary in checks:
  if row.status=="FAIL": failures+=1
 var file: FileAccess=FileAccess.open(OUT+"corner-results.json",FileAccess.WRITE)
 file.store_string(JSON.stringify({"checks":checks,"failures":failures,"input":"Input.parse_input_event; root.unfocusable=true","change":"Resolve drawn icon hit before rejecting exterior movement"}," "))
 file.close()
 s.close(); main.queue_free(); await frames(); quit(1 if failures else 0)
