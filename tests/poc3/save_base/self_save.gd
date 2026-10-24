extends SceneTree
## Runs only with an isolated APPDATA profile. Never copies a real user save.
const Session: GDScript = preload("res://scripts/poc2/poc2_session.gd")
const Save: GDScript = preload("res://scripts/poc2/save/poc2_save.gd")
const OUT: String = "res://evidence/poc3/save_base/self/"
var checks: Array[Dictionary] = []

func _init() -> void:
	root.unfocusable = true
	call_deferred("run")

func check(label: String, passed: bool) -> void:
	checks.append({"name": label, "status": "PASS" if passed else "FAIL"})
	print(checks.back())

func write_json(path: String, data: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data, "", false, true))
	file.close()

func equivalent(left: Variant, right: Variant) -> bool:
	if (left is int or left is float) and (right is int or right is float):
		return absf(float(left) - float(right)) < 0.000000001
	if left is Dictionary and right is Dictionary:
		if left.size() != right.size():
			return false
		for key: Variant in left:
			if not right.has(key) or not equivalent(left[key], right[key]):
				return false
		return true
	if left is Array and right is Array:
		if left.size() != right.size():
			return false
		for index: int in left.size():
			if not equivalent(left[index], right[index]):
				return false
		return true
	return left == right

func run() -> void:
	var isolated: bool = OS.get_user_data_dir().contains("evidence/poc3/save_base/self/profile/")
	check("isolated_profile_required", isolated)
	if not isolated:
		quit(1)
		return
	var session: RefCounted = Session.new()
	var old_state: Dictionary = session.to_dict()
	old_state.format = "greenvader-poc2"
	old_state.version = 2
	old_state.values.seeds = 987
	var legacy_poc: String = "user://poc_saves/slot.json"
	var legacy_poc2: String = "user://poc2_saves/slot1.json"
	write_json(legacy_poc, {"format": "legacy-poc-fixture", "progress": 123})
	write_json(legacy_poc2, {"format": "greenvader_poc2_1", "state": old_state})
	var old_hashes: Dictionary = {legacy_poc: FileAccess.get_sha256(legacy_poc), legacy_poc2: FileAccess.get_sha256(legacy_poc2)}
	check("old_slots_not_auto_adopted", session.seeds == 60 and not FileAccess.file_exists("user://poc3_saves/slot1.json"))
	session.seeds = 137
	session.hp = 71.0
	session.water = 42.0
	session.advance_game(0.5)
	var saved: Dictionary = Save.save_game(session)
	var loaded: Dictionary = Save.load_game()
	check("new_default_save_round_trip", saved.ok and loaded.ok and equivalent(session.to_dict(), loaded.session.to_dict()) if loaded.ok else false)
	var envelope: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("user://poc3_saves/slot1.json"))
	check("new_outer_and_inner_headers", envelope.format == "greenvader_poc3_1" and envelope.state.format == "greenvader-poc3" and envelope.state.version == 3)
	if loaded.ok:
		loaded.session.close()
	var before: String = JSON.stringify(session.to_dict(), "", false, true).sha256_text()
	var legacy_load: Dictionary = Save.load_game("user://poc2_saves")
	check("old_outer_rejected_session_unchanged", not legacy_load.ok and before == JSON.stringify(session.to_dict(), "", false, true).sha256_text())
	var legacy_restore: Dictionary = session.restore(old_state)
	check("old_inner_direct_restore_rejected_unchanged", not legacy_restore.ok and before == JSON.stringify(session.to_dict(), "", false, true).sha256_text())
	var malformed: Dictionary = envelope.duplicate(true)
	malformed.state.values.seeds = -1
	write_json("user://poc3_invalid_fixture/slot1.json", malformed)
	var invalid_load: Dictionary = Save.load_game("user://poc3_invalid_fixture")
	check("invalid_state_rejected_session_unchanged", not invalid_load.ok and before == JSON.stringify(session.to_dict(), "", false, true).sha256_text())
	check("legacy_fixture_files_unchanged", FileAccess.get_sha256(legacy_poc) == old_hashes[legacy_poc] and FileAccess.get_sha256(legacy_poc2) == old_hashes[legacy_poc2] and DirAccess.get_files_at("user://poc_saves").size() == 1 and DirAccess.get_files_at("user://poc2_saves").size() == 1)
	var failed: int = 0
	for result: Dictionary in checks:
		if result.status == "FAIL":
			failed += 1
	write_json(OUT + "results.json", {"checks": checks, "failures": failed, "legacy_fixture_hashes": old_hashes, "user_data": OS.get_user_data_dir(), "not_run": ["physical_input", "broad_gameplay_regression", "long_play", "legacy_progress_migration"]})
	session.close()
	quit(1 if failed > 0 else 0)
