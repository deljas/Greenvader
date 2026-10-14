extends SceneTree
## Independent verifier for P1-03, logic level (headless; no scene). Expectations come from the spec
## (stage thresholds, factor definitions, caps) and from brute-force scans, not from the implementation's formulas.
## Run: Godot --headless --path <project> --script res://tests/p1/independent/p1_03_v_logic.gd [-- --only=perf]

const OUT: String = "res://evidence/p1/p1-03/independent/"
const TILE: int = 4

var results: Array[Dictionary] = []
var observations: Dictionary = {}
var sim_tun: SimTuning
var play_tun: PlayTuning
var region_def: RegionDef

func _initialize() -> void:
	run.call_deferred()

func rec(id: String, cond: String, ok: bool, observed: String) -> void:
	results.append({"id": id, "condition": cond, "status": "PASS" if ok else "FAIL", "observed": observed})
	print("%s [%s] %s :: %s" % ["PASS" if ok else "FAIL", id, cond, observed])

func run() -> void:
	sim_tun = load("res://data/sim_tuning.tres") as SimTuning
	play_tun = load("res://data/play_tuning.tres") as PlayTuning
	region_def = load("res://data/region_01.tres") as RegionDef
	var only: String = ""
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.trim_prefix("--only=")
	var tests: Dictionary = {
		"timing": t_timing, "decay": t_decay, "floor": t_floor, "greening": t_greening, "active": t_active,
		"moisture": t_moisture, "gather": t_gather, "stats": t_stats, "pos": t_positions, "caps": t_caps,
		"rate": t_framerate, "save": t_save, "paths": t_paths, "perf": t_perf,
	}
	for key: String in tests:
		if only != "" and only != key:
			continue
		print("--- section ", key)
		var t0: int = Time.get_ticks_msec()
		(tests[key] as Callable).call()
		print("--- section %s done in %d ms" % [key, Time.get_ticks_msec() - t0])
	var f: FileAccess = FileAccess.open(OUT + "checks_logic%s.json" % ("" if only == "" else "_" + only), FileAccess.WRITE)
	f.store_string(JSON.stringify({"results": results, "observations": observations}, "  "))
	f.close()
	var fails: int = 0
	for r: Dictionary in results:
		if r["status"] != "PASS":
			fails += 1
	print("V_RESULT total=%d fails=%d" % [results.size(), fails])
	quit(1 if fails > 0 else 0)

# ------------------------------------------------------------------------------------------ helpers

func fresh() -> WorldState:
	return RegionLoader.load_region(region_def)

## World with the safe zone's initial mature plants removed (so exact mature counts are under my control).
func fresh_clean() -> WorldState:
	var w: WorldState = fresh()
	for i: int in w.tile_count():
		if w.stage[i] != 0:
			w.set_stage(i, 0)
	w.clear_dirty()
	return w

func center_of(t: Vector2i) -> Vector2:
	return (Vector2(t) + Vector2(0.5, 0.5)) * TILE

func square_all(world: WorldState, cx: int, cy: int, half: int, terrain_id: int) -> bool:
	if cx - half < 0 or cy - half < 0 or cx + half >= world.width or cy + half >= world.height:
		return false
	for y: int in range(cy - half, cy + half + 1):
		for x: int in range(cx - half, cx + half + 1):
			if world.terrain[y * world.width + x] != terrain_id:
				return false
	return true

func find_square(world: WorldState, terrain_id: int, half: int, near: Vector2i) -> Vector2i:
	var best: Vector2i = Vector2i(-1, -1)
	var best_d: int = 1 << 60
	for cy: int in range(half, world.height - half, 2):
		for cx: int in range(half, world.width - half, 2):
			var d: int = (cx - near.x) * (cx - near.x) + (cy - near.y) * (cy - near.y)
			if d >= best_d:
				continue
			if square_all(world, cx, cy, half, terrain_id):
				best = Vector2i(cx, cy)
				best_d = d
	return best

func plantable_list(world: WorldState, n: int, skip: int = 0) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	var skipped: int = 0
	for i: int in world.tile_count():
		if world.can_plant(i):
			if skipped < skip:
				skipped += 1
				continue
			out.append(i)
			if out.size() >= n:
				break
	return out

func hash_world(w: WorldState) -> String:
	return "%d/%d/%d" % [hash(w.stage), hash(w.growth), hash(w.moisture)]

func brute_active(w: WorldState) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	for i: int in w.tile_count():
		var s: int = w.stage[i]
		if (s >= 1 and s <= 3) or w.moisture[i] > 0:
			out.append(i)
	return out

func sorted_copy(a: PackedInt32Array) -> PackedInt32Array:
	var b: PackedInt32Array = a.duplicate()
	b.sort()
	return b

func brute_count_circle(w: WorldState, c: Vector2, r: float) -> int:
	var n: int = 0
	for y: int in range(maxi(floori((c.y - r) / TILE) - 1, 0), mini(floori((c.y + r) / TILE) + 2, w.height)):
		for x: int in range(maxi(floori((c.x - r) / TILE) - 1, 0), mini(floori((c.x + r) / TILE) + 2, w.width)):
			if w.stage[y * w.width + x] == 4:
				if Vector2((x + 0.5) * TILE, (y + 0.5) * TILE).distance_to(c) <= r:
					n += 1
	return n

# ------------------------------------------------------------------------------------------ 1 timing

func stage_ticks(world: WorldState, gs: GrowthSim, idx: int, keep_moisture: int, fert: int, max_ticks: int = 400) -> Array:
	world.fertility[idx] = fert
	world.set_stage(idx, WorldState.STAGE_SEED)
	var res: Array = [0, 0, 0]
	for t: int in range(1, max_ticks + 1):
		if keep_moisture >= 0:
			world.set_moisture(idx, keep_moisture)
		gs.tick()
		var s: int = world.stage[idx]
		for k: int in 3:
			if res[k] == 0 and s >= k + 2:
				res[k] = t
	return res

func t_timing() -> void:
	var w: WorldState = fresh()
	var gs: GrowthSim = GrowthSim.new(w, sim_tun)
	var tiles: PackedInt32Array = plantable_list(w, 10)
	# Expected from the spec numbers: base 1000/tick, thresholds 40000/80000/120000, factors 1..2 (moisture) and 1..1.5 (fertility).
	var cases: Array = [
		["dry", -1, 0, [40, 80, 120]],
		["moisture100_fixed", 100, 0, [20, 40, 60]],
		["moisture50_fixed", 50, 0, [27, 54, 80]],
		["moisture25_fixed", 25, 0, [32, 64, 96]],
		["fert100_dry", -1, 100, [27, 54, 80]],
		["fert100_moisture100", 100, 100, [14, 27, 40]],
	]
	var all_ok: bool = true
	var obs: PackedStringArray = PackedStringArray()
	for i: int in cases.size():
		var c: Array = cases[i]
		var got: Array = stage_ticks(w, gs, tiles[i], int(c[1]), int(c[2]))
		var ok: bool = got == c[3]
		all_ok = all_ok and ok
		obs.append("%s got=%s want=%s" % [c[0], str(got), str(c[3])])
	rec("1.timing", "ticks (0.5 s) to sprout1/sprout2/mature: dry 40/80/120 (mature 60 s), moisture100 20/40/60 (30 s), moisture50, 25, fertility 100 per spec factors", all_ok, "; ".join(obs))
	# seconds via the real clock: dry 60 s, wet 30 s
	var clock: SimClock = SimClock.new()
	clock.configure(sim_tun)
	var w2: WorldState = fresh()
	var gs2: GrowthSim = GrowthSim.new(w2, sim_tun)
	clock.growth_ticked.connect(func(_n: int) -> void: gs2.tick())
	var dry: int = plantable_list(w2, 1)[0]
	w2.set_stage(dry, 1)
	var wet: int = plantable_list(w2, 2)[1]
	w2.set_stage(wet, 1)
	var t_dry: float = -1.0
	var t_wet: float = -1.0
	for step: int in 6000:
		w2.set_moisture(wet, 100)
		clock.advance(1.0 / 60.0)
		if t_wet < 0.0 and w2.stage[wet] == 4:
			t_wet = clock.elapsed
		if t_dry < 0.0 and w2.stage[dry] == 4:
			t_dry = clock.elapsed
	rec("1.seconds", "game time to mature: dry about 60 s, moisture 100 fixed about 30 s, ratio 2 (water speeds growth, dry still matures)", absf(t_dry - 60.0) < 0.1 and absf(t_wet - 30.0) < 0.1 and absf(t_dry / t_wet - 2.0) < 0.01, "dry=%.3f s wet=%.3f s ratio=%.4f" % [t_dry, t_wet, t_dry / t_wet])
	# monotonic stage order and no skipping at a threshold crossing (seed -> s1 -> s2 -> mature one by one at the dry rate)
	var w3: WorldState = fresh()
	var gs3: GrowthSim = GrowthSim.new(w3, sim_tun)
	var tl: int = plantable_list(w3, 1)[0]
	w3.set_stage(tl, 1)
	var seq: Array = []
	for t: int in 200:
		gs3.tick()
		if seq.is_empty() or seq[-1] != w3.stage[tl]:
			seq.append(w3.stage[tl])
	rec("1.sequence", "stage sequence of one dry seed is seed(1), sprout1(2), sprout2(3), mature(4) with no skips and no regress", seq == [1, 2, 3, 4], "seq=%s" % str(seq))
	# after mature: growth stays, tile leaves the active set when dry
	rec("1.mature_inactive", "a mature dry tile has left the active set and further ticks change nothing", not (tl in w3.active_tiles) and w3.stage[tl] == 4 and w3.active_flag[tl] == 0, "in_active=%s flag=%d growth=%d" % [str(tl in w3.active_tiles), w3.active_flag[tl], w3.growth[tl]])
	# a tile put directly into mature stage with moisture>0 stays active only until dry, and never regresses
	var w4: WorldState = fresh()
	var gs4: GrowthSim = GrowthSim.new(w4, sim_tun)
	var mt: int = plantable_list(w4, 1)[0]
	w4.set_stage(mt, 4)
	w4.set_moisture(mt, 30)
	var left_at: int = -1
	for t: int in 60:
		gs4.tick()
		if left_at < 0 and not (mt in w4.active_tiles):
			left_at = t + 1
	rec("1.wet_mature_active", "a wet mature tile is active exactly while moisture > 0 (30 -> 30 ticks), stays mature", left_at == 30 and w4.stage[mt] == 4, "left active after %d ticks stage=%d" % [left_at, w4.stage[mt]])

# ------------------------------------------------------------------------------------------ 2 decay integration

func t_decay() -> void:
	var w: WorldState = fresh()
	var gs: GrowthSim = GrowthSim.new(w, sim_tun)
	var idx: int = plantable_list(w, 1)[0]
	w.set_stage(idx, 1)
	w.set_moisture(idx, 100)
	# my own numeric integration (factor 1 + m/100 per spec: 1.0 dry .. 2.0 at 100; moisture falls 1 per 0.5 s tick)
	var model_pre: PackedInt32Array = PackedInt32Array()
	var model_post: PackedInt32Array = PackedInt32Array()
	var g1: int = 0
	var g2: int = 0
	var m1: int = 100
	var m2: int = 100
	for k: int in 200:
		g1 += roundi(1000.0 * (1.0 + float(m1) / 100.0))
		m1 = maxi(m1 - 1, 0)
		m2 = maxi(m2 - 1, 0)
		g2 += roundi(1000.0 * (1.0 + float(m2) / 100.0))
		model_pre.append(mini(g1, 120000))
		model_post.append(mini(g2, 120000))
	var mism: int = 0
	var first_mismatch: String = ""
	var traj_ok_post: bool = true
	var moisture_ok: bool = true
	for k: int in 120:
		gs.tick()
		if w.growth[idx] != model_pre[k]:
			mism += 1
			if first_mismatch == "":
				first_mismatch = "tick %d got %d want %d" % [k + 1, w.growth[idx], model_pre[k]]
		if w.growth[idx] != model_post[k]:
			traj_ok_post = false
		if w.moisture[idx] != maxi(100 - (k + 1), 0):
			moisture_ok = false
	var mature_tick_pre: int = 0
	var mature_tick_post: int = 0
	for k: int in 200:
		if mature_tick_pre == 0 and model_pre[k] >= 120000:
			mature_tick_pre = k + 1
		if mature_tick_post == 0 and model_post[k] >= 120000:
			mature_tick_post = k + 1
	rec("2.integral_pre", "growth after every tick equals my integral with moisture falling 100,99,... (tick uses moisture before the decay), 74 ticks to mature", mism == 0 and w.stage[idx] == 4, "mismatching ticks=%d %s; model mature tick pre=%d post=%d; model-post-decay also matches=%s" % [mism, first_mismatch, mature_tick_pre, mature_tick_post, str(traj_ok_post)])
	rec("2.moisture_traj", "moisture falls exactly 1 per 0.5 s tick (2 per second), reaching 0 after 100 ticks (50 s)", moisture_ok, "traj ok=%s" % str(moisture_ok))
	# time compared with a dry tile of the same start: wetter-then-drying lies between wet (60) and dry (120) ticks
	rec("2.between", "a tile that dries while growing matures between the always-wet (60) and always-dry (120) times", mature_tick_pre > 60 and mature_tick_pre < 120, "mature tick %d" % mature_tick_pre)
	# dry/zero: moisture never below 0, stops at 0
	var w2: WorldState = fresh()
	var gs2: GrowthSim = GrowthSim.new(w2, sim_tun)
	var t2: int = plantable_list(w2, 1)[0]
	w2.set_moisture(t2, 3)
	var seqm: Array = []
	for k: int in 6:
		gs2.tick()
		seqm.append(w2.moisture[t2])
	rec("2.moisture_floor", "moisture 3 falls 2,1,0 and stays 0 (no underflow to 255)", seqm == [2, 1, 0, 0, 0, 0], "seq=%s" % str(seqm))

# ------------------------------------------------------------------------------------------ 3 lower bound

func t_floor() -> void:
	var variants: Array = []
	var base_t: SimTuning = sim_tun.duplicate() as SimTuning
	variants.append(["real_tuning_sun0", base_t, 0.0])
	variants.append(["real_tuning_sun_neg", base_t, -5.0])
	variants.append(["real_tuning_sun_tiny", base_t, 0.0001])
	var t1: SimTuning = sim_tun.duplicate() as SimTuning
	t1.moisture_growth_min = 0.0
	t1.moisture_growth_max = 0.0
	t1.fertility_growth_bonus = 0.0
	t1.base_growth_per_tick = 1
	variants.append(["zero_moisture_coeff_base1", t1, 1.0])
	var t2: SimTuning = t1.duplicate() as SimTuning
	t2.base_growth_per_tick = 0
	variants.append(["base0_all_zero", t2, 0.0])
	var t3: SimTuning = sim_tun.duplicate() as SimTuning
	t3.moisture_growth_min = -3.0
	t3.moisture_growth_max = -3.0
	variants.append(["negative_moisture_coeff", t3, 1.0])
	var all_ok: bool = true
	var obs: PackedStringArray = PackedStringArray()
	for v: Array in variants:
		var w: WorldState = fresh()
		var gs: GrowthSim = GrowthSim.new(w, v[1] as SimTuning)
		var sun: float = float(v[2])
		gs.sunlight_provider = func(_i: int) -> float: return sun
		var tiles: PackedInt32Array = plantable_list(w, 3)
		w.fertility[tiles[1]] = 100
		w.set_stage(tiles[0], 1)
		w.set_stage(tiles[1], 1)
		w.set_stage(tiles[2], 1)
		w.set_moisture(tiles[2], 100)
		var strictly: bool = true
		var prev: PackedInt32Array = PackedInt32Array([0, 0, 0])
		for k: int in 100:
			gs.tick()
			for j: int in 3:
				if w.growth[tiles[j]] <= prev[j]:
					strictly = false
				prev[j] = w.growth[tiles[j]]
		all_ok = all_ok and strictly
		obs.append("%s strictly_growing=%s g=%s" % [v[0], str(strictly), str([prev[0], prev[1], prev[2]])])
	rec("3.floor", "growth gains at least 1 every tick (never stops) even with sunlight 0 / negative, moisture coefficient 0 or negative, fertility 0, base 0", all_ok, "; ".join(obs))
	# no growth-decreasing and the sunlight hook: factor 2 doubles speed (hook is wired, default 1.0)
	var w3: WorldState = fresh()
	var gs3: GrowthSim = GrowthSim.new(w3, sim_tun)
	var ti: PackedInt32Array = plantable_list(w3, 2)
	w3.set_stage(ti[0], 1)
	w3.set_stage(ti[1], 1)
	var sun2: Callable = func(i: int) -> float: return 2.0 if i == ti[1] else 1.0
	gs3.sunlight_provider = sun2
	for k: int in 10:
		gs3.tick()
	rec("3.sun_hook", "the sunlight hook multiplies speed (x2 -> 2x growth) and defaults to 1.0 without a provider (10 ticks dry: 10000 vs 20000)", w3.growth[ti[0]] == 10000 and w3.growth[ti[1]] == 20000, "g=%d / %d" % [w3.growth[ti[0]], w3.growth[ti[1]]])
	var w4: WorldState = fresh()
	var gs4: GrowthSim = GrowthSim.new(w4, sim_tun)
	var t4: int = plantable_list(w4, 1)[0]
	w4.set_stage(t4, 1)
	for k: int in 10:
		gs4.tick()
	rec("3.sun_default", "without provider growth is the plain dry rate (10 ticks = 10000)", w4.growth[t4] == 10000, "g=%d" % w4.growth[t4])

# ------------------------------------------------------------------------------------------ 4 greening

func t_greening() -> void:
	var w: WorldState = fresh()
	var gs: GrowthSim = GrowthSim.new(w, sim_tun)
	var play: PlayState = PlayState.new(w, play_tun, sim_tun, TILE, [Vector2(0, 0)])
	var base_g: int = 0
	for i: int in w.tile_count():
		if w.target[i] == 1 and w.stage[i] >= 2:
			base_g += 1
	rec("4.baseline", "baseline greened count equals my own scan of initial sprout-or-better target tiles (safe zone)", w.greened_count == base_g, "counter=%d my scan=%d" % [w.greened_count, base_g])
	var site: Vector2i = find_square(w, 0, 14, region_def.start_tile)
	play.seeds = 40
	var planted: PackedInt32Array = PackedInt32Array()
	for k: int in 8:
		var p: Vector2 = center_of(site) + Vector2((k % 4) * 14 - 21, (k / 4) * 14 - 7)
		for i: int in play.land_seed(p):
			planted.append(i)
	rec("4.seed_no_green", "planting seeds (stage 1) does not raise the greening count", planted.size() >= 20 and w.greened_count == base_g and w.counters_consistent(), "planted=%d greened=%d base=%d" % [planted.size(), w.greened_count, base_g])
	# per tick, compare the counter with base + number of planted tiles at stage >= 2 (my own bookkeeping)
	var mismatch: int = 0
	var first_inc: int = -1
	var steps_ok: bool = true
	var prev: int = base_g
	var wet: PackedInt32Array = PackedInt32Array()
	for k: int in planted.size():
		if k % 2 == 0:
			wet.append(planted[k])
	var late: PackedInt32Array = PackedInt32Array()
	for t: int in 160:
		if t == 25:
			# a second batch planted later
			for i: int in play.land_seed(center_of(site) + Vector2(0, 40)):
				late.append(i)
				planted.append(i)
		for i: int in wet:
			if t == 5:
				w.set_moisture(i, 100)
		gs.tick()
		var mine: int = base_g
		for i: int in planted:
			if w.stage[i] >= 2:
				mine += 1
		if mine != w.greened_count:
			mismatch += 1
		if first_inc < 0 and w.greened_count > base_g:
			first_inc = t + 1
		if w.greened_count < prev:
			steps_ok = false
		prev = w.greened_count
	rec("4.diff_vs_recount", "greening counter equals base + my count of planted tiles at sprout1 or later after every one of 160 ticks (includes a late batch)", mismatch == 0, "mismatching ticks=%d first increase at tick %d" % [mismatch, first_inc])
	var stages_seen: Dictionary = {}
	for i: int in planted:
		stages_seen[w.stage[i]] = true
	var recount: int = 0
	for i: int in w.tile_count():
		if w.target[i] == 1 and w.stage[i] >= 2:
			recount += 1
	rec("4.no_double", "after all stages the count is base + planted tiles exactly once each, equals a full recount, counters consistent", w.greened_count == recount and recount == base_g + planted.size() and w.counters_consistent(), "counter=%d recount=%d base+planted=%d stages=%s" % [w.greened_count, recount, base_g + planted.size(), str(stages_seen.keys())])
	# single-tile transitions: counter increments at 1 -> 2 only
	var w2: WorldState = fresh()
	var gs2: GrowthSim = GrowthSim.new(w2, sim_tun)
	var one: int = plantable_list(w2, 1)[0]
	w2.set_stage(one, 1)
	var g0: int = w2.greened_count
	var deltas: Array = []
	var last_stage: int = 1
	for k: int in 130:
		gs2.tick()
		if w2.stage[one] != last_stage:
			deltas.append([last_stage, w2.stage[one], w2.greened_count - g0])
			last_stage = w2.stage[one]
	rec("4.single", "one dry seed: greened +0 at seed, +1 at sprout1, still +1 at sprout2 and mature", deltas == [[1, 2, 1], [2, 3, 1], [3, 4, 1]], "transitions [from,to,greened delta]=%s" % str(deltas))
	# sprout position: 4 candidates, fixed per tile, roughly uniform over the map
	var hist: Array = [0, 0, 0, 0]
	var slot_bad: int = 0
	for i: int in w.tile_count():
		var sl: int = w.sprout_slot[i]
		if sl < 0 or sl > 3:
			slot_bad += 1
		else:
			hist[sl] += 1
	var slot_ok: bool = slot_bad == 0
	for h: int in hist:
		if absf(float(h) / float(w.tile_count()) - 0.25) > 0.01:
			slot_ok = false
	rec("4.sprout_slots", "every tile has one of 4 sprout positions, distribution within 1 point of uniform (random position among the 2x2 centre candidates)", slot_ok, "hist=%s" % str(hist))
	# non-target tiles never grow / count
	var nt_bad: int = 0
	for i: int in w.tile_count():
		if w.target[i] == 0 and (w.stage[i] != 0 or w.growth[i] != 0):
			nt_bad += 1
	rec("4.nontarget_clean", "non-target tiles (water, buildings) never get a stage or growth", nt_bad == 0, "bad=%d" % nt_bad)

# ------------------------------------------------------------------------------------------ 5 active set

func check_active(w: WorldState, label: String) -> bool:
	var want: PackedInt32Array = brute_active(w)
	var got: PackedInt32Array = sorted_copy(w.active_tiles)
	var flag_ok: bool = true
	var flags: int = 0
	for i: int in w.tile_count():
		flags += w.active_flag[i]
	flag_ok = flags == w.active_tiles.size()
	var dup_free: bool = true
	for k: int in range(1, got.size()):
		if got[k] == got[k - 1]:
			dup_free = false
	var ok: bool = got == want and flag_ok and dup_free
	if not ok:
		print("ACTIVE MISMATCH %s: got %d want %d flags %d dup_free %s" % [label, got.size(), want.size(), flags, str(dup_free)])
	return ok

func t_active() -> void:
	var w: WorldState = fresh()
	var gs: GrowthSim = GrowthSim.new(w, sim_tun)
	var play: PlayState = PlayState.new(w, play_tun, sim_tun, TILE, [Vector2(0, 0)])
	var site: Vector2i = find_square(w, 0, 14, region_def.start_tile)
	var checks: Array = []
	checks.append(["initial", check_active(w, "initial"), w.active_tiles.size()])
	play.seeds = 40
	for k: int in 6:
		play.land_seed(center_of(site) + Vector2((k % 3) * 20 - 20, (k / 3) * 20 - 10))
	checks.append(["after_seed", check_active(w, "after_seed"), w.active_tiles.size()])
	play.land_water(center_of(site))
	play.land_water(center_of(site) + Vector2(20, 0))
	play.land_water(center_of(site) + Vector2(60, 60))  # wets tiles with no plant at all
	checks.append(["after_water", check_active(w, "after_water"), w.active_tiles.size()])
	var visited_ok: bool = true
	var outside_ok: bool = true
	for t: int in 300:
		var n_before: int = w.active_tiles.size()
		var snap_stage: PackedByteArray = w.stage.duplicate()
		var snap_g: PackedInt32Array = w.growth.duplicate()
		var snap_m: PackedByteArray = w.moisture.duplicate()
		var in_set: PackedByteArray = w.active_flag.duplicate()
		gs.tick()
		if gs.last_visited != n_before:
			visited_ok = false
		if t % 20 == 0 or t == 299:
			# tiles that were not active must be untouched
			for i: int in w.tile_count():
				if in_set[i] == 0 and (snap_stage[i] != w.stage[i] or snap_g[i] != w.growth[i] or snap_m[i] != w.moisture[i]):
					outside_ok = false
			checks.append(["tick%d" % t, check_active(w, "tick%d" % t), w.active_tiles.size()])
	var all_ok: bool = true
	for c: Array in checks:
		all_ok = all_ok and bool(c[1])
	rec("5.active_equals_brute", "active set (growing or moisture>0) equals a full-map brute force and is duplicate free at planting, watering and every 20 ticks of a 300-tick run", all_ok, str(checks))
	rec("5.visited_only_active", "a tick visits exactly the active tiles and changes nothing outside the set (visited counts match, full diff of stage/growth/moisture)", visited_ok and outside_ok, "visited_ok=%s outside_unchanged=%s" % [str(visited_ok), str(outside_ok)])
	rec("5.drained", "after everything matured and dried the active set is empty", w.active_tiles.size() == 0 and brute_active(w).size() == 0, "active=%d" % w.active_tiles.size())
	# idle tick is light and visits nothing
	var t0: int = Time.get_ticks_usec()
	for k: int in 1000:
		gs.tick()
	var per: float = float(Time.get_ticks_usec() - t0) / 1000.0
	observations["idle_tick_us"] = per
	rec("5.idle_light", "with nothing growing a tick visits 0 tiles and costs well under 0.1 ms (1000 ticks measured)", gs.last_visited == 0 and per < 100.0, "visited=%d, %.2f us/tick" % [gs.last_visited, per])
	# rebuild_derived equivalence after save / load (set equality)
	var w2: WorldState = WorldState.from_dict(w.to_dict(), w.terrain_defs)
	rec("5.rebuild", "from_dict rebuilds the same active set and counts as brute force", w2 != null and check_active(w2, "restored") and w2.mature_count == w.mature_count and w2.greened_count == w.greened_count, "mature=%d/%d" % [w2.mature_count if w2 != null else -1, w.mature_count])

# ------------------------------------------------------------------------------------------ moisture API

func t_moisture() -> void:
	var w: WorldState = fresh()
	var site: Vector2i = find_square(w, 0, 6, region_def.start_tile)
	var p: Vector2 = center_of(site)
	var play: PlayState = PlayState.new(w, play_tun, sim_tun, TILE, [Vector2(0, 0)])
	var seq: Array = []
	for k: int in 5:
		play.land_water(p)
		seq.append(w.moisture[site.y * w.width + site.x])
	var mx: int = 0
	for i: int in w.tile_count():
		mx = maxi(mx, w.moisture[i])
	rec("moist.cap", "repeated water landing adds 40 then caps at 100 (40,80,100,100,100), no tile above 100 anywhere", seq == [40, 80, 100, 100, 100] and mx == 100, "seq=%s max=%d" % [str(seq), mx])
	# water at the lake edge: no non-target tile gets moisture
	var water_t: Vector2i = Vector2i(-1, -1)
	for y: int in range(w.height):
		for x: int in range(w.width):
			if w.terrain[y * w.width + x] == 3 and x + 1 < w.width and w.target[y * w.width + x + 1] == 1:
				water_t = Vector2i(x, y)
				break
		if water_t.x >= 0:
			break
	play.land_water(center_of(water_t))
	play.land_water(center_of(water_t) + Vector2(3, 0))
	var nt_wet: int = 0
	for i: int in w.tile_count():
		if w.target[i] == 0 and w.moisture[i] != 0:
			nt_wet += 1
	var near_wet: int = w.moisture[water_t.y * w.width + water_t.x + 1]
	rec("moist.nontarget", "water landed at the lake edge wets neighbouring target tiles (>0) but no non-target tile (water, building)", nt_wet == 0 and near_wet > 0, "non-target wet=%d east target moisture=%d" % [nt_wet, near_wet])
	# active set stays consistent with the set_moisture entry (water on bare ground)
	rec("moist.active_on_bare", "bare ground made wet joins the active set", check_active(w, "moist"), "active=%d" % w.active_tiles.size())
	# 50 s dry-out: 100 -> 0 in exactly 100 ticks
	var gs: GrowthSim = GrowthSim.new(w, sim_tun)
	var idx: int = site.y * w.width + site.x
	var at99: int = -1
	var at100: int = -1
	for k: int in 120:
		gs.tick()
		if at99 < 0 and w.moisture[idx] == 1:
			at99 = k + 1
		if at100 < 0 and w.moisture[idx] == 0:
			at100 = k + 1
	rec("moist.rate", "moisture 100 reaches 0 after exactly 100 ticks = 50 s (2 per second) and stays 0", at99 == 99 and at100 == 100 and w.moisture[idx] == 0, "moisture 1 at tick %d, 0 at tick %d" % [at99, at100])

# ------------------------------------------------------------------------------------------ 6 gather / stats / positions

func t_gather() -> void:
	var w: WorldState = fresh_clean()
	var pr: PlantProducer = PlantProducer.new(w, play_tun, TILE)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 424242
	# random mature layout: blobs and speckles over a 120 x 120 tile window, plus map edges
	var targets: PackedInt32Array = PackedInt32Array()
	for i: int in w.tile_count():
		if w.target[i] == 1:
			targets.append(i)
	for k: int in 12000:
		var i: int = targets[rng.randi_range(0, targets.size() - 1)]
		w.set_stage(i, 4)
	var bad: int = 0
	var trials: int = 120
	var diag: String = ""
	var centers: Array[Vector2] = []
	for k: int in trials:
		var c: Vector2 = Vector2(rng.randf_range(0.0, 2048.0), rng.randf_range(0.0, 2048.0))
		if k < 8:
			c = [Vector2(0.3, 0.3), Vector2(2047.7, 2047.7), Vector2(0.3, 2047.7), Vector2(1024.3, 0.3), Vector2(63.9, 63.9), Vector2(64.1, 64.1), Vector2(130.7, 1000.2), Vector2(2000.2, 900.4)][k]
		centers.append(c)
	# densify near the first centers so counts are not zero
	for c: Vector2 in centers:
		for k: int in 150:
			var q: Vector2 = c + Vector2(rng.randf_range(-170.0, 170.0), rng.randf_range(-170.0, 170.0))
			if q.x >= 0 and q.y >= 0 and q.x < 2048 and q.y < 2048:
				var i2: int = int(q.y / TILE) * w.width + int(q.x / TILE)
				if w.target[i2] == 1:
					w.set_stage(i2, 4)
	var nonzero: int = 0
	for c: Vector2 in centers:
		var got: int = pr.gather(c, 160.0)
		var want: int = brute_count_circle(w, c, 160.0)
		if got != want:
			bad += 1
			diag = "centre %s got %d want %d" % [str(c), got, want]
		if want > 0:
			nonzero += 1
	rec("6.gather_brute", "mature-tile count around the player equals a brute force (tile centre within 160 px) for %d random/edge centres" % trials, bad == 0 and nonzero > 80, "mismatches=%d nonzero=%d %s" % [bad, nonzero, diag])
	# chunk counts consistent with a full recount
	var chunk_total: int = 0
	for v: int in w.mature_chunk_count:
		chunk_total += v
	rec("6.chunk_counts", "per-chunk mature counts sum to the global count and a full recount", chunk_total == w.mature_count and w.recount_mature() == w.mature_count, "chunks=%d global=%d recount=%d" % [chunk_total, w.mature_count, w.recount_mature()])
	# tile_at enumerates exactly the brute-force set
	var c0: Vector2 = centers[20]
	var n0: int = pr.gather(c0, 160.0)
	var seen: Dictionary = {}
	var all_mature_in: bool = true
	for k: int in n0:
		var t: int = pr.tile_at(k)
		seen[t] = true
		var ctr: Vector2 = Vector2((t % w.width + 0.5) * TILE, (t / w.width + 0.5) * TILE)
		if w.stage[t] != 4 or ctr.distance_to(c0) > 160.0:
			all_mature_in = false
	rec("6.tile_at", "tile_at(0..n-1) lists distinct mature tiles inside the circle only", seen.size() == n0 and all_mature_in and n0 > 0, "n=%d distinct=%d" % [n0, seen.size()])

func drop_count(world: WorldState, producer: PlantProducer, play: PlayTuning, center: Vector2, ticks: int, want_positions: bool = false) -> Dictionary:
	var pk: GroundPickups = GroundPickups.new(24, 60.0, 20, 45.0)
	var total: int = 0
	var max_tick: int = 0
	var bad_pos: int = 0
	var bad_owner: int = 0
	for t: int in ticks:
		pk.items.clear()
		var d: int = producer.produce(pk, center)
		total += d
		max_tick = maxi(max_tick, d)
		for it: Dictionary in pk.items:
			var tx: int = floori(float(it["x"]) / TILE)
			var ty: int = floori(float(it["y"]) / TILE)
			var ti: int = ty * world.width + tx
			var ctr: Vector2 = Vector2((tx + 0.5) * TILE, (ty + 0.5) * TILE)
			if tx < 0 or ty < 0 or tx >= world.width or ty >= world.height or world.stage[ti] != 4 or ctr.distance_to(center) > 160.0:
				bad_pos += 1
			if int(it["owner"]) != GroundPickups.PLANT_OWNER_BASE + ti:
				bad_owner += 1
	return {"total": total, "max_tick": max_tick, "bad_pos": bad_pos, "bad_owner": bad_owner}

func t_stats() -> void:
	var w0: WorldState = fresh_clean()
	var pr0: PlantProducer = PlantProducer.new(w0, play_tun, TILE)
	var far: Vector2 = Vector2(1500, 1500)
	var d0: Dictionary = drop_count(w0, pr0, play_tun, far, 2000)
	rec("7.none_when_no_mature", "with no mature tile anywhere (safe zone cleared) 2000 production ticks drop nothing", w0.mature_count == 0 and d0["total"] == 0, "mature=%d total=%d" % [w0.mature_count, d0["total"]])
	# mature plants only far away (outside 160 px) produce nothing near the player
	var site: Vector2i = find_square(w0, 0, 12, region_def.start_tile)
	var player: Vector2 = center_of(site) + Vector2(0.37, 0.21)
	for dy: int in range(-6, 7):
		for dx: int in range(-6, 7):
			var fi: int = (site.y + dy + 70) * w0.width + site.x + dx
			if w0.can_plant(fi):
				w0.set_stage(fi, 4)
	var d_far: Dictionary = drop_count(w0, pr0, play_tun, player, 1500)
	rec("7.none_outside_circle", "mature tiles all 280+ px away from the player produce nothing for the player (1500 ticks)", w0.mature_count > 0 and d_far["total"] == 0, "mature=%d total=%d" % [w0.mature_count, d_far["total"]])
	# cluster counts N = 40, 160, 400 within the circle
	var results_n: Dictionary = {}
	var stat_ok: bool = true
	var obs: PackedStringArray = PackedStringArray()
	for n: int in [40, 160, 400]:
		var w: WorldState = fresh_clean()
		var pr: PlantProducer = PlantProducer.new(w, play_tun, TILE)
		var s2: Vector2i = find_square(w, 0, 12, region_def.start_tile)
		var cnt: int = 0
		for dy: int in range(-12, 13):
			for dx: int in range(-12, 13):
				if cnt < n and w.can_plant((s2.y + dy) * w.width + s2.x + dx):
					w.set_stage((s2.y + dy) * w.width + s2.x + dx, 4)
					cnt += 1
		var pp: Vector2 = center_of(s2)
		var ticks: int = 6000
		var d: Dictionary = drop_count(w, pr, play_tun, pp, ticks)
		# spec-level expectation: rate 0.00125 per tile per second, tick = 2 s -> N * 0.0025 per tick
		var lam: float = float(n) * 0.00125 * 2.0
		var mean_exp: float = lam * ticks
		var frac: float = fposmod(lam, 1.0)
		var sigma: float = sqrt(maxf(float(ticks) * frac * (1.0 - frac), 1.0))
		var within: bool = absf(float(d["total"]) - mean_exp) <= 5.0 * sigma + 1.0
		stat_ok = stat_ok and within and d["bad_pos"] == 0 and d["bad_owner"] == 0
		results_n[n] = d["total"]
		obs.append("N=%d mature=%d drops=%d expected=%.0f (+-%.1f) bad_pos=%d bad_owner=%d" % [n, w.mature_count, d["total"], mean_exp, 5.0 * sigma, d["bad_pos"], d["bad_owner"]])
	rec("7.expectation", "drops over 6000 ticks match N * 0.00125/s * 2 s * ticks (5 sigma) for N = 40, 160, 400, all on mature tiles inside the circle with the right owner id", stat_ok, "; ".join(obs))
	rec("7.more_mature_more_drops", "more mature tiles around give strictly more fruits (40 < 160 < 400)", results_n[40] < results_n[160] and results_n[160] < results_n[400], str(results_n))

func t_positions() -> void:
	# irregular layout straddling the circle edge: drops must lie on mature tiles inside the circle only
	var w: WorldState = fresh_clean()
	var pr: PlantProducer = PlantProducer.new(w, play_tun, TILE)
	var site: Vector2i = find_square(w, 0, 12, region_def.start_tile)
	var player: Vector2 = center_of(site) + Vector2(1.3, -0.7)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 9
	var inside: int = 0
	var outside: int = 0
	for k: int in 9000:
		var q: Vector2 = player + Vector2(rng.randf_range(-190.0, 190.0), rng.randf_range(-190.0, 190.0))
		var ti: int = int(q.y / TILE) * w.width + int(q.x / TILE)
		if q.x >= 0 and q.y >= 0 and q.x < 2048 and q.y < 2048 and w.target[ti] == 1 and w.stage[ti] != 4:
			w.set_stage(ti, 4)
			if Vector2((ti % w.width + 0.5) * TILE, (ti / w.width + 0.5) * TILE).distance_to(player) <= 160.0:
				inside += 1
			else:
				outside += 1
	var d: Dictionary = drop_count(w, pr, play_tun, player, 3000)
	rec("7.positions", "layout with %d mature tiles inside and %d outside the circle: %d drops, none off a mature tile, none outside the circle, owner ids = base + tile" % [inside, outside, d["total"]], inside > 500 and outside > 100 and d["total"] > 500 and d["bad_pos"] == 0 and d["bad_owner"] == 0, "drops=%d bad_pos=%d bad_owner=%d" % [d["total"], d["bad_pos"], d["bad_owner"]])
	# all-map mature: per-tick maximum 3
	var wall: WorldState = fresh()
	wall.debug_fill_stage(Rect2i(0, 0, wall.width, wall.height), 4)
	var prall: PlantProducer = PlantProducer.new(wall, play_tun, TILE)
	var dall: Dictionary = drop_count(wall, prall, play_tun, Vector2(1024, 1024), 600)
	rec("7.max_per_tick", "with the whole map mature (expectation about 12/tick) a tick never drops more than 3, and 3 on every tick when the pool is empty", dall["max_tick"] == 3 and dall["total"] == 1800 and dall["bad_pos"] == 0, "max=%d total=%d (600 ticks) bad_pos=%d" % [dall["max_tick"], dall["total"], dall["bad_pos"]])

# ------------------------------------------------------------------------------------------ caps, lifetime, source reserve

func mature_field(w: WorldState, count: int) -> Vector2:
	var s2: Vector2i = find_square(w, 0, 12, region_def.start_tile)
	var cnt: int = 0
	for dy: int in range(-12, 13):
		for dx: int in range(-12, 13):
			if cnt < count and w.can_plant((s2.y + dy) * w.width + s2.x + dx):
				w.set_stage((s2.y + dy) * w.width + s2.x + dx, 4)
				cnt += 1
	return center_of(s2)

func t_caps() -> void:
	var w: WorldState = fresh_clean()
	var pp: Vector2 = mature_field(w, 600)
	var src_pos: Vector2 = pp + Vector2(200, 100)  # well outside the production circle and the collect radius
	var play: PlayState = PlayState.new(w, play_tun, sim_tun, TILE, [src_pos])
	play.seeds = play_tun.seed_max  # a full pouch refuses pickups, so fruits stay on the ground
	var dt: float = 1.0 / 60.0
	var max_plant: int = 0
	var max_total: int = 0
	var max_age_plant: float = 0.0
	var over_tile: int = 0
	var both_full: bool = false
	var t_first_full: float = -1.0
	var max_src: int = 0
	var birth: Dictionary = {}
	var life_bad: int = 0
	var seen_expire: int = 0
	var steps: int = 120 * 60
	for s: int in steps:
		play.advance(dt, pp)
		var np: int = play.pickups.count_plant_owned()
		max_plant = maxi(max_plant, np)
		max_total = maxi(max_total, play.pickups.count())
		var per_tile: Dictionary = {}
		for it: Dictionary in play.pickups.items:
			var o: int = int(it["owner"])
			if o >= GroundPickups.PLANT_OWNER_BASE:
				max_age_plant = maxf(max_age_plant, float(it["age"]))
				per_tile[o] = int(per_tile.get(o, 0)) + 1
				if float(it["age"]) > 45.0 + 0.02:
					life_bad += 1
		for o: int in per_tile:
			if per_tile[o] > 1:
				over_tile += 1
		max_src = maxi(max_src, play.pickups.count_owned(1))
		if np == 20 and t_first_full < 0.0:
			t_first_full = play.elapsed
		if np == 20 and play.pickups.count_owned(1) == 3:
			both_full = true
	observations["caps_run"] = {"max_plant": max_plant, "max_total": max_total, "max_age_plant": max_age_plant, "t_first_full": t_first_full, "max_src": max_src}
	rec("8.plant_cap", "plant fruits on the ground never exceed 20 and do reach 20 (production 3 per 2 s with a full pouch for 120 s)", max_plant == 20, "max plant fruits=%d first full at %.2f s" % [max_plant, t_first_full])
	rec("8.total_cap", "all fruits on the ground never exceed 24", max_total <= 24, "max total=%d" % max_total)
	rec("8.tile_cap", "no tile ever holds more than 1 of its own fruits", over_tile == 0, "violations=%d" % over_tile)
	rec("8.lifetime", "a plant fruit lives 45 s: oldest observed age is within [44.9, 45.0+one step] and none older", max_age_plant >= 44.9 and life_bad == 0 and max_age_plant <= 45.0 + 0.02, "max age=%.3f over-limit steps=%d" % [max_age_plant, life_bad])
	rec("8.source_reserved", "while 20 plant fruits lie on the ground the seed source still gets its 3 fruits in the remaining slots (total 23 <= 24)", both_full and max_src == 3, "both full simultaneously=%s max source fruits=%d" % [str(both_full), max_src])
	# plants first, then the source: pre-fill 20 plant fruits and run the source from zero
	var w2: WorldState = fresh_clean()
	var play2: PlayState = PlayState.new(w2, play_tun, sim_tun, TILE, [Vector2(600, 600)])
	play2.seeds = play_tun.seed_max
	var far_player: Vector2 = Vector2(1500, 1500)
	var spawned: int = 0
	for k: int in 40:
		if play2.pickups.spawn(GroundPickups.KIND_SEED_FRUIT, Vector2(1200 + k, 1200), GroundPickups.PLANT_OWNER_BASE + 5000 + k):
			spawned += 1
	var refused21: bool = not play2.pickups.spawn(GroundPickups.KIND_SEED_FRUIT, Vector2(1300, 1300), GroundPickups.PLANT_OWNER_BASE + 9999)
	for s: int in 60 * 30:
		play2.advance(dt, far_player)
	var src_n: int = play2.pickups.count_owned(1)
	rec("8.recover_slots", "with 20 plant fruits already on the ground a 21st plant fruit is refused, and the source still produces its 3 fruits (full 24 pool never starves it)", spawned == 20 and refused21 and src_n == 3 and play2.pickups.count() <= 24, "plant spawned=%d refused 21st=%s source fruits=%d total=%d" % [spawned, str(refused21), src_n, play2.pickups.count()])
	# zero seeds recovery: stand at the source with 0 seeds and a full plant pool elsewhere
	var w3: WorldState = fresh_clean()
	var play3: PlayState = PlayState.new(w3, play_tun, sim_tun, TILE, [Vector2(600, 600)])
	play3.seeds = 0
	for k: int in 40:
		play3.pickups.spawn(GroundPickups.KIND_SEED_FRUIT, Vector2(1200 + k, 1200), GroundPickups.PLANT_OWNER_BASE + 5000 + k)
	var got_seeds: int = 0
	for s: int in 60 * 120:
		play3.advance(dt, Vector2(600, 600))
		got_seeds = maxi(got_seeds, play3.seeds)
	rec("8.zero_seed_recovery", "0 seeds, plant pool full elsewhere, player at the source: seeds come back from source fruits within 120 s", got_seeds > 0 and play3.pickups.count_plant_owned() <= 20, "max seeds=%d plant fruits=%d" % [got_seeds, play3.pickups.count_plant_owned()])
	# collection of plant fruits by the player
	var w4: WorldState = fresh_clean()
	var play4: PlayState = PlayState.new(w4, play_tun, sim_tun, TILE, [Vector2(600, 600)])
	play4.seeds = 3
	play4.pickups.spawn(GroundPickups.KIND_SEED_FRUIT, Vector2(1000, 1000), GroundPickups.PLANT_OWNER_BASE + 12345)
	play4.advance(1.0 / 60.0, Vector2(1005, 1000))
	rec("8.collect_plant_fruit", "a plant fruit within 12 px is collected automatically (+1 seed), one 20 px away is not", play4.seeds == 4 and play4.pickups.count() == 0, "seeds=%d" % play4.seeds)
	var play5: PlayState = PlayState.new(w4, play_tun, sim_tun, TILE, [Vector2(600, 600)])
	play5.seeds = 3
	play5.pickups.spawn(GroundPickups.KIND_SEED_FRUIT, Vector2(1000, 1000), GroundPickups.PLANT_OWNER_BASE + 12345)
	play5.advance(1.0 / 60.0, Vector2(1020, 1000))
	rec("8.collect_far", "a plant fruit 20 px away stays on the ground", play5.seeds == 3 and play5.pickups.count() == 1, "seeds=%d" % play5.seeds)

# ------------------------------------------------------------------------------------------ 8 frame rate

func build_run(dt: float, snapshots: Array) -> Dictionary:
	var w: WorldState = fresh_clean()
	var pp: Vector2 = mature_field(w, 300)
	var gs: GrowthSim = GrowthSim.new(w, sim_tun)
	var clock: SimClock = SimClock.new()
	clock.configure(sim_tun)
	clock.growth_ticked.connect(func(_n: int) -> void: gs.tick())
	var play: PlayState = PlayState.new(w, play_tun, sim_tun, TILE, [pp + Vector2(250, 0)])
	play.seeds = play_tun.seed_max
	# seeds and water at game time zero
	var site2: Vector2i = find_square(w, 0, 6, region_def.start_tile + Vector2i(40, 0))
	var sp: Vector2 = center_of(site2)
	for k: int in 3:
		play.land_seed(sp + Vector2(k * 12 - 12, 0))
	play.land_water(sp)
	play.land_water(sp + Vector2(12, 0))
	var out: Array = []
	var steps_done: int = 0
	for snap: float in snapshots:
		var target_steps: int = roundi(snap / dt)
		while steps_done < target_steps:
			clock.advance(dt)
			play.advance(dt, pp)
			steps_done += 1
		var plant_items: Array = []
		for it: Dictionary in play.pickups.items:
			plant_items.append([snappedf(float(it["x"]), 0.0001), snappedf(float(it["y"]), 0.0001), int(it["owner"])])
		plant_items.sort()
		out.append({
			"snap": snap, "growth_ticks": clock.growth_ticks, "spread_ticks": clock.spread_ticks, "prod_ticks": play.production_ticks,
			"produced": play.producer.total_produced, "hash": hash_world(w), "greened": w.greened_count, "mature": w.mature_count,
			"items": plant_items, "n_items": play.pickups.count(),
		})
	return {"snaps": out}

func t_framerate() -> void:
	var snaps: Array = [20.0, 60.0, 100.0, 100.5]
	var ref: Dictionary = {}
	var all_same: bool = true
	var obs: PackedStringArray = PackedStringArray()
	for hz: int in [60, 30, 144]:
		var r: Dictionary = build_run(1.0 / float(hz), snaps)
		if hz == 60:
			ref = r
		var same: bool = true
		for i: int in snaps.size():
			var a: Dictionary = (ref["snaps"] as Array)[i]
			var b: Dictionary = (r["snaps"] as Array)[i]
			if a != b:
				same = false
				print("DIFF hz=%d snap=%s\n a=%s\n b=%s" % [hz, str(snaps[i]), str(a).substr(0, 400), str(b).substr(0, 400)])
		all_same = all_same and same
		var last: Dictionary = (r["snaps"] as Array)[3]
		obs.append("%dHz: growth_ticks=%d prod_ticks=%d produced=%d mature=%d greened=%d items=%d same_as_60=%s" % [hz, last["growth_ticks"], last["prod_ticks"], last["produced"], last["mature"], last["greened"], last["n_items"], str(same)])
	var rr: Dictionary = (ref["snaps"] as Array)[3]
	rec("9.framerate_logic", "at 20/60/100/100.5 s of game time the clocks, stages, growth, moisture, greening, production counts and fruit positions are identical at 30, 60 and 144 Hz steps", all_same and rr["growth_ticks"] == 201 and rr["prod_ticks"] == 50 and rr["produced"] > 0, "; ".join(obs))
	# hitch guard: one huge step adds at most 0.25 s
	var clock: SimClock = SimClock.new()
	clock.configure(sim_tun)
	clock.advance(30.0)
	var w: WorldState = fresh_clean()
	var play: PlayState = PlayState.new(w, play_tun, sim_tun, TILE, [Vector2(10, 10)])
	play.advance(30.0, Vector2(500, 500))
	rec("9.hitch", "a 30 s frame advances the clock and the play state by at most 0.25 s (no burst)", absf(clock.elapsed - 0.25) < 1e-9 and absf(play.elapsed - 0.25) < 1e-9, "clock=%.3f play=%.3f" % [clock.elapsed, play.elapsed])

# ------------------------------------------------------------------------------------------ 10 save

func t_save() -> void:
	var w: WorldState = fresh_clean()
	var pp: Vector2 = mature_field(w, 300)
	var gs: GrowthSim = GrowthSim.new(w, sim_tun)
	var clock: SimClock = SimClock.new()
	clock.configure(sim_tun)
	clock.growth_ticked.connect(func(_n: int) -> void: gs.tick())
	var play: PlayState = PlayState.new(w, play_tun, sim_tun, TILE, [pp + Vector2(250, 0)])
	play.seeds = 10
	var site2: Vector2i = find_square(w, 0, 6, region_def.start_tile + Vector2i(40, 0))
	var sp: Vector2 = center_of(site2)
	for k: int in 3:
		play.land_seed(sp + Vector2(k * 12 - 12, 0))
	play.land_water(sp)
	var dt: float = 1.0 / 60.0
	for s: int in 60 * 33:  # 33 s: mid-growth, fruits on the ground, uneven phase
		clock.advance(dt)
		play.advance(dt, pp)
	var snap_world: Dictionary = JSON.parse_string(JSON.stringify(w.to_dict()))
	var snap_clock: Dictionary = JSON.parse_string(JSON.stringify(clock.to_dict()))
	var snap_play: Dictionary = JSON.parse_string(JSON.stringify(play.to_dict()))
	var pre_stage_hash: String = hash_world(w)
	for s: int in 60 * 70:
		clock.advance(dt)
		play.advance(dt, pp)
	var final_a: String = hash_world(w)
	var items_a: Array = play.pickups.to_dict()["items"]
	var prod_a: Dictionary = play.producer.to_dict()
	# restore into fresh objects
	var w2: WorldState = WorldState.from_dict(snap_world, w.terrain_defs)
	var gs2: GrowthSim = GrowthSim.new(w2, sim_tun)
	var clock2: SimClock = SimClock.new()
	clock2.configure(sim_tun)
	clock2.load_dict(snap_clock)
	clock2.growth_ticked.connect(func(_n: int) -> void: gs2.tick())
	var play2: PlayState = PlayState.new(w2, play_tun, sim_tun, TILE, [pp + Vector2(250, 0)])
	var loaded: bool = play2.load_dict(snap_play)
	rec("10.restore_equal_now", "after to_dict -> JSON -> from_dict the stage/growth/moisture arrays, counts and active set equal the saved state", w2 != null and hash_world(w2) == pre_stage_hash and w2.counters_consistent() and check_active(w2, "restored") and loaded, "loaded=%s hash=%s vs %s" % [str(loaded), hash_world(w2), pre_stage_hash])
	for s: int in 60 * 70:
		clock2.advance(dt)
		play2.advance(dt, pp)
	var items_b: Array = play2.pickups.to_dict()["items"]
	var prod_b: Dictionary = play2.producer.to_dict()
	rec("10.continue_identical", "continuing 70 s after the restore gives the identical world hash, clock ticks, production counters and fruit list as the uninterrupted run", hash_world(w2) == final_a and clock2.growth_ticks == clock.growth_ticks and play2.production_ticks == play.production_ticks and prod_a == prod_b and str(items_a) == str(items_b) and play2.seeds == play.seeds, "hash %s vs %s; growth_ticks %d/%d; prod %s/%s; items %d/%d" % [hash_world(w2), final_a, clock2.growth_ticks, clock.growth_ticks, str(prod_a), str(prod_b), items_a.size(), items_b.size()])

# ------------------------------------------------------------------------------------------ 11 perf

func t_perf() -> void:
	var w: WorldState = fresh()
	var gs: GrowthSim = GrowthSim.new(w, sim_tun)
	var tiles: PackedInt32Array = plantable_list(w, 10000)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 5
	for i: int in tiles:
		w.set_stage(i, 1)
		w.set_moisture(i, rng.randi_range(0, 100))
	var times: PackedFloat32Array = PackedFloat32Array()
	for k: int in 30:
		var t0: int = Time.get_ticks_usec()
		gs.tick()
		times.append(float(Time.get_ticks_usec() - t0) / 1000.0)
	var avg: float = 0.0
	var mx: float = 0.0
	for t: float in times:
		avg += t
		mx = maxf(mx, t)
	avg /= times.size()
	observations["perf_10k_growing_ms"] = {"avg": avg, "max": mx, "visited": gs.last_visited}
	rec("11.perf_10k", "one growth tick with 10000 growing tiles (random moisture) averages under 16 ms (30 ticks)", avg < 16.0, "avg %.2f ms max %.2f ms visited=%d" % [avg, mx, gs.last_visited])
	# worst case: every tile changes stage in the same tick
	for i: int in tiles:
		w.growth[i] = 39500 if w.stage[i] == 1 else w.growth[i]
	for i: int in tiles:
		if w.stage[i] != 1:
			w.set_stage(i, 1)
			w.growth[i] = 39500
	var t1: int = Time.get_ticks_usec()
	gs.tick()
	var worst: float = float(Time.get_ticks_usec() - t1) / 1000.0
	observations["perf_10k_all_transition_ms"] = worst
	rec("11.perf_10k_transition", "worst-case tick: all 10000 tiles change stage in one tick, under 16 ms", worst < 16.0 and gs.last_stage_changes >= 9000, "%.2f ms, stage changes=%d" % [worst, gs.last_stage_changes])
	# stress: everything wet and growing on the whole target map
	var w2: WorldState = fresh()
	var gs2: GrowthSim = GrowthSim.new(w2, sim_tun)
	var nt: int = 0
	for i: int in w2.tile_count():
		if w2.can_plant(i):
			w2.set_stage(i, 1)
			w2.set_moisture(i, 60)
			nt += 1
	var t2: int = Time.get_ticks_usec()
	gs2.tick()
	var full: float = float(Time.get_ticks_usec() - t2) / 1000.0
	observations["perf_full_map_growing_ms"] = full
	observations["perf_full_map_tiles"] = nt
	print("INFO full map growing %d tiles: %.2f ms per tick (informational)" % [nt, full])
	rec("11.perf_full_info", "informational: tick with the entire plantable map (%d tiles) growing and wet" % nt, true, "%.2f ms" % full)
	# production tick with the whole map mature
	var w3: WorldState = fresh()
	w3.debug_fill_stage(Rect2i(0, 0, w3.width, w3.height), 4)
	var play: PlayState = PlayState.new(w3, play_tun, sim_tun, TILE, [Vector2(40, 40)])
	play.seeds = play_tun.seed_max
	var pt: PackedFloat32Array = PackedFloat32Array()
	var adv: PackedFloat32Array = PackedFloat32Array()
	for k: int in 40:
		var a0: int = Time.get_ticks_usec()
		play.advance(0.25, Vector2(1024.5, 1024.5))  # a production tick every 8 calls
		var el: float = float(Time.get_ticks_usec() - a0) / 1000.0
		adv.append(el)
	var pr: PlantProducer = PlantProducer.new(w3, play_tun, TILE)
	var pk: GroundPickups = GroundPickups.new(24, 60.0, 20, 45.0)
	for k: int in 60:
		pk.items.clear()
		var p0: int = Time.get_ticks_usec()
		pr.produce(pk, Vector2(1024.5 + k, 1024.5))
		pt.append(float(Time.get_ticks_usec() - p0) / 1000.0)
	var pavg: float = 0.0
	var pmax: float = 0.0
	for v: float in pt:
		pavg += v
		pmax = maxf(pmax, v)
	pavg /= pt.size()
	var amax: float = 0.0
	for v: float in adv:
		amax = maxf(amax, v)
	observations["perf_produce_all_mature_ms"] = {"avg": pavg, "max": pmax, "play_advance_max": amax, "mature": w3.mature_count}
	rec("11.perf_produce", "production tick with the entire map mature (%d tiles; player in the middle) under 16 ms; also the worst PlayState.advance call" % w3.mature_count, pmax < 16.0 and amax < 16.0, "produce avg %.3f ms max %.3f ms; PlayState.advance max %.3f ms" % [pavg, pmax, amax])

# ------------------------------------------------------------------------------------------ fast path vs hook path, removal

func t_paths() -> void:
	# the hot loop (no provider) and the Callable path (provider returning 1.0) must give identical growth for every moisture / fertility
	var w1: WorldState = fresh()
	var w2: WorldState = fresh()
	var g1: GrowthSim = GrowthSim.new(w1, sim_tun)
	var g2: GrowthSim = GrowthSim.new(w2, sim_tun)
	g2.sunlight_provider = func(_i: int) -> float: return 1.0
	var tiles: PackedInt32Array = plantable_list(w1, 303)
	var n: int = 0
	for m: int in range(0, 101, 5):
		for f: int in [0, 37, 100]:
			var i: int = tiles[n]
			n += 1
			for w: WorldState in [w1, w2]:
				w.fertility[i] = f
				w.set_stage(i, 1)
				w.set_moisture(i, m)
	for k: int in 40:
		g1.tick()
		g2.tick()
	var diff: int = 0
	for k: int in n:
		if w1.growth[tiles[k]] != w2.growth[tiles[k]] or w1.stage[tiles[k]] != w2.stage[tiles[k]]:
			diff += 1
	rec("12.paths_equal", "growth is identical with and without a sunlight provider (1.0) over 63 moisture/fertility combinations, 40 ticks", diff == 0, "differing tiles=%d of %d" % [diff, n])
	# moisture above the scale (byte up to 255) must not crash or stop growth
	var w3: WorldState = fresh()
	var g3: GrowthSim = GrowthSim.new(w3, sim_tun)
	var t3: int = plantable_list(w3, 1)[0]
	w3.set_stage(t3, 1)
	w3.set_moisture(t3, 250)
	for k: int in 3:
		g3.tick()
	rec("12.moisture_over_scale", "moisture 250 (above the 100 scale, set directly) is clamped to the top factor: 3 ticks = 6000 growth", w3.growth[t3] == 6000, "growth=%d moisture=%d" % [w3.growth[t3], w3.moisture[t3]])
	# a tile emptied while active leaves the active set at the next tick
	var w4: WorldState = fresh()
	var g4: GrowthSim = GrowthSim.new(w4, sim_tun)
	var t4: int = plantable_list(w4, 1)[0]
	w4.set_stage(t4, 2)
	w4.set_stage(t4, 0)
	var in_before: bool = t4 in w4.active_tiles
	g4.tick()
	rec("12.empty_removal", "a tile cleared back to empty (stage 0, dry) drops out of the active set at the next tick (stale entry allowed for at most one tick)", not (t4 in w4.active_tiles) and w4.active_flag[t4] == 0 and w4.growth[t4] == 0, "was in set before tick=%s, after=%s" % [str(in_before), str(t4 in w4.active_tiles)])
