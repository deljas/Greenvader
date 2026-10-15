extends SceneTree
## Independent P2-04 verification, display-free logic on a self-built test map (zone 0 stable | zone 1 enemy | zone 2 enemy).
## Run: Godot --headless --path <p> --script res://tests/p2/independent/p2_04_v_logic.gd -- --only=<trans|reinvade|purge|save> [--minutes=15] [--hz=60]
## Expectations come from the ticket text: U -(all nests destroyed)-> clearing -(0 boars)-> stable -(greened==targets)-> complete; no going back;
## cleared once when all zones complete; enemies never enter / harm stable zones.
const OUT: String = "res://evidence/p2/p2-04/independent/"
const T: int = 4
var results: Array[Dictionary] = []
var obs: Dictionary = {}
var region_def: RegionDef
var etune: EnemyTuning
var minutes: float = 15.0
var hz: int = 60

func _initialize() -> void:
	run.call_deferred()

func rec(id: String, cond: String, ok: bool, observed: String) -> void:
	results.append({"id": id, "condition": cond, "status": "PASS" if ok else "FAIL", "observed": observed})
	print("%s [%s] %s :: %s" % ["PASS" if ok else "FAIL", id, cond, observed])

func run() -> void:
	var only: String = "trans"
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.trim_prefix("--only=")
		elif a.begins_with("--minutes="):
			minutes = float(a.trim_prefix("--minutes="))
		elif a.begins_with("--hz="):
			hz = int(a.trim_prefix("--hz="))
	region_def = load("res://data/region_01.tres") as RegionDef
	etune = load("res://data/enemy_tuning.tres") as EnemyTuning
	match only:
		"trans": t_trans()
		"reinvade": t_reinvade()
		"purge": t_purge()
		"save": t_save()
	var f: FileAccess = FileAccess.open(OUT + "checks_%s_%d.json" % [only, hz], FileAccess.WRITE)
	f.store_string(JSON.stringify({"results": results, "observations": obs}, "  "))
	f.close()
	var fails: int = 0
	for r: Dictionary in results:
		if r["status"] != "PASS":
			fails += 1
	print("RESULT %s checks=%d failures=%d" % [only, results.size(), fails])
	quit(1 if fails > 0 else 0)

func terr(key: StringName) -> TerrainDef:
	for d: TerrainDef in region_def.terrains:
		if d.key == key:
			return d
	return null

## Map W x H of wasteland. Zone of a tile: 0 if x < b1, 1 if x < b2, else 2.
func make_world(w: int, h: int, b1: int, b2: int, states: Array) -> WorldState:
	var def: RegionDef = RegionDef.new()
	def.width_tiles = w
	def.height_tiles = h
	def.terrains = region_def.terrains
	def.sprout_seed = region_def.sprout_seed
	var col: Color = terr(&"wasteland").map_color
	var img: Image = Image.create(w, h, false, Image.FORMAT_RGB8)
	img.fill(Color8(roundi(col.r * 255.0), roundi(col.g * 255.0), roundi(col.b * 255.0)))
	var world: WorldState = RegionLoader.build_state(def, img)
	var ids: PackedByteArray = PackedByteArray()
	ids.resize(world.tile_count())
	for i: int in world.tile_count():
		var x: int = i % w
		ids[i] = 0 if x < b1 else (1 if x < b2 else 2)
	world.set_zones(ids, PackedByteArray(states))
	return world

func zone_targets(w: WorldState, z: int) -> Array[int]:
	var out: Array[int] = []
	for i: int in w.tile_count():
		if w.zone_of[i] == z and w.target[i] == 1:
			out.append(i)
	return out

func own_greened(w: WorldState, z: int) -> int:
	var n: int = 0
	for i: int in w.tile_count():
		if w.zone_of[i] == z and w.target[i] == 1 and w.stage[i] >= 2:
			n += 1
	return n

func step_secs(f: EnemyField, s: float) -> void:
	var n: int = roundi(s * hz)
	for k: int in n:
		f.advance(1.0 / float(hz))

func t_trans() -> void:
	var w: WorldState = make_world(90, 40, 30, 60, [2, 0, 0])
	var f: EnemyField = EnemyField.new(w, etune, T)
	var n1a: Nest = f.add_nest(1, Vector2i(36, 10))
	var n1b: Nest = f.add_nest(1, Vector2i(50, 24))
	var n2: Nest = f.add_nest(2, Vector2i(70, 10))
	var pr: ZoneProgress = ZoneProgress.new(w, f)
	var log: Array = []
	w.zone_state_changed.connect(func(z: int, o: int, n: int) -> void: log.append([z, o, n]))
	var cleared_n: Array[int] = [0]
	pr.cleared.connect(func() -> void: cleared_n[0] += 1)
	pr.start()
	rec("t.init", "after start: zone0 (no nest) stable, zones1/2 unconquered, not cleared", Array(w.zone_state) == [2, 0, 0] and not w.cleared, str(Array(w.zone_state)))
	f.destroy_nest(n1a)
	rec("t.one_left", "one nest of two left -> zone 1 stays unconquered", w.zone_state[1] == 0, str(Array(w.zone_state)))
	step_secs(f, 30.0)
	var boars1: int = f.boar_count_in_zone(1)
	rec("t.spawning", "zone1 (one nest alive) still spawns boars", boars1 > 0, "boars=%d" % boars1)
	f.destroy_nest(n1b)
	rec("t.clearing", "last nest destroyed with boars alive -> clearing", w.zone_state[1] == 1 and boars1 > 0, str(Array(w.zone_state)))
	var z1_boars: int = f.boar_count_in_zone(1)
	var spawned_a: int = n1a.spawned + n1b.spawned
	step_secs(f, 180.0)
	rec("t.spawn_stops", "clearing zone1: nests of zone 1 spawn nothing in 180 s, boar count does not grow", n1a.spawned + n1b.spawned == spawned_a and f.boar_count_in_zone(1) <= z1_boars, "spawned %d -> %d, z1 boars %d -> %d" % [spawned_a, n1a.spawned + n1b.spawned, z1_boars, f.boar_count_in_zone(1)])
	rec("t.still_clearing", "boars remain -> not stable yet", w.zone_state[1] == 1, str(Array(w.zone_state)))
	var killed: int = 0
	while f.boar_count_in_zone(1) > 1:
		var b: Boar = null
		for c: Boar in f.boars:
			if c.zone == 1:
				b = c
				break
		f.damage_boar(b, 99)
		killed += 1
	rec("t.one_boar_left", "one boar left -> still clearing", f.boar_count_in_zone(1) == 1 and w.zone_state[1] == 1, "killed=%d state=%d" % [killed, w.zone_state[1]])
	var last: Boar = null
	for c: Boar in f.boars:
		if c.zone == 1:
			last = c
	f.damage_boar(last, 99)
	rec("t.stable", "last boar killed -> stable", w.zone_state[1] == 2, str(Array(w.zone_state)))
	var targets: Array[int] = zone_targets(w, 1)
	var tcount: int = targets.size()
	obs["zone1_targets"] = tcount
	rec("t.target_count", "world target count of zone 1 equals own count", w.zone_target_count[1] == tcount and tcount > 100, "world=%d own=%d" % [w.zone_target_count[1], tcount])
	for k: int in tcount - 1:
		w.set_stage(targets[k], 2)
	rec("t.one_short", "all targets but ONE greened -> stays stable (not complete)", w.zone_state[1] == 2 and own_greened(w, 1) == tcount - 1, "greened=%d/%d state=%d pct=%d" % [own_greened(w, 1), tcount, w.zone_state[1], w.zone_greening_percent_floor(1)])
	w.set_stage(targets[tcount - 1], 2)
	rec("t.complete", "last target greened -> complete", w.zone_state[1] == 3, "state=%d" % w.zone_state[1])
	for k: int in 50:
		w.set_stage(targets[k], 0)
	rec("t.no_regress", "complete zone stays complete after plants are removed", w.zone_state[1] == 3, "state=%d greened=%d" % [w.zone_state[1], w.zone_greened_count[1]])
	f.destroy_nest(n2)
	for c: Boar in f.boars.duplicate():
		f.damage_boar(c, 99)
	rec("t.z2_stable", "zone2 stable after its nest and boars are gone", w.zone_state[2] == 2, str(Array(w.zone_state)))
	rec("t.not_cleared_yet", "not cleared while zone 0/2 not complete", not w.cleared and cleared_n[0] == 0, "cleared=%s" % str(w.cleared))
	for i: int in zone_targets(w, 2):
		w.set_stage(i, 3)
	rec("t.not_cleared_z0", "zone2 complete, zone0 still stable -> not cleared", w.zone_state[2] == 3 and w.zone_state[0] == 2 and not w.cleared, str(Array(w.zone_state)))
	var z0t: Array[int] = zone_targets(w, 0)
	for k: int in z0t.size() - 1:
		w.set_stage(z0t[k], 2)
	rec("t.z0_one_short", "zone0 one tile short -> not complete, not cleared", w.zone_state[0] == 2 and not w.cleared, "state=%d" % w.zone_state[0])
	w.set_stage(z0t[z0t.size() - 1], 2)
	rec("t.cleared", "all zones complete -> cleared flag and signal exactly once", w.cleared and cleared_n[0] == 1 and Array(w.zone_state) == [3, 3, 3], "cleared=%s signals=%d states=%s" % [str(w.cleared), cleared_n[0], str(Array(w.zone_state))])
	step_secs(f, 20.0)
	w.set_stage(z0t[0], 0)
	w.set_stage(z0t[0], 2)
	pr.start()
	rec("t.cleared_once", "further activity / start() again: still exactly one cleared signal, flag stays", cleared_n[0] == 1 and w.cleared and Array(w.zone_state) == [3, 3, 3], "signals=%d" % cleared_n[0])
	var back: bool = false
	for e: Array in log:
		if int(e[2]) < int(e[1]):
			back = true
	obs["transition_log"] = log
	rec("t.forward_only", "no logged transition goes backwards", not back, str(log))

func border_snapshot(w: WorldState, zone: int) -> PackedByteArray:
	var out: PackedByteArray = PackedByteArray()
	for i: int in w.tile_count():
		if w.zone_of[i] == zone:
			out.append(w.stage[i])
	return out

func t_reinvade() -> void:
	# zone 0 (x<100) stable with plants; zone 1 (100..199) enemy with a nest hugging the border; zone 2 (>=200) enemy
	var w: WorldState = make_world(300, 60, 100, 200, [2, 0, 0])
	var f: EnemyField = EnemyField.new(w, etune, T)
	f.add_nest(1, Vector2i(110, 28))
	f.add_nest(2, Vector2i(206, 28))
	var stable_plants: int = 0
	for y: int in range(10, 50):
		for x: int in range(70, 100):
			if w.set_stage(y * 300 + x, 4):
				stable_plants += 1
	for y: int in range(10, 50):
		for x: int in range(100, 118):
			if x >= 110 and x < 114 and y >= 28 and y < 32:
				continue
			w.set_stage(y * 300 + x, 3)
	var pr: ZoneProgress = ZoneProgress.new(w, f)
	pr.start()
	var snap0: PackedByteArray = border_snapshot(w, 0)
	var green0: int = w.zone_greened_count[0]
	var frames: int = int(minutes * 60.0 * float(hz))
	var dt: float = 1.0 / float(hz)
	var intr: int = 0
	var changed_frames: int = 0
	var min_gap_px: float = INF
	var near_frames: int = 0
	var half: Vector2 = Vector2(etune.boar_half_width_px, etune.boar_half_height_px)
	var max_boars: int = 0
	for fr: int in frames:
		f.advance(dt)
		max_boars = maxi(max_boars, f.boars.size())
		for b: Boar in f.boars:
			var x0: int = floori((b.pos.x - half.x + 0.001) / T)
			var x1: int = floori((b.pos.x + half.x - 0.001) / T)
			var y0: int = floori((b.pos.y - half.y + 0.001) / T)
			var y1: int = floori((b.pos.y + half.y - 0.001) / T)
			for y: int in range(y0, y1 + 1):
				for x: int in range(x0, x1 + 1):
					if x < 100:
						intr += 1
			if b.zone == 1:
				var gap: float = (b.pos.x - half.x) - 400.0
				min_gap_px = minf(min_gap_px, gap)
				if gap < 12.0:
					near_frames += 1
		if w.zone_greened_count[0] != green0:
			changed_frames += 1
		if fr % hz == 0 and border_snapshot(w, 0) != snap0:
			changed_frames += 1
	obs["frames"] = frames
	obs["hz"] = hz
	obs["stable_plants_seeded"] = stable_plants
	obs["min_gap_px_to_stable_border"] = min_gap_px
	obs["frames_with_boar_within_12px_of_border"] = near_frames
	obs["total_gnawed"] = f.total_gnawed
	obs["total_spawned"] = f.total_spawned
	obs["max_boars"] = max_boars
	rec("r.nearby", "boars really near the stable border (<12 px) and gnawing (non-vacuous)", near_frames > 0 and f.total_gnawed > 100 and stable_plants > 1000, "near_frames=%d gnawed=%d stable_plants=%d min_gap=%.2f max_boars=%d" % [near_frames, f.total_gnawed, stable_plants, min_gap_px, max_boars])
	rec("r.no_entry", "every frame: no boar footprint tile inside zone 0", intr == 0, "intrusion tile-frames=%d over %d frames (%.1f game min @%dHz)" % [intr, frames, minutes, hz])
	rec("r.plants_intact", "stable-side greened count unchanged every frame; full tile compare each second", changed_frames == 0 and border_snapshot(w, 0) == snap0, "changed=%d" % changed_frames)
	rec("r.zone_stays", "zone 0 stays stable, counters consistent", w.zone_state[0] == 2 and w.counters_consistent(), "state=%d" % w.zone_state[0])

func t_purge() -> void:
	var w: WorldState = make_world(90, 40, 30, 60, [2, 0, 0])
	var f: EnemyField = EnemyField.new(w, etune, T)
	f.add_nest(1, Vector2i(36, 10))
	var pr: ZoneProgress = ZoneProgress.new(w, f)
	pr.start()
	step_secs(f, 90.0)
	var n_before: int = f.boar_count_in_zone(1)
	var killed_before: int = f.total_killed
	var defeated: Array[int] = [0]
	f.boar_defeated.connect(func(_p: Vector2, _i: int) -> void: defeated[0] += 1)
	var carc_before: int = f.carcasses.size()
	w.set_zone_state(1, 2)
	rec("p.vanish", "zone set stable: its boars vanish at once, no kill credit / drop signal / carcass", n_before > 0 and f.boar_count_in_zone(1) == 0 and f.total_killed == killed_before and defeated[0] == 0 and f.carcasses.size() == carc_before, "boars %d -> %d killed %d -> %d defeated_signals=%d carcasses %d -> %d" % [n_before, f.boar_count_in_zone(1), killed_before, f.total_killed, defeated[0], carc_before, f.carcasses.size()])
	var spawned: int = f.total_spawned
	step_secs(f, 120.0)
	rec("p.no_respawn", "no boar returns to the stable zone (alive nest present)", f.boars.is_empty() and f.total_spawned == spawned, "spawned %d -> %d boars=%d alive_nests=%d" % [spawned, f.total_spawned, f.boars.size(), f.alive_nest_count(1)])

func t_save() -> void:
	var w: WorldState = make_world(90, 40, 30, 60, [2, 0, 0])
	var f: EnemyField = EnemyField.new(w, etune, T)
	var n1: Nest = f.add_nest(1, Vector2i(36, 10))
	f.add_nest(2, Vector2i(70, 10))
	var pr: ZoneProgress = ZoneProgress.new(w, f)
	pr.start()
	step_secs(f, 40.0)
	f.destroy_nest(n1)
	for c: Boar in f.boars.duplicate():
		if c.zone == 1:
			f.damage_boar(c, 99)
	for i: int in zone_targets(w, 1):
		w.set_stage(i, 2)
	var data: Dictionary = w.to_dict()
	var fdata: Dictionary = f.to_dict()
	var json: JSON = JSON.new()
	var parsed: bool = json.parse(JSON.stringify(data)) == OK
	var w2: WorldState = WorldState.from_dict(json.data, w.terrain_defs) if parsed else null
	rec("s.round", "world round trip through JSON keeps states", w2 != null and Array(w2.zone_state) == Array(w.zone_state) and w2.cleared == w.cleared, str(Array(w2.zone_state)) if w2 != null else "null")
	var f2: EnemyField = EnemyField.new(w2, etune, T)
	var fj: JSON = JSON.new()
	fj.parse(JSON.stringify(fdata))
	rec("s.field", "enemy data loads onto the restored world", f2.load_dict(fj.data, true), "states=%s" % str(Array(w.zone_state)))
	var w3: WorldState = make_world(60, 20, 20, 40, [3, 3, 3])
	for z: int in 3:
		for i: int in zone_targets(w3, z):
			w3.set_stage(i, 2)
	w3.cleared = true
	var d3: Dictionary = w3.to_dict()
	var w3b: WorldState = WorldState.from_dict(d3, w3.terrain_defs)
	rec("s.cleared", "cleared world round trips with cleared=true", w3b != null and w3b.cleared, "")
	var bad1: Dictionary = d3.duplicate(true)
	bad1["cleared"] = false
	rec("s.refuse_cleared_false", "all complete but cleared=false refused", WorldState.from_dict(bad1, w3.terrain_defs) == null, "")
	var d4: Dictionary = data.duplicate(true)
	d4["cleared"] = true
	rec("s.refuse_cleared_true", "cleared=true while zones are not all complete refused", WorldState.from_dict(d4, w.terrain_defs) == null, "")
	var w5: WorldState = make_world(60, 20, 20, 40, [3, 3, 3])
	rec("s.refuse_complete_ungreened", "zone state complete with no greened targets refused", WorldState.from_dict(w5.to_dict(), w5.terrain_defs) == null, "")
	var wA: WorldState = make_world(90, 40, 30, 60, [2, 0, 0])
	var fA: EnemyField = EnemyField.new(wA, etune, T)
	fA.add_nest(1, Vector2i(36, 10))
	ZoneProgress.new(wA, fA).start()
	step_secs(fA, 60.0)
	var dA: Dictionary = fA.to_dict()
	var wB: WorldState = make_world(90, 40, 30, 60, [2, 2, 0])
	rec("s.refuse_enemy_in_stable", "enemy data with live nest/boars of a zone the world says is stable refused", fA.boars.size() > 0 and not EnemyField.new(wB, etune, T).load_dict(dA, true), "boars=%d" % fA.boars.size())
	var wC: WorldState = make_world(90, 40, 30, 60, [2, 1, 0])
	rec("s.refuse_alive_nest_clearing", "alive nest in a clearing zone refused", not EnemyField.new(wC, etune, T).load_dict(dA, true), "")
	var wD: WorldState = make_world(90, 40, 30, 60, [2, 0, 0])
	var dD: Dictionary = dA.duplicate(true)
	for n: Dictionary in dD["nests"]:
		n["alive"] = false
	rec("s.refuse_dead_nests_unconquered", "all nests dead but zone unconquered refused", not EnemyField.new(wD, etune, T).load_dict(dD, true), "")
