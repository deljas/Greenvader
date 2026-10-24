extends SceneTree
const Main: PackedScene = preload("res://scenes/poc2.tscn")
const Coords: GDScript = preload("res://scripts/poc/poc_coords.gd")
const OUT: String = "res://evidence/poc2/map_orientation/self/"
var main: Node
var checks: Array[Dictionary] = []
func _init() -> void:
 root.unfocusable = true
 call_deferred("run")
func frames() -> void:
 for index: int in 3: await process_frame
 await RenderingServer.frame_post_draw
func check(label: String, ok: bool, detail: Variant = "") -> void:
 checks.append({"name":label,"status":"PASS" if ok else "FAIL","detail":detail})
 print(checks.back())
func key(code: int) -> void:
 for pressed: bool in [true,false]:
  var event: InputEventKey = InputEventKey.new()
  event.keycode=code; event.physical_keycode=code; event.pressed=pressed
  Input.parse_input_event(event)
func mouse(at: Vector2, button: int = MOUSE_BUTTON_LEFT) -> void:
 for pressed: bool in [true,false]:
  var event: InputEventMouseButton = InputEventMouseButton.new()
  event.position=root.get_final_transform()*at; event.button_index=button; event.pressed=pressed
  Input.parse_input_event(event)
func capture(name_: String) -> void:
 root.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT+name_+".png"))
func run() -> void:
 change_scene_to_packed(Main); await frames()
 main=current_scene; main.auto_process=false; main.save_dir="user://poc2_map_orientation_self_unused"
 main._on_action("new"); await frames()
 var s: RefCounted=main.session
 var map: Control=main.ui.map
 capture("mini-normal")
 # The real camera is the independent reference, including its vertical foreshortening.
 var base: Vector2=s.position
 var camera: Camera3D=main.world.camera
 var origin: Vector2=camera.unproject_position(Coords.ground3(Coords.logic_to_ground(base)))
 var max_angle: float=0.0
 var max_roundtrip: float=0.0
 for offset: Vector2 in [Vector2(40,0),Vector2(0,40),Vector2(-40,0),Vector2(40,40)]:
  var actual: Vector2=camera.unproject_position(Coords.ground3(Coords.logic_to_ground(base+offset)))-origin
  var mapped: Vector2=map.point_exact(base+offset)-map.point_exact(base)
  max_angle=maxf(max_angle,absf(actual.angle_to(mapped)))
  max_roundtrip=maxf(max_roundtrip,map.logic_at(map.point_exact(base+offset)).distance_to(base+offset))
 check("real_camera_ground_projection",max_angle<0.0001,{"max_angle_radians":max_angle})
 check("precision_before_draw",max_roundtrip<0.001,{"max_logic_error":max_roundtrip})
 s.position+=Vector2(5.3,-1.7); main.world.sync(0.0); await frames()
 var common_center: Vector2=map._center()
 var same_center: bool=map.logic_at(map.map_rect.get_center()).distance_to(common_center)<0.001
 var player_anchor: Vector2=map.point(s.position)
 check("moving_mini_shared_snapped_center",same_center and player_anchor==map.map_rect.get_center(),{"display_center":str(common_center),"player":str(s.position)})
 capture("mini-moving")
 s.seeds=1000; s.unlocked.gatlinger=true
 var placed: Dictionary=s.place_helper("gatlinger",Vector2i(196,188),40)
 check("helper_fixture",placed.ok)
 var helper: Dictionary=s.helpers[0]
 helper.hp=40.0
 key(KEY_M); await frames()
 var elapsed: float=s.clock.elapsed
 main.tick(0.25)
 check("map_pause",map.expanded and s.paused and elapsed==s.clock.elapsed)
 capture("full-explored")
 var known: PackedByteArray=s.known.duplicate()
 s.known.fill(1); map.refresh_terrain(); await frames()
 capture("full-terrain")
 check("diamond_fits_existing_frame",map.point_exact(Vector2.ZERO)==Vector2(320,120) and map.point_exact(Vector2(896,896))==Vector2(320,232) and map.point_exact(Vector2(896,0))==Vector2(432,176),str(map.map_rect))
 # Zoom at a real discovered position, checking the raw inverse rather than rounded icons.
 var anchor_pixel: Vector2=map.point(helper.pos)
 var anchor_logic: Vector2=map.logic_at(anchor_pixel)
 mouse(anchor_pixel,MOUSE_BUTTON_WHEEL_UP); await frames()
 var error2: float=map.logic_at(anchor_pixel).distance_to(anchor_logic)
 mouse(anchor_pixel,MOUSE_BUTTON_WHEEL_UP); await frames()
 var error4: float=map.logic_at(anchor_pixel).distance_to(anchor_logic)
 check("zoom_2_4_cursor_anchor",map.zoom==4 and maxf(error2,error4)<0.001,{"zoom2_error":error2,"zoom4_error":error4})
 mouse(map.point(helper.pos)); await frames()
 check("projected_icon_selection_upright_controls",map.selected_id==helper.id and map.remove_button.visible and map.supply_button.visible and map.remove_button.rotation==0 and map.supply_button.rotation==0)
 capture("zoom-selected")
 var original_home: Vector2=helper.home
 mouse(map.supply_button.get_global_rect().get_center()); await frames()
 var opened: bool=map.popup.visible
 mouse(map.popup.position+Vector2(8,8)); await frames()
 check("popup_owns_click",opened and helper.home==original_home and s.clock.elapsed==elapsed)
 map.popup.hide(); map.update_buttons()
 # Choose a known walkable cell away from the selected icon and its command buttons.
 var target: Vector2=Coords.cell_center_logic(Vector2i(174,172))
 var expected: Vector2=map.logic_at(map.point(target))
 mouse(map.point(target)); await frames()
 check("projected_helper_command",helper.home.distance_to(expected)<0.001,{"home":str(helper.home),"clicked":str(expected)})
 # World-exterior corner at zoom1 must never become a helper command.
 map.zoom=1; map.map_center=Vector2(448,448); map.refresh_terrain(); map.update_buttons(); await frames()
 var before: Vector2=helper.home
 mouse(map.map_rect.position+Vector2(10,10)); await frames()
 check("diamond_exterior_no_command",helper.home==before)
 map.selected_id=helper.id; map.selected_helper=true
 map.zoom=4; map.map_center=Vector2(40,40); map.refresh_terrain(); map.update_buttons(); await frames()
 check("offscreen_selected_controls_hidden",not map.remove_button.visible and not map.supply_button.visible)
 capture("edge-clipped")
 # Re-fit when returning to 1x is intentional, so all terrain is visible again.
 map.zoom=2; map.map_center=Vector2(448,448); map.refresh_terrain()
 mouse(Vector2(320,176),MOUSE_BUTTON_WHEEL_DOWN); await frames()
 check("zoom_one_refits_world",map.zoom==1 and map.map_center==Vector2(448,448))
 s.known=known; s.visible.fill(0)
 var enemy: Dictionary=s.enemies[0]
 enemy.pos=helper.pos+Vector2(100,0)
 map.refresh_terrain(); map.queue_redraw(); await frames()
 check("unknown_enemy_not_disclosed",not map.disclosed(enemy.pos))
 root.size=Vector2i(1280,720); await frames()
 check("integer_nearest_640_view",root.content_scale_stretch==Window.CONTENT_SCALE_STRETCH_INTEGER and main.render_view.size==Vector2i(640,360) and map.texture_filter==CanvasItem.TEXTURE_FILTER_NEAREST and root.get_final_transform().x.length()==2.0,{"window":str(root.size),"internal_image":str(root.get_texture().get_size()),"final_transform":str(root.get_final_transform())})
 capture("integer-2x-internal")
 var failures: int=0
 for row: Dictionary in checks:
  if row.status=="FAIL": failures+=1
 var file: FileAccess=FileAccess.open(OUT+"results.json",FileAccess.WRITE)
 file.store_string(JSON.stringify({"checks":checks,"failures":failures,"renderer":RenderingServer.get_video_adapter_name(),"input":"Input.parse_input_event only; root.unfocusable true","not_run":["physical OS input","full game regression","long-play balance"]}," "))
 file.close()
 s.close(); main.queue_free(); await frames(); quit(1 if failures else 0)
