extends SceneTree
## Independent verification of P2-05 (green-verifier). Own fixed small map, expectations derived from the ticket / design text.
## Run: Godot --headless --path <project> --script res://tests/p2/independent/p2_05_v_logic.gd

const OUT: String = "res://evidence/p2/p2-05/independent/checks_logic.json"
var results: Array = []
var region_def: RegionDef
var base_tuning: SimTuning
var fails: int = 0

func _initialize() -> void:
	run.call_deferred()

func rec(id: String, cond: String, ok: bool, observed: Variant) -> void:
	if not ok:
		fails += 1
	results.append({"id": id, "condition": cond, "result": "PASS" if ok else "FAIL", "observed": observed})
	print("%s %s %s %s" % ["PASS" if ok else "FAIL", id, cond, str(observed)])

func tdef(key: StringName) -> TerrainDef:
	for d: TerrainDef in region_def.terrains:
		if d.key == key:
			return d
	return null

func fill(rows: Array, r: Rect2i, g: String) -> void:
	for y: int in range(r.position.y, r.end.y):
		var row: String = rows[y]
		for x: int in range(r.position.x, r.end.x):
			row = row.substr(0, x) + g + row.substr(x + 1)
		rows[y] = row

## 64 x 40. River x 30..32 (3 wide). West: 3x3 island and 1-tile island (rings 2 wide of water). East: 2x1 island,
## chamber of buildings with a 1-wide passage, large open land.
func map() -> Array:
	var rows: Array = []
	for y: int in 40:
		rows.append(".".repeat(64))
	fill(rows, Rect2i(30, 0, 3, 40), "~")
	fill(rows, Rect2i(8, 3, 7, 7), "~")
	fill(rows, Rect2i(10, 5, 3, 3), ".")
	fill(rows, Rect2i(18, 18, 5, 5), "~")
	fill(rows, Rect2i(20, 20, 1, 1), ".")
	fill(rows, Rect2i(50, 3, 6, 5), "~")
	fill(rows, Rect2i(52, 5, 2, 1), ".")
	fill(rows, Rect2i(40, 20, 21, 19), "#")
	fill(rows, Rect2i(46, 24, 13, 11), ".")
	fill(rows, Rect2i(40, 30, 6, 1), ".")
	return rows

func build(states: Array, splits: Array) -> WorldState:
	var rows: Array = map()
	var def: RegionDef = RegionDef.new()
	def.width_tiles = 64
	def.height_tiles = 40
	def.terrains = region_def.terrains
	def.sprout_seed = region_def.sprout_seed
	var img: Image = Image.create(64, 40, false, Image.FORMAT_RGB8)
	var glyph: Dictionary = {".": &"wasteland", "~": &"water", "#": &"building"}
	for y: int in 40:
		for x: int in 64:
			var c: Color = tdef(glyph[String(rows[y])[x]]).map_color
			img.set_pixel(x, y, Color8(roundi(c.r * 255.0), roundi(c.g * 255.0), roundi(c.b * 255.0)))
	var w: WorldState = RegionLoader.build_state(def, img)
	var ids: PackedByteArray = PackedByteArray()
	ids.resize(w.tile_count())
	for i: int in w.tile_count():
		var z: int = 0
		for s: int in splits:
			if i % 64 >= s:
				z += 1
		ids[i] = z
	w.set_zones(ids, PackedByteArray(states))
	return w

class Rig:
	extends RefCounted
	var world: WorldState
	var clock: SimClock = SimClock.new()
	var growth: GrowthSim
	var spread: SpreadSim
	var far: FarSeedSim
	var use_spread: bool = true
	func on_g(_i: int) -> void:
		growth.tick()
	func on_s(_i: int) -> void:
		if use_spread:
			spread.tick()
		far.tick()

func rig_of(w: WorldState, t: SimTuning, use_spread: bool = true, restore: Dictionary = {}) -> Rig:
	var r: Rig = Rig.new()
	r.world = w
	r.use_spread = use_spread
	r.clock.configure(t)
	r.growth = GrowthSim.new(w, t)
	r.spread = SpreadSim.new(w, t, restore.is_empty())
	r.far = FarSeedSim.new(w, t)
	if not restore.is_empty():
		r.clock.load_dict(restore["clock"])
		r.growth.load_dict(restore["growth"])
		r.spread.load_dict(restore["spread"])
		r.far.load_dict(restore["far"])
	r.clock.growth_ticked.connect(r.on_g)
	r.clock.spread_ticked.connect(r.on_s)
	return r

func tune(o: Dictionary) -> SimTuning:
	var t: SimTuning = base_tuning.duplicate() as SimTuning
	for k: String in o:
		t.set(k, o[k])
	return t

func zone_plants(w: WorldState, zone: int) -> int:
	var n: int = 0
	for i: int in w.tile_count():
		if w.zone_of[i] == zone and w.stage[i] != 0:
			n += 1
	return n

func zone_full(w: WorldState, zone: int) -> bool:
	for i: int in w.tile_count():
		if w.zone_of[i] == zone and w.target[i] == 1 and w.stage[i] < WorldState.GREENED_MIN_STAGE:
			return false
	return true

func sig(r: Rig) -> int:
	return hash([hash(r.world.stage), hash(r.world.growth), hash(r.world.natural), r.world.greened_count, r.clock.spread_ticks, r.clock.growth_ticks, r.far.sweep_cursor, r.far.total_sweep_planted, r.far.total_island_planted])

func run_for(r: Rig, seconds: float, dt: float = 0.25) -> void:
	var end: float = r.clock.elapsed + seconds
	while r.clock.elapsed < end - 1.0e-9:
		r.clock.advance(minf(dt, end - r.clock.elapsed))

func max_hops(f: FarSeedSim, zone: int) -> int:
	var m: int = 0
	for c: int in f.finished_comp_count():
		if f.world.zone_of[f.members[f.comp_start[c]]] == zone:
			m = maxi(m, f.component_hops_bound(c))
	return m

func run() -> void:
	region_def = load("res://data/region_01.tres") as RegionDef
	base_tuning = load("res://data/sim_tuning.tres") as SimTuning
	t_guarantee()
	t_delay_and_zones()
	t_isolated()
	t_multiplier()
	t_time()
	var f: FileAccess = FileAccess.open(ProjectSettings.globalize_path(OUT), FileAccess.WRITE)
	f.store_string(JSON.stringify(results, "  "))
	f.close()
	print("V_RESULT total=%d fails=%d" % [results.size(), fails])
	quit(1 if fails > 0 else 0)

func t_guarantee() -> void:
	for variant: Array in [["default", {}], ["slowsweep_K8_S128", {"far_sweep_seeds_per_step": 8, "far_sweep_scan_per_step": 128}]]:
		var t: SimTuning = tune(variant[1])
		# zone 0 starts stable (no plants at all), zone 1 enemies cleared at t = 30 s.
		var w: WorldState = build([2, 0], [31])
		var r: Rig = rig_of(w, t)
		run_for(r, 30.0)
		w.set_zone_state(1, WorldState.ZONE_STABLE)
		var hops: int = max_hops(r.far, 0)
		var bound1: float = r.far.completion_bound_seconds()
		var bound0: float = r.far.initial_zone_bound_seconds(hops, w.zone_target_count[0])
		var t0: float = -1.0
		var t1: float = -1.0
		while r.clock.elapsed < maxf(30.0 + bound1, bound0) + 10.0:
			r.clock.advance(0.25)
			if t0 < 0.0 and zone_full(w, 0):
				t0 = r.clock.elapsed
			if t1 < 0.0 and zone_full(w, 1):
				t1 = r.clock.elapsed
			if t0 >= 0.0 and t1 >= 0.0:
				break
		rec("G1-%s-initial" % variant[0], "initial-stable zone reaches exactly 100 (int equal) within initial_zone_bound", t0 >= 0.0 and t0 <= bound0 and w.zone_greened_count[0] == w.zone_target_count[0], {"t": t0, "bound": bound0, "hops": hops, "greened": w.zone_greened_count[0], "target": w.zone_target_count[0]})
		rec("G2-%s-cleared" % variant[0], "cleared-then-stable zone reaches exactly 100 within stable_time + completion_bound", t1 >= 0.0 and t1 <= 30.0 + bound1 and w.zone_greened_count[1] == w.zone_target_count[1], {"t": t1, "limit": 30.0 + bound1, "greened": w.zone_greened_count[1], "target": w.zone_target_count[1]})
		rec("G3-%s-counters" % variant[0], "counters equal recount", w.counters_consistent() and w.recount_greened() == w.greened_count and w.recount_zone_greened() == w.zone_greened_count and w.recount_targets() == w.target_count, {"greened": w.greened_count, "target": w.target_count})
		# sweep-only guarantee for a cleared zone (no natural spread, no island seeding)
		var merged: Dictionary = variant[1].duplicate()
		merged["far_island_period_seconds"] = 1.0e9
		var t2: SimTuning = tune(merged)
		var w2: WorldState = build([0], [])
		var r2: Rig = rig_of(w2, t2, false)
		w2.set_zone_state(0, WorldState.ZONE_STABLE)
		var b2: float = r2.far.completion_bound_seconds()
		var tt: float = -1.0
		while r2.clock.elapsed < b2 + 10.0:
			r2.clock.advance(0.25)
			if w2.greened_count == w2.target_count:
				tt = r2.clock.elapsed
				break
		rec("G4-%s-sweep-only" % variant[0], "sweep alone (no spread, no island seeding) reaches 100 within bound", tt >= 0.0 and tt <= b2, {"t": tt, "bound": b2})
		# all-initial-stable world
		var w3: WorldState = build([2, 2], [31])
		var r3: Rig = rig_of(w3, t)
		run_for(r3, 3.0)
		var h3: int = maxi(max_hops(r3.far, 0), max_hops(r3.far, 1))
		var b3: float = r3.far.initial_zone_bound_seconds(h3)
		var ta: float = -1.0
		while r3.clock.elapsed < b3 + 10.0:
			r3.clock.advance(0.25)
			if w3.greened_count == w3.target_count:
				ta = r3.clock.elapsed
				break
		rec("G5-%s-all-initial" % variant[0], "world stable from the start reaches exactly 100 within initial bound; sweep planted nothing", ta >= 0.0 and ta <= b3 and r3.far.total_sweep_planted == 0, {"t": ta, "bound": b3, "sweep_planted": r3.far.total_sweep_planted})

func t_delay_and_zones() -> void:
	var t: SimTuning = tune({"far_island_period_seconds": 1.0e9})
	var w: WorldState = build([2, 0, 1], [31, 50])
	var r: Rig = rig_of(w, t, false)
	run_for(r, 10.0)
	w.set_zone_state(1, WorldState.ZONE_STABLE)
	run_for(r, 119.0)
	var at119: int = zone_plants(w, 1)
	run_for(r, 2.0)
	var at121: int = zone_plants(w, 1)
	run_for(r, 200.0)
	rec("D1-delay", "swept zone: no seed 119 s after turning stable, seeds at 121 s", at119 == 0 and at121 > 0, {"at119": at119, "at121": at121})
	rec("D2-initial-not-swept", "initial-stable zone gets no sweep seed (island seeding and spread off)", zone_plants(w, 0) == 0 and r.far.total_sweep_planted > 0, {"zone0_plants": zone_plants(w, 0)})
	rec("D3-untouched", "clearing zone gets nothing", zone_plants(w, 2) == 0, {"zone2_plants": zone_plants(w, 2)})
	var w2: WorldState = build([0, 1], [31])
	var r2: Rig = rig_of(w2, tune({}))
	mature(w2, Rect2i(5, 25, 4, 4))
	mature(w2, Rect2i(40, 5, 3, 3))
	run_for(r2, 600.0)
	rec("D4-unstable-untouched", "unconquered and clearing zones get no far seeds", r2.far.total_sweep_planted == 0 and r2.far.total_island_planted == 0, {"sweep": r2.far.total_sweep_planted, "island": r2.far.total_island_planted})

func mature(w: WorldState, r: Rect2i) -> void:
	w.debug_fill_stage(r, WorldState.STAGE_MATURE)

func t_isolated() -> void:
	var t: SimTuning = tune({"far_sweep_period_seconds": 1.0e9})
	var w: WorldState = build([2], [])
	mature(w, Rect2i(52, 5, 1, 1))
	var r: Rig = rig_of(w, t, false)
	run_for(r, 200.0)
	var comp: PackedInt32Array = flood(w)
	var count: Dictionary = {}
	for i: int in w.tile_count():
		if w.stage[i] != 0:
			count[comp[i]] = int(count.get(comp[i], 0)) + 1
	var maxid: int = 0
	for v: int in comp:
		maxid = maxi(maxid, v)
	var ok_each: bool = true
	var bad: Array = []
	for id: int in range(1, maxid + 1):
		if int(count.get(id, 0)) != 1:
			ok_each = false
			bad.append([id, count.get(id, 0)])
	var natural_ok: bool = true
	var placed_ok: bool = true
	for i: int in w.tile_count():
		if w.stage[i] != 0:
			var island_seed: bool = i != 5 * 64 + 52
			if island_seed and w.natural[i] != 1:
				natural_ok = false
			if w.target[i] != 1 or not w.terrain_defs[w.terrain[i]].plantable:
				placed_ok = false
	rec("I1-one-seed-per-empty-component", "every independent component has exactly one plant (planted island gets none extra)", ok_each and maxid >= 4, {"components": maxid, "bad": bad})
	rec("I2-natural", "island seeds have natural=1 and sit on plantable targets", natural_ok and placed_ok, {"natural_ok": natural_ok, "placed_ok": placed_ok})
	run_for(r, 60.0)
	var grown: int = 0
	for i: int in w.tile_count():
		if w.stage[i] >= WorldState.GREENED_MIN_STAGE:
			grown += 1
	rec("I3-grow", "seeds grow to sprout1 or more", grown >= maxid, {"greened": grown, "components": maxid})

func flood(w: WorldState) -> PackedInt32Array:
	var comp: PackedInt32Array = PackedInt32Array()
	comp.resize(w.tile_count())
	var id: int = 0
	for s: int in w.tile_count():
		if comp[s] != 0 or w.target[s] == 0 or not w.terrain_defs[w.terrain[s]].plantable:
			continue
		id += 1
		comp[s] = id
		var q: Array = [s]
		while not q.is_empty():
			var i: int = q.pop_back()
			var x: int = i % 64
			var y: int = i / 64
			for dy: int in range(-2, 3):
				for dx: int in range(-2, 3):
					if dx * dx + dy * dy > 4 or x + dx < 0 or x + dx >= 64 or y + dy < 0 or y + dy >= 40:
						continue
					var o: int = (y + dy) * 64 + x + dx
					if comp[o] == 0 and w.target[o] == 1 and w.terrain_defs[w.terrain[o]].plantable:
						comp[o] = id
						q.append(o)
	return comp

func first_seed_tick(state: int, mult: float) -> int:
	var w: WorldState = build([state], [])
	var t: SimTuning = tune({"stable_spread_multiplier": mult})
	w.debug_fill_stage(Rect2i(10, 34, 1, 1), WorldState.STAGE_MATURE)
	var sp: SpreadSim = SpreadSim.new(w, t)
	for tick: int in range(1, 200):
		sp.tick()
		for i: int in w.tile_count():
			if w.stage[i] == WorldState.STAGE_SEED:
				return tick
	return -1

func t_multiplier() -> void:
	# Definition: threshold 100000, one mature neighbour rate 6000 per tick. Queued at tick 1 (progress 0), gains rate*mult per following tick.
	# 1.0 -> 17 gains -> seed at tick 18; 1.25 -> 7500 per tick -> 14 gains -> tick 15.
	var u: int = first_seed_tick(WorldState.ZONE_UNCONQUERED, 1.25)
	var s: int = first_seed_tick(WorldState.ZONE_STABLE, 1.25)
	var c: int = first_seed_tick(WorldState.ZONE_COMPLETE, 1.25)
	var s1: int = first_seed_tick(WorldState.ZONE_STABLE, 1.0)
	var cl: int = first_seed_tick(WorldState.ZONE_CLEARING, 1.25)
	rec("M1-multiplier", "unstable 17, stable/complete at 1.25 -> 14, stable at 1.0 -> 17, clearing 17 (ceil(100000/6000)=17, ceil(100000/7500)=14)", u == 17 and s == 14 and c == 14 and s1 == 17 and cl == 17, {"unconquered": u, "stable": s, "complete": c, "stable_mult1": s1, "clearing": cl})

func t_time() -> void:
	var t: SimTuning = tune({})
	var sigs: Array = []
	for dt: float in [1.0 / 30.0, 1.0 / 60.0, 1.0 / 144.0]:
		var w: WorldState = build([2, 0], [31])
		var r: Rig = rig_of(w, t)
		run_for(r, 30.0, dt)
		w.set_zone_state(1, WorldState.ZONE_STABLE)
		run_for(r, 300.0, dt)
		sigs.append(sig(r))
	rec("T1-hz", "30/60/144 Hz identical", sigs[0] == sigs[1] and sigs[1] == sigs[2], sigs)
	var w: WorldState = build([2, 0], [31])
	var r: Rig = rig_of(w, t)
	run_for(r, 20.0)
	var before: int = sig(r)
	r.clock.paused = true
	for i: int in 2000:
		r.clock.advance(0.25)
	rec("T2-pause", "clock paused: nothing changes (clock level; Esc injection not exercised here)", sig(r) == before, {})
	var all_ok: bool = true
	var details: Array = []
	for snap: float in [3.3, 31.7, 137.3, 500.1]:
		var w1: WorldState = build([2, 0], [31])
		var a: Rig = rig_of(w1, t)
		run_for(a, 30.0)
		w1.set_zone_state(1, WorldState.ZONE_STABLE)
		run_for(a, snap)
		var data: Dictionary = {}
		var wd: Dictionary = JSON.parse_string(JSON.stringify(w1.to_dict()))
		data["growth"] = JSON.parse_string(JSON.stringify(a.growth.to_dict()))
		data["spread"] = JSON.parse_string(JSON.stringify(a.spread.to_dict()))
		data["far"] = JSON.parse_string(JSON.stringify(a.far.to_dict()))
		data["clock"] = JSON.parse_string(JSON.stringify(a.clock.to_dict()))
		var w2: WorldState = WorldState.from_dict(wd, w1.terrain_defs)
		var b: Rig = rig_of(w2, t, true, data)
		var same0: bool = sig(a) == sig(b)
		run_for(a, 250.0)
		run_for(b, 250.0)
		var same1: bool = sig(a) == sig(b)
		details.append([snap, same0, same1, w2.counters_consistent()])
		all_ok = all_ok and same0 and same1 and w2.counters_consistent()
	rec("T3-save", "save/restore (JSON) then same time later is identical", all_ok, details)
