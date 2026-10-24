extends RefCounted
## 確認画面の描画(真上からの2D、1マス8px、輪郭線なし)。512x288の区画 + 右128pxのパネル + 下72pxの情報欄。
## 状態は小さな記号で表し、状態別の画像は作らない。足元基準で接地させ、Y順に重ねる。
const Bank: GDScript = preload("res://scripts/content_pack/lab/sprite_bank.gd")
const TinyFont: GDScript = preload("res://scripts/content_pack/lab/tiny_font.gd")
const Game: GDScript = preload("res://scripts/content_pack/lab/lab_game.gd")
const Host: GDScript = preload("res://scripts/content_pack/lab/lab_host.gd")
const Grid: GDScript = preload("res://scripts/content_pack/grid_math.gd")

const CELL: int = 8
const S: float = 2.0                  # 論理px(1マス=4px)から画面pxへ
const MAP_W: int = 512
const MAP_H: int = 288
const PANEL_X: int = 512
const INFO_Y: int = 288

const ICONS: Dictionary = {
	"bang": [".#.", ".#.", ".#.", "...", ".#."],
	"star": ["..#..", ".###.", "#####", ".###.", ".#.#."],
	"drop": [".#.", "###", "###", ".#."],
	"note": ["..##", "..#.", "..#.", "##..", "##.."],
	"anger": ["#...#", ".#.#.", "..#..", ".#.#.", "#...#"],
	"spark": [".#.", "###", ".#."],
	"bubble": [".#.", "#.#", ".#."],
	"wave": ["#...#", ".#.#.", "..#.."],
	"zig": ["#...", ".#..", "..#.", ".#..", "#..."],
}

var bank: RefCounted
var font: RefCounted
var terrain_tex: ImageTexture = null

func _init() -> void:
	bank = Bank.new()
	font = TinyFont.new()

# ---------------------------------------------------------------- 道具
func rc(ci: CanvasItem, x: float, y: float, w: float, h: float, c: Color) -> void:
	ci.draw_rect(Rect2(floorf(x), floorf(y), w, h), c)

func icon(ci: CanvasItem, name: String, pos: Vector2, c: Color) -> void:
	var rows: Array = ICONS[name]
	for y: int in range(rows.size()):
		var row: String = rows[y]
		for x: int in range(row.length()):
			if row[x] == "#":
				rc(ci, pos.x + x, pos.y + y, 1, 1, c)

func shadow(ci: CanvasItem, center: Vector2, rx: int) -> void:
	var a: Color = Color(0, 0, 0, 0.28)
	rc(ci, center.x - rx, center.y, rx * 2, 1, a)
	rc(ci, center.x - rx + 1, center.y + 1, rx * 2 - 2, 1, a)

func dotted(ci: CanvasItem, a: Vector2, b: Vector2, c: Color, step: float = 3.0) -> void:
	var n: int = maxi(1, int(a.distance_to(b) / step))
	for i: int in range(n + 1):
		var p: Vector2 = a.lerp(b, float(i) / float(n))
		rc(ci, p.x, p.y, 1, 1, c)

func ring(ci: CanvasItem, center: Vector2, r: float, c: Color, dash: int = 1) -> void:
	var n: int = maxi(12, int(r * 2.0))
	for i: int in range(n):
		if dash > 1 and (i / dash) % 2 == 1:
			continue
		var p: Vector2 = center + Vector2.from_angle(TAU * float(i) / float(n)) * r
		rc(ci, p.x, p.y, 1, 1, c)

func hpbar(ci: CanvasItem, top_center: Vector2, frac: float) -> void:
	var w: int = 12
	rc(ci, top_center.x - w / 2, top_center.y, w, 2, Color(0.15, 0.1, 0.1))
	rc(ci, top_center.x - w / 2, top_center.y, maxf(1.0, floorf(w * clampf(frac, 0.0, 1.0))), 2, Color(0.4, 0.9, 0.35) if frac > 0.4 else Color(0.95, 0.3, 0.25))

## スプライトを足元基準で描く。戻り値は描いた矩形(画面px)。opts: flip, rot, mod, scale, gray
func spr(ci: CanvasItem, name: String, foot: Vector2, o: Dictionary = {}) -> Rect2:
	var t: Texture2D = bank.gray_tex(name) if bool(o.get("gray", false)) else bank.tex(name)
	var sz: Vector2i = bank.size_of(name)
	var sc: float = float(o.get("scale", 1.0))
	var xs: float = float(o.get("xs", 1.0))
	var w: float = floorf(float(sz.x) * sc * xs)
	var h: float = floorf(float(sz.y) * sc)
	var fo: Vector2 = Vector2(floorf(bank.foot_of(name).x * sc * xs), floorf(bank.foot_of(name).y * sc))
	var tl: Vector2 = (foot - fo).floor()
	var mod: Color = o.get("mod", Color.WHITE)
	if t == null:
		rc(ci, tl.x, tl.y, w, h, Color(1, 0, 1))
		return Rect2(tl, Vector2(w, h))
	var rot: float = float(o.get("rot", 0.0))
	if rot != 0.0:
		ci.draw_set_transform(tl + Vector2(w, h) * 0.5, rot, Vector2.ONE)
		ci.draw_texture_rect(t, Rect2(-w * 0.5, -h * 0.5, w, h), false, mod)
		ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	elif int(o.get("clip_x0", 0)) > 0:
		# 左端(クリップ分)を描かない。イモリの尾の再生中に使う(向きの反転に対応)
		var cl: int = int(o.clip_x0)
		var cw: float = floorf(float(sz.x - cl) * sc * xs)
		var cx: float = floorf(float(cl) * sc * xs)
		var src: Rect2 = Rect2(float(cl), 0.0, float(sz.x - cl), float(sz.y))
		if bool(o.get("flip", false)):
			ci.draw_texture_rect_region(t, Rect2(tl.x + w - cx, tl.y, -cw, h), src, mod)
		else:
			ci.draw_texture_rect_region(t, Rect2(tl.x + cx, tl.y, cw, h), src, mod)
	elif bool(o.get("flip", false)):
		ci.draw_texture_rect(t, Rect2(tl.x + w, tl.y, -w, h), false, mod)
	else:
		ci.draw_texture_rect(t, Rect2(tl, Vector2(w, h)), false, mod)
	return Rect2(tl, Vector2(w, h))

# ---------------------------------------------------------------- 地形
func _hash(x: int, y: int) -> int:
	return (x * 73856093 ^ y * 19349663) & 0x7fffffff

func build_terrain(g: RefCounted) -> void:
	var h: RefCounted = g.host
	var im: Image = Image.create(MAP_W, MAP_H, false, Image.FORMAT_RGBA8)
	for cy: int in range(Host.H):
		for cx: int in range(Host.W):
			var c: Vector2i = Vector2i(cx, cy)
			var t: int = h._t(c)
			var base: Color
			match t:
				Host.GREEN: base = Color(0.31, 0.55, 0.29)
				Host.WASTE: base = Color(0.60, 0.49, 0.35)
				Host.BUILDING: base = Color(0.52, 0.48, 0.52)
				Host.WATER: base = Color(0.20, 0.38, 0.62)
				Host.SHALLOW: base = Color(0.36, 0.58, 0.74)
				Host.CLEAN: base = Color(0.30, 0.72, 0.82)
				_: base = Color(0.45, 0.36, 0.28)
			if t == Host.GREEN:
				var st: String = h.grass_stage(c)
				if st == "wasteland":
					base = Color(0.60, 0.49, 0.35)
				elif st == "seed" or st == "sprout":
					base = Color(0.52, 0.47, 0.32)
			if h.is_shade(c):
				base = base.darkened(0.22)
			for py: int in range(CELL):
				for px: int in range(CELL):
					var col: Color = base
					var hv: int = _hash(cx * CELL + px, cy * CELL + py) % 100
					if t == Host.GREEN or t == Host.WASTE:
						if hv < 7:
							col = base.lightened(0.10)
						elif hv < 12:
							col = base.darkened(0.10)
					elif t == Host.WATER or t == Host.SHALLOW or t == Host.CLEAN:
						if (px + py * 2 + cx * 3) % 8 == 0 and hv < 60:
							col = base.lightened(0.18)
					elif t == Host.BUILDING:
						if py == 0 and not h.is_building(c + Vector2i(0, -1)):
							col = base.lightened(0.2)
						elif py == CELL - 1 and not h.is_building(c + Vector2i(0, 1)):
							col = base.darkened(0.25)
						elif (px == 0 and not h.is_building(c + Vector2i(-1, 0))):
							col = base.lightened(0.1)
					elif t == Host.JUNK and hv < 25:
						col = base.darkened(0.2)
					im.set_pixel(cx * CELL + px, cy * CELL + py, col)
	terrain_tex = ImageTexture.create_from_image(im)

# ---------------------------------------------------------------- 全体
func draw(ci: CanvasItem, g: RefCounted, ui: Dictionary) -> void:
	if terrain_tex == null or g.terrain_dirty:
		build_terrain(g)
		g.terrain_dirty = false
	var t: float = float(ui.get("t", 0.0))
	ci.draw_texture(terrain_tex, Vector2.ZERO)
	_ground_effects(ci, g, t)
	_ground_effects2(ci, g, t)
	_range_previews(ci, g)
	_sprites(ci, g, t)
	_effects(ci, g, t)
	if not g.host.day:
		rc(ci, 0, 0, MAP_W, MAP_H, Color(0.08, 0.1, 0.3, 0.45))
		_glow_moss(ci, g, t)
	_cursor(ci, g, ui)
	if g.debug_flash_until > g.elapsed:
		font.draw_shadow(ci, Vector2(4, 4), "DEBUG OPERATION", Color(1.0, 0.45, 0.35))
	_panel(ci, g, ui)
	_info(ci, g)

# ---------------------------------------------------------------- 地面の表示(粘液・ガス・泥・範囲)
func _ground_effects(ci: CanvasItem, g: RefCounted, t: float) -> void:
	var es: RefCounted = g.pack.enemies
	for s: Dictionary in es.slime_cells():
		var c: Vector2i = s.cell
		rc(ci, c.x * CELL, c.y * CELL, CELL, CELL, Color(0.75, 0.95, 0.35, 0.5))
		rc(ci, c.x * CELL + 2, c.y * CELL + 2, 2, 1, Color(1, 1, 0.8, 0.8))
	for gc: Dictionary in es.gas_clouds():
		var p: Vector2 = Vector2(gc.pos) * S
		var r: float = float(gc.radius) * S
		ci.draw_circle(p, r, Color(0.55, 0.7, 0.3, 0.32))
		for i: int in range(5):
			var a: float = float(i) * 1.3 + t * 0.8
			rc(ci, p.x + cos(a) * r * 0.5, p.y + sin(a * 1.1) * r * 0.5, 2, 2, Color(0.8, 0.95, 0.5, 0.7))

func _ground_effects2(ci: CanvasItem, g: RefCounted, t: float) -> void:
	var es: RefCounted = g.pack.enemies
	var cs: RefCounted = g.pack.crops
	# 動的な日陰(ヒノキ)
	for c: Vector2i in cs.dynamic_shade_cells():
		rc(ci, c.x * CELL, c.y * CELL, CELL, CELL, Color(0.0, 0.05, 0.15, 0.30))
		rc(ci, c.x * CELL + 1, c.y * CELL + 1, 2, 1, Color(0.6, 0.7, 0.9, 0.5))
	# 濡れたマス(6秒、ウナギの伝導)
	for c: Vector2i in g.pack.common.wet_cells():
		rc(ci, c.x * CELL, c.y * CELL, CELL, CELL, Color(0.25, 0.5, 0.95, 0.38))
		rc(ci, c.x * CELL + 2 + (int(t * 3.0) % 3), c.y * CELL + 5, 2, 1, Color(0.8, 0.92, 1.0, 0.85))
	# クズの根(つるが地面を這う)
	for rcell: Vector2i in cs.root_cells():
		var rx: float = float(rcell.x * CELL)
		var ry: float = float(rcell.y * CELL)
		rc(ci, rx + 1, ry + 3, 6, 2, Color(0.22, 0.45, 0.2))
		rc(ci, rx + 3, ry + 1, 2, 6, Color(0.27, 0.52, 0.24))
		rc(ci, rx + 5, ry + 2, 2, 1, Color(0.5, 0.75, 0.4))
	# 落果
	for f: Dictionary in cs.fruit_list():
		var fp: Vector2 = Vector2(f.pos) * S
		shadow(ci, fp + Vector2(0, 3), 2)
		rc(ci, fp.x - 2, fp.y - 2, 4, 4, Color(0.85, 0.2, 0.2))
		rc(ci, fp.x - 1, fp.y - 2, 1, 1, Color(1.0, 0.7, 0.65))
		rc(ci, fp.x, fp.y - 3, 1, 1, Color(0.35, 0.6, 0.25))
	# マンホール網(同じ網は点線でつなぐ)と、モグラの盛り土
	var nets: Dictionary = {}
	for e: Dictionary in es.enemies:
		if not bool(e.alive):
			continue
		if str(e.kind) == "manhole":
			var mp: Vector2 = Vector2(e.pos) * S
			var closed: bool = str(e.state) == "closed"
			spr(ci, "manhole", Vector2(mp.x, mp.y + 4.0), {"mod": Color(0.7, 0.85, 0.7) if closed else Color.WHITE})
			if not nets.has(int(e.net_id)):
				nets[int(e.net_id)] = []
			(nets[int(e.net_id)] as Array).append(mp)
		elif str(e.kind) == "root_mole":
			for m: Dictionary in e.mounds:
				var q: Vector2 = Vector2(m.pos) * S
				var fade: float = clampf((float(m.until) - es.time) / 2.0, 0.25, 1.0)
				rc(ci, q.x - 2, q.y - 1, 4, 2, Color(0.42, 0.3, 0.2, fade))
				rc(ci, q.x - 1, q.y - 2, 2, 1, Color(0.58, 0.44, 0.3, fade))
	for k: Variant in nets.keys():
		var pts: Array = nets[k]
		for i: int in range(pts.size() - 1):
			dotted(ci, pts[i], pts[i + 1], Color(0.55, 0.55, 0.65, 0.55), 5.0)
	# 臭気の雲(扇形)と酸
	for o: Dictionary in es.odor_clouds():
		var op: Vector2 = Vector2(o.pos) * S
		var od: Vector2 = Vector2(o.dir)
		var len_s: float = float(o.length) * S
		var half: float = deg_to_rad(float(o.half_deg))
		var pts2: PackedVector2Array = PackedVector2Array([op])
		for i: int in range(9):
			var a: float = lerpf(-half, half, float(i) / 8.0)
			pts2.append(op + od.rotated(a) * len_s)
		ci.draw_colored_polygon(pts2, Color(0.72, 0.78, 0.3, 0.34))
		for i: int in range(6):
			var a2: float = float(i) * 1.7 + t * 0.9
			var rr: float = len_s * (0.25 + 0.6 * fmod(float(i) * 0.37 + t * 0.2, 1.0))
			var q2: Vector2 = op + od.rotated(sin(a2) * half * 0.8) * rr
			rc(ci, q2.x, q2.y, 2, 2, Color(0.88, 0.95, 0.5, 0.7))
	for a: Dictionary in es.acid_pools():
		var ap: Vector2 = Vector2(a.pos) * S
		var ar: float = float(a.radius) * S
		ci.draw_circle(ap, ar, Color(0.45, 0.85, 0.25, 0.30))
		ring(ci, ap, ar, Color(0.7, 1.0, 0.4, 0.8), 2)
		for i: int in range(4):
			var a3: float = float(i) * 1.6 + t * 1.3
			rc(ci, ap.x + cos(a3) * ar * 0.55, ap.y + sin(a3 * 1.2) * ar * 0.55, 2, 2, Color(0.85, 1.0, 0.55, 0.8))

func _range_previews(ci: CanvasItem, g: RefCounted) -> void:
	var shown: Array = []
	if g.tool == "crop" and g.host.in_bounds(g.hover_cell):
		var cell: Vector2i = g.crop_cell_for(g.sel_crop, g.hover_cell)
		shown.append([g.sel_crop, Rect2i(cell, g.pack.crops.size_of(g.sel_crop))])
	elif g.tool == "enemy" and g.sel_enemy == "honeybee_hive" and g.host.in_bounds(g.hover_cell):
		shown.append(["honeybee_hive", Rect2i(g.hover_cell, Vector2i.ONE)])
	if g.sel_crop_id > 0:
		var c: Dictionary = g.pack.crops.get_crop(g.sel_crop_id)
		if not c.is_empty():
			shown.append([str(c.kind), Rect2i(c.cell, c.size)])
	for it: Array in shown:
		var kind: String = it[0]
		if not Game.RANGE_PREVIEW.has(kind):
			continue
		var rp: Array = Game.RANGE_PREVIEW[kind]
		var r: Rect2i = it[1]
		var col: Color = rp[1]
		col.a = 0.85
		var ex: Rect2i = Grid.expanded(r, int(rp[0]))
		for cy: int in range(ex.position.y, ex.end.y):
			for cx: int in range(ex.position.x, ex.end.x):
				var c2: Vector2i = Vector2i(cx, cy)
				if not g.host.in_bounds(c2) or r.has_point(c2):
					continue
				rc(ci, cx * CELL + 3, cy * CELL + 3, 2, 2, col)

# ---------------------------------------------------------------- スプライト(Y順)
func _sprites(ci: CanvasItem, g: RefCounted, t: float) -> void:
	var es: RefCounted = g.pack.enemies
	var items: Array = []
	for c: Dictionary in g.pack.crops.crops:
		items.append([float((c.cell.y + c.size.y) * CELL), "crop", c])
	for e: Dictionary in es.enemies:
		if not bool(e.alive):
			continue
		var y: float = float(e.pos.y) * S + 3.0
		var hab: String = str(es.def_of(e).get("habitat", "land"))
		if hab == "air" and str(e.state) not in ["ground", "climb", "roost", "low", "dive"]:
			y += 400.0
		if str(e.kind) == "balloon_frog" and str(e.state) in ["inflate", "float"]:
			y += 400.0
		if str(e.kind) == "manhole":
			continue
		if str(es.def_of(e).get("size", "")) != "":
			y = float(es.rect_of_struct(e).end.y * CELL)
		items.append([y, "enemy", e])
	for p: Dictionary in es.piles:
		items.append([float(p.pos.y) * S + 2.0, "pile", p])
	for pk: Dictionary in g.pack.crops.pickups:
		items.append([float(pk.pos.y) * S + 2.0, "pickup", pk])
	for hp: Dictionary in g.host.helper_list:
		items.append([float(Vector2(hp.pos).y) * S + 3.0, "helper", hp])
	items.append([g.hero_pos.y * S + 4.0, "hero", null])
	items.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	for it: Array in items:
		match str(it[1]):
			"crop": _crop(ci, g, it[2], t)
			"enemy": _enemy(ci, g, it[2], t)
			"pile": _pile(ci, g, it[2])
			"pickup": _pickup(ci, it[2], t)
			"hero": _hero(ci, g, t)
			"helper": _helper(ci, g, it[2], t)
	if g.show_detect:
		for d: Dictionary in es.detectable_enemies():
			var dp: Vector2 = Vector2(d.pos) * S
			var dc: Color = Color(1.0, 0.25, 0.25)
			if str(d.category) == "neutral":
				dc = Color(1.0, 0.95, 0.3)
			elif str(d.category) == "bonus":
				dc = Color.from_hsv(fmod(t * 0.8, 1.0), 0.6, 1.0)
			rc(ci, dp.x - 1, dp.y - 1, 3, 3, dc)
			rc(ci, dp.x - 2, dp.y - 2, 5, 1, Color(1, 1, 1, 0.5))
	for m: Dictionary in es.hint_marks():
		var p: Vector2 = Vector2(m.pos) * S
		if int(t * 6.0) % 2 == 0:
			icon(ci, "zig", p + Vector2(-2, -2), Color(0.85, 1.0, 0.8, 0.9))
		else:
			icon(ci, "zig", p + Vector2(-1, -3), Color(0.85, 1.0, 0.8, 0.6))
	for b: Dictionary in g.bullets:
		var bp: Vector2 = Vector2(b.pos) * S
		rc(ci, bp.x - 1, bp.y - 1, 2, 2, Color(1.0, 0.9, 0.4))
	for pr: Dictionary in es.projectile_list():
		var pp: Vector2 = Vector2(pr.pos) * S
		if str(pr.get("kind", "")) == "reflected":
			rc(ci, pp.x - 2, pp.y - 2, 4, 4, Color(0.85, 0.92, 1.0))
			rc(ci, pp.x - 1, pp.y - 1, 2, 2, Color(1.0, 0.35, 0.3))
		else:
			spr(ci, "needle", pp, {"rot": Vector2(pr.dir).angle()})

func _crop(ci: CanvasItem, g: RefCounted, c: Dictionary, t: float) -> void:
	var cs: RefCounted = g.pack.crops
	var kind: String = str(c.kind)
	var foot: Vector2 = Vector2((float(c.cell.x) + float(c.size.x) * 0.5) * CELL, float(c.cell.y + c.size.y) * CELL - 1.0)
	var mature: bool = bool(c.mature)
	var o: Dictionary = {}
	if not mature:
		o["scale"] = 0.5
	var ext: Dictionary = c.get("ext", {})
	if kind == "evening_primrose":
		o["mod"] = Color(1.12, 1.12, 1.0) if not g.host.day else Color(0.68, 0.74, 0.68)
	if kind == "mimosa" and bool(ext.get("closed", false)):
		o["xs"] = 0.4
		o["mod"] = Color(0.85, 0.9, 0.78)
	if kind == "tea" and mature:
		var f: float = clampf(float(c.since_mature) / 3000.0, 0.0, 1.0)
		o["mod"] = Color(1.0 - 0.4 * f, 1.0 - 0.1 * f, 1.0 - 0.4 * f)
	if bool(c.gnawed) and int(t * 4.0) % 2 == 0:
		o["mod"] = Color(1.0, 0.7, 0.7)
	if kind == "bamboo" or kind == "sakura" or kind == "giant_watermelon":
		pass
	else:
		shadow(ci, foot + Vector2(0, -1), maxi(3, int(c.size.x) * CELL / 2 - 1))
	var rect: Rect2 = spr(ci, kind, foot, o)
	var top: Vector2 = Vector2(foot.x, rect.position.y)
	if not mature:
		if bool(c.watered):
			rc(ci, foot.x - 5, foot.y - 1, 2, 2, Color(0.4, 0.7, 1.0))
	else:
		if (int(t * 2.0 + float(c.id)) % 3) != 2:
			icon(ci, "spark", Vector2(rect.end.x - 3, rect.position.y - 1), Color(1.0, 1.0, 0.6))
	if int(c.poison) > 0:
		for i: int in range(mini(3, int(c.poison))):
			rc(ci, top.x - 4 + i * 3, top.y - 4, 2, 2, Color(0.7, 0.3, 0.9))
	if kind == "sakura" and cs.is_bloom(c):
		for i: int in range(26):
			var hx: int = _hash(i * 7 + int(c.id), 3)
			var px: float = rect.position.x + 4.0 + float(hx % int(rect.size.x - 8.0))
			var py: float = rect.position.y + 3.0 + float((hx / 97) % int(rect.size.y * 0.45))
			rc(ci, px, py, 2, 2, Color(1.0, 0.75, 0.85) if i % 3 != 0 else Color(1, 1, 1))
	if kind == "kudzu":
		font.draw_shadow(ci, Vector2(foot.x - 6, foot.y + 1), "R%d" % (ext.get("roots", []) as Array).size(), Color(0.7, 1.0, 0.6))
	if kind == "loofah":
		var wn: int = clampi(int(ceil(float(ext.get("water", 0)) / 2.0)), 0, 5)
		for i: int in range(5):
			rc(ci, foot.x - 7 + i * 3, foot.y + 1, 2, 2, Color(0.35, 0.65, 1.0) if i < wn else Color(0.25, 0.3, 0.4))
	if kind == "flytrap" and float(c.digest_until) > cs.time:
		icon(ci, "bubble", Vector2(foot.x - 1, top.y - 5 - float(int(t * 3.0) % 3)), Color(0.6, 1.0, 0.6))
	if kind == "potato" and mature:
		var cap: float = maxf(1.0, float(c.paid) * 10.0)
		var n: int = clampi(int(ceil(float(c.storage) / cap * 5.0)), 0, 5) if float(c.storage) > 0.0 else 0
		for i: int in range(n):
			rc(ci, foot.x - 6 + i * 3, foot.y + 1, 2, 2, Color(0.75, 0.55, 0.3))
	if float(c.hp) < float(cs.def_of(kind).hp) - 0.01:
		hpbar(ci, Vector2(foot.x, top.y - 3), float(c.hp) / float(cs.def_of(kind).hp))
	if int(c.id) == g.sel_crop_id:
		var rr: Rect2i = Rect2i(c.cell, c.size)
		rc(ci, rr.position.x * CELL - 1, rr.position.y * CELL - 1, 3, 1, Color(1, 1, 1, 0.8))
		rc(ci, rr.end.x * CELL - 2, rr.position.y * CELL - 1, 3, 1, Color(1, 1, 1, 0.8))

func _pile(ci: CanvasItem, g: RefCounted, p: Dictionary) -> void:
	var foot: Vector2 = Vector2(p.pos) * S + Vector2(0, 2)
	var sc: float = 1.0 if int(p.stock) >= 2 else 0.75
	var r: Rect2 = spr(ci, "junk_pile", foot, {"scale": sc})
	font.draw_shadow(ci, Vector2(r.position.x + 2, r.end.y + 1), "x%d" % int(p.stock), Color(1, 1, 0.8))
	if float(p.hp) < float(p.max_hp) - 0.01:
		hpbar(ci, Vector2(foot.x, r.position.y - 3), float(p.hp) / float(p.max_hp))

func _pickup(ci: CanvasItem, pk: Dictionary, t: float) -> void:
	var p: Vector2 = Vector2(pk.pos) * S
	var name: String = "strawberry_pickup" if str(pk.kind) == "strawberry" else "seed_bag"
	shadow(ci, p + Vector2(0, 3), 3)
	spr(ci, name, p + Vector2(0, -float(int(t * 3.0) % 2)))

func _helper(ci: CanvasItem, g: RefCounted, h: Dictionary, t: float) -> void:
	var foot: Vector2 = Vector2(h.pos) * S + Vector2(0, 3)
	shadow(ci, foot, 3)
	var stopped: bool = g.pack.common.helper_stopped(int(h.id))
	var body: Color = Color(0.3, 0.62, 0.9) if not stopped else Color(0.45, 0.5, 0.58)
	rc(ci, foot.x - 3, foot.y - 7, 6, 7, body)
	rc(ci, foot.x - 3, foot.y - 7, 6, 1, body.lightened(0.25))
	rc(ci, foot.x - 2, foot.y - 10, 4, 3, Color(0.5, 0.82, 0.45))
	if stopped:
		icon(ci, "star", Vector2(foot.x - 2, foot.y - 17), Color(1.0, 0.9, 0.3))
	if float(h.hp) < float(h.max_hp) - 0.01:
		hpbar(ci, Vector2(foot.x, foot.y - 13), float(h.hp) / float(h.max_hp))

func _hero(ci: CanvasItem, g: RefCounted, t: float) -> void:
	var foot: Vector2 = g.hero_pos * S + Vector2(0, 4)
	shadow(ci, foot, 4)
	var rect: Rect2 = spr(ci, "hero", foot, {"flip": g.aim.x < 0.0})
	if g.elapsed < g.slow_until:
		icon(ci, "drop", Vector2(foot.x - 1, rect.position.y - 5), Color(0.6, 0.45, 0.25))
	if g.hero_stunned():
		for i: int in range(2):
			var sa: float = t * 5.0 + float(i) * PI
			icon(ci, "star", Vector2(foot.x - 2 + cos(sa) * 5.0, rect.position.y - 8 + sin(sa) * 1.5), Color(1.0, 1.0, 0.4))
	if g.hp < g.max_hp - 0.01:
		hpbar(ci, Vector2(foot.x, rect.position.y - 3), g.hp / g.max_hp)
	if g.tool == "combat":
		dotted(ci, g.hero_pos * S + g.aim * 10.0, g.hero_pos * S + g.aim * 22.0, Color(1, 1, 1, 0.5), 4.0)

# ---------------------------------------------------------------- 敵
const SECOND: Array = ["root_mole", "skunk", "hippo", "honey_bear", "sewer_rat", "manhole", "bat_flock", "iron_rhino", "thunder_eel",
	"decoy_newt", "decoy_tail", "mirror_lizard", "pistol_shrimp", "balloon_frog", "glass_deer"]
const RUST_SPOTS: Array = [Vector2(10, 6), Vector2(20, 9), Vector2(15, 14), Vector2(26, 7), Vector2(7, 13)]

## 前向き(face)の±half度を点線で示す
func _front_arc(ci: CanvasItem, pos: Vector2, face: Vector2, half_deg: float, length: float, c: Color) -> void:
	var f: Vector2 = face.normalized() if face.length() > 0.01 else Vector2.DOWN
	dotted(ci, pos, pos + f.rotated(deg_to_rad(half_deg)) * length, c, 3.0)
	dotted(ci, pos, pos + f.rotated(-deg_to_rad(half_deg)) * length, c, 3.0)

## 第2弾の動物の描画(状態は画像を増やさず、反転・回転・拡縮・色・記号で表す)
func _enemy2(ci: CanvasItem, g: RefCounted, e: Dictionary, t: float) -> void:
	var es: RefCounted = g.pack.enemies
	var kind: String = str(e.kind)
	var st: String = str(e.state)
	var pos: Vector2 = Vector2(e.pos) * S
	var foot: Vector2 = pos + Vector2(0, 3)
	var face: Vector2 = Vector2(e.face)
	var o: Dictionary = {"flip": face.x < -0.05}
	var blink: bool = int(t * 5.0) % 2 == 0
	var rage: bool = false
	var wet_in_water: bool = false
	var rect: Rect2 = Rect2(foot - Vector2(6, 8), Vector2(12, 8))
	match kind:
		"root_mole":
			if st not in ["peek", "stunned"]:
				# 地中: 射撃は当たらない。真上に薄い土の影だけ(検知は盛り土の位置)
				rc(ci, pos.x - 4, pos.y + 1, 8, 2, Color(0.2, 0.14, 0.1, 0.35))
				if st == "pop" and blink:
					icon(ci, "bang", pos + Vector2(-1, -9), Color(0.4, 0.7, 1.0))
				if st == "gnaw":
					rc(ci, pos.x - 2 + (int(t * 8.0) % 3), pos.y - 2, 2, 2, Color(0.5, 0.38, 0.26))
				return
			rect = spr(ci, kind, foot, o)
			rc(ci, pos.x - 5, pos.y + 2, 10, 2, Color(0.35, 0.25, 0.18, 0.7))
			if st == "stunned":
				for i: int in range(2):
					var a: float = t * 4.0 + float(i) * PI
					icon(ci, "star", rect.position + Vector2(rect.size.x * 0.5 - 2 + cos(a) * 5.0, -6 + sin(a) * 1.5), Color(1.0, 0.9, 0.3))
		"skunk":
			shadow(ci, foot, 5)
			rect = spr(ci, kind, foot, o)
			_front_arc(ci, pos, face, 60.0, 16.0, Color(0.95, 0.95, 0.8, 0.55))
			if st == "windup":
				if blink:
					icon(ci, "bang", Vector2(rect.position.x + rect.size.x * 0.5 - 1, rect.position.y - 8), Color(1.0, 0.3, 0.2))
				o["mod"] = Color(1.25, 1.15, 0.9)
		"hippo":
			var in_w: bool = g.host.is_water(Grid.cell_of_pos(e.pos))
			if not in_w:
				shadow(ci, foot, 12)
			rect = spr(ci, kind, foot + Vector2(0, 0.0), o)
			if in_w:
				# 背中だけが水面に出ている
				rc(ci, rect.position.x, rect.position.y + rect.size.y * 0.55, rect.size.x, rect.size.y * 0.45 + 1.0, Color(0.2, 0.4, 0.62, 0.75))
				ring(ci, pos, 14.0 + 2.0 * sin(t * 2.0), Color(0.75, 0.9, 1.0, 0.5), 2)
			if st == "windup" and blink:
				icon(ci, "bang", Vector2(rect.position.x + rect.size.x * 0.5 - 1, rect.position.y - 8), Color(1.0, 0.25, 0.2))
			if st in ["windup", "charge"] and e.has("charge_dir"):
				dotted(ci, pos, pos + Vector2(e.charge_dir) * 60.0, Color(1.0, 0.4, 0.3, 0.8), 4.0)
			if st == "rest":
				font.draw(ci, Vector2(rect.position.x + rect.size.x * 0.5 - 3, rect.position.y - 8), "ZZ", Color(0.8, 0.85, 1.0, 0.85))
		"honey_bear":
			shadow(ci, foot, 11)
			if st == "sleep":
				o["mod"] = Color(0.72, 0.72, 0.9)
			elif st == "enraged":
				o["mod"] = Color(1.25, 0.72, 0.72)
				rage = true
			rect = spr(ci, kind, foot, o)
			var head2: Vector2 = Vector2(rect.position.x + rect.size.x * 0.5, rect.position.y)
			if st == "sleep":
				font.draw(ci, head2 + Vector2(-3, -9), "ZZ", Color(0.8, 0.85, 1.0, 0.9))
			if rage:
				icon(ci, "anger", head2 + Vector2(-2, -8), Color(1.0, 0.15, 0.15))
			for i: int in range(clampi(int(e.get("satiety", 0)), 0, 3)):
				rc(ci, head2.x - 5 + i * 4, head2.y - 5, 3, 3, Color(0.99, 0.8, 0.25))
		"sewer_rat":
			if st == "ug":
				return
			shadow(ci, foot, 3)
			rect = spr(ci, kind, foot, o)
			if st == "stuck":
				icon(ci, "star", Vector2(rect.position.x + 2, rect.position.y - 6), Color(1.0, 0.9, 0.3))
		"bat_flock":
			var lift: float = 0.0
			var xs: float = 1.0
			match st:
				"roost":
					o["rot"] = PI
					o["mod"] = Color(0.8, 0.8, 0.95)
					foot = pos + Vector2(0, 2)
				"swarm", "return":
					lift = 11.0 + 3.0 * sin(t * 6.0 + float(e.id))
					xs = 1.0 if sin(t * 22.0 + float(e.id)) > 0.0 else 0.55
				"dive":
					lift = 6.0
					xs = 1.0 if sin(t * 22.0 + float(e.id)) > 0.0 else 0.55
				"low":
					lift = 2.0
			if lift > 0.0:
				shadow(ci, foot, 2)
				foot.y -= lift
			o["xs"] = xs
			rect = spr(ci, kind, foot, o)
			if st == "roost" and int(e.slot) == 0:
				font.draw(ci, Vector2(rect.position.x, rect.position.y - 8), "ZZ", Color(0.8, 0.85, 1.0, 0.8))
			if st == "dive" and blink:
				icon(ci, "bang", Vector2(rect.position.x + 2, rect.position.y - 7), Color(1.0, 0.3, 0.2))
		"iron_rhino":
			shadow(ci, foot, 13)
			var r: int = int(e.get("rust", 0))
			if r > 0:
				o["mod"] = Color(1.0, 1.0 - 0.07 * float(r), 1.0 - 0.14 * float(r))
			rect = spr(ci, kind, foot, o)
			for i: int in range(mini(r, RUST_SPOTS.size())):
				var rs: Vector2 = RUST_SPOTS[i]
				var rx: float = rect.position.x + (rs.x if not bool(o.flip) else rect.size.x - rs.x - 3.0)
				rc(ci, rx, rect.position.y + rs.y, 3, 2, Color(0.72, 0.36, 0.14))
			if r > 0:
				font.draw_shadow(ci, Vector2(rect.position.x + 2, rect.end.y + 1), "RUST%d" % r, Color(1.0, 0.7, 0.4))
			if st == "windup" and blink:
				icon(ci, "bang", Vector2(rect.position.x + rect.size.x * 0.5 - 1, rect.position.y - 8), Color(1.0, 0.25, 0.2))
			if st in ["windup", "charge"] and e.has("charge_dir"):
				dotted(ci, pos, pos + Vector2(e.charge_dir) * 70.0, Color(1.0, 0.4, 0.3, 0.8), 4.0)
			if st == "recover":
				icon(ci, "drop", Vector2(rect.position.x + rect.size.x * 0.5, rect.position.y - 6), Color(0.6, 0.85, 1.0))
		"thunder_eel":
			if st == "windup":
				o["mod"] = Color(2.0, 2.0, 2.2) if blink else Color(1.4, 1.5, 1.8)
				ring(ci, pos, 30.0 * S, Color(0.6, 0.95, 1.0, 0.7), 3)
				if blink:
					icon(ci, "bang", pos + Vector2(-1, -12), Color(0.6, 0.95, 1.0))
			elif st == "tired":
				o["mod"] = Color(0.8, 0.85, 0.9)
				for c: Variant in e.get("chain", []):
					var cc: Vector2i = c
					if int(t * 10.0) % 2 == 0:
						rc(ci, cc.x * CELL, cc.y * CELL, CELL, CELL, Color(0.65, 0.95, 1.0, 0.45))
						icon(ci, "zig", Vector2(cc.x * CELL + 2, cc.y * CELL + 1), Color(1.0, 1.0, 0.7))
				icon(ci, "drop", pos + Vector2(-1, -10), Color(0.6, 0.85, 1.0))
			rect = spr(ci, kind, foot, o)
			rc(ci, rect.position.x, rect.position.y + rect.size.y * 0.55, rect.size.x, rect.size.y * 0.45 + 1.0, Color(0.2, 0.38, 0.62, 0.55))
			ring(ci, pos, 9.0 + 2.0 * sin(t * 3.0), Color(0.75, 0.92, 1.0, 0.4), 2)
		"decoy_newt", "decoy_tail":
			shadow(ci, foot, 4)
			if kind == "decoy_newt" and not bool(e.get("tail", true)):
				o["clip_x0"] = 5
			rect = spr(ci, "decoy_newt", foot, o)
			if kind == "decoy_tail" and g.show_hidden:
				font.draw(ci, Vector2(rect.position.x, rect.position.y - 8), "DC", Color(1.0, 1.0, 0.5, 0.9))
			if kind == "decoy_newt" and st == "bite":
				icon(ci, "anger", Vector2(rect.position.x + 4, rect.position.y - 7), Color(1.0, 0.2, 0.2))
		"mirror_lizard":
			shadow(ci, foot, 6)
			rect = spr(ci, kind, foot, o)
			_front_arc(ci, pos, face, 60.0, 18.0, Color(0.8, 0.92, 1.0, 0.65))
			if st == "bite":
				icon(ci, "star", Vector2(rect.position.x + rect.size.x * 0.5 - 2, rect.position.y - 7), Color(1.0, 0.9, 0.3))
		"pistol_shrimp":
			shadow(ci, foot, 7)
			if st == "windup":
				o["mod"] = Color(1.7, 1.5, 1.4) if blink else Color(1.2, 1.1, 1.1)
				ring(ci, pos, 40.0 * S, Color(0.9, 0.9, 1.0, 0.55), 4)
			elif st == "cooldown":
				o["mod"] = Color(0.85, 0.85, 0.92)
			rect = spr(ci, kind, foot, o)
			if st == "windup" and blink:
				icon(ci, "bang", Vector2(rect.position.x + rect.size.x * 0.5 - 1, rect.position.y - 8), Color(1.0, 0.25, 0.2))
		"balloon_frog":
			var sc: float = 1.0
			var lift2: float = 0.0
			if st == "inflate":
				var dur: float = maxf(0.1, float(es.defs.balloon_frog.params.get("inflate_s", 1.0)))
				var frac: float = clampf(1.0 - (float(e.until) - es.time) / dur, 0.0, 1.0)
				sc = 1.0 + (16.0 / 12.0 - 1.0) * frac
				o["mod"] = Color(1.05, 1.05, 1.0)
			elif st == "float":
				sc = 16.0 / 12.0
				lift2 = 12.0 + 2.0 * sin(t * 3.0 + float(e.id))
				o["mod"] = Color(1.12, 1.12, 1.0)
			if lift2 > 0.0:
				shadow(ci, foot, 3)   # 浮いている間も影は地面に残る
				foot.y -= lift2
			else:
				shadow(ci, foot, 3)
			o["scale"] = sc
			rect = spr(ci, kind, foot, o)
			if st in ["inflate", "float"]:
				icon(ci, "bubble", Vector2(rect.position.x + rect.size.x * 0.5 - 1, rect.position.y - 5), Color(0.7, 1.0, 0.6))
		"glass_deer":
			shadow(ci, foot, 8)
			var hue: float = fmod(t * 0.35 + float(e.id) * 0.1, 1.0)
			var tint: Color = Color.from_hsv(hue, 0.28, 1.0)
			o["mod"] = Color(tint.r * 1.05, tint.g * 1.05, tint.b * 1.05)
			rect = spr(ci, kind, foot, o)
			# 足元に落ちる虹色の光
			for i: int in range(5):
				rc(ci, foot.x - 10 + i * 4, foot.y + 1 + (i % 2), 4, 1, Color.from_hsv(fmod(hue + float(i) * 0.18, 1.0), 0.6, 1.0, 0.75))
			if int(t * 6.0 + float(e.id)) % 3 == 0:
				icon(ci, "spark", rect.position + Vector2(8 + (int(t * 3.0) % 3) * 4, 3), Color(1, 1, 1, 0.9))
	if float(e.hp) < float(e.max_hp) - 0.01:
		hpbar(ci, Vector2(rect.position.x + rect.size.x * 0.5, rect.position.y - 3), float(e.hp) / float(e.max_hp))

func _enemy(ci: CanvasItem, g: RefCounted, e: Dictionary, t: float) -> void:
	var es: RefCounted = g.pack.enemies
	var kind: String = str(e.kind)
	if SECOND.has(kind):
		_enemy2(ci, g, e, t)
		return
	var st: String = str(e.state)
	var pos: Vector2 = Vector2(e.pos) * S
	var foot: Vector2 = pos + Vector2(0, 3)
	var hidden: bool = es.is_hidden(e)
	var def: Dictionary = es.def_of(e)
	var o: Dictionary = {"flip": Vector2(e.face).x < 0.0}
	var name: String = kind
	var lift: float = 0.0
	var sym_y_extra: float = 0.0
	# 擬態: 擬態後の見た目(茂み・キャベツ)か、非表示(揺らぎ記号は hint_marks で別に描く)
	if hidden:
		match kind:
			"moss_turtle": name = "moss_turtle_bush"
			"mimic_cabbage": name = "mimic_cabbage_disguise"
			"grass_snake": name = "grass_snake_grass"
			_: name = ""
		if g.show_hidden:
			var gh: Rect2 = spr(ci, kind, foot, {"flip": o.flip, "mod": Color(1, 1, 1, 0.45)})
			font.draw(ci, Vector2(gh.position.x, gh.position.y - 8), "HID", Color(1, 1, 0.5, 0.9))
		if name == "":
			return
		o["flip"] = false
	if kind == "ant_hill" or kind == "honeybee_hive":
		var sr: Rect2i = es.rect_of_struct(e)
		foot = Vector2((float(sr.position.x) + float(sr.size.x) * 0.5) * CELL, float(sr.end.y) * CELL - 1.0)
		if kind == "ant_hill" and st == "dormant":
			o["mod"] = Color(0.8, 0.8, 0.8)
	var hab: String = str(def.get("habitat", "land"))
	if kind == "seed_bird" and st == "flying":
		lift = 12.0
	elif kind == "black_kite":
		lift = 0.0 if st == "ground" else (6.0 if st == "climb" else 16.0)
	elif kind == "honeybee_swarm":
		lift = 8.0 + float(int(t * 6.0 + float(e.id)) % 3)
	if lift > 0.0:
		shadow(ci, foot, 5)
		foot.y -= lift
	elif hab == "land" and kind != "ant_hill" and kind != "honeybee_hive":
		shadow(ci, foot, maxi(3, int(float(bank.size_of(kind).x) * 0.35)))
	# 状態による見た目(画像は共通。回転・灰色化・暗転・半透明で表す)
	if kind == "sludge_carp":
		if st == "dive":
			o["mod"] = Color(1, 1, 1, 0.3)
		elif st == "rise":
			o["mod"] = Color(1, 1, 1, 0.65)
	if st == "charred":
		o["mod"] = Color(0.28, 0.26, 0.26)
	if st == "flipped":
		o["rot"] = PI
		o["gray"] = true
	if (kind == "quill_hedgehog" and st == "curl") or (kind == "armadillo" and st == "roll"):
		o["rot"] = float(int(t * 8.0) % 4) * PI * 0.5
		o["gray"] = true
	if kind == "tarachunade" and st == "fuse" and int(t * 8.0) % 2 == 0:
		o["mod"] = Color(1.8, 1.5, 1.2)
	var rage: bool = float(e.get("rage_until", 0.0)) > es.time
	if rage:
		o["mod"] = Color(1.25, 0.7, 0.7)
	if kind == "mushling_parent" or kind == "mushling_child":
		pass
	if kind == "junk_crab" and bool(e.get("shell", false)):
		# 殻は別画像。本体の背中に重ねる(殻は付け替えの間だけ半透明)
		spr(ci, name, foot, o)
		var sh_alpha: float = 0.5 if st == "wearing" else 1.0
		spr(ci, "junk_crab_shell", foot + Vector2(0, -7), {"flip": o.flip, "mod": Color(1, 1, 1, sh_alpha)})
		name = ""
	if name != "":
		var rect0: Rect2 = spr(ci, name, foot, o)
		_enemy_marks(ci, g, e, rect0, t)
	else:
		var r2: Rect2 = Rect2(foot + Vector2(-10, -26), Vector2(20, 26))
		_enemy_marks(ci, g, e, r2, t)
	if sym_y_extra != 0.0:
		pass

## 状態記号。rect はスプライトの描画矩形(画面px)。
func _enemy_marks(ci: CanvasItem, g: RefCounted, e: Dictionary, rect: Rect2, t: float) -> void:
	var es: RefCounted = g.pack.enemies
	var kind: String = str(e.kind)
	var st: String = str(e.state)
	var head: Vector2 = Vector2(rect.position.x + rect.size.x * 0.5, rect.position.y)
	var blink: bool = int(t * 5.0) % 2 == 0
	var pos: Vector2 = Vector2(e.pos) * S
	# 予兆「！」の点滅と、地面の線・影
	var warn: bool = st in ["windup", "fuse", "aim", "mark", "lock", "rise", "lunge"] or (kind == "armadillo" and st == "curl")
	if warn:
		if blink:
			icon(ci, "bang", head + Vector2(-1, -7), Color(1.0, 0.25, 0.2))
		if kind == "shadow_brian" and e.has("charge_dir"):
			dotted(ci, pos, pos + Vector2(e.charge_dir) * 80.0, Color(1.0, 0.4, 0.3, 0.8), 4.0)
		elif kind == "quill_hedgehog" and e.has("tpos"):
			dotted(ci, pos, Vector2(e.tpos) * S, Color(1.0, 0.4, 0.3, 0.8), 4.0)
		elif kind == "tongue_frog":
			dotted(ci, pos, g.hero_pos * S, Color(1.0, 0.5, 0.6, 0.8), 4.0)
		elif kind == "armadillo" and e.has("roll_dir"):
			dotted(ci, pos, pos + Vector2(e.roll_dir) * 60.0, Color(1.0, 0.4, 0.3, 0.8), 4.0)
	if kind == "tongue_frog" and st == "tongue":
		var tp: Vector2 = pos
		var hp2: Vector2 = g.hero_pos * S
		for i: int in range(0, int(tp.distance_to(hp2)), 1):
			var q: Vector2 = tp.lerp(hp2, float(i) / maxf(1.0, tp.distance_to(hp2)))
			rc(ci, q.x, q.y, 2, 1, Color(0.95, 0.45, 0.55))
	if kind == "black_kite" and e.has("shadow") and st in ["mark", "lock", "dive", "ground"]:
		var sp: Vector2 = Vector2(e.shadow) * S
		rc(ci, sp.x - 7, sp.y - 1, 14, 3, Color(0, 0, 0, 0.45))
		rc(ci, sp.x - 5, sp.y - 2, 10, 1, Color(0, 0, 0, 0.3))
		rc(ci, sp.x - 5, sp.y + 2, 10, 1, Color(0, 0, 0, 0.3))
		if st == "lock" and blink:
			ring(ci, sp, 9.0, Color(1.0, 0.3, 0.2))
	if kind == "sludge_carp" and e.has("muds"):
		for m: Dictionary in e.muds:
			var mp: Vector2 = Vector2(m.pos) * S
			ring(ci, mp, float(es.defs.sludge_carp.params.mud_radius_m) * 10.0 * S, Color(0.7, 0.5, 0.25), 2)
			rc(ci, mp.x - 1, mp.y - 1, 2, 2, Color(0.55, 0.35, 0.2))
	# 星(刺さり・目を回す・ひっくり返り)
	if st in ["stuck", "dizzy", "flipped"]:
		for i: int in range(2):
			var a: float = t * 4.0 + float(i) * PI
			icon(ci, "star", head + Vector2(-2 + cos(a) * 5.0, -6 + sin(a) * 1.5), Color(1.0, 0.9, 0.3))
	# 怒り・鳴き声・遠吠え
	var rage: bool = float(e.get("rage_until", 0.0)) > es.time
	if rage or st == "angry" or (kind == "honeybee_hive" and st == "angry"):
		icon(ci, "anger", head + Vector2(-2, -7), Color(1.0, 0.15, 0.15))
	if st == "call" or st == "howl":
		icon(ci, "note", head + Vector2(-2, -7), Color(0.95, 0.95, 1.0))
		if st == "howl":
			icon(ci, "wave", head + Vector2(3, -6), Color(0.9, 0.95, 1.0))
	# 湿り・黒焦げ
	if kind == "tarachunade":
		if float(e.get("wet_until", 0.0)) > es.time:
			icon(ci, "drop", head + Vector2(-5, -5), Color(0.45, 0.75, 1.0))
			icon(ci, "drop", head + Vector2(2, -4), Color(0.45, 0.75, 1.0))
		if st == "charred":
			for i: int in range(3):
				var sy: float = float(int(t * 6.0 + float(i) * 2.0) % 6)
				rc(ci, head.x - 3 + i * 3, head.y - 2 - sy, 2, 2, Color(0.55, 0.55, 0.58, 0.8 - sy * 0.1))
	# ペンキ・荷物など
	if kind == "paint_chameleon" and bool(e.get("paint", false)):
		rc(ci, rect.position.x + 5, rect.position.y + 4, 3, 2, Color(0.4, 0.6, 0.95))
		rc(ci, rect.position.x + 9, rect.position.y + 6, 3, 2, Color(0.95, 0.85, 0.3))
	if kind == "leafcutter_ant" and st == "carry":
		rc(ci, rect.position.x + 1, rect.position.y - 3, 3, 2, Color(0.4, 0.8, 0.35))
	if kind == "pouch_rabbit" and float(e.get("cheek", 0.0)) > 0.0:
		rc(ci, rect.end.x - 4, rect.position.y + 5, 2, 2, Color(1.0, 0.9, 0.4))
	if kind == "seed_bird" and st == "landing":
		icon(ci, "spark", head + Vector2(-1, -4), Color(1, 1, 0.7))
	if kind == "ant_hill" and st == "dormant":
		font.draw(ci, Vector2(head.x - 3, head.y - 8), "ZZ", Color(0.8, 0.8, 1.0, 0.8))
	if float(e.hp) < float(e.max_hp) - 0.01 and not es.is_hidden(e):
		hpbar(ci, Vector2(head.x, head.y - 3), float(e.hp) / float(e.max_hp))

# ---------------------------------------------------------------- 効果
func _effects(ci: CanvasItem, g: RefCounted, t: float) -> void:
	for f: Dictionary in g.fx_list:
		var age: float = (g.elapsed - float(f.t0)) / maxf(0.01, float(f.life))
		var p: Vector2 = Vector2(f.pos) * S
		match str(f.kind):
			"explosion":
				var r: float = float(f.get("radius_px", 30.0)) * S * clampf(age * 2.0, 0.0, 1.0)
				ci.draw_circle(p, r, Color(1.0, 0.6, 0.2, 0.5 * (1.0 - age)))
				ring(ci, p, r, Color(1.0, 0.9, 0.5, 1.0 - age))
			"water":
				ring(ci, p, Game.WATER_RADIUS * S * clampf(age * 2.0, 0.0, 1.0), Color(0.5, 0.8, 1.0, 1.0 - age))
				for i: int in range(6):
					var a: float = float(i) * 1.05
					rc(ci, p.x + cos(a) * 10.0 * age * 2.0, p.y + sin(a) * 10.0 * age * 2.0, 2, 2, Color(0.6, 0.85, 1.0, 1.0 - age))
			"hit":
				rc(ci, p.x - 2, p.y - 2, 4, 4, Color(1, 1, 1, 1.0 - age))
			"seed_land":
				rc(ci, p.x - 1, p.y - 1, 2, 2, Color(1.0, 0.9, 0.4, 1.0 - age))
			"tackle":
				ring(ci, p, 12.0 * age + 4.0, Color(1, 1, 1, 1.0 - age))
			"pull":
				ring(ci, p, 10.0 * (1.0 - age), Color(1.0, 0.5, 0.6, 1.0 - age))
			"revive":
				icon(ci, "spark", p + Vector2(-1, -10 - 6 * age), Color(1.0, 1.0, 0.6, 1.0 - age))
			"needle_hit":
				rc(ci, p.x - 1, p.y - 1, 3, 3, Color(1, 0.8, 0.8, 1.0 - age))
			"carp_warn":
				ring(ci, p, 8.0 + 8.0 * age, Color(0.7, 0.6, 0.4, 1.0 - age))
			"mud_land":
				ci.draw_circle(p, float(f.get("radius", 10.0)) * S, Color(0.45, 0.3, 0.2, 0.55 * (1.0 - age)))
			"stuck", "wet", "howl", "rage", "shell_break", "bear_rage", "odor_cancel", "manhole_closed":
				ring(ci, p, 6.0 + 10.0 * age, Color(1, 1, 1, 0.7 * (1.0 - age)), 2)
			"stun":
				for i: int in range(3):
					var sa: float = t * 6.0 + float(i) * TAU / 3.0
					icon(ci, "star", g.hero_pos * S + Vector2(-2 + cos(sa) * 7.0, -16 + sin(sa) * 2.0), Color(1.0, 1.0, 0.4, 0.9))
			"burst":
				var br: float = float(f.get("radius_px", 20.0)) * S * clampf(age * 2.5, 0.0, 1.0)
				ci.draw_circle(p, br, Color(1.0, 0.5, 0.75, 0.3 * (1.0 - age)))
				ring(ci, p, br, Color(1.0, 0.7, 0.85, 1.0 - age))
			"discharge":
				var dr: float = float(f.get("radius", 30.0)) * S * clampf(age * 3.0, 0.0, 1.0)
				ring(ci, p, dr, Color(0.7, 0.97, 1.0, 1.0 - age))
				for i: int in range(6):
					var da: float = float(i) * 1.047 + 0.3
					icon(ci, "zig", p + Vector2(cos(da), sin(da)) * dr * 0.8 + Vector2(-2, -2), Color(1.0, 1.0, 0.6, 1.0 - age))
			"shrimp_wave":
				var sr: float = float(f.get("radius", 40.0)) * S * clampf(age * 3.0, 0.0, 1.0)
				ring(ci, p, sr, Color(0.9, 0.95, 1.0, 1.0 - age))
				ring(ci, p, sr * 0.7, Color(0.9, 0.95, 1.0, 0.6 * (1.0 - age)), 2)
			"frog_pop":
				var fr: float = float(f.get("radius", 16.0)) * S * clampf(age * 3.0, 0.0, 1.0)
				ring(ci, p, fr, Color(0.7, 1.0, 0.4, 1.0 - age))
			"mole_water":
				ring(ci, p, 4.0 + 8.0 * age, Color(0.5, 0.8, 1.0, 1.0 - age))
			"reflect":
				rc(ci, p.x - 3, p.y, 7, 1, Color(1, 1, 1, 1.0 - age))
				rc(ci, p.x, p.y - 3, 1, 7, Color(1, 1, 1, 1.0 - age))
			"rust":
				ring(ci, p, 3.0 + 6.0 * age, Color(0.8, 0.4, 0.15, 1.0 - age))
			"decoy_pop", "tail_cut":
				icon(ci, "spark", p + Vector2(-1, -6 - 4 * age), Color(1.0, 1.0, 0.8, 1.0 - age))
			"bat_wake":
				icon(ci, "bang", p + Vector2(-1, -12), Color(1.0, 0.9, 0.4, 1.0 - age))
			"glass_break":
				for i: int in range(14):
					var ga: float = float(i) * 0.9 + float(i % 3)
					var gd: float = (6.0 + float(i % 4) * 5.0) * clampf(age * 1.4, 0.0, 1.0)
					rc(ci, p.x + cos(ga) * gd, p.y - 6 + sin(ga) * gd * 0.8 + 6.0 * age * age, 2, 2, Color.from_hsv(fmod(float(i) * 0.09 + t, 1.0), 0.55, 1.0, 1.0 - age))

func _glow_moss(ci: CanvasItem, g: RefCounted, t: float) -> void:
	for c: Dictionary in g.pack.crops.crops:
		if c.kind == "glow_moss" and bool(c.mature):
			var p: Vector2 = (Vector2(c.cell) + Vector2(0.5, 0.5)) * CELL
			ci.draw_circle(p, 6.0, Color(0.5, 1.0, 0.9, 0.2 + 0.05 * sin(t * 3.0)))

func _cursor(ci: CanvasItem, g: RefCounted, ui: Dictionary) -> void:
	var m: Vector2 = ui.get("mouse", Vector2(-10, -10))
	if m.x < 0 or m.y < 0 or m.x >= MAP_W or m.y >= MAP_H:
		return
	if g.tool == "crop":
		var pv: Dictionary = g.preview(g.sel_crop, g.hover_cell)
		var ok: bool = bool(pv.ok) and bool(pv.afford)
		var c0: Color = Color(0.3, 1.0, 0.4, 0.45) if ok else Color(1.0, 0.3, 0.3, 0.45)
		var cell: Vector2i = pv.cell
		var sz: Vector2i = pv.size
		rc(ci, cell.x * CELL, cell.y * CELL, sz.x * CELL, sz.y * CELL, c0)
		var foot: Vector2 = Vector2((float(cell.x) + float(sz.x) * 0.5) * CELL, float(cell.y + sz.y) * CELL - 1.0)
		spr(ci, g.sel_crop, foot, {"mod": Color(1, 1, 1, 0.6)})
		font.draw_shadow(ci, Vector2(cell.x * CELL, (cell.y + sz.y) * CELL + 1), "$%d" % int(pv.price), Color(1, 1, 0.5) if bool(pv.afford) else Color(1, 0.5, 0.5))
	elif g.tool == "remove":
		var cell2: Vector2i = g.hover_cell
		rc(ci, cell2.x * CELL, cell2.y * CELL, CELL, CELL, Color(1.0, 0.3, 0.3, 0.5))
		font.draw_shadow(ci, Vector2(m.x + 6, m.y + 6), "REMOVE", Color(1, 0.6, 0.6))
	elif g.tool == "enemy":
		rc(ci, g.hover_cell.x * CELL, g.hover_cell.y * CELL, CELL, CELL, Color(1.0, 0.8, 0.3, 0.4))
		font.draw_shadow(ci, Vector2(m.x + 6, m.y + 6), g.sel_enemy.to_upper().substr(0, 12), Color(1, 0.9, 0.6))
	else:
		rc(ci, m.x - 3, m.y, 7, 1, Color(1, 1, 1, 0.9))
		rc(ci, m.x, m.y - 3, 1, 7, Color(1, 1, 1, 0.9))

# ---------------------------------------------------------------- パネル
func buttons(g: RefCounted) -> Array:
	var out: Array = []
	var x0: float = float(PANEL_X) + 2.0
	var tabs: Array = [["ENM1", "enemy"], ["CRP1", "crop"], ["ENM2", "enemy2"], ["CRP2", "crop2"]]
	for ti: int in range(tabs.size()):
		out.append({"r": Rect2(x0 + ti * 31, 12, 30, 10), "label": tabs[ti][0], "action": "tab:" + str(tabs[ti][1]), "on": g.tab == tabs[ti][1]})
	var list: Array = g.current_list()
	var is_en: bool = g.is_enemy_tab()
	for i: int in range(list.size()):
		var col: int = i % 2
		var row: int = i / 2
		var kind: String = list[i][0]
		var act: String = ("pick_enemy:" if is_en else "pick_crop:") + kind
		var on: bool = (g.tool == "enemy" and g.sel_enemy == kind) if is_en else (g.tool == "crop" and g.sel_crop == kind)
		out.append({"r": Rect2(x0 + col * 63, 24 + row * 9, 61, 8), "label": list[i][1], "action": act, "on": on})
	out.append({"r": Rect2(x0, 152, 61, 10), "label": "INITIAL", "action": "origin:initial", "on": g.origin == "initial"})
	out.append({"r": Rect2(x0 + 63, 152, 61, 10), "label": "PRODUCED", "action": "origin:produced", "on": g.origin == "produced"})
	out.append({"r": Rect2(x0, 164, 61, 10), "label": "COMBAT", "action": "tool:combat", "on": g.tool == "combat"})
	out.append({"r": Rect2(x0 + 63, 164, 61, 10), "label": "REMOVE", "action": "tool:remove", "on": g.tool == "remove"})
	out.append({"r": Rect2(x0, 176, 61, 10), "label": "DAY/NIGHT", "action": "day", "on": not g.host.day})
	out.append({"r": Rect2(x0 + 63, 176, 61, 10), "label": "PAUSE", "action": "pause", "on": g.paused})
	for i: int in range(3):
		var sp: int = [1, 10, 60][i]
		out.append({"r": Rect2(x0 + i * 42, 188, 40, 10), "label": "X%d" % sp, "action": "speed:%d" % sp, "on": g.speed == sp})
	out.append({"r": Rect2(x0, 200, 61, 10), "label": "SAVE", "action": "save", "on": false})
	out.append({"r": Rect2(x0 + 63, 200, 61, 10), "label": "LOAD", "action": "load", "on": false})
	out.append({"r": Rect2(x0, 222, 61, 10), "label": "ROLL HIT", "action": "dbg_roll_hit", "on": false, "debug": true})
	out.append({"r": Rect2(x0 + 63, 222, 61, 10), "label": "ROLL MISS", "action": "dbg_roll_miss", "on": false, "debug": true})
	out.append({"r": Rect2(x0, 234, 61, 10), "label": "SEEDS+100", "action": "dbg_seeds", "on": false, "debug": true})
	out.append({"r": Rect2(x0 + 63, 234, 61, 10), "label": "MATURE", "action": "dbg_mature", "on": false, "debug": true})
	out.append({"r": Rect2(x0, 246, 61, 10), "label": "WATER ALL", "action": "dbg_water", "on": false, "debug": true})
	out.append({"r": Rect2(x0 + 63, 246, 61, 10), "label": "CLR ENEMY", "action": "clear_enemies", "on": false, "debug": true})
	return out

func _panel(ci: CanvasItem, g: RefCounted, ui: Dictionary) -> void:
	rc(ci, PANEL_X, 0, 128, 360, Color(0.09, 0.11, 0.13))
	rc(ci, PANEL_X, 0, 1, 360, Color(0.3, 0.35, 0.4))
	font.draw(ci, Vector2(PANEL_X + 3, 3), "CONTENT LAB", Color(0.9, 0.95, 1.0))
	var m: Vector2 = ui.get("mouse", Vector2(-1, -1))
	for b: Dictionary in buttons(g):
		var r: Rect2 = b.r
		var hov: bool = r.has_point(m)
		var bg: Color = Color(0.2, 0.24, 0.3)
		if bool(b.on):
			bg = Color(0.3, 0.5, 0.35)
		if bool(b.get("debug", false)):
			bg = Color(0.45, 0.22, 0.2) if not hov else Color(0.6, 0.3, 0.25)
		elif hov:
			bg = bg.lightened(0.18)
		rc(ci, r.position.x, r.position.y, r.size.x, r.size.y, bg)
		font.draw(ci, Vector2(r.position.x + 2, r.position.y + (r.size.y - 7.0) * 0.5), str(b.label), Color(1, 1, 1) if not bool(b.get("debug", false)) else Color(1.0, 0.85, 0.8))
	font.draw(ci, Vector2(PANEL_X + 3, 213), "DEBUG (NOT RULES)", Color(1.0, 0.4, 0.35))
	var hints: Array = ["WASD MOVE", "LMB SEED  RMB WATER", "SHIFT+LMB TACKLE", "SHIFT+RMB BAZOOKA", "SPACE PAUSE  N DAY", "1 2 3 SPEED  R REMOVE", "TAB LIST  G PAGE", "F5 SAVE  F9 LOAD", "H HIDDEN  M DETECT", "RMB OR ESC: END TOOL"]
	for i: int in range(hints.size()):
		font.draw(ci, Vector2(PANEL_X + 3, 262 + i * 9), str(hints[i]), Color(0.7, 0.78, 0.85))

func _info(ci: CanvasItem, g: RefCounted) -> void:
	rc(ci, 0, INFO_Y, PANEL_X, 72, Color(0.07, 0.08, 0.1))
	rc(ci, 0, INFO_Y, PANEL_X, 1, Color(0.3, 0.35, 0.4))
	var lines: Array[String] = g.info_lines()
	var n_log: int = mini(4, g.log.size())
	for i: int in range(mini(8, lines.size())):
		var c: Color = Color(0.85, 0.9, 0.95)
		if i >= 4:
			var li: int = g.log.size() - n_log + (i - 4)
			var rec: Dictionary = g.log[li] if li >= 0 and li < g.log.size() else {}
			var k: String = str(rec.get("kind", ""))
			c = {"debug": Color(1.0, 0.5, 0.4), "reward": Color(1.0, 0.95, 0.5), "damage": Color(1.0, 0.65, 0.6), "defeat": Color(0.7, 1.0, 0.7), "crop": Color(0.7, 0.95, 1.0)}.get(k, Color(0.8, 0.85, 0.9))
		elif i == 1:
			c = Color(0.8, 1.0, 0.85)
		font.draw(ci, Vector2(3, INFO_Y + 3 + i * 8), lines[i], c)
