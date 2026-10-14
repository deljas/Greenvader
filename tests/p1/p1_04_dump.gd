extends SceneTree
## P1-04 headless image dump (no GPU window): RegionView's own pixels (Image, same _render_tile code) of the spread
## front on region_01, enlarged 8x with nearest-neighbour. Shows every stage side by side.
## Run: Godot --headless --path <project> --script res://tests/p1/p1_04_dump.gd
## Saves evidence/p1/p1-04/front_t*.png and prints the stage counts per sample time.

const OUT: String = "res://evidence/p1/p1-04/"

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var region_def: RegionDef = load("res://data/region_01.tres") as RegionDef
	var tuning: SimTuning = load("res://data/sim_tuning.tres") as SimTuning
	var state: WorldState = RegionLoader.load_region(region_def)
	var wasteland: int = 0
	for def: TerrainDef in state.terrain_defs:
		if def.key == &"wasteland":
			wasteland = def.id
	var block: Vector2i = Vector2i(-1, -1)
	for cx: int in range(120, 150, 6):
		for cy: int in range(40, 470, 6):
			var ok: bool = true
			for y: int in range(cy - 22, cy + 22):
				for x: int in range(cx - 22, cx + 22):
					if state.terrain[state.index_of(x, y)] != wasteland or state.stage[state.index_of(x, y)] != 0:
						ok = false
						break
				if not ok:
					break
			if ok and block.x < 0:
				block = Vector2i(cx, cy)
	print("block %s" % block)
	state.debug_fill_stage(Rect2i(block.x - 22, block.y - 22, 5, 44), WorldState.STAGE_MATURE)
	var view: RegionView = RegionView.new()
	view.setup(state, tuning)
	var clock: SimClock = SimClock.new()
	clock.configure(tuning)
	var growth: GrowthSim = GrowthSim.new(state, tuning)
	var spread: SpreadSim = SpreadSim.new(state, tuning)
	clock.growth_ticked.connect(func(_i: int) -> void: growth.tick())
	clock.spread_ticked.connect(func(_i: int) -> void: spread.tick())
	var best_t: int = -1
	var best_score: int = -1
	var best_counts: Array[int] = []
	for second: int in range(1, 241):
		for i: int in 4:
			clock.advance(0.25)
		var counts: Array[int] = [0, 0, 0, 0, 0]
		for y: int in range(block.y - 22, block.y + 22):
			for x: int in range(block.x - 22, block.x + 22):
				counts[state.stage[state.index_of(x, y)]] += 1
		var score: int = mini(counts[1], mini(counts[2], counts[3]))
		if score > best_score and second >= 40:
			best_score = score
			best_t = second
			best_counts = counts
		if second == 100 or second == 120:
			print("t=%d counts(empty,seed,s1,s2,mature)=%s" % [second, counts])
	print("best t=%d counts=%s" % [best_t, best_counts])
	# Replay to the best time and dump.
	var state2: WorldState = RegionLoader.load_region(region_def)
	state2.debug_fill_stage(Rect2i(block.x - 22, block.y - 22, 5, 44), WorldState.STAGE_MATURE)
	var view2: RegionView = RegionView.new()
	view2.setup(state2, tuning)
	var clock2: SimClock = SimClock.new()
	clock2.configure(tuning)
	var growth2: GrowthSim = GrowthSim.new(state2, tuning)
	var spread2: SpreadSim = SpreadSim.new(state2, tuning)
	clock2.growth_ticked.connect(func(_i: int) -> void: growth2.tick())
	clock2.spread_ticked.connect(func(_i: int) -> void: spread2.tick())
	for second: int in best_t:
		for i: int in 4:
			clock2.advance(0.25)
	view2.flush()
	var tiles: Rect2i = Rect2i(block.x - 24, block.y - 9, 44, 18)
	var image: Image = Image.create(tiles.size.x * 4, tiles.size.y * 4, false, Image.FORMAT_RGBA8)
	for y: int in tiles.size.y:
		for x: int in tiles.size.x:
			var tx: int = tiles.position.x + x
			var ty: int = tiles.position.y + y
			var source: Image = view2.block_images[view2.block_of_tile(tx, ty)]
			image.blit_rect(source, Rect2i((tx % 64) * 4, (ty % 64) * 4, 4, 4), Vector2i(x * 4, y * 4))
	image.resize(image.get_width() * 8, image.get_height() * 8, Image.INTERPOLATE_NEAREST)
	image.save_png(ProjectSettings.globalize_path(OUT + "front_t%d_x8.png" % best_t))
	print("saved front_t%d_x8.png %s" % [best_t, image.get_size()])
	view.free()
	view2.free()
	quit()
