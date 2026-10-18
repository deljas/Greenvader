extends RefCounted
## HLP-01 PoC-side helper seeds (おたすけたね) and helper plants (おたすけ植物). Display-free; owned by PocSession and advanced only
## from its single loop (advance_game), so a paused game freezes drops, collection and damage and nothing is banked.
##
## - Helper seeds: a count (cap `seeds_max`) and seed items lying on the ground. Sources: (a) every `drop_interval` game seconds each
##   mature cultivated plant rolls `drop_chance` with a fixed-seed random draw (state = `ticks`, saved), (b) a destroyed nest drops
##   `nest_reward` items. The player collects items by walking close.
## - Helper plants: 4x4 cell blocks held in WorldState.occupy (owner OWNER_BAND_HELPER + uid). The occupied cells are mature ground
##   before and stay mature, so they count as greened and the counters never change. Only a placed block, its hp and its damage
##   cooldown are state; the working of each kind is HLP-02.
## - Lift (E near one) releases the occupancy and keeps the plant as `carried` (one at a time); placing it again costs nothing.
## Nothing here touches scripts/play, scripts/world or scripts/enemy (they are only read; the enemy field is read for boar positions).
const SETUP_PATH: String = "res://data/poc/helpers.json"
const FOOTPRINT: int = 4

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
	kinds.clear()
	for entry: Variant in data.get("kinds", []):
		var source: Dictionary = entry
		kinds.append({"key": String(source["key"]), "name": String(source["name"]), "cost": int(source["cost"]), "hp": int(source["hp"]), "radius_m": float(source["radius_m"]), "radius_px": float(source["radius_m"]) / 0.1, "color": String(source["color"])})

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
	else:
		var def: Dictionary = kind_def(kind_key)
		plant = {"uid": next_uid, "kind": kind_key, "x": origin.x, "y": origin.y, "hp": int(def["hp"]), "cooldown": 0.0}
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
	carried = {"uid": int(plant["uid"]), "kind": String(plant["kind"]), "hp": int(plant["hp"])}
	plants.remove_at(best)
	return {"ok": true, "code": "", "reason": "", "uid": int(carried["uid"])}

func _remove_plant(index: int) -> void:
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

# ---------------------------------------------------------------- save structure

func to_dict() -> Dictionary:
	var item_list: Array = []
	for item: Dictionary in pickups:
		item_list.append({"x": float(item["x"]), "y": float(item["y"]), "age": float(item["age"])})
	var plant_list: Array = []
	for plant: Dictionary in plants:
		plant_list.append({"uid": int(plant["uid"]), "kind": String(plant["kind"]), "x": int(plant["x"]), "y": int(plant["y"]), "hp": int(plant["hp"]), "cooldown": float(plant["cooldown"])})
	return {
		"version": 1, "seeds": seeds, "time": time, "ticks": ticks, "next_uid": next_uid,
		"pickups": item_list, "plants": plant_list,
		"carried": (null if carried.is_empty() else carried.duplicate()),
		"stats": {"dropped": dropped_total, "collected": collected_total, "nest_rewards": nest_rewards_total, "lost": lost_total},
	}

## Restores the state. The occupied cells are part of the world's own save, so this only checks that the world agrees: every placed
## plant owns exactly its block of mature ground, and no other helper-band owner exists (a lifted plant owns nothing).
## Returns false (state unchanged) when the data does not fit.
func load_dict(data: Dictionary) -> bool:
	if int(data.get("version", 0)) != 1 or not (data.get("pickups") is Array) or not (data.get("plants") is Array):
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
		new_carried = {"uid": held_uid, "kind": String(held["kind"]), "hp": held_hp}
	if new_plants.size() + (1 if not new_carried.is_empty() else 0) > max_helpers:
		return false
	for owner_id: Variant in state.occupancy_owners:
		if int(owner_id) >= WorldState.OWNER_BAND_HELPER and int(owner_id) < WorldState.OWNER_BAND_NEST and not seen.has(int(owner_id) - WorldState.OWNER_BAND_HELPER):
			return false
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
	return true
