extends SceneTree
## P2-03 headless checks: contact damage (geometry, 2 HP, invulnerability 1.2 s, knockback 12 px against the map), being downed
## (HP 0, 1.5 s lying, return to the start with full HP, 2 s invulnerability), what is NOT rolled back, the world going on while
## downed, kiwi healing, the enemy drops' own slot (+ direct credit when it is full), the HUD, pause, 30 / 60 / 144 Hz, saves, and the
## real scene (injected key input only): walk into a boar -> hurt -> downed -> back at the start.
## Run: Godot --headless --path <project> --script res://tests/p2/p2_03_checks.gd
## Expected values come from the design written here (contact 2 HP, invulnerability 1.2 s = 72 steps of 1/60 s, knockback 12 px,
## lying 1.5 s = 90 steps, return invulnerability 2.0 s, HP 10, enemy slot 12, plant slot 20, 3 per seed source, total = their sum)
## and from brute-force geometry (body circle radius 8 whose centre is 6 px above the boar's feet; the player's feet rectangle is
## +-3 x +-2 px); they are not read back from the implementation's own tables.

const REGION_PATH: String = "res://data/region_01.tres"
const TILE: int = 4
const HP_MAX: int = 10
const CONTACT: int = 2
const INVULN_STEPS: int = 72
const DOWNED_STEPS: int = 90
const RETURN_INVULN_STEPS: int = 120
const ENEMY_SLOT: int = 12
const PLANT_SLOT: int = 20
const SOURCE_SLOT: int = 3
const BOAR_FRUITS: int = 2
const NEST_FRUITS: int = 4

var failures: int = 0
var checks: int = 0
var region_def: RegionDef
var sim_tuning: SimTuning
var play_tuning: PlayTuning
var enemy_tuning: EnemyTuning
var info: Dictionary = {}

# Scene helpers.
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
	test_contact_geometry()
	test_invulnerability_cycle()
	test_knockback()
	test_downed_pickups_and_controls()
	test_nothing_rolled_back()
	test_world_goes_on()
	test_loss_fractions()
	test_kiwi_heal()
	test_enemy_slot()
	test_drop_direct_credit()
	test_driver_wiring()
	test_hud_text()
	test_frame_rates()
	test_save_round_trip()
	test_performance()
	await test_scene()
	print("INFO " + JSON.stringify(info))
	print("P2_03_RESULT checks=%d failures=%d" % [checks, failures])
	var file: FileAccess = FileAccess.open(ProjectSettings.globalize_path("res://evidence/p2/p2-03/checks_info.json"), FileAccess.WRITE)
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

func tuned(source: Resource, overrides: Dictionary) -> Resource:
	var copy: Resource = source.duplicate()
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
	## The player's feet (px) as a stand-in for the FlowerPlayer node: the health signals move it.
	var pos: Vector2 = Vector2(100, 80)
	var start: Vector2 = Vector2(20, 20)
	var half: Vector2 = Vector2(3, 2)
	var t: float = 0.0
	var steps: int = 0
	var run_field: bool = false
	var events: Array = []

## `play_over` / `enemy_over` replace tuning values (copies; the data files are untouched).
func make_rig(play_over: Dictionary = {}, enemy_over: Dictionary = {}, sources: Array[Vector2] = []) -> Rig:
	var rig: Rig = Rig.new()
	rig.world = small_world()
	var enemy_merged: Dictionary = {"spawn_interval_seconds": 100000.0}
	enemy_merged.merge(enemy_over, true)
	var ptuning: PlayTuning = tuned(play_tuning, play_over) as PlayTuning
	rig.field = EnemyField.new(rig.world, tuned(enemy_tuning, enemy_merged) as EnemyTuning, TILE)
	var defs: Array[PlantDef] = []
	defs.assign(region_def.plants)
	rig.play = PlayState.new(rig.world, ptuning, sim_tuning, TILE, sources, defs)
	rig.play.enemies = rig.field
	rig.combat = EnemyCombat.new(rig.field, rig.play)
	rig.play.health.respawn_position = rig.start
	rig.play.health.knocked.connect(func(motion: Vector2) -> void: rig.pos = Walker.move(rig.world, TILE, rig.pos, motion, rig.half))
	rig.play.health.revived.connect(func(location: Vector2) -> void:
		rig.pos = location
		rig.events.append(["revived", rig.steps]))
	rig.play.health.downed_started.connect(func() -> void: rig.events.append(["downed", rig.steps]))
	rig.play.health.damaged.connect(func(amount: int, _source: Vector2) -> void: rig.events.append(["damaged", rig.steps, amount]))
	return rig

func put_boar(rig: Rig, pos: Vector2, waits: bool = true) -> Boar:
	var boar: Boar = Boar.new()
	boar.id = rig.field.next_boar_id
	rig.field.next_boar_id += 1
	boar.zone = 0
	boar.pos = pos
	boar.home = pos
	boar.hp = rig.field.tuning.boar_hp
	boar.wait = (1 << 30) if waits else 0
	boar.rng = 1
	rig.field.boars.append(boar)
	return boar

## Advances the rig by one 1/hz step of game time (play first, then the enemies, like the scene's driver order).
func tick(rig: Rig, hz: int = 60) -> void:
	var dt: float = 1.0 / float(hz)
	rig.t += dt
	rig.steps = roundi(rig.t * 60.0)
	rig.play.advance(dt, rig.pos)
	if rig.run_field:
		rig.field.advance(dt)

func run_for(rig: Rig, seconds: float, hz: int = 60) -> void:
	for i: int in roundi(seconds * float(hz)):
		tick(rig, hz)

func log_steps(rig: Rig, kind: String) -> Array:
	var result: Array = []
	for entry: Array in rig.events:
		if String(entry[0]) == kind:
			result.append(int(entry[1]))
	return result

# ---- tests ---------------------------------------------------------------------------------------------------------

func test_tuning_values() -> void:
	var p: PlayTuning = play_tuning
	check(absf(p.invuln_seconds - 1.2) < 1.0e-6 and absf(p.respawn_invuln_seconds - 2.0) < 1.0e-6 and absf(p.downed_seconds - 1.5) < 1.0e-6, "invulnerability 1.2 s, return invulnerability 2.0 s, lying 1.5 s")
	check(absf(p.knockback_px - 12.0) < 1.0e-6 and p.health_step_hz == 60 and p.hp_max == HP_MAX, "knockback 12 px, 60 steps/s, HP 10")
	check(enemy_tuning.contact_damage == CONTACT and absf(enemy_tuning.hit_radius_px - 8.0) < 1.0e-6 and absf(enemy_tuning.hit_center_height_px - 6.0) < 1.0e-6, "contact damage 2 from a body circle of radius 8 centred 6 px above the feet")
	check(p.downed_seed_loss_fraction == 0.0 and p.downed_water_loss_fraction == 0.0, "the default keeps every seed and all water")
	check(p.enemy_fruit_cap == ENEMY_SLOT and p.plant_fruit_cap == PLANT_SLOT and p.source_fruit_cap == SOURCE_SLOT, "slots: enemy 12, plants 20, 3 per seed source")
	var sources: int = region_def.seed_source_tiles.size()
	check(p.pickup_total_cap >= sources * SOURCE_SLOT + PLANT_SLOT + ENEMY_SLOT, "the region total (%d) holds the sum of the slots (%d sources x 3 + 20 + 12)" % [p.pickup_total_cap, sources])

func test_contact_geometry() -> void:
	# Boar feet (100, 80): body circle centre (100, 74), radius 8. Player feet rectangle half size (3, 2).
	var cases: Array = [
		[Vector2(100, 80), true, "standing on the boar"],
		[Vector2(110.5, 74), true, "rectangle edge 7.5 px from the centre, side"],
		[Vector2(111.5, 74), false, "rectangle edge 8.5 px from the centre, side"],
		[Vector2(100, 83.9), true, "rectangle top 7.9 px below the centre"],
		[Vector2(100, 84.5), false, "rectangle top 8.5 px below the centre"],
		[Vector2(100, 64.5), true, "rectangle bottom 7.5 px above the centre"],
		[Vector2(100, 62.5), false, "rectangle bottom 9.5 px above the centre"],
		[Vector2(109.5, 79), true, "corner 7.16 px from the centre"],
		[Vector2(110.2, 80), false, "corner 8.24 px from the centre"],
		[Vector2(40, 40), false, "far away"],
	]
	for entry: Array in cases:
		var rig: Rig = make_rig({"knockback_px": 0.0})
		put_boar(rig, Vector2(100, 80))
		rig.pos = entry[0]
		run_for(rig, 0.1)
		var hurt: bool = rig.play.hp < HP_MAX
		check(hurt == bool(entry[1]) and rig.play.hp == (HP_MAX - CONTACT if bool(entry[1]) else HP_MAX), "contact geometry: %s -> %s (HP %d)" % [entry[2], "hit" if bool(entry[1]) else "no hit", rig.play.hp])
	# No boar, no damage; a boar of any zone counts.
	var empty: Rig = make_rig()
	empty.pos = Vector2(100, 80)
	run_for(empty, 3.0)
	check(empty.play.hp == HP_MAX and not empty.play.health.invulnerable(), "no boar: no damage, no invulnerability")
	var other_zone: Rig = make_rig({"knockback_px": 0.0})
	var stable_boar: Boar = put_boar(other_zone, Vector2(300, 80))
	stable_boar.zone = 1
	other_zone.pos = Vector2(300, 80)
	run_for(other_zone, 0.1)
	check(other_zone.play.hp == HP_MAX - CONTACT, "a boar standing in another zone hurts on touch as well")

func test_invulnerability_cycle() -> void:
	var rig: Rig = make_rig({"knockback_px": 0.0})
	put_boar(rig, Vector2(100, 80))
	put_boar(rig, Vector2(20, 26))
	var hp_by_step: Array = []
	var dim_seen: bool = false
	var bright_seen: bool = false
	var invulnerable_steps: int = 0
	for i: int in 520:
		tick(rig)
		hp_by_step.append(rig.play.hp)
		if rig.play.health.invulnerable():
			invulnerable_steps += 1
			if rig.steps < 20:
				dim_seen = dim_seen or rig.play.health.flicker_dim()
				bright_seen = bright_seen or not rig.play.health.flicker_dim()
	# Step n (1-based) is hp_by_step[n - 1].
	var damaged_at: Array = log_steps(rig, "damaged")
	check(damaged_at.slice(0, 5) == [1, 73, 145, 217, 289], "the player staying on the boar is hurt at once and then every 1.2 s: steps %s" % [damaged_at.slice(0, 5)])
	check(hp_by_step[0] == 8 and hp_by_step[71] == 8 and hp_by_step[72] == 6 and hp_by_step[143] == 6 and hp_by_step[144] == 4, "HP 10 -> 8 -> 6 -> 4: no second hit inside 1.2 s (step 72 still 8, step 73 is 6)")
	check(hp_by_step[216] == 2 and hp_by_step[287] == 2 and hp_by_step[288] == 0, "the fifth hit at step 289 takes HP to 0")
	check(log_steps(rig, "downed") == [289], "HP 0 downs the player at once (step 289)")
	check(rig.play.health.down_count == 1 and rig.play.health.hit_count == 6, "one fall counted; six hits (five that downed him, one after the return)")
	check(dim_seen and bright_seen, "while invulnerable the picture flickers (dim and bright halves are both seen)")
	check(log_steps(rig, "revived") == [289 + DOWNED_STEPS], "the player returns exactly 1.5 s (90 steps) after falling (step %s)" % [log_steps(rig, "revived")])
	var back: int = 289 + DOWNED_STEPS
	check(hp_by_step[back - 2] == 0 and hp_by_step[back - 1] == 10, "HP is 0 until the return and 10 from the return step on")
	check(rig.events.size() > 0 and log_steps(rig, "damaged").size() == 6, "after the return the player standing at the start beside a second boar is hurt once more (6 hits)")
	# The return invulnerability: the first hit after the return comes 2.0 s (120 steps) after it, not before.
	var after_return: Array = log_steps(rig, "damaged")
	check(after_return.size() == 6 and after_return[5] == back + RETURN_INVULN_STEPS, "the first hit after the return comes 120 steps (2.0 s) later (step %s)" % [after_return[5] if after_return.size() == 6 else -1])
	check(hp_by_step[back + RETURN_INVULN_STEPS - 2] == 10 and hp_by_step[back + RETURN_INVULN_STEPS - 1] == 8, "HP 10 right up to the end of the return invulnerability, then 8")
	check(rig.pos == rig.start, "the player stands at the start position")
	info["invulnerable_steps_in_520"] = invulnerable_steps

func test_knockback() -> void:
	var rig: Rig = make_rig()
	put_boar(rig, Vector2(100, 80))
	rig.pos = Vector2(104, 80)
	run_for(rig, 2.0)
	var away: Vector2 = Vector2(4, 6).normalized() * 12.0
	var expected: Vector2 = Vector2(104, 80) + away
	check(rig.play.hp == HP_MAX - CONTACT and rig.pos.distance_to(expected) < 0.01, "the hit pushes the player 12 px straight away from the body centre: %s (expected %s)" % [rig.pos, expected])
	check(rig.play.health.hit_count == 1, "the push moved the player out of contact: still one hit after 2 s (a second would have come at 1.2 s)")
	# Against the map: a lake east of the player.
	var wet: Rig = make_rig()
	var water: TerrainDef = terrain_def(&"water")
	for y: int in wet.world.height:
		for x: int in range(28, 32):
			wet.world.terrain[wet.world.index_of(x, y)] = water.id
	put_boar(wet, Vector2(100, 80))
	wet.pos = Vector2(104, 80)
	var stayed_clear: bool = true
	for i: int in 30:
		tick(wet)
		stayed_clear = stayed_clear and Walker.is_clear(wet.world, TILE, wet.pos, wet.half)
	check(stayed_clear, "the push never puts the feet into water")
	check(absf(wet.pos.x - 109.0) < 0.001 and absf(wet.pos.y - (80.0 + away.y)) < 0.01, "against the lake (tile edge 112 - 3 px) the push stops at x = 109 and slides along: %s" % wet.pos)
	# A hit that downs: no push after falling.
	var down: Rig = make_rig()
	put_boar(down, Vector2(100, 80))
	down.play.hp = 2
	down.pos = Vector2(104, 80)
	run_for(down, 0.5)
	check(down.play.health.downed and down.pos.distance_to(Vector2(104, 80)) < 0.001, "a hit that takes the last HP leaves the player lying where he was (no push)")

func test_downed_pickups_and_controls() -> void:
	var rig: Rig = make_rig()
	rig.pos = Vector2(200, 150)
	rig.play.hp = 3
	rig.play.damage_player(3)
	run_for(rig, 0.1)
	check(rig.play.health.downed and rig.play.hp == 0, "HP 0 reached by plain damage_player downs the player as well")
	rig.play.pickups.spawn(GroundPickups.KIND_HEAL_FRUIT, rig.pos, GroundPickups.HEAL_OWNER_BASE + 77)
	rig.play.pickups.spawn(GroundPickups.KIND_SEED_FRUIT, rig.pos, 1)
	var seeds_before: int = rig.play.seeds
	run_for(rig, 1.0)
	check(rig.play.health.downed and rig.play.hp == 0 and rig.play.seeds == seeds_before and rig.play.pickups.count() == 2, "lying there nothing is picked up and a healing fruit does not heal (the fruits stay)")
	run_for(rig, 0.6)
	check(not rig.play.health.downed and rig.play.hp == HP_MAX and rig.pos == rig.start, "the lying phase ends: full HP at the start")
	check(rig.play.pickups.count() == 2 and rig.play.seeds == seeds_before, "the fruits that lay there are still there")

## A frozen-world snapshot of what must survive being downed.
func snapshot(rig: Rig) -> Dictionary:
	var plants: Array = []
	for plant: CultivatedPlant in rig.play.cultivation.plants:
		plants.append([plant.uid, String(plant.key), plant.tile, plant.size])
	var nest_data: Array = []
	for nest: Nest in rig.field.nests:
		nest_data.append(nest.to_dict())
	return {
		"world": hash(JSON.stringify(rig.world.to_dict())),
		"greened": rig.world.greened_count, "targets": rig.world.target_count, "mature": rig.world.mature_count, "plants": rig.world.plant_count,
		"zone_greened": Array(rig.world.zone_greened_count), "zone_targets": Array(rig.world.zone_target_count), "zone_state": Array(rig.world.zone_state),
		"field": hash(JSON.stringify(rig.field.to_dict())), "nests": hash(JSON.stringify(nest_data)),
		"boars": rig.field.boars.size(), "carcasses": rig.field.carcasses.size(), "alive_nests": rig.field.alive_nest_count(),
		"cultivated": hash(JSON.stringify(plants)), "cultivated_count": plants.size(),
		"seeds": rig.play.seeds, "water": rig.play.water, "selected": rig.play.selected_index,
		"landing_counter": rig.play.landing_counter,
	}

func test_nothing_rolled_back() -> void:
	var rig: Rig = make_rig({"knockback_px": 0.0})
	rig.world.set_zones(rig.world.zone_of, PackedByteArray([WorldState.ZONE_UNCONQUERED, WorldState.ZONE_CLEARING]))
	# A varied world: seeds, sprouts, a mature block with a carrot and a kiwi, two nests, three boars, two carcasses.
	var count: int = 0
	for y: int in range(10, 40):
		for x: int in range(4, 48):
			var index: int = rig.world.index_of(x, y)
			var stage: int = [WorldState.STAGE_SEED, WorldState.STAGE_SPROUT1, WorldState.STAGE_SPROUT2][(x + y) % 3]
			if (x + y) % 5 != 0 and rig.world.set_stage(index, stage):
				count += 1
	for y: int in range(44, 52):
		for x: int in range(26, 40):
			rig.world.set_stage(rig.world.index_of(x, y), WorldState.STAGE_MATURE)
	check(rig.play.cultivation.try_place(&"carrot", Vector2(120, 188)) != null and rig.play.cultivation.try_place(&"kiwi", Vector2(140, 188)) != null, "setup: a carrot and a kiwi stand in the mature block")
	rig.field.add_nest(0, Vector2i(5, 5))
	var second_nest: Nest = rig.field.add_nest(0, Vector2i(30, 5))
	rig.field.damage_nest(second_nest, second_nest.hp_max)
	put_boar(rig, Vector2(60, 100))
	put_boar(rig, Vector2(80, 110))
	rig.field.damage_boar(put_boar(rig, Vector2(70, 120)), 3)
	rig.field.damage_boar(put_boar(rig, Vector2(90, 125)), 3)
	var fight: Boar = put_boar(rig, Vector2(300, 60))
	fight.zone = 1
	rig.play.seeds = 17
	rig.play.water = 63.5
	rig.play.select_index(2)
	rig.pos = Vector2(300, 60)
	check(count > 300 and rig.field.carcasses.size() == 2 and rig.field.alive_nest_count() == 1 and rig.world.greened_count > 0, "setup: %d planted tiles, 2 carcasses, 1 live nest, %d greened" % [count, rig.world.greened_count])
	# The player stays on the stable-zone boar until the last HP is about to go, then the snapshot is taken.
	var guard: int = 0
	while rig.play.hp > CONTACT and guard < 2000:
		tick(rig)
		guard += 1
	check(rig.play.hp == CONTACT and not rig.play.health.downed, "walking into the boar until 2 HP are left")
	var before: Dictionary = snapshot(rig)
	var ages_before: Dictionary = {}
	var mature_before: Dictionary = {}
	for plant: CultivatedPlant in rig.play.cultivation.plants:
		ages_before[plant.uid] = plant.age
		mature_before[plant.uid] = plant.mature
	guard = 0
	while log_steps(rig, "revived").is_empty() and guard < 2000:
		tick(rig)
		guard += 1
	check(rig.play.health.down_count == 1 and rig.pos == rig.start and rig.play.hp == HP_MAX, "the last hit downed the player, who came back at the start with full HP")
	var after: Dictionary = snapshot(rig)
	var keys_equal: bool = true
	for key: String in before:
		if before[key] != after[key]:
			keys_equal = false
			print("INFO differs: %s before=%s after=%s" % [key, before[key], after[key]])
	check(keys_equal, "world state hash, greening and zone counters, zone states, nests, boars, carcasses, cultivated plants, seeds, water and selection are exactly as just before the fall")
	var ages_ok: bool = true
	for plant: CultivatedPlant in rig.play.cultivation.plants:
		ages_ok = ages_ok and plant.age >= float(ages_before[plant.uid]) and (plant.mature or not bool(mature_before[plant.uid]))
	check(ages_ok, "cultivated plants kept their age (they only grew on)")

func test_world_goes_on() -> void:
	var rig: Rig = make_rig({}, {"spawn_interval_seconds": 12.0})
	rig.run_field = true
	var nest: Nest = rig.field.add_nest(0, Vector2i(10, 10))
	rig.field.damage_boar(put_boar(rig, Vector2(100, 80)), 3)
	var wanderer: Boar = put_boar(rig, Vector2(60, 100), false)
	wanderer.home = nest.center_px(TILE)
	wanderer.nest_id = nest.id
	for y: int in range(12, 20):
		for x: int in range(16, 40):
			rig.world.set_stage(rig.world.index_of(x, y), WorldState.STAGE_SPROUT2)
	rig.pos = Vector2(300, 150)
	run_for(rig, 5.0)
	rig.play.damage_player(HP_MAX)
	run_for(rig, 1.0 / 60.0)
	check(rig.play.health.downed, "setup: the player is lying")
	var carcass: Carcass = rig.field.carcasses[0]
	var age_down: int = carcass.age_steps
	var steps_down: int = rig.field.steps_done
	var spawn_down: int = nest.spawn_steps
	var elapsed_down: float = rig.play.elapsed
	var wander_from: Vector2 = wanderer.pos
	var gnawed_from: int = rig.field.total_gnawed
	var guard: int = 0
	while rig.play.health.downed and guard < 400:
		tick(rig)
		guard += 1
	check(not rig.play.health.downed, "the player returned")
	check(carcass.age_steps - age_down >= DOWNED_STEPS - 2 and carcass.age_steps - age_down <= DOWNED_STEPS + 1, "the carcass kept aging while the player lay there (+%d steps of 90)" % (carcass.age_steps - age_down))
	check(rig.field.steps_done - steps_down >= DOWNED_STEPS - 2 and rig.field.steps_done - steps_down <= DOWNED_STEPS + 1, "the enemy simulation kept running (+%d steps)" % (rig.field.steps_done - steps_down))
	check(nest.spawn_steps > spawn_down or rig.field.boars.size() > 1, "the nest's spawn timer kept running")
	check(wanderer.pos != wander_from and rig.play.elapsed - elapsed_down > 1.4, "a boar kept walking and game time went on (%.2f s)" % (rig.play.elapsed - elapsed_down))
	info["gnawed_while_downed"] = rig.field.total_gnawed - gnawed_from

func test_loss_fractions() -> void:
	var rig: Rig = make_rig({"downed_seed_loss_fraction": 0.5, "downed_water_loss_fraction": 0.25})
	rig.play.seeds = 21
	rig.play.water = 80.0
	rig.pos = Vector2(200, 150)
	rig.play.damage_player(HP_MAX)
	run_for(rig, 1.7)
	check(rig.play.seeds == 11 and absf(rig.play.water - 60.0) < 1.0e-6 and rig.play.hp == HP_MAX, "with a tuned loss of half the seeds (rounded down) and a quarter of the water: 21 -> 11 seeds, 80 -> 60 water")
	var keep: Rig = make_rig()
	keep.play.seeds = 21
	keep.play.water = 80.0
	keep.pos = Vector2(200, 150)
	keep.play.damage_player(HP_MAX)
	run_for(keep, 1.7)
	check(keep.play.seeds == 21 and keep.play.water == 80.0, "by default seeds and water are kept")

func test_kiwi_heal() -> void:
	var rig: Rig = make_rig()
	for y: int in range(20, 26):
		for x: int in range(60, 66):
			rig.world.set_stage(rig.world.index_of(x, y), WorldState.STAGE_MATURE)
	var kiwi: CultivatedPlant = rig.play.cultivation.try_place(&"kiwi", Vector2(250, 90))
	check(kiwi != null, "setup: a kiwi stands in the mature block")
	rig.play.damage_player(7)
	check(rig.play.hp == 3, "HP 3 after taking 7")
	rig.pos = Vector2(300, 200)
	rig.play.pickups.spawn(GroundPickups.KIND_HEAL_FRUIT, rig.pos, GroundPickups.HEAL_OWNER_BASE + kiwi.uid)
	run_for(rig, 0.1)
	var heal: int = 2
	check(rig.play.hp == 3 + heal and rig.play.pickups.count_kind(GroundPickups.KIND_HEAL_FRUIT) == 0, "a kiwi's healing fruit gives back %d HP (data: fruit_heal 2) and is eaten (HP %d)" % [heal, rig.play.hp])
	var emitted: Array[int] = []
	rig.play.hp_changed.connect(func(value: int) -> void: emitted.append(value))
	rig.play.pickups.spawn(GroundPickups.KIND_HEAL_FRUIT, rig.pos, GroundPickups.HEAL_OWNER_BASE + kiwi.uid)
	run_for(rig, 0.1)
	rig.play.damage_player(2)
	check(emitted == [7, 5], "hp_changed follows the healing and the damage: %s" % [emitted])
	# Full HP: the fruit stays for later.
	rig.play.heal_player(HP_MAX)
	rig.play.pickups.spawn(GroundPickups.KIND_HEAL_FRUIT, rig.pos, GroundPickups.HEAL_OWNER_BASE + kiwi.uid)
	run_for(rig, 0.1)
	check(rig.play.pickups.count_kind(GroundPickups.KIND_HEAL_FRUIT) == 1, "at full HP the healing fruit stays on the ground")
	# Healing while invulnerable after a hit works as well (hit, then eat).
	var rig2: Rig = make_rig({"knockback_px": 0.0})
	put_boar(rig2, Vector2(100, 80))
	rig2.pos = Vector2(100, 80)
	run_for(rig2, 0.1)
	check(rig2.play.hp == 8, "setup: hurt by contact (HP 8)")
	rig2.play.pickups.spawn(GroundPickups.KIND_HEAL_FRUIT, rig2.pos, GroundPickups.HEAL_OWNER_BASE + 999)
	run_for(rig2, 0.1)
	check(rig2.play.hp == 10 and rig2.play.pickups.count_kind(GroundPickups.KIND_HEAL_FRUIT) == 0, "a healing fruit of a plant that no longer exists still heals the fallback amount (2)")

func test_enemy_slot() -> void:
	var sources: Array[Vector2] = [Vector2(300, 200)]
	var total: int = play_tuning.pickup_total_cap
	# 1) Plant fruits at their limit do not touch a boar's reward.
	var rig: Rig = make_rig({}, {}, sources)
	var plant_ok: int = 0
	for i: int in 40:
		if rig.play.pickups.spawn(GroundPickups.KIND_SEED_FRUIT, Vector2(200 + i, 200), GroundPickups.PLANT_OWNER_BASE + i):
			plant_ok += 1
	check(plant_ok == PLANT_SLOT, "plants fill only their own 20 slots (%d)" % plant_ok)
	rig.field.damage_boar(put_boar(rig, Vector2(100, 80)), 3)
	check(rig.play.pickups.count_enemy_owned() == BOAR_FRUITS and rig.combat.fruits_dropped == BOAR_FRUITS and rig.combat.fruits_direct == 0, "plant fruits at the limit: the boar still drops both of its fruits on the ground")
	# 2) The enemy slot is 12: no more, whatever is free elsewhere; plants and sources keep theirs.
	var enemy_ok: int = 0
	for i: int in 30:
		if rig.play.pickups.spawn(GroundPickups.KIND_SEED_FRUIT, Vector2(100 + i, 100), GroundPickups.ENEMY_OWNER_BASE + 500 + i):
			enemy_ok += 1
	check(enemy_ok == ENEMY_SLOT - BOAR_FRUITS and rig.play.pickups.count_enemy_owned() == ENEMY_SLOT, "enemy drops stop at their own 12 slots")
	var source_ok: int = 0
	for i: int in 6:
		if rig.play.pickups.spawn(GroundPickups.KIND_SEED_FRUIT, Vector2(300, 200), 1):
			source_ok += 1
	check(source_ok == SOURCE_SLOT and rig.play.pickups.count_seed_items() == total, "the seed source can still drop with plants and enemies at their limits (%d accepted, total %d of %d)" % [source_ok, rig.play.pickups.count_seed_items(), total])
	check(rig.play.pickups.count_owned(1) >= SOURCE_SLOT, "the source's 3 reserved slots were available (%d on the ground)" % rig.play.pickups.count_owned(1))
	check(rig.play.pickups.count_seed_items() <= total, "the seed total never exceeds %d (%d)" % [total, rig.play.pickups.count_seed_items()])
	# 3) Healing fruits take no enemy slot, and enemy drops take no healing slot.
	var heal_rig: Rig = make_rig({}, {}, sources)
	for i: int in 16:
		heal_rig.play.pickups.spawn(GroundPickups.KIND_HEAL_FRUIT, Vector2(50 + i, 50), GroundPickups.HEAL_OWNER_BASE + i)
	heal_rig.field.damage_boar(put_boar(heal_rig, Vector2(100, 80)), 3)
	check(heal_rig.play.pickups.count_enemy_owned() == BOAR_FRUITS and heal_rig.play.pickups.count_kind(GroundPickups.KIND_HEAL_FRUIT) == 16, "16 healing fruits do not take the boar's slots")
	# 4) Enemy fruits are not counted as plant fruits.
	check(heal_rig.play.pickups.count_plant_owned() == 0, "enemy drops are not plant fruits")
	# 5) With the enemy slot full, plants are not hurt by enemy drops either.
	var full: Rig = make_rig({}, {}, sources)
	for i: int in ENEMY_SLOT:
		full.play.pickups.spawn(GroundPickups.KIND_SEED_FRUIT, Vector2(100 + i, 100), GroundPickups.ENEMY_OWNER_BASE + 900 + i)
	var plants_after: int = 0
	for i: int in 40:
		if full.play.pickups.spawn(GroundPickups.KIND_SEED_FRUIT, Vector2(200 + i, 200), GroundPickups.PLANT_OWNER_BASE + i):
			plants_after += 1
	check(plants_after == PLANT_SLOT, "a full enemy slot does not shrink the plant slots (%d)" % plants_after)
	# 6) Enemy fruit lifetime: its own life value, not the plants' 45 s.
	var life: Rig = make_rig()
	life.field.damage_boar(put_boar(life, Vector2(100, 80)), 3)
	life.play.advance(0.25, Vector2(380, 230))
	for i: int in 4 * 59:
		life.play.advance(0.25, Vector2(380, 230))
	check(life.play.pickups.count_enemy_owned() == BOAR_FRUITS, "an enemy fruit is still there after about 59 s (own lifetime 60 s, not the plants' 45 s)")
	for i: int in 8:
		life.play.advance(0.25, Vector2(380, 230))
	check(life.play.pickups.count_enemy_owned() == 0, "and gone after 60 s")

func test_drop_direct_credit() -> void:
	# Prefilled enemy slots: [taken, boar -> ground, boar -> direct seeds, nest -> ground, nest -> direct].
	var cases: Array = [[0, 2, 0, 4, 0], [10, 2, 0, 2, 2], [11, 1, 1, 1, 3], [12, 0, 2, 0, 4]]
	for entry: Array in cases:
		var boar_rig: Rig = make_rig()
		for i: int in int(entry[0]):
			boar_rig.play.pickups.spawn(GroundPickups.KIND_SEED_FRUIT, Vector2(100 + i, 100), GroundPickups.ENEMY_OWNER_BASE + 900 + i)
		var seeds_before: int = boar_rig.play.seeds
		boar_rig.field.damage_boar(put_boar(boar_rig, Vector2(100, 80)), 3)
		var on_ground: int = boar_rig.play.pickups.count_enemy_owned() - int(entry[0])
		check(on_ground == int(entry[1]) and boar_rig.play.seeds - seeds_before == int(entry[2]), "enemy slot holds %d: a boar's reward is %d on the ground + %d seeds directly (ground %d, seeds +%d)" % [int(entry[0]), int(entry[1]), int(entry[2]), on_ground, boar_rig.play.seeds - seeds_before])
		check(on_ground + (boar_rig.play.seeds - seeds_before) == BOAR_FRUITS, "slot %d: defeating a boar always yields both fruits' worth of seeds" % int(entry[0]))
		var nest_rig: Rig = make_rig()
		for i: int in int(entry[0]):
			nest_rig.play.pickups.spawn(GroundPickups.KIND_SEED_FRUIT, Vector2(100 + i, 100), GroundPickups.ENEMY_OWNER_BASE + 900 + i)
		var nest: Nest = nest_rig.field.add_nest(0, Vector2i(10, 10))
		var nest_seeds: int = nest_rig.play.seeds
		nest_rig.field.damage_nest(nest, nest.hp_max)
		var nest_ground: int = nest_rig.play.pickups.count_enemy_owned() - int(entry[0])
		check(nest_ground == int(entry[3]) and nest_rig.play.seeds - nest_seeds == int(entry[4]), "enemy slot holds %d: a nest's reward is %d on the ground + %d seeds directly (ground %d, seeds +%d)" % [int(entry[0]), int(entry[3]), int(entry[4]), nest_ground, nest_rig.play.seeds - nest_seeds])
	# Direct credit above the pouch cap is lost.
	var capped: Rig = make_rig()
	for i: int in ENEMY_SLOT:
		capped.play.pickups.spawn(GroundPickups.KIND_SEED_FRUIT, Vector2(100 + i, 100), GroundPickups.ENEMY_OWNER_BASE + 900 + i)
	capped.play.seeds = capped.play.tuning.seed_max - 1
	capped.field.damage_boar(put_boar(capped, Vector2(100, 80)), 3)
	check(capped.play.seeds == capped.play.tuning.seed_max and capped.play.enemy_lost_seeds == 1 and capped.combat.fruits_refused == 1, "with the slot full and 1 pouch place left only one of two seeds is credited, the other is lost")
	var round_trip: Dictionary = capped.play.to_dict()
	check(int((round_trip["enemy_drops"] as Dictionary)["lost"]) == 1, "the credit counters are saved")

func test_driver_wiring() -> void:
	# The real PlayDriver + FlowerPlayer (not in a tree): the push uses the player's walking rules, the return teleports.
	var rig: Rig = make_rig()
	var water: TerrainDef = terrain_def(&"water")
	for y: int in rig.world.height:
		for x: int in range(28, 32):
			rig.world.terrain[rig.world.index_of(x, y)] = water.id
	put_boar(rig, Vector2(100, 80))
	var flower: FlowerPlayer = FlowerPlayer.new()
	flower.world_bounds = Rect2(Vector2(8, 8), Vector2(380, 220))
	flower.walk_world = rig.world
	flower.walk_tile_px = TILE
	flower.walk_half = Vector2(3, 2)
	flower.simulation_position = Vector2(20, 20)
	var driver: PlayDriver = PlayDriver.new()
	driver.setup(rig.play, flower)
	check(flower.health == rig.play.health and rig.play.health.respawn_position == Vector2(20, 20), "driver: the player gets the health state and the respawn place is its position at setup")
	flower.simulation_position = Vector2(104, 80)
	for i: int in 30:
		rig.play.advance(1.0 / 60.0, flower.simulation_position)
	check(absf(flower.simulation_position.x - 109.0) < 0.001 and Walker.is_clear(rig.world, TILE, flower.simulation_position, Vector2(3, 2)), "driver: the push goes through the player's walking rules (stopped at the lake: %s)" % flower.simulation_position)
	rig.play.damage_player(HP_MAX)
	for i: int in 30:
		rig.play.advance(1.0 / 60.0, flower.simulation_position)
	check(rig.play.health.downed and flower.is_downed(), "driver: HP 0 locks the player")
	flower.update_look()
	check(flower.visual == null, "driver: a player without a scene tree has no picture to update (no crash)")
	for i: int in 80:
		rig.play.advance(1.0 / 60.0, flower.simulation_position)
	check(not flower.is_downed() and flower.simulation_position == Vector2(20, 20) and rig.play.hp == HP_MAX, "driver: the return puts the player back at the start with full HP")
	flower.free()
	driver.free()

func test_hud_text() -> void:
	var rig: Rig = make_rig()
	var hud: PlayHud = PlayHud.new()
	hud.refresh(rig.play, rig.world)
	check(hud.hp_label.text == "HP 10/10" and hud.hp_gauge.fraction == 1.0, "HUD shows HP 10/10 at the start")
	rig.play.damage_player(CONTACT)
	hud.refresh(rig.play, rig.world)
	check(hud.hp_label.text == "HP 8/10" and absf(hud.hp_gauge.fraction - 0.8) < 1.0e-6, "HUD follows damage: HP 8/10")
	rig.play.heal_player(1)
	hud.refresh(rig.play, rig.world)
	check(hud.hp_label.text == "HP 9/10", "HUD follows healing: HP 9/10")
	rig.play.damage_player(HP_MAX)
	hud.refresh(rig.play, rig.world)
	check(hud.hp_label.text == "HP 0/10" and hud.hp_gauge.fraction == 0.0 and hud.hp_gauge.low, "HUD shows HP 0/10 with a low (amber) empty gauge")
	hud.free()

func test_frame_rates() -> void:
	var results: Dictionary = {}
	var positions: Dictionary = {}
	for hz: int in [30, 60, 144]:
		var rig: Rig = make_rig({"knockback_px": 0.0})
		put_boar(rig, Vector2(100, 80))
		put_boar(rig, Vector2(20, 26))
		var observed: Array = []
		var targets: Array = [0.1, 0.5, 1.25, 2.45, 3.65, 4.85, 5.5, 6.4, 8.0, 8.5]
		var index: int = 0
		while index < targets.size():
			tick(rig, hz)
			if rig.t >= float(targets[index]) - 1.0e-9:
				observed.append([rig.play.hp, rig.play.health.downed, rig.play.health.down_count, rig.play.health.invulnerable()])
				index += 1
		results[hz] = observed
		positions[hz] = rig.pos
	var expected: Array = [
		[8, false, 0, true], [8, false, 0, true], [6, false, 0, true], [4, false, 0, true], [2, false, 0, true],
		[0, true, 1, false], [0, true, 1, false], [10, false, 1, true], [10, false, 1, true], [8, false, 1, true],
	]
	check(results[30] == expected and results[60] == expected and results[144] == expected, "damage, falling, return and invulnerability follow the same timeline at 30, 60 and 144 Hz: %s" % [results[60]])
	# Knockback displacement is the same at every rate.
	var landings: Array = []
	for hz: int in [30, 60, 144]:
		var rig: Rig = make_rig()
		put_boar(rig, Vector2(100, 80))
		rig.pos = Vector2(104, 80)
		run_for(rig, 0.5, hz)
		landings.append(rig.pos)
	check(Vector2(landings[0]).distance_to(landings[1]) < 0.001 and Vector2(landings[2]).distance_to(landings[1]) < 0.001, "the push ends at the same place at 30, 60 and 144 Hz: %s" % [landings])

func health_key(h: PlayerHealth) -> Array:
	return [h.downed, h.invuln_steps, h.downed_steps, h.knock_steps, h.down_count, h.hit_count, h.steps_done]

func test_save_round_trip() -> void:
	var rig: Rig = make_rig()
	put_boar(rig, Vector2(100, 80))
	rig.pos = Vector2(104, 80)
	run_for(rig, 0.04)
	check(rig.play.health.invulnerable() and rig.play.health.knock_steps > 0, "setup: a hit with the push still going on")
	var saved: Dictionary = rig.play.to_dict()
	var text: String = JSON.stringify(saved)
	var parsed: Variant = JSON.parse_string(text)
	check(parsed is Dictionary, "the play state is JSON text")
	var copy: Rig = make_rig()
	copy.pos = rig.pos
	check(copy.play.load_dict(parsed as Dictionary), "loading the saved play state succeeds")
	check(JSON.stringify(copy.play.to_dict()) == text, "invulnerability, push and counters survive the round trip exactly")
	put_boar(copy, Vector2(100, 80))
	copy.t = rig.t
	copy.steps = rig.steps
	var same: bool = true
	for i: int in 60 * 8:
		tick(rig)
		tick(copy)
		same = same and health_key(rig.play.health) == health_key(copy.play.health) and rig.pos.distance_to(copy.pos) < 1.0e-6 and rig.play.hp == copy.play.hp
	check(same, "after loading, the next 8 s (push, invulnerability, a second hit) run exactly like the original")
	# Saved while lying: restored as already returned.
	var down: Rig = make_rig()
	down.pos = Vector2(200, 150)
	down.play.seeds = 13
	down.play.damage_player(HP_MAX)
	run_for(down, 0.5)
	check(down.play.health.downed and down.play.health.downed_steps > 0, "setup: lying, part of the 1.5 s gone")
	var down_saved: Dictionary = JSON.parse_string(JSON.stringify(down.play.to_dict())) as Dictionary
	var restored: Rig = make_rig()
	restored.pos = Vector2(200, 150)
	check(restored.play.load_dict(down_saved), "a save taken while lying loads")
	var health: PlayerHealth = restored.play.health
	check(not health.downed and restored.play.hp == HP_MAX and health.invuln_steps == RETURN_INVULN_STEPS and health.down_count == 1, "it is restored as already returned: full HP, 2 s of invulnerability, the fall still counted")
	check(restored.pos == restored.start and log_steps(restored, "revived").size() == 1, "the owner of the player is told to put him at the start")
	check(restored.play.seeds == 13, "the seeds are as saved")
	# An older save without the health block loads.
	var older: Dictionary = (JSON.parse_string(text) as Dictionary).duplicate(true)
	older.erase("health")
	older.erase("enemy_drops")
	var plain: Rig = make_rig()
	check(plain.play.load_dict(older) and not plain.play.health.downed and plain.play.health.down_count == 0, "a save without the damage block (older) still loads")
	# A saved HP 0 without the lying flag leads to falling at once.
	var zero: Dictionary = (JSON.parse_string(text) as Dictionary).duplicate(true)
	zero["hp"] = 0
	zero["health"] = {"version": 1}
	var zero_rig: Rig = make_rig()
	zero_rig.pos = Vector2(200, 150)
	check(zero_rig.play.load_dict(zero), "HP 0 data loads")
	run_for(zero_rig, 0.1)
	check(zero_rig.play.health.downed, "HP 0 after loading leads to falling on the next step")

func test_performance() -> void:
	var rig: Rig = make_rig()
	for i: int in 40:
		put_boar(rig, Vector2(20.0 + float(i % 10) * 30.0, 20.0 + float(i / 10) * 40.0))
	rig.pos = Vector2(390, 230)
	var started: int = Time.get_ticks_usec()
	for i: int in 3000:
		rig.play.health.advance(1.0 / 60.0, rig.play, rig.pos, rig.field)
	var per_step: float = float(Time.get_ticks_usec() - started) / 3000.0
	info["health_us_per_step_40_boars"] = per_step
	check(per_step < 50.0, "the contact check against 40 boars costs %.2f us per step" % per_step)

# ---- scene (injected input only) -------------------------------------------------------------------------------------

func wait_frames(count: int) -> void:
	for i: int in count:
		await physics_frame
	await process_frame

func send_key(code: Key, pressed: bool) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)

func press(code: Key, pressed: bool) -> void:
	send_key(code, pressed)
	await process_frame

func zone_snapshot(world: WorldState) -> Dictionary:
	return {"greened": world.greened_count, "zone_greened": Array(world.zone_greened_count), "zone_state": Array(world.zone_state), "terrain": hash(world.terrain)}

func test_scene() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await wait_frames(3)
	player = main.player
	var play: PlayState = main.play
	var world: WorldState = main.grid
	var enemies: EnemyField = main.enemies
	check(play.enemies == enemies and player.health == play.health and play.health.respawn_position == player.simulation_position, "scene: the damage state is wired to the enemies and the player, and the start is the respawn place")
	var start: Vector2 = player.simulation_position
	# One boar from the first nest, standing still; the nests are destroyed so nothing else comes.
	var nest: Nest = enemies.nests[0]
	check(enemies._spawn(nest) and enemies.boars.size() == 1, "scene: a boar came out of nest 1")
	var boar: Boar = enemies.boars[0]
	boar.wait = 1 << 30
	for other: Nest in enemies.nests:
		enemies.destroy_nest(other)
	# A carrot stands in the start zone (a cultivated plant that must survive).
	var carrot: CultivatedPlant = null
	for dy: int in range(-12, 13):
		for dx: int in range(-12, 13):
			if carrot == null:
				carrot = play.cultivation.try_place(&"carrot", start + Vector2(dx * 4, dy * 4))
	check(carrot != null, "scene: a carrot was planted near the start")
	# Choose the side of the boar the player walks in from (open ground for 30 px, one of four directions).
	var dirs: Array = [[Vector2(-1, 0), KEY_D], [Vector2(1, 0), KEY_A], [Vector2(0, -1), KEY_S], [Vector2(0, 1), KEY_W]]
	var pick: Array = []
	for entry: Array in dirs:
		var clear: bool = true
		for k: int in range(1, 11):
			clear = clear and Walker.is_clear(world, TILE, boar.pos + Vector2(entry[0]) * float(k) * 3.0, Vector2(3, 2))
		if clear and pick.is_empty():
			pick = entry
	check(not pick.is_empty(), "scene: open ground to approach the boar")
	var key: Key = pick[1]
	player.simulation_position = boar.pos + Vector2(pick[0]) * 30.0
	await wait_frames(3)
	var seeds_before: int = play.seeds
	var water_before: float = play.water
	check(play.hp == HP_MAX and not play.health.downed, "scene: HP full before the walk")
	await press(key, true)
	var guard: int = 0
	while play.hp == HP_MAX and guard < 240:
		await physics_frame
		guard += 1
	check(play.hp == HP_MAX - CONTACT and play.health.invulnerable(), "scene: walking into the boar costs %d HP and starts the invulnerability (HP %d)" % [CONTACT, play.hp])
	await process_frame
	check(main.hud.hp_label.text == "HP 8/10", "scene: the HUD shows HP 8/10 (%s)" % main.hud.hp_label.text)
	var alpha_min: float = 1.0
	var alpha_max: float = 0.0
	for i: int in 24:
		await physics_frame
		alpha_min = minf(alpha_min, player.visual.modulate.a)
		alpha_max = maxf(alpha_max, player.visual.modulate.a)
	check(alpha_min < 0.5 and alpha_max == 1.0, "scene: the player flickers while invulnerable (alpha %.2f .. %.2f)" % [alpha_min, alpha_max])
	# Pause inside the invulnerability: the timer stands still.
	await press(key, false)
	send_key(KEY_ESCAPE, true)
	await process_frame
	send_key(KEY_ESCAPE, false)
	await process_frame
	check(main.get_tree().paused, "scene: Esc pauses")
	var inv_before: int = play.health.invuln_steps
	var steps_before: int = play.health.steps_done
	var pos_before: Vector2 = player.simulation_position
	await wait_frames(60)
	check(play.health.invuln_steps == inv_before and play.health.steps_done == steps_before and player.simulation_position == pos_before and play.hp == HP_MAX - CONTACT, "scene: while paused the invulnerability, the damage clock, the position and HP stand still")
	send_key(KEY_ESCAPE, true)
	await process_frame
	send_key(KEY_ESCAPE, false)
	await wait_frames(2)
	check(not main.get_tree().paused and play.health.steps_done > steps_before and play.health.steps_done - steps_before < 12, "scene: resuming adds only the frames that were stepped (%d steps)" % (play.health.steps_done - steps_before))
	# Keep standing on the boar (after each push the player steps back onto it once the invulnerability is over; the first hit
	# above was a real walk, and walking past a boar rarely stays inside its body for 1.2 s).
	guard = 0
	while play.hp > CONTACT and guard < 900:
		await physics_frame
		guard += 1
		if not play.health.invulnerable() and play.health.touching_boar(enemies, player.simulation_position) == null:
			player.simulation_position = boar.pos
	check(play.hp == CONTACT and not play.health.downed, "scene: three more hits later 2 HP are left (HP %d)" % play.hp)
	var before: Dictionary = zone_snapshot(world)
	var plant_count: int = play.cultivation.plants.size()
	var carcasses_before: int = enemies.carcasses.size()
	var nests_alive: int = enemies.alive_nest_count()
	var boars_before: int = enemies.boars.size()
	guard = 0
	while not play.health.downed and guard < 400:
		await physics_frame
		guard += 1
		if not play.health.invulnerable() and play.health.touching_boar(enemies, player.simulation_position) == null:
			player.simulation_position = boar.pos
	check(play.health.downed and play.hp == 0 and play.health.down_count == 1, "scene: the fifth hit downs the player (HP 0)")
	await press(key, true)
	await process_frame
	check(main.down_panel.visible and main.hud.hp_label.text == "HP 0/10", "scene: the message panel shows and the HUD says HP 0/10")
	check(not main.fire(false) and not main.fire(true), "scene: shooting is locked while downed")
	var lying_at: Vector2 = player.simulation_position
	await wait_frames(20)
	check(player.simulation_position == lying_at, "scene: with the D/A/W/S key held, a downed player does not move")
	check(player.visual.texture == PlayArt.flower_down(), "scene: the downed picture is the lying flower")
	# Pause while lying: the lying timer stands still.
	var lying_steps: int = play.health.downed_steps
	send_key(KEY_ESCAPE, true)
	await process_frame
	send_key(KEY_ESCAPE, false)
	await process_frame
	await wait_frames(40)
	check(play.health.downed and play.health.downed_steps == lying_steps, "scene: pausing while lying stops the lying timer (%d steps left)" % lying_steps)
	send_key(KEY_ESCAPE, true)
	await process_frame
	send_key(KEY_ESCAPE, false)
	await process_frame
	await press(key, false)
	guard = 0
	while play.health.downed and guard < 400:
		await physics_frame
		guard += 1
	await wait_frames(2)
	check(not play.health.downed and play.hp == HP_MAX, "scene: after the lying time HP is full again")
	check(player.simulation_position.distance_to(start) < 0.001, "scene: the player is back at the start (%s)" % player.simulation_position)
	check(not main.down_panel.visible and main.hud.hp_label.text == "HP 10/10", "scene: the message is gone and the HUD says HP 10/10")
	check(play.health.invulnerable() and play.health.invuln_steps > 0, "scene: the return starts the invulnerability")
	var after: Dictionary = zone_snapshot(world)
	check(play.seeds == seeds_before and absf(play.water - water_before) < 1.0e-6, "scene: seeds (%d, before %d) and water (%.1f, before %.1f) are as before" % [play.seeds, seeds_before, play.water, water_before])
	check(play.cultivation.plants.size() == plant_count and carrot != null and play.cultivation.plant_by_uid(carrot.uid) == carrot, "scene: the carrot and all cultivated plants are still there")
	check(enemies.carcasses.size() >= carcasses_before and enemies.alive_nest_count() == nests_alive and enemies.boars.size() == boars_before and enemies.boars[0] == boar, "scene: carcasses, nests and boars are not reset (the boar is the same one)")
	var home_zone: int = world.zone_of[world.index_of(floori(start.x / TILE), floori(start.y / TILE))]
	var home_before: int = (before["zone_greened"] as Array)[home_zone]
	var home_after: int = (after["zone_greened"] as Array)[home_zone]
	check(after["zone_state"] == before["zone_state"] and after["terrain"] == before["terrain"], "scene: zone states and terrain are unchanged")
	check(home_after >= home_before and home_before > 0, "scene: the home zone's greened tiles did not go back (%d -> %d; the world's natural spread went on)" % [home_before, home_after])
	check(player.visual.texture != PlayArt.flower_down() and player.visual.position == Vector2(-8, -14), "scene: the standing picture is back")
	info["scene_hits"] = play.health.hit_count
	info["scene_greened_before_after"] = [before["greened"], after["greened"]]
	main.queue_free()
	await process_frame
