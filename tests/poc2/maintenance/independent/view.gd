extends SceneTree
## Focus-safe engine-input checks for title-save protection and temporary help overlays.
const Main: PackedScene=preload("res://scenes/poc2.tscn")
const Save: GDScript=preload("res://scripts/poc2/save/poc2_save.gd")
const OUT: String="res://evidence/poc2/maintenance/independent/"
const SAVE_DIR: String="user://poc2_maintenance_independent_20261022"
var main: Node
var checks: Array[Dictionary]=[]
func _init() -> void:
 root.unfocusable=true
 call_deferred("run")
func frames() -> void:
 for i: int in 3: await process_frame
 await RenderingServer.frame_post_draw
func check(name_: String,ok: bool,detail: Variant="") -> void:
 checks.append({"name":name_,"status":"PASS" if ok else "FAIL","detail":detail}); print(checks.back())
func key(code: int) -> void:
 for pressed: bool in [true,false]:
  var e: InputEventKey=InputEventKey.new(); e.keycode=code; e.physical_keycode=code; e.pressed=pressed
  Input.parse_input_event(e)
func spinbox(node: Node) -> SpinBox:
 var found: Array[Node]=node.find_children("*","SpinBox",true,false)
 return found[0] as SpinBox if not found.is_empty() else null
func run() -> void:
 # Use the normal current_scene path; plain instantiate bypasses the title branch in _ready.
 var startup: Error=change_scene_to_packed(Main)
 await frames()
 main=current_scene
 main.auto_process=false; main.save_dir=SAVE_DIR
 var title_buttons: Array[Node]=main.ui.menu.find_children("*","Button",true,false)
 check("normal_current_scene_title_three_actions",startup==OK and main.menu=="title" and main.ui.menu.visible and title_buttons.size()==3,{"menu":main.menu,"button_count":title_buttons.size()})
 # Seed an isolated real slot through the production save wrapper; never touch normal save paths.
 main.session.seeds=321
 var saved: Dictionary=Save.save_game(main.session,SAVE_DIR)
 var slot: String=SAVE_DIR.path_join(Save.FILE_NAME)
 var original: String=FileAccess.get_file_as_string(slot)
 main.session.seeds=60
 key(KEY_F1); await frames(); key(KEY_F5); await frames()
 main.tick(0.25)
 check("title_help_f5_preserves_real_slot",saved.ok and main.menu=="help" and FileAccess.get_file_as_string(slot)==original,{"menu":main.menu,"slot_unchanged":FileAccess.get_file_as_string(slot)==original})
 key(KEY_F1); await frames()
 check("title_help_returns_once",main.menu=="title" and main.ui.menu.visible and not main.ui.help.visible and not main.ui.supply.visible and main.session.paused)
 main._on_action("new")
 check("title_new_game_enters_play",main.menu=="" and not main.ui.menu.visible and not main.session.paused)
 main.session.seeds=500; main.session.unlocked.gatlinger=true
 main._placement_supply(Vector2i(190,188)); await frames()
 var quantity: SpinBox=spinbox(main.ui.supply)
 check("supply_fixture",quantity!=null)
 if quantity!=null:
  quantity.value=37
  var elapsed: float=main.session.clock.elapsed
  key(KEY_F1); await frames()
  check("help_hides_supply_and_pauses",main.ui.help.visible and not main.ui.supply.visible and not main.ui.menu.visible and main.session.paused)
  # A repeated help request is idempotent; it must not overwrite the return destination.
  main._on_action("help"); main._on_action("help")
  key(KEY_F1); await frames(); main.tick(0.25)
  check("supply_help_restores_single_popup_amount_and_pause",main.menu=="placement_supply" and main.ui.supply.visible and not main.ui.help.visible and not main.ui.menu.visible and spinbox(main.ui.supply).value==37 and main.session.clock.elapsed==elapsed and main.session.paused,{"menu":main.menu,"quantity":spinbox(main.ui.supply).value,"elapsed":main.session.clock.elapsed})
  key(KEY_F1); await frames(); key(KEY_F1); await frames()
  check("help_key_roundtrip_still_single_popup",main.menu=="placement_supply" and main.ui.supply.visible and not main.ui.menu.visible and spinbox(main.ui.supply).value==37)
  root.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT+"supply-after-help.png"))
  key(KEY_ESCAPE); await frames()
  main.session.seeds=432
  key(KEY_F5); await frames()
  var loaded: Dictionary=Save.load_game(SAVE_DIR)
  check("normal_play_f5_still_saves",loaded.ok and loaded.session.seeds==432,loaded.ok)
  if loaded.ok: loaded.session.close()
 var failures: int=0
 for row: Dictionary in checks:
  if row.status=="FAIL": failures+=1
 var f: FileAccess=FileAccess.open(OUT+"view-results.json",FileAccess.WRITE)
 f.store_string(JSON.stringify({"checks":checks,"failures":failures,"save_dir":SAVE_DIR,"input":"Input.parse_input_event; root.unfocusable true"}," ")); f.close()
 main.session.close(); main.queue_free(); await frames(); quit(1 if failures else 0)
