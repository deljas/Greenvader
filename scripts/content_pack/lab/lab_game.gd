extends RefCounted
## 確認画面の状態と操作(描画・入力は含まない)。本番へ渡す部品(content_pack)をそのまま使い、
## 主人公のHP・水・種はここ(lab側)で持つ。ポーズ中・速度0では pack.advance を呼ばない。
const Host: GDScript = preload("res://scripts/content_pack/lab/lab_host.gd")
const Pack: GDScript = preload("res://scripts/content_pack/content_pack.gd")
const Grid: GDScript = preload("res://scripts/content_pack/grid_math.gd")

const SAVE_DIR: String = "user://content_lab"
const SAVE_PATH: String = "user://content_lab/save.json"
const HERO_SPEED: float = 48.0
const HERO_START: Vector2 = Vector2(160.0, 84.0)
const HERO_R: float = 4.0
const SHOT_SPEED: float = 220.0
const SHOT_RANGE: float = 140.0
const WATER_COST: float = 10.0
const WATER_RADIUS: float = 15.0
const BAZOOKA_COST: int = 5
const BAZOOKA_RADIUS: float = 25.0
const BAZOOKA_RANGE: float = 160.0
const LOG_MAX: int = 40

## 敵の選択肢(表示順)。fam=親子まとめ、pack=群れ。lab名は英数字の短い表記。
const ENEMY_LIST: Array = [
	["shadow_brian", "BRIAN"], ["tarachunade", "TARACHU"], ["mushling_parent", "MUSH+2"], ["quill_hedgehog", "QUILL"],
	["grass_snake", "SNAKE"], ["seed_bird", "SEEDBIRD"], ["junk_crab", "JUNKCRAB"], ["stray_wolf", "WOLF x3"],
	["moss_turtle", "TURTLE"], ["paint_chameleon", "CHAMELE"], ["slime_slug", "SLUG"], ["pouch_rabbit", "RABBIT"],
	["tongue_frog", "FROG"], ["honeybee_hive", "BEEHIVE"], ["armadillo", "ARMADIL"], ["sludge_carp", "CARP"],
	["leafcutter_ant", "ANT"], ["ant_hill", "ANTHILL"], ["mimic_cabbage", "MIMIC"], ["black_kite", "KITE"],
	["deer", "DEER"], ["iron_jaw_beetle", "BEETLE"], ["junk_pile", "+PILE"],
]
const CROP_LIST: Array = [
	["clover", "CLOVER"], ["wasabi", "WASABI"], ["giant_watermelon", "MELON"], ["oleander", "OLEANDER"],
	["golden_clover", "GOLDCLV"], ["edamame", "EDAMAME"], ["sunflower", "SUNFLR"], ["tomato", "TOMATO"],
	["lotus", "LOTUS"], ["corn", "CORN"], ["pumpkin", "PUMPKIN"], ["mint", "MINT"], ["cactus", "CACTUS"],
	["grape", "GRAPE"], ["strawberry", "STRAWB"], ["lavender", "LAVEND"], ["garlic", "GARLIC"], ["bamboo", "BAMBOO"],
	["flytrap", "FLYTRAP"], ["potato", "POTATO"], ["rice", "RICE"], ["tea", "TEA"], ["sakura", "SAKURA"],
	["dokudami", "DOKUDAMI"], ["aloe", "ALOE"], ["pepper", "PEPPER"], ["glow_moss", "GLOWMOSS"],
]
## 範囲効果のプレビュー(半径マス, 色)。金=黄金、黄=ミツバチ、緑=エダマメ、紫=キョウチクトウ等
const RANGE_PREVIEW: Dictionary = {
	"golden_clover": [7, Color(1.0, 0.85, 0.2)], "golden_four_leaf": [7, Color(1.0, 0.85, 0.2)],
	"edamame": [1, Color(0.3, 0.9, 0.3)], "oleander": [3, Color(0.7, 0.3, 0.9)], "lavender": [4, Color(0.6, 0.5, 1.0)],
	"garlic": [3, Color(0.95, 0.95, 0.85)], "pumpkin": [1, Color(1.0, 0.55, 0.15)], "aloe": [4, Color(1.0, 0.5, 0.7)],
	"glow_moss": [5, Color(0.4, 1.0, 0.9)], "corn": [1, Color(0.8, 0.9, 0.3)], "honeybee_hive": [8, Color(1.0, 0.9, 0.2)],
}

var host: RefCounted
var pack: RefCounted
var seeds: int = 300
var seed_acc: float = 0.0
var hp: float = 100.0
var max_hp: float = 100.0
var water: float = 100.0
var max_water: float = 100.0
var hero_pos: Vector2 = HERO_START
var aim: Vector2 = Vector2.RIGHT
var slow_factor: float = 1.0
var slow_until: float = 0.0
var elapsed: float = 0.0
var paused: bool = false
var speed: int = 1
var tool: String = "combat"       # combat / enemy / crop / remove
var tab: String = "enemy"
var sel_enemy: String = "deer"
var sel_crop: String = "clover"
var origin: String = "initial"
var sel_crop_id: int = 0
var hover_cell: Vector2i = Vector2i(-1, -1)
var mouse_world: Vector2 = Vector2.ZERO
var bullets: Array = []
var fx_list: Array = []
var log: Array = []
var counts: Dictionary = {}
var rewards_total: int = 0
var landed: int = 0
var msg: String = ""
var show_hidden: bool = false
var terrain_dirty: bool = true
var debug_flash_until: float = -1.0
var move_keys: Vector2 = Vector2.ZERO   # 注入・テスト用の移動入力(キー入力と合算)
var use_keys: bool = true
var _seq: int = 0

func _init(p_seed: int = 7) -> void:
	host = Host.new()
	pack = Pack.new(host, p_seed)
	_sync_hero()

# ---------------------------------------------------------------- 基本
func _sync_hero() -> void:
	host.hero_state = {"pos": hero_pos, "hp": hp, "max_hp": max_hp, "aim": aim}

func is_day() -> bool:
	return host.day

func toggle_day() -> void:
	host.day = not host.day
	note("DAY" if host.day else "NIGHT", "ui")

func set_speed(s: int) -> void:
	speed = s

func toggle_pause() -> void:
	paused = not paused
	note("PAUSE" if paused else "RESUME", "ui")

func note(text: String, kind: String = "info") -> void:
	log.append({"text": text, "kind": kind, "t": elapsed})
	if log.size() > LOG_MAX:
		log.pop_front()

func cnt(type: String) -> int:
	return int(counts.get(type, 0))

func hero_walkable(p: Vector2) -> bool:
	var c: Vector2i = Grid.cell_of_pos(p)
	if not host.in_bounds(c) or not host.is_walkable(c) or host.is_blocked(c):
		return false
	if pack.enemies.structure_at(c) != "" or pack.crops.blocks_enemy(c):
		return false
	for b: Dictionary in pack.enemies.body_blockers():
		if Vector2(b.pos).distance_to(p) < float(b.radius) + HERO_R - 1.0:
			return false
	return true

# ---------------------------------------------------------------- 時間
## real_dt は実時間の秒。ポーズ中・速度0では何も進めない(pack.advance を呼ばない)。
func step(real_dt: float) -> void:
	if paused or speed <= 0 or real_dt <= 0.0:
		return
	var left: float = real_dt * float(speed)
	while left > 1e-9:
		var s: float = minf(left, 0.1)
		_tick(s, s / float(speed))
		left -= s

func _tick(gdt: float, hero_dt: float) -> void:
	elapsed += gdt
	_move_hero(hero_dt)
	_update_bullets(hero_dt)
	water = minf(max_water, water + 4.0 * gdt)
	_sync_hero()
	apply_events(pack.advance(gdt))
	_sync_hero()
	for f: Dictionary in fx_list.duplicate():
		if elapsed - float(f.t0) > float(f.life):
			fx_list.erase(f)

func _move_hero(dt: float) -> void:
	var v: Vector2 = move_keys
	if use_keys:
		if Input.is_physical_key_pressed(KEY_W): v.y -= 1.0
		if Input.is_physical_key_pressed(KEY_S): v.y += 1.0
		if Input.is_physical_key_pressed(KEY_A): v.x -= 1.0
		if Input.is_physical_key_pressed(KEY_D): v.x += 1.0
	if v == Vector2.ZERO:
		return
	var spd: float = HERO_SPEED * (slow_factor if elapsed < slow_until else 1.0)
	var step_v: Vector2 = v.normalized() * spd * dt
	for axis: Vector2 in [Vector2(step_v.x, 0.0), Vector2(0.0, step_v.y)]:
		if hero_walkable(hero_pos + axis):
			hero_pos += axis

func set_aim_to(world: Vector2) -> void:
	mouse_world = world
	var d: Vector2 = world - hero_pos
	if d.length() > 0.5:
		aim = d.normalized()

# ---------------------------------------------------------------- 主人公の攻撃
func shoot(target: Vector2) -> bool:
	if seeds <= 0:
		msg = "NO SEEDS"
		return false
	set_aim_to(target)
	seeds -= 1
	bullets.append({"pos": hero_pos, "dir": aim, "left": SHOT_RANGE})
	return true

func _update_bullets(dt: float) -> void:
	for b: Dictionary in bullets.duplicate():
		var rem: float = SHOT_SPEED * dt
		var done: bool = false
		while rem > 1e-6 and not done:
			var st: float = minf(rem, 2.0)
			rem -= st
			b.pos = Vector2(b.pos) + Vector2(b.dir) * st
			b.left = float(b.left) - st
			var cell: Vector2i = Grid.cell_of_pos(b.pos)
			if not host.in_bounds(cell) or host.is_building(cell):
				done = true
				break
			for t: Dictionary in pack.enemies.hittable_targets():
				if Vector2(t.pos).distance_to(b.pos) <= float(t.radius) + 1.5:
					apply_events(pack.hit_enemy(int(t.id), 5.0, "shot", hero_pos))
					fx_add("hit", b.pos, 0.25)
					done = true
					break
			if not done and float(b.left) <= 0.0:
				# 地面に落ちた種。近くの擬態を見破る
				landed += 1
				apply_events(pack.enemies.notify_seed(b.pos))
				fx_add("seed_land", b.pos, 0.4)
				done = true
		if done:
			bullets.erase(b)

func do_water(target: Vector2) -> bool:
	if water < WATER_COST:
		msg = "NO WATER"
		return false
	set_aim_to(target)
	water -= WATER_COST
	apply_events(pack.splash(target, WATER_RADIUS, 0.0, "water"))
	for c: Dictionary in pack.crops.crops:
		var r: Rect2 = Rect2(Vector2(c.cell) * Grid.CELL_PX, Vector2(c.size) * Grid.CELL_PX)
		var q: Vector2 = Vector2(clampf(target.x, r.position.x, r.end.x), clampf(target.y, r.position.y, r.end.y))
		if q.distance_to(target) <= WATER_RADIUS:
			pack.crops.set_watered(int(c.id), true)
	fx_add("water", target, 0.5)
	return true

func tackle(target: Vector2) -> bool:
	set_aim_to(target)
	var front: Vector2 = hero_pos + aim * 14.0
	if hero_walkable(front):
		hero_pos = front
	fx_add("tackle", hero_pos, 0.25)
	apply_events(pack.splash(hero_pos + aim * 6.0, 10.0, 8.0, "tackle"))
	_sync_hero()
	return true

func bazooka(target: Vector2) -> bool:
	if seeds < BAZOOKA_COST:
		msg = "NO SEEDS"
		return false
	set_aim_to(target)
	var t: Vector2 = target
	if hero_pos.distance_to(t) > BAZOOKA_RANGE:
		t = hero_pos + (t - hero_pos).normalized() * BAZOOKA_RANGE
	if not host.line_clear(hero_pos, t):
		msg = "BLOCKED"
		return false
	seeds -= BAZOOKA_COST
	fx_add("explosion", t, 0.5, {"radius_px": BAZOOKA_RADIUS})
	apply_events(pack.splash(t, BAZOOKA_RADIUS, 25.0, "bazooka"))
	return true

func fx_add(kind: String, pos: Vector2, life: float, extra: Dictionary = {}) -> void:
	var d: Dictionary = {"kind": kind, "pos": pos, "t0": elapsed, "life": life}
	d.merge(extra, true)
	fx_list.append(d)

# ---------------------------------------------------------------- イベントの反映(ホスト側)
func apply_events(evs: Array) -> void:
	for x: Variant in evs:
		var e: Dictionary = x
		var type: String = str(e.get("type", ""))
		counts[type] = int(counts.get(type, 0)) + 1
		match type:
			"hero_damage":
				hp -= float(e.amount)
				note("HURT -%d %s" % [int(round(float(e.amount))), str(e.get("kind", "")).to_upper()], "damage")
				if hp <= 0.0:
					hp = max_hp
					hero_pos = HERO_START
					note("HERO DOWN: RESPAWN", "damage")
			"helper_damage":
				note("HELPER -%d" % int(round(float(e.amount))), "damage")
			"hero_pull":
				var to: Vector2 = Vector2(e.to)
				if hero_walkable(to):
					hero_pos = to
				fx_add("pull", hero_pos, 0.3)
			"hero_slow":
				slow_factor = float(e.factor)
				slow_until = maxf(slow_until, elapsed + float(e.seconds))
			"reward":
				seeds += int(e.amount)
				rewards_total += int(e.amount)
				note("REWARD +%d %s" % [int(e.amount), str(e.get("kind", "")).to_upper()], "reward")
			"seeds":
				seed_acc += float(e.amount)
				var whole: int = int(floor(seed_acc))
				if whole > 0:
					seeds += whole
					seed_acc -= float(whole)
			"pickup_collected":
				seeds += int(e.amount)
				note("PICKUP +%d" % int(e.amount), "reward")
			"ground_stage":
				host.set_stage(Vector2i(e.cell), str(e.stage))
				terrain_dirty = true
			"enemy_damaged":
				var tgt: Dictionary = pack.enemies.ref(int(e.get("enemy_id", 0)))
				var tname: String = str(tgt.get("kind", "enemy")).to_upper()
				note("HIT %s -%d (%s)" % [tname, int(round(float(e.amount))), str(e.get("kind", "")).to_upper()], "hit")
			"enemy_defeated":
				note("DEFEAT %s" % str(e.get("kind", "")).to_upper(), "defeat")
			"crop_matured":
				note("MATURE %s" % str(e.get("kind", "")).to_upper(), "crop")
			"crop_removed":
				if str(e.reason) != "manual":
					note("LOST %s (%s)" % [str(e.kind).to_upper(), str(e.reason).to_upper()], "damage")
			"variant_roll":
				var tag: String = "DEBUG " if bool(e.get("debug", false)) else ""
				note("%sROLL %s %s" % [tag, "HIT" if bool(e.hit) else "MISS", str(e.kind).to_upper()], "debug" if bool(e.get("debug", false)) else "crop")
			"variant":
				var tag2: String = "DEBUG " if bool(e.get("debug", false)) else ""
				note("%sVARIANT %s>%s" % [tag2, str(e.from).to_upper(), str(e.to).to_upper()], "debug" if bool(e.get("debug", false)) else "crop")
			"mint_spread":
				note("MINT SPREAD", "crop")
			"fx":
				var k: String = str(e.get("kind", ""))
				fx_add(k, Vector2(e.pos), 0.6, e)
				if k in ["wet", "explosion", "revive", "howl", "stuck", "rage", "shell_break", "carp_warn", "mushling_call"]:
					note("FX " + k.to_upper(), "fx")
			"mushling_call":
				note("MUSH CALL", "fx")
			"junk_pile_destroyed":
				note("PILE DOWN", "defeat")

# ---------------------------------------------------------------- 敵の出現・植物の配置
func cell_of(world: Vector2) -> Vector2i:
	return Grid.cell_of_pos(world)

func spawn_enemy(kind: String, world: Vector2) -> Dictionary:
	var cell: Vector2i = cell_of(world)
	if not host.in_bounds(cell):
		return {"ok": false, "reason": "outside"}
	var es: RefCounted = pack.enemies
	if kind == "junk_pile":
		if not host.is_walkable(cell):
			return {"ok": false, "reason": "not_walkable"}
		return {"ok": true, "id": es.add_junk_pile(Grid.center_of_cell(cell), 2)}
	var hab: String = str(es.defs.get(kind, {}).get("habitat", "land"))
	if kind == "sludge_carp":
		if not host.is_water(cell):
			note("CARP NEEDS WATER", "ui")
			return {"ok": false, "reason": "needs_water"}
	elif hab == "land" and (not host.is_walkable(cell) or host.is_blocked(cell) or es.structure_at(cell) != ""):
		note("NOT WALKABLE", "ui")
		return {"ok": false, "reason": "not_walkable"}
	var pos: Vector2 = world
	var id: int = -1
	match kind:
		"mushling_parent":
			id = int(es.spawn_mushling_family(pos, origin)["parent"])
		"stray_wolf":
			id = int(es.spawn_wolf_pack(pos, origin)[0])
		"honeybee_hive":
			pos = Grid.center_of_cell(cell)
			id = es.spawn(kind, pos, origin)
		"ant_hill":
			pos = Vector2(cell + Vector2i(1, 1)) * Grid.CELL_PX
			id = es.spawn(kind, pos, origin)
		"junk_crab":
			var opts: Dictionary = {}
			if es.piles.is_empty():
				opts["piles"] = [{"pos": pos + Vector2(28.0, 0.0), "stock": 2}]
			id = es.spawn(kind, pos, origin, opts)
		_:
			id = es.spawn(kind, pos, origin)
	return {"ok": id >= 0, "id": id}

func crop_cell_for(kind: String, hover: Vector2i) -> Vector2i:
	var s: Vector2i = pack.crops.size_of(kind)
	return hover - Vector2i((s.x - 1) / 2, (s.y - 1) / 2)

func preview(kind: String, hover: Vector2i) -> Dictionary:
	var cell: Vector2i = crop_cell_for(kind, hover)
	var chk: Dictionary = pack.crops.check_placement(kind, cell)
	var price: int = pack.crops.quote(kind)
	var ok: bool = bool(chk.ok) and bool(pack.crops.def_of(kind).get("placeable", true))
	return {"kind": kind, "cell": cell, "size": pack.crops.size_of(kind), "ok": ok, "reason": str(chk.reason), "price": price, "afford": seeds >= price}

func place(kind: String, hover: Vector2i) -> Dictionary:
	var pv: Dictionary = preview(kind, hover)
	if not bool(pv.ok):
		msg = "CANT: " + str(pv.reason).to_upper()
		return {"ok": false, "reason": pv.reason}
	if seeds < int(pv.price):
		msg = "NO SEEDS"
		return {"ok": false, "reason": "no_seeds"}
	var r: Dictionary = pack.crops.place_crop(kind, pv.cell)
	if bool(r.ok):
		seeds -= int(r.paid)
		sel_crop_id = int(r.id)
		note("PLACE %s -%d" % [kind.to_upper(), int(r.paid)], "crop")
		apply_events(r.events)
	return r

func remove_at(cell: Vector2i) -> Dictionary:
	var id: int = pack.crops.crop_id_at(cell)
	if id <= 0:
		msg = "NOTHING HERE"
		return {"ok": false}
	var r: Dictionary = pack.crops.remove_crop(id, "manual")
	if bool(r.ok):
		seeds += int(r.refund)
		note("REMOVE +%d" % int(r.refund), "crop")
		apply_events(r.events)
		if sel_crop_id == id:
			sel_crop_id = 0
	return r

func update_hover(cell: Vector2i) -> void:
	hover_cell = cell
	var cid: int = pack.crops.crop_id_at(cell)
	if cid > 0:
		sel_crop_id = cid

func clear_enemies() -> void:
	var es: RefCounted = pack.enemies
	es.enemies.clear()
	es._by_id.clear()
	es.piles.clear()
	es.projectiles.clear()
	es.gas.clear()
	es.slime.clear()
	note("CLEAR ENEMIES", "ui")

# ---------------------------------------------------------------- デバッグ(通常の仕様とは区別する)
func _debug_note() -> void:
	debug_flash_until = elapsed + 3.0

func debug_roll(hit: bool) -> void:
	_debug_note()
	if sel_crop_id <= 0 or pack.crops.get_crop(sel_crop_id).is_empty():
		note("DEBUG ROLL: NO CROP SELECTED", "debug")
		return
	var evs: Array = pack.crops.debug_force_roll(sel_crop_id, hit)
	if evs.is_empty():
		note("DEBUG ROLL: NOT ROLLABLE", "debug")
	apply_events(evs)

func debug_seeds() -> void:
	_debug_note()
	seeds += 100
	note("DEBUG SEEDS +100", "debug")

func debug_mature() -> void:
	_debug_note()
	var ids: Array = []
	if sel_crop_id > 0 and not pack.crops.get_crop(sel_crop_id).is_empty():
		ids.append(sel_crop_id)
	else:
		for c: Dictionary in pack.crops.crops:
			if not bool(c.mature):
				ids.append(int(c.id))
	for id: Variant in ids:
		apply_events(pack.crops.debug_force_mature(int(id), false))
	note("DEBUG MATURE x%d" % ids.size(), "debug")

func debug_water_all() -> void:
	_debug_note()
	for c: Dictionary in pack.crops.crops:
		pack.crops.set_watered(int(c.id), true)
	note("DEBUG WATER ALL", "debug")

# ---------------------------------------------------------------- 保存・復元(user://content_lab/ 専用)
func save() -> bool:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SAVE_DIR))
	var st: Array = []
	for k: Variant in host.stage_override.keys():
		var c: Vector2i = k
		st.append([c.x, c.y, host.stage_override[c]])
	var d: Dictionary = {"format": 1, "pack": pack.to_dict(), "stage": st, "day": host.day, "elapsed": elapsed,
		"hero": {"x": hero_pos.x, "y": hero_pos.y, "hp": hp, "water": water, "seeds": seeds, "seed_acc": seed_acc, "ax": aim.x, "ay": aim.y}}
	var f: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		msg = "SAVE FAILED"
		return false
	f.store_string(JSON.stringify(d))
	f.close()
	note("SAVED", "ui")
	return true

func load_save() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		msg = "NO SAVE"
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if typeof(parsed) != TYPE_DICTIONARY or typeof((parsed as Dictionary).get("pack")) != TYPE_DICTIONARY:
		msg = "BAD SAVE"
		return false
	var d: Dictionary = parsed
	if not pack.from_dict(d.pack):
		msg = "LOAD FAILED: " + str(pack.last_error)
		return false
	host.stage_override.clear()
	for s: Variant in d.get("stage", []):
		var a: Array = s
		host.stage_override[Vector2i(int(a[0]), int(a[1]))] = str(a[2])
	terrain_dirty = true
	host.day = bool(d.get("day", true))
	elapsed = float(d.get("elapsed", 0.0))
	var h: Dictionary = d.get("hero", {})
	hero_pos = Vector2(float(h.get("x", HERO_START.x)), float(h.get("y", HERO_START.y)))
	hp = float(h.get("hp", max_hp))
	water = float(h.get("water", max_water))
	seeds = int(h.get("seeds", seeds))
	seed_acc = float(h.get("seed_acc", 0.0))
	aim = Vector2(float(h.get("ax", 1.0)), float(h.get("ay", 0.0)))
	bullets.clear()
	fx_list.clear()
	sel_crop_id = 0
	_sync_hero()
	note("LOADED", "ui")
	return true

# ---------------------------------------------------------------- 情報欄
func total_rate_per_min() -> float:
	var t: float = 0.0
	for c: Dictionary in pack.crops.crops:
		if c.kind == "potato":
			continue
		t += float(pack.crops.production_info(int(c.id)).rate)
	return t * 60.0

func selected_info() -> String:
	var c: Dictionary = pack.crops.get_crop(sel_crop_id) if sel_crop_id > 0 else {}
	if c.is_empty():
		return "SEL: NONE (HOVER A PLANT)"
	var pi: Dictionary = pack.crops.production_info(int(c.id))
	var s: String = "SEL %s #%d %s HP%d" % [str(c.kind).to_upper(), int(c.id), "MATURE" if bool(c.mature) else "GROW %d%%" % int(100.0 * float(c.grow) / maxf(1.0, float(pack.crops.def_of(str(c.kind)).maturity))), int(c.hp)]
	if bool(c.mature):
		s += "  BASE %.2f/M FINAL %.2f/M GOLDK%d BEE+%d%%" % [float(pi.base) * 60.0, float(pi.rate) * 60.0, int(pi.gold_k), int(round(float(pi.bee_bonus) * 100.0))]
		if c.kind == "potato":
			s += " STORED %d" % int(float(c.storage))
	return s

func info_lines() -> Array[String]:
	var out: Array[String] = []
	out.append("SEEDS %d  HP %d/%d  WATER %d  T %.0fS  X%d%s  %s  TOOL %s" % [seeds, int(hp), int(max_hp), int(water), elapsed, speed, " PAUSED" if paused else "", "DAY" if host.day else "NIGHT", tool.to_upper()])
	out.append(selected_info())
	out.append("TOTAL %.1f SEEDS/MIN  PLANTS %d  STABLE-COUNT ENEMIES %d" % [total_rate_per_min(), pack.crops.crops.size(), pack.enemies.living_count_for_stability()])
	if tool == "crop":
		var pv: Dictionary = preview(sel_crop, hover_cell)
		out.append("PLACE %s PRICE %d %s" % [sel_crop.to_upper(), int(pv.price), "OK" if bool(pv.ok) and bool(pv.afford) else ("NO SEEDS" if bool(pv.ok) else "NG " + str(pv.reason).to_upper())])
	elif msg != "":
		out.append(msg)
	else:
		out.append("")
	var recent: Array = log.slice(maxi(0, log.size() - 4))
	for r: Variant in recent:
		out.append(str((r as Dictionary).text))
	return out
