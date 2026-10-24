extends SceneTree
const Session: GDScript = preload("res://scripts/poc2/poc2_session.gd")
const Save: GDScript = preload("res://scripts/poc2/save/poc2_save.gd")
const Equal: GDScript = preload("res://tests/poc2/view/equivalence.gd")
const Coords: GDScript = preload("res://scripts/poc/poc_coords.gd")
const OUT: String = "res://evidence/poc3/independent/"
var rows: Array[Dictionary] = []

func _init() -> void:
	call_deferred("run")

func check(id: String, ok: bool, detail: Variant = "") -> void:
	rows.append({"id":id,"status":"PASS" if ok else "FAIL","detail":detail})
	print(JSON.stringify(rows.back()))

func logic() -> bool:
	var s: RefCounted = Session.new()
	s.position = Vector2(461.9998,418.0002)
	var target: Vector2 = Vector2(462,414)
	var offset: Vector2 = target-s.position
	s.walk(Coords.ground_dir_to_screen(offset.normalized()),offset.length()/48.0)
	check("FORMER_NORTH_STEP9_NOW_PASSES",s.position.distance_to(target)<0.01,str(s.position))
	s.position = Vector2(450,418)
	s.walk(Coords.ground_dir_to_screen(Vector2.UP),0.125)
	check("WATER_CONTACT_REMAINS_BLOCKED",s.position.is_equal_approx(Vector2(450,418)),str(s.position))
	s.close()
	s = Session.new()
	var a: Dictionary = s.place_plant("clover",Vector2i(112,112))
	var b: Dictionary = s.place_plant("clover",Vector2i(113,112))
	s.unlocked.sprinkler = true # Save-combination fixture, not an unlock-journey claim.
	var helper: Dictionary = s.place_helper("sprinkler",Vector2i(112,113))
	if not a.ok or not b.ok or not helper.ok:
		check("COMPOSITE_FIXTURE",false)
		s.close()
		return true
	s.water_at(s.plants[0].pos)
	s.set_favorite(1,"sprinkler")
	s.adjust_sow_width(1)
	s.advance_game(0.75)
	var original: Dictionary = s.to_dict()
	var saved: Dictionary = Save.save_game(s)
	var loaded: Dictionary = Save.load_game()
	check("FINAL_COMPOSITE_JSON_FULL_EQUAL",saved.ok and loaded.ok and Equal.same(original,loaded.session.to_dict()) if loaded.ok else false)
	if loaded.ok:
		var peer: RefCounted = loaded.session
		check("HISTORICAL_PAID_WATER_FAVORITE_WIDTH_NO_OFFLINE",peer.plants[0].cost==10 and peer.plants[1].cost==11 and peer.plants[0].watered and peer.favorites[1]=="sprinkler" and peer.sow_width==3 and peer.clock.elapsed==s.clock.elapsed and peer.plants[0].age==s.plants[0].age)
		s.advance_game(0.5)
		peer.advance_game(0.5)
		check("SAME_TICKS_AFTER_FINAL_RESTORE",Equal.same(s.to_dict(),peer.to_dict()))
		peer.close()
	else:
		check("HISTORICAL_PAID_WATER_FAVORITE_WIDTH_NO_OFFLINE",false,"load failed")
		check("SAME_TICKS_AFTER_FINAL_RESTORE",false,"load failed")
	s.close()
	return true

func tap(code: int) -> void:
	for pressed: bool in [true,false]:
		var e: InputEventKey = InputEventKey.new()
		e.keycode=code
		e.physical_keycode=code
		e.pressed=pressed
		root.push_input(e,true)
	await process_frame

func main_path() -> bool:
	change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene"))
	for index: int in 3: await process_frame
	var main: Node = current_scene
	main.auto_process=false
	main._audio_changed(true,0.0)
	main._on_action("new")
	var owned: RefCounted = main.session
	await tap(KEY_E)
	var stopped_at: float = owned.clock.elapsed
	main.tick(0.25)
	check("NORMAL_ENTRY_LIST_STOPS_TIME",main.menu=="plants" and owned.paused and owned.clock.elapsed==stopped_at)
	var click: InputEventMouseButton = InputEventMouseButton.new()
	click.position=Vector2(320,180)
	click.global_position=click.position
	click.button_index=MOUSE_BUTTON_LEFT
	click.pressed=true
	root.push_input(click,true)
	await tap(KEY_E)
	var balance: int = owned.seeds
	main.tick(0.25)
	check("FINAL_UI_HELD_PRESS_DOES_NOT_FIRE",main.menu=="" and not main._primary and owned.shots.is_empty() and owned.seeds==balance)
	click.pressed=false
	root.push_input(click,true)
	main.free() # Exercise normal _exit_tree; do not manually close the owned session.
	check("NORMAL_EXIT_RELEASES_SYSTEM_OWNERSHIP",owned.combat_system.s==null and owned.plant_system.s==null and not owned.state.tile_listener.is_valid() and owned.clock.growth_ticked.get_connections().is_empty() and owned.clock.spread_ticked.get_connections().is_empty())
	return true

func run() -> void:
	if not OS.get_cmdline_user_args().has("--final-freeze-authorized") or not OS.get_user_data_dir().replace("\\","/").contains("evidence/poc3/independent/profile/"):
		quit(2)
		return
	if logic()!=true: check("logic_completed",false,"runtime abort")
	if await main_path()!=true: check("main_completed",false,"runtime abort")
	var failures: int = 0
	for row: Dictionary in rows:
		if row.status=="FAIL": failures+=1
	var file: FileAccess = FileAccess.open(OUT+"final_results.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":rows,"failures":failures,"engine":Engine.get_version_info(),"user_dir":OS.get_user_data_dir()},"  "))
	file.close()
	quit(1 if failures else 0)
