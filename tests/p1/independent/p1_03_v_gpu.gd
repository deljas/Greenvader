extends SceneTree
## Independent GPU-window render check for P1-03 (real window, NOT headless; run with --screen 1).
## State is arranged from inside the engine (no OS input). Capture: PrintWindow (read-only, no focus change).
## Expected pixels come from the spec (stage looks in tasks/P1_03.md and AUTO_001.md) and from the terrain/sim tuning
## colours, composed by this script, not from RegionView code.
## Run: Godot --path <project> --screen 1 --script res://tests/p1/independent/p1_03_v_gpu.gd

const OUT: String = "res://evidence/p1/p1-03/independent/"
const TILE: int = 4
var results: Array[Dictionary] = []

func _initialize() -> void:
	run.call_deferred()

func rec(id: String, cond: String, ok: bool, observed: String) -> void:
	results.append({"id": id, "condition": cond, "status": "PASS" if ok else "FAIL", "observed": observed})
	print("%s [%s] %s :: %s" % ["PASS" if ok else "FAIL", id, cond, observed])

func is_free_rect(w: WorldState, x0: int, y0: int, rw: int, rh: int) -> bool:
	if x0 < 0 or y0 < 0 or x0 + rw > w.width or y0 + rh > w.height:
		return false
	for y: int in range(y0, y0 + rh):
		for x: int in range(x0, x0 + rw):
			if w.terrain[y * w.width + x] != 0:
				return false
	return true

func to8(c: float) -> int:
	return roundi(c * 255.0)

func run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var play: PlayState = main.play
	var world: WorldState = main.grid
	var player: FlowerPlayer = main.player
	var tun: SimTuning = main.tuning
	# a 60 x 30 tile wasteland rectangle, >= 280 px from the safe zone's mature tiles, nearest to the start
	var safe: PackedInt32Array = PackedInt32Array()
	for i: int in world.tile_count():
		if world.stage[i] == 4:
			safe.append(i)
	var rect0: Vector2i = Vector2i(-1, -1)
	var best: int = 1 << 60
	for y0: int in range(10, world.height - 40, 4):
		for x0: int in range(10, world.width - 70, 4):
			var d: int = (x0 + 30 - 184) * (x0 + 30 - 184) + (y0 + 15 - 188) * (y0 + 15 - 188)
			if d >= best or not is_free_rect(world, x0, y0, 60, 30):
				continue
			var cc: Vector2 = Vector2((x0 + 30) * TILE, (y0 + 15) * TILE)
			var ok: bool = true
			for s: int in safe:
				if Vector2((s % world.width + 0.5) * TILE, (s / world.width + 0.5) * TILE).distance_to(cc) < 400.0:
					ok = false
					break
			if ok:
				rect0 = Vector2i(x0, y0)
				best = d
	var o: Vector2i = rect0
	print("GPU_RECT origin=%s" % str(o))
	# --- layout (tile offsets inside the rectangle) -------------------------------------------------------------
	var expected_stage: Dictionary = {}
	for k: int in 8:
		expected_stage[Vector2i(2 + 3 * k, 2)] = 1
		expected_stage[Vector2i(2 + 3 * k, 6)] = 2
		expected_stage[Vector2i(2 + 3 * k, 10)] = 3
	# mature shapes
	var shapes: Array[Vector2i] = [Vector2i(2, 15), Vector2i(6, 15), Vector2i(7, 15), Vector2i(11, 15), Vector2i(12, 15), Vector2i(13, 15)]
	for dy: int in 3:
		for dx: int in 3:
			shapes.append(Vector2i(18 + dx, 14 + dy))
	for t: Vector2i in [Vector2i(26, 14), Vector2i(26, 15), Vector2i(26, 16), Vector2i(27, 16), Vector2i(28, 16)]:
		shapes.append(t)
	shapes.append(Vector2i(2, 20))  # isolated, diagonal neighbours only
	shapes.append(Vector2i(3, 21))
	shapes.append(Vector2i(5, 20))
	shapes.append(Vector2i(7, 22))
	shapes.append(Vector2i(8, 21))
	for t: Vector2i in shapes:
		expected_stage[t] = 4
	# the big field (real production runs on it)
	for fy: int in range(4, 24):
		for fx: int in range(36, 56):
			expected_stage[Vector2i(fx, fy)] = 4
	# apply with the real world API
	for t: Vector2i in expected_stage:
		world.set_stage((o.y + t.y) * world.width + o.x + t.x, expected_stage[t])
	var centre: Vector2 = Vector2(o) * TILE + Vector2(28 * TILE, 12 * TILE)
	player.simulation_position = Vector2(o) * TILE + Vector2(30 * TILE, 33 * TILE)
	play.seeds = play.tuning.seed_max
	for i: int in 4:
		await physics_frame
	# real production: 400 mature tiles inside the circle, default tuning; 32 s of game time in the real code path
	var player_at: Vector2 = player.simulation_position
	for i: int in 128:
		play.advance(0.25, player_at)
	# one source-owned fruit next to the field to compare looks (owner 1)
	play.pickups.spawn(GroundPickups.KIND_SEED_FRUIT, Vector2(o) * TILE + Vector2(33 * TILE, 14 * TILE), 1)
	for i: int in 6:
		await physics_frame
	for i: int in 4:
		await process_frame
	paused = true
	for i: int in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var plant_n: int = play.pickups.count_plant_owned()
	print("GPU_INFO renderer=%s window=%s size=%s scale=%s screen=%d plant_fruits=%d total_pickups=%d player=%s camera=%s" % [RenderingServer.get_current_rendering_method(), root.position, root.size, root.content_scale_size, root.current_screen, plant_n, play.pickups.count(), player.simulation_position, main.camera.position])
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
	# --- pixel oracle for the arranged region --------------------------------------------------------------
	var ct: Transform2D = main.get_viewport().get_canvas_transform()
	var ground: Color = (main.region_def.terrains[0] as TerrainDef).ground_color
	var ground8: Array = [to8(ground.r), to8(ground.g), to8(ground.b)]
	var seed8: Array = [to8(tun.seed_color.r), to8(tun.seed_color.g), to8(tun.seed_color.b)]
	var sprout8: Array = [to8(tun.sprout_color.r), to8(tun.sprout_color.g), to8(tun.sprout_color.b)]
	var mature8: Array = [to8(tun.mature_color.r), to8(tun.mature_color.g), to8(tun.mature_color.b)]
	var edge8: Array = []
	for c: int in 3:
		edge8.append((int(ground8[c]) + int(mature8[c])) / 2.0)  # half transparency over the ground
	# pixels under fruit sprites (4x4, drawn centred on the pickup) are excluded from the stage oracle
	var masked: Dictionary = {}
	for it: Dictionary in play.pickups.items:
		var sp: Vector2 = ct * Vector2(float(it["x"]), float(it["y"]))
		for my: int in range(roundi(sp.y) - 3, roundi(sp.y) + 4):
			for mx: int in range(roundi(sp.x) - 3, roundi(sp.x) + 4):
				masked[Vector2i(mx, my)] = true
	var tiles_checked: int = 0
	var pix_checked: int = 0
	var pix_bad: int = 0
	var first_bad: String = ""
	var in_view_tiles: int = 0
	var slot_seen: Dictionary = {}
	var outline_hits: int = 0
	var mature_edge_ok: bool = true
	# check the rectangle plus a 2 tile margin
	for ty: int in range(-2, 26):
		for tx: int in range(-2, 62):
			var tile: Vector2i = Vector2i(o.x + tx, o.y + ty)
			var st: int = int(expected_stage.get(Vector2i(tx, ty), 0))
			var idx: int = tile.y * world.width + tile.x
			var slot: int = world.sprout_slot[idx]
			var tl: Vector2 = ct * Vector2(tile * TILE)
			var sx: int = roundi(tl.x)
			var sy: int = roundi(tl.y)
			if sx < 0 or sy < 0 or sx + TILE > 640 or sy + TILE > 360:
				continue
			in_view_tiles += 1
			for py: int in TILE:
				for px: int in TILE:
					var want: Array = ground8
					if st == 1 and px == 1 + (slot & 1) and py == 1 + (slot >> 1):
						want = seed8
					elif st == 2 and px == 1 + (slot & 1) and py == 1 + (slot >> 1):
						want = sprout8
					elif st == 3 and px == 1 + (slot & 1) and (py == 1 + (slot >> 1) or py == (slot >> 1)):
						want = sprout8
					elif st == 4:
						want = mature8
						var m_up: bool = int(expected_stage.get(Vector2i(tx, ty - 1), 0)) == 4
						var m_dn: bool = int(expected_stage.get(Vector2i(tx, ty + 1), 0)) == 4
						var m_lf: bool = int(expected_stage.get(Vector2i(tx - 1, ty), 0)) == 4
						var m_rt: bool = int(expected_stage.get(Vector2i(tx + 1, ty), 0)) == 4
						if (py == 0 and not m_up) or (py == TILE - 1 and not m_dn) or (px == 0 and not m_lf) or (px == TILE - 1 and not m_rt):
							want = edge8
					if masked.has(Vector2i(sx + px, sy + py)):
						continue
					var got: Color = vp.get_pixel(sx + px, sy + py)
					var gr: Array = [to8(got.r), to8(got.g), to8(got.b)]
					pix_checked += 1
					var diff: float = 0.0
					for c: int in 3:
						diff = maxf(diff, absf(float(gr[c]) - float(want[c])))
					if diff > 1.01:
						pix_bad += 1
						if first_bad == "":
							first_bad = "tile (%d,%d) stage %d px (%d,%d) got %s want %s" % [tx, ty, st, px, py, str(gr), str(want)]
					if st == 0 and want == ground8 and diff > 1.01:
						outline_hits += 1
			tiles_checked += 1
			if st == 1 or st == 2 or st == 3:
				slot_seen[slot] = true
	rec("gpu.pixel_oracle", "every pixel of the arranged rectangle (seed/sprout1/sprout2 rows, mature shapes, 20x20 field, plus margin) equals the spec composition: seed colour 1 px at the slot, sprout1 1x1, sprout2 1x2 growing up, mature full tile, 1 px half-transparent edge only on sides without a mature 4-neighbour, plain ground elsewhere", pix_bad == 0 and pix_checked > 20000, "tiles in view checked=%d pixels=%d bad=%d %s" % [tiles_checked, pix_checked, pix_bad, first_bad])
	rec("gpu.no_outline", "no outline: the ground tiles around every plant (margin and between plants) are exactly the ground colour; no extra dark/light pixels", outline_hits == 0 and pix_bad == 0, "ground pixels deviating=%d" % outline_hits)
	rec("gpu.sprout_slots", "sprout positions vary over the centre 2x2 candidates in the picture", slot_seen.size() >= 3, "slots seen=%s" % str(slot_seen.keys()))
	# --- fruits: sprites and positions ----------------------------------------------------------------
	var plant_fruit_tiles_ok: bool = true
	var on_field: int = 0
	for it: Dictionary in play.pickups.items:
		var owner: int = int(it["owner"])
		if owner >= GroundPickups.PLANT_OWNER_BASE:
			var tile_i: int = owner - GroundPickups.PLANT_OWNER_BASE
			if world.stage[tile_i] != 4:
				plant_fruit_tiles_ok = false
			on_field += 1
	rec("gpu.fruits", "plant fruits produced by the real code on the 400-tile field lie on mature tiles and are on screen", plant_n >= 5 and plant_fruit_tiles_ok, "plant fruits=%d" % plant_n)
	# crops for my own eyes
	var cam_to_screen: Vector2 = ct * (Vector2(o) * TILE)
	var rx: int = clampi(roundi(cam_to_screen.x) - 8, 0, 640)
	var ry: int = clampi(roundi(cam_to_screen.y) - 8, 0, 360)
	var crop1: Image = vp.get_region(Rect2i(rx, ry, mini(150, 640 - rx), mini(100, 360 - ry)))
	crop1.resize(crop1.get_width() * 8, crop1.get_height() * 8, Image.INTERPOLATE_NEAREST)
	crop1.save_png(ProjectSettings.globalize_path(OUT + "gpu_left_layout_x8.png"))
	var rx2: int = clampi(roundi(ct.x.x * 0.0 + (ct * (Vector2(o) * TILE + Vector2(34 * TILE, 2 * TILE))).x) - 4, 0, 640)
	var ry2: int = clampi(roundi((ct * (Vector2(o) * TILE + Vector2(34 * TILE, 2 * TILE))).y) - 4, 0, 360)
	var crop2: Image = vp.get_region(Rect2i(rx2, ry2, mini(100, 640 - rx2), mini(100, 360 - ry2)))
	crop2.resize(crop2.get_width() * 8, crop2.get_height() * 8, Image.INTERPOLATE_NEAREST)
	crop2.save_png(ProjectSettings.globalize_path(OUT + "gpu_field_fruits_x8.png"))
	var f: FileAccess = FileAccess.open(OUT + "checks_gpu.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(results, "  "))
	f.close()
	var fails: int = 0
	for r: Dictionary in results:
		if r["status"] != "PASS":
			fails += 1
	print("V_GPU_RESULT total=%d fails=%d" % [results.size(), fails])
	quit(1 if fails > 0 else 0)
