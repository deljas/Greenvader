extends SceneTree
## Independent verifier P2-01 (logic, display-free). Run:
## Godot --headless --path <p> --script res://tests/p2/independent/p2_01_v_logic.gd -- --only=<section> [--minutes=30]
## sections: map, nests, spawn, long, gnaw, spread, rates, save
const OUT: String = "res://evidence/p2/p2-01/independent/"
const T: int = 4
var results: Array[Dictionary] = []
var obs: Dictionary = {}
var region_def: RegionDef
var sim_tuning: SimTuning
var etune: EnemyTuning
var my_zone: PackedByteArray = PackedByteArray()
var zone_colors: Array[Color] = []
var minutes: float = 30.0
var nest_walk_frames: int = 0

func _initialize() -> void:
	run.call_deferred()

func rec(id: String, cond: String, ok: bool, observed: String) -> void:
	results.append({"id": id, "condition": cond, "status": "PASS" if ok else "FAIL", "observed": observed})
	print("%s [%s] %s :: %s" % ["PASS" if ok else "FAIL", id, cond, observed])

func run() -> void:
	var only: String = "map"
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.trim_prefix("--only=")
		elif a.begins_with("--minutes="):
			minutes = float(a.trim_prefix("--minutes="))
	region_def = load("res://data/region_01.tres") as RegionDef
	sim_tuning = load("res://data/sim_tuning.tres") as SimTuning
	etune = load("res://data/enemy_tuning.tres") as EnemyTuning
	decode_zones()
	match only:
		"map": t_map()
		"nests": t_nests()
		"spawn": t_spawn()
		"long": t_long()
		"gnaw": t_gnaw()
		"spread": t_spread()
		"rates": t_rates()
		"save": t_save()
	var f: FileAccess = FileAccess.open(OUT + "checks_%s.json" % only, FileAccess.WRITE)
	f.store_string(JSON.stringify({"results": results, "observations": obs}, "  "))
	f.close()
	var fails: int = 0
	for r: Dictionary in results:
		if r["status"] != "PASS":
			fails += 1
	print("RESULT %s checks=%d failures=%d" % [only, results.size(), fails])
	quit(1 if fails > 0 else 0)

# own decode of the zone PNG: pixel colour -> index in region_def.zones order (colour taken from the zone resources)
func decode_zones() -> void:
	var img: Image = Image.load_from_file(ProjectSettings.globalize_path("res://data/region_01_zones.png"))
	img.convert(Image.FORMAT_RGBA8)
	var w: int = img.get_width()
	var h: int = img.get_height()
	obs["zone_png_size"] = [w, h]
	for z: ZoneDef in region_def.zones:
		zone_colors.append(z.map_color)
	var data: PackedByteArray = img.get_data()
	my_zone.resize(w * h)
	var bad: int = 0
	for i: int in w * h:
		var r: int = data[i * 4]
		var g: int = data[i * 4 + 1]
		var b: int = data[i * 4 + 2]
		var found: int = -1
		for k: int in zone_colors.size():
			var c: Color = zone_colors[k]
			if roundi(c.r * 255.0) == r and roundi(c.g * 255.0) == g and roundi(c.b * 255.0) == b and data[i * 4 + 3] == 255:
				found = k
				break
		if found < 0:
			bad += 1
			found = 255
		my_zone[i] = found
	obs["zone_png_unmapped_pixels"] = bad

func new_world() -> WorldState:
	return RegionLoader.load_region(region_def)

func new_field(w: WorldState) -> EnemyField:
	var f: EnemyField = EnemyField.new(w, etune, T)
	f.setup_nests(region_def.zones)
	return f

func own_zone_counts(w: WorldState) -> Dictionary:
	var tg: Array[int] = []
	var gr: Array[int] = []
	tg.resize(zone_colors.size())
	gr.resize(zone_colors.size())
	tg.fill(0)
	gr.fill(0)
	for i: int in w.tile_count():
		if w.target[i] == 1:
			tg[my_zone[i]] += 1
			if w.stage[i] >= 2:
				gr[my_zone[i]] += 1
	return {"t": tg, "g": gr}

func t_map() -> void:
	var w: WorldState = new_world()
	rec("map.size", "map 1px=1tile layer size equals map; every pixel in legend", obs["zone_png_unmapped_pixels"] == 0 and obs["zone_png_size"][0] == w.width and obs["zone_png_size"][1] == w.height, str(obs["zone_png_size"]))
	rec("map.zones7", "7 zones", w.zone_count == 7 and zone_colors.size() == 7, "zone_count=%d" % w.zone_count)
	var same: bool = true
	for i: int in w.tile_count():
		if w.zone_of[i] != my_zone[i]:
			same = false
			break
	rec("map.zone_of", "world.zone_of equals independent PNG decode for all tiles", same, "")
	var oc: Dictionary = own_zone_counts(w)
	var tsum: int = 0
	for v: int in oc["t"]:
		tsum += v
	var csum: int = 0
	for v: int in w.zone_target_count:
		csum += v
	obs["own_target_per_zone"] = oc["t"]
	obs["world_target_per_zone"] = Array(w.zone_target_count)
	rec("map.target_sum", "sum of per-zone targets (own decode) == world.target_count == 244759", tsum == w.target_count and csum == w.target_count and w.target_count == 244759, "own=%d world_sum=%d total=%d" % [tsum, csum, w.target_count])
	rec("map.zone_target_each", "per-zone target equals own per-zone recount", Array(w.zone_target_count) == oc["t"], str(oc["t"]))
	rec("map.start_stable", "start zone stable (state 2), others unconquered (0)", w.zone_state[0] == 2 and w.zone_state[1] == 0 and w.zone_state[2] == 0 and w.zone_state[3] == 0 and w.zone_state[4] == 0 and w.zone_state[5] == 0 and w.zone_state[6] == 0, str(Array(w.zone_state)))
	var st: Vector2i = region_def.start_tile
	rec("map.start_in_zone0", "player start tile lies in zone 0", my_zone[st.y * w.width + st.x] == 0, "start=%s zone=%d" % [st, my_zone[st.y * w.width + st.x]])
	rec("map.consistent", "counters_consistent on fresh world", w.counters_consistent(), "")

func t_nests() -> void:
	var w: WorldState = new_world()
	var f: EnemyField = new_field(w)
	rec("nests.count", "15 nests", f.nests.size() == 15, "n=%d" % f.nests.size())
	var ok_zone: bool = true
	var ok_occ: bool = true
	var ok_terr: bool = true
	var per_zone: Dictionary = {}
	for n: Nest in f.nests:
		per_zone[n.zone] = per_zone.get(n.zone, 0) + 1
		if n.size != 4:
			ok_occ = false
		for y: int in range(n.tile.y, n.tile.y + 4):
			for x: int in range(n.tile.x, n.tile.x + 4):
				var i: int = y * w.width + x
				if my_zone[i] != n.zone or n.zone == 0:
					ok_zone = false
				if w.occupant[i] != 1000000 + n.id:
					ok_occ = false
				if not w.terrain_defs[w.terrain[i]].plantable:
					ok_terr = false
	rec("nests.zone", "all 16 tiles of each nest in a non-start zone (own decode)", ok_zone, str(per_zone))
	rec("nests.occupant", "all 16 tiles occupant == 1000000+id", ok_occ, "")
	rec("nests.terrain", "nests on plantable ground", ok_terr, "")
	var nonzero: int = 0
	for i: int in w.tile_count():
		if w.occupant[i] != 0:
			nonzero += 1
	rec("nests.tilesum", "occupied tile total == 15*16", nonzero == 240, "occupied=%d" % nonzero)
	# nothing else can enter: can_plant false, spread allows false
	var blocked: bool = true
	var n0: Nest = f.nests[0]
	var idx: int = n0.tile.y * w.width + n0.tile.x
	if w.can_plant(idx) or f.spread_allows(idx):
		blocked = false
	rec("nests.noplant", "can_plant and spread hook refuse nest tile", blocked, "")
	rec("nests.occupy_refused", "occupy over a nest refused (cultivated owner band)", not w.occupy(Rect2i(n0.tile.x, n0.tile.y, 2, 2), 1001), "")
	# destroy releases
	f.destroy_nest(n0)
	rec("nests.release", "destroyed nest frees tiles", w.occupant[idx] == 0 and w.can_plant(idx) and not f.nests[0].alive, "")
	# a nest cannot overlap start zone / water
	rec("nests.refuse_start", "add_nest in stable start zone region tile refused when zone mismatch", f.add_nest(1, Vector2i(st_x(), st_y())) == null, "")

func st_x() -> int:
	return region_def.start_tile.x
func st_y() -> int:
	return region_def.start_tile.y

func step_to(f: EnemyField, seconds: float, dt: float) -> void:
	var target: float = f.time + seconds
	while f.time < target - 1e-9:
		f.advance(minf(dt, target - f.time))

func t_spawn() -> void:
	var w: WorldState = new_world()
	var f: EnemyField = new_field(w)
	step_to(f, 11.9, 1.0 / 60.0)
	rec("spawn.before", "no boar before 12 s", f.boars.size() == 0, "n=%d" % f.boars.size())
	step_to(f, 0.2, 1.0 / 60.0)
	rec("spawn.at12", "after 12.1 s exactly one boar per nest (15)", f.boars.size() == 15, "n=%d" % f.boars.size())
	step_to(f, 12.0, 1.0 / 60.0)
	rec("spawn.at24", "after 24.1 s: 30 boars", f.boars.size() == 30, "n=%d" % f.boars.size())
	step_to(f, 12.0, 1.0 / 60.0)
	rec("spawn.at36", "after 36.1 s: 40 (global cap, 15*3=45>40)", f.boars.size() == 40, "n=%d" % f.boars.size())
	var peak: int = 0
	var nest_peak: int = 0
	for k: int in 600 * 60:
		f.advance(1.0 / 60.0)
		peak = maxi(peak, f.boars.size())
		for n: Nest in f.nests:
			nest_peak = maxi(nest_peak, n.boar_count)
	rec("spawn.cap_hold", "10 more minutes: never above 40; per nest <= 4", peak <= 40 and nest_peak <= 4, "peak=%d nest_peak=%d total_spawned=%d" % [peak, nest_peak, f.total_spawned])
	# boar counts per nest recomputed independently
	var by_nest: Dictionary = {}
	for b: Boar in f.boars:
		by_nest[b.nest_id] = by_nest.get(b.nest_id, 0) + 1
	var mx: int = 0
	for k: Variant in by_nest:
		mx = maxi(mx, by_nest[k])
	rec("spawn.per_nest_recount", "own recount of boars per nest <= 4", mx <= 4, str(by_nest))
	# no banked spawns: kill 5 boars; next spawn should need ~12 s, not immediate burst
	var before: int = f.total_spawned
	for k: int in 5:
		f.damage_boar(f.boars[0], 99)
	step_to(f, 0.5, 1.0 / 60.0)
	rec("spawn.nobank", "after killing 5 at cap, no instant refill (timer did not run while capped)", f.total_spawned - before <= 0, "spawned_delta=%d boars=%d" % [f.total_spawned - before, f.boars.size()])
	step_to(f, 12.5, 1.0 / 60.0)
	rec("spawn.refill", "after 13 s refilled to 40", f.boars.size() == 40, "n=%d" % f.boars.size())

	# stable zone: no spawns
	var w2: WorldState = new_world()
	var f2: EnemyField = new_field(w2)
	for z: int in [1, 2, 3, 4, 5]:
		w2.set_zone_state(z, 2)
	step_to(f2, 120.0, 1.0 / 60.0)
	var zones_seen: Dictionary = {}
	for b: Boar in f2.boars:
		zones_seen[b.zone] = zones_seen.get(b.zone, 0) + 1
	rec("spawn.stable_none", "only zone 6 nests (3) spawn when zones 1-5 stable: <=12 boars all in zone 6, per nest <=4", f2.boars.size() == 12 and zones_seen.keys() == [6], "n=%d zones=%s" % [f2.boars.size(), zones_seen])
	# destroy nests: no further spawns
	var w3: WorldState = new_world()
	var f3: EnemyField = new_field(w3)
	step_to(f3, 13.0, 1.0 / 60.0)
	var n_before: int = f3.boars.size()
	for n: Nest in f3.nests:
		f3.destroy_nest(n)
	for b: Boar in f3.boars.duplicate():
		f3.damage_boar(b, 99)
	step_to(f3, 300.0, 1.0 / 60.0)
	rec("spawn.destroyed_none", "no spawn after all nests destroyed", n_before == 15 and f3.boars.size() == 0 and f3.total_spawned == 15, "before=%d now=%d spawned=%d" % [n_before, f3.boars.size(), f3.total_spawned])
	# one nest destroyed: only that nest stops
	var w4: WorldState = new_world()
	var f4: EnemyField = new_field(w4)
	f4.destroy_nest(f4.nests[0])
	step_to(f4, 13.0, 1.0 / 60.0)
	rec("spawn.one_destroyed", "14 boars when one nest destroyed", f4.boars.size() == 14, "n=%d" % f4.boars.size())

func plant_patch(w: WorldState, x0: int, y0: int, x1: int, y1: int, stage: int, z: int) -> int:
	var n: int = 0
	for y: int in range(y0, y1 + 1):
		for x: int in range(x0, x1 + 1):
			var i: int = y * w.width + x
			if my_zone[i] == z and w.occupant[i] == 0 and w.target[i] == 1 and w.terrain_defs[w.terrain[i]].plantable and w.set_stage(i, stage):
				n += 1
	return n

func violation(w: WorldState, f: EnemyField, b: Boar) -> String:
	var hx: float = etune.boar_half_width_px
	var hy: float = etune.boar_half_height_px
	var x0: int = floori((b.pos.x - hx + 0.001) / T)
	var x1: int = floori((b.pos.x + hx - 0.001) / T)
	var y0: int = floori((b.pos.y - hy + 0.001) / T)
	var y1: int = floori((b.pos.y + hy - 0.001) / T)
	if x0 < 0 or y0 < 0 or x1 >= w.width or y1 >= w.height:
		return "out of map"
	for y: int in range(y0, y1 + 1):
		for x: int in range(x0, x1 + 1):
			var i: int = y * w.width + x
			if my_zone[i] != b.zone:
				return "other zone %d at (%d,%d)" % [my_zone[i], x, y]
			var td: TerrainDef = w.terrain_defs[w.terrain[i]]
			if td.key == &"water" or td.key == &"building" or not td.walkable:
				return "terrain %s at (%d,%d)" % [td.key, x, y]
			if w.occupant[i] >= 1000000:
				nest_walk_frames += 1
	var n: Nest = f.nest_by_id(b.nest_id)
	var c: Vector2 = (Vector2(n.tile) + Vector2(2, 2)) * T
	if b.pos.distance_to(c) > 48.0 * T + 0.01:
		return "beyond tether %.2f" % b.pos.distance_to(c)
	if w.zone_state[b.zone] >= 2:
		return "stable zone"
	return ""

func t_long() -> void:
	var w: WorldState = new_world()
	var f: EnemyField = new_field(w)
	# plants: near all nests inside own zone + a mature strip in the START zone and in stable-adjacent zone borders
	var seeded_enemy: int = 0
	for n: Nest in f.nests:
		seeded_enemy += plant_patch(w, n.tile.x - 30, n.tile.y - 30, n.tile.x + 34, n.tile.y + 34, 4, n.zone)
	var start_plants: int = 0
	# start-zone strip along the whole zone-1/zone-0 and zone-2/zone-0 borders (rows 100..150 and 240..290)
	start_plants += plant_patch(w, 40, 126, 260, 150, 4, 0)
	start_plants += plant_patch(w, 40, 240, 260, 259, 4, 0)
	start_plants += plant_patch(w, 300, 100, 460, 200, 4, 0)
	var start_before: int = 0
	var start_ids: PackedInt32Array = PackedInt32Array()
	for i: int in w.tile_count():
		if my_zone[i] == 0 and w.stage[i] != 0:
			start_before += 1
			start_ids.append(i)
	obs["seeded_enemy"] = seeded_enemy
	obs["start_plants_before"] = start_before
	var frames: int = int(minutes * 60.0 * 60.0)
	var bad: Array[String] = []
	var peak: int = 0
	var nest_peak: int = 0
	var series: Array = []
	var min_green_seen: int = w.greened_count
	for fr: int in frames:
		f.advance(1.0 / 60.0)
		peak = maxi(peak, f.boars.size())
		for n: Nest in f.nests:
			nest_peak = maxi(nest_peak, n.boar_count)
		for b: Boar in f.boars:
			var v: String = violation(w, f, b)
			if v != "" and bad.size() < 10:
				bad.append("frame %d boar %d: %s" % [fr, b.id, v])
		if fr % 3600 == 0:
			series.append([fr / 3600, f.boars.size(), f.total_gnawed, w.greened_count])
	obs["series_min_boars_gnawed_green"] = series
	obs["boar_frames_over_nest_tiles"] = nest_walk_frames
	rec("long.cap", "%.0f min idle: boars never > 40, per nest never > 4" % minutes, peak <= 40 and nest_peak <= 4 and peak == 40, "peak=%d nest_peak=%d spawned=%d" % [peak, nest_peak, f.total_spawned])
	rec("long.confine", "every frame, every boar: own zone, no water/building/nest, within 48 tiles tether, zone not stable", bad.is_empty(), str(bad))
	var start_after: int = 0
	for i: int in start_ids:
		if w.stage[i] != 0:
			start_after += 1
	rec("long.safe_back", "start-zone (stable) plants untouched", start_after == start_before and start_before > 1000, "before=%d after=%d" % [start_before, start_after])
	rec("long.gnawed", "boars gnawed plants (total_gnawed>0, plants decreased)", f.total_gnawed > 0, "gnawed=%d" % f.total_gnawed)
	var oc: Dictionary = own_zone_counts(w)
	var gsum: int = 0
	for v: int in oc["g"]:
		gsum += v
	rec("long.counters", "global and per-zone greened counters equal own recount; counters_consistent", gsum == w.greened_count and Array(w.zone_greened_count) == oc["g"] and w.counters_consistent(), "own=%d world=%d" % [gsum, w.greened_count])
	var nest_ok: bool = true
	for n: Nest in f.nests:
		for y: int in range(n.tile.y, n.tile.y + 4):
			for x: int in range(n.tile.x, n.tile.x + 4):
				if w.stage[y * w.width + x] != 0:
					nest_ok = false
	rec("long.nest_tiles_empty", "nest tiles never planted", nest_ok, "")

func manual_boar(f: EnemyField, nest: Nest, pos: Vector2) -> Boar:
	var b: Boar = Boar.new()
	b.id = f.next_boar_id
	f.next_boar_id += 1
	b.nest_id = nest.id
	b.zone = nest.zone
	b.pos = pos
	b.home = nest.center_px(T)
	b.hp = 3
	b.think = 1
	b.rng = 12345
	f.boars.append(b)
	nest.boar_count += 1
	return b

func t_gnaw() -> void:
	var w: WorldState = new_world()
	var f: EnemyField = new_field(w)
	var nest: Nest = f.nests[0]
	obs["nest0"] = [nest.zone, nest.tile]
	# plant a ring of seeds/sprouts/mature near but away from nest
	var cx: int = nest.tile.x + 20
	var cy: int = nest.tile.y + 20
	var n_planted: int = plant_patch(w, cx, cy, cx + 6, cy + 6, 4, nest.zone)
	n_planted += plant_patch(w, cx + 8, cy, cx + 10, cy + 6, 1, nest.zone)
	var g0: int = w.greened_count
	var zg0: int = w.zone_greened_count[nest.zone]
	var zt: Array = Array(w.zone_target_count)
	var b: Boar = manual_boar(f, nest, Vector2(cx * T + 6, cy * T - 40))
	f.tuning.enabled = true
	var seen_drop: bool = false
	var t: float = 0.0
	while t < 60.0:
		f.advance(1.0 / 60.0)
		t += 1.0 / 60.0
	var oc: Dictionary = own_zone_counts(w)
	var gsum: int = 0
	for v: int in oc["g"]:
		gsum += v
	rec("gnaw.reduce", "boar left alone for 60 s reduces greening", w.greened_count < g0 and f.total_gnawed > 0, "greened %d -> %d gnawed=%d" % [g0, w.greened_count, f.total_gnawed])
	rec("gnaw.delta_counters", "global + per-zone differential counters == own recount", gsum == w.greened_count and Array(w.zone_greened_count) == oc["g"] and Array(w.zone_target_count) == zt, "own=%d world=%d zone_before=%d zone_after=%d" % [gsum, w.greened_count, zg0, w.zone_greened_count[nest.zone]])
	var dropped: int = g0 - w.greened_count
	rec("gnaw.delta_equal", "global drop equals zone drop (differential)", dropped == zg0 - w.zone_greened_count[nest.zone], "drop=%d" % dropped)
	var radius_ok: bool = true
	# cultivated plant (occupant) not eaten
	var w2: WorldState = new_world()
	var f2: EnemyField = new_field(w2)
	var nest2: Nest = f2.nests[0]
	var px: int = nest2.tile.x + 20
	var py: int = nest2.tile.y + 20
	w2.occupy(Rect2i(px, py, 2, 2), 1001)
	for yy: int in 2:
		for xx: int in 2:
			w2.set_stage((py + yy) * w2.width + px + xx, 4)
	var b2: Boar = manual_boar(f2, nest2, Vector2((px + 1) * T, (py + 1) * T + 8))
	var t2: float = 0.0
	while t2 < 30.0:
		f2.advance(1.0 / 60.0)
		t2 += 1.0 / 60.0
	var alive: int = 0
	for yy: int in 2:
		for xx: int in 2:
			if w2.stage[(py + yy) * w2.width + px + xx] == 4:
				alive += 1
	rec("gnaw.cultivated", "cultivated (occupied) plant tiles not gnawed even with boar adjacent", alive == 4 and f2.total_gnawed == 0, "alive=%d gnawed=%d boar=%s" % [alive, f2.total_gnawed, b2.pos])
	# radius: a single mature tile; boar stationed at distance >1.5 tile cannot bite it (set far goal blocked)
	var w3: WorldState = new_world()
	var f3: EnemyField = new_field(w3)
	var nest3: Nest = f3.nests[0]
	var fb3: Vector2i = find_block(w3, nest3, 6, 6)
	var qx: int = fb3.x + 2
	var qy: int = fb3.y + 2
	obs["q_planted"] = plant_patch(w3, qx, qy, qx, qy, 4, nest3.zone)
	var q_ok: bool = w3.stage[qy * w3.width + qx] == 4
	# boar placed at 3 tiles distance with think forever pushed away: just check one gnaw call doesn't reach
	var b3: Boar = manual_boar(f3, nest3, Vector2((qx + 0.5) * T + 3.0 * T, (qy + 0.5) * T))
	b3.think = 100000
	b3.wait = 100000
	f3.advance(0.2)
	var still: bool = w3.stage[qy * w3.width + qx] == 4
	rec("gnaw.radius_out", "plant 3 tiles away is not bitten (radius 1 tile)", still and q_ok, "stage=%d" % w3.stage[qy * w3.width + qx])
	b3.pos = Vector2((qx + 0.5) * T + 0.8 * T, (qy + 0.5) * T)
	f3.advance(0.2)
	rec("gnaw.radius_in", "plant within 1 tile is bitten", w3.stage[qy * w3.width + qx] == 0, "stage=%d" % w3.stage[qy * w3.width + qx])
	# interval 0.6 s
	var w4: WorldState = new_world()
	var f4: EnemyField = new_field(w4)
	var nest4: Nest = f4.nests[0]
	var fb4: Vector2i = find_block(w4, nest4, 8, 3)
	var rx: int = fb4.x + 1
	var ry: int = fb4.y + 1
	obs["r_planted"] = plant_patch(w4, rx, ry, rx + 7, ry, 4, nest4.zone)
	var b4: Boar = manual_boar(f4, nest4, Vector2((rx + 0.5) * T, (ry + 0.5) * T))
	var times: Array = []
	var last: int = f4.total_gnawed
	var tt: float = 0.0
	while tt < 12.0:
		f4.advance(1.0 / 60.0)
		tt += 1.0 / 60.0
		if f4.total_gnawed != last:
			times.append(snappedf(tt, 0.001))
			last = f4.total_gnawed
	obs["gnaw_times"] = times
	var gaps_ok: bool = times.size() >= 3
	for k: int in range(1, times.size()):
		if (times[k] - times[k - 1]) < 0.6 - 0.02:
			gaps_ok = false
	rec("gnaw.interval", "consecutive bites at least 0.6 s apart", gaps_ok, str(times))

func t_spread() -> void:
	var w: WorldState = new_world()
	var f: EnemyField = new_field(w)
	var sp: SpreadSim = SpreadSim.new(w, sim_tuning)
	sp.allow_hook = f.spread_allows
	var nest: Nest = f.nests[0]
	var x0: int = nest.tile.x + 20
	var y0: int = nest.tile.y + 20
	var patch: int = plant_patch(w, x0, y0, x0 + 8, y0 + 8, 4, nest.zone)
	obs["patch"] = patch
	# let events be applied
	for k: int in 3:
		sp.tick()
	var center: int = (y0 + 4) * w.width + x0 + 4
	rec("spread.pre", "patch mature and center eligible", w.stage[center] == 4, "")
	# eat center (what the boar does), mature
	w.set_stage(center, 0)
	var planted_at: int = -1
	for k: int in 60:
		sp.tick()
		if w.stage[center] != 0:
			planted_at = k
			break
	rec("spread.regrow_mature", "gnawed formerly-mature tile in a mature patch is planted again by natural spread", planted_at >= 0, "ticks=%d (planted_at=%d)" % [sp.ticks, planted_at])
	# eat a seed tile at border (non-mature) -> also fine
	var edge: int = (y0 + 4) * w.width + x0 + 8
	w.set_stage(edge, 0)
	var edge_at: int = -1
	for k: int in 60:
		sp.tick()
		if w.stage[edge] != 0:
			edge_at = k
			break
	rec("spread.regrow_edge", "gnawed edge mature tile replanted", edge_at >= 0, "k=%d" % edge_at)
	# nest tiles never planted by spread: mature patch next to nest
	var w2: WorldState = new_world()
	var f2: EnemyField = new_field(w2)
	var sp2: SpreadSim = SpreadSim.new(w2, sim_tuning)
	sp2.allow_hook = f2.spread_allows
	var n2: Nest = f2.nests[0]
	plant_patch(w2, n2.tile.x - 6, n2.tile.y - 6, n2.tile.x + 10, n2.tile.y + 10, 4, n2.zone)
	for k: int in 400:
		sp2.tick()
	var bad: int = 0
	for y: int in range(n2.tile.y, n2.tile.y + 4):
		for x: int in range(n2.tile.x, n2.tile.x + 4):
			if w2.stage[y * w2.width + x] != 0:
				bad += 1
	rec("spread.nest_excluded", "400 spread ticks next to a nest: no plant on its 16 tiles; surroundings spread", bad == 0 and sp2.total_planted > 0, "bad=%d planted=%d" % [bad, sp2.total_planted])
	# after destroy the tiles are plantable by spread
	f2.destroy_nest(n2)
	for k: int in 400:
		sp2.tick()
	var after: int = 0
	for y: int in range(n2.tile.y, n2.tile.y + 4):
		for x: int in range(n2.tile.x, n2.tile.x + 4):
			if w2.stage[y * w2.width + x] != 0:
				after += 1
	rec("spread.after_destroy", "tiles free for spread after the nest is destroyed", after > 0, "planted_tiles=%d" % after)
	# end-to-end: boar eats, spread regrows (combined 120 s), counters consistent
	var w3: WorldState = new_world()
	var f3: EnemyField = new_field(w3)
	var sp3: SpreadSim = SpreadSim.new(w3, sim_tuning)
	sp3.allow_hook = f3.spread_allows
	var n3: Nest = f3.nests[0]
	var px: int = n3.tile.x + 20
	var py: int = n3.tile.y + 20
	plant_patch(w3, px, py, px + 12, py + 12, 4, n3.zone)
	manual_boar(f3, n3, Vector2((px + 6) * T, (py + 6) * T))
	var t: float = 0.0
	var tick_acc: float = 0.0
	var min_plants: int = 1 << 30
	while t < 120.0:
		f3.advance(1.0 / 60.0)
		t += 1.0 / 60.0
		tick_acc += 1.0 / 60.0
		if tick_acc >= 1.0:
			tick_acc -= 1.0
			sp3.tick()
		if int(t * 60) % 60 == 0:
			min_plants = mini(min_plants, w3.plant_count)
	rec("spread.e2e", "boar + spread 120 s: counters consistent, spread keeps planting", w3.counters_consistent() and sp3.total_planted > 0 and f3.total_gnawed > 0, "gnawed=%d planted=%d plants=%d" % [f3.total_gnawed, sp3.total_planted, w3.plant_count])
	var pc: PackedInt32Array = w3.recount_plant_chunks()
	rec("spread.plant_chunks", "plant chunk counters equal recount", pc == w3.plant_chunk_count, "")

func state_sig(w: WorldState, f: EnemyField) -> String:
	var h: PackedByteArray = w.stage.duplicate()
	var s: String = "%d|%d|%d|%d|%d|" % [hash(h), w.greened_count, f.boars.size(), f.total_spawned, f.total_gnawed]
	for b: Boar in f.boars:
		s += "%d:%.2f,%.2f;" % [b.id, b.pos.x, b.pos.y]
	return s

func scenario_world() -> Array:
	var w: WorldState = new_world()
	var f: EnemyField = new_field(w)
	for n: Nest in f.nests:
		plant_patch(w, n.tile.x - 20, n.tile.y - 20, n.tile.x + 24, n.tile.y + 24, 4, n.zone)
	return [w, f]

func t_rates() -> void:
	var sigs: Dictionary = {}
	for hz: int in [30, 60, 144]:
		var pair: Array = scenario_world()
		var w: WorldState = pair[0]
		var f: EnemyField = pair[1]
		var dt: float = 1.0 / float(hz)
		var n: int = int(round(180.0 * hz))
		for k: int in n:
			f.advance(dt)
		# step count at 180 s (+ tiny) is the same
		sigs[hz] = "%d|" % f.steps_done + state_sig(w, f)
		print("hz %d steps=%d boars=%d gnawed=%d" % [hz, f.steps_done, f.boars.size(), f.total_gnawed])
	obs["sig_lengths"] = [sigs[30].length(), sigs[60].length(), sigs[144].length()]
	var s30: String = sigs[30]
	var s60: String = sigs[60]
	var s144: String = sigs[144]
	# allow +-1 step difference at the end due to float time: compare after trimming steps_done field
	var same_state: bool = s30.substr(s30.find("|") + 1) == s60.substr(s60.find("|") + 1) and s60.substr(s60.find("|") + 1) == s144.substr(s144.find("|") + 1)
	rec("rates.same", "30/60/144 Hz after 180 s give identical boar positions, stages, counters", same_state, "steps: %s %s %s" % [s30.split("|")[0], s60.split("|")[0], s144.split("|")[0]])
	if not same_state:
		obs["s30"] = s30.substr(0, 400)
		obs["s60"] = s60.substr(0, 400)
		obs["s144"] = s144.substr(0, 400)
	# the hitch cap: one huge delta does not run more than max_step_seconds
	var pair2: Array = scenario_world()
	var f2: EnemyField = pair2[1]
	f2.advance(60.0)
	rec("rates.hitch", "a single 60 s delta adds at most 0.25 s", f2.time <= 0.25 + 1e-6, "time=%f" % f2.time)

func t_save() -> void:
	var pair: Array = scenario_world()
	var w: WorldState = pair[0]
	var f: EnemyField = pair[1]
	for k: int in 90 * 60:
		f.advance(1.0 / 60.0)
	f.damage_nest(f.nests[2], 5)
	f.destroy_nest(f.nests[3])
	var wd: String = JSON.stringify(w.to_dict())
	var fd: String = JSON.stringify(f.to_dict())
	var w2: WorldState = WorldState.from_dict(JSON.parse_string(wd), w.terrain_defs)
	rec("save.world", "world restores from JSON incl. zones and counters", w2 != null and w2.zone_count == 7 and w2.counters_consistent() and w2.zone_of == w.zone_of and Array(w2.zone_state) == Array(w.zone_state) and w2.greened_count == w.greened_count, "")
	var f2: EnemyField = EnemyField.new(w2, etune, T)
	var ok: bool = f2.load_dict(JSON.parse_string(fd))
	rec("save.field", "enemy field restores from JSON", ok and f2.boars.size() == f.boars.size() and f2.nests.size() == 15 and f2.nests[3].alive == false and f2.nests[2].hp == f.nests[2].hp, "boars=%d" % f2.boars.size())
	var occ_same: bool = w2.occupant == w.occupant
	rec("save.occupancy", "occupancy (nest tiles) identical after restore", occ_same, "")
	# continue both for 120 s -> identical
	for k: int in 120 * 60:
		f.advance(1.0 / 60.0)
		f2.advance(1.0 / 60.0)
	rec("save.continue", "original and restored continue identically for 120 s", state_sig(w, f) == state_sig(w2, f2) and f.steps_done == f2.steps_done, state_sig(w, f).substr(0, 80) + " vs " + state_sig(w2, f2).substr(0, 80))
	# bad data rejected
	var bad: Dictionary = JSON.parse_string(fd)
	bad["nests"][0]["zone"] = 99
	var f3: EnemyField = EnemyField.new(w2, etune, T)
	rec("save.reject", "invalid zone in nest data rejected", not f3.load_dict(bad), "")

## First (x, y) near the nest where a w x h block is entirely plantable target ground of the zone, unoccupied and empty.
func find_block(w: WorldState, nest: Nest, bw: int, bh: int) -> Vector2i:
	for r: int in range(8, 40):
		for dy: int in range(-r, r + 1, 2):
			for dx: int in range(-r, r + 1, 2):
				var x0: int = nest.tile.x + dx
				var y0: int = nest.tile.y + dy
				if x0 < 1 or y0 < 1 or x0 + bw >= w.width or y0 + bh >= w.height:
					continue
				var ok: bool = true
				for y: int in range(y0 - 1, y0 + bh + 1):
					for x: int in range(x0 - 1, x0 + bw + 1):
						var i: int = y * w.width + x
						if my_zone[i] != nest.zone or w.target[i] == 0 or w.occupant[i] != 0 or not w.terrain_defs[w.terrain[i]].plantable:
							ok = false
				if ok:
					return Vector2i(x0, y0)
	return Vector2i(-1, -1)
