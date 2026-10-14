extends SceneTree
## Independent GPU-window render check for P1-05 (real window, NOT headless; run once with --screen 1).
## State is set up directly (plants via the play state, healing fruits spawned); no OS input. Capture: PrintWindow.
## Expected pixels are composed here from the art as listed in the P1-05 diff (rows + palette transcribed by me) and the
## tuning's mature colour, not by calling PlayArt.
## Run: Godot --path <project> --screen 1 --script res://tests/p1/independent/p1_05_v_gpu.gd

const OUT: String = "res://evidence/p1/p1-05/independent/"
const TILE: int = 4
var results: Array[Dictionary] = []

const PAL: Dictionary = {
	"g": "77bd77", "G": "408863", "l": "badc83", "o": "f09a4a", "O": "c9692f", "b": "9c7469", "B": "795c58", "k": "a8d65a", "K": "6fa83a",
}
const CARROT_MATURE: Array[String] = ["..g..g..", ".gGg.gg.", "..gGgg..", "...gg...", "..oooo..", "..oooO..", "...oO...", "....O..."]
const CARROT_YOUNG: Array[String] = ["........", "........", "...g.g..", "....g...", "...GG...", "...oo...", "....O...", "........"]
const KIWI_MATURE: Array[String] = ["..gggg..", ".gGgGgg.", "gggbbggg", "gGbbbbgG", ".gbbbbg.", ".ggbbgg.", "..GggG..", "...GG..."]
const KIWI_YOUNG: Array[String] = ["........", "........", "...gg...", "..gGgg..", "...gG...", "...GG...", "...GG...", "........"]
const FRUIT: Array[String] = [".bb.", "bkKb", "bKkb", ".bb."]

func _initialize() -> void:
	run.call_deferred()

func rec(id: String, cond: String, ok: bool, observed: String) -> void:
	results.append({"id": id, "condition": cond, "status": "PASS" if ok else "FAIL", "observed": observed})
	print("%s [%s] %s :: %s" % ["PASS" if ok else "FAIL", id, cond, observed])

func to8(c: float) -> int:
	return roundi(c * 255.0)

func hex_rgb(h: String) -> Array:
	return [h.substr(0, 2).hex_to_int(), h.substr(2, 2).hex_to_int(), h.substr(4, 2).hex_to_int()]

func free_rect(w: WorldState, x0: int, y0: int, rw: int, rh: int) -> bool:
	if x0 < 0 or y0 < 0 or x0 + rw > w.width or y0 + rh > w.height:
		return false
	for y: int in range(y0, y0 + rh):
		for x: int in range(x0, x0 + rw):
			var i: int = y * w.width + x
			if w.terrain[i] != 0 or w.stage[i] != 0:
				return false
	return true

func px(img: Image, x: int, y: int) -> Array:
	var c: Color = img.get_pixel(x, y)
	return [to8(c.r), to8(c.g), to8(c.b)]

## Compares the viewport image at the footprint top-left screen position with the expected rows; transparent = ground.
func check_sprite(vp: Image, top_left: Vector2i, rows: Array[String], ground: Array, size_w: int) -> Dictionary:
	var bad: int = 0
	var first: String = ""
	var art: int = 0
	for y: int in rows.size():
		for x: int in size_w:
			var ch: String = rows[y].substr(x, 1)
			var want: Array = ground if ch == "." else hex_rgb(PAL[ch])
			if ch != ".":
				art += 1
			var got: Array = px(vp, top_left.x + x, top_left.y + y)
			if got != want:
				bad += 1
				if first == "":
					first = "(%d,%d) '%s' want %s got %s" % [x, y, ch, str(want), str(got)]
	# one pixel ring around the sprite must be plain ground (no outline)
	var ring_bad: int = 0
	var ring_first: String = ""
	for y: int in range(-1, rows.size() + 1):
		for x: int in range(-1, size_w + 1):
			if y >= 0 and y < rows.size() and x >= 0 and x < size_w:
				continue
			var gp: Array = px(vp, top_left.x + x, top_left.y + y)
			if gp != ground:
				ring_bad += 1
				if ring_first == "":
					ring_first = "(%d,%d) got %s" % [x, y, str(gp)]
	return {"bad": bad, "first": first, "art_px": art, "ring_bad": ring_bad, "ring_first": ring_first}

func run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var world: WorldState = main.grid
	var play: PlayState = main.play
	var player: FlowerPlayer = main.player
	var tun: SimTuning = main.tuning
	var o: Vector2i = Vector2i(-1, -1)
	var best: int = 1 << 60
	for y0: int in range(10, world.height - 40, 4):
		for x0: int in range(10, world.width - 60, 4):
			var d: int = (x0 + 25 - 184) * (x0 + 25 - 184) + (y0 + 15 - 188) * (y0 + 15 - 188)
			if d < best and free_rect(world, x0, y0, 50, 30):
				o = Vector2i(x0, y0)
				best = d
	print("GPU_RECT origin=%s" % str(o))
	# mature field 40x14; plants on it
	world.debug_fill_stage(Rect2i(o.x + 5, o.y + 5, 40, 14), 4)
	var base_y: int = o.y + 9
	var mature_carrot_px: Vector2 = Vector2(o.x + 10, base_y) * TILE + Vector2(4, 4)
	var mature_kiwi_px: Vector2 = Vector2(o.x + 17, base_y) * TILE + Vector2(4, 4)
	var young_carrot_px: Vector2 = Vector2(o.x + 24, base_y) * TILE + Vector2(4, 4)
	var young_kiwi_px: Vector2 = Vector2(o.x + 31, base_y) * TILE + Vector2(4, 4)
	player.simulation_position = Vector2(o.x + 21, base_y + 8) * TILE
	player.position = player.simulation_position.round()
	play.seeds = 40
	var mc: CultivatedPlant = null
	var mk: CultivatedPlant = null
	var yc: CultivatedPlant = null
	var yk: CultivatedPlant = null
	play.reserve_plant(play.def_by_key(&"carrot"))
	mc = play.land_plant(&"carrot", mature_carrot_px)
	play.reserve_plant(play.def_by_key(&"kiwi"))
	mk = play.land_plant(&"kiwi", mature_kiwi_px)
	rec("gpu.placed_mature_pair", "carrot and kiwi placed on the mature field", mc != null and mk != null, "carrot=%s kiwi=%s" % [str(mc.tile) if mc != null else "null", str(mk.tile) if mk != null else "null"])
	if mc == null or mk == null:
		quit(1)
		return
	mc.age = 39.8
	mk.age = 39.8
	for i: int in 30:
		await physics_frame
	rec("gpu.mature_pair_mature", "both matured after ~0.2 s", mc.mature and mk.mature, "carrot=%s kiwi=%s" % [mc.mature, mk.mature])
	play.reserve_plant(play.def_by_key(&"carrot"))
	yc = play.land_plant(&"carrot", young_carrot_px)
	play.reserve_plant(play.def_by_key(&"kiwi"))
	yk = play.land_plant(&"kiwi", young_kiwi_px)
	rec("gpu.placed_young_pair", "a young carrot and kiwi placed", yc != null and yk != null and not yc.mature and not yk.mature, "carrot=%s kiwi=%s" % [str(yc.tile) if yc != null else "null", str(yk.tile) if yk != null else "null"])
	# healing fruits next to the mature kiwi (player stays away from them)
	var kc: Vector2 = mk.center_tiles() * TILE
	play.pickups.spawn("heal_fruit", kc + Vector2(9, 3), 2000000 + mk.uid, 1000.0)
	play.pickups.spawn("heal_fruit", kc + Vector2(-8, 6), 2000000 + mk.uid, 1000.0)
	play.hp = 6
	play.select_index(1)
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
	rec("gpu.k2_uniform", "every 2x2 block of the window image is one colour (uniform k=2, no smoothing)", bad == 0, "non-uniform pixels=%d" % bad)
	rec("gpu.native_equals_internal", "each block equals the internal frame pixel", mism == 0, "mismatching=%d of 230400" % mism)
	# plant sprites
	var ct: Transform2D = main.get_viewport().get_canvas_transform()
	var ground: Array = [to8(tun.mature_color.r), to8(tun.mature_color.g), to8(tun.mature_color.b)]
	var cases: Array = [["mature carrot", mc, CARROT_MATURE], ["mature kiwi", mk, KIWI_MATURE], ["young carrot", yc, CARROT_YOUNG], ["young kiwi", yk, KIWI_YOUNG]]
	var summary: Dictionary = {}
	for c: Array in cases:
		var plant: CultivatedPlant = c[1]
		var tl: Vector2 = ct * Vector2(plant.tile.x * TILE, plant.tile.y * TILE)
		var top_left: Vector2i = Vector2i(roundi(tl.x), roundi(tl.y))
		var rows: Array[String] = []
		rows.assign(c[2])
		var r: Dictionary = check_sprite(vp, top_left, rows, ground, 8)
		summary[c[0]] = {"top_left": str(top_left), "result": r}
		rec("gpu.sprite_" + String(c[0]).replace(" ", "_"), "the %s is drawn pixel-exact from its 8x8 art (flat colours, transparent = mature ground) and has no outline ring around it" % c[0], int(r["bad"]) == 0 and int(r["ring_bad"]) == 0 and int(r["art_px"]) > 10, str(r))
	# healing fruits
	var fruit_bad: int = 0
	var fruit_first: String = ""
	var fruit_n: int = 0
	for it: Dictionary in play.pickups.items:
		if String(it["kind"]) != "heal_fruit":
			continue
		fruit_n += 1
		var wp: Vector2 = (Vector2(float(it["x"]), float(it["y"])) - Vector2(2, 2)).round()
		var sp: Vector2 = ct * wp
		var tl2: Vector2i = Vector2i(roundi(sp.x), roundi(sp.y))
		var rows2: Array[String] = []
		rows2.assign(FRUIT)
		var fr: Dictionary = check_sprite(vp, tl2, rows2, ground, 4)
		# the fruit may overlap tile edges; ground differs only outside the mature field, which these are inside
		if int(fr["bad"]) != 0:
			fruit_bad += int(fr["bad"])
			if fruit_first == "":
				fruit_first = str(fr)
	rec("gpu.heal_fruits", "both healing fruits are drawn pixel-exact from the 4x4 fruit art", fruit_n == 2 and fruit_bad == 0, "fruits=%d bad=%d %s" % [fruit_n, fruit_bad, fruit_first])
	# crops for my own eyes
	var pad: int = 6
	var rect: Rect2i = Rect2i(roundi((ct * Vector2(mc.tile.x * TILE, mc.tile.y * TILE)).x) - pad, roundi((ct * Vector2(mc.tile.x * TILE, mc.tile.y * TILE)).y) - 2 * pad, (yk.tile.x - mc.tile.x) * TILE + 8 + 2 * pad, 8 + 6 * pad)
	var crop: Image = vp.get_region(rect)
	crop.resize(crop.get_width() * 8, crop.get_height() * 8, Image.INTERPOLATE_NEAREST)
	crop.save_png(ProjectSettings.globalize_path(OUT + "gpu_plants_crop_x8.png"))
	var hud_rect: Rect2i = Rect2i(0, 330, 640, 30)
	var hud_crop: Image = vp.get_region(hud_rect)
	hud_crop.resize(hud_crop.get_width() * 2, hud_crop.get_height() * 2, Image.INTERPOLATE_NEAREST)
	hud_crop.save_png(ProjectSettings.globalize_path(OUT + "gpu_hud_crop_x2.png"))
	var hud_text: String = "%s | %s | %s | %s" % [main.hud.seed_label.text, main.hud.hp_label.text, main.hud.plant_label.text, main.hud.green_label.text]
	print("GPU_INFO hud='%s' crop_rect=%s" % [hud_text, str(rect)])
	rec("gpu.hud_text", "HUD labels show HP 6/10 and the carrot selected", main.hud.hp_label.text == "HP 6/10" and main.hud.plant_label.text == "植物 通常 [にんじん:3] キウイ", hud_text)
	# HUD fits in the footer: right edge of the HUD row inside the viewport
	var hud_right: float = main.hud.global_position.x + main.hud.size.x
	rec("gpu.hud_fits", "the HUD row ends inside the 640 px frame", hud_right <= 640.0, "hud x=%.1f..%.1f size=%s" % [main.hud.global_position.x, hud_right, str(main.hud.size)])
	# no dark outline anywhere near the plants: darkest pixel in the plants' crop must be from the art palette (min luminance of palette = 408863 / 795c58)
	var dark: int = 0
	for y: int in rect.size.y:
		for x: int in rect.size.x:
			var c2: Color = vp.get_pixel(rect.position.x + x, rect.position.y + y)
			if c2.get_luminance() < 0.2:
				dark += 1
	rec("gpu.no_dark_pixels", "no very dark (outline-like) pixel in the plant crop", dark == 0, "dark pixels=%d" % dark)
	var f: FileAccess = FileAccess.open(OUT + "checks_gpu.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"results": results, "summary": summary, "hud": hud_text}, "  "))
	f.close()
	var fails: int = 0
	for r2: Dictionary in results:
		if r2["status"] != "PASS":
			fails += 1
	print("V_RESULT total=%d fails=%d" % [results.size(), fails])
	quit(1 if fails > 0 else 0)
