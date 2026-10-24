extends RefCounted
## 追加コンテンツの窓口。advance(dt) を呼んだ分だけ時間が進む(ポーズ中は呼ばない)。
## 出力はイベント列(Array[Dictionary]、"type"キー)。ホストのデータは直接書き換えない。
const Defs: GDScript = preload("res://scripts/content_pack/content_defs.gd")
const CropSystem: GDScript = preload("res://scripts/content_pack/crop_system.gd")
const EnemySystem: GDScript = preload("res://scripts/content_pack/enemy_system.gd")
const Common2: GDScript = preload("res://scripts/content_pack/common2.gd")

const FORMAT: int = 1

var host: RefCounted
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var crops: RefCounted
var enemies: RefCounted
var common: RefCounted
var last_error: String = ""

func _init(p_host: RefCounted, p_seed: int = 1, p_defs: Dictionary = {}) -> void:
	host = p_host
	rng.seed = p_seed
	crops = CropSystem.new(host, rng, p_defs)
	enemies = EnemySystem.new(host, rng, crops)
	# 敵側の占有(擬態・巣)と受粉源(ミツバチの巣)を植物側へ接続する
	crops.occupy_check = Callable(enemies, "occupied_by")
	crops.pollinator_extra = Callable(enemies, "pollinator_list")
	crops.enemy_feed = Callable(enemies, "threat_positions")
	common = Common2.new()
	enemies.common = common                                 # ウナギの放電が濡れたマスを参照する
	crops.manhole_check = Callable(enemies, "is_open_manhole_cell")   # 開いたマンホールには(緑化済みの条件を除いて)植えられる

func time() -> float:
	return crops.time

func advance(dt: float) -> Array[Dictionary]:
	var ev: Array[Dictionary] = []
	if dt <= 0.0:
		return ev
	common.advance(dt)
	var cev: Array[Dictionary] = crops.advance(dt)
	enemies.on_crop_events(cev)
	ev.append_array(cev)
	# ホウセンカがはじけたら、半径内の中立以外の敵へダメージ(窓口の中で敵側へ渡す)
	for x: Dictionary in cev:
		if x.type == "balsam_burst":
			ev.append_array(enemies.burst_damage(x.center, float(x.radius_px), float(x.damage)))
	var eev: Array[Dictionary] = enemies.advance(dt)
	common.note_events(eev)   # 敵が出した気絶・仕事停止を窓口が受け取る
	ev.append_array(eev)
	return ev

## 水(水やり・スプリンクラー)の着弾マスをホストから受け取る。濡れたマス(6秒)とヘチマの補充に使う。
func water_landed(cells: Array) -> Array[Dictionary]:
	var ev: Array[Dictionary] = []
	ev.append_array(common.water_landed(cells))
	ev.append_array(crops.on_water_cells(cells))
	ev.append_array(enemies.water_cells_landed(cells))   # 地中のネッコモグラが0.8m以内の水で追い出される
	return ev

## 外部(ホスト・テスト)が作ったイベントのうち、気絶・仕事停止を窓口の状態へ反映する。そのまま返す。
func relay_events(evs: Array) -> Array:
	common.note_events(evs)
	return evs

func to_dict() -> Dictionary:
	# 64bit整数はJSONの数値で精度を失うため文字列で保存する
	return {"format": FORMAT, "rng": {"seed": str(rng.seed), "state": str(rng.state)}, "crops": crops.to_dict(), "enemies": enemies.to_dict(), "common": common.to_dict()}

func from_dict(d: Dictionary) -> bool:
	last_error = ""
	if int(d.get("format", 0)) != FORMAT or typeof(d.get("rng")) != TYPE_DICTIONARY or typeof(d.get("crops")) != TYPE_DICTIONARY:
		last_error = "bad format"
		return false
	var r: Dictionary = d.rng
	if typeof(r.get("seed")) != TYPE_STRING or typeof(r.get("state")) != TYPE_STRING \
			or not (r.seed as String).is_valid_int() or not (r.state as String).is_valid_int():
		last_error = "bad rng"
		return false
	if d.has("enemies") and typeof(d.enemies) != TYPE_DICTIONARY:
		last_error = "enemies: not a dictionary"
		return false
	if d.has("common") and typeof(d.common) != TYPE_DICTIONARY:
		last_error = "common: not a dictionary"
		return false
	# 先に作業用の複製ですべて検証し、全部通ったときだけ一括で採用する(どれかが失敗したら何も変えない)
	var scratch_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	var sc: RefCounted = CropSystem.new(host, scratch_rng, crops.defs)
	if not sc.from_dict(d.crops):
		last_error = "crops: " + str(sc.last_error)
		return false
	if d.has("enemies"):
		var se: RefCounted = EnemySystem.new(host, scratch_rng, sc, enemies.defs)
		if not se.from_dict(d.enemies):
			last_error = "enemies: " + str(se.last_error)
			return false
	if d.has("common"):
		var scm: RefCounted = Common2.new()
		if not scm.from_dict(d.common):
			last_error = "common: " + str(scm.last_error)
			return false
	var ok_c: bool = crops.from_dict(d.crops)
	var ok_e: bool = true
	if d.has("enemies"):
		ok_e = enemies.from_dict(d.enemies)
	if not (ok_c and ok_e):
		last_error = "adopt failed"
		return false
	if d.has("common"):
		common.from_dict(d.common)
	else:
		common = Common2.new()
	enemies.common = common
	rng.seed = (r.seed as String).to_int()
	rng.state = (r.state as String).to_int()
	return true

## 主人公の移動速度の倍率(臭気の雲の中は×0.6)。ホストの移動処理が参照する。
func hero_move_mult() -> float:
	return enemies.hero_odor_mult()

## おたすけ植物が狙える標的(ガラスジカを除く)
func helper_targets() -> Array:
	return enemies.helper_targets()

## ガラスジカの初期配置の抽選と出現(regions = {地域キー: [候補地点]}。候補ごとに専用の乱数で5%、地域あたり最大1頭)
func place_glass_deer(world_seed: int, regions: Dictionary) -> Array:
	return enemies.place_glass_deer(world_seed, regions)

# ---------------------------------------------------------------- 敵への入力(出力はイベント列)
func hit_enemy(enemy_id: int, amount: float, kind: String, from_pos: Variant = null) -> Array[Dictionary]:
	return enemies.apply_hit(enemy_id, amount, kind, from_pos)

func splash(pos: Vector2, radius_px: float, amount: float, kind: String) -> Array[Dictionary]:
	return enemies.splash(pos, radius_px, amount, kind)
