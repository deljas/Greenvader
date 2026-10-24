extends SceneTree
## 独立検証: 仮スプライトの画像サイズ(カタログの値を手で転記)・足元基準データ・輪郭線の有無(ヒューリスティック)。
const OUT_DIR: String = "res://evidence/content_pack/independent"
# カタログ 2節・3.1節の「画像px」
const SIZES: Dictionary = {
	"wasabi": [12, 14], "giant_watermelon": [56, 40], "oleander": [24, 32], "four_leaf_clover": [10, 10], "golden_clover": [10, 10], "golden_four_leaf": [12, 12],
	"edamame": [14, 14], "sunflower": [14, 24], "tomato": [12, 18], "lotus": [22, 12], "corn": [12, 26], "pumpkin": [22, 16], "mint": [10, 10], "cactus": [12, 18],
	"grape": [12, 20], "strawberry": [10, 8], "lavender": [10, 14], "garlic": [10, 12], "bamboo": [10, 32], "flytrap": [14, 12], "potato": [12, 10], "rice": [8, 14],
	"tea": [20, 18], "sakura": [40, 48], "dokudami": [10, 10], "aloe": [12, 14], "pepper": [10, 14], "glow_moss": [10, 6], "clover": [10, 10],
	"shadow_brian": [32, 24], "tarachunade": [16, 12], "mushling_parent": [24, 28], "mushling_child": [12, 14], "quill_hedgehog": [16, 14], "grass_snake": [20, 8],
	"seed_bird": [14, 10], "junk_crab": [20, 18], "junk_crab_shell": [16, 12], "stray_wolf": [22, 14], "moss_turtle": [28, 20], "paint_chameleon": [18, 12],
	"slime_slug": [18, 10], "pouch_rabbit": [14, 14], "tongue_frog": [16, 14], "honeybee_hive": [14, 16], "honeybee_swarm": [12, 10], "armadillo": [18, 14],
	"sludge_carp": [20, 10], "leafcutter_ant": [6, 6], "ant_hill": [24, 14], "mimic_cabbage": [14, 12], "black_kite": [24, 12], "deer": [22, 22], "iron_jaw_beetle": [18, 16],
}
var checks: Array = []

func ck(name: String, ok: bool, detail: String = "") -> void:
	checks.append({"name": name, "status": "PASS" if ok else "FAIL", "detail": detail})

func _initialize() -> void:
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/content_pack/sprites.json")).sprites
	var bad_size: Array = []
	var bad_foot: Array = []
	var missing: Array = []
	var dark_edge: Dictionary = {}
	var translucent: Array = []
	for k: String in SIZES:
		if not meta.has(k):
			missing.append(k)
			continue
		var m: Dictionary = meta[k]
		var im: Image = Image.load_from_file(ProjectSettings.globalize_path("res://assets/content_pack/" + str(m.file)))
		if im == null:
			missing.append(k + "(file)")
			continue
		if im.get_width() != SIZES[k][0] or im.get_height() != SIZES[k][1] or int(m.size[0]) != int(SIZES[k][0]) or int(m.size[1]) != int(SIZES[k][1]):
			bad_size.append("%s %dx%d meta=%s want=%s" % [k, im.get_width(), im.get_height(), str(m.size), str(SIZES[k])])
		# 足元基準: 画像内(幅の中央付近、高さ以内)
		var foot: Array = m.get("foot", [])
		if foot.size() != 2 or foot[0] < 0 or foot[0] > im.get_width() or foot[1] < 0 or foot[1] > im.get_height() or absf(float(foot[0]) - float(im.get_width()) / 2.0) > float(im.get_width()) * 0.35 + 1.0:
			bad_foot.append("%s foot=%s size=%dx%d" % [k, str(foot), im.get_width(), im.get_height()])
		# 輪郭線ヒューリスティック: 不透明画素のうち透明画素に隣接する画素の暗さ
		var edge: int = 0
		var dark: int = 0
		var interior_lum: float = 0.0
		var interior_n: int = 0
		var edge_lum: float = 0.0
		for y: int in range(im.get_height()):
			for x: int in range(im.get_width()):
				var c: Color = im.get_pixel(x, y)
				if c.a > 0.0 and c.a < 0.99:
					translucent.append(k)
				if c.a < 0.99:
					continue
				var is_edge: bool = false
				for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var nx: int = x + d.x
					var ny: int = y + d.y
					if nx < 0 or ny < 0 or nx >= im.get_width() or ny >= im.get_height() or im.get_pixel(nx, ny).a < 0.5:
						is_edge = true
				var lum: float = 0.299 * c.r + 0.587 * c.g + 0.114 * c.b
				if is_edge:
					edge += 1
					edge_lum += lum
					if lum < 0.12:
						dark += 1
				else:
					interior_lum += lum
					interior_n += 1
		dark_edge[k] = [edge, dark, (edge_lum / maxf(1.0, float(edge))), (interior_lum / maxf(1.0, float(interior_n)))]
	ck("sprite_meta_and_files_exist_for_all_listed", missing.is_empty(), str(missing))
	ck("sprite_pixel_sizes_match_catalog", bad_size.is_empty(), str(bad_size))
	ck("sprite_foot_reference_data_present_inside_image", bad_foot.is_empty(), str(bad_foot))
	ck("sprites_hard_alpha_only_no_antialias_translucency", translucent.is_empty(), str(translucent.slice(0, 6)))
	# 輪郭線なし: 縁の画素のうち近黒(輝度<0.12)が過半を占める画像があれば疑い
	var suspects: Array = []
	for k: String in dark_edge:
		var d: Array = dark_edge[k]
		if d[0] > 0 and float(d[1]) / float(d[0]) > 0.5:
			suspects.append("%s %d/%d" % [k, d[1], d[0]])
	ck("sprite_no_dark_outline_heuristic_edge_pixels_not_mostly_near_black", suspects.is_empty(), str(suspects))
	# 占有と画像は別データ: 画像サイズと占有(crops.json size)が独立(スイカ 56x40 画像 vs 6x6マス)
	var crops: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/content_pack/crops.json")).crops
	ck("occupancy_independent_of_image_size", int(crops.giant_watermelon.size[0]) == 6 and int(crops.giant_watermelon.size[1]) == 6 and int(crops.giant_watermelon.image[0]) == 56 and int(crops.giant_watermelon.image[1]) == 40 and int(crops.sakura.size[0]) == 3 and int(crops.sakura.image[0]) == 40, "")
	var n_png: int = 0
	for f: String in DirAccess.get_files_at("res://assets/content_pack"):
		if f.ends_with(".png"):
			n_png += 1
	ck("png_count_63", n_png == 63, str(n_png))
	var fails: int = 0
	for c: Dictionary in checks:
		print("%s %s %s" % [c.status, c.name, c.detail])
		if c.status != "PASS":
			fails += 1
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var f: FileAccess = FileAccess.open(OUT_DIR + "/asset_v.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"suite": "asset_v", "total": checks.size(), "failed": fails, "checks": checks, "edge_stats": dark_edge}, "\t"))
	f.close()
	print("asset_v total=%d failed=%d" % [checks.size(), fails])
	quit(1 if fails > 0 else 0)
