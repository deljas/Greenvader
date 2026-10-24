extends SceneTree
## Independent checks from POC3-SAVE-BASE acceptance conditions. Headless only.
const Session: GDScript = preload("res://scripts/poc2/poc2_session.gd")
const Save: GDScript = preload("res://scripts/poc2/save/poc2_save.gd")
const OUT: String = "res://evidence/poc3/save_base/independent/results.json"
var checks: Array[Dictionary] = []

func _init() -> void:
	call_deferred("_run")

func _check(name: String, ok: bool, detail: String) -> void:
	checks.append({"name": name, "status": "PASS" if ok else "FAIL", "detail": detail})

func _write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()

func _snapshot(session: RefCounted) -> String:
	return JSON.stringify(session.to_dict(), "", true, true)

func _compare_values(left: Variant, right: Variant, path: String, differences: Array[Dictionary], numeric_types: Array[String]) -> void:
	if (left is int or left is float) and (right is int or right is float):
		if left != right:
			differences.append({"path": path, "expected": left, "actual": right})
		elif typeof(left) != typeof(right):
			numeric_types.append(path)
	elif left is Dictionary and right is Dictionary:
		if left.size() != right.size(): differences.append({"path": path, "problem": "dictionary size"})
		for key: Variant in left:
			if not right.has(key): differences.append({"path": path + "." + str(key), "problem": "missing key"})
			else: _compare_values(left[key], right[key], path + "." + str(key), differences, numeric_types)
	elif left is Array and right is Array:
		if left.size() != right.size(): differences.append({"path": path, "problem": "array size"})
		for index: int in mini(left.size(), right.size()):
			_compare_values(left[index], right[index], path + "[" + str(index) + "]", differences, numeric_types)
	elif left != right:
		differences.append({"path": path, "expected": str(left).left(160), "actual": str(right).left(160)})

func _recheck_roundtrip() -> void:
	var report: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(OUT))
	var expected: RefCounted = Session.new()
	expected.seeds = 137
	expected.hp = 73.0
	expected.water = 19.0
	expected.unlocked["carrot"] = true
	var loaded: Dictionary = Save.load_game()
	var differences: Array[Dictionary] = []
	var numeric_types: Array[String] = []
	var direct_expected: bool = false
	var string_equal: bool = false
	if bool(loaded.get("ok", false)):
		var actual: RefCounted = loaded.session
		direct_expected = actual.seeds == 137 and actual.hp == 73.0 and actual.water == 19.0 and actual.unlocked.get("carrot", false) and actual.state.width == 224 and actual.state.height == 224 and actual.enemies.size() == expected.enemies.size() and actual.nests.size() == expected.nests.size() and actual.clock.elapsed == 0.0
		_compare_values(expected.to_dict(), actual.to_dict(), "$", differences, numeric_types)
		string_equal = _snapshot(expected) == _snapshot(actual)
		actual.close()
	expected.close()
	var passed: bool = bool(loaded.get("ok", false)) and direct_expected and differences.is_empty()
	report["roundtrip_followup"] = {"status": "PASS" if passed else "FAIL", "load_ok": loaded.get("ok", false), "direct_independent_expectations": direct_expected, "original_string_equal": string_equal, "value_differences": differences, "equal_numeric_type_differences": numeric_types, "method": "One load of existing saved fixture; all values compared exactly, allowing equal int/float values; no tolerance and no game code changes"}
	_write(OUT, JSON.stringify(report, "  ", true, true))
	print(JSON.stringify(report.roundtrip_followup))
	quit(0 if passed else 1)

func _run() -> void:
	var profile: String = OS.get_user_data_dir().replace("\\", "/")
	var safe: bool = DisplayServer.get_name() == "headless" and profile.begins_with("C:/godot/greenvader/evidence/poc3/save_base/independent/profile/")
	if not safe:
		push_error("Independent save test requires headless and isolated profile")
		quit(2)
		return
	if OS.get_cmdline_user_args().has("--recheck-roundtrip"):
		_recheck_roundtrip()
		return
	var report: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(OUT))
	var reference: RefCounted = Session.new()
	var default_snapshot: String = _snapshot(reference)
	var old_state: Dictionary = reference.to_dict().duplicate(true)
	old_state.format = "greenvader-poc2"
	old_state.version = 2
	old_state.values.seeds = 4321
	old_state.values.hp = 23.0
	var old_slot: String = JSON.stringify({"format": "greenvader_poc2_1", "state": old_state}, "", true, true)
	var fixtures: Dictionary = {
		"user://poc_saves/slot.json": "{\"fixture\":\"first-poc-preserve-verbatim\",\"progress\":7654}\n",
		"user://poc2_saves/slot1.json": old_slot,
		"user://poc2_saves/slot1.json.bak": old_slot
	}
	var legacy_hashes: Dictionary = {}
	for path: String in fixtures:
		_write(path, fixtures[path])
		legacy_hashes[path] = FileAccess.get_sha256(path)
	var current: RefCounted = Session.new()
	_check("fresh_session_does_not_adopt_old_progress", _snapshot(current) == default_snapshot and current.seeds == 60 and current.hp == 100.0, "Valid old PoC2 state has seeds=4321/hp=23; new Session remains initial state")
	_check("new_slot_is_separate", Save.DEFAULT_DIR == "user://poc3_saves" and not FileAccess.file_exists("user://poc3_saves/slot1.json"), "Old slots exist; new default slot does not yet exist")
	current.seeds = 137
	current.hp = 73.0
	current.water = 19.0
	current.unlocked["carrot"] = true
	var active_before: String = _snapshot(current)
	var saved: Dictionary = Save.save_game(current)
	var restored: Dictionary = Save.load_game()
	var full_equal: bool = bool(restored.get("ok", false)) and _snapshot(restored.session) == active_before
	_check("new_format_roundtrip_preserves_full_state", bool(saved.get("ok", false)) and full_equal, "Modified seeds/hp/water/unlock and complete serialized state must survive default save/load")
	var new_file: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://poc3_saves/slot1.json"))
	_check("new_file_has_poc3_identity", new_file is Dictionary and new_file.get("format") == "greenvader_poc3_1" and new_file.state.get("format") == "greenvader-poc3" and new_file.state.get("version") == 3, "Outer greenvader_poc3_1; inner greenvader-poc3/version3")
	if bool(restored.get("ok", false)):
		restored.session.close()
	var old_load: Dictionary = Save.load_game("user://poc2_saves")
	_check("legacy_outer_rejected_active_unchanged", not bool(old_load.get("ok", false)) and not old_load.has("session") and _snapshot(current) == active_before, "Explicit load of isolated old outer format returns no candidate session")
	var old_direct: Dictionary = current.restore(old_state)
	_check("legacy_inner_rejected_active_unchanged", not bool(old_direct.get("ok", false)) and _snapshot(current) == active_before, "Direct restore of old inner format/version must reject without adoption")
	var invalid: Dictionary = current.to_dict().duplicate(true)
	invalid.values.hp = -1.0
	_write("user://invalid_case/slot1.json", JSON.stringify({"format": "greenvader_poc3_1", "state": invalid}, "", true, true))
	var invalid_load: Dictionary = Save.load_game("user://invalid_case")
	var invalid_direct: Dictionary = current.restore(invalid)
	_check("invalid_payload_rejected_active_unchanged", not bool(invalid_load.get("ok", false)) and not invalid_load.has("session") and not bool(invalid_direct.get("ok", false)) and _snapshot(current) == active_before, "Correct new headers with impossible negative HP rejected by wrapper and direct restore")
	var fixture_intact: bool = true
	for path: String in fixtures:
		fixture_intact = fixture_intact and FileAccess.get_file_as_string(path) == fixtures[path] and FileAccess.get_sha256(path) == legacy_hashes[path]
	var old_directory: DirAccess = DirAccess.open("user://poc2_saves")
	fixture_intact = fixture_intact and old_directory.get_files().size() == 2
	_check("legacy_fixtures_preserved", fixture_intact, "PoC/PoC2 slots and backup retain exact bytes/hash; PoC2 directory still has exactly two files")
	current.close()
	reference.close()
	var failures: int = 0
	for item: Dictionary in checks:
		if item.status == "FAIL": failures += 1
	report["checks"] = checks
	report["failures"] = failures
	report["legacy_fixture_hashes"] = legacy_hashes
	report["user_data"] = profile
	report["godot"] = Engine.get_version_info()
	report["display"] = DisplayServer.get_name()
	report["not_run"] = ["independent_gui_and_input", "broad_gameplay_and_long_play", "exported_windows_build"]
	_write(OUT, JSON.stringify(report, "  ", true, true))
	for item: Dictionary in checks:
		print(JSON.stringify(item))
	print("Independent save checks: ", checks.size() - failures, " PASS / ", failures, " FAIL")
	quit(0 if failures == 0 else 1)
