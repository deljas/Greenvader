extends RefCounted
## The single source of truth for PoC world state. No Node/rendering dependency.
## Owns WorldState, the one SimClock (game time), the simulators and the player's logical position.
const Config: GDScript = preload("res://scripts/poc/poc_config.gd")
const Coords: GDScript = preload("res://scripts/poc/poc_coords.gd")
const Placement: GDScript = preload("res://scripts/poc/assets/placement.gd")
const Projectiles: GDScript = preload("res://scripts/poc/play/poc_projectiles.gd")
const Day: GDScript = preload("res://scripts/poc/environment/poc_day.gd")
const WallGrowthScript: GDScript = preload("res://scripts/poc/environment/wall_growth.gd")
const HelpersScript: GDScript = preload("res://scripts/poc/helpers/poc_helpers.gd")
const PLAY_SETUP: String = "res://data/poc/play_setup.json"
## POL-01 PoC-side override of SimTuning (tempo): {"sim_tuning": {property: value}}. Missing file = shipped defaults.
static var tempo_path: String = "res://data/poc/tempo.json"

const WIDTH: int = 48
const HEIGHT: int = 40
const TERRAIN_KEYS: Array[String] = ["wasteland", "safe", "shore", "water", "building", "shallows", "paved"]
const T_WASTE: int = 0
const T_SAFE: int = 1
const T_SHORE: int = 2
const T_WATER: int = 3
const T_BUILDING: int = 4
const T_SHALLOWS: int = 5
## POC-05 pavement: a greening target like soil, only the display differs (data/poc/terrain/paved.tres).
const T_PAVED: int = 6
const TERRAIN_DIR_POC: String = "res://data/poc/terrain/"
## Interior wall blocks (cell rects) of the fixture; the outer ring is also building.
const WALLS: Array[Rect2i] = [Rect2i(10, 8, 4, 4), Rect2i(30, 24, 7, 2), Rect2i(20, 30, 2, 6), Rect2i(6, 24, 5, 3)]
const POND: Rect2i = Rect2i(34, 8, 7, 6)
const SAFE_PATCH: Rect2i = Rect2i(18, 12, 8, 6)

## POC-02 placed-object map (data/poc/maps): wall boxes of the bare fixture are replaced by placed GLB objects.
const PLACEMENT_MAP: String = "res://data/poc/maps/fixture_02.json"
const OPEN_POND: Rect2i = Rect2i(39, 3, 6, 5)
const OPEN_SAFE: Rect2i = Rect2i(21, 22, 6, 5)

## POC-04 combat fixture (data/poc): zones, nests, enemy tuning, extra terrain. Opt-in: load_combat().
const COMBAT_SETUP: String = "res://data/poc/combat_setup.json"
## POC-07 playable town: one file holds the map (size, painted terrain, placed objects), zones, nests, seed sources and tuning.
## Load it with load_combat(TOWN_SETUP) on a session created with town_size() cells.
const TOWN_SETUP: String = "res://data/poc/maps/town_01.json"
const ENEMY_TUNING: String = "res://data/enemy_tuning.tres"

var state: WorldState
## Placement (RefCounted) once load_placement() succeeded; null for the bare POC-01 fixture.
var placement: RefCounted
var base_terrain: PackedByteArray = PackedByteArray()
var clock: SimClock = SimClock.new()
var growth: GrowthSim
var spread: SpreadSim
var sim_tuning: SimTuning = SimTuning.new()
## Player feet position in logical px.
var position: Vector2
## Aim target in logical px; valid only while has_aim.
var aim: Vector2 = Vector2.ZERO
var has_aim: bool = false
## Game-time multiplier for fast forward (does not change walking speed).
var multiplier: float = 1.0
## POC-03 play layer: PlayState (seeds, water, HP, sources, pickups, cultivated plants) and the logical shot list.
## Everything advances in advance_game() only, in the order SimClock -> PlayState -> shots.
var play: PlayState
var play_tuning: PlayTuning
var projectiles: RefCounted
## HLP-01 helper seeds / helper plants (RefCounted, scripts/poc/helpers/poc_helpers.gd). Advanced in advance_game() only.
var helpers: RefCounted
## HLP-01 placement mode: index into helpers.kinds, -1 = off (the mode itself is not saved).
var helper_mode: int = -1
var play_setup: Dictionary = {}
## Last result line for the HUD, and a counter so a view can tell a new one arrived.
var last_message: String = ""
var message_serial: int = 0
var message_hold_until: float = -1.0
## The all-supply debug shortcut is OFF by default (the game must be playable without it). Enabled explicitly (HUD shows it).
var debug_refill_enabled: bool = false
var shots_blocked_by_wall: int = 0
## POC-05 environment: tuning (data/poc/environment.json), the day clock derived from clock.elapsed (no own hour state),
## and the wall vegetation growth state (RefCounted; null until a placement is loaded).
var env_tuning: Dictionary = {}
var wall_growth: RefCounted
## Opt-in fixture pavement (cell rects). Empty by default: set before load_placement()/load_combat() (poc_main does, from
## data/poc/environment.json "paving"). Only wasteland cells of the base terrain are repaved.
var paving: Array[Rect2i] = []
## Display cache of the sunlight factor for the current clock.elapsed (the clock stays the only state).
var _sun_cache_elapsed: float = -1.0
var _sun_cache_value: float = 1.0
## POC-04 enemy layer (all null/empty until load_combat()): nests + boars + carcasses, zone transitions, shot->enemy damage,
## far seeding. Driven only by advance_game() (single loop).
var combat_mode: bool = false
var combat_setup: Dictionary = {}
var enemy_tuning: EnemyTuning
var enemies: EnemyField
var zone_progress: ZoneProgress
var combat: EnemyCombat
var far: FarSeedSim
var zone_defs: Array[ZoneDef] = []
## Zone notices in order of occurrence (texts of ZoneHud) and the number of "region cleared" notices.
var zone_log: Array[String] = []
var cleared_notices: int = 0
## Game time (clock.elapsed) at which each zone reached each state: zone_times[zone][state].
var zone_times: Dictionary = {}
var scatter_filtered: int = 0
## Pause lives in the single SimClock; this is just a view of it.
var paused: bool:
	get:
		return clock.paused
	set(value):
		clock.paused = value

## `grid_width` x `grid_height` cells: the POC-01 fixture size by default; the POC-07 town passes its own size (data/poc/maps/town_01.json).
func _init(grid_width: int = WIDTH, grid_height: int = HEIGHT) -> void:
	var defs: Array[TerrainDef] = []
	for key: String in TERRAIN_KEYS:
		defs.append(load((TERRAIN_DIR_POC if key == "paved" else "res://data/terrain/") + key + ".tres") as TerrainDef)
	state = WorldState.new(grid_width, grid_height, defs, 81026)
	for y: int in grid_height:
		for x: int in grid_width:
			var kind: int = T_WASTE
			if SAFE_PATCH.has_point(Vector2i(x, y)):
				kind = T_SAFE
			if POND.grow(1).has_point(Vector2i(x, y)):
				kind = T_SHORE
			if POND.has_point(Vector2i(x, y)):
				kind = T_WATER
			if x == 0 or y == 0 or x == grid_width - 1 or y == grid_height - 1:
				kind = T_BUILDING
			state.terrain[state.index_of(x, y)] = kind
	for rect: Rect2i in WALLS:
		for y: int in range(rect.position.y, rect.end.y):
			for x: int in range(rect.position.x, rect.end.x):
				state.terrain[state.index_of(x, y)] = T_BUILDING
	state.apply_terrain_defs()
	apply_tempo(sim_tuning)
	clock.configure(sim_tuning)
	growth = GrowthSim.new(state, sim_tuning)
	spread = SpreadSim.new(state, sim_tuning)
	clock.growth_ticked.connect(func(_tick: int) -> void: growth.tick())
	clock.spread_ticked.connect(func(_tick: int) -> void: spread.tick())
	position = Coords.cell_center_logic(Vector2i(24, 20))
	env_tuning = Day.load_tuning()
	growth.sunlight_provider = Callable(self, "sunlight_factor")
	_load_setup()
	_build_play("seed_sources_bare")

## Base terrain without any placed object: wasteland, a safe patch, a pond with shore, and the outer ring (building).
static func open_base_terrain() -> PackedByteArray:
	var base: PackedByteArray = PackedByteArray()
	base.resize(WIDTH * HEIGHT)
	for y: int in HEIGHT:
		for x: int in WIDTH:
			var kind: int = T_WASTE
			if OPEN_SAFE.has_point(Vector2i(x, y)):
				kind = T_SAFE
			if OPEN_POND.grow(1).has_point(Vector2i(x, y)):
				kind = T_SHORE
			if OPEN_POND.has_point(Vector2i(x, y)):
				kind = T_WATER
			if x == 0 or y == 0 or x == WIDTH - 1 or y == HEIGHT - 1:
				kind = T_BUILDING
			base[y * WIDTH + x] = kind
	return base

## Wasteland everywhere with only the outer ring as building (POC-07 town; the painted terrain comes from the map data).
static func blank_base_terrain(grid_width: int, grid_height: int) -> PackedByteArray:
	var base: PackedByteArray = PackedByteArray()
	base.resize(grid_width * grid_height)
	for y: int in grid_height:
		for x: int in grid_width:
			var edge: bool = x == 0 or y == 0 or x == grid_width - 1 or y == grid_height - 1
			base[y * grid_width + x] = T_BUILDING if edge else T_WASTE
	return base

## Cell size [w, h] declared by a town map file (data/poc/maps/town_01.json "size"); Vector2i.ZERO when absent / unreadable.
static func town_size(path: String = TOWN_SETUP) -> Vector2i:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary) or not (parsed as Dictionary).has("size"):
		return Vector2i.ZERO
	var size: Array = (parsed as Dictionary)["size"]
	return Vector2i(int(size[0]), int(size[1]))

## Replaces the bare fixture by the placement map: base terrain + obstacle layer from the placed objects.
func load_placement(map_path: String = PLACEMENT_MAP) -> bool:
	var loaded: RefCounted = Placement.new()
	if not loaded.load_map(map_path):
		return false
	base_terrain = open_base_terrain()
	base_terrain = _apply_paving(base_terrain)
	loaded.attach(state, base_terrain)
	placement = loaded
	position = Coords.cell_center_logic(loaded.player_start_cell)
	_build_play("seed_sources_placement")
	_build_wall_growth()
	return true

## Moves the player by `screen_dir` (x right, y down, <= 1) for `delta` seconds with wall collision.
## Returns the actual logical displacement. No movement while paused.
func walk(screen_dir: Vector2, delta: float) -> Vector2:
	if paused or delta <= 0.0 or play.health.downed:
		return Vector2.ZERO
	var ground: Vector2 = Coords.screen_dir_to_ground(screen_dir)
	var step: float = minf(delta, Config.MAX_STEP_S)
	var old: Vector2 = position
	position = Walker.move(state, Config.TILE_PX, position, ground * Config.walk_speed_px() * step, Config.player_half_px())
	return position - old

## Advances game time by `seconds` in <= MAX_STEP_S pieces (independent of how it is split). No-op while paused.
func advance_game(seconds: float) -> void:
	if paused:
		return
	var remaining: float = maxf(seconds, 0.0)
	var piece: float = minf(Config.MAX_STEP_S, clock.max_advance)
	while remaining > 0.000001:
		var step: float = minf(remaining, piece)
		clock.advance(step)
		play.advance(step, position)
		if enemies != null:
			enemies.advance(step)
		helpers.advance(step, position, play.health.downed)
		projectiles.advance(step)
		remaining -= step

## Per-frame advance: real time (capped per call) times the multiplier.
func advance(real_delta: float) -> void:
	advance_game(minf(real_delta, Config.MAX_STEP_S) * multiplier)

func set_aim(logic: Vector2) -> void:
	aim = logic
	has_aim = true

func clear_aim() -> void:
	has_aim = false

func is_walkable_logic(logic: Vector2) -> bool:
	var cell: Vector2i = Coords.logic_to_cell(logic)
	return state.in_bounds(cell.x, cell.y) and state.is_walkable(cell.x, cell.y)

func snapshot() -> Dictionary:
	return {
		"size": [state.width, state.height],
		"position_logic": [position.x, position.y],
		"aim_logic": [aim.x, aim.y] if has_aim else null,
		"paused": paused,
		"multiplier": multiplier,
		"elapsed_game": clock.elapsed,
		"growth_ticks": clock.growth_ticks,
		"spread_ticks": clock.spread_ticks,
		"green": state.greened_count,
		"targets": state.target_count,
		"green_percent": greening_percent(),
		"seeds": play.seeds,
		"water": play.water,
		"hp": play.hp,
		"selected": String(play.selected_def().key),
		"shots": projectiles.shots.size(),
		"pickups": play.pickups.count(),
		"helper_seeds": helpers.seeds,
		"helper_plants": helpers.plants.size(),
	}

func to_dict() -> Dictionary:
	var data: Dictionary = snapshot()
	data["version"] = 1
	data["clock"] = clock.to_dict()
	if wall_growth != null:
		data["wall_growth"] = wall_growth.to_dict()
	return data

## POC-08: shots in flight are not saved. Called at save time on the live session so that it matches what will be restored:
## spent seeds / water of plain shots are refunded and the seeds held back for cultivated shots are released. Returns the count.
func cancel_shots_for_save() -> int:
	var count: int = projectiles.shots.size()
	for shot: Dictionary in projectiles.shots:
		var kind: String = String(shot["kind"])
		if kind == Projectiles.KIND_WATER:
			play.add_water(play_tuning.water_cost_per_shot)
		elif kind == Projectiles.KIND_SEED:
			play.add_seeds(1)
		else:
			play.cancel_plant(StringName(kind))
	projectiles.shots.clear()
	return count

## Break observer cycles when a short-lived session is discarded (tests).
func close() -> void:
	state.tile_listener = Callable()
	for connection: Dictionary in clock.growth_ticked.get_connections():
		clock.growth_ticked.disconnect(connection["callable"])
	for connection: Dictionary in clock.spread_ticked.get_connections():
		clock.spread_ticked.disconnect(connection["callable"])
	play.cultivation.boost_sink = Callable()
	projectiles.blocker = Callable()
	helpers.blocker = Callable()
	projectiles.enemy_hit_provider = Callable()
	spread.allow_hook = Callable()
	growth.sunlight_provider = Callable()
	state.zone_greened_listener = Callable()
	for connection: Dictionary in state.zone_state_changed.get_connections():
		state.zone_state_changed.disconnect(connection["callable"])
	if enemies != null:
		for sig: Signal in [enemies.boar_defeated, enemies.nest_defeated, enemies.enemies_changed]:
			for connection: Dictionary in sig.get_connections():
				sig.disconnect(connection["callable"])
	if zone_progress != null:
		for connection: Dictionary in zone_progress.cleared.get_connections():
			zone_progress.cleared.disconnect(connection["callable"])
	play.enemies = null
	for sig: Signal in [play.health.knocked, play.health.damaged, play.health.downed_started]:
		for connection: Dictionary in sig.get_connections():
			sig.disconnect(connection["callable"])
	for sig: Signal in [projectiles.landed, projectiles.blocked, projectiles.expired, projectiles.enemy_hit, play.health.revived]:
		for connection: Dictionary in sig.get_connections():
			sig.disconnect(connection["callable"])


# ---------------------------------------------------------------- POC-05 environment

## Hour of day (0..24) derived from the one game clock only; there is no separate hour state.
func day_hour() -> float:
	return Day.hour_at(clock.elapsed, env_tuning)

## Sun/moon/ambient state of the current time (see poc_day.gd).
func day_state() -> Dictionary:
	return Day.state(day_hour(), env_tuning)

## GrowthSim.sunlight_provider: a factor >= 1.0 (night exactly 1.0), identical for every tile and independent of moisture.
func sunlight_factor(_index: int = 0) -> float:
	if clock.elapsed != _sun_cache_elapsed:
		_sun_cache_elapsed = clock.elapsed
		_sun_cache_value = Day.sunlight_factor_at(clock.elapsed, env_tuning)
	return _sun_cache_value

## The configured pavement rects from the environment tuning (for poc_main).
static func paving_from(tuning: Dictionary) -> Array[Rect2i]:
	var out: Array[Rect2i] = []
	for rect: Variant in (tuning.get("paving", {}) as Dictionary).get("rects", []):
		out.append(Rect2i(int(rect[0]), int(rect[1]), int(rect[2]), int(rect[3])))
	return out

func _apply_paving(base: PackedByteArray) -> PackedByteArray:
	for rect: Rect2i in paving:
		for y: int in range(rect.position.y, rect.end.y):
			for x: int in range(rect.position.x, rect.end.x):
				if x >= 0 and y >= 0 and x < state.width and y < state.height and base[y * state.width + x] == T_WASTE:
					base[y * state.width + x] = T_PAVED
	return base

func _build_wall_growth() -> void:
	if wall_growth != null:
		for connection: Dictionary in clock.growth_ticked.get_connections():
			if (connection["callable"] as Callable).get_object() == wall_growth:
				clock.growth_ticked.disconnect(connection["callable"])
	wall_growth = WallGrowthScript.new()
	wall_growth.setup(state, placement, env_tuning.get("wall", {}), sim_tuning)
	clock.growth_ticked.connect(wall_growth.on_growth_tick)


## POL-01: applies data/poc/tempo.json over the shipped SimTuning (PoC only; scripts/world and data/ stay untouched). Unknown
## properties are ignored. Returns the number of properties set.
static func apply_tempo(tuning: SimTuning, path: String = tempo_path) -> int:
	if not FileAccess.file_exists(path):
		return 0
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		return 0
	var count: int = 0
	var values: Dictionary = (parsed as Dictionary).get("sim_tuning", {})
	for key: Variant in values:
		if String(key) in tuning:
			tuning.set(String(key), values[key])
			count += 1
	return count

# ---------------------------------------------------------------- POC-04 combat layer

## Replaces the fixture by the combat fixture (data/poc/combat_setup.json): placed objects + painted lake/island, two zones
## (0 = safe patch, stable; 1 = the rest, unconquered, with the nests), EnemyField / ZoneProgress / EnemyCombat / FarSeedSim.
## Setup-time only. Returns false when the data cannot be read or does not fit.
func load_combat(setup_path: String = COMBAT_SETUP) -> bool:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(setup_path))
	if not (parsed is Dictionary):
		return false
	var setup: Dictionary = parsed
	var loaded: RefCounted = Placement.new()
	if not loaded.load_map(String(setup.get("map", PLACEMENT_MAP))):
		return false
	for cell: Variant in setup.get("open_cells", []):
		loaded.reach_seeds.append(Vector2i(int(cell[0]), int(cell[1])))
	var town: bool = setup.has("size")
	if town and Vector2i(state.width, state.height) != town_size(setup_path):
		return false
	base_terrain = blank_base_terrain(state.width, state.height) if town else open_base_terrain()
	for entry: Variant in setup.get("paint", []):
		var rect: Array = entry["rect"]
		var kind: int = TERRAIN_KEYS.find(String(entry["terrain"]))
		if kind < 0:
			return false
		for y: int in range(int(rect[1]), int(rect[1]) + int(rect[3])):
			for x: int in range(int(rect[0]), int(rect[0]) + int(rect[2])):
				base_terrain[y * state.width + x] = kind
	if not town:
		base_terrain = _apply_paving(base_terrain)
	loaded.attach(state, base_terrain)
	placement = loaded
	position = Coords.cell_center_logic(loaded.player_start_cell)
	combat_setup = setup
	_build_play("seed_sources_placement", setup.get("seed_sources", []))
	_build_wall_growth()
	if not _build_zones(setup):
		return false
	_build_enemies(setup)
	combat_mode = true
	return true

func _build_zones(setup: Dictionary) -> bool:
	var entries: Array = setup.get("zones", [])
	if entries.is_empty():
		return false
	var ids: PackedByteArray = PackedByteArray()
	ids.resize(state.tile_count())
	var states: PackedByteArray = PackedByteArray()
	states.resize(entries.size())
	zone_defs.clear()
	var default_id: int = 0
	for entry: Variant in entries:
		if entry["rect"] == null:
			default_id = int(entry["id"])
	ids.fill(default_id)
	for entry: Variant in entries:
		var id: int = int(entry["id"])
		states[id] = int(entry["state"])
		if entry["rect"] != null:
			var rect: Array = entry["rect"]
			for y: int in range(int(rect[1]), int(rect[1]) + int(rect[3])):
				for x: int in range(int(rect[0]), int(rect[0]) + int(rect[2])):
					ids[y * state.width + x] = id
		var def: ZoneDef = ZoneDef.new()
		def.id = id
		def.key = StringName(String(entry["key"]))
		def.display_name = String(entry["name"])
		def.initial_state = int(entry["state"])
		for tile: Variant in entry.get("nest_tiles", []):
			def.nest_tiles.append(Vector2i(int(tile[0]), int(tile[1])))
		zone_defs.append(def)
	return state.set_zones(ids, states)

func _build_enemies(setup: Dictionary) -> void:
	enemy_tuning = (load(ENEMY_TUNING) as EnemyTuning).duplicate() as EnemyTuning
	var overrides: Dictionary = setup.get("enemy_tuning", {})
	for key: String in overrides:
		enemy_tuning.set(key, overrides[key])
	enemies = EnemyField.new(state, enemy_tuning, Config.TILE_PX)
	spread.allow_hook = enemies.spread_allows
	enemies.setup_nests(zone_defs)
	zone_progress = ZoneProgress.new(state, enemies)
	combat = EnemyCombat.new(enemies, play)
	play.enemies = enemies
	projectiles.enemy_hit_provider = combat.hit_provider
	projectiles.enemy_hit.connect(combat.on_enemy_hit)
	far = FarSeedSim.new(state, sim_tuning)
	clock.spread_ticked.connect(func(_tick: int) -> void: far.tick())
	play.health.knocked.connect(_on_knocked)
	play.health.damaged.connect(func(amount: int, _source: Vector2) -> void: say("イノシシに当たった（HP -%d）" % amount))
	play.health.downed_started.connect(func() -> void: say("戦闘不能… 安全地帯へ戻る"))
	play.health.revived.connect(func(_at: Vector2) -> void: say("安全地帯で復帰した"))
	helpers.attach_enemies(enemies)
	zone_progress.start()
	for zone: int in state.zone_count:
		zone_times[zone] = {int(state.zone_state[zone]): 0.0}
	state.zone_state_changed.connect(_on_zone_state_changed)
	zone_progress.cleared.connect(_on_region_cleared)

## A contact hit pushes the player; the walking rules (walls, water) still apply.
func _on_knocked(motion: Vector2) -> void:
	position = Walker.move(state, Config.TILE_PX, position, motion, Config.player_half_px())

func _on_zone_state_changed(zone: int, _old_state: int, new_state: int) -> void:
	if not zone_times.has(zone):
		zone_times[zone] = {}
	(zone_times[zone] as Dictionary)[new_state] = clock.elapsed
	var text: String = ZoneHud.change_text(zone_defs, zone, new_state)
	if not text.is_empty():
		zone_log.append(text)
		say(text, 5.0)

func _on_region_cleared() -> void:
	cleared_notices += 1
	zone_log.append(ZoneHud.CLEARED_TEXT)
	say(ZoneHud.CLEARED_TEXT, 8.0)

## Index of the zone under the player (-1 off the map).
func player_zone() -> int:
	return ZoneHud.zone_at_position(state, Config.TILE_PX, position)

## Boar zone of the combat region: the zone that holds the nests (the first one with nest sites).
func combat_zone() -> int:
	for def: ZoneDef in zone_defs:
		if not def.nest_tiles.is_empty():
			return def.id
	return -1

## Text for the HUD: zone name/state/greening of the combat zone, nests left, boars left.
func combat_status_text() -> String:
	if enemies == null:
		return ""
	var zone: int = combat_zone()
	var text: String = ZoneHud.status_text(state, zone_defs, zone)
	var nest_hp: PackedStringArray = []
	for nest: Nest in enemies.nests:
		nest_hp.append("%d/%d" % [nest.hp, nest.hp_max] if nest.alive else "壊")
	text += "　残巣 %d　残敵 %d　巣HP[%s]" % [enemies.alive_nest_count(zone), enemies.boar_count_in_zone(zone), ",".join(nest_hp)]
	return text


# ---------------------------------------------------------------- POC-03 play layer

func _load_setup() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PLAY_SETUP))
	play_setup = parsed if parsed is Dictionary else {}

## (Re)builds PlayState and the shot list on the current WorldState. Setup-time only: it is called from _init and
## from load_placement (before play starts), never during a run.
func _build_play(sources_key: String, sources_override: Array = []) -> void:
	play_tuning = (load("res://data/play_tuning.tres") as PlayTuning).duplicate() as PlayTuning
	var overrides: Dictionary = play_setup.get("tuning", {})
	for key: String in overrides:
		play_tuning.set(key, overrides[key])
	var source_positions: Array[Vector2] = []
	for entry: Variant in (sources_override if not sources_override.is_empty() else play_setup.get(sources_key, [])):
		source_positions.append(Coords.cell_center_logic(Vector2i(int(entry[0]), int(entry[1]))))
	var defs: Array[PlantDef] = []
	for path: Variant in play_setup.get("plants", []):
		defs.append(load(String(path)) as PlantDef)
	play = PlayState.new(state, play_tuning, sim_tuning, Config.TILE_PX, source_positions, defs)
	play.cultivation.boost_sink = spread.set_speed_scale
	play.health.respawn_position = position
	play.health.revived.connect(func(location: Vector2) -> void: position = location)
	projectiles = Projectiles.new()
	projectiles.setup(play_tuning)
	projectiles.blocker = Callable(self, "shot_blocked")
	projectiles.landed.connect(_on_landed)
	projectiles.blocked.connect(_on_blocked)
	projectiles.expired.connect(func(kind: String, _point: Vector2) -> void: _release(kind))
	projectiles.enemy_hit.connect(func(kind: String, _point: Vector2, _info: Dictionary) -> void: _release(kind))
	helpers = HelpersScript.new(state, play, Config.TILE_PX)
	helpers.notify = Callable(self, "say")
	helpers.blocker = Callable(self, "shot_blocked")
	helper_mode = -1

## Sets the HUD message. A message with `hold_seconds` (zone notices) is not replaced by ordinary messages for that long (game time).
func say(text: String, hold_seconds: float = 0.0) -> void:
	if hold_seconds <= 0.0 and clock.elapsed < message_hold_until:
		return
	message_hold_until = clock.elapsed + hold_seconds if hold_seconds > 0.0 else message_hold_until
	last_message = text
	message_serial += 1

## True when the segment crosses a cell that stops shots (placed walls incl. sealed interiors, the outer ring, off-map).
func shot_blocked(from_logic: Vector2, to_logic: Vector2) -> bool:
	if placement != null:
		return placement.blocks_projectile(from_logic, to_logic)
	var samples: int = maxi(ceili(from_logic.distance_to(to_logic)), 1)
	for i: int in range(0, samples + 1):
		var cell: Vector2i = Coords.logic_to_cell(from_logic.lerp(to_logic, float(i) / float(samples)))
		if not state.in_bounds(cell.x, cell.y) or state.terrain[state.index_of(cell.x, cell.y)] == T_BUILDING:
			return true
	return false

## Greening rate shown to the player: floor of greened / targets (100 only when exactly all targets are greened).
func greening_percent() -> int:
	return state.greening_percent_floor()

## Exact ratio (never rounded for decisions).
func greening_ratio() -> float:
	return 0.0 if state.target_count == 0 else float(state.greened_count) / float(state.target_count)

func selected_label() -> String:
	return play.selected_def().display_name

func cycle_plant(step: int) -> void:
	play.cycle_selection(step)

## Fires the selected seed/plant (water_shot = false) or water (true) toward `aim_logic` (default: current aim).
## Costs are spent only when the shot is really launched. Returns {ok, reason}.
func fire(water_shot: bool, aim_logic: Vector2 = Vector2.INF) -> Dictionary:
	if paused:
		return {"ok": false, "reason": "paused"}
	if play.health.downed:
		return {"ok": false, "reason": "downed"}
	var target: Vector2 = aim_logic
	if target == Vector2.INF:
		if not has_aim:
			return {"ok": false, "reason": "no_aim"}
		target = aim
	if projectiles.is_full():
		return {"ok": false, "reason": "full"}
	var plant: PlantDef = null if water_shot else play.selected_def()
	var cultivated: bool = plant != null and plant.is_cultivated()
	if water_shot:
		if not play.can_fire_water():
			say("水が足りない（水辺で補給）")
			return {"ok": false, "reason": "no_water"}
	elif cultivated:
		if not play.can_fire_plant(plant):
			say("%sは種が足りないか上限" % plant.display_name)
			return {"ok": false, "reason": "no_seed"}
	elif not play.can_fire_seed():
		say("種がない（木の実を拾う）")
		return {"ok": false, "reason": "no_seed"}
	var kind: String = Projectiles.KIND_WATER if water_shot else (String(plant.key) if cultivated else Projectiles.KIND_SEED)
	var landing: Vector2 = projectiles.launch(kind, position, target, Vector2.DOWN)
	if landing == Vector2.INF:
		return {"ok": false, "reason": "full"}
	if water_shot:
		play.spend_water()
	elif cultivated:
		play.reserve_plant(plant)
	else:
		play.spend_seed()
	return {"ok": true, "reason": "", "landing": landing}

func _release(kind: String) -> void:
	if kind != Projectiles.KIND_WATER and kind != Projectiles.KIND_SEED:
		play.cancel_plant(StringName(kind))

func _on_blocked(kind: String, _point: Vector2) -> void:
	shots_blocked_by_wall += 1
	_release(kind)
	say("壁にあたった")

func _on_landed(kind: String, point: Vector2) -> void:
	if kind == Projectiles.KIND_WATER:
		var wet: int = play.land_water(point)
		say("%dマスがうるおった" % wet if wet > 0 else "水は対象外の地面に落ちた")
	elif kind == Projectiles.KIND_SEED:
		var planted: PackedInt32Array = play.land_seed(point)
		# Never plant across a wall: scatter tiles that are not visible from the landing point are undone.
		var kept: PackedInt32Array = PackedInt32Array()
		for index: int in planted:
			var centre: Vector2 = Coords.cell_center_logic(Vector2i(index % state.width, index / state.width))
			if shot_blocked(point, centre):
				state.set_stage(index, WorldState.STAGE_EMPTY)
				scatter_filtered += 1
			else:
				kept.append(index)
		play.last_scatter = kept
		say("%dマスに種をまいた" % kept.size() if kept.size() > 0 else "種は芽にならなかった（対象外の地面）")
	else:
		var plant: CultivatedPlant = play.land_plant(StringName(kind), point)
		say("置いた" if plant != null else "ここには置けない（成熟した地面が必要）")

## E key: describes the cell under `logic` and the pickups near the player (pickups are collected automatically in range).
func inspect(logic: Vector2) -> String:
	var cell: Vector2i = Coords.logic_to_cell(logic)
	if not state.in_bounds(cell.x, cell.y):
		return "範囲外"
	var index: int = state.index_of(cell.x, cell.y)
	var stage_names: Array[String] = ["空き", "種", "芽1", "芽2", "成熟"]
	var def: TerrainDef = state.terrain_def_at(index)
	var text: String = "(%d,%d) %s " % [cell.x, cell.y, String(def.key)]
	if state.target[index] == 1:
		text += "成長:%s 水分:%d" % [stage_names[state.stage[index]], state.moisture[index]]
	else:
		text += "緑化対象外"
	var near: int = 0
	for item: Dictionary in play.pickups.items:
		if Vector2(float(item["x"]), float(item["y"])).distance_to(position) <= play_tuning.pickup_collect_radius_px * 2.0:
			near += 1
	return text + "　近くの拾得物:%d" % near

## Debug shortcut (OFF by default): refills seeds and water. Returns false when not enabled.
func debug_refill() -> bool:
	if not debug_refill_enabled:
		return false
	play.add_seeds(int(play_setup.get("debug_refill_seeds", 20)))
	play.add_water(float(play_setup.get("debug_refill_water", 100.0)))
	helpers.debug_refill()
	say("【デバッグ補給】")
	return true


# ---------------------------------------------------------------- HLP-01 helper plants

func helper_mode_active() -> bool:
	return helper_mode >= 0

## Kind key shown / placed in the current mode: the carried plant's kind while carrying, else the selected kind ("" = mode off).
func helper_active_kind() -> String:
	if helpers.is_carrying():
		return String(helpers.carried["kind"]) if helper_mode >= 0 else ""
	return String(helpers.kinds[helper_mode]["key"]) if helper_mode >= 0 else ""

## Q: off -> first kind -> ... -> last kind -> off. While carrying there is nothing to choose: only on / off.
func cycle_helper_mode() -> void:
	if paused or play.health.downed:
		return
	if helpers.is_carrying():
		helper_mode = -1 if helper_mode >= 0 else helpers.kind_index(String(helpers.carried["kind"]))
	else:
		helper_mode = helper_mode + 1 if helper_mode + 1 < helpers.kinds.size() else -1
	if helper_mode < 0:
		say("設置モード終了")
	else:
		var def: Dictionary = helpers.kind_def(helper_active_kind())
		if helpers.is_carrying():
			say("設置モード：%sを置き直す（左クリック、Qで終了）" % String(def["name"]))
		else:
			say("設置モード：%s（おたすけたね%d個、左クリックで置く、Qで種類切替）" % [String(def["name"]), int(def["cost"])])

## Right click in placement mode: leaves the mode.
func end_helper_mode() -> void:
	if helper_mode >= 0:
		helper_mode = -1
		say("設置モード終了")

## Current placement preview for the HUD / ghost: {kind, origin, ok, code, reason}; empty when the mode is off or there is no aim.
func helper_preview() -> Dictionary:
	if helper_mode < 0 or not has_aim:
		return {}
	var kind: String = helper_active_kind()
	var origin: Vector2i = helpers.origin_for(aim)
	var checked: Dictionary = helpers.evaluate(kind, origin, position)
	checked["kind"] = kind
	checked["origin"] = origin
	return checked

## Left click in placement mode. Returns {ok, code, reason, uid}.
func place_helper(aim_logic: Vector2 = Vector2.INF) -> Dictionary:
	if paused or play.health.downed:
		return {"ok": false, "code": "paused", "reason": "", "uid": 0}
	if helper_mode < 0:
		return {"ok": false, "code": "mode", "reason": "", "uid": 0}
	var target: Vector2 = aim_logic
	if target == Vector2.INF:
		if not has_aim:
			return {"ok": false, "code": "no_aim", "reason": "", "uid": 0}
		target = aim
	var carried_before: bool = helpers.is_carrying()
	var result: Dictionary = helpers.place(helper_active_kind(), target, position)
	if bool(result["ok"]):
		say("%sを%s" % [String(helpers.kind_def(helper_kind_of(int(result["uid"])))["name"]), "置き直した" if carried_before else "設置した"])
	else:
		say(String(result["reason"]))
	return result

func helper_kind_of(uid: int) -> String:
	return String(helpers.plant_by_uid(uid).get("kind", ""))

## E: picks up a helper plant near the player. Returns {ok, code, reason, uid}.
func lift_helper() -> Dictionary:
	if paused or play.health.downed:
		return {"ok": false, "code": "paused", "reason": "", "uid": 0}
	var result: Dictionary = helpers.lift(position)
	if bool(result["ok"]):
		say("%sを持ち上げた（Qで設置モード、左クリックで置き直し）" % String(helpers.kind_def(String(helpers.carried["kind"]))["name"]))
	return result

## HUD text of the helper part.
func helper_status_text() -> String:
	var text: String = "おたすけたね %d/%d　おたすけ植物 %d/%d" % [helpers.seeds, helpers.seeds_max, helpers.total_count(), helpers.max_helpers]
	if helpers.is_carrying():
		text += "　【持ち上げ中：%s HP%d】" % [String(helpers.kind_def(String(helpers.carried["kind"]))["name"]), int(helpers.carried["hp"])]
	for plant: Dictionary in helpers.plants:
		var key: String = String(plant["kind"])
		if key == "gatlinger":
			text += "　ガトリンガー在庫%d/%d" % [int(plant["stock"]), int(helpers.stock_max_of(key))]
		elif key == "sprinkler":
			text += "　スプリンクラー%s" % ("水辺（補給不要）" if helpers.is_by_water(plant) else "水%d/%d" % [int(plant["stock"]), int(helpers.stock_max_of(key))])
	if helper_mode >= 0:
		var def: Dictionary = helpers.kind_def(helper_active_kind())
		text += "　【設置モード：%s%s】" % [String(def["name"]), "" if helpers.is_carrying() else "（%d個）" % int(def["cost"])]
	return text
