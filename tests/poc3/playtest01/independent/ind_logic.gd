extends SceneTree
## POC3-PLAYTEST-01 independent verification (logic). Items 1,3,5,6,11 + save + regressions.
const Session: GDScript = preload("res://scripts/poc2/poc2_session.gd")
const Coords: GDScript = preload("res://scripts/poc/poc_coords.gd")
const OUT: String = "res://evidence/poc3/playtest01/independent/"
var checks: Array[Dictionary] = []
const C: Vector2i = Vector2i(192, 188)

func _init() -> void: call_deferred("run")
func chk(n: String, ok: bool, d: Variant = "") -> void:
	checks.append({"name": n, "status": "PASS" if ok else "FAIL", "detail": d})
	print(JSON.stringify(checks.back()))
func fresh() -> RefCounted:
	var s: RefCounted = Session.new()
	s.enemies.clear(); s.nests.clear(); s.fossils.clear()
	for y: int in range(180, 196):
		for x: int in range(176, 210): s.state.set_stage(s.state.index_of(x, y), WorldState.STAGE_EMPTY)
	s.position = Coords.cell_center_logic(C + Vector2i(-5, 0))
	s.known.fill(1)
	s.water = 100.0
	return s
func cc(c: Vector2i) -> Vector2: return Coords.cell_center_logic(c)
func wet(s: RefCounted, c: Vector2i) -> bool: return s.state.moisture[s.state.index_of(c.x, c.y)] > 0
func idx(s: RefCounted, c: Vector2i) -> int: return s.state.index_of(c.x, c.y)

func water_tests() -> void:
	# Checkerboard of growing cells; only those are effective. Player 40px (10 cells) left of aim -> clamp to 50 not needed (aim 5 cells away = 20px).
	for w: int in [1, 3, 5, 7]:
		var s: RefCounted = fresh()
		var center: Vector2i = C + Vector2i(1, 1)
		var h: int = w >> 1
		var expected: int = 0
		for y: int in range(center.y - 6, center.y + 7):
			for x: int in range(center.x - 6, center.x + 7):
				if (x + y) % 2 == 0:
					s.state.set_stage(idx(s, Vector2i(x, y)), WorldState.STAGE_SEED)
					if absi(x - center.x) <= h and absi(y - center.y) <= h: expected += 1
		s.sow_width = w
		var r: Dictionary = s.water_at(cc(center))
		var wet_in: int = 0; var wet_out: int = 0; var wet_dead: int = 0
		for y: int in range(center.y - 6, center.y + 7):
			for x: int in range(center.x - 6, center.x + 7):
				if wet(s, Vector2i(x, y)):
					if absi(x - center.x) <= h and absi(y - center.y) <= h: wet_in += 1
					else: wet_out += 1
					if (x + y) % 2 != 0: wet_dead += 1
		chk("item1_3_width%d_checker_cost_equals_effective" % w, bool(r.ok) and wet_in == expected and wet_out == 0 and wet_dead == 0 and absf(s.water - (100.0 - float(expected))) < 0.001, {"expected": expected, "wet_in": wet_in, "water": s.water})
		s.close()
	# shortage fractional water, nearest first; independent distance property
	var s2: RefCounted = fresh()
	var center2: Vector2i = C + Vector2i(2, -1)
	for y: int in range(center2.y - 3, center2.y + 4):
		for x: int in range(center2.x - 3, center2.x + 4): s2.state.set_stage(idx(s2, Vector2i(x, y)), WorldState.STAGE_SPROUT1)
	s2.sow_width = 7; s2.water = 13.7
	var r2: Dictionary = s2.water_at(cc(center2))
	var max_wet: int = -1; var min_dry: int = 1 << 30; var nwet: int = 0
	for y: int in range(center2.y - 3, center2.y + 4):
		for x: int in range(center2.x - 3, center2.x + 4):
			var d2: int = (x - center2.x) * (x - center2.x) + (y - center2.y) * (y - center2.y)
			if wet(s2, Vector2i(x, y)): nwet += 1; max_wet = maxi(max_wet, d2)
			else: min_dry = mini(min_dry, d2)
	chk("item1_shortage_floor_water_nearest_first", bool(r2.ok) and nwet == 13 and max_wet <= min_dry and absf(s2.water - 0.7) < 0.001, {"nwet": nwet, "max_wet": max_wet, "min_dry": min_dry, "water": s2.water})
	var r2b: Dictionary = s2.water_at(cc(center2))
	chk("item1_water_below_1_refused", not bool(r2b.ok) and r2b.reason == "no_water" and absf(s2.water - 0.7) < 0.001)
	s2.close()
	# no_effect: nothing spent, no dirty, ok false; repeat on already watered
	var s3: RefCounted = fresh()
	s3.sow_width = 5
	for y: int in range(C.y - 2, C.y + 3):
		for x: int in range(C.x - 2, C.x + 3): s3.state.set_stage(idx(s3, Vector2i(x, y)), WorldState.STAGE_SEED)
	for y: int in range(C.y - 2, C.y + 3):
		for x: int in range(C.x + 3, C.x + 5): s3.state.set_stage(idx(s3, Vector2i(x, y)), WorldState.STAGE_SEED)
	s3.sow_width = 5
	var first: Dictionary = s3.water_at(cc(C - Vector2i(0, 0)))
	var wl: float = s3.water
	s3.state.clear_dirty()
	var second: Dictionary = s3.water_at(cc(C))
	var chk_r: Dictionary = s3.water_check(cc(C))
	chk("item3_second_watering_no_effect_zero_spend", bool(first.ok) and not bool(second.ok) and second.reason == "no_effect" and not bool(chk_r.ok) and s3.water == wl and s3.state.dirty_tiles.size() == 0, {"first_cost": first.get("cost"), "second": second})
	# partially overlapping second: shifted by 2 -> only 10 new cells charged
	var third: Dictionary = s3.water_at(cc(C + Vector2i(2, 0)))
	chk("item3_overlap_charges_only_new_cells", bool(third.ok) and int(third.cost) == 10 and absf(s3.water - (wl - 10.0)) < 0.001, third)
	s3.close()
	# blocked
	var s4: RefCounted = fresh()
	s4.sow_width = 3
	var tgt: Vector2i = Coords.logic_to_cell(s4.position) + Vector2i(8, 0)
	for y: int in range(tgt.y - 1, tgt.y + 2):
		for x: int in range(tgt.x - 1, tgt.x + 2): s4.state.set_stage(idx(s4, Vector2i(x, y)), WorldState.STAGE_SEED)
	var pc: Vector2i = Coords.logic_to_cell(s4.position)
	var wallc: Vector2i = pc + Vector2i(4, 0)
	s4.placement.projectile[wallc.y * s4.placement.width + wallc.x] = 1
	var b: Dictionary = s4.water_at(cc(tgt))
	chk("item3_blocked_by_obstacle_no_spend", not bool(b.ok) and b.reason == "blocked" and s4.water == 100.0 and not wet(s4, tgt) and s4.water_preview(cc(tgt)).blocked, b)
	s4.placement.projectile[wallc.y * s4.placement.width + wallc.x] = 0
	var b2: Dictionary = s4.water_at(cc(tgt))
	chk("item3_unblocked_works", bool(b2.ok) and int(b2.cost) == 9, b2)
	s4.close()
	# range clamp: aim 200px away, width 1; grow cell at exactly 50px along x
	var s5: RefCounted = fresh()
	s5.sow_width = 1
	var p: Vector2 = s5.position
	var far_cell: Vector2i = Coords.logic_to_cell(p + Vector2(50, 0))
	var mid_cell: Vector2i = Coords.logic_to_cell(p + Vector2(120, 0))
	s5.state.set_stage(idx(s5, far_cell), WorldState.STAGE_SEED)
	s5.state.set_stage(idx(s5, mid_cell), WorldState.STAGE_SEED)
	var r5: Dictionary = s5.water_at(p + Vector2(200, 0))
	chk("item1_range_clamped_50", bool(r5.ok) and wet(s5, far_cell) and not wet(s5, mid_cell) and s5.water == 99.0, r5)
	s5.close()
	# paused
	var s6: RefCounted = fresh()
	s6.sow_width = 1
	s6.state.set_stage(idx(s6, C), WorldState.STAGE_SEED)
	s6.paused = true
	var r6: Dictionary = s6.water_at(cc(C))
	chk("item3_paused_refused", not bool(r6.ok) and s6.water == 100.0 and not wet(s6, C), r6)
	s6.close()
	# crop: mature crops/ placed immature crop counts; footprints count once
	var s7: RefCounted = fresh()
	s7.unlocked["watermelon"] = true; s7.seeds = 100000
	s7.sow_width = 7
	for y: int in range(C.y - 5, C.y + 6):
		for x: int in range(C.x - 5, C.x + 6): s7.state.set_stage(idx(s7, Vector2i(x, y)), WorldState.STAGE_MATURE)
	var pr: Dictionary = s7.place_plant("watermelon", C + Vector2i(-1, -1))
	var p7: Dictionary = {}
	for q: Dictionary in s7.plants: p7 = q
	var rr: Dictionary = s7.water_at(cc(C))
	chk("item1_crop_unit_counts_once", bool(pr.ok) and bool(rr.ok) and int(rr.cost) == 1 and bool(p7.watered) and s7.water == 99.0, rr)
	var rr2: Dictionary = s7.water_at(cc(C))
	chk("item3_watered_crop_no_effect", not bool(rr2.ok) and rr2.reason == "no_effect" and s7.water == 99.0)
	# save/restore
	s7.sow_width = 5
	var d: Dictionary = JSON.parse_string(JSON.stringify(s7.to_dict()))
	var rs: RefCounted = Session.new()
	var rres: Dictionary = rs.restore(d)
	var rw: bool = false
	for q: Dictionary in rs.plants: rw = bool(q.watered)
	chk("save_restores_watered_crop_and_sow_width", bool(rres.ok) and rw and rs.sow_width == 5, rres)
	rs.close(); s7.close()
	# wet grass save
	var s8: RefCounted = fresh()
	s8.sow_width = 3
	for y: int in range(C.y - 1, C.y + 2):
		for x: int in range(C.x - 1, C.x + 2): s8.state.set_stage(idx(s8, Vector2i(x, y)), WorldState.STAGE_SEED)
	s8.water_at(cc(C))
	var rs2: RefCounted = Session.new()
	var res2: Dictionary = rs2.restore(JSON.parse_string(JSON.stringify(s8.to_dict())))
	var n: int = 0
	for y: int in range(C.y - 1, C.y + 2):
		for x: int in range(C.x - 1, C.x + 2):
			if wet(rs2, Vector2i(x, y)): n += 1
	chk("save_restores_wet_grass", bool(res2.ok) and n == 9, n)
	rs2.close(); s8.close()

func price_tests() -> void:
	# independent expected values computed offline with exact rationals: ceil(base*1.1^n)
	var table: Dictionary = {
		"clover": [10, 11, 13, 14, 15, 17], "carrot": [15, 17, 19, 20, 22, 25],
		"wheat": [40, 44, 49, 54, 59, 65], "rafflesia": [40, 44, 49, 54, 59, 65], "watermelon": [120, 132, 146, 160, 176, 194]}
	var ok_all: bool = true
	var got: Dictionary = {}
	for kind: String in table:
		var s: RefCounted = fresh()
		s.unlocked[kind] = true; s.seeds = 1000000000
		var seq: Array[int] = []
		for y: int in range(C.y - 8, C.y + 8):
			for x: int in range(C.x - 20, C.x + 20): s.state.set_stage(idx(s, Vector2i(x, y)), WorldState.STAGE_MATURE)
		for n: int in 6:
			seq.append(s.current_cost(kind))
			var before: int = s.seeds
			var cell: Vector2i = C + Vector2i(n * 5 - 14, 0)
			var res: Dictionary = s.place_plant(kind, cell)
			if not bool(res.ok) or before - s.seeds != seq[n]: ok_all = false; seq.append(-999)
		got[kind] = seq
		if seq.slice(0, 6) != (table[kind] as Array): ok_all = false
		s.close()
	chk("item6_price_ceil_1_1_pow_n_and_charged_n0to5", ok_all, got)
	var s2: RefCounted = fresh()
	chk("item6_helpers_fixed_price", s2.current_cost("army") == 25 and s2.current_cost("gatlinger") == 30 and s2.current_cost("sprinkler") == 20)
	s2.close()

func gatling_tests() -> void:
	var s: RefCounted = fresh()
	s.unlocked["gatlinger"] = true; s.seeds = 10000
	# open ground target: dry bare soil (can_plant) around
	var res: Dictionary = s.place_helper("gatlinger", C, 100)
	var h: Dictionary = s.helpers[0]
	var times: Array[float] = []
	var ammo_prev: int = int(h.ammo)
	var seeds_before: int = s.seeds
	var log_rows: Array = []
	for i: int in 400:
		s.advance_game(0.05)
		if int(h.ammo) != ammo_prev:
			log_rows.append([snappedf(s.clock.elapsed, 0.01), ammo_prev - int(h.ammo)])
			ammo_prev = int(h.ammo)
		if log_rows.size() >= 8: break
	# group bursts: events within the same 0.1s window
	var bursts: Array = []
	for row: Array in log_rows:
		if bursts.is_empty() or row[0] - bursts[-1][0] > 0.3: bursts.append([row[0], row[1]])
		else: bursts[-1][1] += row[1]
	var gaps: Array = []
	for i: int in range(1, bursts.size()): gaps.append(snappedf(bursts[i][0] - bursts[i - 1][0], 0.01))
	var sizes: Array = bursts.map(func(b: Array) -> int: return b[1])
	var gaps_ok: bool = gaps.size() >= 2
	for g: float in gaps: gaps_ok = gaps_ok and g >= 1.15 and g <= 1.35
	chk("item5_gatling_4_per_volley_each_1_2s", bool(res.ok) and bursts.size() >= 3 and sizes.slice(0, 3) == [4, 4, 4] and gaps_ok, {"bursts": bursts, "gaps": gaps, "seed_balance_unchanged": s.seeds == seeds_before})
	s.close()

func gatling_consistency() -> void:
	var s: RefCounted = fresh()
	s.unlocked["gatlinger"] = true; s.seeds = 10000
	var seeds0: int = s.seeds
	s.place_helper("gatlinger", C, 100)
	var seeds_after_place: int = s.seeds
	var h: Dictionary = s.helpers[0]
	var occupied0: int = 0
	for y: int in range(176, 200):
		for x: int in range(170, 215):
			if s.state.stage[idx(s, Vector2i(x, y))] > 0: occupied0 += 1
	for i: int in 200: s.advance_game(0.05)   # 10 s of firing
	var fired: int = 100 - int(h.ammo)
	for i: int in 60: s.advance_game(0.05)  # let flights land (gun may keep firing; recompute)
	fired = 100 - int(h.ammo)
	var now: int = 0
	for y: int in range(176, 200):
		for x: int in range(170, 215):
			if s.state.stage[idx(s, Vector2i(x, y))] > 0: now += 1
	var planted: int = now - occupied0
	chk("item5_gatling_ammo_spent_matches_cells_planted_and_player_seeds_untouched", fired >= 30 and planted > 0 and planted >= fired - s.shots.size() - 3 and planted <= fired + 1 and s.seeds == seeds_after_place and seeds_after_place == seeds0 - 30 - 100, {"fired": fired, "planted_cells": planted, "in_flight": s.shots.size(), "ammo": h.ammo, "seeds": [seeds0, seeds_after_place, s.seeds]})
	s.close()

func sprinkler_tests() -> void:
	var s: RefCounted = fresh()
	s.unlocked["sprinkler"] = true; s.seeds = 10000
	s.state.set_stage(idx(s, C + Vector2i(-5, 0)), WorldState.STAGE_EMPTY)
	var res: Dictionary = s.place_helper("sprinkler", C)
	var h: Dictionary = s.helpers[0]
	for y: int in range(180, 196):
		for x: int in range(176, 210):
			s.state.set_stage(idx(s, Vector2i(x, y)), WorldState.STAGE_EMPTY)
	# 28 cells = 112px+2 (inside 120) vs 33 cells = 132px (outside)
	var inside: Vector2i = C + Vector2i(27, 0)
	var outside: Vector2i = C + Vector2i(32, 0)
	s.state.set_stage(idx(s, outside), WorldState.STAGE_SEED)
	var t_out: Vector2 = s.plant_system._work_target(h, true)
	s.state.set_stage(idx(s, outside), WorldState.STAGE_EMPTY)
	s.state.set_stage(idx(s, inside), WorldState.STAGE_SEED)
	var t_in: Vector2 = s.plant_system._work_target(h, true)
	chk("item11_sprinkler_reaches_108px_not_128px", bool(res.ok) and t_out.x < 0.0 and t_in == cc(inside), {"t_in": t_in, "t_out": t_out})
	# Control: army/gatling job radius stays 6m
	var s2: RefCounted = fresh()
	s2.unlocked["gatlinger"] = true; s2.seeds = 10000
	s2.place_helper("gatlinger", C, 50)
	var gh: Dictionary = s2.helpers[0]
	s2.state.set_stage(idx(s2, C), WorldState.STAGE_EMPTY)
	s2.state.set_stage(idx(s2, C + Vector2i(20, 0)), WorldState.STAGE_SEED)
	var gt: Vector2 = s2.plant_system._work_target(gh, false)
	chk("item11_gatling_radius_still_6m", gt.x >= 0.0 and gt.distance_to(gh.home) <= 60.0 + 0.01, str(gt))
	s2.close(); s.close()

func run() -> void:
	water_tests(); price_tests(); gatling_tests(); gatling_consistency(); sprinkler_tests()
	var f: int = 0
	for r: Dictionary in checks:
		if r.status == "FAIL": f += 1
	var fa: FileAccess = FileAccess.open(OUT + "logic_results.json", FileAccess.WRITE)
	fa.store_string(JSON.stringify({"checks": checks, "failures": f}, "  ")); fa.close()
	quit(1 if f > 0 else 0)
