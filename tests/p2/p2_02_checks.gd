extends SceneTree
## P2-02 headless checks: shots hit boars and nests (damage, first hit, water passes, no landing), defeat (3 shots / 20 shots,
## drops under the pickup rules, collecting), carcasses (fertility disk, growth speed-up, corpse -> bone -> gone timing, cap,
## overlap rounding, restoring), pause, frame-rate independence (30 / 60 / 144 Hz), save round trips, and the real scene
## (injected mouse input only): shoot a boar, collect the fruit, watch seeds grow faster around the carcass.
## Run: Godot --headless --path <project> --script res://tests/p2/p2_02_checks.gd
## Expected values come from the ticket and the design written here (3 shots, 20 shots, 2 / 4 fruits, radius 4 tiles, 60 s
## + 40 s, cap 24, strength 40 / 20 with a rounding cap of 60, growth factor 1 + 0.5 * fertility / 100) and from brute force
## geometry; they are not read back from the implementation's own tables.

const REGION_PATH: String = "res://data/region_01.tres"
const TILE: int = 4
## The design numbers of this ticket (the data may be tuned later; then these checks must be adjusted on purpose).
const BOAR_HP: int = 3
const NEST_HP: int = 20
const BOAR_FRUITS: int = 2
const NEST_FRUITS: int = 4
const RADIUS_TILES: int = 4
const CORPSE_S: float = 60.0
const BONE_S: float = 40.0
const FERT_CORPSE: int = 40
const FERT_BONE: int = 20
const FERT_CAP: int = 60
const CARCASS_CAP: int = 24

var failures: int = 0
var checks: int = 0
var region_def: RegionDef
var sim_tuning: SimTuning
var play_tuning: PlayTuning
var enemy_tuning: EnemyTuning
var info: Dictionary = {}

# Scene helpers.
var mouse_screen: Vector2 = Vector2(320, 180)
var main: Node
var player: FlowerPlayer

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
	print("%s %s" % ["PASS" if ok else "FAIL", message])

func run() -> void:
	region_def = load(REGION_PATH) as RegionDef
	sim_tuning = load("res://data/sim_tuning.tres") as SimTuning
	play_tuning = load("res://data/play_tuning.tres") as PlayTuning
	enemy_tuning = load("res://data/enemy_tuning.tres") as EnemyTuning
	check(region_def != null and enemy_tuning != null and play_tuning != null, "region and tunings load")
	test_tuning_values()
	test_seed_hit()
	test_water_and_plant_shots()
	test_first_hit()
	test_boar_defeat_and_drops()
	test_nest_defeat()
	test_drop_slots()
	test_carcass_fertility()
	test_growth_speed()
	test_timeline()
	test_cap_and_overlap()
	test_restore_base()
	test_flash()
	test_frame_rates()
	test_save_round_trip()
	test_performance()
	await test_scene()
	print("INFO " + JSON.stringify(info))
	print("P2_02_RESULT checks=%d failures=%d" % [checks, failures])
	var file: FileAccess = FileAccess.open(ProjectSettings.globalize_path("res://evidence/p2/p2-02/checks_info.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(info, "  "))
		file.close()
	quit(1 if failures > 0 else 0)

# ---- helpers -------------------------------------------------------------------------------------------------------

func terrain_def(key: StringName) -> TerrainDef:
	for def: TerrainDef in region_def.terrains:
		if def.key == key:
			return def
	return null

func c8(color: Color) -> Vector3i:
	return Vector3i(roundi(color.r * 255.0), roundi(color.g * 255.0), roundi(color.b * 255.0))

func tune(overrides: Dictionary = {}) -> EnemyTuning:
	var copy: EnemyTuning = enemy_tuning.duplicate() as EnemyTuning
	for key: String in overrides:
		copy.set(key, overrides[key])
	return copy

## 100 x 60 open wasteland; zone 0 (x < 50) unconquered, zone 1 stable.
func small_world() -> WorldState:
	var def: RegionDef = RegionDef.new()
	def.width_tiles = 100
	def.height_tiles = 60
	def.terrains = region_def.terrains
	def.sprout_seed = region_def.sprout_seed
	var image: Image = Image.create(100, 60, false, Image.FORMAT_RGB8)
	var v: Vector3i = c8(terrain_def(&"wasteland").map_color)
	image.fill(Color8(v.x, v.y, v.z))
	var world: WorldState = RegionLoader.build_state(def, image)
	var ids: PackedByteArray = PackedByteArray()
	ids.resize(world.tile_count())
	for index: int in world.tile_count():
		ids[index] = 0 if index % world.width < 50 else 1
	world.set_zones(ids, PackedByteArray([WorldState.ZONE_UNCONQUERED, WorldState.ZONE_STABLE]))
	return world

class Rig:
	extends RefCounted
	var world: WorldState
	var field: EnemyField
	var play: PlayState
	var combat: EnemyCombat
	var proj: ProjectileField
	var landed: Array = []
	var hit_events: Array = []

func make_rig(overrides: Dictionary = {}, sources: Array[Vector2] = []) -> Rig:
	var rig: Rig = Rig.new()
	rig.world = small_world()
	var merged: Dictionary = {"spawn_interval_seconds": 100000.0}
	merged.merge(overrides, true)
	rig.field = EnemyField.new(rig.world, tune(merged), TILE)
	var defs: Array[PlantDef] = []
	defs.assign(region_def.plants)
	rig.play = PlayState.new(rig.world, play_tuning, sim_tuning, TILE, sources, defs)
	rig.combat = EnemyCombat.new(rig.field, rig.play)
	rig.proj = ProjectileField.new()
	rig.proj.setup(play_tuning)
	rig.proj.enemy_hit_provider = rig.combat.hit_provider
	rig.proj.landed.connect(func(kind: String, point: Vector2) -> void:
		rig.landed.append([kind, point])
		if kind == ProjectileField.KIND_SEED:
			rig.play.land_seed(point))
	rig.proj.enemy_hit.connect(func(kind: String, point: Vector2, hit: Dictionary) -> void:
		rig.hit_events.append([kind, point, String(hit.get("kind", ""))])
		rig.combat.on_enemy_hit(kind, point, hit)
		if kind != ProjectileField.KIND_WATER and kind != ProjectileField.KIND_SEED:
			rig.play.cancel_plant(StringName(kind)))
	return rig

func put_boar(rig: Rig, pos: Vector2, nest: Nest) -> Boar:
	var boar: Boar = Boar.new()
	boar.id = rig.field.next_boar_id
	rig.field.next_boar_id += 1
	boar.nest_id = nest.id if nest != null else 0
	boar.zone = 0
	boar.pos = pos
	boar.home = nest.center_px(TILE) if nest != null else pos
	boar.hp = BOAR_HP
	boar.wait = 1 << 30
	boar.rng = 1
	rig.field.boars.append(boar)
	if nest != null:
		nest.boar_count += 1
	return boar

## Fires one shot and flies it to its end.
func shoot(rig: Rig, kind: String, from: Vector2, to: Vector2) -> void:
	rig.proj.launch(kind, from, to, Vector2.RIGHT)
	var guard: int = 0
	while not rig.proj.shots.is_empty() and guard < 400:
		rig.proj.advance(1.0 / 60.0)
		guard += 1

func planted_tiles(world: WorldState) -> int:
	var total: int = 0
	for index: int in world.tile_count():
		if world.stage[index] != WorldState.STAGE_EMPTY:
			total += 1
	return total

func body_center(boar: Boar) -> Vector2:
	return boar.pos - Vector2(0.0, 6.0)

## Brute-force expected carcass fertility of one tile: the list holds [pos, stage] (0 corpse, 1 bone). Written here.
func expected_fertility(list: Array, x: int, y: int) -> int:
	var centre: Vector2 = Vector2((x + 0.5) * TILE, (y + 0.5) * TILE)
	var sum: int = 0
	for entry: Array in list:
		var d: Vector2 = centre - Vector2(entry[0])
		if d.length() <= RADIUS_TILES * TILE + 1.0e-6:
			sum += FERT_CORPSE if int(entry[1]) == 0 else FERT_BONE
	return mini(sum, FERT_CAP)

func fertility_matches(world: WorldState, list: Array, base: int = 0) -> bool:
	for y: int in world.height:
		for x: int in world.width:
			if int(world.fertility[world.index_of(x, y)]) != base + expected_fertility(list, x, y):
				return false
	return true

func run_time(field: EnemyField, seconds: float, hz: int = 60) -> void:
	var count: int = roundi(seconds * hz)
	var dt: float = 1.0 / float(hz)
	for i: int in count:
		field.advance(dt)

# ---- tests ---------------------------------------------------------------------------------------------------------

func test_tuning_values() -> void:
	var t: EnemyTuning = enemy_tuning
	check(t.boar_hp == BOAR_HP and t.nest_hp == NEST_HP and t.seed_damage == 1, "boar hp 3, nest hp 20, seed damage 1")
	check(t.boar_drop_fruits == BOAR_FRUITS and t.nest_drop_fruits == NEST_FRUITS, "a boar drops 2 seed fruits, a nest 4")
	check(is_equal_approx(t.carcass_radius_tiles, float(RADIUS_TILES)) and is_equal_approx(t.carcass_seconds, CORPSE_S) and is_equal_approx(t.bone_seconds, BONE_S), "carcass radius 4 tiles, 60 s carcass, 40 s bone")
	check(t.carcass_fertility == FERT_CORPSE and t.bone_fertility == FERT_BONE and t.carcass_fertility_cap == FERT_CAP and t.carcass_cap == CARCASS_CAP, "fertility 40 / 20, rounding cap 60, at most 24 carcasses")
	check(not t.water_hits_enemies and t.plant_shot_damage == 0, "water passes through; a plant shot does no damage")

func test_seed_hit() -> void:
	var rig: Rig = make_rig()
	var nest: Nest = rig.field.add_nest(0, Vector2i(10, 10))
	var boar: Boar = put_boar(rig, Vector2(100, 80), nest)
	var before: int = planted_tiles(rig.world)
	var seeds_before: int = rig.play.seeds
	shoot(rig, ProjectileField.KIND_SEED, Vector2(60, 74), Vector2(140, 74))
	check(boar.hp == 2 and rig.hit_events.size() == 1 and String(rig.hit_events[0][2]) == "boar", "an injected seed shot that crosses the boar takes 1 hit point (hp %d)" % boar.hp)
	check(Vector2(rig.hit_events[0][1]).distance_to(Vector2(92, 74)) < 0.01, "the hit point is where the path enters the body circle (92,74): %s" % Vector2(rig.hit_events[0][1]))
	check(rig.landed.is_empty() and rig.proj.shots.is_empty(), "the hit shot is gone and did not land")
	check(planted_tiles(rig.world) == before, "a hit seed plants nothing on the ground")
	check(boar.flash_steps == 15, "a hit that does not kill starts a 0.25 s flash (15 steps)")
	# Control: a shot that misses lands and plants.
	shoot(rig, ProjectileField.KIND_SEED, Vector2(60, 40), Vector2(140, 40))
	check(rig.landed.size() == 1 and Vector2(rig.landed[0][1]).distance_to(Vector2(140, 40)) < 0.01 and planted_tiles(rig.world) > before, "control: a missing shot lands and plants (%d tiles)" % (planted_tiles(rig.world) - before))
	check(boar.hp == 2, "the missing shot did not hurt the boar")
	# A shot that grazes just outside the body circle (radius 8, centre y 74) misses.
	shoot(rig, ProjectileField.KIND_SEED, Vector2(60, 64), Vector2(140, 64))
	check(boar.hp == 2 and rig.hit_events.size() == 1, "a shot 10 px above the body centre misses")
	# Hit from a spot inside the circle at the start of the path.
	shoot(rig, ProjectileField.KIND_SEED, Vector2(100, 74), Vector2(140, 74))
	check(boar.hp == 1 and rig.hit_events.size() == 2, "a shot that starts inside the body hits at once")
	# A seed shot hits a nest.
	var rig2: Rig = make_rig()
	var nest2: Nest = rig2.field.add_nest(0, Vector2i(10, 10))
	shoot(rig2, ProjectileField.KIND_SEED, Vector2(20, 48), Vector2(100, 48))
	check(nest2.hp == NEST_HP - 1 and nest2.alive and rig2.landed.is_empty() and nest2.flash_steps == 15, "a seed shot takes 1 hit point from a nest (hp %d) and does not land" % nest2.hp)

func test_water_and_plant_shots() -> void:
	var rig: Rig = make_rig()
	var nest: Nest = rig.field.add_nest(0, Vector2i(10, 10))
	var boar: Boar = put_boar(rig, Vector2(100, 80), nest)
	var wet_before: int = 0
	shoot(rig, ProjectileField.KIND_WATER, Vector2(60, 74), Vector2(110, 74))
	check(boar.hp == BOAR_HP and rig.hit_events.is_empty() and rig.landed.size() == 1 and String(rig.landed[0][0]) == "water", "a water shot passes through the boar and lands behind it")
	check(Vector2(rig.landed[0][1]).distance_to(Vector2(110, 74)) < 0.01, "the water lands at its aim point")
	shoot(rig, ProjectileField.KIND_WATER, Vector2(20, 48), Vector2(100, 48))
	check(nest.hp == NEST_HP and rig.hit_events.is_empty(), "water passes through a nest too")
	# Cultivated plant shot (carrot): stopped by the boar, the held-back seeds come back, no damage, nothing planted.
	var carrot: PlantDef = rig.play.def_by_key(&"carrot")
	check(carrot != null and rig.play.can_fire_plant(carrot), "the carrot can be fired")
	var seeds_before: int = rig.play.seeds
	rig.play.reserve_plant(carrot)
	check(rig.play.reserved_seeds == carrot.seed_cost, "the shot holds %d seeds back" % carrot.seed_cost)
	shoot(rig, "carrot", Vector2(60, 74), Vector2(140, 74))
	check(rig.hit_events.size() == 1 and String(rig.hit_events[0][0]) == "carrot", "the carrot shot is stopped by the boar")
	check(rig.play.reserved_seeds == 0 and rig.play.seeds == seeds_before and rig.play.cultivation.count(&"carrot") == 0, "the held-back seeds are given back and no plant was placed")
	check(boar.hp == BOAR_HP, "a plant shot does no damage by default")
	# With plant damage switched on it hurts (tuning switch).
	var rig3: Rig = make_rig({"plant_shot_damage": 2})
	var nest3: Nest = rig3.field.add_nest(0, Vector2i(10, 10))
	var boar3: Boar = put_boar(rig3, Vector2(100, 80), nest3)
	rig3.play.reserve_plant(rig3.play.def_by_key(&"kiwi"))
	shoot(rig3, "kiwi", Vector2(60, 74), Vector2(140, 74))
	check(boar3.hp == 1 and rig3.play.reserved_seeds == 0, "with plant_shot_damage 2 the kiwi shot takes 2 hit points (tuning switch)")
	var rig4: Rig = make_rig({"water_hits_enemies": true})
	var nest4: Nest = rig4.field.add_nest(0, Vector2i(10, 10))
	var boar4: Boar = put_boar(rig4, Vector2(100, 80), nest4)
	shoot(rig4, ProjectileField.KIND_WATER, Vector2(60, 74), Vector2(140, 74))
	check(rig4.hit_events.size() == 1 and boar4.hp == BOAR_HP, "with water_hits_enemies water is stopped but does no damage (no water damage value)")

func test_first_hit() -> void:
	var rig: Rig = make_rig()
	var nest: Nest = rig.field.add_nest(0, Vector2i(10, 10))
	var a: Boar = put_boar(rig, Vector2(100, 80), nest)
	var b: Boar = put_boar(rig, Vector2(124, 80), nest)
	shoot(rig, ProjectileField.KIND_SEED, Vector2(60, 74), Vector2(160, 74))
	check(a.hp == 2 and b.hp == BOAR_HP, "of two boars on the path only the first one is hit (a %d, b %d)" % [a.hp, b.hp])
	shoot(rig, ProjectileField.KIND_SEED, Vector2(180, 74), Vector2(90, 74))
	check(b.hp == 2 and a.hp == 2, "from the other side the other boar is the first one")
	# Boar behind a nest: the nest is first from the west, the boar first from the east.
	var rig2: Rig = make_rig()
	var nest2: Nest = rig2.field.add_nest(0, Vector2i(10, 10))
	var c: Boar = put_boar(rig2, Vector2(80, 54), nest2)
	shoot(rig2, ProjectileField.KIND_SEED, Vector2(20, 48), Vector2(110, 48))
	check(nest2.hp == NEST_HP - 1 and c.hp == BOAR_HP, "a nest on the path is hit before the boar behind it")
	shoot(rig2, ProjectileField.KIND_SEED, Vector2(120, 48), Vector2(30, 48))
	check(c.hp == 2 and nest2.hp == NEST_HP - 1, "from the east the boar is hit before the nest behind it")
	# A fast shot (long frame step) cannot tunnel through a boar: hit_test is a segment test.
	var rig3: Rig = make_rig()
	var nest3: Nest = rig3.field.add_nest(0, Vector2i(10, 10))
	var d: Boar = put_boar(rig3, Vector2(100, 80), nest3)
	rig3.proj.launch(ProjectileField.KIND_SEED, Vector2(60, 74), Vector2(140, 74), Vector2.RIGHT)
	rig3.proj.advance(0.25)
	check(d.hp == 2, "one long frame step (0.25 s = 40 px) still hits the boar")

func test_boar_defeat_and_drops() -> void:
	var rig: Rig = make_rig()
	var nest: Nest = rig.field.add_nest(0, Vector2i(10, 10))
	var boar: Boar = put_boar(rig, Vector2(100, 80), nest)
	var origin: Vector2 = Vector2(60, 74)
	for shot_index: int in 3:
		check(rig.field.boars.has(boar), "before shot %d the boar is alive" % (shot_index + 1))
		shoot(rig, ProjectileField.KIND_SEED, origin, Vector2(140, 74))
	check(rig.field.boars.is_empty() and rig.field.total_killed == 1 and nest.boar_count == 0, "three seed shots defeat the boar")
	check(rig.landed.is_empty(), "none of the three shots landed")
	check(rig.field.carcasses.size() == 1 and rig.field.carcasses[0].pos == Vector2(100, 80), "the boar leaves a carcass where it fell")
	var items: Array[Dictionary] = rig.play.pickups.items
	check(items.size() == BOAR_FRUITS, "it drops %d seed fruits (%d)" % [BOAR_FRUITS, items.size()])
	var near: bool = true
	for item: Dictionary in items:
		var d: float = Vector2(float(item["x"]), float(item["y"])).distance_to(Vector2(100, 80))
		near = near and d <= 8.01 and String(item["kind"]) == "seed_fruit"
	check(near, "the fruits lie within 8 px of the spot")
	var seeds_before: int = rig.play.seeds
	rig.play.advance(0.02, Vector2(100, 80))
	check(rig.play.seeds == seeds_before + BOAR_FRUITS and rig.play.pickups.count() == 0, "walking over them collects both (+%d seeds)" % (rig.play.seeds - seeds_before))
	# Full pouch: the fruits stay on the ground.
	var rig2: Rig = make_rig()
	var nest2: Nest = rig2.field.add_nest(0, Vector2i(10, 10))
	var boar2: Boar = put_boar(rig2, Vector2(100, 80), nest2)
	rig2.play.add_seeds(100)
	rig2.field.damage_boar(boar2, 3)
	rig2.play.advance(0.02, Vector2(100, 80))
	check(rig2.play.seeds == play_tuning.seed_max and rig2.play.pickups.count() == BOAR_FRUITS, "with a full pouch the fruits are not taken")
	# Fruits have their own lifetime.
	rig2.play.advance(0.25, Vector2(500, 500))
	for i: int in 245:
		rig2.play.advance(0.25, Vector2(500, 500))
	check(rig2.play.pickups.count() == 0, "an uncollected fruit disappears after about a minute")

func test_nest_defeat() -> void:
	var rig: Rig = make_rig({"spawn_interval_seconds": 12.0})
	var nest: Nest = rig.field.add_nest(0, Vector2i(10, 10))
	var control: Nest = rig.field.add_nest(0, Vector2i(30, 30))
	run_time(rig.field, 13.0)
	check(nest.spawned == 1 and control.spawned == 1, "both nests spawned their first boar after 12 s")
	var block_ok: bool = true
	for y: int in range(10, 14):
		for x: int in range(10, 14):
			block_ok = block_ok and rig.world.occupant[rig.world.index_of(x, y)] == nest.owner_id()
	check(block_ok and not rig.field.spread_allows(rig.world.index_of(11, 11)), "while alive the nest holds its 4x4 block")
	for shot_index: int in 19:
		shoot(rig, ProjectileField.KIND_SEED, Vector2(20, 48), Vector2(100, 48))
	check(nest.alive and nest.hp == 1 and rig.field.total_nests_destroyed == 0, "after 19 shots the nest has 1 hit point left")
	shoot(rig, ProjectileField.KIND_SEED, Vector2(20, 48), Vector2(100, 48))
	check(not nest.alive and nest.hp == 0 and rig.field.total_nests_destroyed == 1, "the 20th shot destroys the nest")
	var free_ok: bool = true
	for y: int in range(10, 14):
		for x: int in range(10, 14):
			free_ok = free_ok and rig.world.occupant[rig.world.index_of(x, y)] == 0
	check(free_ok and rig.field.spread_allows(rig.world.index_of(11, 11)) and not rig.world.occupancy_owners.has(nest.owner_id()), "its tiles are free again (planting is allowed)")
	check(rig.play.pickups.count() == NEST_FRUITS, "it drops %d seed fruits (%d)" % [NEST_FRUITS, rig.play.pickups.count()])
	var inside: bool = true
	for item: Dictionary in rig.play.pickups.items:
		inside = inside and Vector2(float(item["x"]), float(item["y"])).distance_to(Vector2(48, 48)) <= 8.01
	check(inside, "the fruits lie around the nest centre")
	var spawned_before: int = nest.spawned
	var control_before: int = control.spawned
	run_time(rig.field, 60.0)
	check(nest.spawned == spawned_before and control.spawned > control_before, "the destroyed nest spawns no more; the other nest still does (%d -> %d)" % [control_before, control.spawned])
	# Shot 21 passes through the empty place and lands.
	rig.landed.clear()
	shoot(rig, ProjectileField.KIND_SEED, Vector2(20, 48), Vector2(100, 48))
	check(rig.landed.size() == 1 and not nest.alive, "after the nest is gone a shot flies through its place and lands")
	# A seed can now be planted on its tiles by a landing at the old centre.
	var rig_land: Rig = rig
	rig_land.play.land_seed(Vector2(48, 48))
	var planted_in_block: int = 0
	for y: int in range(10, 14):
		for x: int in range(10, 14):
			planted_in_block += 1 if rig.world.stage[rig.world.index_of(x, y)] != WorldState.STAGE_EMPTY else 0
	check(planted_in_block > 0, "seeds can be planted on the freed tiles (%d tiles)" % planted_in_block)
	# The boar that came out of the nest stays after the nest is gone.
	check(rig.field.boars.size() >= 1, "boars that already came out of the destroyed nest stay")

func test_drop_slots() -> void:
	var sources: Array[Vector2] = [Vector2(300, 200), Vector2(320, 200)]
	# Two sources keep 2 x 3 = 6 of the 24 slots: the plant-owned share (fruits of plants and enemies) is at most 18.
	for prefill: int in [0, 10, 16, 17, 18]:
		var rig: Rig = make_rig({}, sources)
		for i: int in prefill:
			rig.play.pickups.spawn(GroundPickups.KIND_SEED_FRUIT, Vector2(200 + i, 200), GroundPickups.PLANT_OWNER_BASE + i)
		var nest: Nest = rig.field.add_nest(0, Vector2i(10, 10))
		var boar: Boar = put_boar(rig, Vector2(100, 80), nest)
		rig.field.damage_boar(boar, 3)
		var expected: int = clampi(18 - prefill, 0, BOAR_FRUITS)
		var enemy_owned: int = 0
		for item: Dictionary in rig.play.pickups.items:
			enemy_owned += 1 if int(item["owner"]) >= GroundPickups.ENEMY_OWNER_BASE else 0
		check(enemy_owned == expected and rig.combat.fruits_dropped == expected and rig.combat.fruits_refused == BOAR_FRUITS - expected, "with %d plant fruits on the ground the boar drops %d of %d fruits" % [prefill, enemy_owned, BOAR_FRUITS])
		# The sources can still fill their own slots completely.
		var source_ok: bool = true
		for source: SeedSource in rig.play.sources:
			for k: int in 3:
				source_ok = source_ok and rig.play.pickups.spawn(GroundPickups.KIND_SEED_FRUIT, Vector2(source.position), source.id)
		check(source_ok and rig.play.pickups.count_seed_items() <= 24, "the seed sources still get their 3 + 3 slots (total %d <= 24)" % rig.play.pickups.count_seed_items())
	# Nest reward under the same rule: 15 plant fruits leave room for 3 of 4.
	var rig2: Rig = make_rig({}, sources)
	for i: int in 15:
		rig2.play.pickups.spawn(GroundPickups.KIND_SEED_FRUIT, Vector2(200 + i, 200), GroundPickups.PLANT_OWNER_BASE + i)
	var nest2: Nest = rig2.field.add_nest(0, Vector2i(10, 10))
	rig2.field.damage_nest(nest2, NEST_HP)
	check(rig2.combat.fruits_dropped == 3 and rig2.combat.fruits_refused == 1, "a nest reward fills only the 3 slots left (dropped %d, refused %d)" % [rig2.combat.fruits_dropped, rig2.combat.fruits_refused])
	# Owner bands do not collide: boar fruit owner never equals a tile-index plant owner or a healing fruit owner.
	check(GroundPickups.ENEMY_OWNER_BASE > GroundPickups.HEAL_OWNER_BASE + 1000000 and GroundPickups.ENEMY_OWNER_BASE > GroundPickups.PLANT_OWNER_BASE + 600 * 600, "the enemy owner band lies above plant tile owners and healing fruit owners")

func test_carcass_fertility() -> void:
	var rig: Rig = make_rig()
	var nest: Nest = rig.field.add_nest(0, Vector2i(5, 5))
	var pos: Vector2 = Vector2(42.0, 30.0)
	var boar: Boar = put_boar(rig, pos, nest)
	check(fertility_matches(rig.world, []), "the world starts without any fertility")
	rig.field.damage_boar(boar, 3)
	var disk: int = 0
	for y: int in rig.world.height:
		for x: int in rig.world.width:
			var f: int = int(rig.world.fertility[rig.world.index_of(x, y)])
			disk += 1 if f > 0 else 0
	# Lattice points with dx^2 + dy^2 <= 16 around the centre tile: 49 (counted by hand: 1 + 4*... = 49).
	check(disk == 49, "the carcass raises exactly the 49 tiles whose centres are within 4 tiles (%d)" % disk)
	check(fertility_matches(rig.world, [[pos, 0]]), "every tile of the map has the brute-force expected fertility (40 inside, 0 outside)")
	var centre_index: int = rig.world.index_of(10, 7)
	check(int(rig.world.fertility[centre_index]) == FERT_CORPSE, "the tile under the carcass has fertility 40")
	# A carcass on the map corner is clipped to the map.
	var rig2: Rig = make_rig()
	var corner: Boar = put_boar(rig2, Vector2(2, 2), null)
	rig2.field.damage_boar(corner, 3)
	check(fertility_matches(rig2.world, [[Vector2(2, 2), 0]]), "a carcass at the map corner raises only the tiles that exist")

func test_growth_speed() -> void:
	var rig: Rig = make_rig()
	var nest: Nest = rig.field.add_nest(0, Vector2i(5, 5))
	var pos: Vector2 = Vector2(42.0, 32.0)
	var inside: PackedInt32Array = PackedInt32Array([rig.world.index_of(10, 7), rig.world.index_of(12, 7), rig.world.index_of(8, 8)])
	var outside: PackedInt32Array = PackedInt32Array([rig.world.index_of(10, 20), rig.world.index_of(16, 7), rig.world.index_of(24, 7)])
	for index: int in inside:
		rig.world.set_stage(index, WorldState.STAGE_SEED)
	for index: int in outside:
		rig.world.set_stage(index, WorldState.STAGE_SEED)
	var growth: GrowthSim = GrowthSim.new(rig.world, sim_tuning)
	rig.field.damage_boar(put_boar(rig, pos, nest), 3)
	# Expected from the design: base 1000 per tick, factor 1 + 0.5 * 40 / 100 = 1.2 -> 1200 per tick with the carcass.
	# Mature at 120000: 100 ticks (50 s) inside, 120 ticks (60 s) outside.
	var first_mature_in: int = -1
	var first_mature_out: int = -1
	for tick: int in range(1, 131):
		growth.tick()
		growth.catch_up()
		var in_stage: int = rig.world.stage[inside[0]]
		var out_stage: int = rig.world.stage[outside[0]]
		if first_mature_in < 0 and in_stage == WorldState.STAGE_MATURE:
			first_mature_in = tick
		if first_mature_out < 0 and out_stage == WorldState.STAGE_MATURE:
			first_mature_out = tick
		if tick == 50:
			check(rig.world.growth[inside[0]] == 50 * 1200 and rig.world.growth[outside[0]] == 50 * 1000, "after 50 ticks: %d growth inside (expected 60000), %d outside (expected 50000)" % [rig.world.growth[inside[0]], rig.world.growth[outside[0]]])
	check(first_mature_in == 100 and first_mature_out == 120, "a seed beside the carcass is mature after 100 ticks, one far away after 120 (%d / %d)" % [first_mature_in, first_mature_out])
	var all_equal: bool = true
	for index: int in inside:
		all_equal = all_equal and rig.world.stage[index] == WorldState.STAGE_MATURE
	check(all_equal, "all three inside tiles matured")
	info["growth_ticks_mature_inside_outside"] = [first_mature_in, first_mature_out]

func test_timeline() -> void:
	var rig: Rig = make_rig()
	var pos: Vector2 = Vector2(42.0, 32.0)
	var centre: int = rig.world.index_of(10, 8)
	rig.field.damage_boar(put_boar(rig, pos, null), 3)
	var ok: Dictionary = {}
	var dt: float = 1.0 / 60.0
	var stages: Dictionary = {}
	for i: int in range(1, 6001):
		rig.field.advance(dt)
		if i == 3599 or i == 3600 or i == 5999 or i == 6000:
			stages[i] = [rig.field.carcasses.size(), (rig.field.carcasses[0].stage if rig.field.carcasses.size() > 0 else -1), int(rig.world.fertility[centre])]
	check(stages[3599] == [1, 0, 40], "after 3599 steps (59.98 s) it is still a carcass with fertility 40: %s" % [stages[3599]])
	check(stages[3600] == [1, 1, 20], "after 3600 steps (60 s) it is bone with fertility 20: %s" % [stages[3600]])
	check(stages[5999] == [1, 1, 20], "after 5999 steps it is still bone: %s" % [stages[5999]])
	check(stages[6000] == [0, -1, 0], "after 6000 steps (100 s) it is gone and the fertility is back to 0: %s" % [stages[6000]])
	check(fertility_matches(rig.world, []), "the whole map has no carcass fertility left")
	check(rig.field.carcass_count(0) == 0 and rig.field.carcass_count(1) == 0, "no carcass and no bone remain")

func test_cap_and_overlap() -> void:
	# Cap: 30 kills one second apart on separate spots; at most 24 stay, the newest ones.
	var rig: Rig = make_rig()
	var list: Array = []
	var max_seen: int = 0
	var ids: Array[int] = []
	for k: int in 30:
		var pos: Vector2 = Vector2(24.0 + 48.0 * float(k % 6), 24.0 + 48.0 * float(k / 6))
		rig.field.damage_boar(put_boar(rig, pos, null), 3)
		max_seen = maxi(max_seen, rig.field.carcasses.size())
		run_time(rig.field, 1.0)
	check(max_seen == CARCASS_CAP and rig.field.carcasses.size() == CARCASS_CAP, "carcasses and bones together never exceed 24 (max seen %d)" % max_seen)
	var expected_list: Array = []
	for k: int in range(6, 30):
		expected_list.append([Vector2(24.0 + 48.0 * float(k % 6), 24.0 + 48.0 * float(k / 6)), 0])
	var kept_ok: bool = true
	for i: int in CARCASS_CAP:
		kept_ok = kept_ok and rig.field.carcasses[i].pos == Vector2(expected_list[i][0])
	check(kept_ok, "the 24 newest stay (the 6 oldest went first)")
	check(fertility_matches(rig.world, expected_list), "the fertility of the map matches the 24 that stay (the 6 removed ones left nothing behind)")
	# Mixed stages with the cap: bones count too.
	var rig2: Rig = make_rig()
	for k: int in 10:
		rig2.field.damage_boar(put_boar(rig2, Vector2(24.0 + 36.0 * float(k), 24.0), null), 3)
	run_time(rig2.field, 70.0)
	for k: int in 20:
		rig2.field.damage_boar(put_boar(rig2, Vector2(24.0 + 18.0 * float(k % 20), 120.0), null), 3)
	check(rig2.field.carcasses.size() == CARCASS_CAP, "10 bones + 20 fresh carcasses: 24 remain (%d)" % rig2.field.carcasses.size())
	check(rig2.field.carcass_count(1) == 4 and rig2.field.carcass_count(0) == 20, "the oldest 6 bones went, 4 bones and 20 carcasses remain (%d / %d)" % [rig2.field.carcass_count(1), rig2.field.carcass_count(0)])
	# Overlap: values add up but are rounded down to 60.
	var rig3: Rig = make_rig()
	var pos3: Vector2 = Vector2(42.0, 32.0)
	var centre: int = rig3.world.index_of(10, 8)
	rig3.field.damage_boar(put_boar(rig3, pos3, null), 3)
	check(int(rig3.world.fertility[centre]) == 40, "one carcass: 40")
	rig3.field.damage_boar(put_boar(rig3, pos3, null), 3)
	check(int(rig3.world.fertility[centre]) == 60, "two carcasses on one spot: 40 + 40 = 80 is rounded to 60")
	rig3.field.damage_boar(put_boar(rig3, pos3, null), 3)
	check(int(rig3.world.fertility[centre]) == 60, "three carcasses: still 60")
	# Staggered end: kills at 0 s, 0 s, 0 s; one more spot partly overlapping.
	var rig4: Rig = make_rig()
	var a: Vector2 = Vector2(42.0, 32.0)
	var b: Vector2 = Vector2(58.0, 32.0)
	rig4.field.damage_boar(put_boar(rig4, a, null), 3)
	run_time(rig4.field, 30.0)
	rig4.field.damage_boar(put_boar(rig4, b, null), 3)
	var both: int = rig4.world.index_of(12, 8)
	check(int(rig4.world.fertility[both]) == 80 - 20 and fertility_matches(rig4.world, [[a, 0], [b, 0]]), "30 s in: two corpses overlap on the middle tiles and are rounded to 60")
	run_time(rig4.field, 30.5)
	check(fertility_matches(rig4.world, [[a, 1], [b, 0]]) and int(rig4.world.fertility[both]) == 60, "60.5 s: first is bone (20), second a corpse (40): 60 in the overlap")
	run_time(rig4.field, 30.0)
	check(fertility_matches(rig4.world, [[a, 1], [b, 1]]) and int(rig4.world.fertility[both]) == 40, "90.5 s: both are bones: 20 + 20 = 40 in the overlap")
	run_time(rig4.field, 10.0)
	check(fertility_matches(rig4.world, [[b, 1]]), "100.5 s: the first bone is gone; only the second one's 20 remains")
	run_time(rig4.field, 30.0)
	check(fertility_matches(rig4.world, []) and rig4.field.carcasses.is_empty(), "130.5 s: everything is gone")

func test_restore_base() -> void:
	var rig: Rig = make_rig()
	for index: int in rig.world.tile_count():
		rig.world.fertility[index] = 10 if index % 7 == 0 else 0
	var base: PackedByteArray = rig.world.fertility.duplicate()
	var pos: Vector2 = Vector2(42.0, 32.0)
	rig.field.damage_boar(put_boar(rig, pos, null), 3)
	rig.field.damage_boar(put_boar(rig, pos, null), 3)
	var raised: bool = false
	for index: int in rig.world.tile_count():
		raised = raised or rig.world.fertility[index] != base[index]
	check(raised, "carcasses add to a non-zero base fertility")
	run_time(rig.field, 100.5)
	check(rig.world.fertility == base, "when the bones are gone the fertility is exactly the base again (restored, not left behind)")
	# Bone stage is a step down, not a restore: staged decrease 40 -> 20 -> base.
	var rig2: Rig = make_rig()
	for index: int in rig2.world.tile_count():
		rig2.world.fertility[index] = 10
	rig2.field.damage_boar(put_boar(rig2, pos, null), 3)
	var centre: int = rig2.world.index_of(10, 8)
	var seen: Array[int] = [int(rig2.world.fertility[centre])]
	run_time(rig2.field, 61.0)
	seen.append(int(rig2.world.fertility[centre]))
	run_time(rig2.field, 40.0)
	seen.append(int(rig2.world.fertility[centre]))
	check(seen == [50, 30, 10], "the decrease is staged: 10 + 40, then 10 + 20 as bone, then the base 10: %s" % [seen])

func test_flash() -> void:
	var rig: Rig = make_rig()
	var nest: Nest = rig.field.add_nest(0, Vector2i(10, 10))
	var boar: Boar = put_boar(rig, Vector2(100, 80), nest)
	rig.field.damage_boar(boar, 1)
	check(boar.flash_steps == 15 and rig.field.flash_bright(boar.flash_steps), "a hit starts the flash in its bright half")
	var pattern: String = ""
	for i: int in 16:
		pattern += "1" if rig.field.flash_bright(boar.flash_steps) else "0"
		rig.field.advance(1.0 / 60.0)
	check(boar.flash_steps == 0, "the flash runs out after 15 steps")
	check(pattern == "111000111000111" + "0", "it blinks every 3 steps (0.05 s): %s" % pattern)
	# No time, no flash progress.
	rig.field.damage_boar(boar, 1)
	var before: int = boar.flash_steps
	check(before == 15, "second hit flashes again")
	rig.field.advance(0.0)
	check(boar.flash_steps == before, "without advance() (a paused game) the flash stands still")
	# Killing blow: no flash, the boar is gone.
	rig.field.damage_boar(boar, 1)
	check(not rig.field.boars.has(boar), "the third hit kills")

func test_frame_rates() -> void:
	var results: Dictionary = {}
	for hz: int in [30, 60, 144]:
		var rig: Rig = make_rig()
		rig.field.damage_boar(put_boar(rig, Vector2(42, 32), null), 3)
		var centre: int = rig.world.index_of(10, 8)
		var dt: float = 1.0 / float(hz)
		var observed: Array = []
		var t: float = 0.0
		for target: float in [59.9, 60.2, 99.9, 100.2]:
			while t < target:
				rig.field.advance(dt)
				t += dt
			observed.append([rig.field.carcasses.size(), int(rig.world.fertility[centre])])
		results[hz] = observed
	var expected: Array = [[1, 40], [1, 20], [1, 20], [0, 0]]
	check(results[30] == expected and results[60] == expected and results[144] == expected, "corpse 60 s, bone 40 s, gone at 100 s at 30, 60 and 144 Hz alike: %s" % [results])
	# Flash length is the same at all rates too.
	var lengths: Array = []
	for hz: int in [30, 60, 144]:
		var rig: Rig = make_rig()
		var nest: Nest = rig.field.add_nest(0, Vector2i(10, 10))
		var boar: Boar = put_boar(rig, Vector2(100, 80), nest)
		rig.field.damage_boar(boar, 1)
		var t: float = 0.0
		while boar.flash_steps > 0:
			rig.field.advance(1.0 / float(hz))
			t += 1.0 / float(hz)
		lengths.append(snappedf(t, 0.01))
	check(absf(lengths[0] - 0.25) < 0.04 and absf(lengths[1] - 0.25) < 0.02 and absf(lengths[2] - 0.25) < 0.02, "the flash lasts about 0.25 s at 30 / 60 / 144 Hz (%s)" % [lengths])

func make_saved_rig() -> Rig:
	var rig: Rig = make_rig({"spawn_interval_seconds": 12.0})
	var nest: Nest = rig.field.add_nest(0, Vector2i(10, 10))
	rig.field.add_nest(0, Vector2i(30, 30))
	run_time(rig.field, 20.0)
	rig.field.damage_boar(put_boar(rig, Vector2(100, 120), nest), 3)
	run_time(rig.field, 40.0)
	rig.field.damage_boar(put_boar(rig, Vector2(120, 120), nest), 3)
	run_time(rig.field, 30.0)
	rig.field.damage_boar(put_boar(rig, Vector2(130, 130), nest), 3)
	rig.field.damage_nest(nest, 5)
	if not rig.field.boars.is_empty():
		rig.field.damage_boar(rig.field.boars[0], 1)
	return rig

func state_text(field: EnemyField, world: WorldState) -> String:
	return JSON.stringify(field.to_dict()) + str(hash(world.fertility))

func test_save_round_trip() -> void:
	var rig: Rig = make_saved_rig()
	check(rig.field.carcass_count(0) == 2 and rig.field.carcass_count(1) == 1, "setup: two carcasses and one bone (%d / %d)" % [rig.field.carcass_count(0), rig.field.carcass_count(1)])
	var saved_world: Dictionary = rig.world.to_dict()
	var saved: Dictionary = rig.field.to_dict()
	var world2: WorldState = WorldState.from_dict(saved_world, rig.world.terrain_defs)
	var field2: EnemyField = EnemyField.new(world2, tune({"spawn_interval_seconds": 12.0}), TILE)
	check(field2.load_dict(saved), "the field loads onto the restored world (which holds the fertility)")
	check(JSON.stringify(field2.to_dict()) == JSON.stringify(saved) and world2.fertility == rig.world.fertility, "carcasses (position, age), flashes, boars, nests and the fertility survive the round trip")
	var flashing: bool = false
	for boar: Boar in field2.boars:
		flashing = flashing or boar.flash_steps > 0
	for nest: Nest in field2.nests:
		flashing = flashing or nest.flash_steps > 0
	check(flashing, "a flash in progress is saved and restored")
	for i: int in range(1, 60 * 90 + 1):
		rig.field.advance(1.0 / 60.0)
		field2.advance(1.0 / 60.0)
	check(state_text(rig.field, rig.world) == state_text(field2, world2), "after loading, the next 90 s (bone, vanish, fertility) run exactly like the original")
	# JSON text.
	var saved2: Dictionary = make_saved_rig().field.to_dict()
	var parsed: Variant = JSON.parse_string(JSON.stringify(saved2))
	var rig_j: Rig = make_saved_rig()
	var world_j: WorldState = WorldState.from_dict(rig_j.world.to_dict(), rig_j.world.terrain_defs)
	var field_j: EnemyField = EnemyField.new(world_j, tune({"spawn_interval_seconds": 12.0}), TILE)
	check(parsed is Dictionary and field_j.load_dict(parsed) and JSON.stringify(field_j.to_dict()) == JSON.stringify(saved2), "the data also loads from JSON text")
	# A fresh world without the layer: the field adds it itself.
	var base_world: WorldState = small_world()
	var field3: EnemyField = EnemyField.new(base_world, tune({"spawn_interval_seconds": 12.0}), TILE)
	check(not field3.load_dict(saved), "world_has_layer: a world without the saved fertility refuses the data")
	check(field3.carcasses.is_empty() and base_world.fertility == small_world().fertility, "the refused load left the field and the world unchanged")
	var loaded_plain: bool = field3.load_dict(saved, false)
	var again: Rig = make_saved_rig()
	var raised_tiles: int = 0
	for index: int in again.world.tile_count():
		raised_tiles += 1 if again.world.fertility[index] > 0 else 0
	check(loaded_plain and base_world.fertility == again.world.fertility and raised_tiles > 100, "loading with world_has_layer = false adds the fertility; it equals the original's (%d tiles raised)" % raised_tiles)
	check(field3.load_dict(saved, false) and base_world.fertility == again.world.fertility, "loading the same data again does not add it twice")
	# Bad data is refused and leaves the state alone.
	var before: String = state_text(field3, base_world)
	var bad_bounds: Dictionary = saved.duplicate(true)
	bad_bounds["carcasses"][0]["x"] = 99999.0
	check(not field3.load_dict(bad_bounds, false) and state_text(field3, base_world) == before, "a carcass outside the map is refused")
	var bad_dup: Dictionary = saved.duplicate(true)
	bad_dup["carcasses"][1]["id"] = bad_dup["carcasses"][0]["id"]
	check(not field3.load_dict(bad_dup, false) and state_text(field3, base_world) == before, "duplicate carcass ids are refused")
	var bad_age: Dictionary = saved.duplicate(true)
	bad_age["carcasses"][0]["age"] = 6000
	check(not field3.load_dict(bad_age, false) and state_text(field3, base_world) == before, "a carcass older than its life is refused")
	var older: Dictionary = {"version": 1}
	var field4: EnemyField = EnemyField.new(small_world(), tune(), TILE)
	check(field4.load_dict(older) and field4.carcasses.is_empty(), "data without carcasses (a P2-01 save) still loads")

func test_performance() -> void:
	var rig: Rig = make_rig()
	var nest: Nest = rig.field.add_nest(0, Vector2i(10, 10))
	for k: int in CARCASS_CAP:
		rig.field.damage_boar(put_boar(rig, Vector2(24.0 + 48.0 * float(k % 6), 24.0 + 48.0 * float(k / 6)), nest), 3)
	var started: int = Time.get_ticks_usec()
	for i: int in 3000:
		rig.field.advance(1.0 / 60.0)
	var per_step: float = float(Time.get_ticks_usec() - started) / 3000.0
	info["advance_us_per_step_24_carcasses"] = per_step
	check(per_step < 1000.0, "24 carcasses add little cost (%.1f us per step)" % per_step)
	var started2: int = Time.get_ticks_usec()
	for i: int in 200:
		rig.proj.advance(1.0 / 60.0)
	info["hit_provider_us"] = float(Time.get_ticks_usec() - started2) / 200.0

# ---- scene (injected input only) -------------------------------------------------------------------------------------

func wait_frames(count: int) -> void:
	for i: int in count:
		await physics_frame
	await process_frame

func aim_at(world_point: Vector2) -> Vector2:
	var guess: Vector2 = world_point - player.position + Vector2(320, 180)
	var achieved: Vector2 = Vector2.ZERO
	for attempt: int in 3:
		var motion: InputEventMouseMotion = InputEventMouseMotion.new()
		motion.position = guess
		motion.global_position = guess
		mouse_screen = guess
		Input.parse_input_event(motion)
		await process_frame
		achieved = player.get_global_mouse_position()
		if achieved.distance_to(world_point) < 0.6:
			break
		guess += world_point - achieved
	return achieved

func click(button: MouseButton) -> void:
	var down: InputEventMouseButton = InputEventMouseButton.new()
	down.button_index = button
	down.pressed = true
	down.position = mouse_screen
	down.global_position = mouse_screen
	Input.parse_input_event(down)
	await process_frame
	var up: InputEventMouseButton = InputEventMouseButton.new()
	up.button_index = button
	up.pressed = false
	up.position = mouse_screen
	up.global_position = mouse_screen
	Input.parse_input_event(up)
	await process_frame

func teleport(location: Vector2) -> void:
	player.simulation_position = location
	await wait_frames(3)

func test_scene() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await wait_frames(3)
	player = main.player
	var play: PlayState = main.play
	var world: WorldState = main.grid
	var enemies: EnemyField = main.enemies
	var growth: GrowthSim = main.simulation.growth
	check(main.enemy_combat != null and main.projectile_view.enemy_hit_provider.is_valid(), "scene: the shot field is connected to the enemies")
	# One boar from the first nest, standing still; no other enemy may disturb the picture.
	var nest: Nest = enemies.nests[0]
	check(enemies._spawn(nest) and enemies.boars.size() == 1, "scene: a boar came out of nest 1")
	var boar: Boar = enemies.boars[0]
	boar.wait = 1 << 30
	for other: Nest in enemies.nests:
		enemies.destroy_nest(other)
	await wait_frames(3)
	check(main.enemy_view.ruin_sprites.size() == 15 and main.enemy_view.nest_sprites.is_empty(), "scene: a ruin is shown for each of the 15 destroyed nests")
	var away: Vector2 = (boar.pos - nest.center_px(TILE)).normalized()
	await teleport(boar.pos + away * 36.0)
	var seeds_start: int = play.seeds
	var landings_start: int = play.landing_counter
	var centre: Vector2 = enemies.boar_body_center(boar)
	# Shot 1.
	await aim_at(centre)
	await click(MOUSE_BUTTON_LEFT)
	await wait_frames(17)
	check(boar.hp == 2 and play.seeds == seeds_start - 1, "scene: the first injected click takes 1 hit point and costs 1 seed (hp %d, seeds %d)" % [boar.hp, play.seeds])
	check(play.landing_counter == landings_start, "scene: the hit seed did not land (no planting)")
	var flash_a: int = boar.flash_steps
	check(flash_a > 0 and flash_a <= 15, "scene: the boar flashes after the hit (%d steps left)" % flash_a)
	# Pause: the flash stands still.
	paused = true
	await wait_frames(30)
	check(boar.flash_steps == flash_a, "scene: while paused the flash stands still (%d == %d)" % [boar.flash_steps, flash_a])
	paused = false
	await wait_frames(20)
	check(boar.flash_steps == 0, "scene: after resuming the flash runs out")
	for shot: int in 2:
		await aim_at(centre)
		await click(MOUSE_BUTTON_LEFT)
		await wait_frames(24)
	check(enemies.boars.is_empty() and enemies.total_killed == 1, "scene: three injected clicks defeat the boar")
	check(play.seeds == seeds_start - 3 and play.landing_counter == landings_start, "scene: the three seeds are spent and none landed")
	check(enemies.carcasses.size() == 1 and main.enemy_view.carcass_sprites.size() == 1, "scene: a carcass lies there and is shown")
	var fruit_count: int = play.pickups.count_owned(GroundPickups.ENEMY_OWNER_BASE + boar.id)
	check(fruit_count == BOAR_FRUITS, "scene: it dropped %d seed fruits" % fruit_count)
	# Carcass timer stands still while paused.
	var carcass: Carcass = enemies.carcasses[0]
	var age: int = carcass.age_steps
	paused = true
	await wait_frames(30)
	check(carcass.age_steps == age, "scene: while paused the carcass does not age")
	paused = false
	# Collect the fruit.
	var spot: Vector2 = carcass.pos
	await teleport(spot)
	check(play.seeds == seeds_start - 3 + BOAR_FRUITS and play.pickups.count_owned(GroundPickups.ENEMY_OWNER_BASE + boar.id) == 0, "scene: standing on the spot collects both fruits (seeds %d)" % play.seeds)
	# Plant by an injected click at the carcass, and control tiles far away.
	await teleport(spot + away * 36.0)
	await aim_at(spot)
	await click(MOUSE_BUTTON_LEFT)
	await wait_frames(24)
	var near_tiles: PackedInt32Array = play.last_scatter
	check(play.landing_counter == landings_start + 1 and near_tiles.size() > 0, "scene: the click at the carcass landed and planted %d tiles" % near_tiles.size())
	var fertile_ok: bool = true
	for index: int in near_tiles:
		fertile_ok = fertile_ok and world.fertility[index] == FERT_CORPSE
	check(fertile_ok, "scene: every planted tile stands on fertility 40")
	var far_tiles: PackedInt32Array = PackedInt32Array()
	var spot_tile: Vector2i = Vector2i(floori(spot.x / TILE), floori(spot.y / TILE))
	for dy: int in range(-4, 5):
		for dx: int in range(12, 24):
			var x: int = spot_tile.x + dx
			var y: int = spot_tile.y + dy
			if far_tiles.size() < 6 and world.in_bounds(x, y):
				var index: int = world.index_of(x, y)
				if world.occupant[index] == 0 and world.target[index] != 0 and world.stage[index] == WorldState.STAGE_EMPTY and world.set_stage(index, WorldState.STAGE_SEED):
					far_tiles.append(index)
	check(far_tiles.size() == 6, "scene: six control seeds were set far from the carcass")
	await wait_frames(2)
	growth.catch_up()
	var near_before: Dictionary = {}
	var far_before: Dictionary = {}
	for index: int in near_tiles:
		near_before[index] = world.growth[index]
	for index: int in far_tiles:
		far_before[index] = world.growth[index]
	var ticks_before: int = growth.ticks
	Engine.time_scale = 6.0
	var guard: int = 0
	while growth.ticks - ticks_before < 40 and guard < 20000:
		await physics_frame
		guard += 1
	Engine.time_scale = 1.0
	growth.catch_up()
	var delta_ticks: int = growth.ticks - ticks_before
	var near_ok: bool = true
	var far_ok: bool = true
	var dry: bool = true
	for index: int in near_tiles:
		near_ok = near_ok and world.growth[index] - int(near_before[index]) == delta_ticks * 1200
		dry = dry and world.moisture[index] == 0
	for index: int in far_tiles:
		far_ok = far_ok and world.growth[index] - int(far_before[index]) == delta_ticks * 1000
		dry = dry and world.moisture[index] == 0
	check(dry, "scene: all measured tiles are dry (moisture 0)")
	check(delta_ticks >= 40 and near_ok, "scene: seeds beside the carcass gained exactly 1200 per tick over %d ticks" % delta_ticks)
	check(far_ok, "scene: control seeds far away gained exactly 1000 per tick")
	check(enemies.carcasses.size() == 1 and enemies.carcasses[0].stage == Carcass.STAGE_CORPSE, "scene: the carcass is still a carcass (stage %d, %d s of game time)" % [enemies.carcasses[0].stage, enemies.carcasses[0].age_steps / 60])
	info["scene_delta_ticks"] = delta_ticks
	Engine.time_scale = 1.0
	main.queue_free()
	await process_frame
