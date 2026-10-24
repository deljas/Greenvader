extends SceneTree
## 独立検証2-E: 第2弾の仮スプライト23枚の画像検査(サイズ・透明背景・輪郭線なし・足元基準・色数)と確認用の拡大一覧の生成。入口スクリプト。
const L: GDScript = preload("res://tests/content_pack/independent2/lib2.gd")
const Defs: GDScript = preload("res://scripts/content_pack/content_defs.gd")
const OUT: String = "res://evidence/content_pack/independent2"
var t: RefCounted = L.new()

const NEW_ENEMY: Array = ["root_mole", "skunk", "hippo", "honey_bear", "sewer_rat", "manhole", "bat_flock", "iron_rhino", "thunder_eel", "decoy_newt", "decoy_tail", "mirror_lizard", "pistol_shrimp", "balloon_frog", "glass_deer"]
const NEW_CROP: Array = ["evening_primrose", "dandelion", "mimosa", "kudzu", "loofah", "hinoki", "apple", "balsam"]

func _initialize() -> void:
	var meta: Dictionary = Defs.load_json("res://data/content_pack/sprites.json").sprites
	var en: Dictionary = Defs.load_enemies()
	var cr: Dictionary = Defs.load_crops()
	var sheet: Image = Image.create(8 * 90 + 20, 8 * 70 + 40, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.35, 0.35, 0.4, 1.0))
	var idx: int = 0
	var bottom_info: Dictionary = {}
	for k: String in NEW_ENEMY + NEW_CROP:
		var m: Dictionary = meta[k]
		var im: Image = Image.new()
		var err: int = im.load("res://assets/content_pack/" + str(m.file))
		t.ck("sprite_loads_" + k, err == OK)
		if err != OK:
			continue
		var want: Array = (en[k] if en.has(k) else cr[k]).image
		t.ck("sprite_size_matches_def_" + k, im.get_width() == int(want[0]) and im.get_height() == int(want[1]) and im.get_width() == int(m.size[0]) and im.get_height() == int(m.size[1]), "%dx%d want %s" % [im.get_width(), im.get_height(), str(want)])
		t.ck("sprite_foot_bottom_center_" + k, int(m.foot[0]) == int(m.size[0]) / 2 and int(m.foot[1]) == int(m.size[1]), str(m.foot))
		# 画素検査
		var w: int = im.get_width()
		var h: int = im.get_height()
		var opaque: int = 0
		var visible: int = 0
		var alphas: Dictionary = {}
		var partial: int = 0
		var colors: Dictionary = {}
		var bottom_opaque: bool = false
		var edge_cols: Dictionary = {}
		var edge_n: int = 0
		for y: int in range(h):
			for x: int in range(w):
				var c: Color = im.get_pixel(x, y)
				if c.a > 0.01:
					visible += 1
					alphas[snappedf(c.a, 0.01)] = true
				if c.a > 0.99:
					opaque += 1
					colors[c.to_rgba32()] = true
					if y == h - 1:
						bottom_opaque = true
					# 外側(透明またはキャンバス外)に接する画素 = 輪郭にあたる位置
					var edge: bool = false
					for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
						var nx: int = x + d.x
						var ny: int = y + d.y
						if nx < 0 or ny < 0 or nx >= w or ny >= h or im.get_pixel(nx, ny).a < 0.01:
							edge = true
					if edge:
						edge_n += 1
						edge_cols[c.to_rgba32()] = int(edge_cols.get(c.to_rgba32(), 0)) + 1
				elif c.a > 0.01:
					partial += 1
		t.ck("sprite_has_content_" + k, visible >= 6, "visible=%d opaque=%d colors=%d" % [visible, opaque, colors.size()])
		# 半透明は、ガラスジカ(透き通る設計)だけに限る。ほかは完全不透明か完全透明のみ(ぼかし・アンチエイリアスなし)
		if k == "glass_deer":
			t.ck("sprite_glass_deer_few_alpha_levels", alphas.size() <= 4, "alpha_levels=%s" % str(alphas.keys()))
		else:
			t.ck("sprite_no_antialias_alpha_" + k, partial == 0, "partial=%d" % partial)
		# 足元基準: 足元の座標は画像の下辺中央。飛行・水中・半透明の種は下辺に画素が届かなくてもよい(情報)
		bottom_info[k] = bottom_opaque
		# 輪郭線なし: 外周の画素が1色の暗色に偏っていない
		var maxshare: float = 0.0
		var domdark: bool = false
		for ck: Variant in edge_cols.keys():
			var share: float = float(edge_cols[ck]) / float(maxi(edge_n, 1))
			if share > maxshare:
				maxshare = share
				var col: Color = Color.from_rgba8((int(ck) >> 24) & 255, (int(ck) >> 16) & 255, (int(ck) >> 8) & 255, int(ck) & 255)
				domdark = col.get_luminance() < 0.2
		t.ck("sprite_no_dark_outline_" + k, not (domdark and maxshare > 0.8) or edge_n < 10, "edge=%d dominant_share=%.2f dark=%s" % [edge_n, maxshare, str(domdark)])
		# 拡大一覧
		var col_i: int = idx % 8
		var row_i: int = idx / 8
		var z: int = 4 if maxi(w, h) <= 24 else 2
		var big: Image = im.duplicate()
		big.resize(w * z, h * z, Image.INTERPOLATE_NEAREST)
		sheet.blend_rect(big, Rect2i(0, 0, big.get_width(), big.get_height()), Vector2i(10 + col_i * 90, 10 + row_i * 70 + (60 - big.get_height()) if big.get_height() < 60 else 10 + row_i * 70))
		idx += 1
	var no_bottom: Array = []
	for k2: String in bottom_info.keys():
		if not bottom_info[k2]:
			no_bottom.append(k2)
	t.ck("sprite_bottom_row_empty_only_for_air_water_glass", no_bottom.all(func(x: String) -> bool: return x in ["bat_flock", "thunder_eel", "balloon_frog", "glass_deer"]), str(no_bottom))
	# 分身と本体の見た目: 分身は本体と同じ見た目(尾が残っている状態)
	var a: Image = Image.new()
	var b: Image = Image.new()
	a.load("res://assets/content_pack/decoy_newt.png")
	b.load("res://assets/content_pack/decoy_tail.png")
	var same: bool = a.get_width() == b.get_width() and a.get_height() == b.get_height()
	var diff: int = 0
	if same:
		for y: int in range(a.get_height()):
			for x: int in range(a.get_width()):
				if a.get_pixel(x, y) != b.get_pixel(x, y):
					diff += 1
	t.ck("decoy_tail_sprite_same_as_newt_body", same and diff == 0, "diff_pixels=%d" % diff)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	sheet.save_png(OUT + "/sprites_contact_sheet.png")
	t.finish("sprite_v", OUT, self)
