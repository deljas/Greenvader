extends SceneTree
## 仮スプライトの生成ツール(入口)。輪郭線なし・少ない色数・透明背景。1種類1枚の静止画。
## 実行(隔離プロジェクトのみ): Godot --headless --path C:/godot/greenvader_content_sandbox --script res://tests/content_pack/tools/gen_sprites.gd
## 出力: assets/content_pack/<名前>.png と data/content_pack/sprites.json(size / foot。占有・当たり判定とは別データ)
const OUT_ASSETS: String = "res://assets/content_pack"
const OUT_META: String = "res://data/content_pack/sprites.json"

var img: Image
var W: int = 0
var H: int = 0
var meta: Dictionary = {}

# ---------------------------------------------------------------- 描画の道具
func px(x: int, y: int, c: Color) -> void:
	if x >= 0 and y >= 0 and x < W and y < H:
		img.set_pixel(x, y, c)

func rect(x: int, y: int, w: int, h: int, c: Color) -> void:
	for yy: int in range(y, y + h):
		for xx: int in range(x, x + w):
			px(xx, yy, c)

## 3段の明暗(左上が明るく右下が暗い)をつけた楕円
func blob(cx: float, cy: float, rx: float, ry: float, c: Color) -> void:
	var lt: Color = c.lightened(0.22)
	var dk: Color = c.darkened(0.25)
	for y: int in range(int(floor(cy - ry)) - 1, int(ceil(cy + ry)) + 2):
		for x: int in range(int(floor(cx - rx)) - 1, int(ceil(cx + rx)) + 2):
			var nx: float = (float(x) + 0.5 - cx) / rx
			var ny: float = (float(y) + 0.5 - cy) / ry
			if nx * nx + ny * ny <= 1.0:
				var s: float = nx * 0.45 + ny * 0.85
				px(x, y, lt if s < -0.38 else (dk if s > 0.45 else c))

## 上辺が明るく下辺が暗い箱
func box(x: int, y: int, w: int, h: int, c: Color) -> void:
	rect(x, y, w, h, c)
	if h >= 3:
		rect(x, y, w, 1, c.lightened(0.22))
		rect(x, y + h - 1, w, 1, c.darkened(0.25))

func line(x0: int, y0: int, x1: int, y1: int, c: Color) -> void:
	var dx: int = absi(x1 - x0)
	var dy: int = -absi(y1 - y0)
	var sx: int = 1 if x0 < x1 else -1
	var sy: int = 1 if y0 < y1 else -1
	var err: int = dx + dy
	var x: int = x0
	var y: int = y0
	for i: int in range(200):
		px(x, y, c)
		if x == x1 and y == y1:
			break
		var e2: int = 2 * err
		if e2 >= dy:
			err += dy
			x += sx
		if e2 <= dx:
			err += dx
			y += sy

func tri(x0: float, y0: float, x1: float, y1: float, x2: float, y2: float, c: Color) -> void:
	var minx: int = int(floor(minf(x0, minf(x1, x2))))
	var maxx: int = int(ceil(maxf(x0, maxf(x1, x2))))
	var miny: int = int(floor(minf(y0, minf(y1, y2))))
	var maxy: int = int(ceil(maxf(y0, maxf(y1, y2))))
	for y: int in range(miny, maxy + 1):
		for x: int in range(minx, maxx + 1):
			var p: Vector2 = Vector2(float(x) + 0.5, float(y) + 0.5)
			var d1: float = (p.x - x1) * (y0 - y1) - (x0 - x1) * (p.y - y1)
			var d2: float = (p.x - x2) * (y1 - y2) - (x1 - x2) * (p.y - y2)
			var d3: float = (p.x - x0) * (y2 - y0) - (x2 - x0) * (p.y - y0)
			var neg: bool = d1 < 0.0 or d2 < 0.0 or d3 < 0.0
			var pos: bool = d1 > 0.0 or d2 > 0.0 or d3 > 0.0
			if not (neg and pos):
				px(x, y, c)

func col(r: int, g: int, b: int) -> Color:
	return Color8(r, g, b)

# ---------------------------------------------------------------- 出力
func begin(name: String, w: int, h: int, foot: Array = []) -> void:
	W = w
	H = h
	img = Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var f: Array = foot if not foot.is_empty() else [w / 2, h]
	meta[name] = {"file": name + ".png", "size": [w, h], "foot": f}
	cur = name

var cur: String = ""

func finish() -> void:
	img.save_png(OUT_ASSETS + "/" + cur + ".png")

# ---------------------------------------------------------------- 敵
func enemy(name: String) -> void:
	match name:
		"shadow_brian":
			var c: Color = col(78, 66, 66)
			rect(6, 19, 3, 5, c.darkened(0.2)); rect(11, 19, 3, 5, c.darkened(0.2))
			rect(19, 19, 3, 5, c.darkened(0.2)); rect(24, 19, 3, 5, c.darkened(0.2))
			line(1, 10, 0, 16, c.darkened(0.2))
			blob(14, 13, 13, 8, c)
			blob(26, 12, 6, 6, c.lightened(0.08))
			rect(24, 8, 4, 2, col(150, 140, 135))
			rect(29, 6, 3, 2, col(225, 215, 175)); rect(30, 3, 2, 3, col(225, 215, 175))
			px(27, 11, col(220, 70, 50))
		"tarachunade":
			for l: Array in [[3, 9, 1, 11], [5, 10, 3, 11], [11, 10, 13, 11], [13, 9, 15, 11]]:
				line(l[0], l[1], l[2], l[3], col(95, 60, 45))
			blob(7, 6, 6, 5, col(205, 120, 55))
			blob(13, 7, 3, 3, col(105, 65, 48))
			px(14, 6, col(240, 230, 120)); px(1, 5, col(255, 225, 90)); px(0, 4, col(255, 170, 60))
		"mushling_parent":
			rect(8, 18, 4, 10, col(230, 215, 190)); rect(13, 18, 4, 10, col(215, 200, 175))
			blob(12, 18, 6, 5, col(235, 220, 195))
			blob(12, 9, 11, 8, col(165, 65, 58))
			blob(7, 7, 2, 1.6, col(240, 235, 225)); blob(14, 4, 2, 1.6, col(240, 235, 225)); blob(17, 9, 2, 1.5, col(240, 235, 225))
			px(10, 17, col(70, 55, 55)); px(14, 17, col(70, 55, 55))
		"mushling_child":
			rect(4, 8, 4, 4, col(235, 220, 195)); rect(3, 12, 2, 2, col(215, 200, 175)); rect(7, 12, 2, 2, col(215, 200, 175))
			blob(6, 5, 5, 4, col(150, 105, 160))
			px(4, 4, col(235, 225, 240)); px(8, 3, col(235, 225, 240)); px(7, 6, col(235, 225, 240))
		"quill_hedgehog":
			for l: Array in [[3, 6, 1, 1], [6, 4, 5, 0], [9, 3, 10, 0], [12, 4, 14, 1], [14, 6, 15, 3]]:
				line(l[0], l[1], l[2], l[3], col(210, 170, 100))
			rect(4, 12, 2, 2, col(105, 75, 55)); rect(10, 12, 2, 2, col(105, 75, 55))
			blob(8, 8, 7, 5, col(130, 95, 70))
			blob(13, 9, 3, 3, col(195, 160, 125))
			px(14, 9, col(60, 45, 40)); px(15, 10, col(60, 45, 40))
		"grass_snake":
			for x: int in range(1, 18):
				var y: int = 3 + int(round(1.6 * sin(float(x) * 0.8)))
				rect(x, y, 2, 3, col(95, 160, 70) if x % 4 < 2 else col(70, 130, 60))
			blob(18, 4, 2.2, 2.2, col(125, 185, 85))
			px(18, 3, col(240, 220, 90)); px(19, 5, col(220, 60, 60))
		"grass_snake_grass":
			var greens: Array = [col(80, 150, 60), col(105, 175, 70), col(60, 125, 55)]
			for i: int in range(9):
				var x0: int = 1 + i * 2
				line(x0, 7, x0 + (i % 3) - 1, 1 + (i * 5) % 4, greens[i % 3])
			rect(0, 6, 20, 2, greens[2])
		"seed_bird":
			line(5, 9, 5, 9, col(230, 150, 60)); line(8, 9, 8, 9, col(230, 150, 60))
			rect(0, 4, 3, 2, col(110, 80, 55))
			blob(6, 5, 5, 4, col(160, 120, 80))
			blob(11, 4, 3, 3, col(185, 145, 100))
			rect(12, 5, 2, 2, col(240, 190, 70))
			blob(5, 5, 3, 2, col(120, 88, 60))
			px(11, 3, col(40, 35, 35))
		"junk_crab":
			line(7, 10, 7, 6, col(215, 130, 100)); line(13, 10, 13, 6, col(215, 130, 100))
			px(7, 5, col(250, 240, 230)); px(13, 5, col(250, 240, 230)); px(7, 6, col(40, 35, 35)); px(13, 6, col(40, 35, 35))
			for l: Array in [[5, 15, 3, 17], [8, 16, 7, 17], [12, 16, 13, 17], [15, 15, 17, 17]]:
				line(l[0], l[1], l[2], l[3], col(170, 90, 70))
			blob(10, 13, 6, 3.5, col(225, 130, 100))
			blob(3, 11, 3, 2.5, col(235, 150, 115)); blob(17, 11, 3, 2.5, col(235, 150, 115))
		"junk_crab_shell":
			box(1, 2, 14, 10, col(135, 150, 165))
			rect(1, 1, 14, 2, col(175, 190, 205))
			rect(3, 6, 4, 3, col(165, 100, 65)); rect(10, 4, 3, 4, col(165, 100, 65))
			rect(1, 5, 14, 1, col(105, 118, 132))
		"junk_pile":
			blob(8, 9, 7, 3, col(120, 100, 85))
			box(2, 4, 5, 5, col(135, 150, 165)); box(8, 2, 5, 6, col(165, 100, 65))
			box(10, 6, 5, 5, col(150, 150, 155)); box(5, 7, 4, 4, col(180, 90, 80))
		"stray_wolf":
			rect(5, 11, 2, 3, col(110, 110, 118)); rect(8, 11, 2, 3, col(110, 110, 118))
			rect(13, 11, 2, 3, col(110, 110, 118)); rect(16, 11, 2, 3, col(110, 110, 118))
			line(2, 5, 0, 2, col(125, 125, 132))
			blob(10, 8, 8, 4, col(150, 150, 158))
			blob(18, 6, 3.5, 3, col(170, 170, 178))
			rect(20, 6, 2, 2, col(140, 140, 148)); rect(17, 2, 2, 2, col(125, 125, 132)); rect(19, 2, 2, 2, col(125, 125, 132))
			px(19, 5, col(240, 210, 90)); px(21, 6, col(50, 45, 48))
		"moss_turtle":
			rect(6, 17, 5, 3, col(165, 170, 105)); rect(18, 17, 5, 3, col(165, 170, 105))
			blob(25, 13, 3, 3, col(170, 175, 110))
			blob(14, 11, 12, 8, col(100, 112, 70))
			blob(10, 6, 4, 2, col(70, 150, 70)); blob(18, 6, 5, 2, col(85, 165, 75))
			for l: Array in [[8, 5, 7, 2], [12, 4, 12, 1], [17, 4, 18, 1], [21, 5, 22, 2]]:
				line(l[0], l[1], l[2], l[3], col(95, 175, 85))
			px(26, 12, col(45, 40, 35))
		"moss_turtle_bush":
			blob(8, 13, 7, 6, col(70, 140, 65)); blob(19, 12, 8, 7, col(85, 155, 70)); blob(14, 8, 8, 6, col(100, 170, 80))
			rect(3, 17, 22, 3, col(60, 120, 58))
			for p: Array in [[6, 9], [20, 7], [13, 4], [22, 14]]:
				px(p[0], p[1], col(150, 205, 110))
		"paint_chameleon":
			rect(5, 10, 1, 2, col(205, 140, 155)); rect(11, 10, 1, 2, col(205, 140, 155))
			for a: Array in [[0, 4], [0, 5], [1, 3], [2, 3], [3, 4], [3, 5], [2, 6], [1, 6]]:
				px(a[0], a[1], col(215, 150, 165))
			blob(8, 7, 6, 4, col(240, 180, 195))
			blob(14, 6, 3, 3, col(245, 195, 205))
			px(15, 5, col(40, 35, 40)); px(13, 3, col(225, 160, 175))
		"slime_slug":
			rect(2, 8, 14, 2, col(185, 195, 110))
			blob(9, 6, 8, 3.5, col(160, 190, 95))
			line(15, 3, 16, 0, col(140, 170, 85)); line(17, 4, 17, 1, col(140, 170, 85))
			px(5, 4, col(235, 245, 200)); px(6, 4, col(235, 245, 200))
		"pouch_rabbit":
			rect(3, 12, 3, 2, col(190, 160, 125)); rect(8, 12, 3, 2, col(190, 160, 125))
			box(7, 0, 2, 5, col(205, 175, 140)); box(10, 1, 2, 4, col(205, 175, 140))
			px(8, 2, col(235, 170, 175))
			blob(6, 9, 5, 4, col(200, 168, 130))
			blob(10, 6, 4, 4, col(212, 182, 145))
			blob(12, 8, 3, 3, col(230, 205, 175))
			blob(1.5, 10, 1.5, 1.5, col(245, 240, 230))
			px(10, 5, col(50, 40, 40))
		"tongue_frog":
			rect(2, 11, 3, 3, col(100, 150, 75)); rect(11, 11, 3, 3, col(100, 150, 75))
			blob(8, 9, 7, 5, col(115, 175, 85))
			blob(8, 11, 4, 2, col(190, 215, 150))
			blob(4, 3, 2.2, 2.2, col(130, 190, 95)); blob(12, 3, 2.2, 2.2, col(130, 190, 95))
			px(4, 3, col(250, 245, 200)); px(12, 3, col(250, 245, 200)); px(4, 4, col(45, 40, 40)); px(12, 4, col(45, 40, 40))
			line(4, 9, 12, 9, col(80, 120, 60))
		"honeybee_hive":
			line(7, 0, 7, 3, col(120, 90, 60))
			blob(7, 5, 4, 4, col(235, 185, 85))
			blob(7, 11, 6, 5, col(225, 165, 55))
			rect(2, 9, 11, 1, col(180, 120, 40)); rect(3, 12, 9, 1, col(180, 120, 40))
			rect(6, 13, 3, 2, col(90, 60, 35))
		"honeybee_swarm":
			for p: Array in [[2, 6], [6, 2], [9, 7], [4, 3], [8, 4]]:
				rect(p[0], p[1], 2, 2, col(250, 205, 70))
				px(p[0], p[1] + 1, col(95, 70, 40))
				px(p[0] - 1, p[1] - 1, col(225, 235, 245)); px(p[0] + 2, p[1] - 1, col(225, 235, 245))
		"armadillo":
			rect(4, 11, 2, 3, col(135, 115, 105)); rect(12, 11, 2, 3, col(135, 115, 105))
			line(1, 8, 0, 11, col(135, 115, 105))
			blob(9, 8, 8, 5, col(150, 130, 120))
			for x: int in [5, 8, 11]:
				rect(x, 4, 1, 8, col(120, 100, 92))
			blob(16, 9, 2.5, 2.2, col(180, 160, 150))
			rect(15, 5, 2, 3, col(135, 115, 105)); px(17, 8, col(45, 40, 40))
		"sludge_carp":
			rect(0, 3, 3, 5, col(125, 105, 70))
			blob(10, 5, 9, 4, col(130, 108, 72))
			blob(7, 5, 3, 2, col(95, 78, 55)); blob(13, 6, 2.5, 2, col(95, 78, 55))
			rect(7, 0, 5, 2, col(110, 92, 62))
			px(16, 4, col(240, 230, 190)); px(19, 6, col(80, 62, 45))
		"leafcutter_ant":
			rect(0, 3, 2, 2, col(180, 80, 45)); rect(2, 2, 2, 2, col(165, 70, 40)); rect(4, 3, 2, 2, col(190, 90, 50))
			px(1, 5, col(120, 55, 35)); px(3, 4, col(120, 55, 35)); px(5, 5, col(120, 55, 35))
		"ant_hill":
			blob(12, 10, 11, 5, col(150, 105, 70))
			rect(10, 9, 4, 3, col(70, 48, 35))
			for p: Array in [[4, 11], [19, 11], [7, 8], [17, 8]]:
				px(p[0], p[1], col(185, 140, 100))
		"mimic_cabbage":
			rect(2, 9, 10, 3, col(150, 190, 80))
			blob(3, 8, 2.8, 2.8, col(170, 205, 90)); blob(6, 7, 2.8, 2.8, col(155, 195, 80)); blob(9, 7, 2.8, 2.8, col(170, 205, 90))
			blob(11.5, 6, 2.5, 2.5, col(195, 220, 110))
			px(12, 5, col(40, 40, 35)); px(12, 7, col(215, 70, 60))
			rect(1, 10, 1, 2, col(130, 110, 60)); rect(5, 10, 1, 2, col(130, 110, 60)); rect(9, 10, 1, 2, col(130, 110, 60))
		"mimic_cabbage_disguise":
			blob(7, 7, 6.5, 5, col(105, 165, 85))
			blob(7, 6, 4, 3.5, col(160, 205, 115))
			blob(7, 6, 2, 2, col(205, 230, 150))
			line(7, 10, 7, 4, col(215, 235, 170)); line(3, 8, 6, 6, col(190, 220, 140)); line(11, 8, 8, 6, col(190, 220, 140))
		"black_kite":
			rect(1, 6, 4, 2, col(105, 75, 50)); px(1, 8, col(105, 75, 50)); px(4, 8, col(105, 75, 50))
			blob(6, 5, 6, 2.6, col(95, 66, 45)); blob(18, 5, 6, 2.6, col(95, 66, 45))
			blob(12, 6, 5, 3, col(130, 92, 62))
			blob(21, 6, 2.4, 2.4, col(205, 170, 120))
			px(23, 7, col(245, 200, 70)); px(21, 5, col(40, 35, 32))
		"deer":
			rect(4, 16, 2, 6, col(135, 95, 55)); rect(7, 17, 2, 5, col(125, 88, 50))
			rect(13, 16, 2, 6, col(135, 95, 55)); rect(16, 17, 2, 5, col(125, 88, 50))
			rect(15, 6, 3, 8, col(190, 140, 85))
			blob(10, 12, 8, 5, col(195, 142, 85))
			blob(18, 6, 3.6, 3, col(205, 155, 98))
			line(17, 3, 16, 0, col(225, 210, 175)); line(16, 2, 14, 1, col(225, 210, 175))
			line(19, 3, 20, 0, col(225, 210, 175)); line(20, 2, 21, 1, col(225, 210, 175))
			blob(2, 11, 1.6, 1.6, col(245, 240, 230))
			px(7, 11, col(235, 215, 185)); px(11, 10, col(235, 215, 185)); px(19, 6, col(40, 35, 32))
		"iron_jaw_beetle":
			for l: Array in [[4, 8, 1, 6], [4, 10, 1, 10], [4, 12, 2, 14], [14, 8, 17, 6], [14, 10, 17, 10], [14, 12, 16, 14]]:
				line(l[0], l[1], l[2], l[3], col(110, 78, 62))
			blob(9, 9, 6, 5, col(150, 98, 70))
			rect(9, 6, 1, 7, col(105, 68, 50))
			blob(9, 3.5, 3, 2.5, col(125, 82, 62))
			line(7, 3, 5, 2, col(175, 180, 190)); line(5, 2, 4, 0, col(175, 180, 190))
			line(11, 3, 13, 2, col(175, 180, 190)); line(13, 2, 14, 0, col(175, 180, 190))
		# ---- 第2弾の動物(右向き。左向きは表示側で反転)
		"root_mole":
			var mc: Color = col(92, 74, 68)
			rect(4, 10, 2, 2, mc.darkened(0.2)); rect(8, 10, 2, 2, mc.darkened(0.2))
			blob(7, 7, 6.2, 4, mc)
			blob(12.5, 9, 2.6, 2.2, col(215, 165, 150))
			px(14, 11, col(250, 235, 225)); px(12, 11, col(250, 235, 225)); px(13, 11, col(250, 235, 225))
			blob(13.5, 6.5, 2.2, 1.8, mc.lightened(0.08))
			rect(15, 7, 1, 1, col(240, 140, 150)); px(13, 5, col(30, 28, 30))
		"skunk":
			var kc: Color = col(48, 44, 52)
			rect(5, 9, 2, 3, kc.darkened(0.2)); rect(11, 9, 2, 3, kc.darkened(0.2))
			blob(3, 4, 3.4, 4.2, kc)
			line(3, 1, 3, 7, col(240, 238, 232)); line(4, 1, 4, 6, col(240, 238, 232))
			blob(8, 7, 5.6, 3.4, kc)
			line(4, 5, 12, 5, col(240, 238, 232)); line(5, 6, 11, 6, col(240, 238, 232))
			blob(13, 6, 2.6, 2.4, kc.lightened(0.05))
			line(12, 4, 14, 4, col(240, 238, 232)); px(14, 6, col(235, 150, 160)); px(13, 5, col(240, 220, 90))
			rect(12, 2, 1, 2, kc); rect(14, 2, 1, 2, kc)
		"hippo":
			var hc: Color = col(128, 118, 138)
			rect(6, 18, 5, 6, hc.darkened(0.25)); rect(14, 19, 5, 5, hc.darkened(0.2))
			rect(24, 18, 5, 6, hc.darkened(0.25)); rect(30, 19, 5, 5, hc.darkened(0.2))
			blob(20, 13, 17, 8, hc)
			blob(31, 13, 7, 5.6, hc.lightened(0.1))
			rect(27, 16, 12, 3, col(230, 150, 150)); rect(27, 16, 12, 1, col(250, 230, 220))
			px(28, 15, col(250, 245, 230)); px(37, 15, col(250, 245, 230))
			px(34, 9, col(45, 40, 45)); px(36, 11, col(60, 50, 60)); px(37, 11, col(60, 50, 60))
			rect(27, 6, 2, 2, hc.darkened(0.1)); rect(31, 5, 2, 2, hc.darkened(0.1))
			line(3, 11, 1, 14, hc.darkened(0.2))
		"honey_bear":
			var bc: Color = col(120, 82, 55)
			rect(6, 22, 5, 6, bc.darkened(0.25)); rect(13, 23, 5, 5, bc.darkened(0.15))
			rect(21, 22, 5, 6, bc.darkened(0.25)); rect(26, 23, 5, 5, bc.darkened(0.15))
			blob(15, 16, 13, 8.5, bc)
			blob(25, 11, 6, 5.5, bc.lightened(0.08))
			blob(28, 13, 3, 2.6, col(215, 175, 120))
			blob(21, 5, 2.2, 2.2, bc.darkened(0.1)); blob(27, 5, 2.2, 2.2, bc.darkened(0.1))
			blob(22, 16, 4.4, 3.8, col(240, 222, 165)); blob(22, 14.4, 4.0, 3.4, bc)
			rect(28, 15, 3, 1, col(252, 205, 60)); px(30, 16, col(252, 205, 60)); px(30, 17, col(252, 205, 60)); px(29, 17, col(252, 205, 60))
			px(29, 10, col(35, 28, 28)); px(31, 13, col(35, 28, 28))
			line(2, 14, 0, 16, bc.darkened(0.1))
		"sewer_rat":
			rect(3, 6, 1, 2, col(130, 115, 108)); rect(6, 6, 1, 2, col(130, 115, 108))
			line(2, 4, 0, 2, col(205, 150, 150))
			blob(4.5, 4.5, 3.6, 2.4, col(122, 112, 106))
			blob(8, 4, 2, 1.7, col(142, 130, 122))
			px(7, 2, col(200, 150, 150)); px(9, 4, col(235, 150, 160)); px(8, 3, col(30, 28, 28))
		"manhole":
			blob(4, 4, 3.6, 3.6, col(78, 80, 88))
			blob(4, 4, 2.4, 2.4, col(34, 34, 40))
			rect(2, 3, 4, 1, col(96, 98, 108)); rect(2, 5, 4, 1, col(96, 98, 108)); rect(3, 2, 1, 4, col(96, 98, 108)); rect(5, 2, 1, 4, col(96, 98, 108))
		"bat_flock":
			tri(0, 1, 3, 2, 2, 5, col(52, 44, 62)); tri(8, 1, 5, 2, 6, 5, col(52, 44, 62))
			tri(0, 1, 3, 2, 1, 3, col(72, 62, 84)); tri(8, 1, 5, 2, 7, 3, col(72, 62, 84))
			blob(4, 3, 1.3, 2, col(60, 50, 72))
			px(3, 0, col(60, 50, 72)); px(4, 0, col(60, 50, 72)); px(3, 3, col(235, 90, 80)); px(4, 3, col(235, 90, 80))
		"iron_rhino":
			var rc2: Color = col(128, 136, 150)
			rect(6, 22, 5, 6, rc2.darkened(0.3)); rect(13, 23, 5, 5, rc2.darkened(0.2))
			rect(24, 22, 5, 6, rc2.darkened(0.3)); rect(30, 23, 5, 5, rc2.darkened(0.2))
			blob(19, 15, 17, 9, rc2)
			for x: int in [8, 14, 20, 26]:
				rect(x, 8, 1, 14, rc2.darkened(0.3))
			rect(4, 12, 28, 1, rc2.lightened(0.2))
			blob(32, 16, 6.4, 5.6, rc2.lightened(0.08))
			tri(34, 12, 39, 4, 37, 13, col(214, 218, 228)); tri(30, 12, 33, 7, 33, 12, col(196, 200, 212))
			rect(28, 8, 3, 3, rc2.darkened(0.15)); px(34, 14, col(235, 190, 70))
			px(37, 18, col(60, 55, 60)); line(2, 12, 0, 16, rc2.darkened(0.2))
		"thunder_eel":
			for x: int in range(0, 19):
				var y: int = 2 + int(round(1.6 * sin(float(x) * 0.65)))
				rect(x, y, 2, 3, col(46, 66, 108) if x % 4 < 2 else col(58, 84, 130))
				if x % 3 == 0:
					px(x, y + 1, col(150, 238, 255))
			blob(19.5, 4.2, 2.4, 2.2, col(70, 98, 150))
			px(20, 3, col(255, 240, 120)); px(21, 5, col(140, 210, 240))
		"decoy_newt", "decoy_tail":
			rect(8, 6, 1, 2, col(60, 58, 70)); rect(11, 6, 1, 2, col(60, 58, 70))
			line(4, 4, 0, 2, col(62, 60, 72)); line(4, 5, 1, 4, col(62, 60, 72))
			blob(8, 4.2, 4.6, 2.2, col(62, 60, 74))
			rect(5, 5, 7, 2, col(218, 74, 56))
			blob(12, 4, 2, 1.8, col(76, 72, 88))
			px(12, 3, col(250, 240, 200)); px(13, 5, col(230, 90, 70))
		"mirror_lizard":
			rect(5, 7, 1, 3, col(86, 118, 86)); rect(10, 7, 1, 3, col(86, 118, 86))
			line(3, 6, 0, 8, col(96, 128, 94)); line(4, 5, 0, 7, col(96, 128, 94))
			blob(7, 5.5, 5.4, 2.6, col(102, 134, 98))
			for x: int in [4, 6, 8]:
				px(x, 4, col(70, 100, 72))
			blob(13.5, 5, 3.6, 3.2, col(196, 224, 240))
			blob(12.5, 4, 1.8, 1.4, col(250, 252, 255))
			rect(12, 6, 4, 1, col(150, 190, 220)); px(16, 4, col(40, 40, 50)); px(17, 5, col(150, 190, 220))
		"pistol_shrimp":
			var sc2: Color = col(226, 112, 84)
			line(7, 12, 5, 13, sc2.darkened(0.25)); line(9, 12, 8, 13, sc2.darkened(0.25)); line(11, 12, 11, 13, sc2.darkened(0.25))
			tri(0, 7, 3, 6, 3, 11, sc2.darkened(0.15))
			blob(6, 8, 3.4, 3, sc2); blob(10, 7.5, 3.4, 3, sc2.lightened(0.06))
			blob(14, 6.5, 2.4, 2.6, sc2.lightened(0.1))
			blob(17, 9.5, 3.2, 3.0, col(240, 140, 100)); rect(15, 10, 5, 1, col(180, 70, 55))
			tri(16, 6, 19, 5, 19, 8, col(240, 140, 100))
			line(15, 4, 17, 0, col(240, 200, 170)); line(14, 4, 13, 0, col(240, 200, 170))
			px(15, 4, col(30, 28, 30))
		"balloon_frog":
			rect(2, 9, 2, 2, col(96, 150, 78)); rect(7, 9, 2, 2, col(96, 150, 78))
			blob(5.5, 6.5, 4.4, 3.4, col(108, 168, 86))
			blob(8, 7.5, 2.8, 2.4, col(214, 230, 170))
			blob(3, 2.8, 1.8, 1.8, col(122, 184, 96)); blob(8, 2.8, 1.8, 1.8, col(122, 184, 96))
			px(3, 2, col(250, 245, 210)); px(8, 2, col(250, 245, 210)); px(3, 3, col(40, 38, 38)); px(8, 3, col(40, 38, 38))
		"glass_deer":
			var gc: Color = Color(0.72, 0.92, 1.0, 0.62)
			rect(4, 16, 2, 8, gc); rect(7, 17, 2, 7, gc.darkened(0.12))
			rect(14, 16, 2, 8, gc); rect(17, 17, 2, 7, gc.darkened(0.12))
			rect(15, 6, 3, 9, gc.lightened(0.1))
			blob(10, 13, 8, 4.8, gc)
			blob(17, 6, 3.4, 3, gc.lightened(0.1))
			var rb: Array = [Color(1.0, 0.45, 0.5, 0.85), Color(1.0, 0.85, 0.4, 0.85), Color(0.5, 1.0, 0.6, 0.85), Color(0.45, 0.8, 1.0, 0.85), Color(0.8, 0.55, 1.0, 0.85)]
			line(16, 3, 15, 0, rb[0]); line(15, 2, 13, 1, rb[1]); line(18, 3, 19, 0, rb[3]); line(19, 2, 21, 1, rb[4])
			for i: int in range(5):
				px(5 + i * 2, 11 + (i % 2) * 2, rb[i]); px(4 + i * 3, 23, rb[(i + 2) % 5])
			px(18, 6, col(60, 70, 90)); blob(2, 11, 1.6, 1.6, Color(0.95, 0.98, 1.0, 0.8))
		"hero":
			rect(2, 12, 2, 2, col(95, 75, 60)); rect(6, 12, 2, 2, col(95, 75, 60))
			box(2, 6, 6, 6, col(70, 150, 150))
			blob(5, 4, 2.8, 2.6, col(235, 195, 160))
			rect(1, 2, 8, 2, col(235, 205, 90)); rect(3, 0, 4, 2, col(235, 205, 90))
		"needle":
			rect(0, 1, 5, 1, col(230, 215, 170)); px(5, 1, col(250, 245, 225))
		"mud_ball":
			blob(3, 3, 2.8, 2.8, col(125, 95, 60))
		"seed_bag":
			blob(4, 5, 3.2, 3, col(205, 170, 110))
			rect(3, 1, 2, 2, col(150, 110, 70))
			px(3, 5, col(240, 215, 120)); px(5, 6, col(240, 215, 120))
		"strawberry_pickup":
			rect(3, 0, 3, 2, col(80, 160, 70))
			blob(4, 5, 3.2, 3, col(220, 60, 70))
			px(3, 4, col(250, 230, 130)); px(5, 6, col(250, 230, 130))

# ---------------------------------------------------------------- 植物
func crop(name: String) -> void:
	var g: Color = col(75, 165, 80)
	match name:
		"clover":
			line(5, 8, 5, 9, g.darkened(0.2))
			blob(3, 6, 2.6, 2.6, g); blob(7, 6, 2.6, 2.6, g); blob(5, 3, 2.6, 2.6, g.lightened(0.05))
		"four_leaf_clover":
			var f: Color = col(45, 195, 105)
			line(5, 7, 5, 9, f.darkened(0.3))
			blob(3, 4, 2.6, 2.6, f); blob(7, 4, 2.6, 2.6, f); blob(3, 7, 2.2, 2.2, f.lightened(0.1)); blob(7, 7, 2.2, 2.2, f.lightened(0.1))
			px(5, 5, f.lightened(0.5))
		"golden_clover":
			var y: Color = col(240, 200, 60)
			line(5, 8, 5, 9, y.darkened(0.4))
			blob(3, 6, 2.6, 2.6, y); blob(7, 6, 2.6, 2.6, y); blob(5, 3, 2.6, 2.6, y.lightened(0.1))
			px(5, 5, col(255, 245, 190))
		"golden_four_leaf":
			var y2: Color = col(245, 205, 70)
			line(6, 8, 6, 11, y2.darkened(0.4))
			blob(4, 5, 3, 3, y2); blob(8, 5, 3, 3, y2); blob(4, 8, 2.6, 2.6, y2.lightened(0.1)); blob(8, 8, 2.6, 2.6, y2.lightened(0.1))
			px(6, 6, col(255, 250, 210)); px(0, 1, col(255, 250, 210)); px(11, 2, col(255, 250, 210)); px(1, 10, col(255, 250, 210))
		"wasabi":
			line(4, 10, 3, 5, col(120, 175, 100)); line(8, 10, 9, 5, col(120, 175, 100)); line(6, 10, 6, 4, col(120, 175, 100))
			blob(3, 5, 2.8, 2.6, col(80, 165, 95)); blob(9, 5, 2.8, 2.6, col(80, 165, 95)); blob(6, 3, 2.8, 2.6, col(95, 180, 105))
			blob(6, 12, 3.2, 1.9, col(185, 210, 130))
		"giant_watermelon":
			blob(28, 24, 26, 15, col(60, 140, 70))
			for y: int in range(10, 40):
				for x: int in range(2, 54):
					var nx: float = (float(x) + 0.5 - 28.0) / 26.0
					var ny: float = (float(y) + 0.5 - 24.0) / 15.0
					if nx * nx + ny * ny <= 1.0 and (x + int(float(y) * 0.2)) % 9 < 3:
						px(x, y, col(35, 100, 55))
			blob(19, 17, 6, 3, col(110, 190, 110))
			rect(27, 7, 3, 3, col(110, 130, 60)); line(29, 7, 32, 4, col(100, 150, 70))
			blob(10, 9, 4, 2.5, g); blob(47, 9, 4, 2.5, g)
		"oleander":
			rect(11, 22, 2, 10, col(110, 85, 60))
			for p: Array in [[6, 20], [17, 20], [12, 16], [5, 12], [18, 12], [12, 9]]:
				blob(float(p[0]), float(p[1]), 5, 4, col(55, 130, 85))
			for p: Array in [[7, 8], [14, 6], [4, 14], [19, 15], [12, 12], [9, 17], [16, 20]]:
				blob(float(p[0]), float(p[1]), 2.4, 2.4, col(235, 120, 165))
				px(p[0], p[1], col(255, 225, 120))
		"edamame":
			line(7, 13, 7, 5, g.darkened(0.2))
			blob(3, 5, 3, 2.4, g); blob(11, 5, 3, 2.4, g); blob(7, 3, 3, 2.4, g.lightened(0.05))
			line(5, 9, 4, 12, col(150, 200, 90)); line(9, 9, 10, 12, col(150, 200, 90))
			rect(3, 9, 2, 3, col(145, 200, 85)); rect(9, 8, 2, 3, col(145, 200, 85))
		"sunflower":
			line(7, 10, 7, 23, g.darkened(0.2)); line(7, 17, 11, 15, g)
			blob(4, 18, 3.2, 2, g); blob(10, 15, 3, 2, g)
			blob(7, 6, 6.4, 6.2, col(250, 205, 40))
			blob(7, 6, 3.2, 3.2, col(105, 65, 30))
		"tomato":
			line(5, 6, 5, 17, col(60, 130, 60))
			blob(3, 5, 3, 2.4, g); blob(9, 4, 3, 2.4, g); blob(6, 2, 3, 2.2, g)
			blob(4, 10, 2.6, 2.6, col(225, 65, 55)); blob(8, 13, 2.6, 2.6, col(225, 65, 55)); blob(8, 8, 2.2, 2.2, col(235, 85, 60))
		"lotus":
			blob(11, 8, 10, 3.6, col(70, 160, 115))
			line(11, 8, 11, 8, col(40, 100, 75)); rect(15, 7, 5, 1, col(40, 100, 75))
			blob(11, 4, 3.2, 3.2, col(250, 170, 195)); blob(8, 5, 2, 2.4, col(245, 150, 180)); blob(14, 5, 2, 2.4, col(245, 150, 180))
			px(11, 3, col(250, 225, 110))
		"corn":
			line(6, 5, 6, 25, col(95, 160, 70)); line(7, 5, 7, 25, col(80, 145, 65))
			line(6, 14, 1, 9, g); line(7, 17, 11, 12, g); line(6, 20, 2, 17, g.darkened(0.1))
			box(8, 10, 3, 6, col(245, 205, 65))
			line(6, 4, 3, 0, col(215, 190, 100)); line(6, 4, 7, 0, col(215, 190, 100)); line(7, 4, 10, 1, col(215, 190, 100))
		"pumpkin":
			blob(11, 10, 10, 6, col(240, 140, 40))
			for x: int in [6, 9, 12, 15]:
				rect(x, 6, 1, 8, col(195, 100, 30))
			rect(10, 3, 2, 3, col(95, 130, 60)); blob(5, 4, 3, 2, g)
		"mint":
			line(5, 9, 5, 4, g.darkened(0.25))
			blob(3, 7, 2, 1.6, col(95, 205, 130)); blob(7, 6, 2, 1.6, col(95, 205, 130)); blob(3, 4, 2, 1.6, col(95, 205, 130)); blob(7, 3, 2, 1.6, col(120, 220, 150)); blob(5, 1.5, 1.8, 1.5, col(120, 220, 150))
		"cactus":
			box(4, 3, 5, 15, col(70, 155, 90))
			rect(0, 8, 4, 2, col(70, 155, 90)); rect(0, 5, 2, 5, col(70, 155, 90))
			rect(9, 10, 3, 2, col(70, 155, 90)); rect(10, 7, 2, 5, col(70, 155, 90))
			for p: Array in [[5, 6], [7, 10], [5, 13], [1, 6], [11, 8]]:
				px(p[0], p[1], col(240, 235, 170))
			px(6, 2, col(240, 120, 160)); px(5, 2, col(240, 120, 160)); px(6, 1, col(240, 120, 160))
		"grape":
			line(6, 2, 6, 10, col(120, 95, 60)); line(6, 9, 1, 4, col(120, 95, 60))
			blob(3, 4, 3, 2.4, g); blob(9, 3, 3, 2.4, g); blob(6, 1, 3, 1.8, g.lightened(0.05))
			for p: Array in [[4, 12], [8, 12], [6, 14], [3, 15], [9, 15], [6, 17], [5, 19.0]]:
				blob(float(p[0]), float(p[1]), 2, 2, col(125, 65, 150))
		"strawberry":
			blob(3, 3, 2.6, 2, g); blob(7, 3, 2.6, 2, g); blob(5, 1.5, 2.2, 1.6, g.lightened(0.05))
			blob(3, 6, 1.9, 1.9, col(225, 55, 70)); blob(7, 5.5, 1.9, 1.9, col(235, 75, 80))
			px(5, 4, col(250, 245, 230))
		"lavender":
			for l: Array in [[3, 13, 3, 6], [5, 13, 5, 3], [7, 13, 7, 5]]:
				line(l[0], l[1], l[2], l[3], col(120, 160, 110))
			rect(2, 3, 2, 5, col(165, 130, 225)); rect(4, 1, 2, 5, col(185, 150, 240)); rect(6, 3, 2, 5, col(165, 130, 225))
			px(3, 8, col(210, 190, 250))
		"garlic":
			line(4, 7, 3, 0, col(105, 175, 90)); line(6, 7, 7, 1, col(105, 175, 90)); line(7, 1, 8, 0, col(105, 175, 90))
			blob(5, 9, 3.6, 3, col(240, 232, 215))
			line(3, 8, 3, 10, col(210, 200, 180)); line(7, 8, 7, 10, col(210, 200, 180)); px(5, 11, col(190, 160, 140))
		"bamboo":
			box(2, 0, 3, 32, col(105, 180, 90)); box(6, 4, 3, 28, col(130, 200, 105))
			for y: int in [7, 15, 23, 30]:
				rect(2, y, 3, 1, col(65, 130, 65))
			for y: int in [11, 19, 27]:
				rect(6, y, 3, 1, col(75, 145, 70))
			blob(7, 3, 2.5, 1.4, g); blob(2, 1, 2, 1.2, g)
		"flytrap":
			line(7, 6, 7, 11, col(70, 140, 80)); line(3, 11, 5, 8, col(70, 140, 80)); line(11, 11, 9, 8, col(70, 140, 80))
			blob(4, 5, 4, 3.4, col(90, 175, 90)); blob(10, 5, 4, 3.4, col(90, 175, 90))
			rect(3, 4, 3, 2, col(200, 60, 80)); rect(8, 4, 3, 2, col(200, 60, 80))
			for x: int in [2, 4, 9, 11]:
				px(x, 3, col(240, 240, 215))
		"potato":
			blob(6, 8, 5.5, 2, col(110, 80, 55))
			blob(4, 4, 3, 2.4, col(85, 160, 75)); blob(8, 3, 3, 2.4, col(95, 170, 80)); blob(6, 5, 2.6, 2, col(75, 145, 70))
			px(7, 1, col(245, 240, 250))
		"rice":
			for l: Array in [[2, 13, 2, 4], [4, 13, 4, 3], [6, 13, 6, 5]]:
				line(l[0], l[1], l[2], l[3], col(150, 185, 85))
			line(2, 4, 4, 2, col(215, 200, 90)); line(4, 3, 6, 2, col(215, 200, 90)); line(6, 5, 7, 4, col(215, 200, 90))
			px(4, 2, col(245, 225, 120)); px(6, 2, col(245, 225, 120)); px(7, 5, col(245, 225, 120))
		"tea":
			blob(10, 11, 9, 7, col(45, 115, 70))
			blob(7, 8, 5, 4, col(55, 135, 80))
			for p: Array in [[5, 6], [10, 5], [14, 8], [8, 11], [13, 12], [4, 11]]:
				px(p[0], p[1], col(150, 215, 110)); px(p[0] + 1, p[1], col(130, 200, 100))
			rect(8, 16, 4, 2, col(100, 75, 55))
		"sakura":
			rect(18, 26, 4, 22, col(105, 75, 55)); rect(18, 26, 1, 22, col(130, 95, 70))
			line(19, 34, 8, 24, col(105, 75, 55)); line(21, 33, 33, 23, col(105, 75, 55))
			blob(20, 16, 15, 12, col(70, 140, 80)); blob(10, 22, 8, 7, col(65, 130, 75)); blob(31, 22, 8, 7, col(65, 130, 75))
			blob(15, 11, 6, 4, col(100, 170, 100))
		"dokudami":
			blob(3, 6, 3, 3, col(55, 130, 95)); blob(7, 6, 3, 3, col(55, 130, 95)); blob(5, 7, 2.6, 2, col(70, 150, 105))
			rect(5, 3, 1, 4, col(110, 90, 130))
			px(5, 1, col(250, 250, 240)); px(4, 2, col(250, 250, 240)); px(6, 2, col(250, 250, 240)); px(5, 2, col(240, 220, 110))
		"aloe":
			tri(6, 2, 4, 13, 8, 13, col(85, 175, 130))
			tri(1, 5, 2, 13, 6, 13, col(70, 155, 115))
			tri(11, 5, 6, 13, 10, 13, col(70, 155, 115))
			line(6, 4, 6, 12, col(150, 215, 170))
			rect(3, 13, 6, 1, col(110, 80, 60))
		"pepper":
			line(5, 6, 5, 13, col(75, 135, 70))
			blob(3, 4, 2.8, 2.2, g); blob(8, 3, 2.8, 2.2, g)
			tri(2, 7, 4, 7, 3, 12, col(220, 40, 35)); tri(6, 8, 8, 8, 7, 13, col(235, 60, 40))
		"glow_moss":
			blob(5, 4, 4.8, 2.6, col(70, 175, 140))
			for p: Array in [[2, 3], [5, 2], [8, 3], [4, 4]]:
				px(p[0], p[1], col(185, 250, 235))
		# ---- 第2弾の栽培植物
		"evening_primrose":
			line(6, 6, 6, 19, col(100, 150, 80)); line(6, 14, 2, 11, g); line(6, 16, 10, 13, g)
			blob(2, 11, 2.2, 1.5, g); blob(10, 13, 2.2, 1.5, g)
			blob(6, 4, 3.8, 3.4, col(250, 232, 120)); blob(6, 4, 1.4, 1.4, col(250, 205, 70))
			px(2, 3, col(255, 245, 170)); px(10, 3, col(255, 245, 170)); px(6, 0, col(255, 245, 170))
		"dandelion":
			tri(0, 12, 2, 8, 4, 12, g.darkened(0.1)); tri(5, 12, 7, 7, 9, 12, g); tri(2, 12, 4, 9, 6, 12, g.lightened(0.05))
			line(5, 11, 5, 5, col(110, 160, 90))
			blob(5, 3, 3.4, 3.2, col(244, 244, 240)); blob(5, 3, 1.4, 1.4, col(250, 214, 70))
			px(2, 1, col(255, 255, 255)); px(8, 2, col(255, 255, 255)); px(5, 0, col(255, 255, 255))
		"mimosa":
			line(6, 9, 6, 4, g.darkened(0.25))
			for l: Array in [[6, 7, 1, 5], [6, 7, 11, 5], [6, 5, 2, 2], [6, 5, 10, 2]]:
				line(l[0], l[1], l[2], l[3], col(120, 190, 100))
				line(l[0], l[1] + 1, l[2], l[3] + 1, col(88, 160, 84))
			blob(6, 2, 2, 2, col(240, 150, 200))
		"kudzu":
			rect(6, 9, 2, 5, col(100, 150, 70))
			blob(4, 8, 4.2, 3.6, col(56, 138, 70)); blob(10, 8, 4.2, 3.6, col(62, 148, 74)); blob(7, 4, 4.4, 3.8, col(72, 160, 82))
			line(7, 12, 2, 12, col(90, 135, 70)); line(7, 12, 13, 12, col(90, 135, 70))
			px(7, 3, col(140, 200, 120)); px(4, 7, col(120, 185, 105)); px(10, 7, col(120, 185, 105))
			px(2, 1, col(160, 90, 170)); px(12, 2, col(160, 90, 170))
		"loofah":
			rect(1, 0, 2, 24, col(150, 112, 74))
			for i: int in range(6):
				var vy: int = 2 + i * 3
				line(1 + (i % 2) * 2, vy, 3 - (i % 2) * 2, vy + 2, col(76, 150, 78))
			blob(6, 5, 2.6, 1.8, g); blob(9, 11, 2.6, 1.8, g)
			box(6, 12, 4, 11, col(128, 178, 90)); rect(7, 13, 1, 9, col(162, 205, 120))
			px(4, 3, col(250, 220, 70)); px(5, 3, col(250, 220, 70))
		"hinoki":
			rect(16, 46, 4, 10, col(122, 82, 58)); rect(16, 46, 1, 10, col(150, 104, 74))
			tri(18, 28, 4, 50, 32, 50, col(40, 104, 70))
			tri(18, 16, 6, 38, 30, 38, col(46, 116, 76))
			tri(18, 6, 8, 26, 28, 26, col(54, 130, 84))
			tri(18, 0, 11, 14, 25, 14, col(66, 146, 94))
			for p: Array in [[12, 40], [24, 42], [16, 30], [22, 24], [18, 12], [14, 46]]:
				px(p[0], p[1], col(120, 190, 130))
		"apple":
			rect(12, 22, 4, 13, col(108, 78, 56)); rect(12, 22, 1, 13, col(136, 100, 72))
			rect(8, 34, 12, 2, col(92, 66, 48))
			blob(14, 12, 13, 10, col(66, 142, 80)); blob(7, 17, 6, 5, col(60, 132, 76)); blob(21, 17, 6, 5, col(60, 132, 76))
			blob(10, 6, 5, 3, col(98, 172, 104))
			for p: Array in [[8, 10], [17, 8], [20, 15], [11, 17], [15, 14], [5, 17], [23, 12]]:
				blob(float(p[0]), float(p[1]), 2.2, 2.2, col(222, 52, 56)); px(p[0] - 1, p[1] - 1, col(250, 150, 140))
		"balsam":
			line(5, 13, 5, 4, col(112, 168, 96))
			blob(2, 8, 2.6, 1.6, g); blob(8, 6, 2.6, 1.6, g); blob(3, 11, 2.4, 1.5, g.darkened(0.08))
			blob(7, 10, 1.6, 2.4, col(150, 205, 110))
			blob(5, 2, 2.2, 2.0, col(240, 90, 140)); blob(8, 3, 1.5, 1.5, col(250, 130, 170)); blob(2, 3, 1.5, 1.5, col(250, 130, 170))
			px(5, 2, col(255, 235, 150))

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_ASSETS))
	var enemies: Dictionary = (JSON.parse_string(FileAccess.get_file_as_string("res://data/content_pack/enemies.json")) as Dictionary).enemies
	var crops: Dictionary = (JSON.parse_string(FileAccess.get_file_as_string("res://data/content_pack/crops.json")) as Dictionary).crops
	var n: int = 0
	for k: String in enemies:
		var im: Array = enemies[k].image
		begin(k, int(im[0]), int(im[1]))
		enemy(k)
		finish()
		n += 1
	for k: String in crops:
		var im2: Array = crops[k].image
		begin(k, int(im2[0]), int(im2[1]))
		crop(k)
		finish()
		n += 1
	# 付属・擬態・小物(カタログ4節)。足元は中央下、小物は中央
	for a: Array in [["junk_crab_shell", 16, 12], ["junk_pile", 16, 12], ["moss_turtle_bush", 28, 20], ["grass_snake_grass", 20, 8],
			["mimic_cabbage_disguise", 14, 12], ["hero", 10, 14]]:
		begin(a[0], a[1], a[2])
		enemy(a[0])
		finish()
		n += 1
	for a: Array in [["needle", 6, 3], ["mud_ball", 6, 6], ["seed_bag", 8, 8], ["strawberry_pickup", 8, 8]]:
		begin(a[0], a[1], a[2], [a[1] / 2, a[2] / 2])
		enemy(a[0])
		finish()
		n += 1
	var f: FileAccess = FileAccess.open(OUT_META, FileAccess.WRITE)
	f.store_string(JSON.stringify({"version": 1, "note": "仮スプライトのメタ情報。size=画像px、foot=足元基準(画像内px)。占有・当たり判定とは別データ。", "sprites": meta}, " ", false))
	f.close()
	print("gen_sprites: ", n, " images")
	quit(0)
