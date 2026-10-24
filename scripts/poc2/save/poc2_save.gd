extends RefCounted
## PoC2-only atomic save wrapper. A failed restore never touches the active session.
const Session: GDScript = preload("res://scripts/poc2/poc2_session.gd")
const DEFAULT_DIR: String = "user://poc2_saves"
const FILE_NAME: String = "slot1.json"
const FORMAT: String = "greenvader_poc2_1"

static func save_game(session: RefCounted, directory: String = DEFAULT_DIR) -> Dictionary:
	var absolute: String = ProjectSettings.globalize_path(directory)
	if not absolute.begins_with(ProjectSettings.globalize_path("user://")):
		return {"ok":false,"reason":"保存先がユーザー領域ではありません"}
	if DirAccess.make_dir_recursive_absolute(absolute)!=OK:
		return {"ok":false,"reason":"保存先を作成できません"}
	var path: String = directory.path_join(FILE_NAME)
	var temporary: String = path+".tmp"
	var backup: String = path+".bak"
	var file: FileAccess = FileAccess.open(temporary,FileAccess.WRITE)
	if file==null: return {"ok":false,"reason":"保存ファイルを開けません"}
	file.store_string(JSON.stringify({"format":FORMAT,"state":session.to_dict()},"",false,true))
	file.flush()
	var error: Error = file.get_error()
	file.close()
	if error!=OK: return {"ok":false,"reason":"保存に失敗しました"}
	# Parse back the temporary bytes before moving the last known-good save.
	var parsed: Variant = _parse(FileAccess.get_file_as_string(temporary))
	if not parsed is Dictionary: return {"ok":false,"reason":"保存内容を検証できません"}
	if FileAccess.file_exists(path):
		if FileAccess.file_exists(backup): DirAccess.remove_absolute(ProjectSettings.globalize_path(backup))
		if DirAccess.rename_absolute(ProjectSettings.globalize_path(path),ProjectSettings.globalize_path(backup))!=OK:
			return {"ok":false,"reason":"前回の保存を保全できません"}
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary),ProjectSettings.globalize_path(path))!=OK:
		if FileAccess.file_exists(backup):
			DirAccess.rename_absolute(ProjectSettings.globalize_path(backup),ProjectSettings.globalize_path(path))
		return {"ok":false,"reason":"保存を確定できません"}
	return {"ok":true,"reason":"保存しました"}

static func load_game(directory: String = DEFAULT_DIR, backup: bool = false) -> Dictionary:
	var path: String = directory.path_join(FILE_NAME)+(".bak" if backup else "")
	if not FileAccess.file_exists(path): return {"ok":false,"reason":"保存データがありません"}
	var parsed: Variant = _parse(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary or String(parsed.get("format",""))!=FORMAT or not parsed.get("state") is Dictionary:
		return {"ok":false,"reason":"保存データを読めません。現在のゲームは保持しています"}
	var candidate: RefCounted = Session.new()
	var result: Dictionary = candidate.restore(parsed.state)
	if not bool(result.get("ok",false)):
		candidate.close()
		return {"ok":false,"reason":"保存データが不正です。現在のゲームは保持しています"}
	return {"ok":true,"session":candidate,"reason":"再開しました"}


static func _parse(text: String) -> Variant:
	var parser: JSON=JSON.new()
	return parser.data if parser.parse(text)==OK else null
