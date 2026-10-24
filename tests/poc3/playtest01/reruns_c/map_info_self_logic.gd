extends SceneTree
const Session: GDScript = preload("res://scripts/poc2/poc2_session.gd")
const Save: GDScript = preload("res://scripts/poc2/save/poc2_save.gd")
const Map: GDScript = preload("res://scripts/poc2/ui/map_ui.gd")
const Coords: GDScript = preload("res://scripts/poc/poc_coords.gd")
const OUT: String = "res://evidence/poc3/playtest01/self/rerun_C_map_info/"
var checks: Array[Dictionary] = []

func _init() -> void:
	call_deferred("run")

func check(label: String, passed: bool) -> void:
	checks.append({"name":label,"status":"PASS" if passed else "FAIL"})
	print(checks.back())

func fingerprint(session: RefCounted) -> String:
	return JSON.stringify(session.to_dict(),"",false,true).sha256_text()

func run() -> void:
	if not OS.get_user_data_dir().contains("evidence/poc3/playtest01/self/rerun_C_map_info/profile/"):
		push_error("Isolated profile required")
		quit(1)
		return
	var session: RefCounted = Session.new()
	var nest: Dictionary = session.nests[0].duplicate(true)
	var mother: Dictionary = nest.duplicate(true)
	var fossil: Dictionary = {"id":session.allocate_id(),"kind":"fossil","pos":Vector2(180,100),"unlock":"carrot","found":false,"discovered":false,"nest_id":-1}
	session.nests.clear()
	session.enemies.clear()
	session.fossils.clear()
	session.helpers.clear()
	session.state.stage.fill(0) # Detection-only fixture; never saved.
	session.position = Vector2(448.25,448.125)
	nest.pos = Vector2(100,100)
	nest.home = nest.pos
	nest.discovered = false
	mother.id = session.allocate_id()
	mother.pos = Vector2(140,100)
	mother.home = mother.pos
	mother.kind = "mother"
	mother.mother = true
	mother.discovered = false
	session.nests.assign([nest,mother])
	session.fossils.append(fossil)
	var map: Control = Map.new()
	map.session = session
	var far: Vector2 = nest.pos
	check("normal_camera_replaces_player_circle", session.detected(session.position+Vector2(-100,100)) and not session.detected(far))
	var helper: Dictionary = {"pos":far-Vector2(72,0),"hp":80.0}
	session.helpers.append(helper)
	check("helper_existing_radius_72", session.detected(far) and not session.detected(far+Vector2(0.01,0)))
	helper.pos = far
	session.reveal()
	var live_color: Color = map.icon_style("nests",nest).color
	check("fixed_nest_and_mother_detected", nest.discovered and not mother.discovered and map.icon_style("nests",mother).shape == "mother")
	session.helpers.clear()
	session.reveal()
	check("fixed_memory_pale_mother_no_memory", not map.icon_style("nests",nest).is_empty() and map.icon_style("nests",nest).color != live_color and map.icon_style("nests",mother).is_empty())
	var index: int = session.state.index_of(25,25)
	var enemy: Dictionary = {"id":session.allocate_id(),"pos":far,"hp":20.0}
	session.state.stage[index] = WorldState.STAGE_SEED
	session.reveal()
	check("seed_is_not_green_detection", not session.detected(far) and map.icon_style("enemies",enemy).is_empty())
	session.state.stage[index] = WorldState.STAGE_SPROUT1
	session.reveal()
	check("remote_green_detects_current_enemy", session.detected(far) and not map.icon_style("enemies",enemy).is_empty())
	session.state.stage[index] = WorldState.STAGE_EMPTY
	session.reveal()
	check("green_loss_hides_enemy_keeps_known", not session.detected(far) and map.icon_style("enemies",enemy).is_empty() and session.known[index] == 1 and session.visible[index] == 0)
	var fossil_cell: Vector2i = Coords.logic_to_cell(fossil.pos)
	var fossil_index: int = session.state.index_of(fossil_cell.x,fossil_cell.y)
	session.state.stage[fossil_index] = WorldState.STAGE_SEED
	session.reveal()
	check("seed_does_not_discover_fossil", not fossil.discovered and map.icon_style("fossils",fossil).is_empty())
	session.state.stage[fossil_index] = WorldState.STAGE_SPROUT1
	session.reveal()
	check("remote_fossil_discovery_no_unlock", fossil.discovered and not fossil.found and not session.unlocked.get("carrot",false))
	session.state.stage[fossil_index] = WorldState.STAGE_EMPTY
	session.reveal()
	check("fossil_memory_after_green_loss", not session.detected(fossil.pos) and map.icon_style("fossils",fossil).shape == "fossil")
	session.position = fossil.pos
	session.reveal()
	check("approach_collects_unlocks_hides_fossil", fossil.found and session.unlocked.get("carrot",false) and map.icon_style("fossils",fossil).is_empty())
	var reward: Dictionary = {"id":session.allocate_id(),"kind":"fossil","pos":nest.pos,"unlock":"wheat","found":false,"discovered":false,"nest_id":nest.id}
	session.fossils.append(reward)
	var reward_hidden: bool = map.icon_style("fossils",reward).is_empty()
	session.combat_system.damage_nest(nest,float(nest.hp))
	check("destroyed_nest_clears_and_reward_unlocks", map.icon_style("nests",nest).is_empty() and not session.nests.has(nest) and reward_hidden and reward.found and session.unlocked.get("wheat",false))
	map.free()
	session.close()
	# Persistence uses an unmodified, internally consistent world, not the detection fixture.
	var saved_session: RefCounted = Session.new()
	saved_session.nests[0].discovered = true
	var exploration: Dictionary = {}
	for item: Dictionary in saved_session.fossils:
		if int(item.nest_id) < 0:
			exploration = item
			break
	exploration.discovered = true
	var state: Dictionary = saved_session.to_dict()
	var saved: Dictionary = Save.save_game(saved_session)
	var loaded: Dictionary = Save.load_game()
	var memory_restored: bool = false
	if loaded.ok:
		for item: Dictionary in loaded.session.fossils:
			if item.id == exploration.id:
				memory_restored = item.discovered and not item.found and loaded.session.nests[0].discovered
		loaded.session.close()
	check("discovery_save_roundtrip", saved.ok and loaded.ok and memory_restored)
	var earlier: Dictionary = state.duplicate(true)
	for category: String in ["nests","fossils"]:
		for item: Dictionary in earlier.entities[category]:
			item.erase("discovered")
	var candidate: RefCounted = Session.new()
	var supplemented: Dictionary = candidate.restore(earlier)
	var defaults_false: bool = true
	for item: Dictionary in candidate.nests+candidate.fossils:
		defaults_false = defaults_false and item.has("discovered") and not item.discovered
	check("earlier_poc3_missing_discovery_defaults_false", supplemented.ok and defaults_false)
	candidate.close()
	var unchanged: String = fingerprint(saved_session)
	for category: String in ["nests","fossils"]:
		var invalid: Dictionary = state.duplicate(true)
		invalid.entities[category][0].discovered = "true"
		var rejected: Dictionary = saved_session.restore(invalid)
		check("invalid_discovery_bool_"+category, not rejected.ok and fingerprint(saved_session) == unchanged)
	var old: Dictionary = state.duplicate(true)
	old.format = "greenvader-poc2"
	old.version = 2
	var old_rejected: Dictionary = saved_session.restore(old)
	check("old_poc2_rejected_unchanged", not old_rejected.ok and fingerprint(saved_session) == unchanged)
	saved_session.close()
	var failures: int = 0
	for result: Dictionary in checks:
		if result.status == "FAIL": failures += 1
	var file: FileAccess = FileAccess.open(OUT+"logic_results.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"user_data":OS.get_user_data_dir(),"not_run":["physical_input","wide_regression","long_play"]},"  "))
	file.close()
	quit(1 if failures > 0 else 0)
