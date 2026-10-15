extends SceneTree
## P2-06 controlled front-speed measurement of the carrot (natural spread front with and without carrots).
## Run: Godot --headless --path <project> --script res://tests/p2/p2_06_front.gd -- [--minutes=10] [--mult=3] [--radius=20] [--cost=3] [--interval=20] [--out=path]
## A 240 x 60 open field with a 20 x 20 mature block at the west end. Growth + spread only (the shipped SimTuning), carrots placed with the
## real Cultivation rules. Arms: none / one carrot at the east edge / a chain (a carrot every `interval` seconds on the mature block
## nearest to the east front, at most `chain_max`). Reported: the east front (largest mature x), and the greened count.
const TILE: int = 4
const REGION_PATH: String = "res://data/region_01.tres"

func _initialize() -> void:
	run.call_deferred()

func c8(color: Color) -> Vector3i:
	return Vector3i(roundi(color.r * 255.0), roundi(color.g * 255.0), roundi(color.b * 255.0))

func make_world(region_def: RegionDef, width: int, height: int) -> WorldState:
	var def: RegionDef = RegionDef.new()
	def.width_tiles = width
	def.height_tiles = height
	def.terrains = region_def.terrains
	def.sprout_seed = region_def.sprout_seed
	var image: Image = Image.create(width, height, false, Image.FORMAT_RGB8)
	var waste: Vector3i = Vector3i.ZERO
	for t: TerrainDef in region_def.terrains:
		if t.key == &"wasteland":
			waste = c8(t.map_color)
	for y: int in height:
		for x: int in width:
			image.set_pixel(x, y, Color8(waste.x, waste.y, waste.z))
	return RegionLoader.build_state(def, image)

func front_x(world: WorldState) -> int:
	var best: int = 0
	for index: int in world.tile_count():
		if world.stage[index] == WorldState.STAGE_MATURE:
			best = maxi(best, index % world.width)
	return best

func run_arm(region_def: RegionDef, plant_defs: Array[PlantDef], sim_tuning: SimTuning, play_tuning: PlayTuning, minutes: float, arm: String, interval: float, chain_max: int) -> Dictionary:
	var world: WorldState = make_world(region_def, 240, 60)
	world.debug_fill_stage(Rect2i(10, 20, 20, 20), WorldState.STAGE_MATURE)
	var growth: GrowthSim = GrowthSim.new(world, sim_tuning)
	var spread: SpreadSim = SpreadSim.new(world, sim_tuning)
	var clock: SimClock = SimClock.new()
	clock.configure(sim_tuning)
	clock.growth_ticked.connect(func(_i: int) -> void: growth.tick())
	clock.spread_ticked.connect(func(_i: int) -> void: spread.tick())
	var play: PlayState = PlayState.new(world, play_tuning, sim_tuning, TILE, [], plant_defs)
	play.cultivation.boost_sink = spread.set_speed_scale
	var greened_start: int = world.greened_count
	var placed: int = 0
	var next_place: float = 0.0
	var t: float = 0.0
	var dt: float = 0.25
	while t < minutes * 60.0:
		t += dt
		clock.advance(dt)
		play.cultivation.advance(dt, play.pickups)
		if arm != "none" and t >= next_place and placed < (1 if arm == "one" else chain_max):
			# The mature 2x2 block nearest to the east front (rows 28..32 tried), as a player aiming at the edge of the green.
			var fx: int = front_x(world)
			var done: bool = false
			for back: int in range(2, 12):
				for row: int in [30, 27, 33, 24, 36]:
					var plant: CultivatedPlant = play.cultivation.try_place(&"carrot", Vector2((fx - back) * TILE + 2, row * TILE + 2))
					if plant != null:
						placed += 1
						done = true
						break
				if done:
					break
			next_place = t + interval
	return {"arm": arm, "front_x": front_x(world), "front_gain": front_x(world) - 29, "greened_gain": world.greened_count - greened_start, "greened": world.greened_count, "carrots": placed}

func run() -> void:
	var minutes: float = 10.0
	var mult: float = -1.0
	var radius: float = -1.0
	var cost: int = -1
	var interval: float = 20.0
	var chain_max: int = 32
	var out: String = ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--minutes="):
			minutes = float(argument.trim_prefix("--minutes="))
		elif argument.begins_with("--mult="):
			mult = float(argument.trim_prefix("--mult="))
		elif argument.begins_with("--radius="):
			radius = float(argument.trim_prefix("--radius="))
		elif argument.begins_with("--cost="):
			cost = int(argument.trim_prefix("--cost="))
		elif argument.begins_with("--interval="):
			interval = float(argument.trim_prefix("--interval="))
		elif argument.begins_with("--chain-max="):
			chain_max = int(argument.trim_prefix("--chain-max="))
		elif argument.begins_with("--out="):
			out = argument.trim_prefix("--out=")
	var region_def: RegionDef = load(REGION_PATH) as RegionDef
	var sim_tuning: SimTuning = load("res://data/sim_tuning.tres") as SimTuning
	var play_tuning: PlayTuning = (load("res://data/play_tuning.tres") as PlayTuning).duplicate() as PlayTuning
	play_tuning.seed_start = 1000
	play_tuning.seed_max = 1000
	var plant_defs: Array[PlantDef] = []
	for def: PlantDef in region_def.plants:
		var copy: PlantDef = def.duplicate() as PlantDef
		if copy.key == &"carrot":
			copy.effect_multiplier = mult if mult > 0.0 else copy.effect_multiplier
			copy.effect_radius_tiles = radius if radius > 0.0 else copy.effect_radius_tiles
			copy.seed_cost = cost if cost > 0 else copy.seed_cost
		plant_defs.append(copy)
	var carrot: PlantDef = plant_defs[1]
	var results: Dictionary = {"minutes": minutes, "mult": carrot.effect_multiplier, "radius": carrot.effect_radius_tiles, "cost": carrot.seed_cost, "interval": interval, "arms": []}
	var base_gain: float = 0.0
	var base_green: float = 0.0
	for arm: String in ["none", "one", "chain"]:
		var r: Dictionary = run_arm(region_def, plant_defs, sim_tuning, play_tuning, minutes, arm, interval, chain_max)
		if arm == "none":
			base_gain = maxf(float(r["front_gain"]), 1.0)
			base_green = maxf(float(r["greened_gain"]), 1.0)
		r["front_ratio"] = snappedf(float(r["front_gain"]) / base_gain, 0.001)
		r["area_ratio"] = snappedf(float(r["greened_gain"]) / base_green, 0.001)
		results["arms"].append(r)
	print("FRONT_RESULT " + JSON.stringify(results))
	if out != "":
		var file: FileAccess = FileAccess.open(out, FileAccess.WRITE)
		file.store_string(JSON.stringify(results, "  "))
		file.close()
	quit(0)
