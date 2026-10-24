extends SceneTree
## Independent SOURCE smoke: use configured entry, without external or engine input.
var checks: Array[Dictionary] = []

func _init() -> void:
	root.unfocusable = true
	call_deferred("_run")

func _check(name: String, ok: bool, actual: Variant) -> void:
	checks.append({"name": name, "status": "PASS" if ok else "FAIL", "actual": str(actual)})

func _run() -> void:
	var destination: String = str(ProjectSettings.get_setting("application/run/main_scene", ""))
	_check("configured_latest_scene", destination == "res://scenes/poc2.tscn", destination)
	var result: Error = change_scene_to_file(destination)
	_check("configured_scene_instantiates", result == OK, result)
	await process_frame
	await process_frame
	await process_frame
	var scene: Node = current_scene
	_check("current_scene_is_latest", scene != null and scene.scene_file_path == "res://scenes/poc2.tscn", scene.scene_file_path if scene != null else "null")
	if scene != null:
		_check("startup_has_title_and_pauses", scene.get("menu") == "title" and bool(scene.call("is_paused")), scene.get("menu"))
		_check("save_namespace_unchanged", scene.get("save_dir") == "user://poc2_saves", scene.get("save_dir"))
	var user_path: String = OS.get_user_data_dir().replace("\\", "/")
	_check("isolated_user_data", user_path.begins_with("C:/godot/greenvader/evidence/poc3/source/independent/profile/"), user_path)
	var failures: int = 0
	for check: Dictionary in checks:
		if check.status == "FAIL": failures += 1
	var report: Dictionary = {"checks": checks, "failures": failures, "godot": Engine.get_version_info(), "display": DisplayServer.get_name(), "user_data": user_path, "input_sent": false}
	var file: FileAccess = FileAccess.open("res://evidence/poc3/source/independent/smoke_results.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	print(JSON.stringify(report))
	quit(0 if failures == 0 else 1)
