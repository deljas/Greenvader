extends SceneTree
## POC2-06 narrow menu/input regression. No OS input or foregrounding.
const Main: PackedScene=preload("res://scenes/poc2.tscn")
const Save: GDScript=preload("res://scripts/poc2/save/poc2_save.gd")
const OUT: String="res://evidence/poc2/maintenance/view/"
const TEST_SAVE: String="user://poc2_maintenance_view_20261022"
var main: Node
var checks: Array[Dictionary]=[]

func _init() -> void:
	root.unfocusable=true
	call_deferred("run")

func frames() -> void:
	for i: int in 3: await process_frame
	await RenderingServer.frame_post_draw

func check(name_: String, passed: bool, detail: Variant="") -> void:
	checks.append({"name":name_,"status":"PASS" if passed else "FAIL","detail":detail})
	print(checks.back())

func key(code: int) -> void:
	for pressed: bool in [true,false]:
		var event: InputEventKey=InputEventKey.new()
		event.physical_keycode=code
		event.keycode=code
		event.pressed=pressed
		Input.parse_input_event(event)

func mouse(at: Vector2) -> void:
	for pressed: bool in [true,false]:
		var event: InputEventMouseButton=InputEventMouseButton.new()
		event.position=root.get_final_transform()*at
		event.button_index=MOUSE_BUTTON_LEFT
		event.pressed=pressed
		Input.parse_input_event(event)

func capture(name_: String) -> void:
	await frames()
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT+name_+".png"))

func saved_seeds() -> int:
	var parser: JSON=JSON.new()
	if parser.parse(FileAccess.get_file_as_string(TEST_SAVE.path_join(Save.FILE_NAME)))!=OK: return -1
	return int(parser.data.state.values.seeds)

func run() -> void:
	main=Main.instantiate()
	main.auto_process=false
	main.save_dir=TEST_SAVE
	root.add_child(main)
	await frames()
	# Explicit title fixture: a test-instantiated scene is intentionally not the game's current_scene.
	main.menu="title"
	main.ui.show_menu(true)
	main._sync_pause()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TEST_SAVE))
	var path: String=TEST_SAVE.path_join(Save.FILE_NAME)
	var previous: FileAccess=FileAccess.open(path,FileAccess.WRITE)
	if previous==null:
		check("test_save_writable",false)
		finish()
		return
	previous.store_string("existing-slot-must-survive-title")
	previous.close()
	var original: String=FileAccess.get_sha256(path)
	key(KEY_F5)
	await frames()
	check("title_f5_preserves_existing_slot",FileAccess.get_sha256(path)==original)
	key(KEY_F1)
	await frames()
	check("title_help_is_only_panel",main.menu=="help" and main._help_return=="title" and main.ui.help.visible and not main.ui.menu.visible and not main.ui.supply.visible)
	key(KEY_F5)
	var rejected: Dictionary=main.save_game()
	await frames()
	check("title_help_f5_and_direct_save_rejected",not rejected.ok and FileAccess.get_sha256(path)==original)
	# '?' is outside the help panel and used to overwrite the return target with 'help'.
	mouse(Vector2(619,342))
	await frames()
	check("reopening_help_keeps_title_return",main._help_return=="title")
	key(KEY_F1)
	await frames()
	check("help_returns_to_title_only",main.menu=="title" and main.ui.menu.visible and not main.ui.help.visible and not main.ui.supply.visible and main.session.paused)
	main._on_action("new")
	main.session.seeds=123
	key(KEY_F5)
	await frames()
	check("playing_f5_saves",saved_seeds()==123)
	key(KEY_ESCAPE)
	main.session.seeds=124
	key(KEY_F5)
	await frames()
	check("pause_f5_saves",main.menu=="pause" and saved_seeds()==124)
	key(KEY_F1)
	key(KEY_F1)
	await frames()
	check("help_returns_to_pause_only",main.menu=="pause" and main.ui.menu.visible and not main.ui.help.visible and not main.ui.supply.visible and main.session.paused)
	main._on_action("resume")
	main.session.seeds=200
	main.session.unlocked.gatlinger=true
	main._placement_kind="gatlinger"
	main._placement_supply(Vector2i(196,188))
	await frames()
	var quantity: SpinBox=main.ui.supply.find_children("*","SpinBox",true,false)[0]
	quantity.value=17
	var elapsed: float=main.session.clock.elapsed
	var seeds: int=main.session.seeds
	var count: int=main.session.helpers.size()
	key(KEY_F1)
	await frames()
	main.tick(0.25)
	check("supply_help_hides_popup_and_stops_time",main.menu=="help" and main.ui.help.visible and not main.ui.supply.visible and not main.ui.menu.visible and main.session.clock.elapsed==elapsed)
	mouse(Vector2(619,342))
	key(KEY_ESCAPE)
	await frames()
	check("help_restores_same_supply_popup",main.menu=="placement_supply" and main.ui.supply.visible and not main.ui.menu.visible and not main.ui.help.visible and quantity.value==17)
	check("restored_supply_inputs_and_state_clean",main.session.paused and not main._primary and not main._secondary and main.session.helpers.size()==count and main.session.seeds==seeds)
	await capture("01_supply_restored")
	for button: Node in main.ui.supply.find_children("*","Button",true,false):
		if button.text=="設置":
			mouse(button.get_global_rect().get_center())
			break
	await frames()
	main.tick(0.05)
	check("restored_supply_confirms_once",main.menu=="" and not main.ui.supply.visible and not main.ui.menu.visible and main.session.helpers.size()==count+1 and main.session.seeds==seeds-47 and main.session.helpers.back().ammo==17)
	await capture("02_after_single_placement")
	finish()

func finish() -> void:
	var failures: int=0
	for row: Dictionary in checks:
		if row.status=="FAIL": failures+=1
	var file: FileAccess=FileAccess.open(OUT+"checks.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"save_dir":TEST_SAVE,"input":"engine only; root.unfocusable=true"},"  "))
	file.close()
	if main!=null:
		main.session.close()
		main.queue_free()
	quit(0 if failures==0 else 1)
