extends RefCounted
## HLP-01 PoC-side helper seeds (おたすけたね) and helper plants (おたすけ植物). Display-free; owned by PocSession and advanced only
## from its single loop (advance_game), so a paused game freezes drops, collection and damage and nothing is banked.
##
## - Helper seeds: a count (cap `seeds_max`) and seed items lying on the ground. Sources: (a) every `drop_interval` game seconds each
##   mature cultivated plant rolls `drop_chance` with a fixed-seed random draw (state = `ticks`, saved), (b) a destroyed nest drops
##   `nest_reward` items. The player collects items by walking close.
## - Helper plants: 4x4 cell blocks held in WorldState.occupy (owner OWNER_BAND_HELPER + uid). The occupied cells are mature ground
##   before and stay mature, so they count as greened and the counters never change. Only a placed block, its hp and its damage
##   cooldown are state. HLP-02 adds the working of each kind (see _work): the Gatlinger takes seeds from nearby mature cells into an
##   inventory and shoots them as small flights onto free greenable cells; the Sprinkler waters seeds / sprouts (free next to water,
##   else from a refillable inventory); the Army unit defends the spot it was placed on.
## - Lift (E near one) releases the occupancy and keeps the plant as `carried` (one at a time); placing it again costs nothing.
## Nothing here touches scripts/play, scripts/world or scripts/enemy (they are only read; the enemy field is read for boar positions).
const SETUP_PATH: String = "res://data/poc/helpers.json"
const FOOTPRINT: int = 4
## Work is advanced in pieces of at most this many game seconds (any larger step is split; the result does not depend on the split).
const WORK_STEP: float = 0.25
const STATE_VERSION: int = 2

var state: WorldState
var play: PlayState
var enemies: EnemyField
var tile_px: int = 4
## Callable(text: String) -> void for short HUD messages (the session's say()).
var notify: Callable = Callable()

# Data (data/poc/helpers.json). Tests may change these members after construction.
var kinds: Array[Dictionary] = []
var seeds_max: int = 20
var debug_refill_seeds: int = 6
var rng_seed: int = 1
var drop_interval: float = 20.0
var drop_chance: float = 0.1
var ground_cap: int = 10
var pickup_lifetime: float = 300.0
var ring_min: float = 5.0
var ring_max: float = 7.0
var collect_radius: float = 12.0
var nest_reward: int = 3
var nest_ring_min: float = 6.0
var nest_ring_max: float = 14.0
var max_helpers: int = 6
var place_range_px: float = 40.0
var lift_range_px: float = 24.0
var damage_interval: float = 1.0
var damage_amount: int = 1
var contact_px: float = 6.0
## HLP-02 working values per kind (data/poc/helpers.json "gatlinger" / "sprinkler" / "army").
var gat: Dictionary = {}
var spr: Dictionary = {}
var army: Dictionary = {}
## Callable(from_px, to_px) -> bool: the segment crosses a cell that stops shots (the session's shot_blocked). Empty = nothing blocks.
var blocker: Callable = Callable()

# State (saved).
var seeds: int = 0
var time: float = 0.0
var ticks: int = 0
var next_uid: int = 1
## Seed items on the ground: {x, y, age}.
var pickups: Array[Dictionary] = []
## Placed helper plants: {uid, kind: String, x, y (top-left cell), hp, cooldown}.
var plants: Array[Dictionary] = []
## The lifted plant ({uid, kind, hp}) or {} when nothing is carried.
var carried: Dictionary = {}
## Observability (saved as "stats").
var dropped_total: int = 0
var collected_total: int = 0
var nest_rewards_total: int = 0
var lost_total: int = 0
## HLP-02 state (saved): seed flights {ox, oy, cx, cy (target cell), age, dur}, the fixed-rng position of the Gatlinger, counters.
var flights: Array[Dictionary] = []
var fire_serial: int = 0
var seeded_total: int = 0
var wasted_total: int = 0
var pulses_total: int = 0
var kills_total: int = 0
## Display-only (not saved): seconds a Sprinkler pulse stays visible, by uid.
var pulse_fx: Dictionary = {}

func _init(world_state: WorldState, play_state: PlayState, tile_size: int, path: String = SETUP_PATH) -> void:
	state = world_state
	play = play_state
	tile_px = tile_size
	_read_setup(path)

func _read_setup(path: String) -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	var data: Dictionary = parsed if parsed is Dictionary else {}
	var seed_cfg: Dictionary = data.get("seeds", {})
	seeds = int(seed_cfg.get("start", 0))
	seeds_max = int(seed_cfg.get("max", 20))
	debug_refill_seeds = int(seed_cfg.get("debug_refill", 6))
	var drop: Dictionary = data.get("drop", {})
	rng_seed = int(drop.get("rng_seed", 1))
	drop_interval = float(drop.get("interval_seconds", 20.0))
	drop_chance = float(drop.get("chance", 0.1))
	ground_cap = int(drop.get("ground_cap", 10))
	pickup_lifetime = float(drop.get("lifetime_seconds", 300.0))
	ring_min = float(drop.get("ring_min_px", 5.0))
	ring_max = float(drop.get("ring_max_px", 7.0))
	collect_radius = float(drop.get("collect_radius_px", 12.0))
	nest_reward = int(drop.get("nest_reward", 3))
	nest_ring_min = float(drop.get("nest_ring_min_px", 6.0))
	nest_ring_max = float(drop.get("nest_ring_max_px", 14.0))
	var place: Dictionary = data.get("place", {})
	max_helpers = int(place.get("max_helpers", 6))
	place_range_px = float(place.get("range_m", 4.0)) / 0.1
	lift_range_px = float(place.get("lift_range_m", 2.4)) / 0.1
	var damage: Dictionary = data.get("damage", {})
	damage_interval = float(damage.get("interval_seconds", 1.0))
	damage_amount = int(damage.get("amount", 1))
	contact_px = float(damage.get("contact_px", 6.0))
	gat = _num_dict(data.get("gatlinger", {}), {"stock_max": 12.0, "stock_start": 0.0, "receive_interval": 2.0, "min_mature_cells": 8.0, "fire_interval": 2.5, "retry_interval": 0.5, "flight_speed_px": 60.0, "pioneer_window": 2.0, "tries": 24.0})
	spr = _num_dict(data.get("sprinkler", {}), {"stock_max": 60.0, "stock_start": 30.0, "pulse_interval": 3.0, "pulse_cost": 10.0, "moisture_add": 40.0, "refill_per_second": 20.0, "refill_range_px": 24.0, "fx_seconds": 0.8})
	army = _num_dict(data.get("army", {}), {"damage": 2.0, "attack_interval": 0.8, "unit_speed_px": 24.0, "reach_px": 6.0})
	kinds.clear()
	for entry: Variant in data.get("kinds", []):
		var source: Dictionary = entry
		kinds.append({"key": String(source["key"]), "name": String(source["name"]), "cost": int(source["cost"]), "hp": int(source["hp"]), "radius_m": float(source["radius_m"]), "radius_px": float(source["radius_m"]) / 0.1, "color": String(source["color"])})

static func _num_dict(source: Variant, defaults: Dictionary) -> Dictionary:
	var out: Dictionary = defaults.duplicate()
	if source is Dictionary:
		for key: Variant in source:
			if out.has(key):
				out[key] = float(source[key])
	return out

## Connects the nest reward. Setup-time only (PocSession._build_enemies).
func attach_enemies(field: EnemyField) -> void:
	enemies = field
	field.nest_defeated.connect(_on_nest_defeated)

# ---------------------------------------------------------------- kinds

func kind_index(key: String) -> int:
	for i: int in kinds.size():
		if String(kinds[i]["key"]) == key:
			return i
	return -1

func kind_def(key: String) -> Dictionary:
	var i: int = kind_index(key)
	return kinds[i] if i >= 0 else {}

func owner_of(uid: int) -> int:
	return WorldState.OWNER_BAND_HELPER + uid

func is_carrying() -> bool:
	return not carried.is_empty()

func total_count() -> int:
	return plants.size() + (1 if is_carrying() else 0)

func plant_rect(plant: Dictionary) -> Rect2i:
	return Rect2i(int(plant["x"]), int(plant["y"]), FOOTPRINT, FOOTPRINT)

## Footprint centre in logical px.
func plant_center_px(plant: Dictionary) -> Vector2:
	return (Vector2(int(plant["x"]), int(plant["y"])) + Vector2(FOOTPRINT, FOOTPRINT) * 0.5) * float(tile_px)

func plant_by_uid(uid: int) -> Dictionary:
	for plant: Dictionary in plants:
		if int(plant["uid"]) == uid:
			return plant
	return {}

func _say(text: String) -> void:
	if notify.is_valid():
		notify.call(text)

static func rect_distance(point: Vector2, rect: Rect2) -> float:
	var dx: float = maxf(maxf(rect.position.x - point.x, point.x - rect.end.x), 0.0)
	var dy: float = maxf(maxf(rect.position.y - point.y, point.y - rect.end.y), 0.0)
	return sqrt(dx * dx + dy * dy)

func _rect_px(rect: Rect2i) -> Rect2:
	return Rect2(Vector2(rect.position) * float(tile_px), Vector2(rect.size) * float(tile_px))

# ---------------------------------------------------------------- seeds

func add_seeds(amount: int) -> int:
	var before: int = seeds
	seeds = clampi(seeds + amount, 0, seeds_max)
	return seeds - before

func debug_refill() -> void:
	add_seeds(debug_refill_seeds)

func _spawn_item(center: Vector2, ring_min_px: float, ring_max_px: float, rng: RandomNumberGenerator) -> void:
	var angle: float = rng.randf() * TAU
	var radius: float = rng.randf_range(ring_min_px, ring_max_px)
	var at: Vector2 = center + Vector2(cos(angle), sin(angle)) * radius
	var cell: Vector2i = Vector2i(floori(at.x / tile_px), floori(at.y / tile_px))
	if not state.is_walkable(cell.x, cell.y):
		at = center
	pickups.append({"x": at.x, "y": at.y, "age": 0.0})

func _roll_drops() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	for plant: CultivatedPlant in play.cultivation.plants:
		if not plant.mature:
			continue
		# One draw per (tick, plant): the same state gives the same result however the time was advanced.
		rng.seed = rng_seed * 1000003 + ticks * 7919 + plant.uid * 104729
		var lucky: bool = rng.randf() < drop_chance
		if lucky and pickups.size() < ground_cap:
			_spawn_item(plant.center_tiles() * float(tile_px), ring_min, ring_max, rng)
			dropped_total += 1

func _on_nest_defeated(nest: Nest) -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = rng_seed * 1000003 + nest.id * 15485863
	for i: int in nest_reward:
		_spawn_item(nest.center_px(tile_px), nest_ring_min, nest_ring_max, rng)
	nest_rewards_total += nest_reward
	_say("巣を壊した！　おたすけたねが落ちた（%d個）" % nest_reward)

# ---------------------------------------------------------------- placement

func origin_for(aim_logic: Vector2) -> Vector2i:
	return Vector2i(roundi(aim_logic.x / float(tile_px)) - FOOTPRINT / 2, roundi(aim_logic.y / float(tile_px)) - FOOTPRINT / 2)

func block_center_px(origin: Vector2i) -> Vector2:
	return (Vector2(origin) + Vector2(FOOTPRINT, FOOTPRINT) * 0.5) * float(tile_px)

## Checks a placement of `kind_key` at `origin` (top-left cell) for a player standing at `player_px`. Does not change anything.
## Returns {ok, code, reason}; `code` is one of "" / unknown / bounds / terrain / nest / occupied / immature / range / limit / cost.
func evaluate(kind_key: String, origin: Vector2i, player_px: Vector2) -> Dictionary:
	var def: Dictionary = kind_def(carried["kind"] if is_carrying() else kind_key)
	if def.is_empty():
		return _result("unknown", "その種類は置けない")
	var out_of_map: bool = false
	var bad_ground: bool = false
	var on_nest: bool = false
	var taken: bool = false
	var immature: bool = false
	for y: int in range(origin.y, origin.y + FOOTPRINT):
		for x: int in range(origin.x, origin.x + FOOTPRINT):
			if not state.in_bounds(x, y):
				out_of_map = true
				continue
			var index: int = state.index_of(x, y)
			if not state.is_walkable(x, y) or state.target[index] == 0 or not state.terrain_defs[state.terrain[index]].plantable:
				bad_ground = true
			elif state.occupant[index] >= WorldState.OWNER_BAND_NEST:
				on_nest = true
			elif state.occupant[index] != 0:
				taken = true
			elif state.stage[index] != WorldState.STAGE_MATURE:
				immature = true
	if out_of_map:
		return _result("bounds", "マップの外には置けない")
	if bad_ground:
		return _result("terrain", "建物・水など緑化できない地面には置けない")
	if on_nest:
		return _result("nest", "巣の上には置けない")
	if taken:
		return _result("occupied", "ほかの植物がある場所には置けない")
	if immature:
		return _result("immature", "成熟した緑地の上にだけ置ける（未緑化・成長中のマスがある）")
	if player_px.distance_to(block_center_px(origin)) > place_range_px:
		return _result("range", "遠すぎて置けない（射程 %.1fm）" % (place_range_px * 0.1))
	if not is_carrying():
		if total_count() >= max_helpers:
			return _result("limit", "おたすけ植物の上限（%d）に達している" % max_helpers)
		if seeds < int(def["cost"]):
			return _result("cost", "おたすけたねが足りない（必要 %d・所持 %d）" % [int(def["cost"]), seeds])
	return _result("", "")

static func _result(code: String, reason: String) -> Dictionary:
	return {"ok": code.is_empty(), "code": code, "reason": reason}

## Places `kind_key` (or the carried plant, free of charge) with the block centred on `aim_logic`. Returns {ok, code, reason, uid}.
func place(kind_key: String, aim_logic: Vector2, player_px: Vector2) -> Dictionary:
	var origin: Vector2i = origin_for(aim_logic)
	var checked: Dictionary = evaluate(kind_key, origin, player_px)
	checked["uid"] = 0
	if not bool(checked["ok"]):
		return checked
	var plant: Dictionary
	if is_carrying():
		plant = {"uid": int(carried["uid"]), "kind": String(carried["kind"]), "x": origin.x, "y": origin.y, "hp": int(carried["hp"]), "cooldown": 0.0}
		_init_work(plant, float(carried.get("stock", -1.0)))
	else:
		var def: Dictionary = kind_def(kind_key)
		plant = {"uid": next_uid, "kind": kind_key, "x": origin.x, "y": origin.y, "hp": int(def["hp"]), "cooldown": 0.0}
		_init_work(plant, -1.0)
	if not state.occupy(Rect2i(origin, Vector2i(FOOTPRINT, FOOTPRINT)), owner_of(int(plant["uid"]))):
		return _result("occupied", "ほかの植物がある場所には置けない")
	if is_carrying():
		carried = {}
	else:
		next_uid += 1
		seeds -= int(kind_def(kind_key)["cost"])
	plants.append(plant)
	checked["uid"] = int(plant["uid"])
	return checked

## Picks up the nearest placed plant within the lift range. Returns {ok, code, reason, uid}.
func lift(player_px: Vector2) -> Dictionary:
	if is_carrying():
		return {"ok": false, "code": "carrying", "reason": "すでに持ち上げている", "uid": 0}
	var best: int = -1
	var best_distance: float = INF
	for i: int in plants.size():
		var distance: float = rect_distance(player_px, _rect_px(plant_rect(plants[i])))
		if distance <= lift_range_px and distance < best_distance:
			best_distance = distance
			best = i
	if best < 0:
		return {"ok": false, "code": "none", "reason": "近くにおたすけ植物がない", "uid": 0}
	var plant: Dictionary = plants[best]
	state.release(owner_of(int(plant["uid"])))
	carried = {"uid": int(plant["uid"]), "kind": String(plant["kind"]), "hp": int(plant["hp"]), "stock": float(plant.get("stock", 0.0))}
	pulse_fx.erase(int(plant["uid"]))
	plants.remove_at(best)
	return {"ok": true, "code": "", "reason": "", "uid": int(carried["uid"])}

func _remove_plant(index: int) -> void:
	pulse_fx.erase(int(plants[index]["uid"]))
	state.release(owner_of(int(plants[index]["uid"])))
	plants.remove_at(index)
	lost_total += 1

# ---------------------------------------------------------------- time

## `delta` game seconds (already capped by the caller). `downed`: a downed player cannot collect.
func advance(delta: float, player_px: Vector2, downed: bool) -> void:
	if delta <= 0.0:
		return
	time += delta
	# Age first, then roll: a new item starts at age 0 whatever the step size (the result does not depend on how time is split).
	var i: int = pickups.size() - 1
	while i >= 0:
		pickups[i]["age"] = float(pickups[i]["age"]) + delta
		if float(pickups[i]["age"]) >= pickup_lifetime:
			pickups.remove_at(i)
		i -= 1
	while float(ticks + 1) * drop_interval <= time + 1.0e-9:
		ticks += 1
		_roll_drops()
	if not downed:
		_collect(player_px)
	_damage(delta)
	_work(delta, player_px, downed)

func _collect(player_px: Vector2) -> void:
	var i: int = 0
	while i < pickups.size() and seeds < seeds_max:
		if Vector2(float(pickups[i]["x"]), float(pickups[i]["y"])).distance_to(player_px) <= collect_radius:
			pickups.remove_at(i)
			seeds += 1
			collected_total += 1
			_say("おたすけたね +1（%d/%d）" % [seeds, seeds_max])
		else:
			i += 1

## Boars next to a placed plant hurt it: every `damage_interval` seconds of contact costs `damage_amount` per boar in contact.
func _damage(delta: float) -> void:
	var i: int = plants.size() - 1
	while i >= 0:
		var plant: Dictionary = plants[i]
		var cooldown: float = maxf(float(plant["cooldown"]) - delta, 0.0)
		if enemies != null and cooldown <= 0.0:
			var near: int = 0
			var rect: Rect2 = _rect_px(plant_rect(plant))
			for boar: Boar in enemies.boars:
				if rect_distance(boar.pos, rect) <= contact_px:
					near += 1
			if near > 0:
				plant["hp"] = maxi(int(plant["hp"]) - damage_amount * near, 0)
				cooldown = damage_interval
		plant["cooldown"] = cooldown
		if int(plant["hp"]) <= 0:
			_say("%sが倒された…（おたすけたねで再建できる）" % String(kind_def(String(plant["kind"])).get("name", "おたすけ植物")))
			_remove_plant(i)
		i -= 1

# ---------------------------------------------------------------- HLP-02 work

func stock_max_of(key: String) -> float:
	if key == "gatlinger":
		return float(gat["stock_max"])
	if key == "sprinkler":
		return float(spr["stock_max"])
	return 0.0

## Work fields of a freshly placed (or re-placed) plant: stock (`stock` < 0 = the kind's start stock), two timers and the Army unit
## position (px). Timers start full, so nothing happens in the instant of placing.
func _init_work(plant: Dictionary, stock: float) -> void:
	var key: String = String(plant["kind"])
	var start: float = 0.0
	plant["timer"] = 0.0
	plant["timer2"] = 0.0
	if key == "gatlinger":
		start = float(gat["stock_start"])
		plant["timer"] = float(gat["fire_interval"])
		plant["timer2"] = float(gat["receive_interval"])
	elif key == "sprinkler":
		start = float(spr["stock_start"])
		plant["timer"] = float(spr["pulse_interval"])
	plant["stock"] = clampf(start if stock < 0.0 else stock, 0.0, stock_max_of(key))
	var centre: Vector2 = plant_center_px(plant)
	plant["ax"] = centre.x
	plant["ay"] = centre.y

func unit_pos(plant: Dictionary) -> Vector2:
	return Vector2(float(plant["ax"]), float(plant["ay"]))

func _work(delta: float, player_px: Vector2, downed: bool) -> void:
	for uid: Variant in pulse_fx.keys():
		pulse_fx[uid] = float(pulse_fx[uid]) - delta
		if float(pulse_fx[uid]) <= 0.0:
			pulse_fx.erase(uid)
	if plants.is_empty() and flights.is_empty():
		return
	var left: float = delta
	while left > 1.0e-9:
		var dt: float = minf(left, WORK_STEP)
		left -= dt
		_step_flights(dt)
		for plant: Dictionary in plants:
			var key: String = String(plant["kind"])
			if key == "gatlinger":
				_gat_step(plant, dt)
			elif key == "sprinkler":
				_spr_step(plant, dt, player_px, downed)
			elif key == "army":
				_army_step(plant, dt)

# ---- Gatlinger

func _step_flights(dt: float) -> void:
	var i: int = flights.size() - 1
	while i >= 0:
		var flight: Dictionary = flights[i]
		flight["age"] = float(flight["age"]) + dt
		if float(flight["age"]) >= float(flight["dur"]):
			var index: int = state.index_of(int(flight["cx"]), int(flight["cy"]))
			# The landing is the same planting rule as a player's seed (free, plantable, unoccupied target cell).
			if state.can_plant(index) and state.set_stage(index, WorldState.STAGE_SEED):
				seeded_total += 1
			else:
				wasted_total += 1
			flights.remove_at(i)
		i -= 1

## Mature cells (stage 4) within the effect radius, not counting the plant's own block: what the Gatlinger takes its seeds from.
func mature_cells_around(plant: Dictionary) -> int:
	var centre: Vector2 = plant_center_px(plant)
	var radius: float = float(kind_def("gatlinger")["radius_px"])
	var own: Rect2i = plant_rect(plant)
	var count: int = 0
	for y: int in range(maxi(floori((centre.y - radius) / tile_px), 0), mini(floori((centre.y + radius) / tile_px), state.height - 1) + 1):
		for x: int in range(maxi(floori((centre.x - radius) / tile_px), 0), mini(floori((centre.x + radius) / tile_px), state.width - 1) + 1):
			if own.has_point(Vector2i(x, y)):
				continue
			if Vector2((x + 0.5) * tile_px, (y + 0.5) * tile_px).distance_to(centre) <= radius and state.stage[state.index_of(x, y)] == WorldState.STAGE_MATURE:
				count += 1
	return count

func _gat_step(plant: Dictionary, dt: float) -> void:
	var cap: float = float(gat["stock_max"])
	plant["timer2"] = float(plant["timer2"]) - dt
	if float(plant["timer2"]) <= 0.0:
		plant["timer2"] = float(plant["timer2"]) + float(gat["receive_interval"])
		if float(plant["stock"]) + 1.0e-6 < cap and mature_cells_around(plant) >= int(gat["min_mature_cells"]):
			plant["stock"] = minf(float(plant["stock"]) + 1.0, cap)
	# The timer may run slightly below zero (the rest of the step) so that the rate does not depend on the step length.
	plant["timer"] = maxf(float(plant["timer"]) - dt, -dt)
	if float(plant["timer"]) > 0.0 or float(plant["stock"]) < 1.0:
		return
	var cell: Vector2i = pick_target(plant)
	if cell.x < 0:
		plant["timer"] = float(gat["retry_interval"])
		return
	var from: Vector2 = plant_center_px(plant)
	var to: Vector2 = Vector2((cell.x + 0.5) * tile_px, (cell.y + 0.5) * tile_px)
	flights.append({"ox": from.x, "oy": from.y, "cx": cell.x, "cy": cell.y, "age": 0.0, "dur": maxf(from.distance_to(to) / float(gat["flight_speed_px"]), 0.2)})
	fire_serial += 1
	plant["stock"] = float(plant["stock"]) - 1.0
	plant["timer"] = maxf(float(plant["timer"]), -WORK_STEP) + float(gat["fire_interval"])

## Picks a free greenable cell in range for the Gatlinger: unseeded, unoccupied, not a nest / building / water, not already aimed at by
## a flight, and with a clear line (no wall) from the plant. Cells with no plants nearby (the pioneer window) come first, so the seeds
## start new green points away from the existing green. Returns (-1, -1) when there is none.
func pick_target(plant: Dictionary) -> Vector2i:
	var centre: Vector2 = plant_center_px(plant)
	var radius: float = float(kind_def("gatlinger")["radius_px"])
	var reserved: Dictionary = {}
	for flight: Dictionary in flights:
		reserved[state.index_of(int(flight["cx"]), int(flight["cy"]))] = true
	var window: int = int(gat["pioneer_window"])
	var pioneers: Array[Vector2i] = []
	var others: Array[Vector2i] = []
	for y: int in range(maxi(floori((centre.y - radius) / tile_px), 0), mini(floori((centre.y + radius) / tile_px), state.height - 1) + 1):
		for x: int in range(maxi(floori((centre.x - radius) / tile_px), 0), mini(floori((centre.x + radius) / tile_px), state.width - 1) + 1):
			if Vector2((x + 0.5) * tile_px, (y + 0.5) * tile_px).distance_to(centre) > radius:
				continue
			var index: int = state.index_of(x, y)
			if not state.can_plant(index) or reserved.has(index):
				continue
			var crowded: bool = false
			for wy: int in range(maxi(y - window, 0), mini(y + window, state.height - 1) + 1):
				for wx: int in range(maxi(x - window, 0), mini(x + window, state.width - 1) + 1):
					if state.stage[state.index_of(wx, wy)] != WorldState.STAGE_EMPTY:
						crowded = true
			(others if crowded else pioneers).append(Vector2i(x, y))
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = rng_seed * 1000003 + fire_serial * 7919 + int(plant["uid"]) * 104729
	var tries: int = int(gat["tries"])
	for list: Array[Vector2i] in [pioneers, others]:
		while not list.is_empty() and tries > 0:
			tries -= 1
			var pick: int = rng.randi_range(0, list.size() - 1)
			var cell: Vector2i = list[pick]
			list.remove_at(pick)
			var to: Vector2 = Vector2((cell.x + 0.5) * tile_px, (cell.y + 0.5) * tile_px)
			if not blocker.is_valid() or not bool(blocker.call(centre, to)):
				return cell
	return Vector2i(-1, -1)

# ---- Sprinkler

## True when the block or the ring of cells around it touches a waterside terrain (shore / shallows / water).
func is_by_water(plant: Dictionary) -> bool:
	var rect: Rect2i = plant_rect(plant).grow(1)
	for y: int in range(maxi(rect.position.y, 0), mini(rect.end.y, state.height)):
		for x: int in range(maxi(rect.position.x, 0), mini(rect.end.x, state.width)):
			if play.waterside_by_terrain[state.terrain[state.index_of(x, y)]] == 1:
				return true
	return false

## Seeds and sprouts (stage 1..3) in range whose moisture is below the cap: the cells a pulse would wet.
func _pulse_cells(plant: Dictionary) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	var centre: Vector2 = plant_center_px(plant)
	var radius: float = float(kind_def("sprinkler")["radius_px"])
	var top: int = play.sim_tuning.moisture_max
	for y: int in range(maxi(floori((centre.y - radius) / tile_px), 0), mini(floori((centre.y + radius) / tile_px), state.height - 1) + 1):
		for x: int in range(maxi(floori((centre.x - radius) / tile_px), 0), mini(floori((centre.x + radius) / tile_px), state.width - 1) + 1):
			var index: int = state.index_of(x, y)
			var growing: bool = state.stage[index] >= WorldState.STAGE_SEED and state.stage[index] <= WorldState.STAGE_SPROUT2
			if growing and state.target[index] == 1 and int(state.moisture[index]) < top and Vector2((x + 0.5) * tile_px, (y + 0.5) * tile_px).distance_to(centre) <= radius:
				out.append(index)
	return out

func _spr_step(plant: Dictionary, dt: float, player_px: Vector2, downed: bool) -> void:
	var cap: float = float(spr["stock_max"])
	var by_water: bool = is_by_water(plant)
	# Manual refill: the player stands next to a Sprinkler that is not by the water.
	if not by_water and not downed and float(plant["stock"]) < cap and rect_distance(player_px, _rect_px(plant_rect(plant))) <= float(spr["refill_range_px"]):
		plant["stock"] = minf(float(plant["stock"]) + float(spr["refill_per_second"]) * dt, cap)
	plant["timer"] = float(plant["timer"]) - dt
	if float(plant["timer"]) > 0.0:
		return
	plant["timer"] = float(plant["timer"]) + float(spr["pulse_interval"])
	if not by_water and float(plant["stock"]) + 1.0e-6 < float(spr["pulse_cost"]):
		return
	var cells: PackedInt32Array = _pulse_cells(plant)
	if cells.is_empty():
		return
	if not by_water:
		plant["stock"] = maxf(float(plant["stock"]) - float(spr["pulse_cost"]), 0.0)
	var top: int = play.sim_tuning.moisture_max
	for index: int in cells:
		state.set_moisture(index, mini(int(state.moisture[index]) + int(spr["moisture_add"]), top))
	pulses_total += 1
	pulse_fx[int(plant["uid"])] = float(spr["fx_seconds"])

# ---- Army

func _blocked(from: Vector2, to: Vector2) -> bool:
	return blocker.is_valid() and bool(blocker.call(from, to))

func _army_step(plant: Dictionary, dt: float) -> void:
	var home: Vector2 = plant_center_px(plant)
	var radius: float = float(kind_def("army")["radius_px"])
	var unit: Vector2 = unit_pos(plant)
	plant["timer"] = maxf(float(plant["timer"]) - dt, -dt)
	var target: Boar = null
	if enemies != null:
		var best: float = INF
		for boar: Boar in enemies.boars:
			if boar.pos.distance_to(home) <= radius and boar.pos.distance_to(unit) < best:
				best = boar.pos.distance_to(unit)
				target = boar
	var goal: Vector2 = home
	if target != null:
		goal = target.pos
		if unit.distance_to(goal) <= float(army["reach_px"]) and not _blocked(unit, goal):
			if float(plant["timer"]) <= 0.0:
				plant["timer"] = maxf(float(plant["timer"]), -WORK_STEP) + float(army["attack_interval"])
				if enemies.damage_boar(target, int(army["damage"])):
					kills_total += 1
			return
	var step: float = float(army["unit_speed_px"]) * dt
	if unit.distance_to(goal) > 0.001:
		var motion: Vector2 = (goal - unit).limit_length(step)
		var moved: Vector2 = Walker.move(state, tile_px, unit, motion, Vector2(1.0, 1.0))
		# Never beyond the defence radius around the post (the unit does not chase further).
		if moved.distance_to(home) > radius:
			var pulled: Vector2 = home + (moved - home).normalized() * radius
			var cell: Vector2i = Vector2i(floori(pulled.x / tile_px), floori(pulled.y / tile_px))
			moved = pulled if state.in_bounds(cell.x, cell.y) and state.is_walkable(cell.x, cell.y) else unit
		unit = moved
	plant["ax"] = unit.x
	plant["ay"] = unit.y

# ---------------------------------------------------------------- save structure

func to_dict() -> Dictionary:
	var item_list: Array = []
	for item: Dictionary in pickups:
		item_list.append({"x": float(item["x"]), "y": float(item["y"]), "age": float(item["age"])})
	var plant_list: Array = []
	for plant: Dictionary in plants:
		plant_list.append({"uid": int(plant["uid"]), "kind": String(plant["kind"]), "x": int(plant["x"]), "y": int(plant["y"]), "hp": int(plant["hp"]), "cooldown": float(plant["cooldown"]),
			"stock": _r4(plant["stock"]), "timer": float(plant["timer"]), "timer2": _r4(plant["timer2"]), "ax": _r4(plant["ax"]), "ay": _r4(plant["ay"])})
	var flight_list: Array = []
	for flight: Dictionary in flights:
		flight_list.append({"ox": _r4(flight["ox"]), "oy": _r4(flight["oy"]), "cx": int(flight["cx"]), "cy": int(flight["cy"]), "age": _r4(flight["age"]), "dur": _r4(flight["dur"])})
	var held: Variant = null
	if not carried.is_empty():
		held = {"uid": int(carried["uid"]), "kind": String(carried["kind"]), "hp": int(carried["hp"]), "stock": _r4(carried.get("stock", 0.0))}
	return {
		"version": STATE_VERSION, "seeds": seeds, "time": time, "ticks": ticks, "next_uid": next_uid,
		"pickups": item_list, "plants": plant_list,
		"carried": held, "flights": flight_list, "fire_serial": fire_serial,
		"stats": {"dropped": dropped_total, "collected": collected_total, "nest_rewards": nest_rewards_total, "lost": lost_total, "seeded": seeded_total, "wasted": wasted_total, "pulses": pulses_total, "kills": kills_total},
	}

## State values are saved exactly (the save writes full-precision floats), so a resumed run branches nowhere.
static func _r4(value: Variant) -> float:
	return float(value)

## Restores the state. The occupied cells are part of the world's own save, so this only checks that the world agrees: every placed
## plant owns exactly its block of mature ground, and no other helper-band owner exists (a lifted plant owns nothing).
## Returns false (state unchanged) when the data does not fit.
func load_dict(data: Dictionary) -> bool:
	var version: int = int(data.get("version", 0))
	if version < 1 or version > STATE_VERSION or not (data.get("pickups") is Array) or not (data.get("plants") is Array):
		return false
	var new_seeds: int = int(data.get("seeds", -1))
	if new_seeds < 0 or new_seeds > seeds_max or float(data.get("time", -1.0)) < 0.0 or int(data.get("ticks", -1)) < 0:
		return false
	var new_pickups: Array[Dictionary] = []
	for entry: Variant in data["pickups"]:
		if not (entry is Dictionary) or not (entry as Dictionary).has("x") or not (entry as Dictionary).has("y") or not (entry as Dictionary).has("age"):
			return false
		new_pickups.append({"x": float(entry["x"]), "y": float(entry["y"]), "age": float(entry["age"])})
	var seen: Dictionary = {}
	var new_plants: Array[Dictionary] = []
	for entry: Variant in data["plants"]:
		if not (entry is Dictionary):
			return false
		var source: Dictionary = entry
		var def: Dictionary = kind_def(String(source.get("kind", "")))
		var uid: int = int(source.get("uid", 0))
		var hp: int = int(source.get("hp", 0))
		if def.is_empty() or uid <= 0 or seen.has(uid) or hp < 1 or hp > int(def["hp"]) or not source.has("x") or not source.has("y"):
			return false
		seen[uid] = true
		var plant: Dictionary = {"uid": uid, "kind": String(source["kind"]), "x": int(source["x"]), "y": int(source["y"]), "hp": hp, "cooldown": maxf(float(source.get("cooldown", 0.0)), 0.0)}
		_init_work(plant, -1.0)
		if version >= 2:
			var unit: Vector2 = Vector2(float(source.get("ax", -1.0e9)), float(source.get("ay", -1.0e9)))
			if not source.has("stock") or not source.has("timer") or not source.has("timer2") or float(source["stock"]) < 0.0 or float(source["stock"]) > stock_max_of(String(source["kind"])) + 1.0e-6:
				return false
			if float(source["timer"]) < -WORK_STEP - 1.0e-6 or float(source["timer"]) > _timer_max() or float(source["timer2"]) < 0.0 or float(source["timer2"]) > _timer_max():
				return false
			if unit.distance_to(plant_center_px(plant)) > float(def["radius_px"]) + 1.0:
				return false
			plant["stock"] = float(source["stock"])
			plant["timer"] = float(source["timer"])
			plant["timer2"] = float(source["timer2"])
			plant["ax"] = unit.x
			plant["ay"] = unit.y
		var rect: Rect2i = plant_rect(plant)
		if not state.occupancy_owners.has(owner_of(uid)) or Rect2i(state.occupancy_owners[owner_of(uid)]) != rect:
			return false
		for y: int in range(rect.position.y, rect.end.y):
			for x: int in range(rect.position.x, rect.end.x):
				if state.occupant[state.index_of(x, y)] != owner_of(uid) or state.stage[state.index_of(x, y)] != WorldState.STAGE_MATURE:
					return false
		new_plants.append(plant)
	var new_carried: Dictionary = {}
	if data.get("carried") != null:
		if not (data["carried"] is Dictionary):
			return false
		var held: Dictionary = data["carried"]
		var held_def: Dictionary = kind_def(String(held.get("kind", "")))
		var held_uid: int = int(held.get("uid", 0))
		var held_hp: int = int(held.get("hp", 0))
		if held_def.is_empty() or held_uid <= 0 or seen.has(held_uid) or held_hp < 1 or held_hp > int(held_def["hp"]) or state.occupancy_owners.has(owner_of(held_uid)):
			return false
		seen[held_uid] = true
		var held_stock: float = float(held.get("stock", 0.0))
		if held_stock < 0.0 or held_stock > stock_max_of(String(held["kind"])) + 1.0e-6:
			return false
		new_carried = {"uid": held_uid, "kind": String(held["kind"]), "hp": held_hp, "stock": held_stock}
	if new_plants.size() + (1 if not new_carried.is_empty() else 0) > max_helpers:
		return false
	for owner_id: Variant in state.occupancy_owners:
		if int(owner_id) >= WorldState.OWNER_BAND_HELPER and int(owner_id) < WorldState.OWNER_BAND_NEST and not seen.has(int(owner_id) - WorldState.OWNER_BAND_HELPER):
			return false
	var new_flights: Array[Dictionary] = []
	if version >= 2:
		if not (data.get("flights") is Array) or (data["flights"] as Array).size() > 200 or int(data.get("fire_serial", -1)) < 0:
			return false
		for entry: Variant in data["flights"]:
			if not (entry is Dictionary):
				return false
			var f: Dictionary = entry
			for key: String in ["ox", "oy", "cx", "cy", "age", "dur"]:
				if not f.has(key):
					return false
			var fx_cell: Vector2i = Vector2i(int(f["cx"]), int(f["cy"]))
			if not state.in_bounds(fx_cell.x, fx_cell.y) or float(f["age"]) < 0.0 or float(f["dur"]) <= 0.0 or float(f["age"]) >= float(f["dur"]) or float(f["dur"]) > 30.0:
				return false
			new_flights.append({"ox": float(f["ox"]), "oy": float(f["oy"]), "cx": fx_cell.x, "cy": fx_cell.y, "age": float(f["age"]), "dur": float(f["dur"])})
	var new_next: int = maxi(int(data.get("next_uid", 1)), 1)
	for uid: Variant in seen:
		new_next = maxi(new_next, int(uid) + 1)
	seeds = new_seeds
	time = float(data["time"])
	ticks = int(data["ticks"])
	next_uid = new_next
	pickups = new_pickups
	plants = new_plants
	carried = new_carried
	var stats: Dictionary = data.get("stats", {})
	dropped_total = maxi(int(stats.get("dropped", 0)), 0)
	collected_total = maxi(int(stats.get("collected", 0)), 0)
	nest_rewards_total = maxi(int(stats.get("nest_rewards", 0)), 0)
	lost_total = maxi(int(stats.get("lost", 0)), 0)
	seeded_total = maxi(int(stats.get("seeded", 0)), 0)
	wasted_total = maxi(int(stats.get("wasted", 0)), 0)
	pulses_total = maxi(int(stats.get("pulses", 0)), 0)
	kills_total = maxi(int(stats.get("kills", 0)), 0)
	flights = new_flights
	fire_serial = maxi(int(data.get("fire_serial", 0)), 0)
	pulse_fx.clear()
	return true

## Largest value a work timer can hold (its longest interval).
func _timer_max() -> float:
	return maxf(maxf(float(gat["fire_interval"]), float(gat["receive_interval"])), maxf(float(gat["retry_interval"]), maxf(float(spr["pulse_interval"]), float(army["attack_interval"])))) + 0.01
