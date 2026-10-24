extends SceneTree
## Headless observation of entity nodes from an independent world fixture.
const Session: GDScript = preload("res://scripts/poc2/poc2_session.gd")
const View: GDScript = preload("res://scripts/poc2/view/world_view.gd")
const Coords: GDScript = preload("res://scripts/poc/poc_coords.gd")
const OUT: String = "res://evidence/poc3/visibility/independent/results.json"
var checks: Array[Dictionary] = []

func _init() -> void:
	call_deferred("_run")

func _check(name: String, ok: bool, actual: Variant) -> void:
	checks.append({"name": name, "status": "PASS" if ok else "FAIL", "actual": str(actual)})

func _shown(view: Node3D, key: String) -> bool:
	var node: Node3D = view.entities.get(key)
	return is_instance_valid(node) and node.visible and node is MeshInstance3D and node.mesh != null

func _run() -> void:
	var profile: String = OS.get_user_data_dir().replace("\\", "/")
	if DisplayServer.get_name() != "headless" or not profile.begins_with("C:/godot/greenvader/evidence/poc3/visibility/independent/profile/"):
		push_error("Headless and isolated visibility profile required")
		quit(2)
		return
	var report: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(OUT))
	var session: RefCounted = Session.new()
	var enemy: Dictionary = session.enemies[0].duplicate(true)
	var fixed_nest: Dictionary = {}
	var mother: Dictionary = {}
	for nest: Dictionary in session.nests:
		if nest.mother: mother = nest.duplicate(true)
		elif fixed_nest.is_empty(): fixed_nest = nest.duplicate(true)
	if fixed_nest.is_empty() or mother.is_empty():
		push_error("Fixture needs an existing fixed nest and mother template")
		session.close()
		quit(2)
		return
	enemy.id = 80001
	enemy.pos = Vector2(100, 100)
	enemy.home = enemy.pos
	enemy.source = 80002
	fixed_nest.id = 80002
	fixed_nest.pos = Vector2(140, 100)
	fixed_nest.home = fixed_nest.pos
	mother.id = 80003
	mother.pos = Vector2(180, 100)
	mother.home = mother.pos
	for nest: Dictionary in [fixed_nest, mother]:
		nest.active = false
		nest.status = "dormant"
		nest.last_contact = -100.0
	var fossil: Dictionary = {"id": 80004, "kind": "fossil", "pos": Vector2(220, 100), "found": false, "nest_id": -1, "unlock": "carrot"}
	session.position = Vector2(600, 600)
	session.enemies.assign([enemy])
	session.nests.assign([fixed_nest, mother])
	session.fossils.assign([fossil])
	session.plants.clear()
	session.helpers.clear()
	session.shots.clear()
	session.visible.fill(0)
	session.known.fill(0)
	session.state.stage.fill(WorldState.STAGE_EMPTY)
	var view: Node3D = View.new()
	root.add_child(view)
	view.session = session
	var snapshot_before: String = JSON.stringify(session.to_dict(), "", true, true)
	view.call("_entities")
	_check("empty_visibility_still_draws_living_enemy", _shown(view, "enemies80001"), view.entities.keys())
	_check("empty_visibility_still_draws_fixed_nest", _shown(view, "nests80002"), fixed_nest.kind)
	_check("empty_visibility_still_draws_moving_mother", _shown(view, "nests80003"), mother.kind)
	_check("rendering_does_not_mutate_session", JSON.stringify(session.to_dict(), "", true, true) == snapshot_before, "Full before/after state compared before simulation is advanced")
	_check("unseen_fossil_stays_hidden", not _shown(view, "fossils80004"), "All visibility and known bytes zero")
	session.clock.advance(0.25)
	session.combat_system.advance(0.25)
	_check("displayed_far_nests_do_not_activate", not fixed_nest.active and not mother.active and fixed_nest.status == "dormant" and mother.status == "dormant" and session.enemies.size() == 1, "No green anywhere, player far away, one 0.25-second combat step; no production")
	var cell: Vector2i = Coords.logic_to_cell(fossil.pos)
	session.visible[session.state.index_of(cell.x, cell.y)] = 1
	view.call("_entities")
	_check("visible_uncollected_fossil_draws", _shown(view, "fossils80004"), "Only the fossil's visibility cell enabled")
	fossil.found = true
	view.call("_entities")
	var found_hidden: bool = not _shown(view, "fossils80004")
	fossil.found = false
	fossil.nest_id = 80002
	view.call("_entities")
	_check("collected_and_nest_reward_fossils_stay_hidden", found_hidden and not _shown(view, "fossils80004"), "Found=true then nest_id>=0 remain hidden even with visibility")
	enemy.hp = 0.0
	mother.hp = 0.0
	session.nests.erase(fixed_nest)
	view.call("_entities")
	_check("death_and_array_removal_clear_nodes", not view.entities.has("enemies80001") and not view.entities.has("nests80002") and not view.entities.has("nests80003"), view.entities.keys())
	view.queue_free()
	await process_frame
	session.close()
	var failures: int = 0
	for item: Dictionary in checks:
		if item.status == "FAIL": failures += 1
		print(JSON.stringify(item))
	report["checks"] = checks
	report["failures"] = failures
	report["user_data"] = profile
	report["godot"] = Engine.get_version_info()
	report["display"] = DisplayServer.get_name()
	report["not_run"] = ["independent_gpu_or_native_input", "building_occlusion_map_information_broad_regression", "all_lighting_sizes_and_exported_build"]
	var file: FileAccess = FileAccess.open(OUT, FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	quit(0 if failures == 0 else 1)
