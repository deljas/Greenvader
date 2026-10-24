extends SceneTree
## Targeted follow-up only: save float comparison, wheel input, disposed display nodes.
const Main: PackedScene=preload("res://scenes/poc2.tscn")
const Save: GDScript=preload("res://scripts/poc2/save/poc2_save.gd")
const Equivalent: GDScript=preload("res://tests/poc2/view/equivalence.gd")
const Coords: GDScript=preload("res://scripts/poc/poc_coords.gd")
var main: Node
var checks: Array[Dictionary]=[]
func _init() -> void:
	root.unfocusable=true
	call_deferred("run")
func check(name_: String, passed: bool) -> void:
	checks.append({"name":name_,"status":"PASS" if passed else "FAIL"})
	print(checks.back())
func frames() -> void:
	for i: int in 3: await process_frame
	await RenderingServer.frame_post_draw
func wheel(at: Vector2) -> void:
	var event: InputEventMouseButton=InputEventMouseButton.new()
	event.position=root.get_final_transform()*at
	event.button_index=MOUSE_BUTTON_WHEEL_UP
	event.pressed=true
	Input.parse_input_event(event)
func run() -> void:
	main=Main.instantiate()
	main.auto_process=false
	root.add_child(main)
	await frames()
	main.session.advance_game(0.35)
	main.world.sync(0.0)
	main.ui.map.set_expanded(true)
	wheel(main.ui.map.point(main.session.position))
	await frames()
	check("engine_wheel_zoom",main.ui.map.zoom==2)
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://evidence/poc2/view/05_engine_zoom_ui.png"))
	var before: Dictionary=main.session.to_dict()
	var directory: String="user://poc2_view_followup"
	var saved: Dictionary=Save.save_game(main.session,directory)
	var loaded: Dictionary=Save.load_game(directory)
	check("save_roundtrip_structure_and_values",saved.ok and loaded.ok and Equivalent.same(before,loaded.session.to_dict()))
	if loaded.ok: loaded.session.close()
	var file: FileAccess=FileAccess.open(directory.path_join(Save.FILE_NAME),FileAccess.WRITE)
	if file!=null:
		file.store_string("{broken")
		file.close()
	var invalid: Dictionary=Save.load_game(directory)
	check("corrupt_load_quiet_and_preserves",not invalid.ok and Equivalent.same(before,main.session.to_dict()))
	check("income_tooltip_hover_enabled",main.ui.status.mouse_filter!=Control.MOUSE_FILTER_IGNORE)
	main.ui.map.set_expanded(false)
	main.session.paused=false
	check("income_hover_blocks_shoot",main.ui.blocks(main.ui.status.position+Vector2(2,2)))
	main.session.set_aim(main.session.position+Vector2(40,0))
	var shot: Dictionary=main.session.fire()
	main.world.sync(0.0)
	var id: int=main.session.shots.back().id if shot.ok else -1
	check("shot_view_exists",main.world.entities.has("shots"+str(id)))
	main.session.shots.clear()
	main.world.sync(0.0)
	check("disposed_shot_view_erased",not main.world.entities.has("shots"+str(id)))
	var enemy: Dictionary=main.session.enemies[0]
	enemy.pos=main.session.position+Vector2(8,8)
	main.session.reveal()
	main.world.sync(0.0)
	var key: String="enemies"+str(enemy.id)
	main.session.visible.fill(0)
	main.world.sync(0.0)
	check("living_unseen_enemy_kept_hidden",main.world.entities.has(key) and not main.world.entities[key].visible)
	var holder: Node3D=main.world.placement_view.holders.values()[0]
	main.session.position=Coords.ground_to_logic(Vector2(holder.position.x-1.5,holder.position.z-1.5))
	main.world.sync(0.3)
	check("cutaway_engaged",not main.world.occlusion.records.is_empty())
	await frames()
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://evidence/poc2/view/06_cutaway_ui.png"))
	var result_file: FileAccess=FileAccess.open("res://evidence/poc2/view/followup_checks.json",FileAccess.WRITE)
	result_file.store_string(JSON.stringify(checks,"  "))
	result_file.close()
	var failures: int=0
	for row: Dictionary in checks:
		if row.status=="FAIL": failures+=1
	main.session.close()
	main.queue_free()
	await frames()
	quit(0 if failures==0 else 1)

