extends SceneTree
## OFFLINE re-evaluation of the saved GPU capture (gpu_viewport_640x360.png) of p1_05_v_gpu.gd: the GPU run had a wrong sanity threshold (art_px > 10) that failed the sparse young carrot (8 art px).
## Camera offset and plant tiles are taken from the GPU run log (carrot (168,207), kiwi (175,207), young (182,207),(189,207); screen = world - (396,680)).
## State is set up directly (plants via the play state, healing fruits spawned); no OS input. Capture: PrintWindow.
## Expected pixels are composed here from the art as listed in the P1-05 diff (rows + palette transcribed by me) and the
## tuning's mature colour, not by calling PlayArt.
## Run: Godot --headless --path <project> --script res://tests/p1/independent/p1_05_v_gpu_offline.gd

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
	var vp: Image = Image.load_from_file(ProjectSettings.globalize_path(OUT + "gpu_viewport_640x360.png"))
	vp.convert(Image.FORMAT_RGBA8)
	var tun: SimTuning = load("res://data/sim_tuning.tres") as SimTuning
	var ground: Array = [to8(tun.mature_color.r), to8(tun.mature_color.g), to8(tun.mature_color.b)]
	var off: Vector2i = Vector2i(396, 680)
	var cases: Array = [["mature carrot", Vector2i(168, 207), CARROT_MATURE, 20], ["mature kiwi", Vector2i(175, 207), KIWI_MATURE, 30], ["young carrot", Vector2i(182, 207), CARROT_YOUNG, 5], ["young kiwi", Vector2i(189, 207), KIWI_YOUNG, 5]]
	for c: Array in cases:
		var tile: Vector2i = c[1]
		var tl: Vector2i = Vector2i(tile.x * TILE, tile.y * TILE) - off
		var rows: Array[String] = []
		rows.assign(c[2])
		var r: Dictionary = check_sprite(vp, tl, rows, ground, 8)
		rec("gpu_offline.sprite_" + String(c[0]).replace(" ", "_"), "the %s in the saved GPU capture equals its 8x8 art pixel for pixel, with a plain-ground ring (no outline)" % c[0], int(r["bad"]) == 0 and int(r["ring_bad"]) == 0 and int(r["art_px"]) >= int(c[3]), "top_left=%s %s" % [str(tl), str(r)])
	var f: FileAccess = FileAccess.open(OUT + "checks_gpu_offline.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"results": results}, "  "))
	f.close()
	var fails: int = 0
	for r2: Dictionary in results:
		if r2["status"] != "PASS":
			fails += 1
	print("V_RESULT total=%d fails=%d" % [results.size(), fails])
	quit(1 if fails > 0 else 0)
