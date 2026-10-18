extends SceneTree
## HLP-03 front play with the helper plants on town_01 (headless OK, game-time fast-forward, each condition once):
##   godot --headless --path <repo> --script res://tests/poc/integration/helpers_front.gd
## F: a 600 s (10 min of game time) bot run through the NORMAL operation API only (walk / fire / advance_game / cycle_helper_mode /
##    place_helper / lift_helper): hand sowing -> cultivated plants -> helper seeds (ground drops) -> Gatlinger / Sprinkler / Army placed
##    at the green front -> the front moves on. No debug refill, no direct writes to play / world / enemy / helper state.
##    The same bot runs twice: with the Gatlinger and without it (same time, same bot) to compare the front speed.
## T: one short placement each on water / narrow road / wide wasteland (setup by test fixture: ground made mature, boar spawned).
## R: main regressions: save round trip (placed + carried + projectile in the air), exact 100 % after stable (upper bound), no re-invasion, pause.
## Own save namespace user://poc_saves_helpers_front/. No OS-level input.
const Config: GDScript = preload("res://scripts/poc/poc_config.gd")
const Coords: GDScript = preload("res://scripts/poc/poc_coords.gd")
const Session: GDScript = preload("res://scripts/poc/poc_session.gd")
const PocSave: GDScript = preload("res://scripts/poc/save/poc_save.gd")
const Cmp: GDScript = preload("res://tests/poc/integration/cmp.gd")
const Bot: GDScript = preload("res://tests/poc/integration/bot.gd")
const OUT: String = "res://evidence/helper/03/"
const SAVE_DIR: String = "user://poc_saves_helpers_front/"
const STAND0: Vector2i = Vector2i(78, 84)
const SAFE: Rect2i = Rect2i(76, 74, 22, 22)
const RUN_SECONDS: float = 600.0
const TILE: float = 4.0

var failures: int = 0
var passes: int = 0
var checks: Array[String] = []
var report: Dictionary = {}
var sessions: Array[RefCounted] = []

func check(name: String, ok: bool, detail: String = "") -> void:
	var line: String = "%s %s %s" % ["PASS" if ok else "FAIL", name, detail]
	checks.append(line)
	print(line)
	if ok:
		passes += 1
	else:
		failures += 1

func _init() -> void:
	_run.call_deferred()

func make_session() -> RefCounted:
	var size: Vector2i = Session.town_size()
	var made: RefCounted = Session.new(size.x, size.y)
	made.paving = Session.paving_from(made.env_tuning)
	if not made.load_combat(Session.TOWN_SETUP):
		push_error("town load failed")
	sessions.append(made)
	return made

func run_for(s: RefCounted, seconds: float) -> void:
	var left: float = seconds
	while left > 0.0:
		var piece: float = minf(left, 0.25)
		s.advance_game(piece)
		left -= piece

# ---------------------------------------------------------------- measures

func zone1_greened(s: RefCounted) -> int:
	var n: int = 0
	var st: WorldState = s.state
	for i: int in st.tile_count():
		if st.target[i] == 1 and st.zone_at(i) == 1 and st.stage[i] >= WorldState.GREENED_MIN_STAGE:
			n += 1
	return n

func safe_distance(x: int, y: int) -> float:
	var dx: int = maxi(maxi(SAFE.position.x - x, x - (SAFE.end.x - 1)), 0)
	var dy: int = maxi(maxi(SAFE.position.y - y, y - (SAFE.end.y - 1)), 0)
	return sqrt(float(dx * dx + dy * dy))

## Farthest greened zone-1 cell from the start safe zone (cells): how far the green front has come.
func front_distance(s: RefCounted) -> float:
	var best: float = 0.0
	var st: WorldState = s.state
	for y: int in st.height:
		for x: int in st.width:
			var i: int = st.index_of(x, y)
			if st.target[i] == 1 and st.stage[i] >= WorldState.GREENED_MIN_STAGE and st.zone_at(i) == 1:
				best = maxf(best, safe_distance(x, y))
	return best

# ---------------------------------------------------------------- bot parts (normal operation API)

func landing_cells(s: RefCounted, stand: Vector2i, count: int) -> Array[Vector2i]:
	var st: WorldState = s.state
	var cs: Vector2 = Bot.cpx(stand)
	var out: Array[Vector2i] = []
	for y: int in range(stand.y - 10, stand.y + 11):
		for x: int in range(stand.x - 14, stand.x + 3):
			if not st.in_bounds(x, y) or out.size() >= count:
				continue
			var i: int = st.index_of(x, y)
			var c: Vector2i = Vector2i(x, y)
			var d_px: float = Bot.cpx(c).distance_to(cs)
			if st.target[i] != 1 or st.zone_at(i) != 1 or st.stage[i] != WorldState.STAGE_EMPTY or st.occupant[i] != 0:
				continue
			if not (st.terrain[i] == Session.T_WASTE or st.terrain[i] == Session.T_PAVED) or d_px < 24.0 or d_px > 52.0 or s.shot_blocked(cs, Bot.cpx(c)):
				continue
			var spaced: bool = true
			for other: Vector2i in out:
				if absi(other.x - c.x) < 3 and absi(other.y - c.y) < 3:
					spaced = false
			if spaced:
				out.append(c)
	return out

## The reachable greened cell farthest from the safe zone that has at least 3 spots to sow in throwing range.
func front_stand(s: RefCounted, bot: RefCounted) -> Vector2i:
	var st: WorldState = s.state
	var field: PackedInt32Array = bot.field_from(bot.cell_now())
	var list: Array[Vector2i] = []
	for y: int in st.height:
		for x: int in st.width:
			var i: int = st.index_of(x, y)
			if field[i] >= 0 and field[i] <= 140 and st.target[i] == 1 and st.stage[i] >= WorldState.GREENED_MIN_STAGE and st.occupant[i] == 0:
				list.append(Vector2i(x, y))
	list.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return safe_distance(a.x, a.y) > safe_distance(b.x, b.y))
	var tried: int = 0
	for c: Vector2i in list:
		tried += 1
		if tried > 60:
			break
		if landing_cells(s, c, 3).size() >= 3:
			return c
	return Vector2i(-1, -1)

func sow_round(s: RefCounted, bot: RefCounted, count: int, with_water: bool, rec: Dictionary) -> int:
	var stand: Vector2i = front_stand(s, bot) if rec["sow_rounds"] > 0 else STAND0
	if stand.x < 0:
		stand = STAND0
	bot.go(stand, 90.0, 2.0)
	var landing: Array[Vector2i] = landing_cells(s, bot.cell_now(), count)
	var shot: int = 0
	for c: Vector2i in landing:
		if s.play.seeds < 1:
			break
		var attempts: int = 0
		while not bot.try_fire(false, Bot.cpx(c)) and attempts < 40:
			bot.frame()
			attempts += 1
		shot += 1
		bot.idle(0.4)
	if with_water:
		for c: Vector2i in landing:
			if s.play.water < 10.0:
				break
			var attempts2: int = 0
			while not bot.try_fire(true, Bot.cpx(c)) and attempts2 < 40:
				bot.frame()
				attempts2 += 1
			bot.idle(0.4)
	rec["sow_rounds"] += 1
	rec["seeds_sown_by_hand"] += shot
	return shot

## Free mature 4x4 block (all cells walkable, target, plantable, unoccupied, mature) reachable by the player. `score` maps the block origin to a number.
func find_block(s: RefCounted, bot: RefCounted, score: Callable) -> Vector2i:
	var st: WorldState = s.state
	var field: PackedInt32Array = bot.field_from(bot.cell_now())
	var best: Vector2i = Vector2i(-1, -1)
	var best_score: float = -1.0e18
	for oy: int in range(1, st.height - 5):
		for ox: int in range(1, st.width - 5):
			var ok: bool = true
			for y: int in range(oy, oy + 4):
				for x: int in range(ox, ox + 4):
					var i: int = st.index_of(x, y)
					if not (st.is_walkable(x, y) and st.target[i] == 1 and st.occupant[i] == 0 and st.stage[i] == WorldState.STAGE_MATURE and st.terrain_defs[st.terrain[i]].plantable):
						ok = false
						break
				if not ok:
					break
			if not ok or field[(oy + 2) * st.width + ox + 2] < 0 or field[(oy + 2) * st.width + ox + 2] > 140:
				continue
			var value: float = float(score.call(Vector2i(ox, oy)))
			if value > best_score:
				best_score = value
				best = Vector2i(ox, oy)
	return best

func frontier_score(origin: Vector2i) -> float:
	return safe_distance(origin.x + 2, origin.y + 2)

## Walk next to the block, select the kind with the Q key (cycle_helper_mode) and left-click (place_helper). Returns the result.
func place_at(s: RefCounted, bot: RefCounted, kind: String, origin: Vector2i) -> Dictionary:
	var centre: Vector2 = s.helpers.block_center_px(origin)
	var stand: Vector2i = bot.nearest_clear(Coords.logic_to_cell(centre))
	bot.go(stand, 90.0, 3.0)
	s.set_aim(centre)
	s.end_helper_mode()
	var guard: int = 0
	while s.helper_active_kind() != kind and guard < 6:
		s.cycle_helper_mode()
		guard += 1
	var result: Dictionary = s.place_helper(centre)
	s.end_helper_mode()
	refresh_clear(bot)
	return result

## Selects the cultivated plant `label` (the real plant-cycle key) and shoots it at a mature cell; true when a plant was placed.
func place_cultivated(s: RefCounted, bot: RefCounted, label: String, targets: Array[Vector2i]) -> bool:
	var guard: int = 0
	while s.selected_label() != label and guard < 6:
		s.cycle_plant(1)
		guard += 1
	var before: int = s.play.cultivation.plants.size()
	for target: Vector2i in targets:
		if s.play.available_seeds() < 3:
			return false
		var stand: Vector2i = bot.nearest_clear(target + Vector2i(-6, 0))
		bot.go(stand, 60.0, 3.0)
		var attempts: int = 0
		while not bot.try_fire(false, Bot.cpx(target)) and attempts < 40:
			bot.frame()
			attempts += 1
		bot.idle(1.6)
		if s.play.cultivation.plants.size() > before:
			refresh_clear(bot)
			return true
	return false

## The bot's walkability table is built once; planted blocks (cultivated / helper plants) change it, so rebuild it.
func refresh_clear(bot: RefCounted) -> void:
	var half: Vector2 = Config.player_half_px()
	for y: int in bot.height:
		for x: int in bot.width:
			bot.clear[y * bot.width + x] = 1 if Walker.is_clear(bot.s.state, Config.TILE_PX, Bot.cpx(Vector2i(x, y)), half) else 0

func nearest_pickup(s: RefCounted, bot: RefCounted, max_path: int) -> Vector2i:
	var field: PackedInt32Array = bot.field_from(bot.cell_now())
	var best: Vector2i = Vector2i(-1, -1)
	var best_d: int = 1 << 30
	for item: Dictionary in s.helpers.pickups:
		var cell: Vector2i = Coords.logic_to_cell(Vector2(float(item["x"]), float(item["y"])))
		var d: int = field[cell.y * s.state.width + cell.x]
		if d >= 0 and d <= max_path and d < best_d:
			best_d = d
			best = cell
	return best

func refill_sprinklers(s: RefCounted, bot: RefCounted, rec: Dictionary) -> bool:
	var did: bool = false
	for plant: Dictionary in s.helpers.plants:
		if String(plant["kind"]) != "sprinkler" or s.helpers.is_by_water(plant):
			continue
		if float(plant["stock"]) >= 12.0 or s.helpers._pulse_cells(plant).is_empty():
			continue
		var rect: Rect2i = s.helpers.plant_rect(plant)
		var stand: Vector2i = bot.nearest_clear(Vector2i(rect.position.x - 1, rect.position.y + 2))
		var t0: float = s.clock.elapsed
		bot.go(stand, 90.0, 3.0)
		var wait0: float = s.clock.elapsed
		while float(plant["stock"]) < 55.0 and s.clock.elapsed - wait0 < 15.0 and not bot.stopped:
			bot.idle(1.0)
		rec["spr_refill_trips"] += 1
		rec["spr_refill_seconds"] += s.clock.elapsed - t0
		did = true
	return did

func relocate_gatlinger(s: RefCounted, bot: RefCounted, rec: Dictionary) -> bool:
	var gat: Dictionary = {}
	for plant: Dictionary in s.helpers.plants:
		if String(plant["kind"]) == "gatlinger":
			gat = plant
	if gat.is_empty():
		return false
	var rect: Rect2i = s.helpers.plant_rect(gat)
	var here_score: float = frontier_score(rect.position)
	var target: Vector2i = find_block(s, bot, Callable(self, "frontier_score"))
	if target.x < 0 or frontier_score(target) < here_score + 3.0:
		return false
	var stand: Vector2i = bot.nearest_clear(Vector2i(rect.position.x - 1, rect.position.y + 2))
	bot.go(stand, 90.0, 3.0)
	var lifted: Dictionary = s.lift_helper()
	refresh_clear(bot)
	if not bool(lifted["ok"]):
		return false
	var placed: Dictionary = place_at(s, bot, "gatlinger", target)
	if not bool(placed["ok"]):
		# Put it back on the first free spot rather than leaving it in the hands.
		var again: Vector2i = find_block(s, bot, Callable(self, "frontier_score"))
		if again.x >= 0:
			placed = place_at(s, bot, "gatlinger", again)
	rec["relocations"] += 1 if bool(placed["ok"]) else 0
	rec["events"].append("t=%.1f gatlinger moved to %s (%s)" % [s.clock.elapsed, str(target), "ok" if bool(placed["ok"]) else String(placed["code"])])
	return true

## One 10-minute run. `use_gat`: false skips the Gatlinger (the comparison run).
func run_front(use_gat: bool) -> Dictionary:
	var s: RefCounted = make_session()
	var bot: RefCounted = Bot.new(s)
	bot.guard_until = RUN_SECONDS
	bot.log_every = 30.0
	var rec: Dictionary = {"use_gat": use_gat, "sow_rounds": 0, "cultivated": 0, "cultivated_failed": 0, "seeds_sown_by_hand": 0, "restock_trips": 0, "restock_wait_s": 0.0, "helper_pickup_trips": 0,
		"spr_refill_trips": 0, "spr_refill_seconds": 0.0, "relocations": 0, "placed": [], "events": [], "samples": []}
	var queue: Array[String] = []
	if use_gat:
		queue.append("gatlinger")
	queue.append("sprinkler")
	queue.append("army")
	var start_greened: int = zone1_greened(s)
	var last_sow: float = -100.0
	var last_gat_move: float = 0.0
	var next_sample: float = 0.0
	var loops: int = 0
	while s.clock.elapsed < RUN_SECONDS and not bot.stopped:
		loops += 1
		if s.clock.elapsed >= next_sample:
			next_sample += 60.0
			rec["samples"].append({"t": snappedf(s.clock.elapsed, 0.1), "zone1_greened": zone1_greened(s), "front_m": snappedf(front_distance(s) * 0.4, 0.1), "helper_seeds": s.helpers.seeds, "seeds": s.play.seeds, "hp": s.play.hp, "boars": s.enemies.boars.size(), "helpers": s.helpers.plants.size(), "kills": s.helpers.kills_total, "seeded": s.helpers.seeded_total})
		if s.play.health.downed:
			bot.frame()
			continue
		# 00) a plant still in the hands (e.g. the player was knocked down while moving it) is put down first
		if s.helpers.is_carrying():
			var put_down: Vector2i = find_block(s, bot, Callable(self, "frontier_score"))
			var carried_kind: String = String(s.helpers.carried["kind"])
			var again: Dictionary = place_at(s, bot, carried_kind, put_down) if put_down.x >= 0 else {"ok": false, "code": "no_block"}
			rec["events"].append("t=%.1f put down carried %s at %s -> %s %s" % [s.clock.elapsed, carried_kind, str(put_down), str(again["ok"]), String(again["code"])])
			if not bool(again["ok"]):
				bot.idle(2.0)
			continue
		# 0) the very first thing: hand sowing next to the start zone, then cultivated plants on its mature ground
		if rec["sow_rounds"] == 0:
			sow_round(s, bot, 4, true, rec)
			continue
		if int(rec["cultivated"]) < 6 and int(rec["cultivated_failed"]) < 6 and s.play.seeds >= 3 and s.clock.elapsed < 400.0:
			var label: String = "にんじん" if int(rec["cultivated"]) % 2 == 0 else "キウイ"
			var spots: Array[Vector2i] = []
			for k: int in 12:
				var n: int = (k + 2 * int(rec["cultivated"])) % 12
				spots.append(Vector2i(79 + (n % 3) * 3, 76 + n * 2))
			if place_cultivated(s, bot, label, spots):
				rec["cultivated"] += 1
				rec["events"].append("t=%.1f cultivated %s (%d)" % [s.clock.elapsed, label, int(rec["cultivated"])])
				continue
			rec["cultivated_failed"] += 1
		# 1) place the next helper when the seeds are there
		if not queue.is_empty() and s.helpers.seeds >= int(s.helpers.kind_def(queue[0])["cost"]):
			var origin: Vector2i = find_block(s, bot, Callable(self, "frontier_score"))
			if origin.x >= 0:
				var result: Dictionary = place_at(s, bot, queue[0], origin)
				rec["events"].append("t=%.1f place %s at %s -> %s %s" % [s.clock.elapsed, queue[0], str(origin), str(result["ok"]), String(result["code"])])
				if bool(result["ok"]):
					rec["placed"].append({"kind": queue[0], "t": snappedf(s.clock.elapsed, 0.1), "origin": [origin.x, origin.y]})
					if queue[0] == "gatlinger":
						last_gat_move = s.clock.elapsed
					queue.remove_at(0)
					continue
		# 2) pick up a helper seed lying around
		if not queue.is_empty() and not s.helpers.pickups.is_empty() and s.helpers.seeds < 7:
			var pickup: Vector2i = nearest_pickup(s, bot, 70)
			if pickup.x >= 0:
				var before: int = s.helpers.seeds
				bot.go(pickup, 40.0, 3.0)
				bot.idle(0.3)
				rec["helper_pickup_trips"] += 1
				rec["events"].append("t=%.1f helper seed pickup %s: %d -> %d" % [s.clock.elapsed, str(pickup), before, s.helpers.seeds])
				continue
		# 3) sprinkler refill (manual refill away from the water)
		if refill_sprinklers(s, bot, rec):
			continue
		# 4) move the Gatlinger to the new front
		if use_gat and s.clock.elapsed - last_gat_move >= 100.0:
			last_gat_move = s.clock.elapsed
			if relocate_gatlinger(s, bot, rec):
				continue
		# 5) own seeds low: back to a seed source
		if s.play.seeds < 5:
			rec["restock_trips"] += 1
			rec["restock_wait_s"] += bot.restock(14, 120.0)
			continue
		# 6) sow at the front
		if s.play.seeds >= 8 and s.clock.elapsed - last_sow >= 25.0:
			last_sow = s.clock.elapsed
			sow_round(s, bot, 6, s.play.water >= 60.0, rec)
			continue
		bot.idle(2.0)
	var end_green: int = zone1_greened(s)
	var h: RefCounted = s.helpers
	rec["end"] = {"t": snappedf(s.clock.elapsed, 0.1), "zone1_greened_start": start_greened, "zone1_greened_end": end_green, "zone1_gain": end_green - start_greened,
		"front_m": snappedf(front_distance(s) * 0.4, 0.1), "greened_total": s.state.greened_count, "pct": s.greening_percent(),
		"cultivated_plants": s.play.cultivation.plants.size(), "cultivated_mature": s.play.cultivation.plants.filter(func(p: CultivatedPlant) -> bool: return p.mature).size(), "helper_dropped": h.dropped_total, "helper_collected": h.collected_total, "helper_seeds_left": h.seeds, "helpers_alive": h.plants.size(), "helpers_lost": h.lost_total,
		"gat_seeded": h.seeded_total, "gat_wasted": h.wasted_total, "gat_shots": h.fire_serial, "spr_pulses": h.pulses_total, "army_kills": h.kills_total,
		"boars_alive": s.enemies.boars.size(), "boars_spawned": s.enemies.total_spawned, "boars_killed_total": s.enemies.total_killed, "player_hits": s.play.health.hit_count, "downs": bot.down_times.size(),
		"seed_shots_player": bot.seed_shots, "water_shots": bot.water_shots, "walked_m": snappedf(bot.walked_px * Config.M_PER_LOGIC_PX, 0.1), "frames": bot.frames}
	rec["plants"] = []
	for plant: Dictionary in h.plants:
		rec["plants"].append({"kind": String(plant["kind"]), "hp": int(plant["hp"]), "stock": snappedf(float(plant["stock"]), 0.1), "x": int(plant["x"]), "y": int(plant["y"])})
	rec["bot_events"] = Array(bot.events)
	rec["rows"] = bot.rows
	rec["session"] = s
	rec["bot"] = bot
	return rec

# ---------------------------------------------------------------- short placement checks (fixture setup)

func kill_enemies(s: RefCounted) -> void:
	for nest: Nest in s.enemies.nests:
		s.enemies.damage_nest(nest, 999)
	while not s.enemies.boars.is_empty():
		s.enemies.damage_boar(s.enemies.boars[0], 999)

func make_mature(s: RefCounted, rect: Rect2i) -> void:
	for y: int in range(rect.position.y, rect.end.y):
		for x: int in range(rect.position.x, rect.end.x):
			var i: int = s.state.index_of(x, y)
			if s.state.target[i] == 1 and s.state.occupant[i] == 0:
				s.state.set_stage(i, WorldState.STAGE_MATURE)

func block_center(origin: Vector2i) -> Vector2:
	return (Vector2(origin) + Vector2(2, 2)) * TILE

func put(s: RefCounted, origin: Vector2i, kind_index: int) -> Dictionary:
	make_mature(s, Rect2i(origin, Vector2i(4, 4)))
	s.helpers.seeds = 10
	s.position = block_center(origin)
	s.set_aim(block_center(origin))
	s.helper_mode = kind_index
	var r: Dictionary = s.place_helper()
	s.helper_mode = -1
	s.position = Vector2(-1000, -1000)
	return s.helpers.plant_by_uid(int(r["uid"]))

func new_boar(s: RefCounted, at: Vector2, hp: int = 3) -> Boar:
	var boar: Boar = Boar.new()
	boar.id = 9100 + s.enemies.boars.size()
	boar.zone = 1
	boar.hp = hp
	boar.pos = at
	s.enemies.boars.append(boar)
	return boar

func block_ok(s: RefCounted, ox: int, oy: int) -> bool:
	var st: WorldState = s.state
	for y: int in range(oy, oy + 4):
		for x: int in range(ox, ox + 4):
			if not st.in_bounds(x, y):
				return false
			var i: int = st.index_of(x, y)
			if not (st.is_walkable(x, y) and st.target[i] == 1 and st.occupant[i] == 0 and st.terrain_defs[st.terrain[i]].plantable):
				return false
	return true

## Walkable cells in the (2n+1)^2 square around the block centre: small = a narrow road, large = open ground.
func openness(s: RefCounted, ox: int, oy: int, n: int) -> int:
	var count: int = 0
	for y: int in range(oy + 2 - n, oy + 2 + n + 1):
		for x: int in range(ox + 2 - n, ox + 2 + n + 1):
			if s.state.in_bounds(x, y) and s.state.is_walkable(x, y):
				count += 1
	return count

func in_range_free_cells(s: RefCounted, plant: Dictionary) -> int:
	var h: RefCounted = s.helpers
	var centre: Vector2 = h.plant_center_px(plant)
	var radius: float = float(h.kind_def("gatlinger")["radius_px"])
	var n: int = 0
	for y: int in range(maxi(floori((centre.y - radius) / TILE), 0), mini(floori((centre.y + radius) / TILE), s.state.height - 1) + 1):
		for x: int in range(maxi(floori((centre.x - radius) / TILE), 0), mini(floori((centre.x + radius) / TILE), s.state.width - 1) + 1):
			var to: Vector2 = Vector2((x + 0.5) * TILE, (y + 0.5) * TILE)
			if to.distance_to(centre) <= radius and s.state.can_plant(s.state.index_of(x, y)) and not s.shot_blocked(centre, to):
				n += 1
	return n

## Free greenable cells (with a clear line) in a Gatlinger's range at `origin`, on a fresh town with only its own block made mature.
func gat_free_at(origin: Vector2i) -> int:
	var fresh: RefCounted = make_session()
	kill_enemies(fresh)
	var plant: Dictionary = put(fresh, origin, 0)
	return in_range_free_cells(fresh, plant)

func terrain_checks() -> void:
	var s: RefCounted = make_session()
	kill_enemies(s)
	var st: WorldState = s.state
	var h: RefCounted = s.helpers
	# --- find the three spots
	var water: Vector2i = Vector2i(-1, -1)
	var narrow: Vector2i = Vector2i(-1, -1)
	var wide: Vector2i = Vector2i(-1, -1)
	var narrow_open: int = 1 << 30
	var wide_open: int = -1
	for oy: int in range(2, st.height - 6):
		for ox: int in range(2, st.width - 6):
			if not block_ok(s, ox, oy):
				continue
			if water.x < 0 and h.is_by_water({"x": ox, "y": oy}) and oy > 40 and oy < 66:
				water = Vector2i(ox, oy)
			var o: int = openness(s, ox, oy, 8)
			# the narrow road must not be a dead corner: keep blocks with a clear 4x4 and some room around (> 90 walkable of 289)
			if ox >= 10 and oy >= 10 and ox <= st.width - 16 and oy <= st.height - 16 and o > 90 and o < narrow_open and s.state.zone_at(st.index_of(ox, oy)) == 1 and not SAFE.grow(6).has_point(Vector2i(ox, oy)):
				narrow_open = o
				narrow = Vector2i(ox, oy)
			if o == 289 and o > wide_open and st.terrain[st.index_of(ox, oy)] == Session.T_WASTE and not SAFE.grow(6).has_point(Vector2i(ox, oy)):
				wide_open = o
				wide = Vector2i(ox, oy)
	report["spots"] = {"water": [water.x, water.y], "narrow": [narrow.x, narrow.y, narrow_open], "wide": [wide.x, wide.y, wide_open]}
	check("T0.three_spots_found", water.x >= 0 and narrow.x >= 0 and wide.x >= 0, str(report["spots"]))
	# --- water: a Sprinkler by the water runs without refill
	var spr: Dictionary = put(s, water, 1)
	check("T1.sprinkler_placed_by_water", not spr.is_empty() and h.is_by_water(spr), "origin %s" % str(water))
	var seeded: int = 0
	var centre: Vector2 = h.plant_center_px(spr)
	for y: int in range(0, st.height):
		for x: int in range(0, st.width):
			var i: int = st.index_of(x, y)
			if Vector2((x + 0.5) * TILE, (y + 0.5) * TILE).distance_to(centre) <= 24.0 and st.can_plant(i) and seeded < 12:
				st.set_stage(i, WorldState.STAGE_SEED)
				seeded += 1
	var stock0: float = float(spr["stock"])
	run_for(s, 60.0)
	var wet1: int = 0
	for i: int in st.tile_count():
		wet1 += 1 if st.moisture[i] > 0 and st.stage[i] >= WorldState.STAGE_SEED and st.stage[i] <= WorldState.STAGE_SPROUT2 else 0
	check("T2.sprinkler_by_water_works_without_refill", h.pulses_total >= 10 and float(spr["stock"]) == stock0 and seeded >= 4, "seeds=%d pulses=%d in 60 s, stock %.0f -> %.0f, wet growing cells=%d" % [seeded, h.pulses_total, stock0, float(spr["stock"]), wet1])
	# --- narrow road: an Army holds the corridor
	var s2: RefCounted = make_session()
	kill_enemies(s2)
	var h2: RefCounted = s2.helpers
	var army: Dictionary = put(s2, narrow, 2)
	var home: Vector2 = h2.plant_center_px(army)
	var radius: float = float(h2.kind_def("army")["radius_px"])
	var spot: Vector2 = Vector2.ZERO
	for k: int in 16:
		var p: Vector2 = home + Vector2(cos(TAU * k / 16.0), sin(TAU * k / 16.0)) * radius * 0.7
		if Walker.is_clear(s2.state, 4, p, Vector2(1.0, 1.0)) and not s2.shot_blocked(home, p):
			spot = p
			break
	var boar: Boar = new_boar(s2, spot)
	var t_kill: float = -1.0
	for step: int in 200:
		h2.advance(0.1, Vector2(-1000, -1000), true)
		if t_kill < 0.0 and not s2.enemies.boars.has(boar):
			t_kill = float(step + 1) * 0.1
	check("T3.army_in_narrow_road_kills_boar", not army.is_empty() and spot != Vector2.ZERO and t_kill > 0.0 and h2.kills_total == 1 and h2.unit_pos(army).distance_to(home) < 1.0, "openness %d/289, killed after %.1f s, back at post %.2f px" % [narrow_open, t_kill, h2.unit_pos(army).distance_to(home)])
	# --- wide wasteland: a Gatlinger sows around it; narrow gives it fewer targets
	var s3: RefCounted = make_session()
	kill_enemies(s3)
	var h3: RefCounted = s3.helpers
	make_mature(s3, Rect2i(wide.x - 8, wide.y - 8, 20, 20))
	var gat: Dictionary = put(s3, wide, 0)
	var free_wide: int = gat_free_at(wide)
	var shots0: int = h3.fire_serial
	run_for(s3, 60.0)
	var free_narrow: int = gat_free_at(narrow)
	check("T4.gatlinger_on_wide_wasteland_sows", not gat.is_empty() and h3.seeded_total >= 10 and h3.fire_serial > shots0, "free greenable cells in range %d, shots=%d seeded=%d wasted=%d in 60 s" % [free_wide, h3.fire_serial, h3.seeded_total, h3.wasted_total])
	report["terrain"] = {"water_pulses_60s": h.pulses_total, "narrow_kill_s": t_kill, "wide_free_cells": free_wide, "narrow_free_cells_same_radius": free_narrow, "wide_gat_seeded_60s": h3.seeded_total, "wide_gat_shots": h3.fire_serial - shots0}
	check("T5.narrow_road_has_fewer_gatlinger_targets_than_wide", free_narrow >= 0 and free_narrow < free_wide, "in-range free greenable cells: narrow %d vs wide %d" % [free_narrow, free_wide])

# ---------------------------------------------------------------- regressions

func start_patch_edge(s: RefCounted) -> Vector2i:
	var st: WorldState = s.state
	for ox: int in range(1, st.width - 5):
		for oy: int in range(1, st.height - 5):
			var ok: bool = true
			for y: int in range(oy, oy + 4):
				for x: int in range(ox, ox + 4):
					var i: int = st.index_of(x, y)
					ok = ok and st.is_walkable(x, y) and st.target[i] == 1 and st.occupant[i] == 0 and st.stage[i] == WorldState.STAGE_MATURE
			if ok:
				return Vector2i(ox, oy + 4)
	return Vector2i(-1, -1)

func load_slot() -> Dictionary:
	return PocSave.load_slot(SAVE_DIR, false, Callable(self, "make_session"))

func regress_save() -> RefCounted:
	var s: RefCounted = make_session()
	kill_enemies(s)
	var h: RefCounted = s.helpers
	s.position = Vector2(-1000, -1000)
	var origin: Vector2i = start_patch_edge(s)
	make_mature(s, Rect2i(origin.x - 8, origin.y - 8, 20, 20))
	put(s, origin, 0)
	put(s, origin + Vector2i(-6, 0), 1)
	put(s, origin + Vector2i(0, 6), 2)
	s.position = Coords.cell_center_logic(s.placement.player_start_cell)
	var guard: int = 0
	while h.flights.is_empty() and guard < 240:
		s.advance_game(0.25)
		guard += 1
	var in_air: int = h.flights.size()
	var army_plant: Dictionary = {}
	for plant: Dictionary in h.plants:
		if String(plant["kind"]) == "army":
			army_plant = plant
	var carried_ok: bool = false
	if not army_plant.is_empty():
		var rect: Rect2i = h.plant_rect(army_plant)
		s.position = Coords.cell_center_logic(Vector2i(rect.position.x - 1, rect.position.y + 2))
		carried_ok = bool(s.lift_helper()["ok"]) and h.is_carrying()
	check("R1a.state_has_placed_carried_and_flight", h.plants.size() == 2 and carried_ok and in_air > 0, "placed=%d carried=%s flights in the air=%d" % [h.plants.size(), str(h.is_carrying()), in_air])
	var saved: Dictionary = PocSave.save(s, SAVE_DIR, {})
	var loaded: Dictionary = load_slot()
	check("R1b.save_load_ok", bool(saved["ok"]) and bool(loaded["ok"]), String(loaded.get("reason", "")))
	if not bool(loaded["ok"]):
		return s
	var t: RefCounted = loaded["session"]
	var diff0: String = Cmp.same_state(s, t)
	check("R1c.restored_state_identical", diff0 == "" and t.helpers.is_carrying() and t.helpers.flights.size() == in_air and t.helpers.plants.size() == h.plants.size(), "diff=[%s] carried=%s flights=%d plants=%d" % [diff0, str(t.helpers.is_carrying()), t.helpers.flights.size(), t.helpers.plants.size()])
	run_for(s, 30.0)
	run_for(t, 30.0)
	var diff1: String = Cmp.same_state(s, t)
	check("R1d.runs_on_identically_30s", diff1 == "", "diff=[%s] greened %d vs %d, seeded %d vs %d" % [diff1, s.state.greened_count, t.state.greened_count, h.seeded_total, t.helpers.seeded_total])
	# put the carried plant down again in the original (to confirm that the loaded copy can place it)
	var free: Vector2i = Vector2i(-1, -1)
	var st: WorldState = t.state
	for oy: int in range(1, st.height - 5):
		for ox: int in range(1, st.width - 5):
			if free.x < 0:
				var ok: bool = true
				for y: int in range(oy, oy + 4):
					for x: int in range(ox, ox + 4):
						var i: int = st.index_of(x, y)
						ok = ok and st.is_walkable(x, y) and st.target[i] == 1 and st.occupant[i] == 0 and st.stage[i] == WorldState.STAGE_MATURE
				if ok:
					free = Vector2i(ox, oy)
	t.position = Coords.cell_center_logic(Vector2i(free.x + 2, free.y + 2))
	t.set_aim(t.helpers.block_center_px(free))
	t.cycle_helper_mode()
	var replaced: Dictionary = t.place_helper(t.helpers.block_center_px(free))
	t.end_helper_mode()
	check("R1e.carried_plant_can_be_placed_after_load", bool(replaced["ok"]) and not t.helpers.is_carrying(), "%s" % str(replaced))
	return s

func regress_hundred(rep: Dictionary) -> void:
	var s: RefCounted = make_session()
	var h: RefCounted = s.helpers
	s.enemy_tuning.contact_damage = 0
	var bound: float = s.far.completion_bound_seconds()
	for nest: Nest in s.enemies.nests:
		s.enemies.damage_nest(nest, 99)
	var guard: int = 0
	while not s.enemies.boars.is_empty() and guard < 400:
		s.enemies.damage_boar(s.enemies.boars[0], 99)
		guard += 1
		s.advance_game(0.25)
	var origin: Vector2i = start_patch_edge(s)
	put(s, origin, 0)
	put(s, origin + Vector2i(-6, 0), 1)
	put(s, origin + Vector2i(0, 6), 2)
	s.position = Coords.cell_center_logic(s.placement.player_start_cell)
	check("R2a.three_kinds_placed", h.plants.size() == 3, str(h.plants.size()))
	var steps: int = 0
	while s.state.zone_state[1] < WorldState.ZONE_STABLE and steps < 4000:
		s.advance_game(0.25)
		steps += 1
	var t_stable: float = float((s.zone_times[1] as Dictionary).get(WorldState.ZONE_STABLE, s.clock.elapsed))
	var spawned: int = s.enemies.total_spawned
	var invaded: int = 0
	var t_done: float = -1.0
	var over_cap: int = 0
	while s.clock.elapsed <= t_stable + bound + 5.0:
		s.advance_game(0.25)
		if not s.enemies.boars.is_empty() or s.enemies.total_spawned != spawned:
			invaded += 1
		if s.state.greened_count > s.state.target_count:
			over_cap += 1
		if s.state.greened_count == s.state.target_count:
			t_done = s.clock.elapsed - t_stable
			break
	check("R2b.exact_100_within_bound_with_helpers_working", t_done >= 0.0 and t_done <= bound and s.greening_percent() == 100 and s.state.counters_consistent() and over_cap == 0, "stable at %.1f s, 100%% after %.1f s of bound %.1f s, greened %d/%d, shots=%d seeded=%d pulses=%d" % [t_stable, t_done, bound, s.state.greened_count, s.state.target_count, h.fire_serial, h.seeded_total, h.pulses_total])
	run_for(s, 60.0)
	check("R2c.no_reinvasion_and_helpers_stand", invaded == 0 and s.enemies.boars.is_empty() and s.enemies.total_spawned == spawned and h.plants.size() == 3 and s.greening_percent() == 100, "invaded steps=%d spawned=%d plants=%d" % [invaded, s.enemies.total_spawned, h.plants.size()])
	rep["hundred"] = {"t_stable": t_stable, "after_stable_s": t_done, "bound_s": bound}

func regress_pause(s: RefCounted) -> void:
	var h: RefCounted = s.helpers
	var before_hash: String = JSON.stringify(h.to_dict())
	var greened: int = s.state.greened_count
	var elapsed: float = s.clock.elapsed
	var boars: int = s.enemies.boars.size()
	var pos: Vector2 = s.position
	s.paused = true
	run_for(s, 60.0)
	var frozen: bool = JSON.stringify(h.to_dict()) == before_hash and s.state.greened_count == greened and s.clock.elapsed == elapsed and s.enemies.boars.size() == boars and s.position == pos
	var placed: Dictionary = s.place_helper(Vector2(100, 100))
	s.paused = false
	run_for(s, 3.0)
	check("R3.pause_freezes_helpers_and_resumes", frozen and not bool(placed["ok"]) and JSON.stringify(h.to_dict()) != before_hash, "frozen=%s place while paused=%s" % [str(frozen), String(placed["code"])])

func slim(rec: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for key: String in ["use_gat", "sow_rounds", "cultivated", "cultivated_failed", "seeds_sown_by_hand", "restock_trips", "restock_wait_s", "helper_pickup_trips", "spr_refill_trips", "spr_refill_seconds", "relocations", "placed", "events", "samples", "end", "plants", "bot_events"]:
		out[key] = rec[key]
	return out

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	for file: String in DirAccess.get_files_at(SAVE_DIR):
		DirAccess.remove_absolute(SAVE_DIR + file)
	# --- spread starting from the safe patch (the HLP-03 fix)
	var s0: RefCounted = make_session()
	var g0: int = s0.state.greened_count
	run_for(s0, 120.0)
	check("F0.safe_patch_is_the_start_of_natural_spread", g0 == 484 and s0.state.greened_count > g0 + 150 and s0.spread.mature_near.size() == s0.state.tile_count(), "greened %d -> %d in 120 s" % [g0, s0.state.greened_count])
	report["natural_120s"] = {"start": g0, "end": s0.state.greened_count}
	# --- F: the two 10-minute runs
	var with_gat: Dictionary = run_front(true)
	print("RUN A done: ", JSON.stringify(with_gat["end"]))
	var no_gat: Dictionary = run_front(false)
	print("RUN B done: ", JSON.stringify(no_gat["end"]))
	var ea: Dictionary = with_gat["end"]
	var eb: Dictionary = no_gat["end"]
	var kinds: Array = []
	for p: Dictionary in with_gat["placed"]:
		kinds.append(String(p["kind"]))
	check("F1.bot_placed_all_three_with_normal_input", kinds.has("gatlinger") and kinds.has("sprinkler") and kinds.has("army"), "placements %s; helper seeds dropped=%d collected=%d" % [str(with_gat["placed"]), int(ea["helper_dropped"]), int(ea["helper_collected"])])
	check("F2.gatlinger_sowed_for_the_player", int(ea["gat_seeded"]) > 0 and int(ea["gat_shots"]) > 0, "shots=%d seeded=%d wasted=%d relocations=%d" % [int(ea["gat_shots"]), int(ea["gat_seeded"]), int(ea["gat_wasted"]), int(with_gat["relocations"])])
	check("F3.front_moved_in_both_runs", int(ea["zone1_gain"]) > 0 and int(eb["zone1_gain"]) > 0, "zone-1 greened gain with=%d without=%d, front %.1f m vs %.1f m" % [int(ea["zone1_gain"]), int(eb["zone1_gain"]), float(ea["front_m"]), float(eb["front_m"])])
	var ratio: float = float(ea["zone1_gain"]) / maxf(float(eb["zone1_gain"]), 1.0)
	print("INFO front speed ratio (zone-1 greened gain, with/without gatlinger) = %.2f" % ratio)
	report["with_gatlinger"] = slim(with_gat)
	report["without_gatlinger"] = slim(no_gat)
	report["front_speed_ratio_zone1_gain"] = ratio
	# --- T: short placements
	terrain_checks()
	# --- R: regressions (save on the run-A session, 100 % on a fresh one, pause on the run-A session)
	var sa: RefCounted = regress_save()
	regress_hundred(report)
	regress_pause(sa)
	for file: String in DirAccess.get_files_at(SAVE_DIR):
		DirAccess.remove_absolute(SAVE_DIR + file)
	for made: RefCounted in sessions:
		made.close()
	report["checks"] = checks
	report["passes"] = passes
	report["failures"] = failures
	var file: FileAccess = FileAccess.open(ProjectSettings.globalize_path(OUT + "front_report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  ", false, true))
	file.close()
	print("RESULT passes=%d failures=%d" % [passes, failures])
	quit(1 if failures > 0 else 0)
