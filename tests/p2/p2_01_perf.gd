extends SceneTree
## P2-01 frame cost of the enemy logic (headless, no GPU; the real-window cost is measured by p2_01_gpu.gd).
## Worst case allowed by the limits: all 15 nests, 40 boars (the global limit) busy chasing plants that are refilled
## around every nest, measured per 1/60 s frame (one fixed enemy step per frame).
##   A  enemies alone
##   B  everything of the game logic together: PlayState.advance + SimClock (growth tick, spread tick) + EnemyField +
##      RegionView.flush, with the P1-06 stress scene on top (40,000 wet seeds, 40,000 mature tiles with an open rim)
## Run: Godot --headless --path <project> --script res://tests/p2/p2_01_perf.gd

const TILE: int = 4

func _initialize() -> void:
	run.call_deferred()

func percentile(values: PackedFloat64Array, q: float) -> float:
	var sorted: PackedFloat64Array = values.duplicate()
	sorted.sort()
	return sorted[clampi(int(float(sorted.size() - 1) * q), 0, sorted.size() - 1)]

## Refills the plants around nest `which` (all nests when -1). Staggered refills avoid a single huge repaint burst that the
## test harness, not the game, would cause.
func feed(world: WorldState, field: EnemyField, which: int = -1) -> void:
	for k: int in field.nests.size():
		if which >= 0 and k != which:
			continue
		var nest: Nest = field.nests[k]
		for y: int in range(maxi(nest.tile.y - 14, 0), mini(nest.tile.y + 18, world.height)):
			for x: int in range(maxi(nest.tile.x - 14, 0), mini(nest.tile.x + 18, world.width)):
				var index: int = world.index_of(x, y)
				if world.occupant[index] == 0 and world.stage[index] == WorldState.STAGE_EMPTY:
					world.set_stage(index, WorldState.STAGE_MATURE)

func summary(name: String, costs: PackedFloat64Array) -> Dictionary:
	var mean: float = 0.0
	var over: int = 0
	for c: float in costs:
		mean += c
		over += 1 if c >= 16.0 else 0
	mean /= costs.size()
	var result: Dictionary = {"name": name, "frames": costs.size(), "mean_ms": mean, "p50_ms": percentile(costs, 0.5), "p99_ms": percentile(costs, 0.99), "p999_ms": percentile(costs, 0.999), "max_ms": percentile(costs, 1.0), "frames_ge_16ms": over}
	print("PERF %s: %d frames, mean %.3f ms, p50 %.3f, p99 %.3f, p99.9 %.3f, max %.3f ms; frames >= 16 ms: %d" % [name, costs.size(), mean, result["p50_ms"], result["p99_ms"], result["p999_ms"], result["max_ms"], over])
	return result

func run() -> void:
	var region_def: RegionDef = load("res://data/region_01.tres") as RegionDef
	var sim_tuning: SimTuning = load("res://data/sim_tuning.tres") as SimTuning
	var play_tuning: PlayTuning = load("res://data/play_tuning.tres") as PlayTuning
	var enemy_tuning: EnemyTuning = load("res://data/enemy_tuning.tres") as EnemyTuning
	var dt: float = 1.0 / 60.0
	var report: Dictionary = {}
	# ---- A: enemies alone ----
	var world: WorldState = RegionLoader.load_region(region_def)
	var field: EnemyField = EnemyField.new(world, enemy_tuning, TILE)
	field.setup_nests(region_def.zones)
	feed(world, field)
	var costs: PackedFloat64Array = PackedFloat64Array()
	var max_boars: int = 0
	for i: int in range(1, 60 * 600 + 1):
		var t0: int = Time.get_ticks_usec()
		field.advance(dt)
		costs.append(float(Time.get_ticks_usec() - t0) / 1000.0)
		max_boars = maxi(max_boars, field.boars.size())
		if i % 300 == 0:
			feed(world, field)
	report["A"] = summary("A enemies alone (15 nests, up to 40 boars, 10 min game time)", costs)
	report["A"]["max_boars"] = max_boars
	report["A"]["tiles_gnawed"] = field.total_gnawed
	# ---- B: whole game logic ----
	var world2: WorldState = RegionLoader.load_region(region_def)
	var field2: EnemyField = EnemyField.new(world2, enemy_tuning, TILE)
	field2.setup_nests(region_def.zones)
	var clock: SimClock = SimClock.new()
	clock.configure(sim_tuning)
	var growth: GrowthSim = GrowthSim.new(world2, sim_tuning)
	var spread: SpreadSim = SpreadSim.new(world2, sim_tuning)
	spread.allow_hook = field2.spread_allows
	clock.growth_ticked.connect(func(_i: int) -> void: growth.tick())
	clock.spread_ticked.connect(func(_i: int) -> void: spread.tick())
	var sources: Array[Vector2] = []
	for tile: Vector2i in region_def.seed_source_tiles:
		sources.append((Vector2(tile) + Vector2(0.5, 0.5)) * region_def.tile_px)
	var defs: Array[PlantDef] = []
	defs.assign(region_def.plants)
	var play: PlayState = PlayState.new(world2, play_tuning, sim_tuning, region_def.tile_px, sources, defs)
	var view: RegionView = RegionView.new()
	view.setup(world2, sim_tuning)
	world2.debug_fill_stage(Rect2i(20, 250, 200, 200), WorldState.STAGE_MATURE)
	for y: int in range(40, 240):
		for x: int in range(20, 220):
			var index: int = world2.index_of(x, y)
			if world2.occupant[index] == 0 and world2.set_stage(index, WorldState.STAGE_SEED):
				world2.set_moisture(index, 100)
	feed(world2, field2)
	var player_pos: Vector2 = Vector2(120 * 4, 240 * 4)
	var costs2: PackedFloat64Array = PackedFloat64Array()
	var enemy_costs: PackedFloat64Array = PackedFloat64Array()
	var max_boars2: int = 0
	var slow: Array[Dictionary] = []
	for i: int in range(1, 60 * 300 + 1):
		var t0: int = Time.get_ticks_usec()
		play.advance(dt, player_pos)
		clock.advance(dt)
		var t1: int = Time.get_ticks_usec()
		field2.advance(dt)
		var t2: int = Time.get_ticks_usec()
		view.flush(sim_tuning.render_tiles_per_frame)
		var t3: int = Time.get_ticks_usec()
		costs2.append(float(t3 - t0) / 1000.0)
		enemy_costs.append(float(t2 - t1) / 1000.0)
		max_boars2 = maxi(max_boars2, field2.boars.size())
		if i % 30 == 0:
			feed(world2, field2, (i / 30) % field2.nests.size())
		if costs2[costs2.size() - 1] >= 8.0:
			slow.append({"frame": i, "total_ms": snappedf(costs2[costs2.size() - 1], 0.01), "play_clock_ms": snappedf(float(t1 - t0) / 1000.0, 0.01), "enemy_ms": snappedf(float(t2 - t1) / 1000.0, 0.01), "flush_ms": snappedf(float(t3 - t2) / 1000.0, 0.01), "dirty": world2.dirty_tiles.size(), "spread_examined": spread.last_examined, "spread_events": spread.last_events})
	report["B"] = summary("B whole logic (play + clock + enemies + view flush) on the stress scene, 5 min game time", costs2)
	report["B"]["max_boars"] = max_boars2
	report["B"]["tiles_gnawed"] = field2.total_gnawed
	report["B"]["enemy_part"] = summary("B enemy part only", enemy_costs)
	report["B"]["frames_ge_8ms"] = slow.slice(0, 40)
	report["B"]["active_tiles_at_end"] = world2.active_tiles.size()
	report["B"]["counters_consistent"] = world2.counters_consistent()
	var file: FileAccess = FileAccess.open(ProjectSettings.globalize_path("res://evidence/p2/p2-01/perf_logic.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	var worst: float = maxf(float(report["A"]["max_ms"]), float(report["B"]["max_ms"]))
	print("P2_01_PERF_RESULT worst_ms=%.3f frames_ge_16ms=%d counters_consistent=%s" % [worst, int(report["A"]["frames_ge_16ms"]) + int(report["B"]["frames_ge_16ms"]), report["B"]["counters_consistent"]])
	quit(1 if worst >= 16.0 or not report["B"]["counters_consistent"] else 0)
