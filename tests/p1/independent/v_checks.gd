extends SceneTree
## Independent verifier for P1-01 (headless, logic + pixel oracle). Written by the verifier, not the implementer.
## Run: Godot --headless --path <project> --script res://tests/p1/independent/v_checks.gd
## Expectations come from the spec (AUTO-001 / P1_01) and from tests/p1/independent/count_png_gdi.ps1 output
## (evidence/p1/p1-01/independent/png_counts_gdi.json, made with .NET System.Drawing), not from the implementation formulas.

const OUT: String = "res://evidence/p1/p1-01/independent/"
const GDI: String = "res://evidence/p1/p1-01/independent/png_counts_gdi.json"
# Legend colours as written in the spec/data: target terrains are wasteland, safe and shore.
const TARGET_HEX: Array[String] = ["b0a060", "60b060", "e0d090"]

var results: Array[Dictionary] = []

func _initialize() -> void:
	run.call_deferred()

func rec(id: String, cond: String, ok: bool, observed: String) -> void:
	results.append({"id": id, "condition": cond, "status": "PASS" if ok else "FAIL", "observed": observed})
	print("%s [%s] %s :: %s" % ["PASS" if ok else "FAIL", id, cond, observed])

func ms() -> float:
	return Time.get_ticks_usec() / 1000.0

func hex_of(c: Color) -> String:
	return "%02x%02x%02x" % [roundi(c.r * 255.0), roundi(c.g * 255.0), roundi(c.b * 255.0)]

func run() -> void:
	await t1_region()
	t2_greening()
	t3_clock()
	await t3_pause_real_scene()
	await t3_scene_rates()
	t4_render()
	await t5_regression()
	t7_perf()
	var f: FileAccess = FileAccess.open(OUT + "checks_headless.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(results, "  "))
	f.close()
	var fails: int = 0
	for r: Dictionary in results:
		if r["status"] != "PASS":
			fails += 1
	print("V_RESULT total=%d fails=%d" % [results.size(), fails])
	quit(1 if fails > 0 else 0)

# ---------------------------------------------------------------------------------------------
func t1_region() -> void:
	var def: RegionDef = load("res://data/region_01.tres") as RegionDef
	var raw: Image = Image.load_from_file("res://data/region_01.png")
	rec("1.size", "map PNG is 512x512, 1 tile = 4px -> 2048px", raw.get_width() == 512 and raw.get_height() == 512 and def.tile_px == 4, "png=%s tile_px=%d" % [raw.get_size(), def.tile_px])
	var gdi: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(GDI))
	var target_expected: int = 0
	for h: String in TARGET_HEX:
		target_expected += int(gdi["counts"][h])
	var world: WorldState = RegionLoader.load_region(def)
	rec("1.target_count", "target count equals independent System.Drawing count of target legend colours", world.target_count == target_expected and target_expected == 244846, "world=%d gdi=%d" % [world.target_count, target_expected])
	# Per-terrain counts
	var per: Dictionary = {}
	for i: int in world.tile_count():
		var k: String = hex_of(def.terrains[world.terrain[i]].map_color)
		per[k] = int(per.get(k, 0)) + 1
	var same: bool = true
	for k: String in gdi["counts"]:
		if int(gdi["counts"][k]) != int(per.get(k, -1)):
			same = false
	rec("1.terrain_counts", "per-terrain tile counts equal independent count for all 5 legend colours", same, str(per))
	# Target definition depends only on the legend: flip building to target in a copied legend -> count changes by building count.
	var defs2: Array[TerrainDef] = []
	for t: TerrainDef in def.terrains:
		var c: TerrainDef = t.duplicate() as TerrainDef
		if c.key == &"building":
			c.is_target = true
			c.plantable = true
		defs2.append(c)
	var def2: RegionDef = RegionDef.new()
	def2.terrains = defs2
	def2.width_tiles = 512
	def2.height_tiles = 512
	var w2: WorldState = RegionLoader.build_state(def2, raw)
	rec("1.legend_only", "changing only the legend (building -> target) changes targets by exactly the building count; no scenery involved", w2 != null and w2.target_count == target_expected + int(gdi["counts"]["808080"]), "targets=%d (expected %d)" % [w2.target_count, target_expected + int(gdi["counts"]["808080"])])
	# Code reading evidence is separate (grep). Check that world/ scripts and data do not reference LandscapeProp/Art.
	var bad: Array[String] = []
	for dir: String in ["res://scripts/world", "res://data"]:
		for fname: String in DirAccess.get_files_at(dir):
			if fname.ends_with(".gd"):
				var txt: String = FileAccess.get_file_as_string(dir + "/" + fname)
				for needle: String in ["LandscapeProp", "LandscapeArt", "scenery", "PixelArt"]:
					if txt.contains(needle) and not (fname == "terrain_def.gd"):
						bad.append(fname + ":" + needle)
	rec("1.no_props", "no P0 decoration class referenced from scripts/world or data/*.gd", bad.is_empty(), str(bad))
	# Map loading survives deletion of the raw source: imported texture path works without raw file access.
	var import_file: String = FileAccess.get_file_as_string("res://data/region_01.png.import")
	var tex: Texture2D = load("res://data/region_01.png") as Texture2D
	var img_tex: Image = tex.get_image() if tex != null else null
	var lossless: bool = import_file.contains("compress/mode=0") and import_file.contains('"vram_texture": false')
	var a: Image = img_tex.duplicate()
	a.convert(Image.FORMAT_RGBA8)
	var b: Image = raw.duplicate()
	b.convert(Image.FORMAT_RGBA8)
	rec("1.export_safe", "loader uses imported lossless CompressedTexture2D (works in exported build); pixels equal the raw PNG", tex != null and lossless and a.get_data() == b.get_data() and tex.get_class() == "CompressedTexture2D", "class=%s lossless_import=%s equal=%s" % [tex.get_class(), lossless, a.get_data() == b.get_data()])
	# Wrong colour / alpha is rejected, not silently mapped.
	var bad_img: Image = raw.duplicate()
	bad_img.set_pixel(5, 5, Color8(1, 2, 3))
	var rejected: bool = RegionLoader.build_state(def, bad_img) == null
	rec("1.reject_unknown", "unknown legend colour is rejected (ERROR line expected above)", rejected, str(rejected))

# ---------------------------------------------------------------------------------------------
func t2_greening() -> void:
	var def: RegionDef = load("res://data/region_01.tres") as RegionDef
	var world: WorldState = RegionLoader.load_region(def)
	# Independent shadow model built from raw PNG + hex legend.
	var raw: Image = Image.load_from_file("res://data/region_01.png")
	var is_t: PackedByteArray = PackedByteArray()
	is_t.resize(512 * 512)
	var tcount: int = 0
	for y: int in 512:
		for x: int in 512:
			var c: Color = raw.get_pixel(x, y)
			if hex_of(c) in TARGET_HEX:
				is_t[y * 512 + x] = 1
				tcount += 1
	rec("2.denominator", "denominator = target tiles only (water/buildings excluded)", world.target_count == tcount and tcount < 512 * 512, "world=%d shadow=%d" % [world.target_count, tcount])
	var shadow: PackedByteArray = PackedByteArray()
	shadow.resize(512 * 512)
	for i: int in 512 * 512:
		if is_t[i] == 1 and hex_of(def.terrains[world.terrain[i]].map_color) == "60b060":
			shadow[i] = 4
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 424242
	var mismatch: int = 0
	for step: int in 200000:
		var i: int = rng.randi_range(0, 512 * 512 - 1)
		var s: int = rng.randi_range(0, 4)
		world.set_stage(i, s)
		if is_t[i] == 1:
			shadow[i] = s
		if step % 25000 == 24999:
			var g: int = 0
			for j: int in 512 * 512:
				if is_t[j] == 1 and shadow[j] >= 2:
					g += 1
			if g != world.greened_count or not world.counters_consistent():
				mismatch += 1
	var g2: int = 0
	for j: int in 512 * 512:
		if is_t[j] == 1 and shadow[j] >= 2:
			g2 += 1
	rec("2.diff_counter", "after 200000 random set_stage (incl. non-target) the differential counter equals my own recount (8 checkpoints)", mismatch == 0 and g2 == world.greened_count, "greened=%d shadow=%d mismatching_checkpoints=%d" % [world.greened_count, g2, mismatch])
	# seed-only not counted; sprout1 counted
	var fresh: WorldState = RegionLoader.load_region(def)
	var base: int = fresh.greened_count
	var some: int = -1
	for i: int in 512 * 512:
		if is_t[i] == 1 and fresh.stage[i] == 0:
			some = i
			break
	fresh.set_stage(some, 1)
	var seed_only: bool = fresh.greened_count == base
	fresh.set_stage(some, 2)
	var sprout: bool = fresh.greened_count == base + 1
	fresh.set_stage(some, 1)
	var back: bool = fresh.greened_count == base
	rec("2.seed_vs_sprout", "seed does not count; sprout1 counts; back to seed uncounts", seed_only and sprout and back, "%s %s %s" % [seed_only, sprout, back])
	# Water/building refuse
	var water_i: int = -1
	for i: int in 512 * 512:
		if is_t[i] == 0:
			water_i = i
			break
	var before: int = fresh.greened_count
	var acc: bool = fresh.set_stage(water_i, 4)
	rec("2.nontarget_refused", "set_stage on a non-target tile is refused and does not change the count", not acc and fresh.greened_count == before and fresh.stage[water_i] == 0, "accepted=%s" % acc)
	# 100% integer: all targets mature -> full; one short -> not full though display float may round
	for i: int in 512 * 512:
		if is_t[i] == 1:
			fresh.set_stage(i, 4)
	var full: bool = fresh.is_fully_greened() and fresh.greened_count == 244846 and fresh.greening_percent_floor() == 100
	var pick: int = -1
	for i: int in range(512 * 512 - 1, -1, -1):
		if is_t[i] == 1:
			pick = i
			break
	fresh.set_stage(pick, 1)
	var one_short: bool = not fresh.is_fully_greened() and fresh.greened_count == 244845 and fresh.greening_percent_floor() == 99
	rec("2.integer_100", "all 244846 targets mature = full; one tile short is not full (float ratio %.7f)" % (244845.0 / 244846.0), full and one_short, "full=%s short: greened=%d full=%s floor=%d" % [full, fresh.greened_count, fresh.is_fully_greened(), fresh.greening_percent_floor()])
	# Empty-target map never 100.
	var empty: WorldState = WorldState.new(2, 2, def.terrains, 1)
	for i: int in 4:
		empty.terrain[i] = 3
	empty.apply_terrain_defs()
	rec("2.zero_targets", "map without targets is never 100%", not empty.is_fully_greened() and empty.target_count == 0, "")

# ---------------------------------------------------------------------------------------------
func t3_clock() -> void:
	var tuning: SimTuning = load("res://data/sim_tuning.tres") as SimTuning
	rec("3.periods", "growth 0.5 s, spread 1.0 s", tuning.growth_tick_seconds == 0.5 and tuning.spread_tick_seconds == 1.0, "%s %s" % [tuning.growth_tick_seconds, tuning.spread_tick_seconds])
	var all_ok: bool = true
	var detail: Array[String] = []
	for seconds: float in [0.5, 1.0, 2.5, 10.0, 60.0, 600.0]:
		var rows: Array[String] = []
		for rate: int in [24, 30, 60, 75, 120, 144, 240]:
			var clock: SimClock = SimClock.new()
			clock.configure(tuning)
			var steps: int = roundi(seconds * rate)
			var dt: float = 1.0 / rate
			for i: int in steps:
				clock.advance(dt)
			var want_g: int = int(seconds / 0.5 + 1.0e-6)
			var want_s: int = int(seconds / 1.0 + 1.0e-6)
			# Use the actual simulated duration (steps*dt) for a rate whose step does not divide the span.
			var actual: float = steps * dt
			var fits: bool = absf(actual - seconds) < 1.0e-9
			if fits and (clock.growth_ticks != want_g or clock.spread_ticks != want_s):
				all_ok = false
			rows.append("%d:%d/%d" % [rate, clock.growth_ticks, clock.spread_ticks])
		detail.append("%.1fs[%s]" % [seconds, " ".join(rows)])
	rec("3.rate_independent", "same game time gives the same growth/spread tick counts at 24..240 Hz", all_ok, "; ".join(detail))
	# irregular with sums
	var tot: float = 0.0
	var c: SimClock = SimClock.new()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 3
	while tot < 200.0:
		tot += c.advance(rng.randf_range(0.0005, 0.24))
	rec("3.irregular", "irregular frame times: ticks = floor(game time / period)", c.growth_ticks == int(c.elapsed / 0.5 + 1.0e-6) and c.spread_ticks == int(c.elapsed + 1.0e-6), "t=%.3f g=%d s=%d" % [c.elapsed, c.growth_ticks, c.spread_ticks])

func key_event(code: Key, pressed: bool) -> InputEventKey:
	var e: InputEventKey = InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = pressed
	return e

func t3_scene_rates() -> void:
	var lines: Array[String] = []
	var ok: bool = true
	for rate: int in [30, 60, 120]:
		Engine.physics_ticks_per_second = rate
		var main: Node = load("res://scenes/main.tscn").instantiate()
		root.add_child(main)
		var sim: SimulationDriver = main.simulation
		var guard: int = 0
		while sim.clock.elapsed < 5.0 and guard < 5000:
			await physics_frame
			guard += 1
		lines.append("%dHz: elapsed=%.4f growth=%d spread=%d" % [rate, sim.clock.elapsed, sim.clock.growth_ticks, sim.clock.spread_ticks])
		ok = ok and sim.clock.growth_ticks == 10 and sim.clock.spread_ticks == 5
		main.queue_free()
		await process_frame
	Engine.physics_ticks_per_second = 60
	rec("3.scene_rates", "real main.tscn at physics 30/60/120 Hz: when 5.0 s of game time has passed there are exactly 10 growth / 5 spread ticks", ok, " | ".join(lines))

func t3_pause_real_scene() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i: int in 60:
		await physics_frame
	var sim: SimulationDriver = main.simulation
	var running_ticks: int = sim.clock.growth_ticks
	rec("3.scene_runs", "main.tscn: simulation clock advances while running (60 physics frames)", running_ticks >= 1 and sim.clock.elapsed > 0.5, "elapsed=%.3f growth=%d spread=%d" % [sim.clock.elapsed, running_ticks, sim.clock.spread_ticks])
	# Esc injection (engine internal)
	Input.parse_input_event(key_event(KEY_ESCAPE, true))
	Input.parse_input_event(key_event(KEY_ESCAPE, false))
	await physics_frame
	await physics_frame
	rec("3.esc_pauses", "injected Esc pauses the SceneTree and shows the pause panel", paused and main.pause_panel.visible, "paused=%s panel=%s" % [paused, main.pause_panel.visible])
	var e0: float = sim.clock.elapsed
	var g0: int = sim.clock.growth_ticks
	var s0: int = sim.clock.spread_ticks
	for i: int in 180:
		await physics_frame
	rec("3.pause_freezes", "no ticks and no time while paused (180 physics frames = 3 s)", sim.clock.elapsed == e0 and sim.clock.growth_ticks == g0 and sim.clock.spread_ticks == s0, "elapsed %.4f -> %.4f ; growth %d -> %d ; spread %d -> %d" % [e0, sim.clock.elapsed, g0, sim.clock.growth_ticks, s0, sim.clock.spread_ticks])
	Input.parse_input_event(key_event(KEY_ESCAPE, true))
	Input.parse_input_event(key_event(KEY_ESCAPE, false))
	await physics_frame
	await physics_frame
	var resumed_at: float = sim.clock.elapsed
	var resumed_g: int = sim.clock.growth_ticks
	rec("3.esc_resumes", "second Esc resumes", not paused, "paused=%s" % paused)
	for i: int in 30:
		await physics_frame
	var gained: float = sim.clock.elapsed - e0
	rec("3.no_bulk_catchup", "after resume only the ~0.5 s of running frames is added, not the 3 s pause (gained %.3f s, ticks +%d)" % [gained, sim.clock.growth_ticks - g0], gained > 0.2 and gained < 0.7 and sim.clock.growth_ticks - g0 <= 2, "gained=%.4f resume_ticks=%d" % [gained, resumed_g - g0])
	# SceneTree-level pause flag direct (not through Esc) as well
	paused = true
	await physics_frame
	var e1: float = sim.clock.elapsed
	for i: int in 60:
		await physics_frame
	var frozen: bool = sim.clock.elapsed == e1
	paused = false
	rec("3.tree_pause", "SceneTree.paused=true alone also freezes the clock", frozen, "")
	main.queue_free()
	await process_frame

# ---------------------------------------------------------------------------------------------
# Oracle of the final picture, built from world state with my own rules.
func oracle_check(world: WorldState, view: RegionView, tuning: SimTuning, def: RegionDef, tx0: int, ty0: int, tw: int, th: int) -> Dictionary:
	var full: Image = Image.create(2048, 2048, false, Image.FORMAT_RGBA8)
	for by: int in view.blocks_y:
		for bx: int in view.blocks_x:
			full.blit_rect(view.block_images[by * view.blocks_x + bx], Rect2i(0, 0, 256, 256), Vector2i(bx * 256, by * 256))
	var data: PackedByteArray = full.get_data()
	var bad: int = 0
	var first_bad: String = ""
	var slot_pixel: Dictionary = {}
	var slot_bad: int = 0
	var ga: Array[PackedByteArray] = []
	for t: TerrainDef in def.terrains:
		ga.append(PackedByteArray([roundi(t.ground_color.r * 255.0), roundi(t.ground_color.g * 255.0), roundi(t.ground_color.b * 255.0)]))
	var mat: PackedByteArray = PackedByteArray([roundi(tuning.mature_color.r * 255.0), roundi(tuning.mature_color.g * 255.0), roundi(tuning.mature_color.b * 255.0)])
	var seedc: PackedByteArray = PackedByteArray([roundi(tuning.seed_color.r * 255.0), roundi(tuning.seed_color.g * 255.0), roundi(tuning.seed_color.b * 255.0)])
	var spr: PackedByteArray = PackedByteArray([roundi(tuning.sprout_color.r * 255.0), roundi(tuning.sprout_color.g * 255.0), roundi(tuning.sprout_color.b * 255.0)])
	var a: float = 0.5
	for ty: int in range(ty0, ty0 + th):
		for tx: int in range(tx0, tx0 + tw):
			var i: int = ty * 512 + tx
			var st: int = world.stage[i]
			var g: PackedByteArray = ga[world.terrain[i]]
			var tile_px: Array = []
			for ly: int in 4:
				for lx: int in 4:
					var o: int = ((ty * 4 + ly) * 2048 + tx * 4 + lx) * 4
					tile_px.append(PackedByteArray([data[o], data[o + 1], data[o + 2], data[o + 3]]))
			var expect: Array = []
			if st == 4:
				var up: bool = ty > 0 and world.stage[i - 512] == 4
				var dn: bool = ty < 511 and world.stage[i + 512] == 4
				var lf: bool = tx > 0 and world.stage[i - 1] == 4
				var rt: bool = tx < 511 and world.stage[i + 1] == 4
				var edge: PackedByteArray = PackedByteArray([0, 0, 0])
				for ch: int in 3:
					edge[ch] = roundi(g[ch] * (1.0 - a) + mat[ch] * a)
				for ly: int in 4:
					for lx: int in 4:
						var is_edge: bool = (ly == 0 and not up) or (ly == 3 and not dn) or (lx == 0 and not lf) or (lx == 3 and not rt)
						expect.append(edge if is_edge else mat)
				for p: int in 16:
					var ok: bool = true
					for ch: int in 3:
						if absi(int(tile_px[p][ch]) - int(expect[p][ch])) > 1:
							ok = false
					if tile_px[p][3] != 255:
						ok = false
					if not ok:
						bad += 1
						if first_bad == "":
							first_bad = "tile(%d,%d) px %d got %s want %s" % [tx, ty, p, tile_px[p], expect[p]]
			else:
				# Non-mature: all pixels ground except the plant pixels.
				var lit: Array[Vector2i] = []
				for p: int in 16:
					var is_g: bool = true
					for ch: int in 3:
						if absi(int(tile_px[p][ch]) - int(g[ch])) > 1:
							is_g = false
					if not is_g:
						lit.append(Vector2i(p % 4, p / 4))
				var want_n: int = [0, 1, 1, 2][st]
				var shape_ok: bool = lit.size() == want_n
				if shape_ok and st >= 1:
					var base_px: Vector2i = lit[lit.size() - 1]  # lowest pixel (last in raster order)
					# candidate set: centre 2x2
					shape_ok = base_px.x in [1, 2] and base_px.y in [1, 2]
					if st == 3:
						shape_ok = shape_ok and lit[0] == base_px + Vector2i(0, -1)
					# same slot -> same pixel everywhere (bijection check)
					var s: int = world.sprout_slot[i]
					if slot_pixel.has(s) and slot_pixel[s] != base_px:
						slot_bad += 1
					slot_pixel[s] = base_px
					var col: PackedByteArray = seedc if st == 1 else spr
					for q: Vector2i in lit:
						for ch: int in 3:
							if absi(int(tile_px[q.y * 4 + q.x][ch]) - int(col[ch])) > 1:
								shape_ok = false
				for p: int in 16:
					if tile_px[p][3] != 255:
						shape_ok = false
				if not shape_ok:
					bad += 1
					if first_bad == "":
						first_bad = "tile(%d,%d) stage %d lit=%s" % [tx, ty, st, lit]
	return {"bad": bad, "first_bad": first_bad, "slot_bad": slot_bad, "slots": slot_pixel.size()}

func t4_render() -> void:
	var def: RegionDef = load("res://data/region_01.tres") as RegionDef
	var tuning: SimTuning = load("res://data/sim_tuning.tres") as SimTuning
	var world: WorldState = RegionLoader.load_region(def)
	var view: RegionView = RegionView.new()
	view.setup(world, tuning)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 99
	# Build a messy region across the block boundaries x=64,128 / y=64,128: random clusters of all stages.
	for n: int in 3000:
		var x: int = rng.randi_range(40, 150)
		var y: int = rng.randi_range(40, 150)
		world.set_stage(y * 512 + x, rng.randi_range(0, 4))
	# Dense mature patches
	world.debug_fill_stage(Rect2i(60, 60, 9, 9), 4)
	world.debug_fill_stage(Rect2i(126, 100, 5, 3), 4)
	view.flush()
	var r: Dictionary = oracle_check(world, view, tuning, def, 40, 40, 112, 112)
	rec("4.oracle_after_flush", "every pixel of the 112x112-tile area (incl. block seams 64/128) equals my oracle after a flush", r["bad"] == 0, "bad=%d %s slots_seen=%d slot_inconsistent=%d" % [r["bad"], r["first_bad"], r["slots"], r["slot_bad"]])
	rec("4.slot_pixels", "all 4 centre-2x2 candidates occur; one fixed pixel per slot", r["slots"] == 4 and r["slot_bad"] == 0, "")
	# distribution across tiles
	var cnt: Array[int] = [0, 0, 0, 0]
	for x: int in range(40, 152):
		for y: int in range(40, 152):
			cnt[world.sprout_slot[y * 512 + x]] += 1
	var neighbour_same: int = 0
	for x: int in range(40, 151):
		if world.sprout_slot[100 * 512 + x] == world.sprout_slot[100 * 512 + x + 1]:
			neighbour_same += 1
	rec("4.slot_variation", "sprout position varies per tile (spread %s; adjacent-equal %d/111, ~25%% expected)" % [cnt, neighbour_same], cnt.min() > 112 * 112 * 0.18 and neighbour_same < 60, "")
	# More changes then re-oracle (edges must be redrawn when neighbours change)
	for n: int in 4000:
		var x: int = rng.randi_range(40, 150)
		var y: int = rng.randi_range(40, 150)
		world.set_stage(y * 512 + x, rng.randi_range(0, 4))
	view.flush()
	var r2: Dictionary = oracle_check(world, view, tuning, def, 40, 40, 112, 112)
	rec("4.oracle_incremental", "after 4000 more random changes and an incremental flush all pixels still equal my oracle (neighbour redraw)", r2["bad"] == 0, "bad=%d %s" % [r2["bad"], r2["first_bad"]])
	# Full-map oracle
	var rows_bad: int = 0
	var rf: Dictionary = oracle_check(world, view, tuning, def, 0, 0, 512, 512)
	rec("4.oracle_full", "all 262144 tiles (2048x2048 px) equal my oracle, incl. map border tiles", rf["bad"] == 0, "bad=%d %s" % [rf["bad"], rf["first_bad"]])
	# Oracle self-test: corrupt one pixel and one edge; the oracle must notice.
	var saved: Color = view.block_images[0].get_pixel(1, 1)
	view.block_images[0].set_pixel(1, 1, Color(1, 0, 1))
	var neg: Dictionary = oracle_check(world, view, tuning, def, 0, 0, 4, 4)
	view.block_images[0].set_pixel(1, 1, saved)
	rec("4.oracle_selftest", "oracle detects a deliberately corrupted pixel (negative control)", neg["bad"] >= 1, "bad=%d" % neg["bad"])
	# Explicit isolated cases with hand-specified expectations
	var w3: WorldState = WorldState.new(8, 8, def.terrains, 7)
	for i: int in 64:
		w3.terrain[i] = 0
	w3.apply_terrain_defs()
	var v3: RegionView = RegionView.new()
	v3.setup(w3, tuning)
	w3.set_stage(3 * 8 + 3, 4)
	v3.flush()
	var im: Image = v3.block_images[0]
	var ground: Color = def.terrains[0].ground_color
	var expect_edge: Color = ground.lerp(tuning.mature_color, 0.5)
	var ring_ok: bool = true
	for ly: int in 4:
		for lx: int in 4:
			var c: Color = im.get_pixel(12 + lx, 12 + ly)
			var inner: bool = lx in [1, 2] and ly in [1, 2]
			var want: Color = tuning.mature_color if inner else expect_edge
			if absf(c.r - want.r) > 0.01 or absf(c.g - want.g) > 0.01 or absf(c.b - want.b) > 0.01:
				ring_ok = false
	rec("4.isolated_mature", "isolated mature tile: inner 2x2 solid, 12 ring px = 50% green over ground (hand-computed)", ring_ok, "edge=%s ground=%s mature=%s" % [expect_edge, ground, tuning.mature_color])
	# diagonal only
	w3.set_stage(2 * 8 + 2, 4)
	v3.flush()
	var d_ok: bool = true
	for ly: int in 4:
		for lx: int in 4:
			var c: Color = im.get_pixel(12 + lx, 12 + ly)
			var inner: bool = lx in [1, 2] and ly in [1, 2]
			var want: Color = tuning.mature_color if inner else expect_edge
			if absf(c.r - want.r) > 0.01 or absf(c.g - want.g) > 0.01:
				d_ok = false
	rec("4.diagonal_ignored", "diagonal mature neighbour leaves the ring unchanged", d_ok, "")
	# orthogonal right neighbour: right side of (3,3) opaque, left side of (4,3) opaque
	w3.set_stage(3 * 8 + 4, 4)
	v3.flush()
	var c1: Color = im.get_pixel(12 + 3, 12 + 1)
	var c2: Color = im.get_pixel(16 + 0, 12 + 2)
	var c3: Color = im.get_pixel(12 + 0, 12 + 1)
	var shared: bool = c1.is_equal_approx(tuning.mature_color) and c2.is_equal_approx(tuning.mature_color) and absf(c3.r - expect_edge.r) < 0.01
	w3.set_stage(3 * 8 + 4, 0)
	v3.flush()
	var c4: Color = im.get_pixel(12 + 3, 12 + 1)
	var back: bool = absf(c4.r - expect_edge.r) < 0.01 and absf(c4.g - expect_edge.g) < 0.01
	rec("4.neighbour_redraw", "adjacent mature: shared side opaque on both; when neighbour stops being mature the side is semi-transparent again", shared and back, "shared=%s back=%s" % [shared, back])

# ---------------------------------------------------------------------------------------------
func t5_regression() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i: int in 20:
		await physics_frame
	var player: FlowerPlayer = main.player
	var cam: Camera2D = main.camera
	# Walk into each corner by injected actions.
	var corners: Array[String] = []
	var bounds_ok: bool = true
	var cam_ok: bool = true
	for case: Array in [[Vector2(100, 100), "move_left", "move_up", Vector2(32, 32), Vector2(320, 180)], [Vector2(1950, 1950), "move_right", "move_down", Vector2(2016, 2016), Vector2(1728, 1868)], [Vector2(100, 1950), "move_left", "move_down", Vector2(32, 2016), Vector2(320, 1868)], [Vector2(1950, 100), "move_right", "move_up", Vector2(2016, 32), Vector2(1728, 180)]]:
		player.simulation_position = case[0]
		Input.action_press(case[1])
		Input.action_press(case[2])
		for i: int in 120:
			await physics_frame
		Input.action_release(case[1])
		Input.action_release(case[2])
		await process_frame
		await process_frame
		var center: Vector2 = cam.get_screen_center_position()
		var p_ok: bool = player.simulation_position.is_equal_approx(case[3])
		var c_ok: bool = center.is_equal_approx(case[4])
		corners.append("%s->player %s cam %s" % [case[1] + "+" + case[2], player.simulation_position, center])
		bounds_ok = bounds_ok and p_ok
		cam_ok = cam_ok and c_ok
	rec("5.player_bounds", "player is clamped at the 2048x2048 region edges (32..2016 margin) in all 4 corners", bounds_ok, "; ".join(corners))
	rec("5.camera_bounds", "camera view stays within 0..2048 in all 4 corners (centre limited to 320..1728 / 180..1868)", cam_ok, "")
	# Movement inside region
	player.simulation_position = Vector2(1000, 1000)
	Input.action_press("move_right")
	for i: int in 60:
		await physics_frame
	Input.action_release("move_right")
	rec("5.moves", "player moves ~96 px/s inside the region (1 s)", absf(player.simulation_position.x - 1096.0) < 2.0 and player.simulation_position.y == 1000.0, str(player.simulation_position))
	# Weather keys
	var wx: Array[String] = []
	for pair: Array in [[KEY_2, "rain"], [KEY_3, "night"], [KEY_1, "sunny"]]:
		Input.parse_input_event(key_event(pair[0], true))
		Input.parse_input_event(key_event(pair[0], false))
		await physics_frame
		wx.append(main.condition)
	rec("5.weather", "injected 2/3/1 switch rain/night/sunny", wx == ["rain", "night", "sunny"], str(wx))
	# aim + shot (mouse injection inside engine)
	var mm: InputEventMouseMotion = InputEventMouseMotion.new()
	mm.position = Vector2(320, 100)
	mm.global_position = mm.position
	Input.parse_input_event(mm)
	await physics_frame
	await physics_frame
	var aim_up: bool = player.aim_direction.y < -0.3
	var mb: InputEventMouseButton = InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = true
	mb.position = mm.position
	mb.global_position = mm.position
	Input.parse_input_event(mb)
	await physics_frame
	await physics_frame
	var shots: int = main.preview_projectiles.size()
	var moved: bool = false
	if shots > 0:
		var p0: Vector2 = main.preview_projectiles[0]["position"]
		for i: int in 20:
			await physics_frame
		moved = (Vector2(main.preview_projectiles[0]["position"]) - p0).length() > 20.0 if not main.preview_projectiles.is_empty() else false
	rec("5.aim_shot", "injected mouse motion aims, left click spawns a preview seed which flies", aim_up and shots == 1 and moved, "aim=%s shots=%d moved=%s" % [player.aim_direction, shots, moved])
	# Esc pause blocks input/weather
	Input.parse_input_event(key_event(KEY_ESCAPE, true))
	Input.parse_input_event(key_event(KEY_ESCAPE, false))
	await physics_frame
	await physics_frame
	var pre: String = main.condition
	Input.parse_input_event(key_event(KEY_3, true))
	Input.parse_input_event(key_event(KEY_3, false))
	await physics_frame
	var blocked: bool = main.condition == pre
	var pp: Vector2 = player.simulation_position
	Input.action_press("move_left")
	for i: int in 20:
		await physics_frame
	Input.action_release("move_left")
	var still: bool = player.simulation_position == pp
	Input.parse_input_event(key_event(KEY_ESCAPE, true))
	Input.parse_input_event(key_event(KEY_ESCAPE, false))
	await physics_frame
	await physics_frame
	rec("5.pause_blocks", "while paused weather keys and movement are ignored; Esc again resumes", blocked and still and not paused, "weather_blocked=%s player_still=%s paused=%s" % [blocked, still, paused])
	main.queue_free()
	await process_frame

# ---------------------------------------------------------------------------------------------
func t7_perf() -> void:
	var def: RegionDef = load("res://data/region_01.tres") as RegionDef
	var tuning: SimTuning = load("res://data/sim_tuning.tres") as SimTuning
	var samples_init: Array[float] = []
	var load_ms: Array[float] = []
	var view_ms: Array[float] = []
	for k: int in 3:
		var t0: float = ms()
		var world: WorldState = RegionLoader.load_region(def)
		var t1: float = ms()
		var view: RegionView = RegionView.new()
		view.setup(world, tuning)
		var t2: float = ms()
		load_ms.append(t1 - t0)
		view_ms.append(t2 - t1)
		samples_init.append(t2 - t0)
	var world2: WorldState = RegionLoader.load_region(def)
	var view2: RegionView = RegionView.new()
	view2.setup(world2, tuning)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 5
	var res_lines: Array[String] = []
	for stage: int in [2, 4]:
		var picked: Array[int] = []
		while picked.size() < 1000:
			var i: int = rng.randi_range(0, 512 * 512 - 1)
			if world2.target[i] == 1 and world2.stage[i] != stage:
				picked.append(i)
		var t3: float = ms()
		for i: int in picked:
			world2.set_stage(i, stage)
		var t4: float = ms()
		view2.flush()
		var t5: float = ms()
		res_lines.append("stage%d scattered1000: set=%.2fms redraw=%.2fms total=%.2fms tiles=%d blocks=%d" % [stage, t4 - t3, t5 - t4, t5 - t3, view2.last_flush_tiles, view2.last_flush_blocks])
	# clustered
	var t6: float = ms()
	world2.debug_fill_stage(Rect2i(200, 200, 32, 32), 3)
	view2.flush()
	var t7: float = ms()
	res_lines.append("clustered 1024 tiles total=%.2fms" % (t7 - t6))
	var t8: float = ms()
	view2.flush()
	res_lines.append("idle flush %.3fms" % (ms() - t8))
	var init_avg: float = (samples_init[0] + samples_init[1] + samples_init[2]) / 3.0
	rec("7.perf_init", "init (load PNG + state + full render) measured 3x (headless: no GPU upload cost)", init_avg < 3000.0, "load=%s view=%s total=%s ms" % [load_ms, view_ms, samples_init])
	rec("7.perf_1000", "1000 scattered tile changes: set+redraw time (target <= 16 ms, informational)", true, " | ".join(res_lines))
