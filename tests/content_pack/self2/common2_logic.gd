extends SceneTree
## 第2弾の共通の追加(向き・草食タグ・濡れたマス・動的な日陰・報酬の即時加算・気絶/仕事停止)の自己検証(入口スクリプト)。
## 実行(隔離プロジェクトのみ): Godot --headless --path C:/godot/greenvader_content_sandbox --script res://tests/content_pack/self2/common2_logic.gd
const Lab: GDScript = preload("res://scripts/content_pack/lab/lab_host.gd")
const Pack: GDScript = preload("res://scripts/content_pack/content_pack.gd")
const Grid: GDScript = preload("res://scripts/content_pack/grid_math.gd")
const Facing: GDScript = preload("res://scripts/content_pack/facing.gd")
const Common2: GDScript = preload("res://scripts/content_pack/common2.gd")
const Defs: GDScript = preload("res://scripts/content_pack/content_defs.gd")
const OUT_DIR: String = "res://evidence/content_pack/self2"

var checks: Array = []

func ck(name: String, ok: bool, detail: String = "") -> void:
	checks.append({"name": name, "status": "PASS" if ok else "FAIL", "detail": detail})

func mk(seed: int = 1) -> RefCounted:
	return Pack.new(Lab.new(), seed)

func sp(p: RefCounted, kind: String, x: int, y: int, mature: bool = true, watered: bool = true) -> int:
	var cost: int = int(p.crops.def_of(kind).cost)
	var r: Dictionary = p.crops.spawn_crop(kind, Vector2i(x, y), cost, {"mature": mature, "watered": watered})
	return int(r.id) if bool(r.ok) else -1

func evs(events: Array, type: String) -> Array:
	var out: Array = []
	for e: Dictionary in events:
		if e.type == type:
			out.append(e)
	return out

func near(a: float, b: float, eps: float = 1e-6) -> bool:
	return absf(a - b) <= eps * maxf(1.0, absf(b))

func rate(p: RefCounted, id: int) -> float:
	return float(p.crops.production_info(id).rate)

func cond(p: RefCounted, id: int) -> float:
	return float(p.crops.production_info(id).condition)

func _initialize() -> void:
	t_facing()
	t_herbivore()
	t_wet()
	t_shade()
	t_reward_stun_pause()
	var fails: int = 0
	for c: Dictionary in checks:
		print("%s %s %s" % [c.status, c.name, c.detail])
		if c.status != "PASS":
			fails += 1
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var f: FileAccess = FileAccess.open(OUT_DIR + "/common2_logic.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"suite": "common2_logic", "total": checks.size(), "failed": fails, "checks": checks}, "\t"))
	f.close()
	print("common2_logic total=%d failed=%d" % [checks.size(), fails])
	quit(1 if fails > 0 else 0)

# ------------------------------------------------------------------ 1.2 向き
func t_facing() -> void:
	var own: Vector2 = Vector2(100, 100)
	var face: Vector2 = Vector2.RIGHT
	ck("facing_front_ahead", Facing.is_front(face, own, Vector2(200, 100)), "")
	ck("facing_boundary_60deg_inclusive", Facing.is_front(face, own, own + Vector2.RIGHT.rotated(deg_to_rad(60.0)) * 50.0), "60 deg is front")
	ck("facing_61deg_is_not_front", not Facing.is_front(face, own, own + Vector2.RIGHT.rotated(deg_to_rad(61.0)) * 50.0), "")
	ck("facing_behind_and_side_not_front", not Facing.is_front(face, own, Vector2(0, 100)) and not Facing.is_front(face, own, Vector2(100, 200)), "")
	ck("facing_non_vector_origin_is_false", not Facing.is_front(face, own, null), "")
	# 攻撃ごとの基準位置: 弾は発射元、爆風は爆心、たいあたりは主人公の位置
	var shooter: Vector2 = Vector2(10, 10)
	var blast: Vector2 = Vector2(20, 20)
	var hero: Vector2 = Vector2(30, 30)
	ck("facing_attack_origin_by_kind", Facing.attack_origin("shot", shooter, blast, hero) == shooter and Facing.attack_origin("helper", shooter, blast, hero) == shooter \
		and Facing.attack_origin("bazooka", shooter, blast, hero) == blast and Facing.attack_origin("tackle", shooter, blast, hero) == hero \
		and Facing.attack_origin("water", shooter, blast, hero) == null, "")
	# 旋回上限
	var f1: Vector2 = Facing.turn_toward(Vector2.RIGHT, Vector2.DOWN, 90.0, 0.5)
	ck("facing_turn_limited_to_rate", near(rad_to_deg(Vector2.RIGHT.angle_to(f1)), 45.0, 1e-4), "deg=%.3f" % rad_to_deg(Vector2.RIGHT.angle_to(f1)))
	var f2: Vector2 = Facing.turn_toward(Vector2.RIGHT, Vector2.DOWN, 90.0, 2.0)
	ck("facing_turn_reaches_target_when_enough", near(f2.x, 0.0, 1e-6) and near(f2.y, 1.0, 1e-6), str(f2))
	var f3: Vector2 = Facing.turn_toward(Vector2.RIGHT, Vector2.LEFT, 120.0, 0.5)
	ck("facing_turn_180_takes_limited_step", near(absf(rad_to_deg(Vector2.RIGHT.angle_to(f3))), 60.0, 1e-4), "")
	# 旋回上限があるので、背後へ回り込まれた直後はまだ正面ではない(カガミトカゲの120度/秒を想定)
	var f4: Vector2 = Facing.turn_toward(Vector2.RIGHT, Vector2.LEFT, 120.0, 0.2)
	ck("facing_after_short_turn_target_behind_not_front", not Facing.is_front(f4, own, Vector2(0, 100)), "")

# ------------------------------------------------------------------ 1.3 草食タグ
func t_herbivore() -> void:
	var p: RefCounted = mk()
	var defs: Dictionary = p.enemies.defs
	var herb: Array = []
	for k: String in ["deer", "pouch_rabbit", "moss_turtle", "slime_slug", "leafcutter_ant", "mimic_cabbage"]:
		if (defs[k].tags as Array).has(Defs.TAG_HERBIVORE):
			herb.append(k)
	ck("herbivore_tag_on_6_first_series_kinds", herb.size() == 6, str(herb))
	var non: Array = []
	for k: String in defs:
		if (defs[k].tags as Array).has(Defs.TAG_HERBIVORE) and not herb.has(k):
			non.append(k)
	ck("herbivore_tag_not_on_other_kinds", non.is_empty(), str(non))
	# 既存のバッタ(ホスト側の敵)を、草食タグつきで接続口から渡せる
	var a: int = sp(p, "apple", 22, 24)
	p.advance(30.0)
	var id: int = p.enemies.spawn("deer", Vector2(60, 60))
	ck("herbivore_tag_in_tags_of", p.enemies.tags_of(p.enemies.get_enemy(id)).has("herbivore"), "")
	ck("herbivore_apple_dropped", p.crops.fruit_list().size() == 1, "")
	p.host.host_enemy_list = [{"id": "hopper1", "pos": Vector2(100, 130), "neutral": false, "tags": ["bug", "small", "herbivore"]}]
	var he: Dictionary = p.host.host_enemies()[0]
	var f: Dictionary = p.crops.nearest_attracting_fruit(he.tags, he.pos, 200.0)
	ck("herbivore_host_side_enemy_attracted", not f.is_empty(), "")
	ck("herbivore_non_tag_not_attracted", p.crops.nearest_attracting_fruit(["beast"], he.pos, 200.0).is_empty(), "")
	ck("herbivore_out_of_range_not_attracted", p.crops.nearest_attracting_fruit(he.tags, Vector2(500, 500), 100.0).is_empty(), "")
	p.host.set_stable_rect(Rect2i(18, 20, 10, 10))
	ck("herbivore_fruit_in_stable_region_excluded", p.crops.nearest_attracting_fruit(he.tags, he.pos, 200.0).is_empty(), "")
	ck("herbivore_apple_still_alive", a > 0, "")

# ------------------------------------------------------------------ 1.4 濡れたマス
func t_wet() -> void:
	var p: RefCounted = mk()
	var c: Vector2i = Vector2i(30, 30)
	var ev: Array = p.water_landed([c, Vector2i(31, 30)])
	ck("wet_event_per_cell", evs(ev, "wet_cell").size() == 2, "")
	ck("wet_immediately_true", p.common.is_wet(c), "")
	p.advance(5.9)
	ck("wet_still_wet_at_5_9s", p.common.is_wet(c), "")
	p.advance(0.2)
	ck("wet_dry_after_6s", not p.common.is_wet(c) and p.common.wet_cells().is_empty(), "")
	# 再び水が当たると6秒に延長
	p.water_landed([c])
	p.advance(4.0)
	p.water_landed([c])
	p.advance(4.0)
	ck("wet_extended_by_second_hit", p.common.is_wet(c), "")
	# ポーズ中(advanceを呼ばない)は進まない
	var t0: float = p.common.time
	var snapshot: String = JSON.stringify(p.common.to_dict())
	for i: int in range(10):
		pass
	ck("wet_pause_no_progress", near(p.common.time, t0) and JSON.stringify(p.common.to_dict()) == snapshot and p.advance(0.0).is_empty(), "")
	# 濡れは成長や給水の規則に影響しない
	var id: int = sp(p, "bamboo", 30, 30, false, false)
	ck("wet_does_not_change_growth_rule", near(p.crops.growth_rate(id), 0.5), "")
	# 保存復元で濡れが残る
	var d: Dictionary = JSON.parse_string(JSON.stringify(p.to_dict()))
	var q: RefCounted = mk(99)
	ck("wet_save_restore", q.from_dict(d) and q.common.is_wet(c), str(q.last_error))
	q.advance(2.5)
	ck("wet_restored_expires_on_schedule", not q.common.is_wet(c), "")

# ------------------------------------------------------------------ 1.5 動的な日陰
func t_shade() -> void:
	var p: RefCounted = mk()
	var h: int = sp(p, "hinoki", 20, 22, false, true)
	var dk_in: int = sp(p, "dokudami", 21, 21)
	var dk_side: int = sp(p, "dokudami", 23, 21)
	var dk_far: int = sp(p, "dokudami", 21, 19)
	var dk_static: int = sp(p, "dokudami", 30, 12)
	ck("shade_hinoki_3x3_placed", h > 0 and p.crops.crop_id_at(Vector2i(22, 24)) == h and p.crops.crop_id_at(Vector2i(23, 24)) == 0, "")
	ck("shade_immature_hinoki_makes_none", p.crops.dynamic_shade_cells().is_empty() and near(cond(p, dk_in), 1.0), "")
	ck("shade_static_attribute_still_works", near(cond(p, dk_static), 2.0), "")
	p.crops.debug_force_mature(h)
	var cells: Array = p.crops.dynamic_shade_cells()
	ck("shade_mature_hinoki_north_2x3", cells.size() == 6 and cells.has(Vector2i(20, 20)) and cells.has(Vector2i(22, 21)) and not cells.has(Vector2i(23, 21)) and not cells.has(Vector2i(21, 19)) and not cells.has(Vector2i(21, 22)), str(cells.size()))
	ck("shade_dokudami_in_dynamic_shade_x2", near(cond(p, dk_in), 2.0), "")
	ck("shade_dokudami_beside_or_far_not_shaded", near(cond(p, dk_side), 1.0) and near(cond(p, dk_far), 1.0), "")
	ck("shade_dokudami_growth_x1_5_under_dynamic_shade", near(p.crops.growth_rate(dk_in), 1.5) and near(p.crops.growth_rate(dk_far), 1.0), "")
	# 静的と動的の論理和(同じマスに両方でも倍率は2.0のまま)
	p.host.shade[21 * 64 + 21] = 1
	ck("shade_static_or_dynamic_not_stacked", near(cond(p, dk_in), 2.0), "")
	# 日陰は常時判定。ヒノキが失われると消える
	p.crops.remove_crop(h, "enemy")
	ck("shade_removed_with_hinoki", p.crops.dynamic_shade_cells().is_empty(), "")
	p.host.shade[21 * 64 + 21] = 0
	ck("shade_dokudami_loses_multiplier", near(cond(p, dk_in), 1.0) and near(cond(p, dk_static), 2.0), "")
	# 生産への反映(種/秒): 定義2/分
	var h2: int = sp(p, "hinoki", 20, 22, true, true)
	ck("shade_rate_follows_in_production", near(rate(p, dk_in), 2.0 / 60.0 * 2.0) and h2 > 0, "%.5f" % rate(p, dk_in))

# ------------------------------------------------------------------ 1.6 報酬 / 気絶 / ポーズ
func t_reward_stun_pause() -> void:
	var p: RefCounted = mk()
	var r: Dictionary = Common2.reward_event(5, "glass_deer", 120, "near", Vector2(10, 10))
	p.advance(1.0)
	ck("reward_instant_event_no_pickup", r.type == "reward" and bool(r.instant) and int(r.amount) == 120 and p.crops.pickups.is_empty(), "")
	# 気絶(主人公)
	ck("stun_hero_initially_false", not p.common.hero_stunned(), "")
	var out: Array = p.relay_events([Common2.hero_stun_event(1.5, 7)])
	ck("stun_event_relayed_through_window", out.size() == 1 and out[0].type == "hero_stun" and p.common.hero_stunned(), "")
	p.advance(1.4)
	ck("stun_hero_still_at_1_4s", p.common.hero_stunned(), "")
	p.advance(0.2)
	ck("stun_hero_ends_after_1_5s", not p.common.hero_stunned(), "")
	# おたすけ植物の仕事停止(気絶と臭気)
	p.relay_events([Common2.helper_stop_event(3, 2.0, "stun"), Common2.helper_stop_event(4, 1.0, "odor")])
	ck("stop_helper_flags", p.common.helper_stopped(3) and p.common.helper_stopped(4) and not p.common.helper_stopped(5), "")
	p.advance(1.5)
	ck("stop_helper_expire_independently", p.common.helper_stopped(3) and not p.common.helper_stopped(4), "")
	# ポーズ中は進まない
	var s1: String = JSON.stringify(p.to_dict())
	var none: Array = p.advance(0.0)
	ck("pause_no_advance_no_change", none.is_empty() and JSON.stringify(p.to_dict()) == s1, "")
	# 保存復元
	var d: Dictionary = JSON.parse_string(JSON.stringify(p.to_dict()))
	var q: RefCounted = mk(5)
	ck("stun_save_restore", q.from_dict(d) and q.common.helper_stopped(3) and not q.common.hero_stunned(), str(q.last_error))
	q.advance(0.6)
	ck("stun_restored_expires", not q.common.helper_stopped(3), "")
