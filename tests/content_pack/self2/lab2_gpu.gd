extends SceneTree
## 第2弾の確認画面の実GPU撮影(入口スクリプト、非headless)。ウィンドウは前面化しない(unfocusable)。入力は Input.parse_input_event のみ。
## 実行(隔離プロジェクトのみ): Godot --path C:/godot/greenvader_content_sandbox --script res://tests/content_pack/self2/lab2_gpu.gd
## 画像は evidence/content_pack/self2/gpu/*.png(640x360のビューポート画像)。実GPUで描けない環境では NOT_RUN と記録して終了する。
const OUT_DIR: String = "res://evidence/content_pack/self2"
const GPU_DIR: String = "res://evidence/content_pack/self2/gpu"
const Common2: GDScript = preload("res://scripts/content_pack/common2.gd")

var checks: Array = []
var shots: Array = []
var lab: Node = null
var g: RefCounted = null
var es: RefCounted = null
var cs: RefCounted = null
var adapter: String = ""

func ck(name: String, status: String, detail: String = "") -> void:
	checks.append({"name": name, "status": status, "detail": detail})

func frame() -> void:
	await process_frame

func draw_frames(n: int = 3) -> void:
	for i: int in range(n):
		await RenderingServer.frame_post_draw

func finish(code: int) -> void:
	var fails: int = 0
	var notrun: int = 0
	for c: Dictionary in checks:
		print("%s %s %s" % [c.status, c.name, c.detail])
		if c.status == "FAIL":
			fails += 1
		elif c.status == "NOT_RUN":
			notrun += 1
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var f: FileAccess = FileAccess.open(OUT_DIR + "/lab2_gpu.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"suite": "lab2_gpu", "adapter": adapter, "driver": RenderingServer.get_current_rendering_driver_name(),
		"display_server": DisplayServer.get_name(), "window_size": [root.size.x, root.size.y], "total": checks.size(), "failed": fails, "not_run": notrun,
		"shots": shots, "checks": checks}, "\t"))
	f.close()
	print("lab2_gpu total=%d failed=%d not_run=%d adapter=%s" % [checks.size(), fails, notrun, adapter])
	quit(code)

func _initialize() -> void:
	root.unfocusable = true
	adapter = RenderingServer.get_video_adapter_name()
	var gpu_ok: bool = DisplayServer.get_name() != "headless" and adapter != ""
	if not gpu_ok:
		ck("gpu_available", "NOT_RUN", "display_server=%s adapter='%s'" % [DisplayServer.get_name(), adapter])
		finish(0)
		return
	ck("gpu_available", "PASS", "adapter=%s driver=%s display=%s" % [adapter, RenderingServer.get_current_rendering_driver_name(), DisplayServer.get_name()])
	var scn: PackedScene = load("res://scenes/content_pack/content_lab.tscn")
	lab = scn.instantiate()
	lab.auto_step = false
	root.add_child(lab)
	await frame()
	await draw_frames(2)
	g = lab.game
	es = g.pack.enemies
	cs = g.pack.crops
	lab.ui.freeze = true
	lab.ui.t = 0.0
	root.unfocusable = true
	await frame()
	ck("window_unfocusable_flag_set", "PASS" if root.unfocusable and root.get_flag(Window.FLAG_NO_FOCUS) else "FAIL", "unfocusable=%s (ウィンドウ生成時の初回フォーカスはスクリプトでは防げない)" % str(root.unfocusable))
	g.seeds = 800
	var base: Image = await shot_baseline()
	await shot_lineup(base)
	await shot_crops_lineup()
	await shot_mole_wet()
	await shot_water_species()
	await shot_air()
	await shot_directions()
	await shot_manholes()
	await shot_crops_states()
	await shot_big_and_glass()
	await shot_panel_pages()
	await shot_night()
	check_nearest_setting()
	finish(0)

# ---------------------------------------------------------------- 撮影
func capture(name: String, note: String) -> Image:
	await draw_frames(3)
	var im: Image = root.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(GPU_DIR))
	im.save_png(GPU_DIR + "/" + name + ".png")
	var colors: Dictionary = {}
	for y: int in range(im.get_height()):
		for x: int in range(im.get_width()):
			colors[im.get_pixel(x, y).to_rgba32()] = true
	var mult_ok: bool = im.get_width() % 640 == 0 and im.get_height() % 360 == 0 and im.get_width() >= 640
	ck("shot_%s_size_multiple_of_640x360" % name, "PASS" if mult_ok else "FAIL", "%dx%d" % [im.get_width(), im.get_height()])
	ck("shot_%s_limited_palette_no_blur" % name, "PASS" if colors.size() <= 1500 else "FAIL", "unique_colors=%d" % colors.size())
	shots.append({"name": name, "file": "evidence/content_pack/self2/gpu/%s.png" % name, "size": [im.get_width(), im.get_height()], "unique_colors": colors.size(), "note": note})
	return im

func reset_world() -> void:
	g.clear_enemies()
	cs.crops.clear()
	cs._by_id.clear()
	cs._occ.clear()
	cs._root_occ.clear()
	cs.fruits.clear()
	cs.pickups.clear()
	g.host.helper_list.clear()
	g.host.stage_override.clear()
	g.terrain_dirty = true
	g.host.day = true
	g.tool = "combat"
	g.tab = "enemy2"
	g.sel_crop_id = 0
	g.hero_pos = Vector2(60, 84)
	g.paused = false
	g.bullets.clear()
	g.fx_list.clear()
	g.log.clear()
	g.hp = g.max_hp
	g.hover_cell = Vector2i(-1, -1)
	g.show_detect = false
	g.show_hidden = false
	g.pack.common.wet.clear()
	g.pack.common.hero_stun_until = 0.0
	g.pack.common.helper_stop.clear()
	g.slow_until = 0.0
	lab.ui.mouse = Vector2(-10, -10)
	g.debug_flash_until = -1.0

func sp(kind: String, x: float, y: float) -> int:
	return es.spawn(kind, Vector2(x, y), "initial")

func R(id: int) -> Dictionary:
	return es.ref(id)

func crop(kind: String, x: int, y: int, mature: bool = true) -> int:
	var r: Dictionary = cs.spawn_crop(kind, Vector2i(x, y), 20, {"mature": mature, "watered": true, "skip_check": true})
	return int(r.id)

## 2枚の画像の、矩形内で異なる画素の外接矩形(空なら Rect2i())
func diff_bounds(a: Image, b: Image, r: Rect2i) -> Rect2i:
	var x0: int = 100000
	var y0: int = 100000
	var x1: int = -1
	var y1: int = -1
	for y: int in range(maxi(0, r.position.y), mini(a.get_height(), r.end.y)):
		for x: int in range(maxi(0, r.position.x), mini(a.get_width(), r.end.x)):
			if a.get_pixel(x, y) != b.get_pixel(x, y):
				x0 = mini(x0, x)
				y0 = mini(y0, y)
				x1 = maxi(x1, x)
				y1 = maxi(y1, y)
	if x1 < 0:
		return Rect2i()
	return Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1)

func count_diff(a: Image, b: Image, r: Rect2i) -> int:
	var n: int = 0
	for y: int in range(maxi(0, r.position.y), mini(a.get_height(), r.end.y)):
		for x: int in range(maxi(0, r.position.x), mini(a.get_width(), r.end.x)):
			if a.get_pixel(x, y) != b.get_pixel(x, y):
				n += 1
	return n

# 0. 基準(何も置かない画面。差分検出に使う)
func shot_baseline() -> Image:
	reset_world()
	g.hero_pos = Vector2(8, 140)
	return await capture("wave2_baseline_empty", "基準(何も置かない)。以降の撮影との差分で、各スプライトが実際に描かれて足元基準で接地していることを機械確認する")

const ENEMY_LINE: Array = ["root_mole", "skunk", "sewer_rat", "decoy_newt", "mirror_lizard", "pistol_shrimp", "balloon_frog", "bat_flock",
	"manhole", "thunder_eel", "glass_deer", "honey_bear", "iron_rhino", "hippo"]

# 1. 動物13種+付属(静止、状態記号なし)
func shot_lineup(base: Image) -> void:
	reset_world()
	g.hero_pos = Vector2(8, 140)
	# x(論理px), y(論理px)。下の行ほど大きい個体。足元は y*2+3
	var pos: Dictionary = {
		"root_mole": Vector2(20, 90), "skunk": Vector2(50, 90), "sewer_rat": Vector2(76, 90), "decoy_newt": Vector2(98, 90),
		"mirror_lizard": Vector2(150, 90), "pistol_shrimp": Vector2(180, 90), "balloon_frog": Vector2(214, 90),
		"bat_flock": Vector2(238, 90), "manhole": Vector2(20, 112), "thunder_eel": Vector2(48, 112),
		"glass_deer": Vector2(80, 124), "honey_bear": Vector2(118, 126), "iron_rhino": Vector2(162, 126), "hippo": Vector2(212, 126)}
	var ids: Dictionary = {}
	for k: String in ENEMY_LINE:
		if k == "manhole":
			var net: Dictionary = es.spawn_manhole_net([Vector2(pos[k])], "initial")
			ids[k] = int((net.manholes as Array)[0])
		elif k == "bat_flock":
			ids[k] = int(es.spawn_bat_flock(Vector2(pos[k]), "initial")[0])
		else:
			ids[k] = sp(k, pos[k].x, pos[k].y)
	R(int(ids["root_mole"])).state = "peek"   # 地上に顔を出している姿(スプライトを見せる)
	# 吊り下がるコウモリは1匹だけを数える(群れの他の5匹は円状にずれる)
	var im: Image = await capture("wave2_enemies_lineup", "第2弾の動物13種+付属(マンホール)を静止で並べた画像。コウモリは群れ(ねぐら)")
	var bank: RefCounted = lab.view.bank
	var bad: Array = []
	var detail: Array = []
	for k2: String in ENEMY_LINE:
		var p: Vector2 = Vector2(pos[k2])
		var sz: Vector2i = bank.size_of(k2)
		var foot: Vector2 = p * 2.0 + Vector2(0, 3)
		if k2 == "manhole":
			foot = Vector2(p.x * 2.0, p.y * 2.0 + 4.0)
		var r: Rect2i = Rect2i(int(foot.x) - sz.x - 8, int(foot.y) - sz.y - 8, sz.x * 2 + 16, sz.y + 14)
		var n: int = count_diff(base, im, r)
		var bb: Rect2i = diff_bounds(base, im, r)
		# 足元基準: 描かれた領域の最下行(影を含む)が足元の行から2行以内。吊り下がるコウモリと、浮かぶものは除く
		var bottom: int = bb.end.y - 1
		# 向きの点線(スカンク・カガミトカゲ)と水面の波紋(ウナギ)は足元より下に伸びるため、許容を広げる
		var tol: float = 8.0 if k2 in ["skunk", "mirror_lizard", "thunder_eel"] else 3.0
		var ok: bool = n >= 6 and absf(float(bottom) - foot.y) <= tol
		if k2 == "bat_flock":
			ok = n >= 6
		if not ok:
			bad.append("%s diff=%d bottom=%d foot=%.0f" % [k2, n, bottom, foot.y])
		detail.append("%s:%d/%d" % [k2, n, bottom - int(foot.y)])
	ck("wave2_enemy_sprites_drawn_and_grounded_at_foot_row", "PASS" if bad.is_empty() else "FAIL", str(bad) if not bad.is_empty() else ",".join(detail))
	# 画素一致: ハチミツグマ(不透明画素)が画面にそのまま写る
	var src: Image = bank.image("honey_bear")
	var foot_b: Vector2 = Vector2(pos["honey_bear"]) * 2.0 + Vector2(0, 3)
	var tl: Vector2 = (foot_b - bank.foot_of("honey_bear")).floor()
	var total: int = 0
	var same: int = 0
	for y: int in range(src.get_height()):
		for x: int in range(src.get_width()):
			var c: Color = src.get_pixel(x, y)
			if c.a >= 0.99:
				total += 1
				var sc_c: Color = im.get_pixel(int(tl.x) + x, int(tl.y) + y)
				if absf(sc_c.r - c.r) < 0.02 and absf(sc_c.g - c.g) < 0.02 and absf(sc_c.b - c.b) < 0.02:
					same += 1
	ck("wave2_sprite_pixels_match_png_exactly_nearest_no_blur", "PASS" if total > 0 and float(same) / float(total) >= 0.98 else "FAIL", "honey_bear opaque px=%d exact=%d (%.1f%%)" % [total, same, 100.0 * float(same) / float(maxi(1, total))])

# 2. 植物8種(成熟と未成熟)
const CROP_LINE: Array = ["evening_primrose", "dandelion", "mimosa", "kudzu", "loofah", "balsam", "apple", "hinoki"]

func shot_crops_lineup() -> void:
	var base: Image = null
	reset_world()
	g.hero_pos = Vector2(8, 140)
	base = await capture("wave2_baseline_empty2", "基準(何も置かない、2枚目)")
	reset_world()
	g.hero_pos = Vector2(8, 140)
	var cells: Dictionary = {"evening_primrose": Vector2i(18, 12), "dandelion": Vector2i(22, 12), "mimosa": Vector2i(26, 12), "kudzu": Vector2i(30, 12),
		"loofah": Vector2i(34, 12), "balsam": Vector2i(38, 12), "apple": Vector2i(42, 12), "hinoki": Vector2i(48, 11)}
	for k: String in CROP_LINE:
		crop(k, cells[k].x, cells[k].y, true)
		crop(k, cells[k].x, cells[k].y + 8 if k not in ["apple", "hinoki"] else cells[k].y + 12, false)
	# 夜でない昼の見た目(ツキミソウはしぼんだ色)
	var im: Image = await capture("wave2_crops_lineup", "第2弾の植物8種。上段=成熟(等倍)、下段=未成熟(縮小)。昼はツキミソウがしぼんだ色")
	var bank: RefCounted = lab.view.bank
	var bad: Array = []
	for k2: String in CROP_LINE:
		var c: Vector2i = cells[k2]
		var sz: Vector2i = cs.size_of(k2)
		var foot: Vector2 = Vector2((float(c.x) + float(sz.x) * 0.5) * 8.0, float(c.y + sz.y) * 8.0 - 1.0)
		var isz: Vector2i = bank.size_of(k2)
		var r: Rect2i = Rect2i(int(foot.x) - isz.x, int(foot.y) - isz.y - 10, isz.x * 2, isz.y + 14)
		var n: int = count_diff(base, im, r)
		var bb: Rect2i = diff_bounds(base, im, r)
		var bottom: int = bb.end.y - 1
		if not (n >= 20 and absf(float(bottom) - foot.y) <= 6.0):
			bad.append("%s diff=%d bottom=%d foot=%.0f" % [k2, n, bottom, foot.y])
	ck("wave2_crop_sprites_drawn_and_grounded_at_foot", "PASS" if bad.is_empty() else "FAIL", str(bad))

# 3. 地中のモグラ(盛り土)と濡れたマス、飛び出し
func shot_mole_wet() -> void:
	reset_world()
	g.hero_pos = Vector2(90, 84)
	var m1: int = sp("root_mole", 150, 100)
	R(m1).state = "move"
	for i: int in range(8):
		R(m1).mounds.append({"pos": Vector2(150.0 - 4.0 * float(i + 1), 100.0 + sin(float(i)) * 1.0), "until": es.time + 2.0 + float(i)})
	var m2: int = sp("root_mole", 200, 100)
	R(m2).state = "pop"
	var m3: int = sp("root_mole", 200, 125)
	R(m3).state = "stunned"
	R(m3).until = es.time + 3.0
	var ids: Array = []
	for x: int in range(10, 15):
		for y: int in range(9, 12):
			ids.append(Vector2i(x, y))
	g.apply_events(g.pack.water_landed(ids))
	g.show_detect = true
	await capture("wave2_mole_mounds_wet_detect", "ネッコモグラ: 地中(薄い影と盛り土の列)、飛び出し予兆、目を回して地上。濡れたマス(青)。Mの検知印はモグラの盛り土の先に出る")
	g.show_detect = false

# 4. カバ・ウナギ(水中)と放電
func shot_water_species() -> void:
	reset_world()
	g.hero_pos = Vector2(90, 40)
	var h: int = sp("hippo", 28, 30)
	R(h).state = "float"
	var h2: int = sp("hippo", 88, 120)
	R(h2).state = "windup"
	R(h2).charge_dir = Vector2.LEFT
	var e1: int = sp("thunder_eel", 36, 14)
	R(e1).state = "windup"
	var e2: int = sp("thunder_eel", 28, 44)
	R(e2).state = "tired"
	var cells: Array = []
	for x: int in range(18, 26):
		cells.append(Vector2i(x, 11))
	R(e2).chain = [Vector2i(16, 11), Vector2i(17, 11), Vector2i(18, 11), Vector2i(19, 11)]
	g.apply_events(g.pack.water_landed(cells))
	var h3: int = sp("hippo", 36, 36)
	R(h3).state = "rest"
	g.fx_add("discharge", Vector2(36, 14), 0.9, {"radius": 30.0})
	g.elapsed = 0.3
	g.fx_list[0].t0 = 0.0
	g.apply_events([])
	await capture("wave2_water_hippo_eel", "カバ(水中=背中だけ水面、休み=ZZ、上陸して突進の予兆と線)・カミナリウナギ(予兆=光る輪、放電後=疲れと伝導した濡れたマス)")

# 5. コウモリ・フウセンガエル・酸
func shot_air() -> void:
	reset_world()
	g.hero_pos = Vector2(100, 100)
	var ids: Array = es.spawn_bat_flock(Vector2(110, 66), "initial")
	for i: int in range(ids.size()):
		R(int(ids[i])).state = "swarm" if i < 3 else ("dive" if i == 3 else ("low" if i == 4 else "roost"))
		if i < 5:
			R(int(ids[i])).pos = Vector2(100.0 + float(i) * 8.0, 84.0 + float(i % 2) * 6.0)
	var ids2: Array = es.spawn_bat_flock(Vector2(150, 56), "initial")
	var f: Array = es.spawn_frog_flock(Vector2(200, 100), "initial")
	R(int(f[0])).state = "hop"
	R(int(f[1])).state = "inflate"
	R(int(f[1])).until = es.time + 0.5
	R(int(f[2])).state = "float"
	es.add_acid(Vector2(220, 125), 0, 16.0, 5.0, 3.0)
	var f2: Array = es.spawn_frog_flock(Vector2(60, 125), "initial")
	for id: Variant in f2:
		R(int(id)).state = "float"
	await capture("wave2_air_bats_frogs_acid", "コウモリ(吊り下がり=逆さ、乱れ飛び・急降下=影つき、低空)・フウセンガエル(地上=跳ね、膨らむ、浮上=影が地面に残る)・酸の水たまり")

# 6. 向きの判定(スカンク・カガミトカゲ)、衝撃波、臭気、気絶
func shot_directions() -> void:
	reset_world()
	g.hero_pos = Vector2(110, 100)
	var sk: int = sp("skunk", 150, 70)
	R(sk).state = "windup"
	R(sk).face = Vector2.LEFT
	es.add_odor(Vector2(150, 70), Vector2.LEFT, 0, 50.0, 30.0, 8.0)
	var sk2: int = sp("skunk", 60, 130)
	R(sk2).face = Vector2.RIGHT
	var ml: int = sp("mirror_lizard", 190, 110)
	R(ml).face = Vector2.LEFT
	es.spawn_projectile({"kind": "reflected", "owner": ml, "pos": Vector2(170, 110), "dir": Vector2.LEFT, "speed": 80.0, "left": 100.0, "damage": 5.0})
	es.spawn_projectile({"kind": "reflected", "owner": ml, "pos": Vector2(160, 110), "dir": Vector2.LEFT, "speed": 80.0, "left": 100.0, "damage": 5.0})
	var ml2: int = sp("mirror_lizard", 220, 70)
	R(ml2).face = Vector2.DOWN
	R(ml2).state = "bite"
	var ps: int = sp("pistol_shrimp", 210, 40)
	R(ps).state = "windup"
	var ps2: int = sp("pistol_shrimp", 110, 40)
	R(ps2).state = "cooldown"
	g.host.helper_list.append({"id": 9201, "pos": Vector2(125, 100), "hp": 30.0, "max_hp": 50.0})
	g.host.helper_list.append({"id": 9202, "pos": Vector2(140, 105), "hp": 50.0, "max_hp": 50.0})
	g.apply_events(g.pack.relay_events([Common2.hero_stun_event(3.0, ps), Common2.helper_stop_event(9201, 3.0, "stun")]))
	g.fx_add("stun", g.hero_pos, 3.0)
	await capture("wave2_directions_odor_shock", "スカンク(尾を立てて予兆・正面120度の点線・臭気の扇形)・カガミトカゲ(正面の点線と反射弾)・タイホウエビ(予兆=光る輪、半径4m)・気絶した主人公(星)と仕事停止のおたすけ植物(星)")

# 7. マンホール網
func shot_manholes() -> void:
	reset_world()
	g.hero_pos = Vector2(100, 100)
	var net: Dictionary = es.spawn_manhole_net([Vector2(150, 80), Vector2(200, 90), Vector2(180, 120)], "initial")
	var mids: Array = net.manholes
	var cl: int = crop("bamboo", 49, 22, true)
	cs._occ.clear()
	es.enemies[0].state = "closed"
	es.enemies[0].plug = cl
	var r1: int = sp("sewer_rat", 145, 90)
	R(r1).state = "walk"
	var r2: int = sp("sewer_rat", 196, 100)
	R(r2).state = "gnaw"
	var r3: int = sp("sewer_rat", 175, 125)
	R(r3).state = "ug"
	await capture("wave2_manhole_net", "マンホール網(同じ網は点線でつなぐ)。閉じたマンホール(緑がかった色、上に植物)・ドブネズミ(地下の個体は描かない)")

# 8. 植物の状態
func shot_crops_states() -> void:
	reset_world()
	g.hero_pos = Vector2(8, 140)
	var kz: int = crop("kudzu", 30, 18, true)
	var roots: Array = [Vector2i(31, 18), Vector2i(32, 18), Vector2i(33, 18), Vector2i(33, 19), Vector2i(34, 19), Vector2i(30, 19), Vector2i(29, 19), Vector2i(29, 20)]
	cs._by_id[kz].ext.roots = roots.duplicate()
	for rc: Vector2i in roots:
		cs._root_occ[rc] = kz
	var ms1: int = crop("mimosa", 20, 18, true)
	var ms2: int = crop("mimosa", 22, 18, true)
	cs._by_id[ms2].ext.closed = true
	var lf: int = crop("loofah", 24, 17, true)
	cs._by_id[lf].ext.water = 7
	var hk: int = crop("hinoki", 40, 20, true)
	var ap: int = crop("apple", 46, 18, true)
	cs.fruits.append({"id": 1, "cell": Vector2i(44, 20), "source_id": ap})
	cs.fruits.append({"id": 2, "cell": Vector2i(48, 21), "source_id": ap})
	cs.fruits.append({"id": 3, "cell": Vector2i(45, 21), "source_id": ap})
	var dd: int = crop("dandelion", 12, 22, true)
	var bs: int = crop("balsam", 14, 22, true)
	g.fx_add("burst", Vector2(58, 92), 0.6, {"radius_px": 20.0})
	g.elapsed = 0.2
	g.fx_list[0].t0 = 0.0
	g.apply_events([])
	g.sel_crop_id = kz
	await capture("wave2_crops_states", "クズ(株+這う根のマスとR数)・オジギソウ(開/閉)・ヘチマ(貯水の青い点)・ヒノキ(北側の動的な日陰)・リンゴ(落果の赤い点)・ホウセンカのはじけ")

# 9. 大型・ガラスジカ・ハチミツグマ・サイの状態
func shot_big_and_glass() -> void:
	reset_world()
	g.hero_pos = Vector2(8, 140)
	var hb: int = sp("honey_bear", 50, 100)
	R(hb).state = "sleep"
	R(hb).satiety = 3
	var hb2: int = sp("honey_bear", 110, 100)
	R(hb2).state = "enraged"
	var rh: int = sp("iron_rhino", 70, 130)
	R(rh).rust = 3
	var rh2: int = sp("iron_rhino", 135, 130)
	R(rh2).rust = 5
	R(rh2).state = "windup"
	R(rh2).charge_dir = Vector2.RIGHT
	var gd: int = sp("glass_deer", 200, 100)
	var gd2: int = sp("glass_deer", 225, 125)
	var nt: int = sp("decoy_newt", 190, 70)
	R(nt).tail = false
	var nt2: int = sp("decoy_newt", 215, 70)
	var dt: int = sp("decoy_tail", 240, 70)
	g.show_hidden = true
	g.show_detect = true
	g.fx_add("glass_break", Vector2(180, 125), 0.9)
	g.elapsed = 0.25
	g.fx_list[0].t0 = 0.0
	g.apply_events([])
	await capture("wave2_bear_rhino_glass_newt", "ハチミツグマ(眠り=ZZと満腹の黄点、怒り)・テツヨロイサイ(錆3と5、突進の予兆)・ガラスジカ(虹色の光とキラキラ、砕ける破片)・ブンシンイモリ(尾が再生中=短い、満タン、分身=H表示でDC)・Mの検知印(ガラスジカは虹色)")
	g.show_hidden = false
	g.show_detect = false

# 10. パネル(第2ページ)
func shot_panel_pages() -> void:
	reset_world()
	g.hero_pos = Vector2(8, 140)
	lab.do_action("tab:enemy2")
	lab.do_action("pick_enemy:skunk")
	g.hover_cell = Vector2i(20, 22)
	await capture("wave2_panel_enemy2", "パネルの第2ページ(ENM2): 動物13種+付属+抽選+試験用おたすけ植物")
	lab.do_action("tab:crop2")
	lab.do_action("pick_crop:hinoki")
	g.hover_cell = Vector2i(30, 24)
	var m: Vector2 = Vector2(30.5 * 8.0, 24.5 * 8.0)
	var ev: InputEventMouseMotion = InputEventMouseMotion.new()
	var sc: float = root.get_final_transform().x.x
	ev.position = m * sc
	ev.global_position = m * sc
	Input.parse_input_event(ev)
	await frame()
	await capture("wave2_panel_crop2_preview", "パネルの第2ページ(CRP2): ヒノキの配置プレビュー(緑=可)と価格")
	lab.do_action("tool:combat")

# 11. 夜
func shot_night() -> void:
	reset_world()
	g.hero_pos = Vector2(60, 100)
	g.host.day = false
	crop("evening_primrose", 20, 18, true)
	crop("evening_primrose", 23, 18, true)
	crop("glow_moss", 28, 18, true)
	var ids: Array = es.spawn_bat_flock(Vector2(110, 66), "initial")
	for i: int in range(ids.size()):
		R(int(ids[i])).state = "swarm"
		R(int(ids[i])).pos = Vector2(90.0 + float(i) * 6.0, 84.0 + float(i % 3) * 6.0)
	await capture("wave2_night", "夜: ツキミソウは明るく開く、コウモリの乱れ飛び、ヒカリゴケの光")
	g.host.day = true

func check_nearest_setting() -> void:
	var filt: int = int(ProjectSettings.get_setting("rendering/textures/canvas_textures/default_texture_filter", 1))
	var mode: String = str(ProjectSettings.get_setting("display/window/stretch/mode", ""))
	var scale_mode: String = str(ProjectSettings.get_setting("display/window/stretch/scale_mode", ""))
	ck("project_uses_nearest_and_integer_viewport_scaling", "PASS" if filt == 0 and mode == "viewport" and scale_mode == "integer" else "FAIL", "filter=%d mode=%s scale=%s" % [filt, mode, scale_mode])
	ck("lab_canvas_nearest", "PASS" if lab.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST else "FAIL", str(lab.texture_filter))
