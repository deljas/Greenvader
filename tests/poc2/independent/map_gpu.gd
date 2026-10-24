extends SceneTree
const Main: PackedScene=preload("res://scenes/poc2.tscn")
var main: Node
var checks: Array[Dictionary]=[]
func _init() -> void:
 root.unfocusable=true
 call_deferred("run")
func frames() -> void:
 for i: int in 3: await process_frame
 await RenderingServer.frame_post_draw
func check(name_: String,ok: bool,detail: Variant="") -> void:
 checks.append({"name":name_,"status":"PASS" if ok else "FAIL","detail":detail})
 print(checks.back())
func key(code: int) -> void:
 for pressed: bool in [true,false]:
  var e: InputEventKey=InputEventKey.new(); e.keycode=code; e.physical_keycode=code; e.pressed=pressed
  Input.parse_input_event(e)
func mouse(at: Vector2,button: int=MOUSE_BUTTON_LEFT) -> void:
 for pressed: bool in [true,false]:
  var e: InputEventMouseButton=InputEventMouseButton.new()
  e.position=root.get_final_transform()*at; e.button_index=button; e.pressed=pressed
  Input.parse_input_event(e)
func run() -> void:
 main=Main.instantiate(); main.auto_process=false; main.save_dir="user://poc2_independent_unused"
 root.add_child(main)
 await frames()
 var s: RefCounted=main.session
 s.seeds=1000; s.unlocked.gatlinger=true; s.unlocked.sprinkler=true
 var gat: Dictionary=s.place_helper("gatlinger",Vector2i(196,188),100)
 var spr: Dictionary=s.place_helper("sprinkler",Vector2i(194,184))
 check("map_fixture",gat.ok and spr.ok)
 var h: Dictionary=s.helpers[0]
 main.world.sync(0.0)
 var elapsed: float=s.clock.elapsed
 key(KEY_M); await frames()
 var map: Control=main.ui.map
 mouse(map.point(s.position),MOUSE_BUTTON_WHEEL_UP); await frames()
 mouse(map.point(s.position),MOUSE_BUTTON_WHEEL_UP); await frames()
 main.tick(0.25)
 check("engine_map_pause_zoom",map.expanded and s.paused and s.clock.elapsed==elapsed and map.zoom==4,{"zoom":map.zoom,"elapsed":s.clock.elapsed})
 var at: Vector2=map.point(h.pos)
 var full_image: Image=root.get_texture().get_image()
 full_image.save_png("C:/godot/greenvader/evidence/poc2/independent/map-full.png")
 # Texture image coordinates are internal 640x360; final transform is only for window input.
 var gauge_pixel: Vector2i=Vector2i(at+Vector2(-4,5))
 var no_gauge: Color=full_image.get_pixelv(gauge_pixel)
 h.hp=40.0; h.ammo=35; s.helpers[1].water=30.0
 map.queue_redraw(); await frames()
 var depleted: Image=root.get_texture().get_image()
 depleted.save_png("C:/godot/greenvader/evidence/poc2/independent/map-depleted.png")
 var now_gauge: Color=depleted.get_pixelv(gauge_pixel)
 check("full_gauge_hidden_depleted_visible",no_gauge!=now_gauge,{"full_pixel":str(no_gauge),"depleted_pixel":str(now_gauge)})
 mouse(map.point(h.pos)); await frames()
 check("engine_select_shows_commands",map.selected_id==h.id and map.remove_button.visible and map.supply_button.visible)
 var original_home: Vector2=h.home
 mouse(map.supply_button.get_global_rect().get_center()); await frames()
 check("engine_supply_popup_opens",map.popup.visible)
 mouse(map.popup.position+Vector2(8,8)); await frames()
 check("popup_click_no_movement_or_time",h.home==original_home and s.clock.elapsed==elapsed)
 map.quantity.value=5
 var before_seed: int=s.seeds
 for b: Node in map.popup.find_children("*","Button",true,false):
  if b.text=="確定": mouse(b.get_global_rect().get_center()); break
 await frames()
 check("engine_supply_confirms_once",h.ammo==40 and s.seeds==before_seed-5 and not map.popup.visible)
 # Living enemy nodes must disappear when current visibility is removed.
 var enemy: Dictionary=s.enemies[0]
 enemy.pos=s.position+Vector2(8,8); s.reveal(); main.world.sync(0.0)
 var entity_key: String="enemies"+str(enemy.id)
 s.visible.fill(0); main.world.sync(0.0)
 check("unknown_enemy_view_hidden",main.world.entities.has(entity_key) and not main.world.entities[entity_key].visible)
 var old_light: int=main.world.light_updates
 main.world.sync(0.0); main.world.sync(0.0)
 check("paused_light_not_rewritten",main.world.light_updates==old_light)
 check("internal_640_and_nearest",main.render_view.size==Vector2i(640,360) and main.view_rect.texture_filter==CanvasItem.TEXTURE_FILTER_NEAREST)
 var failures: int=0
 for row: Dictionary in checks:
  if row.status=="FAIL": failures+=1
 var f: FileAccess=FileAccess.open("res://evidence/poc2/independent/map-gpu-results.json",FileAccess.WRITE)
 f.store_string(JSON.stringify({"checks":checks,"failures":failures,"renderer":RenderingServer.get_video_adapter_name(),"input":"Input.parse_input_event only; root.unfocusable true"}," ")); f.close()
 main.session.close(); main.queue_free(); await frames()
 quit(1 if failures else 0)
