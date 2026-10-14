extends SceneTree
## OFFLINE re-analysis (headless) of the GPU capture gpu_viewport_640x360.png: rebuilds the identical deterministic world and camera, then compares pixels.
## The state is produced by the real natural spread (engine clock stepping), no OS input. Capture: PrintWindow.
## Expected pixels are composed here from the live WorldState (stage, sprout slot, terrain) and the tuning colours,
## not from RegionView code.
## Run: Godot --path <project> --screen 1 --script res://tests/p1/independent/p1_04_v_gpu_offline.gd

const OUT: String = "res://evidence/p1/p1-04/independent/"
const TILE: int = 4
var results: Array[Dictionary] = []

func _initialize() -> void:
	run.call_deferred()

func rec(id: String, cond: String, ok: bool, observed: String) -> void:
	results.append({"id": id, "condition": cond, "status": "PASS" if ok else "FAIL", "observed": observed})
	print("%s [%s] %s :: %s" % ["PASS" if ok else "FAIL", id, cond, observed])

func to8(c: float) -> int:
	return roundi(c * 255.0)

func free_rect(w: WorldState, x0: int, y0: int, rw: int, rh: int) -> bool:
	if x0 < 0 or y0 < 0 or x0 + rw > w.width or y0 + rh > w.height:
		return false
	for y: int in range(y0, y0 + rh):
		for x: int in range(x0, x0 + rw):
			var i: int = y * w.width + x
			if w.terrain[i] != 0 or w.stage[i] != 0:
				return false
	return true

func stage_counts(w: WorldState, r: Rect2i) -> Array[int]:
	var c: Array[int] = [0, 0, 0, 0, 0]
	for y: int in range(r.position.y, r.end.y):
		for x: int in range(r.position.x, r.end.x):
			c[w.stage[y * w.width + x]] += 1
	return c

func run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var world: WorldState = main.grid
	var player: FlowerPlayer = main.player
	var tun: SimTuning = main.tuning
	var clock: SimClock = main.simulation.clock
	var o: Vector2i = Vector2i(-1, -1)
	var best: int = 1 << 60
	for y0: int in range(10, world.height - 60, 4):
		for x0: int in range(10, world.width - 80, 4):
			var d: int = (x0 + 40 - 184) * (x0 + 40 - 184) + (y0 + 25 - 188) * (y0 + 25 - 188)
			if d < best and free_rect(world, x0, y0, 80, 50):
				o = Vector2i(x0, y0)
				best = d
	print("GPU_RECT origin=%s" % str(o))
	# initial mature block 4 wide x 30 high on the left, a manual seed, sprout1 and sprout2 of the player kind further right
	for y: int in range(10, 40):
		for x: int in range(4, 8):
			world.set_stage((o.y + y) * world.width + o.x + x, 4)
	world.set_stage((o.y + 20) * world.width + o.x + 70, 1)
	world.set_stage((o.y + 22) * world.width + o.x + 70, 2)
	world.growth[(o.y + 22) * world.width + o.x + 70] = 40000
	world.set_stage((o.y + 24) * world.width + o.x + 70, 3)
	world.growth[(o.y + 24) * world.width + o.x + 70] = 80000
	# keep the manual ones from growing past their stage by moving them away from natural time: they are checked as-is at capture
	var view_rect: Rect2i = Rect2i(o.x, o.y, 80, 50)
	var pick_t: float = -1.0
	var counts: Array[int] = []
	for step: int in 4 * 120:
		clock.advance(0.25)
		if step % 4 == 3 and clock.elapsed > 36.0:
			counts = stage_counts(world, Rect2i(o.x + 8, o.y, 40, 50))
			if counts[1] >= 8 and counts[2] >= 8 and counts[3] >= 8 and counts[4] > 120:
				pick_t = clock.elapsed
				break
	print("GPU_INFO t=%.2f counts(empty,seed,s1,s2,mature) right of block=%s" % [pick_t, str(counts)])
	rec("gpu.front_state", "natural spread produced a front with seeds, sprout1, sprout2 and mature tiles all present beside each other", pick_t > 0.0, "t=%.1f counts=%s natural tiles=%d" % [pick_t, str(counts), main.simulation.spread.total_planted])
	# camera: centre on the front
	var front_x: int = o.x + 8
	for x: int in range(o.x + 8, o.x + 60):
		if world.stage[(o.y + 25) * world.width + x] >= 2:
			front_x = x
	player.simulation_position = (Vector2(front_x - 6, o.y + 25) + Vector2(0.5, 0.5)) * TILE
	for i: int in 6:
		await physics_frame
	for i: int in 4:
		await process_frame
	paused = true
	for i: int in 4:
		await process_frame
	print("GPU_INFO renderer=%s window=%s size=%s screen=%d" % [RenderingServer.get_current_rendering_method(), root.position, root.size, root.current_screen])
	var vp: Image = Image.load_from_file(ProjectSettings.globalize_path(OUT + "gpu_viewport_640x360.png"))
	vp.convert(Image.FORMAT_RGBA8)
	var ct: Transform2D = main.get_viewport().get_canvas_transform()
	print("OFFLINE ct origin=%s" % str(ct.origin))
	var defs: Array[TerrainDef] = world.terrain_defs
	var seed8: Array = [to8(tun.seed_color.r), to8(tun.seed_color.g), to8(tun.seed_color.b)]
	var sprout8: Array = [to8(tun.sprout_color.r), to8(tun.sprout_color.g), to8(tun.sprout_color.b)]
	var mature8: Array = [to8(tun.mature_color.r), to8(tun.mature_color.g), to8(tun.mature_color.b)]
	var inv: Transform2D = ct.affine_inverse()
	var tl_world: Vector2 = inv * Vector2(0, 0)
	var br_world: Vector2 = inv * Vector2(640, 360)
	var clean_tiles: int = 0
	var occluded_tiles: int = 0
	var wrong_tiles: int = 0
	var by_stage_clean: Dictionary = {}
	var by_stage_total: Dictionary = {}
	var first_bad: String = ""
	var outline_bad: int = 0
	for ty: int in range(maxi(floori(tl_world.y / TILE), 0), mini(ceili(br_world.y / TILE), world.height)):
		for tx: int in range(maxi(floori(tl_world.x / TILE), 0), mini(ceili(br_world.x / TILE), world.width)):
			var idx: int = ty * world.width + tx
			var st: int = world.stage[idx]
			var slot: int = world.sprout_slot[idx]
			var ground: Color = defs[world.terrain[idx]].ground_color
			var g8: Array = [to8(ground.r), to8(ground.g), to8(ground.b)]
			var tl: Vector2 = ct * Vector2(tx * TILE, ty * TILE)
			var sx: int = roundi(tl.x)
			var sy: int = roundi(tl.y)
			if sx < 0 or sy < 40 or sx + TILE > 640 or sy + TILE > 320:
				continue
			by_stage_total[st] = int(by_stage_total.get(st, 0)) + 1
			var m_up: bool = ty > 0 and world.stage[idx - world.width] == 4
			var m_dn: bool = ty < world.height - 1 and world.stage[idx + world.width] == 4
			var m_lf: bool = tx > 0 and world.stage[idx - 1] == 4
			var m_rt: bool = tx < world.width - 1 and world.stage[idx + 1] == 4
			var edge8: Array = [(int(g8[0]) + int(mature8[0])) / 2.0, (int(g8[1]) + int(mature8[1])) / 2.0, (int(g8[2]) + int(mature8[2])) / 2.0]
			var palette: Array = [g8, seed8, sprout8, mature8, edge8]
			var foreign: bool = false
			var mismatch: bool = false
			for py: int in TILE:
				for px: int in TILE:
					var want: Array = g8
					if st == 1 and px == 1 + (slot & 1) and py == 1 + (slot >> 1):
						want = seed8
					elif st == 2 and px == 1 + (slot & 1) and py == 1 + (slot >> 1):
						want = sprout8
					elif st == 3 and px == 1 + (slot & 1) and (py == 1 + (slot >> 1) or py == (slot >> 1)):
						want = sprout8
					elif st == 4:
						want = mature8
						if (py == 0 and not m_up) or (py == TILE - 1 and not m_dn) or (px == 0 and not m_lf) or (px == TILE - 1 and not m_rt):
							want = edge8
					var got: Color = vp.get_pixel(sx + px, sy + py)
					var gr: Array = [to8(got.r), to8(got.g), to8(got.b)]
					var in_palette: bool = false
					for pcol: Array in palette:
						if absf(float(gr[0]) - float(pcol[0])) <= 1.01 and absf(float(gr[1]) - float(pcol[1])) <= 1.01 and absf(float(gr[2]) - float(pcol[2])) <= 1.01:
							in_palette = true
					if not in_palette:
						foreign = true
					elif absf(float(gr[0]) - float(want[0])) > 1.01 or absf(float(gr[1]) - float(want[1])) > 1.01 or absf(float(gr[2]) - float(want[2])) > 1.01:
						mismatch = true
			if foreign:
				occluded_tiles += 1
			elif mismatch:
				wrong_tiles += 1
				if first_bad == "":
					first_bad = "tile (%d,%d) stage %d" % [tx, ty, st]
			else:
				clean_tiles += 1
				by_stage_clean[st] = int(by_stage_clean.get(st, 0)) + 1
	rec("gpu_offline.pixel_oracle", "tiles whose 16 pixels are all palette colours (ground / seed / sprout / mature / half-transparent edge; the rest is covered by P0 scenery props, trees, shadows, HUD) match the live-world composition exactly; no tile shows palette-valid but wrong content", wrong_tiles == 0 and clean_tiles > 5000, "clean=%d occluded_by_scenery=%d wrong=%d clean by stage=%s of total by stage=%s %s" % [clean_tiles, occluded_tiles, wrong_tiles, str(by_stage_clean), str(by_stage_total), first_bad])
	rec("gpu_offline.front_tiles_clean", "clean (unoccluded) tiles include seeds, sprout1, sprout2 and mature tiles", by_stage_clean.has(1) and by_stage_clean.has(2) and by_stage_clean.has(3) and by_stage_clean.has(4), str(by_stage_clean))
	var f: FileAccess = FileAccess.open(OUT + "checks_gpu_offline.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(results, "  "))
	f.close()
	var fails: int = 0
	for r: Dictionary in results:
		if r["status"] != "PASS":
			fails += 1
	print("V_RESULT total=%d fails=%d" % [results.size(), fails])
	quit(1 if fails > 0 else 0)
