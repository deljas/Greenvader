extends SceneTree
## Repeat only the reported transient-camera scenario and its storage side effects.
const Session: GDScript = preload("res://scripts/poc2/poc2_session.gd")
const Map: GDScript = preload("res://scripts/poc2/ui/map_ui.gd")
const Save: GDScript = preload("res://scripts/poc2/save/poc2_save.gd")
const Geometry: GDScript = preload("res://scripts/poc2/view/camera_geometry.gd")
const Coords: GDScript = preload("res://scripts/poc/poc_coords.gd")
const OUT: String = "res://evidence/poc3/map_info/independent/memory_fix_results.json"
var checks: Array[Dictionary] = []

func _init() -> void:
	call_deferred("_run")

func _check(name: String, ok: bool) -> void:
	checks.append({"name": name, "status": "PASS" if ok else "FAIL"})

func _run() -> void:
	var profile: String = OS.get_user_data_dir().replace("\\", "/")
	if DisplayServer.get_name() != "headless" or not profile.begins_with("C:/godot/greenvader/evidence/poc3/map_info/independent/profile/"):
		quit(2)
		return
	var report: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(OUT))
	var s: RefCounted = Session.new()
	var fixed: Dictionary = s.nests[0].duplicate(true)
	fixed.id = s.allocate_id()
	fixed.discovered = false
	fixed.active = false
	fixed.status = "dormant"
	fixed.last_contact = -100.0
	s.nests.assign([fixed])
	s.enemies.clear()
	s.fossils.clear()
	s.position = Vector2(400,400)
	var viewport: SubViewport = SubViewport.new()
	viewport.size = Vector2i(640,360)
	root.add_child(viewport)
	var camera: Camera3D = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.size = 18.5
	camera.near = 0.05
	camera.far = 150.0
	viewport.add_child(camera)
	camera.current = true
	camera.transform = Geometry.transform_for(s.position)
	await process_frame
	var origin: Vector3 = camera.project_ray_origin(Vector2(642,180))
	var direction: Vector3 = camera.project_ray_normal(Vector2(642,180))
	var ground: Vector3 = origin + direction * (-origin.y/direction.y)
	fixed.pos = Coords.ground_to_logic(Vector2(ground.x,ground.z))
	fixed.home = fixed.pos
	var fossil: Dictionary = {"id": s.allocate_id(), "kind": "fossil", "pos": fixed.pos, "unlock": "carrot", "found": false, "discovered": false, "nest_id": -1}
	s.fossils.append(fossil)
	var ui: Control = Map.new()
	ui.session = s
	s.advance(0.05)
	var initial_hidden: bool = ui.icon_style("nests",fixed).is_empty() and ui.icon_style("fossils",fossil).is_empty() and not fixed.discovered and not fossil.discovered
	var terrain_visible: PackedByteArray = s.visible.duplicate()
	var terrain_known: PackedByteArray = s.known.duplicate()
	var entering: Vector2 = s.walk(Vector2.RIGHT,0.1)
	s.advance(0.1)
	var nest_at_entry: Dictionary = ui.icon_style("nests",fixed)
	var fossil_at_entry: Dictionary = ui.icon_style("fossils",fossil)
	var both_recorded_on_entry: bool = fixed.discovered and fossil.discovered
	var leaving: Vector2 = s.walk(Vector2.LEFT,0.1)
	s.advance(0.1)
	var nest_after: Dictionary = ui.icon_style("nests",fixed)
	var fossil_after: Dictionary = ui.icon_style("fossils",fossil)
	var crossed: bool = initial_hidden and entering.length() > 0.0 and leaving.length() > 0.0 and not s.detected(fixed.pos)
	_check("fixed_nest_transient_display_is_remembered", crossed and both_recorded_on_entry and nest_at_entry.get("shape") == "square" and nest_after.get("shape") == "square" and nest_after.color.get_luminance() < nest_at_entry.color.get_luminance())
	_check("exploration_fossil_transient_display_is_remembered", crossed and both_recorded_on_entry and fossil_at_entry.get("shape") == "fossil" and fossil_after.get("shape") == "fossil" and fossil.discovered)
	_check("periodic_terrain_and_collection_activation_unchanged", s.clock.elapsed < s.reveal_at and s.visible == terrain_visible and s.known == terrain_known and not fossil.found and not s.unlocked.get("carrot",false) and not fixed.active and fixed.status == "dormant" and s.enemies.is_empty())
	var saved: Dictionary = Save.save_game(s,"user://memory_fix_checkpoint")
	var loaded: Dictionary = Save.load_game("user://memory_fix_checkpoint")
	var roundtrip: bool = false
	if loaded.get("ok",false):
		var restored: RefCounted = loaded.session
		var restored_ui: Control = Map.new()
		restored_ui.session = restored
		roundtrip = restored.nests[0].discovered and restored.fossils[0].discovered and not restored.fossils[0].found and not restored.unlocked.get("carrot",false) and not restored.nests[0].active and not restored_ui.icon_style("nests",restored.nests[0]).is_empty() and not restored_ui.icon_style("fossils",restored.fossils[0]).is_empty()
		restored_ui.free()
		restored.close()
	_check("transient_memories_save_restore_without_collection_or_activation", saved.get("ok",false) and loaded.get("ok",false) and roundtrip)
	report["observations"] = {"target": str(fixed.pos), "initial_hidden": initial_hidden, "both_recorded_on_entry": both_recorded_on_entry, "entering_move": str(entering), "leaving_move": str(leaving), "elapsed": s.clock.elapsed, "reveal_at": s.reveal_at, "save_ok": saved.get("ok",false), "load_ok": loaded.get("ok",false)}
	ui.free()
	viewport.queue_free()
	await process_frame
	s.close()
	var failures: int = 0
	for check: Dictionary in checks:
		print(JSON.stringify(check))
		if check.status == "FAIL": failures += 1
	report["checks"] = checks
	report["failures"] = failures
	report["user_data"] = profile
	report["godot"] = Engine.get_version_info()
	report["not_run"] = ["independent_gpu_native_input", "wide_regression_long_play", "all_lighting_sizes_exported_build"]
	var file: FileAccess = FileAccess.open(OUT,FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	quit(0 if failures == 0 else 1)
