extends SceneTree
## 敵 E12〜E21 と保存の原子性の自己検証(入口スクリプト)。1条件1回、ゲーム内時間は advance で早送り。
## 実行(隔離プロジェクトのみ): Godot --headless --path C:/godot/greenvader_content_sandbox --script res://tests/content_pack/self/enemies_b.gd
const Lab: GDScript = preload("res://scripts/content_pack/lab/lab_host.gd")
const Pack: GDScript = preload("res://scripts/content_pack/content_pack.gd")
const OUT_DIR: String = "res://evidence/content_pack/self"

var checks: Array = []

func ck(name: String, ok: bool, detail: String = "") -> void:
	checks.append({"name": name, "status": "PASS" if ok else "FAIL", "detail": detail})

func near(a: float, b: float, eps: float = 0.01) -> bool:
	return absf(a - b) <= eps

func mk(seed: int = 1) -> RefCounted:
	return Pack.new(Lab.new(), seed)

func sp(p: RefCounted, kind: String, x: float, y: float, origin: String = "initial", opts: Dictionary = {}) -> int:
	return p.enemies.spawn(kind, Vector2(x, y), origin, opts)

func E(p: RefCounted, id: int) -> Dictionary:
	return p.enemies.get_enemy(id)

func R(p: RefCounted, id: int) -> Dictionary:
	return p.enemies.ref(id)

func hero(p: RefCounted, x: float, y: float, aim: Vector2 = Vector2.RIGHT) -> void:
	p.host.hero_state = {"pos": Vector2(x, y), "hp": 100.0, "max_hp": 100.0, "aim": aim}

func helper(p: RefCounted, id: int, x: float, y: float) -> void:
	p.host.helper_list.append({"id": id, "pos": Vector2(x, y), "hp": 50.0, "max_hp": 50.0})

func crop(p: RefCounted, kind: String, x: int, y: int, mature: bool = true) -> int:
	var r: Dictionary = p.crops.spawn_crop(kind, Vector2i(x, y), 0, {"mature": mature, "watered": true, "skip_check": true})
	return int(r.id) if bool(r.ok) else -1

func evs(events: Array, type: String, kind: String = "") -> Array:
	var out: Array = []
	for e: Dictionary in events:
		if e.type == type and (kind == "" or str(e.get("kind", "")) == kind):
			out.append(e)
	return out

func timed(p: RefCounted, secs: float, dt: float = 0.1) -> Array:
	var out: Array = []
	var n: int = int(round(secs / dt))
	for i: int in range(n):
		var ev: Array[Dictionary] = p.advance(dt)
		for e: Dictionary in ev:
			out.append({"t": p.enemies.time, "e": e})
	return out

func only(tl: Array, type: String, kind: String = "") -> Array:
	var out: Array = []
	for x: Dictionary in tl:
		var e: Dictionary = x.e
		if e.type == type and (kind == "" or str(e.get("kind", "")) == kind):
			out.append(x)
	return out

func roundtrip(d: Dictionary) -> Dictionary:
	var parsed: Variant = JSON.parse_string(JSON.stringify(d))
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}

func dump(p: RefCounted) -> String:
	return JSON.stringify(p.to_dict(), "", true)

func snap(p: RefCounted, prec: float = 0.001) -> String:
	var rows: Array = []
	for e: Dictionary in p.enemies.enemies:
		rows.append("%d:%s:%s:%.3f:%.2f,%.2f" % [e.id, e.kind, e.state, e.hp, snappedf(e.pos.x, prec), snappedf(e.pos.y, prec)])
	rows.sort()
	var hp_sum: float = 0.0
	for c: Dictionary in p.crops.crops:
		hp_sum += float(c.hp)
	return "|".join(rows) + "#g%d#p%d#pk%d#hp%.2f" % [p.enemies.gas.size(), p.enemies.projectiles.size(), p.crops.pickups.size(), hp_sum]

func ids_of(p: RefCounted, kind: String) -> Array:
	var out: Array = []
	for e: Dictionary in p.enemies.enemies:
		if e.alive and e.kind == kind:
			out.append(int(e.id))
	return out

func _initialize() -> void:
	t_e12()
	t_e13()
	t_e14()
	t_e15()
	t_e16()
	t_e17()
	t_e18()
	t_e19()
	t_e20()
	t_e21()
	t_save_all()
	t_atomic()
	var fails: int = 0
	var lines: Array = []
	for c: Dictionary in checks:
		var line: String = "%s %s %s" % [c.status, c.name, c.detail]
		print(line)
		lines.append(line)
		if c.status != "PASS":
			fails += 1
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var f: FileAccess = FileAccess.open(OUT_DIR + "/enemies_b.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"suite": "enemies_b", "total": checks.size(), "failed": fails, "checks": checks}, "\t"))
	f.close()
	var lf: FileAccess = FileAccess.open(OUT_DIR + "/enemies_b.log", FileAccess.WRITE)
	lf.store_string("\n".join(lines) + "\nenemies_b total=%d failed=%d\n" % [checks.size(), fails])
	lf.close()
	print("enemies_b total=%d failed=%d" % [checks.size(), fails])
	quit(1 if fails > 0 else 0)

# ------------------------------------------------------------------ E12 ホオブクロウサギ
func t_e12() -> void:
	# かじっている間、生産量はほお袋へ入る(種は生まれない)。1ダメージ/秒
	var p: RefCounted = mk()
	var cid: int = crop(p, "clover", 30, 6)
	var rid: int = sp(p, "pouch_rabbit", 112, 26)
	var tl: Array = timed(p, 12.0)
	var stolen: Array = only(tl, "seeds_stolen")
	var sum: float = 0.0
	for x: Dictionary in stolen:
		sum += float(x.e.amount)
	var first_t: float = float(stolen[0].t) if stolen.size() > 0 else 1e9
	var seeds_after: int = 0
	for x: Dictionary in only(tl, "seeds"):
		if float(x.t) > first_t:
			seeds_after += 1
	var cd: Array = only(tl, "crop_damaged")
	var all_one: bool = true
	for x: Dictionary in cd:
		if not near(float(x.e.amount), 1.0):
			all_one = false
	var cheek: float = float(E(p, rid).cheek)
	ck("e12_gnaw_stolen_seeds_go_to_cheek_not_player", stolen.size() > 0 and sum > 0.0 and near(cheek, minf(20.0, sum), 0.001) and seeds_after == 0 and bool(p.crops.get_crop(cid).gnawed),
		"sum=%.4f cheek=%.4f seeds_after=%d" % [sum, cheek, seeds_after])
	ck("e12_chew_1_damage_per_second", cd.size() >= 9 and cd.size() <= 11 and all_one, "n=%d" % cd.size())
	# 満杯(上限20)になると かじるのをやめて家へ戻り、ほお袋を抱えたまま休む
	var q: RefCounted = mk()
	var cq: int = crop(q, "clover", 30, 6)
	var rq: int = sp(q, "pouch_rabbit", 112, 26, "initial", {"home": Vector2(70, 26)})
	R(q, rq).cheek = 19.999
	timed(q, 5.0)
	var st: Dictionary = E(q, rq)
	var more: Array = timed(q, 10.0)
	ck("e12_full_cheek_20_goes_home_and_rests", near(float(st.cheek), 20.0, 0.0001) and st.state == "rest" and Vector2(st.pos).distance_to(Vector2(70, 26)) <= 3.1 \
		and not bool(q.crops.get_crop(cq).gnawed) and only(more, "seeds_stolen").is_empty() and only(more, "crop_damaged").is_empty(),
		"cheek=%.3f st=%s pos=%s" % [float(st.cheek), str(st.state), str(st.pos)])
	# 主人公が5m以内: 3.0m/sで逃げる(攻撃しない)。4秒走ると2秒疲れて止まる
	var f: RefCounted = mk()
	hero(f, 70, 100)
	var fid: int = sp(f, "pouch_rabbit", 100, 100)
	var ftl: Array = timed(f, 1.2)
	var moved: float = float(E(f, fid).pos.x) - 100.0
	var st1: String = str(E(f, fid).state)
	var tl2: Array = timed(f, 3.0)
	var at_tired_start: Vector2 = E(f, fid).pos
	var st2: String = str(E(f, fid).state)
	var tl3: Array = timed(f, 1.8)
	var st3: String = str(E(f, fid).state)
	var held: bool = Vector2(E(f, fid).pos).distance_to(at_tired_start) < 0.01
	timed(f, 1.0)
	var st4: String = str(E(f, fid).state)
	ck("e12_flees_at_3mps_and_never_attacks_hero", near(moved, 33.0, 1.0) and st1 == "flee" and only(ftl + tl2 + tl3, "hero_damage").is_empty(), "moved=%.2f %s" % [moved, st1])
	ck("e12_runs_4s_then_tired_2s_then_rests", st2 == "tired" and st3 == "tired" and held and st4 == "rest", "%s %s %s held=%s" % [st2, st3, st4, str(held)])
	# 縄張り(家から15m)の外へは逃げない
	var g: RefCounted = mk()
	hero(g, 170, 100)
	var gid: int = sp(g, "pouch_rabbit", 190, 100, "initial", {"home": Vector2(60, 100)})
	var maxd: float = 0.0
	for i: int in range(120):
		g.advance(0.1)
		maxd = maxf(maxd, Vector2(E(g, gid).pos).distance_to(Vector2(60, 100)))
	ck("e12_flee_stays_inside_territory_15m", maxd <= 150.01 and maxd >= 147.0, "maxd=%.2f" % maxd)
	# 撃破: 報酬4、ほお袋の種を地面へ(拾い物)。主人公が近づくと回収
	var k: RefCounted = mk()
	var kid: int = sp(k, "pouch_rabbit", 100, 100)
	R(k, kid).cheek = 7.6
	var kev: Array = k.hit_enemy(kid, 12.0, "shot", null)
	var pk: Array = k.crops.pickups
	var rw: Array = evs(kev, "reward")
	ck("e12_defeat_drops_cheek_seeds_pickup_and_reward_4", pk.size() == 1 and int(pk[0].amount) == 7 and Vector2(pk[0].pos).distance_to(Vector2(100, 100)) < 0.01 and rw.size() == 1 and int(rw[0].amount) == 4, str(pk))
	hero(k, 100, 104)
	var ctl: Array = timed(k, 0.2)
	var pc: Array = only(ctl, "pickup_collected")
	ck("e12_pickup_collected_by_hero_nearby", pc.size() == 1 and int(pc[0].e.amount) == 7 and k.crops.pickups.is_empty(), "")

# ------------------------------------------------------------------ E13 ベロガエル
func t_e13() -> void:
	var p: RefCounted = mk()
	hero(p, 150, 100)
	var id: int = sp(p, "tongue_frog", 100, 100)
	var tl: Array = timed(p, 5.2)
	var dmg: Array = only(tl, "hero_damage")
	var pull: Array = only(tl, "hero_pull")
	var aim_fx: Array = []
	for x: Dictionary in only(tl, "fx"):
		if x.e.kind == "tongue_line":
			aim_fx.append(x)
	var ok_first: bool = dmg.size() == 2 and near(float(dmg[0].t), 0.9, 0.11) and near(float(dmg[0].e.amount), 6.0) and pull.size() == 2 \
		and Vector2(pull[0].e.to).distance_to(Vector2(120, 100)) < 0.01
	ck("e13_aim_0_8s_then_6_damage_and_pull_3m", ok_first and aim_fx.size() >= 1 and near(float(aim_fx[0].e.seconds), 0.8), "dmg=%d t0=%s" % [dmg.size(), str(dmg[0].t) if dmg.size() > 0 else "-"])
	ck("e13_no_tongue_for_3s_after_firing", dmg.size() == 2 and float(dmg[1].t) - float(dmg[0].t) >= 3.7, "gap=%.2f" % (float(dmg[1].t) - float(dmg[0].t)) if dmg.size() == 2 else "n=%d" % dmg.size())
	ck("e13_tongue_line_is_7m", Vector2(aim_fx[0].e.to).distance_to(Vector2(170, 100)) < 0.01, str(aim_fx[0].e.to) if aim_fx.size() > 0 else "")
	# 予兆中に線から外れれば当たらない(線は予兆開始時に固定)
	var q: RefCounted = mk()
	hero(q, 150, 100)
	var qid: int = sp(q, "tongue_frog", 100, 100)
	timed(q, 0.2)
	hero(q, 150, 130)
	var qt: Array = timed(q, 1.2)
	ck("e13_sidestep_during_aim_avoids_tongue", E(q, qid).state != "aim" and only(qt, "hero_damage").is_empty() and only(qt, "hero_pull").is_empty(), "")
	# 建物は舌を遮る(見えない相手には予兆も出さない)
	var b: RefCounted = mk()
	hero(b, 150, 68)
	var bid: int = sp(b, "tongue_frog", 90, 68)
	var bt: Array = timed(b, 3.0)
	ck("e13_building_blocks_tongue_and_trigger", only(bt, "hero_damage").is_empty() and E(b, bid).state == "idle", str(E(b, bid).state))
	# 舌がおたすけ植物に先に当たると4ダメージ(引き寄せなし)
	var h: RefCounted = mk()
	hero(h, 160, 100)
	helper(h, 7, 130, 100)
	sp(h, "tongue_frog", 100, 100)
	var ht: Array = timed(h, 1.1)
	var hd: Array = only(ht, "helper_damage")
	ck("e13_tongue_hits_helper_first_4_damage_no_pull", hd.size() == 1 and int(hd[0].e.helper_id) == 7 and near(float(hd[0].e.amount), 4.0) and only(ht, "hero_pull").is_empty() and only(ht, "hero_damage").is_empty(), "n=%d" % hd.size())

# ------------------------------------------------------------------ E14 ミツバチ
func _bee_ids(p: RefCounted) -> Dictionary:
	var hv: Array = ids_of(p, "honeybee_hive")
	var sw: Array = ids_of(p, "honeybee_swarm")
	return {"hive": hv[0] if hv.size() > 0 else -1, "swarm": sw[0] if sw.size() > 0 else -1}

func t_e14() -> void:
	# 中立: 安定判定に数えない。壊しても報酬なし、受粉が消える
	var p: RefCounted = mk()
	var cid: int = crop(p, "clover", 24, 30)
	var hv: int = sp(p, "honeybee_hive", 82, 122)
	var bee: Dictionary = _bee_ids(p)
	var stab0: int = p.enemies.living_count_for_stability()
	sp(p, "shadow_brian", 200, 40)
	var stab1: int = p.enemies.living_count_for_stability()
	var bonus_before: float = float(p.crops.production_info(cid).bee_bonus)
	var occ: Dictionary = p.crops.check_placement("clover", Vector2i(20, 30))
	var struct_kind: String = p.enemies.structure_at(Vector2i(20, 30))
	var hev: Array = p.hit_enemy(hv, 40.0, "shot", Vector2(200, 122))
	var bonus_after: float = float(p.crops.production_info(cid).bee_bonus)
	ck("e14_neutral_not_counted_for_stability_but_alive", stab0 == 0 and stab1 == 1 and int(bee.swarm) > 0 and not p.enemies.counts_for_stability(int(bee.swarm)) and not p.enemies.counts_for_stability(hv), "%d %d" % [stab0, stab1])
	ck("e14_hive_pollinates_8_cells_and_blocks_planting", near(bonus_before, 0.10, 0.0001) and not bool(occ.ok) and occ.reason == "occupied" and occ.by == "honeybee_hive" and struct_kind == "honeybee_hive", "%.3f %s" % [bonus_before, str(occ)])
	ck("e14_destroying_hive_gives_nothing_and_ends_pollination", evs(hev, "reward").is_empty() and evs(hev, "enemy_defeated").size() == 1 and near(bonus_after, 0.0, 0.0001) and not p.enemies.is_alive(int(bee.swarm)) and p.enemies.pollinator_list().is_empty(), "after=%.3f" % bonus_after)
	timed(p, 40.0)
	ck("e14_destroyed_hive_never_returns", ids_of(p, "honeybee_hive").is_empty() and ids_of(p, "honeybee_swarm").is_empty(), "")
	# 怒り: 攻撃した相手だけを巣から10mまで追って刺す(3ダメージ/1秒)。草・植物は攻撃しない
	var a: RefCounted = mk()
	crop(a, "clover", 24, 30)
	hero(a, 142, 122)
	helper(a, 3, 90, 122)
	sp(a, "honeybee_hive", 82, 122)
	var ba: Dictionary = _bee_ids(a)
	a.hit_enemy(int(ba.swarm), 5.0, "shot", Vector2(142, 122))
	var angry_now: bool = R(a, int(ba.hive)).state == "angry"
	var at: Array = timed(a, 5.0)
	var st: Array = only(at, "hero_damage")
	var sting_ok: bool = st.size() >= 3 and st.size() <= 4 and float(st[0].t) >= 1.5 and float(st[0].t) <= 2.2
	for x: Dictionary in st:
		if not near(float(x.e.amount), 3.0) or x.e.kind != "honeybee_swarm":
			sting_ok = false
	for i: int in range(1, st.size()):
		if absf(float(st[i].t) - float(st[i - 1].t) - 1.0) > 0.11:
			sting_ok = false
	ck("e14_angry_swarm_stings_3_per_second_hero_only", angry_now and sting_ok and only(at, "helper_damage").is_empty() and only(at, "crop_damaged").is_empty(), "stings=%d" % st.size())
	timed(a, 16.5)
	var calm_ok: bool = R(a, int(ba.hive)).state == "calm" and R(a, int(ba.swarm)).state == "orbit"
	var late: Array = timed(a, 3.0)
	ck("e14_anger_ends_after_20s_and_swarm_returns", calm_ok and only(late, "hero_damage").is_empty() and Vector2(R(a, int(ba.swarm)).pos).distance_to(Vector2(82, 122)) <= 13.0, "")
	# 追跡は巣から10mまで
	var c: RefCounted = mk()
	hero(c, 222, 122)
	sp(c, "honeybee_hive", 82, 122)
	var bc: Dictionary = _bee_ids(c)
	c.hit_enemy(int(bc.swarm), 1.0, "shot", Vector2(222, 122))
	var maxd: float = 0.0
	var ctl: Array = []
	for i: int in range(80):
		ctl.append_array(timed(c, 0.1))
		maxd = maxf(maxd, Vector2(R(c, int(bc.swarm)).pos).distance_to(Vector2(82, 122)))
	ck("e14_chase_limited_to_10m_from_hive", maxd <= 100.01 and maxd >= 95.0 and only(ctl, "hero_damage").is_empty(), "maxd=%.2f" % maxd)
	# 巣の1.5m以内に3秒以上とどまると怒る(途中で離れると数え直し)
	var d: RefCounted = mk()
	hero(d, 92, 122)
	sp(d, "honeybee_hive", 82, 122)
	var bd: Dictionary = _bee_ids(d)
	timed(d, 2.0)
	hero(d, 200, 122)
	timed(d, 0.5)
	hero(d, 92, 122)
	timed(d, 2.0)
	var calm_mid: bool = R(d, int(bd.hive)).state == "calm"
	timed(d, 1.2)
	ck("e14_staying_within_1_5m_for_3s_angers_hive", calm_mid and R(d, int(bd.hive)).state == "angry" and R(d, int(bd.hive)).ttype == "hero", "")
	# 爆風は怒らせる。水(ダメージ0)は怒らせない
	var e1: RefCounted = mk()
	sp(e1, "honeybee_hive", 82, 122)
	var be: Dictionary = _bee_ids(e1)
	e1.splash(Vector2(92, 122), 20.0, 0.0, "water")
	var calm_w: bool = R(e1, int(be.hive)).state == "calm"
	e1.splash(Vector2(92, 122), 20.0, 5.0, "bazooka")
	ck("e14_blast_angers_water_does_not", calm_w and R(e1, int(be.hive)).state == "angry", "")
	# 群れを倒すと30秒後に巣から新しい群れ(生産扱い・報酬0)
	var f: RefCounted = mk()
	sp(f, "honeybee_hive", 82, 122)
	var bf: Dictionary = _bee_ids(f)
	var kev: Array = f.hit_enemy(int(bf.swarm), 15.0, "shot", Vector2(200, 122))
	timed(f, 29.8)
	var none_yet: bool = ids_of(f, "honeybee_swarm").is_empty()
	timed(f, 0.4)
	var ns: Array = ids_of(f, "honeybee_swarm")
	var new_origin: String = str(R(f, int(ns[0])).origin) if ns.size() == 1 else ""
	var nev: Array = f.hit_enemy(int(ns[0]), 15.0, "shot", null) if ns.size() == 1 else []
	ck("e14_swarm_respawns_after_30s_as_produced_no_reward", evs(kev, "reward").is_empty() and none_yet and ns.size() == 1 and new_origin == "produced" and evs(nev, "reward").is_empty(), "ns=%d" % ns.size())

# ------------------------------------------------------------------ E15 アルマジロ
func t_e15() -> void:
	# 時間切れ(3秒)で止まる。主人公に10・株に8(同じ相手には1回)
	var p: RefCounted = mk()
	hero(p, 98, 100)
	crop(p, "clover", 10, 25)
	var id: int = sp(p, "armadillo", 20, 100)
	var tl: Array = timed(p, 3.6)
	var st_roll: String = str(E(p, id).state)
	timed(p, 0.4)
	var hd: Array = only(tl, "hero_damage")
	var cd: Array = only(tl, "crop_damaged")
	ck("e15_roll_hits_hero_10_and_crop_8_once_each", hd.size() == 1 and near(float(hd[0].e.amount), 10.0) and cd.size() == 1 and near(float(cd[0].e.amount), 8.0), "hero=%d crop=%d" % [hd.size(), cd.size()])
	ck("e15_roll_stops_after_3s_then_dizzy", st_roll == "roll" and str(E(p, id).state) == "dizzy" and int(E(p, id).bounces) == 0, "%s %s" % [st_roll, str(E(p, id).state)])
	# 壁で反射し最大4回。5回目の接触で止まり目を回す(2.5秒)。転がり中×0.2、目を回している間×1.5
	var q: RefCounted = mk()
	q.host.set_stable_rect(Rect2i(14, 0, 1, 36))
	q.host.set_stable_rect(Rect2i(22, 0, 1, 36))
	hero(q, 140, 100)
	var qid: int = sp(q, "armadillo", 72, 100)
	timed(q, 1.4)
	var roll_state: String = str(E(q, qid).state)
	q.hit_enemy(qid, 10.0, "shot", null)
	var hp_roll: float = float(E(q, qid).hp)
	var dizzy_start: float = -1.0
	var dizzy_end: float = -1.0
	var max_b: int = 0
	var minx: float = 1e9
	var maxx: float = -1e9
	var pre_hits: int = 0
	for i: int in range(70):
		var ev: Array[Dictionary] = q.advance(0.1)
		pre_hits += evs(ev, "hero_damage").size()
		var en: Dictionary = E(q, qid)
		max_b = maxi(max_b, int(en.bounces))
		minx = minf(minx, float(en.pos.x))
		maxx = maxf(maxx, float(en.pos.x))
		if en.state == "dizzy" and dizzy_start < 0.0:
			dizzy_start = q.enemies.time
		if en.state != "dizzy" and dizzy_start >= 0.0 and dizzy_end < 0.0:
			dizzy_end = q.enemies.time
	ck("e15_bounces_off_walls_max_4_times_then_stops", roll_state == "roll" and max_b == 4 and dizzy_start > 0.0 and minx >= 59.9 and maxx <= 88.0 and pre_hits == 0, "b=%d x=[%.1f,%.1f] dz=%.1f" % [max_b, minx, maxx, dizzy_start])
	ck("e15_dizzy_2_5s_and_damage_multipliers", near(hp_roll, 28.0, 0.001) and near(dizzy_end - dizzy_start, 2.5, 0.11), "hp_roll=%.2f dizzy=%.2f" % [hp_roll, dizzy_end - dizzy_start])
	var r: RefCounted = mk()
	r.host.set_stable_rect(Rect2i(14, 0, 1, 36))
	r.host.set_stable_rect(Rect2i(22, 0, 1, 36))
	hero(r, 140, 100)
	var rid: int = sp(r, "armadillo", 72, 100)
	timed(r, 3.0)
	var dz: String = str(E(r, rid).state)
	r.hit_enemy(rid, 10.0, "shot", null)
	ck("e15_dizzy_takes_x1_5_damage", dz == "dizzy" and near(float(E(r, rid).hp), 15.0, 0.001), "%s hp=%.2f" % [dz, float(E(r, rid).hp)])

# ------------------------------------------------------------------ E16 ヘドロゴイ
func t_e16() -> void:
	var p: RefCounted = mk()
	hero(p, 66, 30)
	var cid: int = crop(p, "clover", 16, 7)
	var id: int = sp(p, "sludge_carp", 30, 30)
	var surf_start: Array = []
	var in_water: bool = true
	var prev: String = ""
	var tl: Array = []
	for i: int in range(200):
		tl.append_array(timed(p, 0.1))
		var en: Dictionary = E(p, id)
		if str(en.state) == "surface" and prev != "surface":
			surf_start.append(p.enemies.time)
		prev = str(en.state)
		if not p.host.is_water(Vector2i(floori(en.pos.x / 4.0), floori(en.pos.y / 4.0))):
			in_water = false
	var gaps_ok: bool = surf_start.size() >= 2
	for i: int in range(1, surf_start.size()):
		if float(surf_start[i]) - float(surf_start[i - 1]) > 8.0:
			gaps_ok = false
	ck("e16_surfaces_every_7_3s_at_most_8s_apart_and_stays_in_water", gaps_ok and near(float(surf_start[0]), 4.8, 0.11) and in_water, "starts=%s water=%s" % [str(surf_start), str(in_water)])
	var md: Array = only(tl, "hero_damage")
	var slow: Array = only(tl, "hero_slow")
	ck("e16_mud_lands_0_8s_after_spit_6_damage_and_50pct_slow_2s", md.size() == 2 and near(float(md[0].t), 5.6, 0.11) and near(float(md[0].e.amount), 6.0) and slow.size() == 2 and near(float(slow[0].e.factor), 0.5) and near(float(slow[0].e.seconds), 2.0), "n=%d t=%s" % [md.size(), str(md[0].t) if md.size() > 0 else "-"])
	ck("e16_mud_does_not_affect_plants_or_grass", only(tl, "crop_damaged").is_empty() and only(tl, "ground_stage").is_empty() and near(float(p.crops.get_crop(cid).hp), 30.0), "")
	var marks: Array = []
	for x: Dictionary in only(tl, "fx"):
		if x.e.kind == "mud_mark":
			marks.append(x)
	ck("e16_landing_marked_from_spit_time", marks.size() >= 2 and near(float(marks[0].t), 4.8, 0.11) and near(float(marks[0].e.land_at) - float(marks[0].t), 0.8, 0.11) and Vector2(marks[0].e.pos).distance_to(Vector2(66, 30)) < 0.01, "")
	# 潜行中・予兆中は当たらず、浮上中だけ当たる
	var q: RefCounted = mk()
	var qid: int = sp(q, "sludge_carp", 30, 30)
	timed(q, 3.0)
	var h1: Array = q.hit_enemy(qid, 5.0, "shot", null)
	timed(q, 1.4)
	var st_rise: String = str(E(q, qid).state)
	var h2: Array = q.hit_enemy(qid, 5.0, "shot", null)
	timed(q, 0.6)
	var st_surf: String = str(E(q, qid).state)
	var h3: Array = q.hit_enemy(qid, 5.0, "shot", null)
	ck("e16_dive_not_hittable_surface_hittable", h1.is_empty() and h2.is_empty() and st_rise == "rise" and st_surf == "surface" and evs(h3, "enemy_damaged").size() == 1 and near(float(E(q, qid).hp), 20.0) and q.enemies.counts_for_stability(qid), "%s %s" % [st_rise, st_surf])
	# 浮上中に着弾表示から外れれば当たらない
	var d: RefCounted = mk()
	hero(d, 66, 30)
	sp(d, "sludge_carp", 30, 30)
	timed(d, 5.0)
	hero(d, 120, 30)
	var dt2: Array = timed(d, 1.0)
	ck("e16_leaving_marked_spot_avoids_mud", only(dt2, "hero_damage").is_empty() and only(dt2, "hero_slow").is_empty(), "")

# ------------------------------------------------------------------ E17 アリ塚・ハキリアリ
func _waste_around(p: RefCounted) -> void:
	for y: int in range(Lab.H):
		for x: int in range(Lab.W):
			if p.host.terrain[y * Lab.W + x] == Lab.GREEN:
				p.host.set_terrain(Vector2i(x, y), Lab.WASTE)

func _produced(p: RefCounted) -> int:
	var n: int = 0
	for e: Dictionary in p.enemies.enemies:
		if e.alive and e.kind == "leafcutter_ant" and e.origin == "produced":
			n += 1
	return n

func t_e17() -> void:
	# 活動中は8秒ごとに1匹、同時6匹まで。生産アリの報酬は0、初期配置アリは2
	var p: RefCounted = mk()
	var hill: int = sp(p, "ant_hill", 100, 60)
	timed(p, 8.2)
	var n1: int = _produced(p)
	timed(p, 8.0)
	var n2: int = _produced(p)
	timed(p, 33.0)
	var n6: int = _produced(p)
	timed(p, 12.0)
	var n6b: int = _produced(p)
	var prod_id: int = int(ids_of(p, "leafcutter_ant")[0])
	var pev: Array = p.hit_enemy(prod_id, 3.0, "shot", null)
	var rem: int = _produced(p)
	timed(p, 8.0)
	var refill: int = _produced(p)
	ck("e17_hill_produces_every_8s_up_to_6_at_once", n1 == 1 and n2 == 2 and n6 == 6 and n6b == 6 and rem == 5 and refill == 6, "%d %d %d %d %d %d" % [n1, n2, n6, n6b, rem, refill])
	var init_ant: int = sp(p, "leafcutter_ant", 100, 72, "initial", {"hill_id": hill, "home": Vector2(100, 60)})
	var iev: Array = p.hit_enemy(init_ant, 3.0, "shot", null)
	ck("e17_produced_ant_reward_0_initial_ant_reward_2", evs(pev, "reward").is_empty() and evs(pev, "enemy_defeated").size() == 1 and evs(iev, "reward").size() == 1 and int(evs(iev, "reward")[0].amount) == 2, "")
	# 活動条件を満たさない間は生産しない(主人公なし・周辺に緑地なし)
	var q: RefCounted = mk()
	_waste_around(q)
	sp(q, "ant_hill", 100, 60)
	timed(q, 30.0)
	var inactive: int = _produced(q)
	hero(q, 120, 60)
	timed(q, 12.0)
	ck("e17_hill_idle_without_activity_condition_then_active_when_hero_near", inactive == 0 and _produced(q) >= 1, "inactive=%d after=%d" % [inactive, _produced(q)])
	# 固定巣: 占有2x2(歩けない・植付け不可)。破壊で小規模の巣の報酬(基礎値)を載せる。生産された塚は0
	var s: RefCounted = mk()
	var hs: int = sp(s, "ant_hill", 100, 60)
	var occ: Dictionary = s.crops.check_placement("clover", Vector2i(25, 15))
	var rects: Array = s.enemies.structure_rects()
	var rev: Array = s.hit_enemy(hs, 60.0, "shot", null)
	var rw: Array = evs(rev, "reward")
	var s2: RefCounted = mk()
	var hs2: int = sp(s2, "ant_hill", 100, 60, "produced")
	var rev2: Array = s2.hit_enemy(hs2, 60.0, "shot", null)
	ck("e17_hill_is_fixed_2x2_nest_with_small_nest_reward_base", not bool(occ.ok) and occ.by == "ant_hill" and rects.size() == 1 and rects[0].rect == Rect2i(24, 14, 2, 2) \
		and rw.size() == 1 and rw[0].nest == "small" and int(rw[0].amount) == 30 and evs(rev2, "reward").is_empty(), str(rw))
	# 株を狙う: 葉を切り取り(2ダメージ/2秒)、持ち帰る。最後の1匹でも同じ
	var a: RefCounted = mk()
	var cid: int = crop(a, "clover", 20, 12)
	var ha: int = sp(a, "ant_hill", 100, 60)
	var ant: int = sp(a, "leafcutter_ant", 96, 70, "initial", {"hill_id": ha, "home": Vector2(100, 60)})
	var atl: Array = []
	var carry_seen: bool = false
	for i: int in range(120):
		atl.append_array(timed(a, 0.1))
		if E(a, ant).state == "carry":
			carry_seen = true
	var acd: Array = only(atl, "crop_damaged")
	ck("e17_ant_cuts_2_damage_per_2s_then_carries_leaf_home", acd.size() >= 1 and near(float(acd[0].e.amount), 2.0) and carry_seen, "n=%d first=%s" % [acd.size(), str(acd[0].t) if acd.size() > 0 else "-"])
	# 行列の途中の1匹が倒されると、その後ろの仲間は3秒うろうろする
	var b: RefCounted = mk()
	var cb: int = crop(b, "clover", 20, 12)
	var hb: int = sp(b, "ant_hill", 100, 60)
	var cc: Vector2 = b.enemies.crop_center(b.crops.get_crop(cb))
	var ids: Array = []
	for f: float in [0.35, 0.6, 0.85]:
		var pos: Vector2 = Vector2(100, 60).lerp(cc, f)
		var aid: int = sp(b, "leafcutter_ant", pos.x, pos.y, "initial", {"hill_id": hb, "home": Vector2(100, 60)})
		R(b, aid).state = "walk"
		R(b, aid).target_crop = cb
		ids.append(aid)
	b.hit_enemy(int(ids[1]), 3.0, "shot", null)
	var st_rear: String = str(E(b, int(ids[0])).state)
	var st_front: String = str(E(b, int(ids[2])).state)
	timed(b, 2.8)
	var rear_mid: String = str(E(b, int(ids[0])).state)
	timed(b, 0.4)
	var rear_after: String = str(E(b, int(ids[0])).state)
	ck("e17_killing_mid_column_ant_makes_followers_wander_3s", st_rear == "lost" and st_front == "walk" and rear_mid == "lost" and rear_after != "lost", "%s %s %s %s" % [st_rear, st_front, rear_mid, rear_after])

# ------------------------------------------------------------------ E18 ミミックキャベツ
func t_e18() -> void:
	var p: RefCounted = mk()
	var id: int = sp(p, "mimic_cabbage", 150, 110)
	var hid_occ: Dictionary = p.crops.check_placement("clover", Vector2i(37, 27))
	var side: Dictionary = p.crops.check_placement("clover", Vector2i(38, 27))
	var ht: Array = p.enemies.hittable_targets()
	ck("e18_hidden_not_detectable_but_counts_and_blocks_planting", p.enemies.detectable_enemies().is_empty() and p.enemies.living_count_for_stability() == 1 and ht.size() == 1 and bool(ht[0].hidden) \
		and not bool(hid_occ.ok) and hid_occ.reason == "occupied" and hid_occ.by == "mimic_cabbage" and bool(side.ok), str(hid_occ))
	p.hit_enemy(id, 5.0, "shot", null)
	var after_hit: Array = p.enemies.detectable_enemies()
	var occ2: Dictionary = p.crops.check_placement("clover", Vector2i(37, 27))
	ck("e18_hit_reveals_then_detectable_and_cell_free", after_hit.size() == 1 and str(E(p, id).state) == "revealed" and bool(occ2.ok), str(E(p, id).state))
	var q: RefCounted = mk()
	sp(q, "mimic_cabbage", 150, 110)
	sp(q, "mimic_cabbage", 200, 110)
	q.enemies.notify_seed(Vector2(155, 110))
	var seed_n: int = q.enemies.detectable_enemies().size()
	q.splash(Vector2(200, 110), 15.0, 0.0, "water")
	ck("e18_seed_within_1m_and_water_reveal", seed_n == 1 and q.enemies.detectable_enemies().size() == 2, "")
	# 2m以内: 0.3秒で噛みつき12 → 6秒追う(1.5秒ごとに噛む) → 戻って3秒止まると再び擬態
	var r: RefCounted = mk()
	hero(r, 150, 130)
	var rid: int = sp(r, "mimic_cabbage", 150, 110)
	var rtl: Array = timed(r, 6.6)
	var bites: Array = only(rtl, "hero_damage")
	var revealed_in_strike: bool = r.enemies.detectable_enemies().size() == 1
	hero(r, 250, 140)
	timed(r, 8.0)
	ck("e18_strike_0_3s_bite_12_then_chase_6s", bites.size() == 4 and near(float(bites[0].t), 0.4, 0.11) and near(float(bites[0].e.amount), 12.0) and revealed_in_strike, "bites=%d t0=%s" % [bites.size(), str(bites[0].t) if bites.size() > 0 else "-"])
	ck("e18_returns_home_waits_3s_and_hides_again", str(E(r, rid).state) == "hidden" and r.enemies.detectable_enemies().is_empty() and Vector2(E(r, rid).pos).distance_to(Vector2(150, 110)) <= 2.1, "%s %s" % [str(E(r, rid).state), str(E(r, rid).pos)])
	# おたすけ植物も狙う
	var s: RefCounted = mk()
	helper(s, 5, 150, 128)
	sp(s, "mimic_cabbage", 150, 110)
	var stl: Array = timed(s, 0.6)
	ck("e18_targets_helper_within_2m", only(stl, "helper_damage").size() == 1 and int(only(stl, "helper_damage")[0].e.helper_id) == 5 and near(float(only(stl, "helper_damage")[0].e.amount), 12.0), "")

# ------------------------------------------------------------------ E19 トンビ
func t_e19() -> void:
	var p: RefCounted = mk()
	hero(p, 150, 100)
	var id: int = sp(p, "black_kite", 150, 100)
	var tl: Array = []
	var hit_samples: int = 0
	var mismatch: int = 0
	for i: int in range(90):
		tl.append_array(timed(p, 0.1))
		var en: Dictionary = E(p, id)
		var listed: bool = false
		for t: Dictionary in p.enemies.hittable_targets():
			if int(t.id) == id:
				listed = true
		var should: bool = en.state == "ground" or en.state == "climb"
		if listed and p.enemies.time < 6.0:
			hit_samples += 1
		if listed != should:
			mismatch += 1
		if absf(p.enemies.time - 2.1) < 0.01:
			mismatch += 0 if (en.state == "dive" and not listed) else 1
		if absf(p.enemies.time - 2.5) < 0.01:
			mismatch += 0 if listed else 1
	var dmg: Array = only(tl, "hero_damage")
	ck("e19_shadow_1_5s_lock_0_5s_dive_hits_12", dmg.size() == 2 and near(float(dmg[0].t), 2.2, 0.11) and near(float(dmg[0].e.amount), 12.0) and near(float(dmg[1].t) - float(dmg[0].t), 6.1, 0.15), "n=%d t=%s" % [dmg.size(), str(dmg[0].t) if dmg.size() > 0 else "-"])
	ck("e19_hittable_only_on_ground_and_climb_2s", mismatch == 0 and hit_samples >= 19 and hit_samples <= 21, "samples=%d mismatch=%d" % [hit_samples, mismatch])
	var sh: Array = []
	for x: Dictionary in only(tl, "fx"):
		if x.e.kind == "dive_hit":
			sh.append(x)
	ck("e19_dive_radius_1m_fx", sh.size() == 2 and near(float(sh[0].e.radius), 10.0), "")
	# 影は追従し、固定後に動いても当たらない
	var q: RefCounted = mk()
	hero(q, 150, 100)
	var qid: int = sp(q, "black_kite", 150, 100)
	timed(q, 1.0)
	hero(q, 160, 100)
	timed(q, 0.4)
	var follow: Vector2 = E(q, qid).shadow
	timed(q, 0.4)
	hero(q, 200, 100)
	timed(q, 0.2)
	var locked: Vector2 = E(q, qid).shadow
	var qtl: Array = timed(q, 1.5)
	var fx2: Array = []
	for x: Dictionary in only(qtl, "fx"):
		if x.e.kind == "dive_hit":
			fx2.append(x)
	ck("e19_shadow_follows_then_locks_and_dodge_works", follow.distance_to(Vector2(160, 100)) < 0.01 and locked.distance_to(Vector2(160, 100)) < 0.01 and only(qtl, "hero_damage").is_empty() and fx2.size() == 1 and Vector2(fx2[0].e.pos).distance_to(Vector2(160, 100)) < 0.01, "%s %s" % [str(follow), str(locked)])
	# 主人公がいなければおたすけ植物を狙う
	var r: RefCounted = mk()
	helper(r, 4, 160, 100)
	sp(r, "black_kite", 150, 100)
	var rtl: Array = timed(r, 2.5)
	ck("e19_targets_helper_when_no_hero", only(rtl, "helper_damage").size() == 1 and near(float(only(rtl, "helper_damage")[0].e.amount), 12.0), "")
	# 安定地域の上空へは入らず、そこにいる相手は狙わない
	var s: RefCounted = mk()
	s.host.set_stable_rect(Rect2i(36, 20, 8, 10))
	hero(s, 156, 100)
	var sid: int = sp(s, "black_kite", 100, 100, "initial", {"home": Vector2(130, 100)})
	var in_stable: bool = false
	var reversed: bool = false
	var moved_ang: float = 0.0
	var states_ok: bool = true
	var stl: Array = []
	for i: int in range(120):
		stl.append_array(timed(s, 0.1))
		var en2: Dictionary = E(s, sid)
		if s.host.is_stable_cell(Vector2i(floori(en2.pos.x / 4.0), floori(en2.pos.y / 4.0))):
			in_stable = true
		if float(en2.dir_sign) < 0.0:
			reversed = true
		moved_ang = maxf(moved_ang, absf(float(en2.ang) - PI))
		if en2.state != "circle":
			states_ok = false
	ck("e19_never_enters_or_targets_stable_airspace", not in_stable and reversed and moved_ang > 1.0 and states_ok and only(stl, "hero_damage").is_empty(), "stable=%s rev=%s ang=%.2f" % [str(in_stable), str(reversed), moved_ang])

# ------------------------------------------------------------------ E20 シカ
func t_e20() -> void:
	var p: RefCounted = mk()
	var cid: int = crop(p, "clover", 30, 6)
	var id: int = sp(p, "deer", 112, 26)
	var tl: Array = timed(p, 6.0)
	var cd: Array = only(tl, "crop_damaged")
	var all3: bool = true
	for x: Dictionary in cd:
		if not near(float(x.e.amount), 3.0):
			all3 = false
	ck("e20_eats_mature_crop_3_per_second_and_ignores_hero", cd.size() == 5 and all3 and near(float(p.crops.get_crop(cid).hp), 15.0) and E(p, id).state == "eat" and only(tl, "hero_damage").is_empty(), "n=%d" % cd.size())
	# 4m以内の主人公で3.5m/sで逃げ、4秒走って3秒疲れる
	var q: RefCounted = mk()
	hero(q, 70, 100)
	var qid: int = sp(q, "deer", 100, 100, "initial", {"home": Vector2(100, 100)})
	timed(q, 1.2)
	var moved: float = float(E(q, qid).pos.x) - 100.0
	var s1: String = str(E(q, qid).state)
	timed(q, 3.1)
	var tired_pos: Vector2 = E(q, qid).pos
	var s2: String = str(E(q, qid).state)
	timed(q, 2.7)
	var held: bool = Vector2(E(q, qid).pos).distance_to(tired_pos) < 0.01 and str(E(q, qid).state) == "tired"
	timed(q, 0.5)
	ck("e20_flee_3_5mps_4s_run_3s_tired", near(moved, 38.5, 1.1) and s1 == "flee" and s2 == "tired" and held and str(E(q, qid).state) == "graze", "moved=%.2f %s %s %s" % [moved, s1, s2, str(E(q, qid).state)])
	var r: RefCounted = mk()
	hero(r, 170, 100)
	var rid: int = sp(r, "deer", 190, 100, "initial", {"home": Vector2(60, 100)})
	var maxd: float = 0.0
	for i: int in range(120):
		r.advance(0.1)
		maxd = maxf(maxd, Vector2(E(r, rid).pos).distance_to(Vector2(60, 100)))
	ck("e20_flee_stays_inside_territory_15m", maxd <= 150.01 and maxd >= 147.0, "maxd=%.2f" % maxd)
	# 攻撃が当たると逃げる。疲れている間は逃げず撃てる。報酬8
	var s: RefCounted = mk()
	var sid: int = sp(s, "deer", 100, 100)
	s.hit_enemy(sid, 3.0, "shot", Vector2(60, 100))
	var st_hit: String = str(E(s, sid).state)
	timed(s, 4.4)
	var st_tired: String = str(E(s, sid).state)
	s.hit_enemy(sid, 3.0, "shot", Vector2(60, 100))
	var st_after: String = str(E(s, sid).state)
	var kev: Array = s.hit_enemy(sid, 30.0, "shot", Vector2(60, 100))
	ck("e20_hit_makes_it_flee_tired_deer_can_be_shot_reward_8", st_hit == "flee" and st_tired == "tired" and st_after == "tired" and evs(kev, "reward").size() == 1 and int(evs(kev, "reward")[0].amount) == 8, "%s %s %s" % [st_hit, st_tired, st_after])

# ------------------------------------------------------------------ E21 テツアゴクワガタ
func t_e21() -> void:
	var p: RefCounted = mk()
	hero(p, 110, 100)
	helper(p, 7, 160, 100)
	sp(p, "iron_jaw_beetle", 100, 100)
	var tl: Array = timed(p, 8.0)
	var hd: Array = only(tl, "helper_damage")
	ck("e21_prefers_helper_windup_0_5s_snip_20", hd.size() >= 2 and int(hd[0].e.helper_id) == 7 and near(float(hd[0].e.amount), 20.0) and float(hd[0].t) >= 3.3 and float(hd[0].t) <= 3.9 and only(tl, "hero_damage").is_empty(), "n=%d t=%s" % [hd.size(), str(hd[0].t) if hd.size() > 0 else "-"])
	ck("e21_recovers_1_5s_after_snip", hd.size() >= 2 and float(hd[1].t) - float(hd[0].t) >= 1.99 and float(hd[1].t) - float(hd[0].t) <= 2.25, "gap=%.2f" % (float(hd[1].t) - float(hd[0].t)) if hd.size() >= 2 else "")
	var q: RefCounted = mk()
	hero(q, 128, 100)
	sp(q, "iron_jaw_beetle", 100, 100)
	var qt: Array = timed(q, 3.0)
	ck("e21_hero_within_3m_takes_8", only(qt, "hero_damage").size() >= 1 and near(float(only(qt, "hero_damage")[0].e.amount), 8.0) and only(qt, "helper_damage").is_empty(), "")
	var r: RefCounted = mk()
	hero(r, 140, 100)
	var rid: int = sp(r, "iron_jaw_beetle", 100, 100)
	var rt: Array = timed(r, 5.0)
	ck("e21_hero_at_4m_is_ignored", only(rt, "hero_damage").is_empty() and str(E(r, rid).state) == "idle", str(E(r, rid).state))
	var s: RefCounted = mk()
	helper(s, 8, 240, 100)
	var sid: int = sp(s, "iron_jaw_beetle", 100, 100)
	var stl: Array = timed(s, 4.0)
	ck("e21_helper_beyond_12m_ignored", only(stl, "helper_damage").is_empty() and str(E(s, sid).state) == "idle", "")

# ------------------------------------------------------------------ 保存(新しい10種を含む)
func _scene_b(p: RefCounted) -> void:
	hero(p, 200, 60)
	helper(p, 9, 250, 60)
	crop(p, "clover", 30, 6)
	crop(p, "clover", 20, 12)
	crop(p, "clover", 57, 8)
	sp(p, "pouch_rabbit", 112, 26)
	sp(p, "tongue_frog", 180, 60)
	sp(p, "honeybee_hive", 82, 122)
	var bee: Dictionary = _bee_ids(p)
	p.hit_enemy(int(bee.swarm), 1.0, "shot", Vector2(200, 60))
	sp(p, "armadillo", 150, 20)
	var carp: int = sp(p, "sludge_carp", 30, 30)
	R(p, carp).muds.append({"pos": Vector2(70, 30), "land_at": 6.0})
	var hill: int = sp(p, "ant_hill", 100, 60)
	for f: float in [0.35, 0.6, 0.85]:
		var pos: Vector2 = Vector2(100, 60).lerp(Vector2(82, 50), f)
		var aid: int = sp(p, "leafcutter_ant", pos.x, pos.y, "initial", {"hill_id": hill, "home": Vector2(100, 60)})
		R(p, aid).state = "walk"
		R(p, aid).target_crop = p.crops.crop_id_at(Vector2i(20, 12))
	sp(p, "mimic_cabbage", 210, 72)
	sp(p, "black_kite", 170, 60)
	sp(p, "deer", 230, 30)
	sp(p, "iron_jaw_beetle", 240, 60)

func t_save_all() -> void:
	var p: RefCounted = mk(11)
	_scene_b(p)
	p.advance(4.5)
	var direct: Dictionary = p.to_dict()
	var saved: Dictionary = roundtrip(direct)
	var q: RefCounted = mk(77)
	hero(q, 200, 60)
	helper(q, 9, 250, 60)
	var okq: bool = q.from_dict(saved)
	var r: RefCounted = mk(78)
	hero(r, 200, 60)
	helper(r, 9, 250, 60)
	var okr: bool = r.from_dict(direct)
	p.advance(8.0)
	q.advance(8.0)
	r.advance(8.0)
	var kinds: Dictionary = {}
	for e: Dictionary in p.enemies.enemies:
		kinds[e.kind] = true
	var da: String = dump(p)
	var db: String = dump(r)
	var at: int = 0
	while at < mini(da.length(), db.length()) and da[at] == db[at]:
		at += 1
	ck("save_all_new_kinds_direct_dict_restore_is_exact", okr and da == db, "len=%d diff@%d: %s | %s" % [da.length(), at, da.substr(maxi(0, at - 60), 120), db.substr(maxi(0, at - 60), 120)])
	ck("save_all_new_kinds_json_roundtrip_continues_identically", okq and snap(p) == snap(q), snap(p).substr(0, 120))
	ck("save_all_scene_covers_10_new_kinds_midflight", kinds.size() >= 9 and direct.enemies.enemies.size() >= 14, "kinds=%d n=%d" % [kinds.size(), direct.enemies.enemies.size()])

# ------------------------------------------------------------------ 保存の原子性
func t_atomic() -> void:
	var p: RefCounted = mk(3)
	crop(p, "clover", 30, 6)
	crop(p, "clover", 31, 6)
	sp(p, "pouch_rabbit", 112, 26)
	sp(p, "deer", 150, 60)
	p.advance(2.0)
	var good: Dictionary = roundtrip(p.to_dict())
	var q: RefCounted = mk(5)
	crop(q, "clover", 10, 10)
	sp(q, "tongue_frog", 60, 60)
	q.advance(1.0)
	var before: String = dump(q)
	var rng_before: int = q.rng.state
	# crops は正常、enemies が不正(未知の種類)
	var bad1: Dictionary = good.duplicate(true)
	bad1.enemies.enemies[0].kind = "no_such_kind"
	var ok1: bool = q.from_dict(bad1)
	var same1: bool = dump(q) == before and q.rng.state == rng_before
	ck("atomic_bad_enemies_kind_changes_nothing", not ok1 and same1 and q.crops.crops.size() == 1 and str(q.last_error).begins_with("enemies"), str(q.last_error))
	# enemies が辞書でない
	var bad2: Dictionary = good.duplicate(true)
	bad2.enemies = 5
	var ok2: bool = q.from_dict(bad2)
	ck("atomic_enemies_not_a_dictionary_changes_nothing", not ok2 and dump(q) == before and q.crops.crops.size() == 1, str(q.last_error))
	# enemies の位置欠落
	var bad3: Dictionary = good.duplicate(true)
	bad3.enemies.enemies[1].erase("pos")
	var ok3: bool = q.from_dict(bad3)
	ck("atomic_bad_enemy_field_changes_nothing", not ok3 and dump(q) == before, str(q.last_error))
	# crops が不正で enemies が正常
	var bad4: Dictionary = good.duplicate(true)
	bad4.crops.crops[0].kind = "no_such_crop"
	var ok4: bool = q.from_dict(bad4)
	ck("atomic_bad_crops_changes_nothing", not ok4 and dump(q) == before and str(q.last_error).begins_with("crops"), str(q.last_error))
	# 乱数が不正
	var bad5: Dictionary = good.duplicate(true)
	bad5.rng.state = "xyz"
	var ok5: bool = q.from_dict(bad5)
	ck("atomic_bad_rng_changes_nothing", not ok5 and dump(q) == before, "")
	# 正常なら全部を一括で採用する
	var ok6: bool = q.from_dict(good)
	ck("atomic_valid_data_adopts_everything", ok6 and q.crops.crops.size() == 2 and q.enemies.enemies.size() == 2 and q.rng.state == p.rng.state and snap(q) == snap(p), str(q.last_error))
