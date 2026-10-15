extends SceneTree
## P2-04 headless checks: zone state transitions (cleared nests -> clearing, no boar left -> stable, all targets greened ->
## complete; forward only), no re-invasion (a long run on a test map and on region_01, every frame), the boars of a zone that is set
## stable from outside vanish, the zone display texts and notices, the clear state, pause, 30 / 60 / 144 Hz, save round trips and the
## refusal of contradicting data, and the real scene (injected mouse input only): shoot a nest, kill the last boar, zone turns stable.
## Run: Godot --headless --path <project> --script res://tests/p2/p2_04_checks.gd [-- --skip-long]
## Expected values come from the ticket and the design written here (a state follows from the counts of nests / boars / greened
## tiles; percentages are floors of integers; the texts are spelled out below); they are not read back from the implementation.

const REGION_PATH: String = "res://data/region_01.tres"
const TILE: int = 4
const U: int = WorldState.ZONE_UNCONQUERED
const C: int = WorldState.ZONE_CLEARING
const S: int = WorldState.ZONE_STABLE
const K: int = WorldState.ZONE_COMPLETE

var failures: int = 0
var checks: int = 0
var skip_long: bool = false
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
	skip_long = OS.get_cmdline_user_args().has("--skip-long")
	region_def = load(REGION_PATH) as RegionDef
	sim_tuning = load("res://data/sim_tuning.tres") as SimTuning
	play_tuning = load("res://data/play_tuning.tres") as PlayTuning
	enemy_tuning = load("res://data/enemy_tuning.tres") as EnemyTuning
	check(region_def != null and enemy_tuning != null and play_tuning != null, "region and tunings load")
	test_region_start()
	test_transitions_nests_and_boars()
	test_greening_complete()
	test_one_tile_short_on_stable()
	test_no_regress()
	test_external_stable_purges()
	test_contact_after_stable()
	test_texts_and_notices()
	test_clear_state()
	test_save_round_trip()
	test_load_refusals()
	test_frame_rates()
	test_cost()
	if not skip_long:
		test_no_reinvasion_test_map()
		test_no_reinvasion_region()
	await test_scene()
	print("INFO " + JSON.stringify(info))
	print("P2_04_RESULT checks=%d failures=%d" % [checks, failures])
	var file: FileAccess = FileAccess.open(ProjectSettings.globalize_path("res://evidence/p2/p2-04/checks_info.json"), FileAccess.WRITE)
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

func open_rows(width: int, height: int) -> Array:
	var rows: Array = []
	for y: int in height:
		rows.append(".".repeat(width))
	return rows

## World from glyph rows ('.' wasteland, '~' water, '#' building); zone id of a tile = number of `splits` its x has reached.
func build_world(rows: Array, splits: Array, states: Array) -> WorldState:
	var def: RegionDef = RegionDef.new()
	def.width_tiles = String(rows[0]).length()
	def.height_tiles = rows.size()
	def.terrains = region_def.terrains
	def.sprout_seed = region_def.sprout_seed
	var image: Image = Image.create(def.width_tiles, def.height_tiles, false, Image.FORMAT_RGB8)
	var glyphs: Dictionary = {".": &"wasteland", "~": &"water", "#": &"building"}
	for y: int in rows.size():
		for x: int in String(rows[y]).length():
			var v: Vector3i = c8(terrain_def(glyphs[String(rows[y])[x]]).map_color)
			image.set_pixel(x, y, Color8(v.x, v.y, v.z))
	var world: WorldState = RegionLoader.build_state(def, image)
	var ids: PackedByteArray = PackedByteArray()
	ids.resize(world.tile_count())
	for index: int in world.tile_count():
		var zone: int = 0
		for split: int in splits:
			if index % world.width >= split:
				zone += 1
		ids[index] = zone
	world.set_zones(ids, PackedByteArray(states))
	return world

func zone_defs(count: int) -> Array[ZoneDef]:
	var defs: Array[ZoneDef] = []
	for id: int in count:
		var def: ZoneDef = ZoneDef.new()
		def.id = id
		def.key = StringName("z%d" % id)
		def.display_name = "試験地域%d" % id
		defs.append(def)
	return defs

class Rig:
	extends RefCounted
	var world: WorldState
	var field: EnemyField
	var progress: ZoneProgress
	var events: Array = []
	var cleared_count: int = 0
	func on_state(zone: int, old_state: int, new_state: int) -> void:
		events.append([zone, old_state, new_state])
	func on_cleared() -> void:
		cleared_count += 1

func make_rig(rows: Array, splits: Array, states: Array, overrides: Dictionary = {}) -> Rig:
	var rig: Rig = Rig.new()
	rig.world = build_world(rows, splits, states)
	rig.field = EnemyField.new(rig.world, tune(overrides), TILE)
	rig.progress = ZoneProgress.new(rig.world, rig.field)
	rig.world.zone_state_changed.connect(rig.on_state)
	rig.progress.cleared.connect(rig.on_cleared)
	return rig

## Number of target tiles of `zone` counted from the glyph rows and the zone split (independent of the world's counters).
func targets_in(rig: Rig, zone: int) -> Array[int]:
	var result: Array[int] = []
	for index: int in rig.world.tile_count():
		if rig.world.zone_of[index] == zone and rig.world.terrain_defs[rig.world.terrain[index]].is_target:
			result.append(index)
	return result

func put_boar(field: EnemyField, zone: int, pos: Vector2, home: Vector2) -> Boar:
	var boar: Boar = Boar.new()
	boar.id = field.next_boar_id
	field.next_boar_id += 1
	boar.zone = zone
	boar.pos = pos
	boar.home = home
	boar.hp = field.tuning.boar_hp
	boar.wait = 1 << 30
	boar.rng = 1
	field.boars.append(boar)
	return boar

func events_text(events: Array) -> String:
	return JSON.stringify(events)

# ---- tests -------------------------------------------------------------------------------------------------------

func test_region_start() -> void:
	var world: WorldState = RegionLoader.load_region(region_def)
	var field: EnemyField = EnemyField.new(world, tune(), TILE)
	field.setup_nests(region_def.zones)
	var progress: ZoneProgress = ZoneProgress.new(world, field)
	var events: Array = []
	world.zone_state_changed.connect(func(zone: int, old_state: int, new_state: int) -> void: events.append([zone, old_state, new_state]))
	progress.start()
	var expected: Array = [S, U, U, U, U, U, U]
	check(Array(world.zone_state) == expected and events.is_empty() and not world.cleared, "region_01 starts with the start zone stable and six unconquered zones; start() changes nothing")
	var nests_per_zone: Array = [0, 2, 2, 2, 3, 3, 3]
	var counts_ok: bool = true
	for zone: int in 7:
		counts_ok = counts_ok and field.alive_nest_count(zone) == nests_per_zone[zone]
	check(counts_ok, "every unconquered zone starts with its nests (2 2 2 3 3 3), so none advances at start")
	var world2: WorldState = RegionLoader.load_region(region_def)
	var field2: EnemyField = EnemyField.new(world2, tune(), TILE)
	var progress2: ZoneProgress = ZoneProgress.new(world2, field2)
	progress2.start()
	check(world2.zone_state[1] == S and world2.zone_state[0] == S, "a zone that has no nest at all settles to stable at start")

func test_transitions_nests_and_boars() -> void:
	# Zone 0 (x < 30) unconquered with two nests, zone 1 stable. Plants everywhere so the boars have work.
	var rig: Rig = make_rig(open_rows(60, 40), [30], [U, S])
	var nest_a: Nest = rig.field.add_nest(0, Vector2i(5, 5))
	var nest_b: Nest = rig.field.add_nest(0, Vector2i(5, 25))
	rig.progress.start()
	check(rig.world.zone_state[0] == U and rig.events.is_empty(), "two nests alive: unconquered")
	var dt: float = 1.0 / 60.0
	for i: int in 60 * 30:
		rig.field.advance(dt)
	check(rig.field.boars.size() >= 4, "boars came out (%d)" % rig.field.boars.size())
	check(rig.field.damage_nest(nest_a, nest_a.hp_max) and not nest_a.alive, "nest 1 is destroyed")
	check(rig.world.zone_state[0] == U and rig.events.is_empty(), "one nest left: the zone is still unconquered (no state change)")
	var spawned_before: int = nest_b.spawned
	for i: int in 60 * 40:
		rig.field.advance(dt)
	check(nest_b.spawned > spawned_before or nest_b.boar_count == rig.field.tuning.nest_boar_cap, "the surviving nest keeps spawning (%d -> %d)" % [spawned_before, nest_b.spawned])
	# Last nest: damage in steps; only the final point of damage changes the state.
	rig.field.damage_nest(nest_b, nest_b.hp_max - 1)
	check(rig.world.zone_state[0] == U, "a nest with 1 hit point left keeps the zone unconquered")
	rig.field.damage_nest(nest_b, 1)
	check(rig.world.zone_state[0] == C and rig.events == [[0, U, C]], "the last nest falls: clearing (events %s)" % events_text(rig.events))
	check(rig.world.zone_state[1] == S and rig.world.zone_state[0] != S, "the other zone is untouched, and with boars left the zone is not stable yet")
	var total_before: int = rig.field.total_spawned
	for i: int in 60 * 60:
		rig.field.advance(dt)
	check(rig.field.total_spawned == total_before and rig.world.zone_state[0] == C, "clearing: nothing spawns, the state stays clearing while boars live")
	# Kill all boars but one: still clearing; the last one: stable.
	var boars: Array[Boar] = rig.field.boars.duplicate()
	for k: int in boars.size() - 1:
		rig.field.damage_boar(boars[k], 3)
	check(rig.world.zone_state[0] == C and rig.field.boars.size() == 1, "one boar left: still clearing")
	rig.field.damage_boar(boars[boars.size() - 1], 3)
	check(rig.world.zone_state[0] == S and rig.events == [[0, U, C], [0, C, S]], "the last boar falls: stable (events %s)" % events_text(rig.events))
	# Nests destroyed with no boar alive: both steps at once, in order.
	var quick: Rig = make_rig(open_rows(60, 40), [30], [U, S], {"spawn_interval_seconds": 100000.0})
	var nest_q: Nest = quick.field.add_nest(0, Vector2i(5, 5))
	quick.progress.start()
	quick.field.damage_nest(nest_q, nest_q.hp_max)
	check(quick.events == [[0, U, C], [0, C, S]], "no boar alive when the last nest falls: clearing, then stable, in that order")
	# A boar killed while a nest still lives never moves the state.
	var third: Rig = make_rig(open_rows(60, 40), [30], [U, S], {"spawn_interval_seconds": 5.0})
	third.field.add_nest(0, Vector2i(5, 5))
	third.progress.start()
	for i: int in 60 * 30:
		third.field.advance(dt)
	for boar: Boar in third.field.boars.duplicate():
		third.field.damage_boar(boar, 3)
	check(third.field.boars.is_empty() and third.world.zone_state[0] == U and third.events.is_empty(), "all boars dead but a nest alive: still unconquered")

func test_greening_complete() -> void:
	# Zone 0 has 20 x 20 tiles, 3 of them water (not targets); zone 1 is the rest. Both stable, no nests.
	var rows: Array = open_rows(40, 20)
	rows[3] = "~~~" + String(rows[3]).substr(3)
	var rig: Rig = make_rig(rows, [20], [S, S])
	rig.progress.start()
	var targets: Array[int] = targets_in(rig, 0)
	check(targets.size() == 400 - 3 and rig.world.zone_target_count[0] == 397, "zone 0 has 397 greening targets (400 tiles, 3 water)")
	var refused: bool = not rig.world.set_stage(rig.world.index_of(1, 3), WorldState.STAGE_MATURE)
	check(refused, "water is not a target: planting it is refused")
	for k: int in targets.size() - 1:
		rig.world.set_stage(targets[k], WorldState.STAGE_SPROUT1)
	check(rig.world.zone_state[0] == S and rig.events.is_empty(), "396 of 397 greened: stable, not complete")
	check(rig.world.zone_greening_percent_floor(0) == 99, "396 of 397 is 99 percent (floor), not 100")
	check(ZoneHud.status_text(rig.world, zone_defs(2), 0) == "試験地域0  安定  緑化 99％", "the status text shows 99％")
	rig.world.set_stage(targets[targets.size() - 1], WorldState.STAGE_SEED)
	check(rig.world.zone_state[0] == S, "the last tile only as a seed (not greened): still stable")
	rig.world.set_stage(targets[targets.size() - 1], WorldState.STAGE_SPROUT1)
	check(rig.world.zone_state[0] == K and rig.events == [[0, S, K]], "the last tile greened (sprout 1): complete (events %s)" % events_text(rig.events))
	check(rig.world.zone_state[1] == S and not rig.world.cleared, "the other zone is not complete: not cleared")
	check(ZoneHud.status_text(rig.world, zone_defs(2), 0) == "試験地域0  緑化完了  緑化 100％", "the status text shows 100％ / complete")
	# Mature counts too, and a tile that jumps straight to mature completes as well.
	var rig2: Rig = make_rig(rows, [20], [S, S])
	rig2.progress.start()
	var t2: Array[int] = targets_in(rig2, 0)
	for k: int in t2.size() - 1:
		rig2.world.set_stage(t2[k], WorldState.STAGE_MATURE)
	check(rig2.world.zone_state[0] == S, "396 mature of 397: stable")
	rig2.world.set_stage(t2[t2.size() - 1], WorldState.STAGE_MATURE)
	check(rig2.world.zone_state[0] == K, "all mature: complete")
	# Greened before the zone is stable: complete only after it became stable (chain stable -> complete at once).
	var rig3: Rig = make_rig(rows, [20], [U, S], {"spawn_interval_seconds": 1.0})
	var nest: Nest = rig3.field.add_nest(0, Vector2i(10, 10))
	rig3.progress.start()
	for i: int in 60 * 20:
		rig3.field.advance(1.0 / 60.0)
	check(rig3.field.boars.size() > 0, "boars exist in the unconquered test zone")
	for index: int in targets_in(rig3, 0):
		rig3.world.set_stage(index, WorldState.STAGE_MATURE)
	check(rig3.world.zone_greened_count[0] == rig3.world.zone_target_count[0] and rig3.world.zone_state[0] == U and rig3.events.is_empty(), "everything greened but nests alive: still unconquered")
	rig3.field.damage_nest(nest, nest.hp_max)
	check(rig3.world.zone_state[0] == C, "nest destroyed: clearing (boars left, fully greened already)")
	for boar: Boar in rig3.field.boars.duplicate():
		rig3.field.damage_boar(boar, 3)
	check(rig3.events == [[0, U, C], [0, C, S], [0, S, K]], "last boar falls on a fully greened zone: stable and complete in order (events %s)" % events_text(rig3.events))

func test_one_tile_short_on_stable() -> void:
	# One target tile short when the zone becomes stable by the last boar: stable only; the last tile then completes it.
	var rig: Rig = make_rig(open_rows(40, 20), [20], [U, S], {"spawn_interval_seconds": 1.0})
	var nest: Nest = rig.field.add_nest(0, Vector2i(10, 10))
	rig.progress.start()
	for i: int in 60 * 20:
		rig.field.advance(1.0 / 60.0)
	var targets: Array[int] = targets_in(rig, 0)
	for k: int in targets.size() - 1:
		rig.world.set_stage(targets[k], WorldState.STAGE_MATURE)
	rig.field.damage_nest(nest, nest.hp_max)
	for boar: Boar in rig.field.boars.duplicate():
		rig.field.damage_boar(boar, 3)
	check(rig.events == [[0, U, C], [0, C, S]] and rig.world.zone_state[0] == S, "one target tile short when the last boar falls: stable, not complete (events %s)" % events_text(rig.events))
	rig.world.set_stage(targets[targets.size() - 1], WorldState.STAGE_SPROUT2)
	check(rig.world.zone_state[0] == K and rig.events == [[0, U, C], [0, C, S], [0, S, K]], "the last tile (sprout 2) completes it")
	# Same for a state set from outside.
	var rig2: Rig = make_rig(open_rows(40, 20), [20], [U, S])
	rig2.progress.start()
	var t2: Array[int] = targets_in(rig2, 0)
	for k: int in t2.size() - 1:
		rig2.world.set_stage(t2[k], WorldState.STAGE_MATURE)
	rig2.world.set_zone_state(0, S)
	check(rig2.world.zone_state[0] == S, "set stable from outside with one tile short: stays stable")

func test_no_regress() -> void:
	var rows: Array = open_rows(40, 20)
	var rig: Rig = make_rig(rows, [20], [S, S])
	rig.progress.start()
	var targets: Array[int] = targets_in(rig, 0)
	for index: int in targets:
		rig.world.set_stage(index, WorldState.STAGE_MATURE)
	check(rig.world.zone_state[0] == K, "zone complete")
	rig.world.set_stage(targets[7], WorldState.STAGE_EMPTY)
	rig.world.set_stage(targets[8], WorldState.STAGE_SEED)
	check(rig.world.zone_state[0] == K and rig.world.zone_greened_count[0] == 398 and rig.events == [[0, S, K]], "greened count down by 2: the zone stays complete, no new event")
	rig.world.set_stage(targets[7], WorldState.STAGE_MATURE)
	check(rig.world.zone_state[0] == K and rig.events == [[0, S, K]], "greened again: no second event")
	# A stable zone does not fall back to clearing / unconquered, even with a new nest or new enemies.
	var rig2: Rig = make_rig(open_rows(60, 40), [30], [U, S], {"spawn_interval_seconds": 100000.0})
	var nest: Nest = rig2.field.add_nest(0, Vector2i(5, 5))
	rig2.progress.start()
	rig2.field.damage_nest(nest, nest.hp_max)
	check(rig2.world.zone_state[0] == S, "stable after the only nest fell")
	var added: Nest = rig2.field.add_nest(0, Vector2i(5, 20))
	put_boar(rig2.field, 0, Vector2(40, 40), Vector2(40, 40))
	rig2.field.damage_boar(rig2.field.boars[0], 3)
	for i: int in 60 * 60:
		rig2.field.advance(1.0 / 60.0)
	check(added != null and rig2.world.zone_state[0] == S and rig2.field.boars.is_empty() and rig2.field.total_spawned == 0, "a nest added to a stable zone neither reopens it nor spawns")
	# Direct low-level setting back down is the loader's business: ZoneProgress itself never goes down.
	for state: int in [U, C]:
		rig2.world.set_zone_state(0, state)
	check(rig2.world.zone_state[0] != K, "(sanity) the low-level setter is only for tests / loading")

func test_external_stable_purges() -> void:
	# Three zones: 0 and 1 unconquered with nests, 2 stable. Boars of zone 0 vanish when it is set stable from outside.
	var rig: Rig = make_rig(open_rows(90, 40), [30, 60], [U, U, S])
	rig.field.add_nest(0, Vector2i(5, 5))
	rig.field.add_nest(0, Vector2i(5, 25))
	rig.field.add_nest(1, Vector2i(40, 5))
	rig.progress.start()
	var dt: float = 1.0 / 60.0
	for i: int in 60 * 60:
		rig.field.advance(dt)
	var zone0: int = rig.field.boar_count_in_zone(0)
	var zone1: int = rig.field.boar_count_in_zone(1)
	check(zone0 >= 4 and zone1 >= 2, "boars in both zones before (%d, %d)" % [zone0, zone1])
	var killed: int = rig.field.total_killed
	var carcasses: int = rig.field.carcasses.size()
	rig.world.set_zone_state(0, S)
	check(rig.field.boar_count_in_zone(0) == 0 and rig.field.boar_count_in_zone(1) == zone1, "zone 0 set stable from outside: its boars are gone at once, the other zone's are not (%d)" % rig.field.boar_count_in_zone(1))
	check(rig.field.total_killed == killed and rig.field.carcasses.size() == carcasses, "they vanish without a kill count or carcass")
	var counts_ok: bool = true
	for nest: Nest in rig.field.nests:
		counts_ok = counts_ok and nest.boar_count == rig.field.boar_count_in_zone(nest.zone)
	check(counts_ok, "nest boar counters match the boars left")
	check(rig.world.zone_state[0] == S and rig.world.zone_state[1] == U, "external stable also leaves the zone stable (not pushed on); the other zone keeps its state")
	var gnawed: int = rig.field.total_gnawed
	for i: int in 60 * 60:
		rig.field.advance(dt)
	var zone0_boars: int = rig.field.boar_count_in_zone(0)
	check(zone0_boars == 0, "a minute later still no boar in zone 0 (their nests spawn nothing)")
	# Complete does the same.
	rig.world.set_zone_state(1, K)
	check(rig.field.boar_count_in_zone(1) == 0, "zone 1 set complete from outside: its boars are gone")
	check(rig.field.total_gnawed >= gnawed, "(info) biting counter only grows: %d" % rig.field.total_gnawed)
	# Setting clearing from outside removes nobody.
	var rig2: Rig = make_rig(open_rows(60, 40), [30], [U, S])
	rig2.field.add_nest(0, Vector2i(5, 5))
	for i: int in 60 * 30:
		rig2.field.advance(dt)
	var present: int = rig2.field.boars.size()
	rig2.world.set_zone_state(0, C)
	check(present > 0 and rig2.field.boars.size() == present, "setting clearing from outside removes no boar (%d)" % present)

func test_contact_after_stable() -> void:
	# P2-03 finding: a boar that stood still in a stable zone could still hurt by touch. Now it is gone.
	var defs: Array[PlantDef] = []
	defs.assign(region_def.plants)
	var hp_by_case: Array = []
	for stable_first: bool in [false, true]:
		var rig: Rig = make_rig(open_rows(60, 40), [30], [U, S], {"spawn_interval_seconds": 100000.0})
		var play: PlayState = PlayState.new(rig.world, play_tuning, sim_tuning, TILE, [], defs)
		play.enemies = rig.field
		var boar: Boar = put_boar(rig.field, 0, Vector2(60, 60), Vector2(60, 60))
		if stable_first:
			rig.world.set_zone_state(0, S)
		for i: int in 60 * 5:
			rig.field.advance(1.0 / 60.0)
			play.advance(1.0 / 60.0, boar.pos)
		hp_by_case.append(play.hp)
	check(hp_by_case[0] < play_tuning.hp_max, "control: a boar in an unconquered zone hurts on touch (HP %d)" % hp_by_case[0])
	check(hp_by_case[1] == play_tuning.hp_max, "a boar of a zone that became stable is gone: no touch damage in 5 s (HP %d)" % hp_by_case[1])

func test_texts_and_notices() -> void:
	var zones: Array[ZoneDef] = zone_defs(3)
	check(ZoneHud.change_text(zones, 1, C) == "試験地域1の巣をすべて壊した", "notice text: clearing")
	check(ZoneHud.change_text(zones, 1, S) == "試験地域1が安定した", "notice text: stable")
	check(ZoneHud.change_text(zones, 2, K) == "試験地域2の緑化が完了した", "notice text: complete")
	check(ZoneHud.change_text(zones, 2, U) == "", "no notice for unconquered")
	check(ZoneHud.CLEARED_TEXT == "すべての地域を緑化した", "clear text")
	var names: Array[String] = []
	for state: int in 4:
		names.append(ZoneHud.state_name(state))
	check(names == ["未制圧", "掃討中", "安定", "緑化完了"], "state names")
	# Status follows the position and the numbers.
	var rig: Rig = make_rig(open_rows(40, 20), [20], [U, S])
	rig.field.add_nest(0, Vector2i(2, 2))
	rig.progress.start()
	var left: Array[int] = targets_in(rig, 0)
	for k: int in 123:
		rig.world.set_stage(left[k], WorldState.STAGE_MATURE)
	# 123 of 400 = 30.75 -> 30.
	check(ZoneHud.zone_at_position(rig.world, TILE, Vector2(10, 10)) == 0 and ZoneHud.zone_at_position(rig.world, TILE, Vector2(100, 10)) == 1 and ZoneHud.zone_at_position(rig.world, TILE, Vector2(-1, 10)) == -1, "zone under a position")
	check(ZoneHud.status_text(rig.world, zones, 0) == "試験地域0  未制圧  緑化 30％", "status at 123 / 400: 30％ (floor of 30.75): " + ZoneHud.status_text(rig.world, zones, 0))
	check(ZoneHud.status_text(rig.world, zones, 1) == "試験地域1  安定  緑化 0％", "the other zone: its own state and rate")
	check(ZoneHud.status_text(rig.world, zones, -1) == "", "outside the map: no text")
	# Notice queue.
	var notice: ZoneNotice = ZoneNotice.new()
	notice.setup(Theme.new(), Vector2(160, 40))
	notice.push("一")
	notice.push("二")
	notice.push("三", 8.0)
	check(notice.current_text == "一" and notice.visible and notice.queue.size() == 2, "the first notice shows at once, the others wait")
	notice.advance(2.9)
	check(notice.current_text == "一", "still the first at 2.9 s")
	notice.advance(0.2)
	check(notice.current_text == "二", "the second after 3 s")
	notice.advance(3.0)
	check(notice.current_text == "三" and notice.remaining == 8.0, "the third has its own duration (8 s)")
	notice.advance(7.9)
	check(notice.visible and notice.current_text == "三", "still showing at 7.9 s")
	notice.advance(0.2)
	check(not notice.visible and notice.current_text == "", "hidden when the queue is empty")
	check(notice.shown_log == ["一", "二", "三"], "log of shown texts")
	notice.push("a")
	for k: int in 10:
		notice.push("b%d" % k)
	check(notice.queue.size() == ZoneNotice.QUEUE_MAX, "the queue holds at most %d waiting notices" % ZoneNotice.QUEUE_MAX)
	check(notice.position == Vector2(160, 40) and notice.size == Vector2(320, 22), "the panel sits on whole pixels (160, 40) size 320 x 22")
	notice.free()
	# Notices follow the real transitions.
	var log_notice: ZoneNotice = ZoneNotice.new()
	log_notice.setup(Theme.new(), Vector2.ZERO)
	var rig2: Rig = make_rig(open_rows(60, 40), [30], [U, S], {"spawn_interval_seconds": 100000.0})
	var nest: Nest = rig2.field.add_nest(0, Vector2i(5, 5))
	var zdefs: Array[ZoneDef] = zone_defs(2)
	rig2.world.zone_state_changed.connect(func(zone: int, _old: int, new_state: int) -> void: log_notice.push(ZoneHud.change_text(zdefs, zone, new_state)))
	rig2.progress.start()
	rig2.field.damage_nest(nest, nest.hp_max)
	check(log_notice.shown_log == ["試験地域0の巣をすべて壊した"] and log_notice.queue.size() == 1 and String(log_notice.queue[0]["text"]) == "試験地域0が安定した", "a transition produces its notice, in order")
	log_notice.free()

func test_clear_state() -> void:
	var rig: Rig = make_rig(open_rows(40, 20), [20], [S, S])
	rig.progress.start()
	check(not rig.world.cleared and rig.cleared_count == 0, "not cleared at start")
	for index: int in targets_in(rig, 0):
		rig.world.set_stage(index, WorldState.STAGE_MATURE)
	check(rig.world.zone_state[0] == K and not rig.world.cleared and rig.cleared_count == 0, "one zone complete: not cleared")
	var t1: Array[int] = targets_in(rig, 1)
	for k: int in t1.size() - 1:
		rig.world.set_stage(t1[k], WorldState.STAGE_MATURE)
	check(not rig.world.cleared, "one tile short in the last zone: not cleared")
	rig.world.set_stage(t1[t1.size() - 1], WorldState.STAGE_MATURE)
	check(rig.world.cleared and rig.cleared_count == 1 and rig.world.zone_state[1] == K, "the last tile: the region is cleared, signal once")
	check(ZoneHud.status_text(rig.world, zone_defs(2), 1) == "試験地域1  緑化完了  緑化 100％  【全地域緑化】", "the status shows the clear mark")
	# Play goes on: a plant removed, a boar spawned elsewhere — still cleared, signal not repeated.
	rig.world.set_stage(t1[0], WorldState.STAGE_EMPTY)
	rig.world.set_stage(t1[0], WorldState.STAGE_MATURE)
	rig.progress.start()
	check(rig.world.cleared and rig.cleared_count == 1 and rig.world.zone_state[1] == K, "greening drops and returns, start() again: still cleared, one signal")
	# Set from outside: all zones complete -> cleared by the state-change event.
	var rig2: Rig = make_rig(open_rows(40, 20), [20], [S, S])
	rig2.progress.start()
	rig2.world.set_zone_state(0, K)
	check(not rig2.world.cleared and rig2.cleared_count == 0, "one zone set complete from outside: not cleared")
	rig2.world.set_zone_state(1, K)
	check(rig2.world.cleared and rig2.cleared_count == 1, "all zones set complete from outside: cleared")
	# Three zones, a clearing zone blocks the clear.
	var rig3: Rig = make_rig(open_rows(60, 20), [20, 40], [K, K, C])
	rig3.progress.start()
	check(not rig3.world.cleared, "a zone that is only clearing (boar-less settles to stable, not complete): not cleared")

func test_save_round_trip() -> void:
	var rig: Rig = make_rig(open_rows(40, 20), [20], [U, S], {"spawn_interval_seconds": 100000.0})
	var nest: Nest = rig.field.add_nest(0, Vector2i(5, 5))
	rig.progress.start()
	rig.field.damage_nest(nest, nest.hp_max)
	for index: int in targets_in(rig, 0):
		rig.world.set_stage(index, WorldState.STAGE_MATURE)
	for index: int in targets_in(rig, 1):
		rig.world.set_stage(index, WorldState.STAGE_MATURE)
	check(rig.world.cleared and Array(rig.world.zone_state) == [K, K], "built a cleared world (states %s)" % [Array(rig.world.zone_state)])
	var data: Dictionary = rig.world.to_dict()
	var copy: WorldState = WorldState.from_dict(data, rig.world.terrain_defs)
	check(copy != null and copy.zone_state == rig.world.zone_state and copy.cleared and copy.zone_target_count == rig.world.zone_target_count and copy.zone_greened_count == rig.world.zone_greened_count, "states, clear flag and counters survive a round trip")
	var json: JSON = JSON.new()
	var text: String = JSON.stringify(data)
	var parsed_ok: bool = json.parse(text) == OK
	var from_json: WorldState = WorldState.from_dict(json.data, rig.world.terrain_defs) if parsed_ok else null
	check(from_json != null and from_json.zone_state == rig.world.zone_state and from_json.cleared, "states and the clear flag survive a JSON text round trip")
	# All four states in one world, and a field that goes with it.
	var mixed: Rig = make_rig(open_rows(80, 20), [20, 40, 60], [U, C, S, K], {"spawn_interval_seconds": 100000.0})
	for index: int in targets_in(mixed, 3):
		mixed.world.set_stage(index, WorldState.STAGE_MATURE)
	mixed.field.add_nest(0, Vector2i(5, 5))
	var mixed_data: Dictionary = mixed.world.to_dict()
	var mixed_copy: WorldState = WorldState.from_dict(mixed_data, mixed.world.terrain_defs)
	check(mixed_copy != null and Array(mixed_copy.zone_state) == [U, C, S, K] and not mixed_copy.cleared, "all four states round trip, not cleared")
	var field_data: Dictionary = mixed.field.to_dict()
	var restored: EnemyField = EnemyField.new(mixed_copy, tune(), TILE)
	check(restored.load_dict(field_data, true) and JSON.stringify(restored.to_dict()) == JSON.stringify(field_data), "the enemy data loads onto the restored world and round trips")
	var progress: ZoneProgress = ZoneProgress.new(mixed_copy, restored)
	progress.start()
	check(Array(mixed_copy.zone_state) == [U, S, S, K] and not mixed_copy.cleared, "start() on the restored world only settles: zone 0 keeps its live nest (unconquered), the nest-less clearing zone 1 with no boar becomes stable, 2 and 3 stay")

func test_load_refusals() -> void:
	var rig: Rig = make_rig(open_rows(40, 20), [20], [U, S], {"spawn_interval_seconds": 100000.0})
	rig.field.add_nest(0, Vector2i(5, 5))
	var dead: Nest = rig.field.add_nest(0, Vector2i(5, 12))
	rig.field.destroy_nest(dead)
	put_boar(rig.field, 0, Vector2(60, 60), Vector2(60, 60))
	var good_world: Dictionary = rig.world.to_dict()
	var good_field: Dictionary = rig.field.to_dict()
	var fresh: WorldState = WorldState.from_dict(good_world, rig.world.terrain_defs)
	var base: EnemyField = EnemyField.new(fresh, tune(), TILE)
	check(base.load_dict(good_field), "(control) consistent data loads: unconquered zone with a live nest and a boar")
	# World level.
	var bad: Dictionary = good_world.duplicate(true)
	bad["zones"]["state"] = [K, S]
	# P2-05 (parent decision): complete is forward-only, so a complete zone with fewer greened tiles than targets is accepted.
	var short_complete: WorldState = WorldState.from_dict(bad, rig.world.terrain_defs)
	check(short_complete != null and short_complete.zone_state[0] == K and short_complete.zone_greened_count[0] < short_complete.zone_target_count[0] and not short_complete.cleared, "a complete zone with ungreened targets is accepted (P2-05: complete is forward-only)")
	bad = good_world.duplicate(true)
	bad["cleared"] = true
	check(WorldState.from_dict(bad, rig.world.terrain_defs) == null, "the clear flag with zones that are not complete is refused")
	var full: Rig = make_rig(open_rows(40, 20), [20], [S, S])
	for index: int in full.world.tile_count():
		full.world.set_stage(index, WorldState.STAGE_MATURE)
	full.progress.start()
	check(full.world.cleared, "(control) a fully greened world is cleared")
	bad = full.world.to_dict()
	bad["cleared"] = false
	check(WorldState.from_dict(bad, full.world.terrain_defs) == null, "all zones complete but the flag off is refused")
	bad = full.world.to_dict()
	bad.erase("cleared")
	var derived: WorldState = WorldState.from_dict(bad, full.world.terrain_defs)
	check(derived != null and derived.cleared, "a save without the flag derives it from the zone states")
	bad = good_world.duplicate(true)
	bad["zones"]["state"] = [9, S]
	check(WorldState.from_dict(bad, rig.world.terrain_defs) == null, "an unknown state is refused")
	# Enemy level: build worlds with the zone state changed, load the enemy data onto them.
	var cases: Array = [
		["a live nest in a stable zone", [S, S], good_field],
		["a live nest in a complete zone", [K, S], good_field],
		["a live nest in a clearing zone", [C, S], good_field],
		["a boar in a stable zone", [S, S], null],
	]
	for entry: Array in cases:
		var world: WorldState = WorldState.from_dict(good_world, rig.world.terrain_defs)
		world.zone_state = PackedByteArray(entry[1])
		var field: EnemyField = EnemyField.new(world, tune(), TILE)
		var data: Dictionary = good_field
		if entry[2] == null:
			data = good_field.duplicate(true)
			for n: Dictionary in data["nests"]:
				n["alive"] = false
				n["hp"] = 0
		var boars_before: int = field.boars.size()
		check(not field.load_dict(data) and field.boars.size() == boars_before and field.nests.is_empty(), "refused: %s (state unchanged)" % entry[0])
	# All nests dead but the zone still unconquered.
	var world2: WorldState = WorldState.from_dict(good_world, rig.world.terrain_defs)
	var field2: EnemyField = EnemyField.new(world2, tune(), TILE)
	var data2: Dictionary = good_field.duplicate(true)
	for n: Dictionary in data2["nests"]:
		n["alive"] = false
		n["hp"] = 0
	data2["boars"] = []
	check(not field2.load_dict(data2), "refused: every nest of an unconquered zone is dead")
	world2.zone_state = PackedByteArray([S, S])
	check(field2.load_dict(data2), "the same data with the zone stable loads")
	# Consistent saves of every state still load.
	var okcases: Array = [[C, "clearing, a boar left"], [U, "unconquered"]]
	for entry: Array in okcases:
		var world: WorldState = WorldState.from_dict(good_world, rig.world.terrain_defs)
		world.zone_state = PackedByteArray([entry[0], S])
		var field: EnemyField = EnemyField.new(world, tune(), TILE)
		var data: Dictionary = good_field.duplicate(true)
		if entry[0] == C:
			for n: Dictionary in data["nests"]:
				n["alive"] = false
				n["hp"] = 0
		check(field.load_dict(data), "loads: %s" % entry[1])

func scenario(hz: int) -> Array:
	var rig: Rig = make_rig(open_rows(60, 40), [30], [U, S])
	rig.field.add_nest(0, Vector2i(5, 5))
	rig.field.add_nest(0, Vector2i(5, 25))
	rig.progress.start()
	var dt: float = 1.0 / float(hz)
	var frames: int = 90 * hz
	var log_times: Array = []
	rig.world.zone_state_changed.connect(func(zone: int, _old: int, new_state: int) -> void: log_times.append([zone, new_state, snappedf(rig.field.time, 0.001)]))
	for i: int in range(1, frames + 1):
		rig.field.advance(dt)
		if i == 60 * hz:
			for nest: Nest in rig.field.nests:
				rig.field.damage_nest(nest, nest.hp_max)
		if i == 75 * hz:
			for boar: Boar in rig.field.boars.duplicate():
				rig.field.damage_boar(boar, 3)
	return [Array(rig.world.zone_state), rig.field.total_spawned, rig.field.total_killed, log_times.size(), rig.events]

func test_frame_rates() -> void:
	var results: Array = []
	for hz: int in [30, 60, 144]:
		results.append(scenario(hz))
	var same: bool = true
	for r: Array in results:
		same = same and JSON.stringify(r) == JSON.stringify(results[0])
	check(same and results[0][0] == [S, S] and results[0][4] == [[0, U, C], [0, C, S]], "30 / 60 / 144 Hz: the same transitions, spawns and kills (state %s, spawned %d, killed %d)" % [results[0][0], results[0][1], results[0][2]])
	info["hz_scenario"] = {"spawned": results[0][1], "killed": results[0][2]}

func test_cost() -> void:
	var world: WorldState = RegionLoader.load_region(region_def)
	var field: EnemyField = EnemyField.new(world, tune(), TILE)
	field.setup_nests(region_def.zones)
	var indices: PackedInt32Array = PackedInt32Array()
	for index: int in world.tile_count():
		if world.target[index] == 1 and world.stage[index] == WorldState.STAGE_EMPTY and indices.size() < 30000:
			indices.append(index)
	var started: int = Time.get_ticks_usec()
	for index: int in indices:
		world.set_stage(index, WorldState.STAGE_SPROUT1)
		world.set_stage(index, WorldState.STAGE_EMPTY)
	var plain: float = float(Time.get_ticks_usec() - started) / float(indices.size() * 2)
	var progress: ZoneProgress = ZoneProgress.new(world, field)
	progress.start()
	started = Time.get_ticks_usec()
	for index: int in indices:
		world.set_stage(index, WorldState.STAGE_SPROUT1)
		world.set_stage(index, WorldState.STAGE_EMPTY)
	var with_progress: float = float(Time.get_ticks_usec() - started) / float(indices.size() * 2)
	info["set_stage_us"] = {"without_progress": plain, "with_progress": with_progress}
	check(with_progress - plain < 5.0, "the greening event hook adds under 5 us per set_stage (%.2f -> %.2f us)" % [plain, with_progress])

# ---- no re-invasion --------------------------------------------------------------------------------------------------

## Feet-rectangle corner tiles of a boar all lie in `zone` (zone layer lookup by the test itself).
func boar_footprint_in(world: WorldState, boar: Boar, tuning: EnemyTuning, zone: int) -> bool:
	for sx: int in [-1, 1]:
		for sy: int in [-1, 1]:
			var x: int = floori((boar.pos.x + float(sx) * (tuning.boar_half_width_px - 0.001)) / TILE)
			var y: int = floori((boar.pos.y + float(sy) * (tuning.boar_half_height_px - 0.001)) / TILE)
			if not world.in_bounds(x, y) or world.zone_of[world.index_of(x, y)] != zone:
				return false
	return true

func fill_rect(world: WorldState, rect: Rect2i, only_zone: int = -1) -> int:
	var count: int = 0
	for y: int in range(maxi(rect.position.y, 0), mini(rect.end.y, world.height)):
		for x: int in range(maxi(rect.position.x, 0), mini(rect.end.x, world.width)):
			var index: int = world.index_of(x, y)
			if only_zone >= 0 and world.zone_of[index] != only_zone:
				continue
			if world.occupant[index] == 0 and world.stage[index] == WorldState.STAGE_EMPTY and world.set_stage(index, WorldState.STAGE_MATURE):
				count += 1
	return count

## Collects every plant change of a closed zone: WorldState.tile_listener fires for each tile that turns mature / stops being
## mature / becomes empty (all plants of these tests are mature, so any bite or growth in a closed zone is reported).
class Watch:
	extends RefCounted
	var world: WorldState
	var closed: Dictionary = {}
	var touched: int = 0
	var first_index: int = -1
	func on_tile(index: int, _old: int, _new: int) -> void:
		if closed.has(int(world.zone_of[index])):
			touched += 1
			if first_index < 0:
				first_index = index

func test_no_reinvasion_test_map() -> void:
	# Test map: stable zone 0 (x < 50) full of plants right up to the border, enemy zone 1 (x >= 50) with three nests close to the
	# border. A bait strip of plants on the enemy side along the border is renewed every 5 s so boars keep coming to the border.
	var rig: Rig = make_rig(open_rows(100, 40), [50], [S, U])
	rig.field.add_nest(1, Vector2i(52, 4))
	rig.field.add_nest(1, Vector2i(52, 18))
	rig.field.add_nest(1, Vector2i(52, 32))
	rig.progress.start()
	fill_rect(rig.world, Rect2i(0, 0, 50, 40))
	fill_rect(rig.world, Rect2i(50, 0, 2, 40))
	var zone0_targets: int = rig.world.zone_target_count[0]
	var zone0_greened: int = rig.world.zone_greened_count[0]
	var snapshot: PackedByteArray = rig.world.stage.duplicate()
	var watch: Watch = Watch.new()
	watch.world = rig.world
	watch.closed = {0: true}
	rig.world.tile_listener = watch.on_tile
	var dt: float = 1.0 / 60.0
	var frames: int = 60 * 60 * 20
	var tuning: EnemyTuning = rig.field.tuning
	var violations: int = 0
	var first: String = ""
	var near_border_frames: int = 0
	var max_boars: int = 0
	var gnaw_radius_px: float = tuning.gnaw_radius_tiles * TILE
	var started: int = Time.get_ticks_msec()
	for i: int in range(1, frames + 1):
		rig.field.advance(dt)
		if i % 300 == 0:
			fill_rect(rig.world, Rect2i(50, 0, 2, 40), 1)
		max_boars = maxi(max_boars, rig.field.boars.size())
		for boar: Boar in rig.field.boars:
			if boar.zone != 1 or not boar_footprint_in(rig.world, boar, tuning, 1):
				violations += 1
				if first == "":
					first = "frame %d boar %d at %s" % [i, boar.id, boar.pos]
			if boar.pos.x - tuning.boar_half_width_px <= 50.0 * TILE + gnaw_radius_px:
				near_border_frames += 1
	var seconds: float = float(Time.get_ticks_msec() - started) / 1000.0
	var intact: bool = true
	for y: int in 40:
		intact = intact and rig.world.stage.slice(y * 100, y * 100 + 50) == snapshot.slice(y * 100, y * 100 + 50)
	check(violations == 0, "20 min, every frame: no boar footprint left zone 1 (boar-frames within bite reach of the border: %d) %s" % [near_border_frames, first])
	check(near_border_frames > 1000, "the test is not vacuous: boars were at the border for %d boar-frames" % near_border_frames)
	check(watch.touched == 0 and intact and rig.world.zone_greened_count[0] == zone0_greened and zone0_greened == zone0_targets, "no tile of the stable zone changed in 20 min: %d change events, stages equal the snapshot, %d of %d greened" % [watch.touched, zone0_greened, zone0_targets])
	check(rig.world.zone_state[0] == K and max_boars >= 6 and rig.field.total_gnawed > 100, "zone 0 was fully planted, so it is complete (closed all the same); the enemy zone was active (max %d boars, %d tiles bitten)" % [max_boars, rig.field.total_gnawed])
	check(rig.world.counters_consistent(), "counters equal a recount after the run")
	info["no_reinvasion_test_map"] = {"game_minutes": 20, "frames": frames, "max_boars": max_boars, "near_border_boar_frames": near_border_frames, "tiles_gnawed": rig.field.total_gnawed, "cpu_seconds": seconds}

func test_no_reinvasion_region() -> void:
	var world: WorldState = RegionLoader.load_region(region_def)
	var field: EnemyField = EnemyField.new(world, tune(), TILE)
	field.setup_nests(region_def.zones)
	var progress: ZoneProgress = ZoneProgress.new(world, field)
	progress.start()
	var tuning: EnemyTuning = field.tuning
	# Plants for the boars next to every nest (own zone only), bait in the stable start zone along its north border.
	for nest: Nest in field.nests:
		fill_rect(world, Rect2i(nest.tile.x - 14, nest.tile.y - 14, 32, 32), nest.zone)
	fill_rect(world, Rect2i(130, 125, 110, 25), 0)
	var start_snapshot: PackedByteArray = PackedByteArray()
	var start_tiles: PackedInt32Array = PackedInt32Array()
	for index: int in world.tile_count():
		if world.zone_of[index] == 0:
			start_tiles.append(index)
			start_snapshot.append(world.stage[index])
	var watch: Watch = Watch.new()
	watch.world = world
	watch.closed = {0: true}
	world.tile_listener = watch.on_tile
	var dt: float = 1.0 / 30.0
	var frames: int = 30 * 60 * 20
	var violations: int = 0
	var first: String = ""
	var boar_frames: int = 0
	var late_zone: int = -1
	var late_before: int = 0
	var late_snapshot: PackedByteArray = PackedByteArray()
	var late_tiles: PackedInt32Array = PackedInt32Array()
	var started: int = Time.get_ticks_msec()
	for i: int in range(1, frames + 1):
		field.advance(dt)
		if i % 150 == 0:
			for nest: Nest in field.nests:
				if nest.alive and world.zone_open_to_enemies(nest.zone):
					fill_rect(world, Rect2i(nest.tile.x - 14, nest.tile.y - 14, 32, 32), nest.zone)
		if i == frames / 2:
			# At 10 min the zone with the most boars is set stable from outside.
			for zone: int in range(1, 7):
				if field.boar_count_in_zone(zone) > late_before:
					late_before = field.boar_count_in_zone(zone)
					late_zone = zone
			for index: int in world.tile_count():
				if world.zone_of[index] == late_zone:
					late_tiles.append(index)
			world.set_zone_state(late_zone, S)
			watch.closed[late_zone] = true
			watch.touched = 0
			check(late_before > 0 and field.boar_count_in_zone(late_zone) == 0, "region_01 at 10 min: zone %d (%d boars) set stable from outside: all its boars gone at once" % [late_zone, late_before])
			# Snapshot after the purge (nothing bites any more) for the closed zone.
			for index: int in late_tiles:
				late_snapshot.append(world.stage[index])
		for boar: Boar in field.boars:
			boar_frames += 1
			if watch.closed.has(boar.zone) or not boar_footprint_in(world, boar, tuning, boar.zone):
				violations += 1
				if first == "":
					first = "frame %d boar %d zone %d at %s" % [i, boar.id, boar.zone, boar.pos]
	var seconds: float = float(Time.get_ticks_msec() - started) / 1000.0
	var start_now: PackedByteArray = PackedByteArray()
	for index: int in start_tiles:
		start_now.append(world.stage[index])
	var late_now: PackedByteArray = PackedByteArray()
	for index: int in late_tiles:
		late_now.append(world.stage[index])
	check(violations == 0, "region_01, 20 min, every frame (%d boar-frames): every boar stood in its own open zone, none in a closed one %s" % [boar_frames, first])
	check(watch.touched == 0 and start_now == start_snapshot and late_now == late_snapshot, "region_01: no plant of the closed zones (start zone for 20 min; zone %d after 10 min) changed (%d change events)" % [late_zone, watch.touched])
	check(world.counters_consistent() and field.total_gnawed > 500, "region_01: counters equal a recount; %d tiles bitten overall" % field.total_gnawed)
	info["no_reinvasion_region_01"] = {"game_minutes": 20, "frames": frames, "boar_frames_checked": boar_frames, "tiles_gnawed": field.total_gnawed, "closed_late_zone": late_zone, "cpu_seconds": seconds}

# ---- scene (injected mouse input only) ---------------------------------------------------------------------------------

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

func expected_percent(world: WorldState, zone: int) -> int:
	var targets: int = 0
	var greened: int = 0
	for index: int in world.tile_count():
		if world.zone_of[index] == zone and world.terrain_defs[world.terrain[index]].is_target:
			targets += 1
			if world.stage[index] >= WorldState.STAGE_SPROUT1:
				greened += 1
	return greened * 100 / targets

func test_scene() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await wait_frames(3)
	player = main.player
	var play: PlayState = main.play
	var world: WorldState = main.grid
	var enemies: EnemyField = main.enemies
	var notice: ZoneNotice = main.zone_notice
	var cleared_signals: Array[int] = [0]
	main.zone_progress.cleared.connect(func() -> void: cleared_signals[0] += 1)
	check(main.zone_progress != null and notice != null and main.zone_label != null, "scene: ZoneProgress, the notice panel and the zone label exist")
	check(main.zone_label.text == "  開始地域 (西岸中部)  安定  緑化 %d％" % expected_percent(world, 0), "scene: the player at the start sees the start zone: '%s'" % main.zone_label.text)
	# Zone 2 = "西岸南1" with nests at (175,300) and (60,350). Keep only the first; nothing spawns by itself in this test.
	enemies._spawn_steps = 1 << 30
	var zone: int = 2
	var keep: Nest = null
	for nest: Nest in enemies.nests:
		if nest.zone == zone:
			if keep == null:
				keep = nest
			else:
				enemies.destroy_nest(nest)
	check(keep != null and world.zone_state[zone] == U, "scene: zone 2 keeps one nest and is still unconquered after the other one was removed")
	var others_untouched: bool = world.zone_state[0] == S
	for z: int in range(1, world.zone_count):
		others_untouched = others_untouched and world.zone_state[z] == U
	check(others_untouched, "scene: the start zone is stable, the six others unconquered")
	check(enemies._spawn(keep) and enemies.boars.size() >= 1, "scene: a boar of the zone stands near the nest")
	var boar: Boar = null
	for candidate: Boar in enemies.boars:
		if candidate.zone == zone:
			boar = candidate
	boar.wait = 1 << 30
	var centre: Vector2 = keep.center_px(TILE)
	var away: Vector2 = (boar.pos - centre).normalized()
	var spot: Vector2 = Vector2.INF
	for angle_deg: int in [180, 150, 210, 120, 240, 90, 270]:
		var candidate_spot: Vector2 = centre + (-away).rotated(deg_to_rad(float(angle_deg - 180))) * 30.0
		if Walker.is_clear(world, TILE, candidate_spot, Vector2(play_tuning.walk_half_width_px, play_tuning.walk_half_height_px)) and ZoneHud.zone_at_position(world, TILE, candidate_spot) == zone:
			spot = candidate_spot
			break
	check(spot != Vector2.INF, "scene: a free spot opposite to the boar was found")
	await teleport(spot)
	play.seeds = play_tuning.seed_max
	var percent: int = expected_percent(world, zone)
	check(main.zone_label.text == "  西岸南1  未制圧  緑化 %d％" % percent, "scene: the top bar names the zone, state and rate: '%s'" % main.zone_label.text)
	# Shoot the nest dead with injected clicks (the shipped nest hit points, 30 since P2-06; 1 per seed).
	await aim_at(centre)
	var shots: int = 0
	var state_before_last: int = -1
	while keep.alive and shots < 50:
		if keep.hp == 1:
			state_before_last = world.zone_state[zone]
		await click(MOUSE_BUTTON_LEFT)
		await wait_frames(22)
		shots += 1
	check(main.enemy_tuning.nest_hp == 30 and not keep.alive and shots == 30, "scene: the nest (shipped hit points 30) fell to %d injected clicks" % shots)
	check(state_before_last == U, "scene: with 1 hit point left the zone was still unconquered")
	check(world.zone_state[zone] == C, "scene: the last nest destroyed: the zone is clearing")
	check(notice.shown_log.size() >= 1 and notice.shown_log[0] == "西岸南1の巣をすべて壊した", "scene: the notice says so: %s" % [notice.shown_log])
	check(main.zone_label.text == "  西岸南1  掃討中  緑化 %d％" % expected_percent(world, zone), "scene: the top bar shows clearing: '%s'" % main.zone_label.text)
	# Pause: the shown notice does not age, the enemy steps stand still.
	var remaining: float = notice.remaining
	var steps: int = enemies.steps_done
	paused = true
	await wait_frames(30)
	check(notice.remaining == remaining and enemies.steps_done == steps, "scene: while paused the notice neither ages nor hides (%.3f) and the enemy steps stand still" % notice.remaining)
	paused = false
	# Kill the boar with three clicks.
	var body: Vector2 = enemies.boar_body_center(boar)
	check(boar.zone == zone and enemies.boars.has(boar), "scene: the boar is still there and the zone is not stable yet")
	await aim_at(body)
	for k: int in 3:
		await click(MOUSE_BUTTON_LEFT)
		await wait_frames(22)
	check(not enemies.boars.has(boar) and enemies.boar_count_in_zone(zone) == 0, "scene: three clicks defeat the last boar of the zone")
	check(world.zone_state[zone] == S, "scene: the zone is stable")
	check(main.zone_label.text == "  西岸南1  安定  緑化 %d％" % expected_percent(world, zone), "scene: the top bar shows stable: '%s'" % main.zone_label.text)
	for k: int in 10:
		await wait_frames(60)
		if notice.shown_log.size() >= 2:
			break
	check(notice.shown_log.size() >= 2 and notice.shown_log[1] == "西岸南1が安定した", "scene: the stable notice follows the first one: %s" % [notice.shown_log])
	others_untouched = world.zone_state[0] == S
	for z: int in range(1, world.zone_count):
		if z != zone:
			others_untouched = others_untouched and world.zone_state[z] == U
	check(others_untouched and notice.shown_log.size() == 2, "scene: the other zones did not move (their nests live) and exactly two notices were shown")
	# Everything else complete -> cleared; play goes on.
	check(not world.cleared and cleared_signals[0] == 0, "scene: not cleared yet")
	for z: int in world.zone_count:
		world.set_zone_state(z, maxi(world.zone_state[z], S))
	world.debug_fill_stage(Rect2i(0, 0, world.width, world.height), WorldState.STAGE_MATURE)
	await wait_frames(3)
	check(world.cleared and cleared_signals[0] == 1 and world.all_zones_complete(), "scene: every zone greened: complete, cleared flag and one clear signal")
	var guard: int = 0
	while notice.current_text != ZoneHud.CLEARED_TEXT and guard < 40:
		notice.advance(10.0)
		guard += 1
	check(notice.current_text == "すべての地域を緑化した" and notice.visible and notice.remaining == 8.0, "scene: the clear notice is shown for 8 s")
	check(main.zone_label.text.ends_with("【全地域緑化】") and main.zone_label.text.contains("緑化完了  緑化 100％"), "scene: the top bar shows the clear mark: '%s'" % main.zone_label.text)
	var seeds_before: int = play.seeds
	await aim_at(player.position + Vector2(60, 0))
	await click(MOUSE_BUTTON_LEFT)
	await wait_frames(10)
	check(play.seeds == seeds_before - 1, "scene: after the clear the game goes on (a shot still costs a seed)")
	var saved: Dictionary = world.to_dict()
	var restored: WorldState = WorldState.from_dict(saved, world.terrain_defs)
	check(restored != null and restored.cleared and restored.zone_state == world.zone_state, "scene: the cleared world survives a save round trip")
	Engine.time_scale = 1.0
	main.queue_free()
	await process_frame
