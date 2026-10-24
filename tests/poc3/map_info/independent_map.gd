extends SceneTree
## Independent scenario expectations from POC3-MAP-INFO; headless and isolated.
const Session: GDScript = preload("res://scripts/poc2/poc2_session.gd")
const Map: GDScript = preload("res://scripts/poc2/ui/map_ui.gd")
const Save: GDScript = preload("res://scripts/poc2/save/poc2_save.gd")
const Geometry: GDScript = preload("res://scripts/poc2/view/camera_geometry.gd")
const Coords: GDScript = preload("res://scripts/poc/poc_coords.gd")
const OUT: String = "res://evidence/poc3/map_info/independent/results.json"
var checks: Array[Dictionary] = []

func _init() -> void:
	call_deferred("_run")

func _check(name: String, ok: bool, observations: Dictionary = {}) -> void:
	checks.append({"name": name, "status": "PASS" if ok else "FAIL", "observations": observations})

func _snapshot(session: RefCounted) -> String:
	return JSON.stringify(session.to_dict(), "", true, true)

func _limited_followup() -> void:
	var report: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(OUT))
	var initial_file: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("user://poc3_saves/slot1.json"))
	var diagnosis: RefCounted = Session.new()
	var original_reason: Dictionary = diagnosis.restore(initial_file.state)
	diagnosis.close()
	# Use a normal unmodified world for persistence, with discovery from helpers.
	var valid: RefCounted = Session.new()
	var nest: Dictionary = valid.nests[0]
	var fossil: Dictionary = {}
	for item: Dictionary in valid.fossils:
		if int(item.nest_id) < 0:
			fossil = item
			break
	valid.helpers.append({"id": valid.allocate_id(), "pos": nest.pos, "hp": 20.0})
	valid.helpers.append({"id": valid.allocate_id(), "pos": fossil.pos, "hp": 20.0})
	valid.reveal()
	valid.helpers.clear()
	var saved: Dictionary = Save.save_game(valid,"user://valid_memory")
	var loaded: Dictionary = Save.load_game("user://valid_memory")
	var memory_restored: bool = false
	if loaded.get("ok",false):
		var restored: RefCounted = loaded.session
		var remembered_fossil: bool = false
		for item: Dictionary in restored.fossils:
			if item.id == fossil.id: remembered_fossil = item.discovered and not item.found
		memory_restored = restored.nests[0].discovered and remembered_fossil and not restored.unlocked.get(String(fossil.unlock),false)
		restored.close()
	var earlier: Dictionary = valid.to_dict().duplicate(true)
	for item: Dictionary in earlier.entities.nests: item.erase("discovered")
	for item: Dictionary in earlier.entities.fossils: item.erase("discovered")
	var compatibility: RefCounted = Session.new()
	var compatibility_result: Dictionary = compatibility.restore(earlier)
	var defaults_false: bool = compatibility_result.get("ok",false)
	if defaults_false:
		for item: Dictionary in compatibility.nests: defaults_false = defaults_false and item.discovered == false
		for item: Dictionary in compatibility.fossils: defaults_false = defaults_false and item.discovered == false
	compatibility.close()
	# Validate bad bool types against this known-valid snapshot as well.
	var active_before: String = _snapshot(valid)
	var malformed: Dictionary = valid.to_dict().duplicate(true)
	malformed.entities.nests[0].discovered = "yes"
	var bad_nest: Dictionary = valid.restore(malformed)
	var invalid_preserved: bool = not bad_nest.get("ok",false) and _snapshot(valid) == active_before
	malformed = valid.to_dict().duplicate(true)
	malformed.entities.fossils[0].discovered = 1
	var bad_fossil: Dictionary = valid.restore(malformed)
	invalid_preserved = invalid_preserved and not bad_fossil.get("ok",false) and _snapshot(valid) == active_before
	valid.close()
	# One normal movement/time scenario: briefly cross the real camera edge between reveals.
	var race: RefCounted = Session.new()
	var fixed: Dictionary = race.nests[0].duplicate(true)
	fixed.discovered = false
	race.nests.assign([fixed])
	race.enemies.clear()
	race.fossils.clear()
	race.position = Vector2(400,400)
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
	camera.transform = Geometry.transform_for(race.position)
	await process_frame
	var ray_origin: Vector3 = camera.project_ray_origin(Vector2(642,180))
	var ray_direction: Vector3 = camera.project_ray_normal(Vector2(642,180))
	var ground: Vector3 = ray_origin + ray_direction * (-ray_origin.y/ray_direction.y)
	fixed.pos = Coords.ground_to_logic(Vector2(ground.x,ground.z))
	fixed.home = fixed.pos
	race.advance(0.05)
	var map: Control = Map.new()
	map.session = race
	var hidden_initially: bool = map.icon_style("nests",fixed).is_empty()
	var entering_move: Vector2 = race.walk(Vector2.RIGHT,0.1)
	race.advance(0.1)
	var displayed: bool = not map.icon_style("nests",fixed).is_empty()
	var discovered_while_displayed: bool = fixed.discovered
	var leaving_move: Vector2 = race.walk(Vector2.LEFT,0.1)
	race.advance(0.1)
	var remembered_after: bool = not map.icon_style("nests",fixed).is_empty()
	var exercised: bool = hidden_initially and displayed and entering_move.length() > 0.0 and leaving_move.length() > 0.0 and not race.detected(fixed.pos)
	var race_result: Dictionary = {"status": "PASS" if exercised and remembered_after else ("FAIL" if exercised else "NOT_RUN"), "initially_hidden": hidden_initially, "displayed_between_reveals": displayed, "discovered_while_displayed": discovered_while_displayed, "remembered_after_leaving": remembered_after, "elapsed": race.clock.elapsed, "next_reveal_at": race.reveal_at, "entering_move": str(entering_move), "leaving_move": str(leaving_move), "target": str(fixed.pos)}
	map.free()
	viewport.queue_free()
	await process_frame
	race.close()
	report["limited_followup"] = {"original_fixture_restore_result": original_reason, "normal_world_save_load_memory": saved.get("ok",false) and loaded.get("ok",false) and memory_restored, "normal_world_missing_discovery_defaults_false": defaults_false, "invalid_bool_rechecked_on_valid_state": invalid_preserved, "transient_camera_detection": race_result}
	var file: FileAccess = FileAccess.open(OUT,FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	print(JSON.stringify(report.limited_followup))
	quit(1 if race_result.status == "FAIL" or not memory_restored or not defaults_false or not invalid_preserved else 0)

func _run() -> void:
	var profile: String = OS.get_user_data_dir().replace("\\", "/")
	if DisplayServer.get_name() != "headless" or not profile.begins_with("C:/godot/greenvader/evidence/poc3/map_info/independent/profile/"):
		push_error("Headless isolated MAP-INFO profile required")
		quit(2)
		return
	if OS.get_cmdline_user_args().has("--limited-followup"):
		await _limited_followup()
		return
	var report: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(OUT))
	var s: RefCounted = Session.new()
	var ui: Control = Map.new()
	ui.session = s
	var fixed: Dictionary = {}
	var mother: Dictionary = {}
	for nest: Dictionary in s.nests:
		if nest.mother: mother = nest.duplicate(true)
		elif fixed.is_empty(): fixed = nest.duplicate(true)
	var enemy: Dictionary = s.enemies[0].duplicate(true)
	enemy.id = s.allocate_id()
	enemy.pos = Vector2(162, 202) # Authoritative wasteland cell(40,50), far from camera.
	enemy.home = enemy.pos
	fixed.id = s.allocate_id()
	fixed.pos = Vector2(170, 202)
	fixed.home = fixed.pos
	fixed.discovered = false
	mother.id = s.allocate_id()
	mother.pos = Vector2(178, 202)
	mother.home = mother.pos
	mother.discovered = true # Even an adversarial stored flag must not create mother memory.
	s.enemies.assign([enemy])
	s.nests.assign([fixed, mother])
	s.fossils.clear()
	s.helpers.clear()
	s.plants.clear()
	s.shots.clear()
	s.position = Vector2(600,600)
	s.known.fill(0)
	s.reveal()
	var camera_only: Vector2 = s.position + Vector2(80,0)
	_check("camera_source_and_unseen_remote", s.detected(camera_only) and not s.detected(enemy.pos) and ui.icon_style("nests", fixed).is_empty(), {"camera_point": str(camera_only), "remote_point": str(enemy.pos)})
	var helper: Dictionary = {"id": s.allocate_id(), "pos": Vector2(122,202), "hp": 20.0}
	s.helpers.append(helper)
	s.reveal()
	var helper_detects: bool = s.detected(enemy.pos)
	var current_fixed: Dictionary = ui.icon_style("nests", fixed)
	var current_mother: Dictionary = ui.icon_style("nests", mother)
	helper.hp = 0.0
	s.reveal()
	_check("living_helper_source_only", helper_detects and not s.detected(enemy.pos), {"living_helper_detected": helper_detects, "dead_helper_detected": s.detected(enemy.pos)})
	s.helpers.clear()
	var remembered: Dictionary = ui.icon_style("nests", fixed)
	var fixed_memory: bool = fixed.discovered and current_fixed.get("shape") == "square" and remembered.get("shape") == "square" and remembered.color.get_luminance() < current_fixed.color.get_luminance()
	var mother_no_memory: bool = current_mother.get("shape") == "mother" and current_mother.shape != "dot" and ui.icon_style("nests", mother).is_empty()
	var hp_before: float = fixed.hp
	fixed.hp = 0.0
	var dead_hidden: bool = ui.icon_style("nests", fixed).is_empty()
	fixed.hp = hp_before
	_check("fixed_memory_and_mother_no_memory", fixed_memory and mother_no_memory and dead_hidden, {"fixed_memory_paler": fixed_memory, "mother_no_memory": mother_no_memory, "dead_fixed_hidden": dead_hidden})
	var enemy_index: int = s.state.index_of(40,50)
	s.state.set_stage(enemy_index, WorldState.STAGE_SPROUT1)
	s.reveal()
	var green_detects: bool = s.detected(enemy.pos) and not ui.icon_style("enemies", enemy).is_empty()
	s.state.set_stage(enemy_index, WorldState.STAGE_EMPTY)
	s.reveal()
	_check("green_source_loss_hides_enemy_but_keeps_history", green_detects and not s.detected(enemy.pos) and ui.icon_style("enemies", enemy).is_empty() and s.known[enemy_index] == 1, {"green_detected": green_detects, "known_after_loss": s.known[enemy_index]})
	var fossil: Dictionary = {"id": s.allocate_id(), "kind": "fossil", "pos": Vector2(162,282), "unlock": "carrot", "found": false, "discovered": false, "nest_id": -1}
	s.fossils.append(fossil)
	var fossil_index: int = s.state.index_of(40,70)
	s.state.set_stage(fossil_index, WorldState.STAGE_SEED)
	s.reveal()
	var seed_hidden: bool = not fossil.discovered and ui.icon_style("fossils", fossil).is_empty()
	s.state.set_stage(fossil_index, WorldState.STAGE_SPROUT1)
	s.reveal()
	var discovered_without_unlock: bool = fossil.discovered and not fossil.found and not s.unlocked.get("carrot",false) and ui.icon_style("fossils", fossil).get("shape") == "fossil"
	s.state.set_stage(fossil_index, WorldState.STAGE_EMPTY)
	s.reveal()
	var fossil_memory: bool = not s.detected(fossil.pos) and ui.icon_style("fossils", fossil).get("shape") == "fossil" and not s.unlocked.get("carrot",false)
	_check("fossil_seed_green_discovery_memory", seed_hidden and discovered_without_unlock and fossil_memory, {"seed_hidden": seed_hidden, "discovered_without_unlock": discovered_without_unlock, "memory_after_green_loss": fossil_memory})
	var checkpoint: Dictionary = s.to_dict().duplicate(true)
	var saved: Dictionary = Save.save_game(s)
	var loaded: Dictionary = Save.load_game()
	var restored_memory: bool = false
	if loaded.get("ok",false):
		var restored: RefCounted = loaded.session
		var restored_ui: Control = Map.new()
		restored_ui.session = restored
		restored_memory = restored.nests[0].discovered and restored.fossils[0].discovered and not restored.fossils[0].found and not restored.unlocked.get("carrot",false) and restored_ui.icon_style("nests",restored.nests[0]).get("shape") == "square" and restored_ui.icon_style("fossils",restored.fossils[0]).get("shape") == "fossil"
		restored_ui.free()
		restored.close()
	_check("discovery_memory_survives_save_load", saved.get("ok",false) and loaded.get("ok",false) and restored_memory, {"save_ok": saved.get("ok",false), "load_ok": loaded.get("ok",false), "remembered_without_unlock": restored_memory})
	var snapshot: String = _snapshot(s)
	var invalid_nest: Dictionary = checkpoint.duplicate(true)
	invalid_nest.entities.nests[0].discovered = "yes"
	var reject_nest: Dictionary = s.restore(invalid_nest)
	var nest_unchanged: bool = _snapshot(s) == snapshot
	var invalid_fossil: Dictionary = checkpoint.duplicate(true)
	invalid_fossil.entities.fossils[0].discovered = 1
	var reject_fossil: Dictionary = s.restore(invalid_fossil)
	_check("invalid_discovery_types_rejected_without_mutation", not reject_nest.get("ok",false) and nest_unchanged and not reject_fossil.get("ok",false) and _snapshot(s) == snapshot, {"string_nest_rejected": not reject_nest.get("ok",false), "numeric_fossil_rejected": not reject_fossil.get("ok",false)})
	var earlier: Dictionary = checkpoint.duplicate(true)
	for item: Dictionary in earlier.entities.nests: item.erase("discovered")
	for item: Dictionary in earlier.entities.fossils: item.erase("discovered")
	var compatible: RefCounted = Session.new()
	var compatibility: Dictionary = compatible.restore(earlier)
	var conservative: bool = compatibility.get("ok",false)
	if conservative:
		for item: Dictionary in compatible.nests: conservative = conservative and item.discovered == false
		for item: Dictionary in compatible.fossils: conservative = conservative and item.discovered == false
	_check("earlier_poc3_discovery_defaults_false", conservative, {"restore_ok": compatibility.get("ok",false)})
	compatible.close()
	s.position = fossil.pos + Vector2(4,0)
	s.reveal()
	_check("approach_collects_unlocks_and_removes_icon", fossil.found and s.unlocked.get("carrot",false) and ui.icon_style("fossils", fossil).is_empty(), {"found": fossil.found, "carrot_unlocked": s.unlocked.get("carrot",false)})
	var reward: Dictionary = {"id": s.allocate_id(), "kind": "fossil", "pos": fixed.pos, "unlock": "wheat", "found": false, "discovered": true, "nest_id": fixed.id}
	s.fossils.append(reward)
	var reward_icon_hidden: bool = ui.icon_style("fossils", reward).is_empty()
	s.combat_system.damage_nest(fixed, fixed.hp)
	_check("nest_reward_preserved_without_ground_icon", reward_icon_hidden and reward.found and s.unlocked.get("wheat",false) and not s.nests.has(fixed), {"ground_icon_hidden": reward_icon_hidden, "wheat_unlocked": s.unlocked.get("wheat",false)})
	s.known.fill(1)
	s.position = Vector2(448,448)
	ui.refresh_terrain()
	var terrain: int = s.state.terrain[s.state.index_of(112,112)]
	var source_hex: String = ui.get("_terrain_source").get_pixel(112,112).to_html(false)
	var raster_hex: String = ui.terrain_texture.get_image().get_pixel(54,54).to_html(false)
	var image: Image = Image.load_from_file("res://evidence/poc3/map_info/self/minimap_followup.png")
	var water_pixels: int = 0
	for y: int in range(8,112):
		for x: int in range(8,112):
			if image.get_pixel(x,y).to_html(false) == "4d8eab": water_pixels += 1
	_check("minimap_water_expected_from_authoritative_terrain", terrain == 3 and source_hex == "4d8eab" and raster_hex == "4d8eab" and water_pixels > 0, {"cell": "112,112", "terrain_id": terrain, "source_color": source_hex, "raster_center_color": raster_hex, "provided_minimap_water_pixels": water_pixels, "authoritative_paint": "water rect [109,1,6,222]"})
	ui.free()
	s.close()
	var failures: int = 0
	for item: Dictionary in checks:
		print(JSON.stringify(item))
		if item.status == "FAIL": failures += 1
	report["checks"] = checks
	report["failures"] = failures
	report["user_data"] = profile
	report["godot"] = Engine.get_version_info()
	report["not_run"] = ["independent_gpu_native_input", "wide_regression_long_play", "all_lighting_sizes_exported_build"]
	var file: FileAccess = FileAccess.open(OUT, FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	quit(0 if failures == 0 else 1)
