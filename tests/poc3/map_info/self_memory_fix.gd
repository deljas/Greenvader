extends SceneTree
## One normal walk/advance transient crossing for both discovery types, then a save round trip.
const Session: GDScript = preload("res://scripts/poc2/poc2_session.gd")
const Save: GDScript = preload("res://scripts/poc2/save/poc2_save.gd")
const Map: GDScript = preload("res://scripts/poc2/ui/map_ui.gd")
const OUT: String = "res://evidence/poc3/map_info/self/memory_fix/"
var checks: Array[Dictionary] = []

func _init() -> void:
	call_deferred("run")

func check(label: String, passed: bool) -> void:
	checks.append({"name":label,"status":"PASS" if passed else "FAIL"})
	print(checks.back())

func run() -> void:
	if not OS.get_user_data_dir().contains("evidence/poc3/map_info/self/memory_fix/profile/"):
		quit(1)
		return
	var session: RefCounted = Session.new()
	var nest: Dictionary = session.nests[0]
	var fossil: Dictionary = {}
	for item: Dictionary in session.fossils:
		if int(item.nest_id) < 0:
			fossil = item
			break
	# The independent failure derived this ground point from actual camera pixel(642,180).
	var target: Vector2 = Vector2(502.2525,268.228)
	session.position = Vector2(400,400)
	nest.pos = target
	nest.home = target
	nest.discovered = false
	fossil.pos = target
	fossil.discovered = false
	fossil.found = false
	var unlocked_before: Dictionary = session.unlocked.duplicate(true)
	var map: Control = Map.new()
	map.session = session
	session.advance(0.05)
	var visible_before: PackedByteArray = session.visible.duplicate()
	var next_reveal: float = session.reveal_at
	check("initial_nest_and_fossil_outside_camera", not session.detected(target) and not nest.discovered and not fossil.discovered)
	session.walk(Vector2.RIGHT,0.1)
	session.advance(0.1)
	var live: bool = session.detected(target)
	check("transient_detection_records_both_immediately", live and nest.discovered and fossil.discovered and not map.icon_style("nests",nest).is_empty() and not map.icon_style("fossils",fossil).is_empty())
	session.walk(Vector2.LEFT,0.1)
	session.advance(0.1)
	check("departure_before_reveal_keeps_both_memories", not session.detected(target) and nest.discovered and fossil.discovered and map.icon_style("nests",nest).shape == "square" and map.icon_style("fossils",fossil).shape == "fossil")
	check("terrain_reveal_cadence_unchanged", session.clock.elapsed < next_reveal and session.reveal_at == next_reveal and session.visible == visible_before)
	check("discovery_does_not_collect_or_activate", not fossil.found and session.unlocked == unlocked_before and not nest.active and nest.status == "dormant")
	var saved: Dictionary = Save.save_game(session)
	var loaded: Dictionary = Save.load_game()
	var restored: bool = false
	if loaded.ok:
		var restored_nest: bool = false
		var restored_fossil: bool = false
		for item: Dictionary in loaded.session.nests:
			if item.id == nest.id: restored_nest = item.discovered
		for item: Dictionary in loaded.session.fossils:
			if item.id == fossil.id: restored_fossil = item.discovered and not item.found
		restored = restored_nest and restored_fossil and loaded.session.unlocked == unlocked_before
		loaded.session.close()
	check("transient_memories_survive_save_restore", saved.ok and loaded.ok and restored)
	var failures: int = 0
	for result: Dictionary in checks:
		if result.status == "FAIL": failures += 1
	var file: FileAccess = FileAccess.open(OUT+"results.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"elapsed":session.clock.elapsed,"next_reveal_at":next_reveal,"target":[target.x,target.y],"user_data":OS.get_user_data_dir(),"session_sha256":FileAccess.get_sha256("res://scripts/poc2/poc2_session.gd"),"not_run":["broad_logic_regression","gpu_regression","physical_input"]},"  "))
	file.close()
	map.free()
	session.close()
	quit(1 if failures > 0 else 0)
