extends RefCounted
## POC-08 manual save / load of a PoC session (JSON, one slot + the previous one as backup).
##
## Saved (see SECTIONS): world/map identity (format_version, map_id, map_hash), WorldState (terrain, plants, growth, moisture,
## fertility, occupancy, zones; sprout_seed is its random source), GrowthSim / SpreadSim / FarSeedSim progress, SimClock,
## PlayState (resources, HP, selection, pickups, cultivated plants, source timers, drops), EnemyField (nests, boars with their
## rng, carcasses), wall vegetation growth, player position, zone notices/times, and UI settings (resolution).
## NOT saved on purpose: shots in flight (the live session drops them at save time: spent seeds / water are refunded and the
## seeds reserved for cultivated plants are released, so nothing is lost or duplicated), the aim point, the real-time clock
## (saved_at is display only; the game clock continues from game_elapsed with no real time added), the fast-forward multiplier,
## the pause flag and everything that is only display (views are rebuilt).
##
## Loading builds a NEW session, applies the file to it and returns it only when everything checked out; the caller then swaps
## it in. A rejected file therefore never touches the running session.
const Config: GDScript = preload("res://scripts/poc/poc_config.gd")
const FORMAT_VERSION: int = 1
const DEFAULT_DIR: String = "user://poc_saves/"
const SLOT_FILE: String = "slot.json"
const BACKUP_FILE: String = "slot.bak.json"
const TEMP_FILE: String = "slot.tmp.json"
const SECTIONS: Array[String] = ["world", "growth", "spread", "far", "clock", "play", "enemies", "wall_growth", "session", "combat_stats", "ui"]

const WORLD_PACKED: Array[String] = ["terrain", "plant_id", "stage", "growth", "moisture", "fertility", "sprout_slot", "occupant"]
const REQUIRED: Dictionary = {
	"world": ["version", "width", "height", "sprout_seed", "terrain", "plant_id", "stage", "growth", "moisture", "fertility", "sprout_slot", "occupant", "occupancy_owners", "zones"],
	"growth": ["version", "ticks", "cursor", "active", "lag"],
	"spread": ["version", "ticks", "queue", "progress", "visits", "pending", "counted"],
	"far": ["version", "ticks", "sweep_cursor", "zone_enum", "zone_initial", "zone_stable_tick", "zone_queue", "job_zone", "job_scan", "job_head", "job_open", "label", "members", "comp_start", "comp_end", "comp_state", "round_active", "round_comp", "round_pos", "round_empty"],
	"clock": ["version", "elapsed", "growth_ticks", "spread_ticks"],
	"play": ["version", "seeds", "water", "pickups", "sources", "hp", "health", "cultivated", "selected"],
	"enemies": ["version", "nests", "boars", "carcasses"],
	"wall_growth": ["version", "ticks", "entries"],
	"session": ["position", "zone_log", "cleared_notices", "zone_times"],
	"combat_stats": [],
	"ui": ["resolution_index"],
}

## Display-only strings are produced here; callers show `reason` as is.
static func result_fail(code: String, reason: String) -> Dictionary:
	return {"ok": false, "code": code, "reason": reason}

static func map_id_of(s: RefCounted) -> String:
	return String(s.combat_setup.get("map", "")).get_file().get_basename() if s.combat_mode else ""

## Hash of the terrain layout and the greening-target set (and the size): what must be identical for a save to fit the map.
static func map_hash(s: RefCounted) -> String:
	var ctx: HashingContext = HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(("%dx%d" % [s.state.width, s.state.height]).to_utf8_buffer())
	ctx.update(s.base_terrain)
	ctx.update(s.state.target)
	return ctx.finish().hex_encode().substr(0, 32)

# ---------------------------------------------------------------- capture

## Pure snapshot of a session (no change to it). Shots in flight are not part of it (call s.cancel_shots_for_save() first
## when the live session should match what the file will restore; save() does).
static func capture(s: RefCounted, extras: Dictionary = {}) -> Dictionary:
	var zone_times: Dictionary = {}
	for zone: Variant in s.zone_times:
		var row: Dictionary = {}
		for state_id: Variant in s.zone_times[zone]:
			row[str(int(state_id))] = float(s.zone_times[zone][state_id])
		zone_times[str(int(zone))] = row
	var stats: Dictionary = {}
	if s.combat != null:
		stats = {"hits": s.combat.hits, "fruits_dropped": s.combat.fruits_dropped, "fruits_refused": s.combat.fruits_refused, "fruits_direct": s.combat.fruits_direct, "seeds_direct": s.combat.seeds_direct}
	return {
		"format_version": FORMAT_VERSION,
		"map_id": map_id_of(s),
		"map_hash": map_hash(s),
		"game_elapsed": s.clock.elapsed,
		"saved_at": Time.get_datetime_string_from_system(false, true),
		"world": s.state.to_dict(),
		"growth": s.growth.to_dict(),
		"spread": s.spread.to_dict(),
		"far": s.far.to_dict(),
		"clock": s.clock.to_dict(),
		"play": s.play.to_dict(),
		"enemies": s.enemies.to_dict(),
		"wall_growth": s.wall_growth.to_dict(),
		"session": {
			"position": [s.position.x, s.position.y],
			"zone_log": Array(s.zone_log),
			"cleared_notices": s.cleared_notices,
			"zone_times": zone_times,
			"scatter_filtered": s.scatter_filtered,
			"shots_blocked_by_wall": s.shots_blocked_by_wall,
		},
		"combat_stats": stats,
		"ui": {"resolution_index": int(extras.get("resolution_index", 0))},
	}

## Canonical text of a capture without the wall-clock field (state comparison in tests).
static func signature(s: RefCounted) -> String:
	var data: Dictionary = capture(s)
	data.erase("saved_at")
	# Parsed back once so that int / float typing of the same number does not matter (a file only knows numbers).
	return JSON.stringify(_parse(JSON.stringify(data, "", true, true)), "", true, true)

# ---------------------------------------------------------------- files

## Quiet parse (the engine's JSON.parse_string logs an error for every bad file, which is expected for a damaged save).
static func _parse(text: String) -> Variant:
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		return null
	return json.data

static func _abs(base_dir: String, file: String) -> String:
	return base_dir.path_join(file)

static func has_file(base_dir: String, file: String) -> bool:
	return FileAccess.file_exists(_abs(base_dir, file))

## Manual save: drops the shots in flight, writes a temp file, verifies it, moves the old slot to the backup, then puts the
## temp file in place. Returns {ok, reason, path}.
static func save(s: RefCounted, base_dir: String, extras: Dictionary = {}) -> Dictionary:
	if not s.combat_mode or s.enemies == null or s.wall_growth == null:
		return result_fail("unsupported", "このマップは保存に対応していません")
	s.cancel_shots_for_save()
	var data: Dictionary = capture(s, extras)
	var text: String = JSON.stringify(data, "", false, true)
	if DirAccess.make_dir_recursive_absolute(base_dir) != OK and not DirAccess.dir_exists_absolute(base_dir):
		return result_fail("io", "保存先を作れませんでした")
	var temp_path: String = _abs(base_dir, TEMP_FILE)
	var slot_path: String = _abs(base_dir, SLOT_FILE)
	var backup_path: String = _abs(base_dir, BACKUP_FILE)
	var file: FileAccess = FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		return result_fail("io", "保存ファイルを開けませんでした")
	file.store_string(text)
	file.flush()
	file.close()
	if FileAccess.get_file_as_string(temp_path).length() != text.length() or not (_parse(FileAccess.get_file_as_string(temp_path)) is Dictionary):
		DirAccess.remove_absolute(temp_path)
		return result_fail("io", "保存の書込みを確認できませんでした（元のセーブは変更していません）")
	if FileAccess.file_exists(slot_path):
		# A slot that no longer parses must not replace a good backup.
		if not (_parse(FileAccess.get_file_as_string(slot_path)) is Dictionary):
			DirAccess.remove_absolute(slot_path)
		elif DirAccess.copy_absolute(slot_path, backup_path) != OK:
			DirAccess.remove_absolute(temp_path)
			return result_fail("io", "バックアップを作れませんでした（元のセーブは変更していません）")
		DirAccess.remove_absolute(slot_path)
	if DirAccess.rename_absolute(temp_path, slot_path) != OK:
		if FileAccess.file_exists(backup_path) and not FileAccess.file_exists(slot_path):
			DirAccess.copy_absolute(backup_path, slot_path)
		return result_fail("io", "保存ファイルを置き換えられませんでした")
	return {"ok": true, "code": "", "reason": "", "path": slot_path}

## What the menus show: whether the slot / backup exist and a one-line summary of each (empty when unreadable).
static func slot_info(base_dir: String) -> Dictionary:
	var info: Dictionary = {"slot": has_file(base_dir, SLOT_FILE), "backup": has_file(base_dir, BACKUP_FILE), "slot_text": "", "backup_text": "", "slot_valid": false}
	for pair: Array in [[SLOT_FILE, "slot_text"], [BACKUP_FILE, "backup_text"]]:
		if has_file(base_dir, String(pair[0])):
			var parsed: Variant = _parse(FileAccess.get_file_as_string(_abs(base_dir, String(pair[0]))))
			if parsed is Dictionary and (parsed as Dictionary).has("game_elapsed"):
				var elapsed: float = float((parsed as Dictionary)["game_elapsed"])
				info[pair[1]] = "%s　ゲーム時間 %02d:%02d" % [String((parsed as Dictionary).get("saved_at", "")), int(elapsed) / 60, int(elapsed) % 60]
				if pair[0] == SLOT_FILE:
					info["slot_valid"] = true
	return info

# ---------------------------------------------------------------- load

## Reads `slot.json` (or the backup), builds a fresh session with `factory` (Callable -> session with the map loaded) and applies
## the file. Returns {ok, code, reason, session, extras, backup_available}; on failure no session is returned and the
## candidate session is closed.
static func load_slot(base_dir: String, use_backup: bool, factory: Callable, expected_map_id: String = "town_01") -> Dictionary:
	var file: String = BACKUP_FILE if use_backup else SLOT_FILE
	var backup_note: String = "　バックアップから読み込めます" if (not use_backup and has_file(base_dir, BACKUP_FILE)) else ""
	if not has_file(base_dir, file):
		return result_fail("missing", ("バックアップがありません" if use_backup else "セーブデータがありません") + backup_note)
	var parsed: Variant = _parse(FileAccess.get_file_as_string(_abs(base_dir, file)))
	if not (parsed is Dictionary):
		return _fail_with_backup("corrupt", "セーブデータが壊れています（読み取れません）。" + backup_note, not use_backup and has_file(base_dir, BACKUP_FILE))
	var data: Dictionary = parsed
	var backup_ok: bool = not use_backup and has_file(base_dir, BACKUP_FILE)
	for key: String in ["format_version", "map_id", "map_hash", "game_elapsed"]:
		if not data.has(key):
			return _fail_with_backup("missing_key", "セーブデータの必須項目「%s」が欠けています。" % key + backup_note, backup_ok)
	if not _is_number(data["format_version"]) or int(data["format_version"]) != FORMAT_VERSION:
		return _fail_with_backup("version", "セーブの形式が違うため読み込めません（保存 v%s / 現在 v%d）。" % [str(int(data["format_version"])) if _is_number(data["format_version"]) else "?", FORMAT_VERSION], backup_ok)
	if String(data["map_id"]) != expected_map_id:
		return _fail_with_backup("map", "別のマップのセーブです（保存 %s / 現在 %s）。" % [String(data["map_id"]), expected_map_id], backup_ok)
	for section: String in SECTIONS:
		if not data.has(section) or not (data[section] is Dictionary):
			return _fail_with_backup("missing_key", "セーブデータの必須項目「%s」が欠けています。" % section + backup_note, backup_ok)
		for key: String in REQUIRED[section]:
			if not (data[section] as Dictionary).has(key):
				return _fail_with_backup("missing_key", "セーブデータの必須項目「%s.%s」が欠けています。" % [section, key] + backup_note, backup_ok)
	var fresh: RefCounted = factory.call()
	if fresh == null:
		return result_fail("internal", "マップを準備できませんでした")
	var problem: Dictionary = apply(fresh, data)
	if not bool(problem["ok"]):
		fresh.close()
		problem["backup_available"] = backup_ok
		if backup_ok and String(problem["code"]) != "hash":
			problem["reason"] = String(problem["reason"]) + backup_note
		return problem
	return {"ok": true, "code": "", "reason": "", "session": fresh, "extras": {"resolution_index": int((data["ui"] as Dictionary)["resolution_index"])}, "backup_available": backup_ok}

static func _fail_with_backup(code: String, reason: String, backup_ok: bool) -> Dictionary:
	var result: Dictionary = result_fail(code, reason)
	result["backup_available"] = backup_ok
	return result

static func _is_number(value: Variant) -> bool:
	return (value is int) or ((value is float) and is_finite(value))

static func _packed_ok(value: Variant) -> bool:
	return value is Dictionary and (value as Dictionary).has("n") and (value as Dictionary).has("z") and _is_number((value as Dictionary)["n"]) and ((value as Dictionary)["z"] is String)

# ---------------------------------------------------------------- value checks (before anything is applied)

static func _int_in(value: Variant, low: int, high: int) -> bool:
	return _is_number(value) and float(value) == floorf(float(value)) and float(value) >= float(low) and float(value) <= float(high)

static func _num_in(value: Variant, low: float, high: float) -> bool:
	return _is_number(value) and float(value) >= low and float(value) <= high

static func _vec_ok(value: Variant, size: int = 2) -> bool:
	if not (value is Array) or (value as Array).size() != size:
		return false
	for item: Variant in value:
		if not _is_number(item) or absf(float(item)) > 1.0e7:
			return false
	return true

static func _keys_ok(d: Variant, keys: Array) -> bool:
	if not (d is Dictionary):
		return false
	for key: Variant in keys:
		if not (d as Dictionary).has(key):
			return false
	return true

static func _ints_unpack(value: Variant) -> Variant:
	if not _packed_ok(value):
		return null
	return WorldState._unpack_bytes(value).to_int32_array()

static func _array_in(value: Variant, size: int, low: int, high: int) -> bool:
	if not (value is Array) or (value as Array).size() != size:
		return false
	for item: Variant in value:
		if not _int_in(item, low, high):
			return false
	return true

## Returns "" when every value that could break the session after loading is inside its range / type, else a short label.
## Out-of-range values are rejected, never clamped.
static func _validate_values(s: RefCounted, data: Dictionary) -> String:
	var n: int = s.state.tile_count()
	var zones: int = s.state.zone_count
	var big: int = 2000000000
	# world: the pieces from_dict reads without checking
	var world: Dictionary = data["world"]
	if not (world["occupancy_owners"] is Dictionary):
		return "world.occupancy_owners"
	if not _keys_ok(world["zones"], ["count", "of", "state"]) or not _packed_ok(world["zones"]["of"]) or not (world["zones"]["state"] is Array) or not _int_in(world["zones"]["count"], 1, 255):
		return "world.zones"
	for key: Variant in (world["occupancy_owners"] as Dictionary):
		if not _vec_ok((world["occupancy_owners"] as Dictionary)[key], 4) or not str(key).is_valid_int():
			return "world.occupancy_owners"
	for key: String in ["sprout_seed"]:
		if not _is_number(world[key]):
			return "world." + key
	# clock
	var clock: Dictionary = data["clock"]
	if not _num_in(clock["elapsed"], 0.0, 1.0e9) or not _int_in(clock["growth_ticks"], 0, big) or not _int_in(clock["spread_ticks"], 0, big):
		return "clock"
	if absf(float(clock["growth_ticks"]) - floorf(float(clock["elapsed"]) / s.clock.growth_period)) > 1.0 or absf(float(clock["spread_ticks"]) - floorf(float(clock["elapsed"]) / s.clock.spread_period)) > 1.0:
		return "clock の tick と時間の不整合"
	# growth
	var growth: Dictionary = data["growth"]
	var order: Variant = _ints_unpack(growth["active"])
	var lag: Variant = _ints_unpack(growth["lag"])
	if order == null or lag == null or not _int_in(growth["ticks"], 0, big) or not _int_in(growth["cursor"], 0, n) or (order as PackedInt32Array).size() != (lag as PackedInt32Array).size():
		return "growth"
	if int(growth["cursor"]) > (order as PackedInt32Array).size():
		return "growth.cursor"
	for value: int in lag:
		if value < 0 or value > int(growth["ticks"]):
			return "growth.lag"
	# spread
	var spread: Dictionary = data["spread"]
	if not _int_in(spread["ticks"], 0, big):
		return "spread.ticks"
	for key: String in ["queue", "progress", "visits", "pending", "counted"]:
		if not _packed_ok(spread[key]):
			return "spread." + key
	if not _int_in((spread["counted"] as Dictionary)["n"], n, n):
		return "spread.counted"
	for key: String in ["queue", "pending"]:
		for index: int in WorldState._unpack_bytes(spread[key]).to_int32_array():
			if index < 0 or index >= n:
				return "spread." + key
	# far
	var far: Dictionary = data["far"]
	for key: String in ["label", "members", "comp_start", "comp_end", "comp_state", "zone_queue"]:
		if not _packed_ok(far[key]):
			return "far." + key
	if not _int_in(far["ticks"], 0, big) or not _int_in(far["sweep_cursor"], 0, maxi(n - 1, 0)) or not _int_in(far["job_zone"], -1, zones - 1) or not _int_in(far["job_scan"], 0, n) or not _int_in(far["job_head"], 0, n) or not _int_in(far["round_comp"], 0, n) or not _int_in(far["round_pos"], 0, n) or not _int_in(far["round_empty"], -1, n):
		return "far の添字"
	if not (far["job_open"] is bool) or not (far["round_active"] is bool):
		return "far のフラグ"
	if not _array_in(far["zone_enum"], zones, 0, 255) or not _array_in(far["zone_initial"], zones, 0, 1) or not _array_in(far["zone_stable_tick"], zones, -1, big):
		return "far の地域配列"
	for zone_index: int in WorldState._unpack_bytes(far["zone_queue"]).to_int32_array():
		if zone_index < 0 or zone_index >= zones:
			return "far.zone_queue"
	var members: PackedInt32Array = WorldState._unpack_bytes(far["members"]).to_int32_array()
	var starts: PackedInt32Array = WorldState._unpack_bytes(far["comp_start"]).to_int32_array()
	var ends: PackedInt32Array = WorldState._unpack_bytes(far["comp_end"]).to_int32_array()
	for index: int in members:
		if index < 0 or index >= n:
			return "far.members"
	for value: int in starts:
		if value < 0 or value > members.size():
			return "far.comp_start"
	for value: int in ends:
		if value < 0 or value > members.size():
			return "far.comp_end"
	for value: int in WorldState._unpack_bytes(far["label"]).to_int32_array():
		if value < 0 or value > starts.size():
			return "far.label"
	if int(far["round_comp"]) > starts.size() or int(far["job_head"]) > members.size():
		return "far の添字"
	# play
	var play: Dictionary = data["play"]
	var tuning: PlayTuning = s.play.tuning
	if not _int_in(play["seeds"], 0, tuning.seed_max) or not _num_in(play["water"], 0.0, tuning.water_max) or not _int_in(play["hp"], 0, s.play.hp_max):
		return "play の種・水・HP"
	if not (play["sources"] is Array) or not (play["pickups"] is Dictionary) or not (play["health"] is Dictionary) or not (play["cultivated"] is Dictionary) or not _is_str(play["selected"]):
		return "play の型"
	if not (play["pickups"].get("items", []) is Array):
		return "play.pickups"
	for item: Variant in play["pickups"].get("items", []):
		if not _keys_ok(item, ["kind", "x", "y", "age", "owner"]) or not _vec_ok([item["x"], item["y"]]) or not _is_number(item["age"]) or not _is_number(item["owner"]):
			return "play.pickups"
	for source: Variant in play["sources"]:
		if not _keys_ok(source, ["id", "timer", "drops"]) or not _is_number(source["id"]) or not _is_number(source["timer"]) or not _is_number(source["drops"]):
			return "play.sources"
	if not ((play["cultivated"] as Dictionary).get("plants", []) is Array):
		return "play.cultivated"
	for plant: Variant in (play["cultivated"] as Dictionary).get("plants", []):
		if not _keys_ok(plant, ["uid", "key", "x", "y", "size", "age", "mature", "timer", "drops"]) or not _is_number(plant["uid"]) or not _is_number(plant["x"]) or not _is_number(plant["y"]) or not _is_number(plant["size"]) or not _is_number(plant["age"]) or not _is_number(plant["timer"]) or not _is_number(plant["drops"]) or not (plant["mature"] is bool):
			return "play.cultivated"
	# enemies
	var enemies: Dictionary = data["enemies"]
	if not (enemies["nests"] is Array) or not (enemies["boars"] is Array) or not (enemies["carcasses"] is Array):
		return "enemies の型"
	var boar_keys: Array = ["id", "nest_id", "zone", "pos", "home", "hp", "facing", "mode", "goal", "goal_tile", "think", "gnaw_cooldown", "wait", "blocked_tile", "blocked_steps", "window_steps", "window_pos", "rng"]
	var px_limit: float = float(maxi(s.state.width, s.state.height) * Config.TILE_PX)
	for entry: Variant in enemies["boars"]:
		if not _keys_ok(entry, boar_keys):
			return "enemies.boars の項目"
		var boar: Dictionary = entry
		if not _vec_ok(boar["pos"]) or not _vec_ok(boar["home"]) or not _vec_ok(boar["window_pos"]) or not (boar["goal"] is Array) or ((boar["goal"] as Array).size() != 0 and not _vec_ok(boar["goal"])):
			return "enemies.boars の座標"
		for key: String in ["id", "nest_id", "zone", "facing", "mode", "goal_tile", "think", "gnaw_cooldown", "wait", "blocked_tile", "blocked_steps", "window_steps", "rng"]:
			if not _int_in(boar[key], -2147483648, 2147483647):
				return "enemies.boars." + key
		if not _int_in(boar["hp"], 1, s.enemy_tuning.boar_hp) or not _int_in(boar["zone"], 0, zones - 1) or not _int_in(boar["mode"], 0, 16) or not _int_in(boar["facing"], -16, 16):
			return "敵のHP・地域"
		if not _int_in(boar["goal_tile"], -1, n - 1) or not _int_in(boar["blocked_tile"], -1, n - 1) or not _int_in(boar["rng"], 0, 2147483647):
			return "enemies.boars の添字"
		if absf(float((boar["pos"] as Array)[0])) > px_limit or absf(float((boar["pos"] as Array)[1])) > px_limit:
			return "敵の位置"
	for entry: Variant in enemies["nests"]:
		if not _keys_ok(entry, ["id", "zone", "x", "y", "size", "hp", "hp_max", "alive"]):
			return "enemies.nests の項目"
		var nest: Dictionary = entry
		if not _int_in(nest["id"], 1, big) or not _int_in(nest["zone"], 0, zones - 1) or not _int_in(nest["x"], 0, s.state.width - 1) or not _int_in(nest["y"], 0, s.state.height - 1) or not _int_in(nest["size"], 1, 16) or not (nest["alive"] is bool):
			return "巣の座標・地域"
		if not _int_in(nest["hp_max"], 1, s.enemy_tuning.nest_hp) or not _int_in(nest["hp"], 0, nest["hp_max"]):
			return "巣のHP"
	for entry: Variant in enemies["carcasses"]:
		if not _keys_ok(entry, ["id", "x", "y", "age"]) or not _vec_ok([entry["x"], entry["y"]]) or not _int_in(entry["id"], 1, big) or not _int_in(entry["age"], 0, big):
			return "enemies.carcasses"
	# wall vegetation: rows of two arrays
	var wall: Dictionary = data["wall_growth"]
	if not (wall["entries"] is Dictionary) or not _int_in(wall["ticks"], 0, big):
		return "wall_growth"
	for key: Variant in (wall["entries"] as Dictionary):
		var row: Variant = (wall["entries"] as Dictionary)[key]
		if not _keys_ok(row, ["roots", "moss"]) or not (row["roots"] is Array) or not (row["moss"] is Array):
			return "wall_growth.entries"
		for value: Variant in (row["roots"] as Array) + (row["moss"] as Array):
			if not _num_in(value, 0.0, 1.0):
				return "wall_growth の進捗"
	return ""

static func _is_str(value: Variant) -> bool:
	return value is String

static func _invalid(what: String) -> Dictionary:
	return result_fail("invalid", "セーブデータの値が範囲外または不整合です（%s）。" % what)

## Applies the file to a freshly built session of the same map. {ok, code, reason}. The session is unusable on failure.
static func apply(s: RefCounted, data: Dictionary) -> Dictionary:
	if map_hash(s) != String(data["map_hash"]):
		return result_fail("hash", "マップの内容（地形・緑化対象）がセーブ時と違うため読み込めません。")
	var state: WorldState = s.state
	var n: int = state.tile_count()
	var bad: String = _validate_values(s, data)
	if not bad.is_empty():
		return _invalid(bad)
	var elapsed: float = float(data["game_elapsed"]) if _is_number(data["game_elapsed"]) else -1.0
	if elapsed < 0.0 or absf(elapsed - float((data["clock"] as Dictionary)["elapsed"])) > 0.000001:
		return _invalid("ゲーム時間")
	# --- world
	var world_data: Dictionary = data["world"]
	for key: String in WORLD_PACKED:
		if not _packed_ok(world_data[key]):
			return _invalid("world." + key)
		var unit: int = 4 if (key == "growth" or key == "occupant") else 1
		if int((world_data[key] as Dictionary)["n"]) != n * unit:
			return _invalid("world." + key + " の大きさ")
	if int(world_data["width"]) != state.width or int(world_data["height"]) != state.height:
		return _invalid("world の大きさ")
	if not (world_data["zones"] is Dictionary) or not (world_data["occupancy_owners"] is Dictionary):
		return _invalid("world.zones")
	var restored: WorldState = WorldState.from_dict(world_data, state.terrain_defs)
	if restored == null:
		return _invalid("world")
	if restored.terrain != state.terrain or restored.target != state.target or restored.zone_count != state.zone_count or restored.zone_of != state.zone_of:
		return result_fail("hash", "マップの内容（地形・地域）がセーブ時と違うため読み込めません。")
	var allowed_plants: Dictionary = {0: true, 1: true}
	for def: TerrainDef in state.terrain_defs:
		allowed_plants[def.initial_plant_id] = true
	for index: int in n:
		if not allowed_plants.has(int(restored.plant_id[index])):
			return _invalid("world.plant_id")
		if int(restored.moisture[index]) > s.sim_tuning.moisture_max:
			return _invalid("world.moisture")
		if int(restored.fertility[index]) > s.sim_tuning.fertility_max:
			return _invalid("world.fertility")
	# --- player position
	var session_data: Dictionary = data["session"]
	var pos: Variant = session_data["position"]
	if not (pos is Array) or (pos as Array).size() != 2 or not _is_number((pos as Array)[0]) or not _is_number((pos as Array)[1]):
		return _invalid("session.position")
	var position: Vector2 = Vector2(float((pos as Array)[0]), float((pos as Array)[1]))
	if not s.is_walkable_logic(position):
		return _invalid("プレイヤー位置")
	var res_index: Variant = (data["ui"] as Dictionary)["resolution_index"]
	if not _is_number(res_index) or int(res_index) < 0 or int(res_index) >= Config.RESOLUTIONS.size():
		return _invalid("ui.resolution_index")
	if not (session_data["zone_log"] is Array) or not (session_data["zone_times"] is Dictionary):
		return _invalid("session")
	# --- copy the restored world into the session's own WorldState (everything else holds a reference to that object)
	_copy_world(restored, state)
	# The growth sweep drops dry mature tiles from its active set lazily, so the set is not always derivable from the tile data:
	# the saved set (and its order) is put in place first, and GrowthSim.load_dict then restores the per-tile lag.
	var growth_data: Dictionary = data["growth"]
	if not _packed_ok(growth_data["active"]) or not _packed_ok(growth_data["lag"]):
		return _invalid("growth")
	var order: PackedInt32Array = WorldState._unpack_bytes(growth_data["active"]).to_int32_array()
	var seen: Dictionary = {}
	for index: int in order:
		if index < 0 or index >= n or seen.has(index):
			return _invalid("growth.active")
		seen[index] = true
	state.active_flag.fill(0)
	for index: int in order:
		state.active_flag[index] = 1
	state.active_tiles = order
	if not s.growth.load_dict(growth_data):
		return _invalid("growth")
	if not s.spread.load_dict(data["spread"]):
		return _invalid("spread")
	if not s.far.load_dict(data["far"]):
		return _invalid("far")
	if not s.clock.load_dict(data["clock"]):
		return _invalid("clock")
	if not s.wall_growth.load_dict(data["wall_growth"]):
		return _invalid("wall_growth")
	# PlayerHealth.load_dict turns a save taken while downed into a return to the respawn point (revived handler sets the
	# position): the saved position must not overwrite it.
	var saved_downed: bool = bool(((data["play"] as Dictionary)["health"] as Dictionary).get("downed", false))
	if not s.play.load_dict(data["play"]):
		return _invalid("play")
	if not s.enemies.load_dict(data["enemies"], true):
		return _invalid("enemies")
	# Position after play (a save taken while downed would revive the player at the start: the saved position is restored by
	# the revive handler only in that case, so set it for the normal case here).
	if not saved_downed:
		s.position = position
	s.zone_log.clear()
	for line: Variant in session_data["zone_log"]:
		s.zone_log.append(String(line))
	s.cleared_notices = maxi(int(session_data["cleared_notices"]), 0)
	s.zone_times = {}
	for zone_key: Variant in session_data["zone_times"]:
		var row: Dictionary = {}
		for state_key: Variant in (session_data["zone_times"][zone_key] as Dictionary):
			row[int(state_key)] = float(session_data["zone_times"][zone_key][state_key])
		s.zone_times[int(zone_key)] = row
	s.scatter_filtered = maxi(int(session_data.get("scatter_filtered", 0)), 0)
	s.shots_blocked_by_wall = maxi(int(session_data.get("shots_blocked_by_wall", 0)), 0)
	var stats: Dictionary = data["combat_stats"]
	if s.combat != null:
		s.combat.hits = int(stats.get("hits", 0))
		s.combat.fruits_dropped = int(stats.get("fruits_dropped", 0))
		s.combat.fruits_refused = int(stats.get("fruits_refused", 0))
		s.combat.fruits_direct = int(stats.get("fruits_direct", 0))
		s.combat.seeds_direct = int(stats.get("seeds_direct", 0))
	if not state.counters_consistent():
		return _invalid("カウンタ")
	s.projectiles.shots.clear()
	s.last_message = ""
	state.mark_all_dirty()
	return {"ok": true, "code": "", "reason": ""}

static func _copy_world(src: WorldState, dst: WorldState) -> void:
	dst.sprout_seed = src.sprout_seed
	dst.terrain = src.terrain
	dst.target = src.target
	dst.plant_id = src.plant_id
	dst.stage = src.stage
	dst.growth = src.growth
	dst.moisture = src.moisture
	dst.fertility = src.fertility
	dst.sprout_slot = src.sprout_slot
	dst.occupant = src.occupant
	dst.occupancy_owners = src.occupancy_owners
	dst.natural = src.natural
	dst.fruitless = src.fruitless
	dst.target_count = src.target_count
	dst.greened_count = src.greened_count
	dst.zone_of = src.zone_of
	dst.zone_count = src.zone_count
	dst.zone_state = src.zone_state
	dst.cleared = src.cleared
	dst.rebuild_derived()
	dst.rebuild_zone_counts()
