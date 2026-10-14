extends SceneTree
## Independent GPU-window render check for P1-04 (real window, NOT headless; run with --screen 1).
## The state is produced by the real natural spread (engine clock stepping), no OS input. Capture: PrintWindow.
## Expected pixels are composed here from the live WorldState (stage, sprout slot, terrain) and the tuning colours,
## not from RegionView code.
## Run: Godot --path <project> --screen 1 --script res://tests/p1/independent/p1_04_v_gpu.gd

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
	await RenderingServer.frame_post_draw
	print("GPU_INFO renderer=%s window=%s size=%s screen=%d" % [RenderingServer.get_current_rendering_method(), root.position, root.size, root.current_screen])
	var vp: Image = root.get_texture().get_image()
	vp.convert(Image.FORMAT_RGBA8)
	vp.save_png(ProjectSettings.globalize_path(OUT + "gpu_viewport_640x360.png"))
	var native_path: String = ProjectSettings.globalize_path(OUT + "gpu_window_native.png")
	var script_path: String = ProjectSettings.globalize_path("res://tests/independent/p0_verify_printwindow.ps1")
	var hwnd: int = DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE, 0)
	var pid: int = OS.create_process("powershell", ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", script_path, "-Hwnd", str(hwnd), "-Out", native_path])
	var waited: int = 0
	while pid > 0 and OS.is_process_running(pid) and waited < 1800:
		await process_frame
		waited += 1
	var native: Image = Image.load_from_file(native_path)
	native.convert(Image.FORMAT_RGBA8)
	var k: int = native.get_width() / 640
	rec("gpu.size", "PrintWindow capture is 1280x720 (k=2), internal frame 640x360", native.get_size() == Vector2i(1280, 720) and vp.get_size() == Vector2i(640, 360), "native=%s vp=%s" % [native.get_size(), vp.get_size()])
	var nd: PackedByteArray = native.get_data()
	var vd: PackedByteArray = vp.get_data()
	var bad: int = 0
	var mism: int = 0
	var w: int = native.get_width()
	for y: int in 360:
		for x: int in 640:
			var o0: int = ((y * k) * w + x * k) * 4
			for dy: int in k:
				for dx: int in k:
					var oo: int = ((y * k + dy) * w + x * k + dx) * 4
					if nd[oo] != nd[o0] or nd[oo + 1] != nd[o0 + 1] or nd[oo + 2] != nd[o0 + 2]:
						bad += 1
			var vo: int = (y * 640 + x) * 4
			if nd[o0] != vd[vo] or nd[o0 + 1] != vd[vo + 1] or nd[o0 + 2] != vd[vo + 2]:
				mism += 1
	rec("gpu.k2_uniform", "every 2x2 block of the window image is one colour (no smoothing)", bad == 0, "non-uniform pixels=%d" % bad)
	rec("gpu.native_equals_internal", "each block equals the internal frame pixel", mism == 0, "mismatching=%d of 230400" % mism)
	# pixel oracle for every tile in view, from the live world
	var ct: Transform2D = main.get_viewport().get_canvas_transform()
	var defs: Array[TerrainDef] = world.terrain_defs
	var seed8: Array = [to8(tun.seed_color.r), to8(tun.seed_color.g), to8(tun.seed_color.b)]
	var sprout8: Array = [to8(tun.sprout_color.r), to8(tun.sprout_color.g), to8(tun.sprout_color.b)]
	var mature8: Array = [to8(tun.mature_color.r), to8(tun.mature_color.g), to8(tun.mature_color.b)]
	var tiles_checked: int = 0
	var pix_checked: int = 0
	var pix_bad: int = 0
	var first_bad: String = ""
	var bad_tiles: Dictionary = {}
	var seen_stage: Dictionary = {}
	var edge_px_checked: int = 0
	var inv: Transform2D = ct.affine_inverse()
	var tl_world: Vector2 = inv * Vector2(0, 0)
	var br_world: Vector2 = inv * Vector2(640, 360)
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
			# skip the player sprite / aim marker area
			var ps: Vector2 = ct * player.simulation_position
			if absf(float(sx) - ps.x) < 40.0 and absf(float(sy) - ps.y) < 40.0:
				continue
			tiles_checked += 1
			seen_stage[st] = int(seen_stage.get(st, 0)) + 1
			var m_up: bool = ty > 0 and world.stage[idx - world.width] == 4
			var m_dn: bool = ty < world.height - 1 and world.stage[idx + world.width] == 4
			var m_lf: bool = tx > 0 and world.stage[idx - 1] == 4
			var m_rt: bool = tx < world.width - 1 and world.stage[idx + 1] == 4
			for py: int in TILE:
				for px: int in TILE:
					var want: Array = g8
					var is_edge: bool = false
					if st == 1 and px == 1 + (slot & 1) and py == 1 + (slot >> 1):
						want = seed8
					elif st == 2 and px == 1 + (slot & 1) and py == 1 + (slot >> 1):
						want = sprout8
					elif st == 3 and px == 1 + (slot & 1) and (py == 1 + (slot >> 1) or py == (slot >> 1)):
						want = sprout8
					elif st == 4:
						want = mature8
						if (py == 0 and not m_up) or (py == TILE - 1 and not m_dn) or (px == 0 and not m_lf) or (px == TILE - 1 and not m_rt):
							want = [(int(g8[0]) + int(mature8[0])) / 2.0, (int(g8[1]) + int(mature8[1])) / 2.0, (int(g8[2]) + int(mature8[2])) / 2.0]
							is_edge = true
					var got: Color = vp.get_pixel(sx + px, sy + py)
					var gr: Array = [to8(got.r), to8(got.g), to8(got.b)]
					pix_checked += 1
					if is_edge:
						edge_px_checked += 1
					var diff: float = 0.0
					for c: int in 3:
						diff = maxf(diff, absf(float(gr[c]) - float(want[c])))
					if diff > 1.01:
						pix_bad += 1
						bad_tiles[Vector2i(tx, ty)] = true
						if first_bad == "":
							first_bad = "tile (%d,%d) stage %d px (%d,%d) got %s want %s" % [tx, ty, st, px, py, str(gr), str(want)]
	rec("gpu.pixel_oracle", "every pixel of every visible tile (excluding HUD bars and the player area) equals the composition from the live world: seed 1 px at the slot, sprout1 1x1, sprout2 1x2 up, mature full tile, 1 px half-transparent edge only on sides without a mature 4-neighbour, bare ground elsewhere (so no outline)", pix_bad == 0 and pix_checked > 20000, "tiles=%d pixels=%d (edge px %d) bad=%d stages seen=%s %s" % [tiles_checked, pix_checked, edge_px_checked, pix_bad, str(seen_stage), first_bad])
	rec("gpu.front_visible", "the screenshot contains all of: seeds, sprout1, sprout2, mature tiles and ground", seen_stage.has(1) and seen_stage.has(2) and seen_stage.has(3) and seen_stage.has(4) and seen_stage.has(0), str(seen_stage))
	# crops for my own eyes
	var cx: int = clampi(roundi((ct * Vector2(front_x * TILE, (o.y + 25) * TILE)).x) - 60, 0, 520)
	var cy: int = clampi(roundi((ct * Vector2(front_x * TILE, (o.y + 25) * TILE)).y) - 30, 0, 300)
	var crop: Image = vp.get_region(Rect2i(cx, cy, 120, 60))
	crop.resize(120 * 8, 60 * 8, Image.INTERPOLATE_NEAREST)
	crop.save_png(ProjectSettings.globalize_path(OUT + "gpu_front_crop_x8.png"))
	# --- real-GPU CPU cost of the worst per-frame work: repaint budget with the window renderer (flush uploads the touched blocks)
	paused = false
	var times: Array[float] = []
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 5
	for rep: int in 40:
		for i: int in 6000:
			world.mark_dirty(rng.randi_range(0, world.tile_count() - 1))
		var t0: int = Time.get_ticks_usec()
		main.region_view.flush(tun.render_tiles_per_frame)
		times.append(float(Time.get_ticks_usec() - t0) / 1000.0)
		await process_frame
	times.sort()
	observations_print(times)
	rec("gpu.flush_cost", "real renderer: flushing a full 6000-tile budget scattered over the whole map (touching up to all 64 blocks) costs < 8 ms of CPU", times[times.size() / 2] < 8.0 and times[times.size() - 1] < 12.0, "median %.2f ms, max %.2f ms (blocks last flush=%d)" % [times[times.size() / 2], times[times.size() - 1], main.region_view.last_flush_blocks])
	var f: FileAccess = FileAccess.open(OUT + "checks_gpu.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(results, "  "))
	f.close()
	var fails: int = 0
	for r: Dictionary in results:
		if r["status"] != "PASS":
			fails += 1
	print("V_GPU_RESULT total=%d fails=%d" % [results.size(), fails])
	quit(1 if fails > 0 else 0)

func observations_print(times: Array[float]) -> void:
	print("GPU_FLUSH_MS ", str(times))
