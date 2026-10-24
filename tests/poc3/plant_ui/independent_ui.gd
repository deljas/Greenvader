extends SceneTree
## Nine focused acceptance scenarios, engine input only; no independent GPU run.
const Session: GDScript = preload("res://scripts/poc2/poc2_session.gd")
const Ui: GDScript = preload("res://scripts/poc2/ui/poc2_ui.gd")
const Row: GDScript = preload("res://scripts/poc2/ui/plant_list_row.gd")
const Save: GDScript = preload("res://scripts/poc2/save/poc2_save.gd")
const Coords: GDScript = preload("res://scripts/poc/poc_coords.gd")
const OUT: String = "res://evidence/poc3/plant_ui/independent/results.json"
var checks: Array[Dictionary] = []
var pointer: Vector2 = Vector2.ZERO
var main: Node

func _init() -> void:
	call_deferred("_run")

func _check(name: String, ok: bool, observations: Dictionary = {}) -> void:
	checks.append({"name":name,"status":"PASS" if ok else "FAIL","observations":observations})
	print(JSON.stringify(checks.back()))

func _frames(count: int = 2) -> void:
	for index: int in count: await process_frame

func _motion(at: Vector2, held: bool = false) -> void:
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.position = at
	event.global_position = at
	event.relative = at-pointer
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	pointer = at
	root.push_input(event,true)

func _button(at: Vector2, pressed: bool, which: int = MOUSE_BUTTON_LEFT) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.position = at
	event.global_position = at
	event.button_index = which
	event.pressed = pressed
	root.push_input(event,true)

func _click(at: Vector2) -> void:
	_motion(at)
	_button(at,true)
	await _frames(1)
	_button(at,false)
	await _frames()

func _key(code: int) -> void:
	for pressed: bool in [true,false]:
		var event: InputEventKey = InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		root.push_input(event,true)
	await _frames()

func _run() -> void:
	var profile: String = OS.get_user_data_dir().replace("\\", "/")
	if DisplayServer.get_name() != "headless" or not profile.begins_with("C:/godot/greenvader/evidence/poc3/plant_ui/independent/profile/"):
		quit(2)
		return
	var report: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(OUT))
	var production: RefCounted = Session.new()
	var placed_ok: bool = true
	for cell: Vector2i in [Vector2i(181,184),Vector2i(183,184),Vector2i(185,184)]:
		placed_ok = production.place_plant("clover",cell).get("ok",false) and placed_ok
	if placed_ok:
		for index: int in 2:
			production.plants[index].mature = true
			production.plants[index].age = 20.0
	var income_before: float = production.income_fraction
	production.advance_game(1.0)
	var stats: Dictionary = production.plant_stats("clover")
	_check("immature_count_and_mature_actual_income", placed_ok and stats.count == 3 and absf(stats.rate_per_second-0.0666666666666667) < 0.000001 and absf(production.crop_rate()-4.0) < 0.000001 and absf(production.income_fraction-income_before-0.15) < 0.000001 and not production.plants[2].mature, {"stats":stats,"crop_per_minute":production.crop_rate(),"income_in_one_second":production.income_fraction-income_before})
	var sample_ui: Control = Ui.new()
	root.add_child(sample_ui)
	sample_ui.bind(production)
	var entry: Dictionary = sample_ui.list_rows()[0]
	var row: Button = Row.new()
	root.add_child(row)
	row.set_data(entry)
	_check("production_digits_nonproducer_and_hover", Row.production_text(0.5) == "+0.500 ●/s" and Row.production_text(1.0) == "+1.00 ●/s" and Row.production_text(100.0) == "+100.0 ●/s" and Row.production_text(0.0,false) == "—" and row.columns[2].text == "3" and row.columns[3].text == "+0.067 ●/s" and row.detail.contains("成熟1株") and row.detail.contains("+0.033 ●/s"), {"count_column":row.columns[2].text,"rate_column":row.columns[3].text,"hover":row.detail})
	row.free()
	sample_ui.free()
	production.close()
	change_scene_to_file(str(ProjectSettings.get_setting("application/run/main_scene")))
	await _frames(3)
	main = current_scene
	main.auto_process = false
	main.muted = true
	root.notify_mouse_entered()
	main._on_action("new")
	var only_unlocked: bool = main.ui.list_rows().size() == 1 and main.ui.list_rows()[0].kind == "clover"
	for kind: String in main.session.CATALOG: main.session.unlocked[kind] = true
	var order: Array[String] = []
	for item: Dictionary in main.ui.list_rows(): order.append(item.kind)
	_check("unlocked_only_and_literal_rank_order", only_unlocked and order == ["clover","carrot","army","wheat","gatlinger","sprinkler","rafflesia","watermelon"], {"initial_only_clover":only_unlocked,"order":order})
	main.session.set_favorite(1,"clover")
	await _key(KEY_1)
	var selected_first: bool = main.ui.selected_slot == 0
	await _key(KEY_1)
	var deselected: bool = main.ui.selected_slot == -1 and main._placement_kind == ""
	await _key(KEY_1)
	await _key(KEY_2)
	main.ui.refresh()
	_check("five_slots_identity_selection_and_hud", main.ui.favorite_buttons.size() == 5 and selected_first and deselected and main.ui.selected_slot == 1 and main._placement_kind == "clover" and main.ui.status.text.contains("●10") and main.ui.economy.text.contains("●60") and main.ui.hp_bar.value == 100.0 and main.ui.water_bar.value == 100.0)
	await _key(KEY_E)
	var list: Control = main.ui.plant_list
	var before_pause: float = main.session.clock.elapsed
	main.tick(0.25)
	var paused: bool = main.menu == "plants" and main.session.paused and main.session.clock.elapsed == before_pause
	await _key(KEY_4)
	var number_blocked: bool = main.ui.selected_slot == 1
	await _click(list.rows.carrot.get_global_rect().get_center())
	var holding_without_placement: bool = list.held_kind == "carrot" and main._placement_kind == "clover"
	await _click(list.slots[1].get_global_rect().get_center())
	_check("list_pause_hold_overwrite_clears_old_selection", paused and number_blocked and holding_without_placement and main.session.favorites[1] == "carrot" and list.held_kind == "" and main.ui.selected_slot == -1 and main._placement_kind == "", {"pause":paused,"numbers_blocked":number_blocked,"hold_not_placement":holding_without_placement})
	var favorites_before: Array[String] = main.session.favorites.duplicate()
	await _click(list.rows.army.get_global_rect().get_center())
	var held_before_cancel: bool = list.held_kind == "army"
	_button(pointer,true,MOUSE_BUTTON_RIGHT)
	await _frames()
	_check("right_cancel_on_child_button_preserves_slots", held_before_cancel and list.held_kind == "" and list.visible and main.session.favorites == favorites_before)
	var water_before: float = main.session.water
	await _key(KEY_E)
	_motion(Vector2(350,270))
	main.tick(0.25)
	var right_no_leak: bool = not main._secondary and not main._primary and main.session.water == water_before and main.session.shots.is_empty()
	_button(pointer,false,MOUSE_BUTTON_RIGHT)
	await _key(KEY_E)
	var source: Vector2 = list.rows.clover.get_global_rect().get_center()
	var destination: Vector2 = list.slots[4].get_global_rect().get_center()
	_motion(source)
	_button(source,true)
	_motion(source+Vector2(15,3),true)
	await _frames()
	_motion(destination,true)
	await _frames()
	var dragging: bool = root.gui_is_dragging()
	_button(destination,false)
	await _frames()
	_check("representative_engine_drag_drop", dragging and main.session.favorites[4] == "clover" and list.held_kind == "", {"engine_dragging_before_release":dragging,"slot5":main.session.favorites[4]})
	source = list.rows.clover.get_global_rect().get_center()
	_motion(source)
	_button(source,true)
	await _key(KEY_E)
	_motion(Vector2(350,270),true)
	var seeds_before: int = main.session.seeds
	main.tick(0.25)
	var left_no_leak: bool = not main._primary and main.session.shots.is_empty() and main.session.seeds == seeds_before
	_button(pointer,false)
	await _frames()
	_check("held_list_clicks_do_not_leak_after_close", right_no_leak and left_no_leak and main.menu == "" and not main.session.paused, {"right_no_leak":right_no_leak,"left_no_leak":left_no_leak})
	var expected_favorites: Array[String] = main.session.favorites.duplicate()
	var saved: Dictionary = Save.save_game(main.session,"user://independent_favorites")
	var loaded: Dictionary = Save.load_game("user://independent_favorites")
	var roundtrip: bool = loaded.get("ok",false) and loaded.session.favorites == expected_favorites
	if loaded.get("ok",false): loaded.session.close()
	var before_invalid: String = JSON.stringify(main.session.to_dict(),"",true,true)
	var invalid: Dictionary = main.session.to_dict().duplicate(true)
	invalid.values.favorites[2] = 9
	var rejected: Dictionary = main.session.restore(invalid)
	var intact: bool = before_invalid == JSON.stringify(main.session.to_dict(),"",true,true)
	var old: Dictionary = main.session.to_dict().duplicate(true)
	old.values.erase("favorites")
	var compatible: RefCounted = Session.new()
	var compatible_result: Dictionary = compatible.restore(old)
	var defaulted: bool = compatible_result.get("ok",false) and compatible.favorites == ["clover","","","",""]
	compatible.close()
	_check("favorites_storage_rejection_and_old_default", saved.get("ok",false) and roundtrip and not rejected.get("ok",false) and intact and defaulted, {"save_ok":saved.get("ok",false),"roundtrip":roundtrip,"invalid_rejected":not rejected.get("ok",false),"active_unchanged":intact,"missing_defaults":defaulted})
	main.session.close()
	var failures: int = 0
	for item: Dictionary in checks:
		if item.status == "FAIL": failures += 1
	report["checks"] = checks
	report["failures"] = failures
	report["user_data"] = profile
	report["godot"] = Engine.get_version_info()
	report["input"] = "Headless Viewport.push_input; no OS input"
	report["not_run"] = ["independent_gpu_native_physical_input", "wide_regression_long_play", "all_sizes_lighting_exported_build"]
	var file: FileAccess = FileAccess.open(OUT,FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	quit(0 if failures == 0 else 1)
