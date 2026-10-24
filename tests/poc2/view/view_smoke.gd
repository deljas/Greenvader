extends SceneTree
## Focus-safe engine-input / persistence / map smoke. GPU capture uses only viewport textures.
const Main: PackedScene=preload("res://scenes/poc2.tscn")
const Save: GDScript=preload("res://scripts/poc2/save/poc2_save.gd")
const Coords: GDScript=preload("res://scripts/poc/poc_coords.gd")
const Equivalent: GDScript=preload("res://tests/poc2/view/equivalence.gd")
const OUT: String="res://evidence/poc2/view/"
var main: Node
var checks: Array[Dictionary]=[]
var gpu: bool=false

func _init() -> void:
	root.unfocusable=true
	call_deferred("run")

func check(name_: String, passed: bool, detail: String="") -> void:
	checks.append({"name":name_,"status":"PASS" if passed else "FAIL","detail":detail})
	print(checks.back())

func frames(count: int=3) -> void:
	for index: int in count: await process_frame
	if gpu: await RenderingServer.frame_post_draw

func key(code: int, pressed: bool) -> void:
	var event: InputEventKey=InputEventKey.new()
	event.physical_keycode=code
	event.keycode=code
	event.pressed=pressed
	Input.parse_input_event(event)

func click(at: Vector2) -> void:
	var event: InputEventMouseButton=InputEventMouseButton.new()
	event.position=at
	event.button_index=MOUSE_BUTTON_LEFT
	event.pressed=true
	Input.parse_input_event(event)
	var release: InputEventMouseButton=InputEventMouseButton.new()
	release.position=at
	release.button_index=MOUSE_BUTTON_LEFT
	release.pressed=false
	Input.parse_input_event(release)

func capture(tag: String) -> void:
	if not gpu: return
	await frames(4)
	var image: Image=main.render_view.get_texture().get_image()
	image.save_png(ProjectSettings.globalize_path(OUT+tag+"_world.png"))
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT+tag+"_ui.png"))
	check(tag+"_internal_resolution",image.get_size()==Vector2i(640,360))

func run() -> void:
	gpu=DisplayServer.get_name()!="headless"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	main=Main.instantiate()
	main.auto_process=false
	main.save_dir="user://poc2_view_smoke"
	root.add_child(main)
	await frames()
	check("new_entry_224",main.session.state.width==224 and main.session.state.height==224)
	check("separate_save_namespace",Save.DEFAULT_DIR=="user://poc2_saves")
	var before: Vector2=main.session.position
	key(KEY_D,true)
	await frames(1)
	main.tick(0.15)
	key(KEY_D,false)
	await frames(1)
	check("engine_key_moves",main.session.position!=before)
	main.session.position=before
	# Small display fixture uses public placement methods in existing safe grass.
	for kind: String in main.session.CATALOG: main.session.unlocked[kind]=true
	main.session.seeds=600
	var clover: Dictionary=main.session.place_plant("clover",Vector2i(182,184))
	var carrot: Dictionary=main.session.place_plant("carrot",Vector2i(184,184))
	var army: Dictionary=main.session.place_helper("army",Vector2i(187,184))
	var gat: Dictionary=main.session.place_helper("gatlinger",Vector2i(190,184),20)
	var sprinkler: Dictionary=main.session.place_helper("sprinkler",Vector2i(193,184))
	check("display_fixture_places",clover.ok and carrot.ok and army.ok and gat.ok and sprinkler.ok)
	for helper: Dictionary in main.session.helpers:
		helper.hp-=10.0
		if helper.kind=="sprinkler": helper.water=40.0
	main.tick(0.1)
	main._placement_kind="watermelon"
	main.cursor_known=true
	main.cursor=main.world.camera.unproject_position(Coords.ground3(Coords.cell_center_ground(Vector2i(198,185))))
	main.tick(0.0)
	check("watermelon_preview_3x4",main.world.marker.scale.is_equal_approx(Vector3(1.2,0.06,1.6)))
	main._placement_kind=""
	main.tick(0.0)
	await capture("01_play")
	var elapsed: float=main.session.clock.elapsed
	key(KEY_M,true); key(KEY_M,false)
	await frames(2)
	main.tick(0.25)
	check("map_stops_clock",main.ui.map.expanded and main.session.clock.elapsed==elapsed)
	await capture("02_map")
	var map: Control=main.ui.map
	map.zoom=4
	map.map_center=main.session.position
	map.refresh_terrain()
	map.selected_id=gat.id
	map.selected_helper=true
	map.update_buttons()
	await frames()
	var selected: Dictionary=map.selected()
	var home: Vector2=selected.home
	var old_ammo: int=selected.ammo
	map.open_popup("supply")
	await frames()
	map.quantity.value=5
	var frozen_position: Vector2=selected.pos
	var popup_click: InputEventMouseButton=InputEventMouseButton.new()
	popup_click.position=map.popup.position+Vector2(8,8)
	popup_click.button_index=MOUSE_BUTTON_LEFT
	popup_click.pressed=true
	map.handle_click(popup_click)
	check("popup_does_not_move",selected.home==home)
	map.confirm_popup()
	check("supply_exact",selected.ammo==old_ammo+5)
	check("map_commands_do_not_advance",selected.pos==frozen_position and main.session.clock.elapsed==elapsed)
	map.open_popup("remove")
	await capture("03_remove_confirmation")
	map.popup.hide()
	map.zoom=4
	map.map_center=main.session.position
	map.refresh_terrain()
	map.selected_id=gat.id
	map.selected_helper=true
	map.update_buttons()
	var destination: Vector2=Coords.cell_center_logic(Vector2i(201,191))
	var event: InputEventMouseButton=InputEventMouseButton.new()
	event.position=map.point(destination)
	event.button_index=MOUSE_BUTTON_LEFT
	event.pressed=true
	map.handle_click(event)
	check("map_move_order_queued",selected.home!=home and selected.pos==frozen_position)
	# Save/load uses full backend snapshots. Current active instance is never mutated by a failed load.
	var save1: Dictionary=Save.save_game(main.session,main.save_dir)
	var loaded: Dictionary=Save.load_game(main.save_dir)
	check("save_load_full_state",save1.ok and loaded.ok and Equivalent.same(loaded.session.to_dict(),main.session.to_dict()))
	if loaded.ok: loaded.session.close()
	var saved2: Dictionary=Save.save_game(main.session,main.save_dir)
	check("backup_created",saved2.ok and FileAccess.file_exists(main.save_dir.path_join(Save.FILE_NAME)+".bak"))
	var snapshot: Dictionary=main.session.to_dict()
	var broken: FileAccess=FileAccess.open(main.save_dir.path_join(Save.FILE_NAME),FileAccess.WRITE)
	if broken!=null:
		broken.store_string("{broken")
		broken.close()
	var invalid: Dictionary=Save.load_game(main.save_dir)
	check("invalid_load_preserves_active",not invalid.ok and main.session.to_dict()==snapshot)
	var backup: Dictionary=Save.load_game(main.save_dir,true)
	check("backup_readable",backup.ok)
	if backup.ok: backup.session.close()
	main.ui.map.set_expanded(false)
	main.session.paused=false
	var old_light: int=main.world.light_updates
	main.world.sync(0.0)
	main.world.sync(0.0)
	check("sun_not_rewritten_each_frame",main.world.light_updates==old_light)
	# Find a real building occluder from the placed scene, without any OS cursor operations.
	if main.world.placement_view!=null:
		var holder: Node3D=main.world.placement_view.holders.values()[0]
		main.session.position=Coords.ground_to_logic(Vector2(holder.position.x-1.5,holder.position.z-1.5))
		main.session.set_aim(main.session.position+Vector2(20,0))
		main.world.sync(0.3)
		await capture("04_occlusion")
	checks.append({"name":"physical_keyboard_OS_route","status":"NOT_RUN","detail":"User manual verification only"})
	if not gpu: checks.append({"name":"GPU_render","status":"NOT_RUN","detail":"Headless run"})
	var result_file: FileAccess=FileAccess.open(OUT+"checks.json",FileAccess.WRITE)
	result_file.store_string(JSON.stringify({"gpu":gpu,"checks":checks},"  "))
	result_file.close()
	var failures: int=0
	for row: Dictionary in checks:
		if row.status=="FAIL": failures+=1
	main.session.close()
	main.queue_free()
	await frames(1)
	quit(0 if failures==0 else 1)




