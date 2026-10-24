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
	var w: float = floorf(float(sz.x) * sc)
	var h: float = floorf(float(sz.y) * sc)
	var fo: Vector2 = (bank.foot_of(name) * sc).floor()
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
		if hab == "air" and str(e.state) not in ["ground", "climb"]:
			y += 400.0
		if str(es.def_of(e).get("size", "")) != "":
			y = float(es.rect_of_struct(e).end.y * CELL)
		items.append([y, "enemy", e])
	for p: Dictionary in es.piles:
		items.append([float(p.pos.y) * S + 2.0, "pile", p])
	for pk: Dictionary in g.pack.crops.pickups:
		items.append([float(pk.pos.y) * S + 2.0, "pickup", pk])
	items.append([g.hero_pos.y * S + 4.0, "hero", null])
	items.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	for it: Array in items:
		match str(it[1]):
			"crop": _crop(ci, g, it[2], t)
			"enemy": _enemy(ci, g, it[2], t)
			"pile": _pile(ci, g, it[2])
			"pickup": _pickup(ci, it[2], t)
			"hero": _hero(ci, g, t)
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
		spr(ci, "needle", pp, {"rot": Vector2(pr.dir).angle()})

func _crop(ci: CanvasItem, g: RefCounted, c: Dictionary, t: float) -> void:
	var cs: RefCounted = g.pack.crops
	var kind: String = str(c.kind)
	var foot: Vector2 = Vector2((float(c.cell.x) + float(c.size.x) * 0.5) * CELL, float(c.cell.y + c.size.y) * CELL - 1.0)
	var mature: bool = bool(c.mature)
	var o: Dictionary = {}
	if not mature:
		o["scale"] = 0.5
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

func _hero(ci: CanvasItem, g: RefCounted, t: float) -> void:
	var foot: Vector2 = g.hero_pos * S + Vector2(0, 4)
	shadow(ci, foot, 4)
	var rect: Rect2 = spr(ci, "hero", foot, {"flip": g.aim.x < 0.0})
	if g.elapsed < g.slow_until:
		icon(ci, "drop", Vector2(foot.x - 1, rect.position.y - 5), Color(0.6, 0.45, 0.25))
	if g.hp < g.max_hp - 0.01:
		hpbar(ci, Vector2(foot.x, rect.position.y - 3), g.hp / g.max_hp)
	if g.tool == "combat":
		dotted(ci, g.hero_pos * S + g.aim * 10.0, g.hero_pos * S + g.aim * 22.0, Color(1, 1, 1, 0.5), 4.0)

# ---------------------------------------------------------------- 敵
func _enemy(ci: CanvasItem, g: RefCounted, e: Dictionary, t: float) -> void:
	var es: RefCounted = g.pack.enemies
	var kind: String = str(e.kind)
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
			"stuck", "wet", "howl", "rage", "shell_break":
				ring(ci, p, 6.0 + 10.0 * age, Color(1, 1, 1, 0.7 * (1.0 - age)), 2)

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
	out.append({"r": Rect2(x0, 12, 61, 10), "label": "ENEMY", "action": "tab:enemy", "on": g.tab == "enemy"})
	out.append({"r": Rect2(x0 + 63, 12, 61, 10), "label": "CROP", "action": "tab:crop", "on": g.tab == "crop"})
	var list: Array = Game.ENEMY_LIST if g.tab == "enemy" else Game.CROP_LIST
	for i: int in range(list.size()):
		var col: int = i % 2
		var row: int = i / 2
		var kind: String = list[i][0]
		var act: String = ("pick_enemy:" if g.tab == "enemy" else "pick_crop:") + kind
		var on: bool = (g.tool == "enemy" and g.sel_enemy == kind) if g.tab == "enemy" else (g.tool == "crop" and g.sel_crop == kind)
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
	var hints: Array = ["WASD MOVE", "LMB SEED  RMB WATER", "SHIFT+LMB TACKLE", "SHIFT+RMB BAZOOKA", "SPACE PAUSE  N DAY", "1 2 3 SPEED  R REMOVE", "TAB LIST  ESC COMBAT", "F5 SAVE  F9 LOAD", "H SHOW HIDDEN", "TOOL:LMB MAP RMB END"]
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
