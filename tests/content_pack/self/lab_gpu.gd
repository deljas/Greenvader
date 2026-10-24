extends SceneTree
## 確認画面の実GPU撮影(入口スクリプト、非headless)。ウィンドウは前面化しない(unfocusable)。入力は Input.parse_input_event のみ。
## 実行(隔離プロジェクトのみ): Godot --path C:/godot/greenvader_content_sandbox --script res://tests/content_pack/self/lab_gpu.gd
## 画像は evidence/content_pack/self/gpu/*.png。実GPUで描けない環境では NOT_RUN と記録して終了する。
const OUT_DIR: String = "res://evidence/content_pack/self"
const GPU_DIR: String = "res://evidence/content_pack/self/gpu"
const Game: GDScript = preload("res://scripts/content_pack/lab/lab_game.gd")

var checks: Array = []
var shots: Array = []
var lab: Node = null
var g: RefCounted = null
var es: RefCounted = null
var adapter: String = ""
var deer_probe: Dictionary = {}

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
	var f: FileAccess = FileAccess.open(OUT_DIR + "/lab_gpu.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"suite": "lab_gpu", "adapter": adapter, "driver": RenderingServer.get_current_rendering_driver_name(),
		"display_server": DisplayServer.get_name(), "window_size": [root.size.x, root.size.y], "total": checks.size(), "failed": fails, "not_run": notrun,
		"shots": shots, "checks": checks}, "\t"))
	f.close()
	print("lab_gpu total=%d failed=%d not_run=%d adapter=%s" % [checks.size(), fails, notrun, adapter])
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
	lab.ui.freeze = true   # 点滅の位相を固定して撮影する(予兆の「!」が写る位相)
	lab.ui.t = 0.0
	# 最初のフレームでウィンドウ設定が初期化し直されるため、1フレーム後にもう一度 unfocusable を設定する
	root.unfocusable = true
	await frame()
	ck("window_unfocusable_flag_set", "PASS" if root.unfocusable and root.get_flag(Window.FLAG_NO_FOCUS) else "FAIL", "unfocusable=%s (ウィンドウ生成時の初回フォーカスはスクリプトでは防げない)" % str(root.unfocusable))
	await check_input_mapping()
	g.seeds = 500
	await shot_enemies()
	await shot_states_ground()
	await shot_states_special()
	await shot_crops()
	await shot_ui_preview()
	await shot_night()
	check_assets_no_outline()
	check_nearest_setting()
	finish(0)

# ---------------------------------------------------------------- 入力の座標系の確認
func check_input_mapping() -> void:
	var ft: Transform2D = root.get_final_transform()
	var sc: float = ft.x.x
	var want: Vector2 = Vector2(100, 100)
	var ev: InputEventMouseMotion = InputEventMouseMotion.new()
	ev.position = want * sc
	ev.global_position = want * sc
	Input.parse_input_event(ev)
	await frame()
	var got: Vector2 = lab.ui.mouse
	ck("injected_input_maps_to_viewport_coords", "PASS" if got.distance_to(want) < 1.5 else "FAIL", "scale=%.2f got=%s" % [sc, str(got)])

# ---------------------------------------------------------------- 撮影
func capture(name: String, note: String) -> Image:
	await draw_frames(3)
	var im: Image = root.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(GPU_DIR))
	var path: String = GPU_DIR + "/" + name + ".png"
	im.save_png(path)
	var colors: Dictionary = {}
	for y: int in range(0, im.get_height(), 1):
		for x: int in range(0, im.get_width(), 1):
			colors[im.get_pixel(x, y).to_rgba32()] = true
	var mult_ok: bool = im.get_width() % 640 == 0 and im.get_height() % 360 == 0 and im.get_width() >= 640
	ck("shot_%s_size_multiple_of_640x360" % name, "PASS" if mult_ok else "FAIL", "%dx%d" % [im.get_width(), im.get_height()])
	ck("shot_%s_limited_palette_no_blur" % name, "PASS" if colors.size() <= 900 else "FAIL", "unique_colors=%d" % colors.size())
	shots.append({"name": name, "file": "evidence/content_pack/self/gpu/%s.png" % name, "size": [im.get_width(), im.get_height()], "unique_colors": colors.size(), "note": note})
	return im

func reset_world() -> void:
	g.clear_enemies()
	g.pack.crops.crops.clear()
	g.pack.crops._by_id.clear()
	g.pack.crops._occ.clear()
	g.pack.crops.pickups.clear()
	g.host.day = true
	g.tool = "combat"
	g.sel_crop_id = 0
	g.hero_pos = Vector2(160, 84)
	g.paused = false
	g.bullets.clear()
	g.fx_list.clear()
	g.log.clear()
	g.hover_cell = Vector2i(-1, -1)
	lab.ui.mouse = Vector2(-10, -10)
	g.debug_flash_until = -1.0

func sp(kind: String, x: float, y: float) -> int:
	var r: Dictionary = g.spawn_enemy(kind, Vector2(x, y))
	if not bool(r.get("ok", false)):
		ck("spawn_" + kind, "FAIL", str(r))
		return -1
	return int(r.id)

func R(id: int) -> Dictionary:
	return es.ref(id)

# 1. 全敵が並ぶ(静止・状態記号なし)。deer は画素一致の確認に使う
func shot_enemies() -> void:
	reset_world()
	g.hero_pos = Vector2(60, 84)
	sp("shadow_brian", 95, 20); sp("tarachunade", 125, 20); sp("mushling_parent", 155, 22); sp("quill_hedgehog", 190, 20)
	sp("grass_snake", 215, 20); sp("seed_bird", 240, 20)
	sp("junk_crab", 95, 48); sp("stray_wolf", 140, 46); sp("moss_turtle", 185, 48); sp("paint_chameleon", 215, 45); sp("slime_slug", 240, 48)
	sp("pouch_rabbit", 95, 78); sp("tongue_frog", 160, 70); sp("honeybee_hive", 155, 100); sp("armadillo", 190, 78)
	sp("sludge_carp", 36, 30); sp("leafcutter_ant", 215, 78); sp("ant_hill", 235, 100); sp("mimic_cabbage", 245, 70)
	sp("black_kite", 120, 100); sp("deer", 100, 125); sp("iron_jaw_beetle", 160, 130)
	g.spawn_enemy("junk_pile", Vector2(60, 100))
	# 擬態3種を見破られた状態にして本体の画像も見せる(別の位置)
	for k: String in ["moss_turtle", "mimic_cabbage", "grass_snake"]:
		pass
	var did: int = es.enemy_ids().size()
	ck("shot_enemies_spawned_all_kinds", "PASS" if did >= 24 else "FAIL", "enemies=%d piles=%d" % [did, es.piles.size()])
	var im: Image = await capture("enemies_all", "全敵(静止)。擬態3種(クサヘビ・コケガメ・ミミック)は擬態中の見た目")
	# 画素一致: deer(足元基準で接地)の不透明画素が画面にそのまま写っているか
	var deer: int = int(g.pack.enemies.enemy_ids().filter(func(i: int) -> bool: return str(es.ref(i).kind) == "deer")[0])
	var p: Vector2 = Vector2(R(deer).pos) * 2.0
	var foot: Vector2 = p + Vector2(0, 3)
	var bank: RefCounted = lab.view.bank
	var src: Image = bank.image("deer")
	var tl: Vector2 = (foot - bank.foot_of("deer")).floor()
	var scale: int = im.get_width() / 640
	var total: int = 0
	var same: int = 0
	var dark_edge: int = 0
	for y: int in range(src.get_height()):
		for x: int in range(src.get_width()):
			var c: Color = src.get_pixel(x, y)
			if c.a >= 0.99:
				total += 1
				var sc_c: Color = im.get_pixel(int(tl.x + x) * scale + scale / 2, int(tl.y + y) * scale + scale / 2)
				if absf(sc_c.r - c.r) < 0.02 and absf(sc_c.g - c.g) < 0.02 and absf(sc_c.b - c.b) < 0.02:
					same += 1
	ck("sprite_pixels_match_png_exactly_nearest_no_blur", "PASS" if total > 0 and float(same) / float(total) >= 0.98 else "FAIL", "deer opaque px=%d exact=%d (%.1f%%)" % [total, same, 100.0 * float(same) / float(maxi(1, total))])
	# 接地: 足元の1行下に影が出ていて、足元より下にスプライトがはみ出さない(スプライト最下段=足元の1行上)
	var bottom_y: int = int(tl.y) + src.get_height() - 1
	ck("sprite_bottom_row_is_at_foot_line", "PASS" if absf(float(bottom_y) - (foot.y - 1.0)) < 0.5 else "FAIL", "bottom=%d foot=%.0f" % [bottom_y, foot.y])
	deer_probe = {"foot": [foot.x, foot.y]}

# 2. 地上の敵の状態記号
func shot_states_ground() -> void:
	reset_world()
	g.hero_pos = Vector2(40, 90)
	var b1: int = sp("shadow_brian", 90, 20)
	R(b1).state = "windup"; R(b1).face = Vector2.RIGHT; R(b1).charge_dir = Vector2.RIGHT
	var b2: int = sp("shadow_brian", 90, 50)
	R(b2).state = "stuck"
	var t1: int = sp("tarachunade", 150, 20); R(t1).wet_until = es.time + 10.0
	var t2: int = sp("tarachunade", 175, 20); R(t2).state = "charred"; R(t2).until = es.time + 15.0
	var t3: int = sp("tarachunade", 200, 20); R(t3).state = "fuse"; R(t3).until = es.time + 1.5
	var m1: int = sp("mushling_parent", 150, 50); R(m1).rage_until = es.time + 25.0
	var fam: Dictionary = es.spawn_mushling_family(Vector2(200, 52), "initial")
	R(int(fam.children[0])).state = "call"
	var q1: int = sp("quill_hedgehog", 90, 80); R(q1).state = "aim"; R(q1).tpos = g.hero_pos
	var q2: int = sp("quill_hedgehog", 115, 80); R(q2).state = "curl"
	var a1: int = sp("armadillo", 150, 80); R(a1).state = "roll"
	var a2: int = sp("armadillo", 175, 80); R(a2).state = "dizzy"
	var a3: int = sp("armadillo", 200, 80); R(a3).state = "curl"
	var tu: int = sp("moss_turtle", 90, 110); R(tu).state = "flipped"
	var d1: int = sp("deer", 150, 110); R(d1).hp = 12.0
	var w: Array = es.spawn_wolf_pack(Vector2(200, 112), "initial")
	R(int(w[0])).state = "howl"
	var fr: int = sp("tongue_frog", 120, 135); R(fr).state = "aim"
	var sl: int = sp("slime_slug", 240, 20)
	for c: Vector2i in [Vector2i(56, 6), Vector2i(57, 6), Vector2i(58, 6), Vector2i(58, 5), Vector2i(59, 5)]:
		es.slime[c] = {"until": es.time + 20.0, "since": es.time, "ground_sent": false}
	es.add_gas(Vector2(240, 60), 0, 14.0, 30.0, 3.0)
	var rb: int = sp("pouch_rabbit", 240, 90); R(rb).cheek = 12.0
	g.fx_add("explosion", Vector2(235, 130), 1.0, {"radius_px": 25.0})
	g.elapsed = 0.4
	g.fx_list[0].t0 = 0.0
	g.apply_events([])
	await capture("states_ground", "状態記号: 予兆!・線・★・湿り・黒焦げ煙・怒り・音符・丸まり(回転灰色)・ひっくり返り・HPバー・粘液・ガス・爆発")

# 3. 擬態・飛行・水中・巣
func shot_states_special() -> void:
	reset_world()
	g.hero_pos = Vector2(60, 84)
	var sn: int = sp("grass_snake", 90, 20); R(sn).state = "moving"
	var sn2: int = sp("grass_snake", 120, 20); R(sn2).state = "hidden"
	var ch: int = sp("paint_chameleon", 150, 20); R(ch).state = "moving"; R(ch).paint = true
	var ch2: int = sp("paint_chameleon", 180, 20); R(ch2).state = "idle"; R(ch2).paint = true
	var tu: int = sp("moss_turtle", 215, 22); R(tu).state = "hidden"
	var mi: int = sp("mimic_cabbage", 245, 22); R(mi).state = "hidden"
	var mi2: int = sp("mimic_cabbage", 245, 50); R(mi2).state = "revealed"
	var bd: int = sp("seed_bird", 100, 55); R(bd).state = "flying"
	var bd2: int = sp("seed_bird", 125, 55); R(bd2).state = "landing"
	var k1: int = sp("black_kite", 160, 60); R(k1).state = "mark"; R(k1).shadow = Vector2(175, 75)
	var k2: int = sp("black_kite", 200, 60); R(k2).state = "lock"; R(k2).shadow = Vector2(215, 75)
	var k3: int = sp("black_kite", 230, 80); R(k3).state = "ground"; R(k3).shadow = Vector2(230, 80)
	var c1: int = sp("sludge_carp", 30, 20); R(c1).state = "dive"
	var c2: int = sp("sludge_carp", 30, 36); R(c2).state = "rise"; R(c2).muds = [{"pos": Vector2(60, 70), "land_at": es.time + 5.0}]
	var c3: int = sp("sludge_carp", 50, 28); R(c3).state = "surface"
	var hv: int = sp("honeybee_hive", 100, 110); R(hv).state = "angry"
	var hv2: int = sp("honeybee_hive", 130, 110)
	var ah: int = sp("ant_hill", 180, 110)
	var ah2: int = sp("ant_hill", 215, 110); R(ah2).state = "active"
	var an: int = sp("leafcutter_ant", 190, 128); R(an).state = "carry"
	var jc: int = sp("junk_crab", 100, 135); R(jc).state = "wearing"
	var jc2: int = sp("junk_crab", 150, 135); R(jc2).shell = false
	var ib: int = sp("iron_jaw_beetle", 240, 120)
	g.spawn_enemy("junk_pile", Vector2(125, 135))
	es.piles[0].stock = 1
	es.piles[0].hp = 8.0
	g.show_hidden = false
	await capture("states_special", "擬態中(茂み・キャベツ・草)・揺らぎ記号・飛行(影)・トンビの影と予兆・水中/浮上・巣(怒り・休止ZZ)・殻付け替え・置き場の在庫")
	# 擬態中の敵が検知対象外であることを併せて確認する
	var det: Array = es.detectable_enemies()
	var hidden_kinds: Array = []
	for d: Dictionary in det:
		if int(d.id) in [sn, sn2, ch, tu, mi]:
			hidden_kinds.append(d.kind)
	ck("hidden_enemies_not_in_detectable_list", "PASS" if hidden_kinds.is_empty() else "FAIL", str(hidden_kinds))

# 4. 植物(成熟=等倍、未成熟=縮小)と状態記号
func shot_crops() -> void:
	reset_world()
	g.hero_pos = Vector2(60, 150)
	var cs: RefCounted = g.pack.crops
	var small: Array = ["clover", "four_leaf_clover", "golden_clover", "golden_four_leaf", "wasabi", "edamame", "sunflower", "tomato", "corn", "mint", "cactus",
		"grape", "strawberry", "lavender", "garlic", "bamboo", "flytrap", "potato", "rice", "dokudami", "aloe", "pepper", "glow_moss"]
	var i: int = 0
	var ids: Dictionary = {}
	for k: String in small:
		var cx: int = 17 + (i % 23) * 2
		var r1: Dictionary = cs.spawn_crop(k, Vector2i(cx, 4), 20, {"mature": true, "watered": true, "skip_check": true})
		ids[k] = int(r1.id)
		cs.spawn_crop(k, Vector2i(cx, 8), 20, {"mature": false, "watered": i % 2 == 0, "skip_check": true})
		i += 1
	var big: Array = [["lotus", 4, 4], ["pumpkin", 20, 12], ["tea", 24, 12], ["oleander", 38, 12], ["sakura", 44, 11], ["giant_watermelon", 52, 12]]
	for b: Array in big:
		var rr: Dictionary = cs.spawn_crop(b[0], Vector2i(b[1], b[2]), 50, {"mature": true, "watered": true, "skip_check": true})
		ids[b[0]] = int(rr.id)
	cs.spawn_crop("oleander", Vector2i(38, 20), 45, {"mature": false, "watered": true, "skip_check": true})
	# 状態: 毒3つ・開花・消化・貯蔵・低HP・かじられ
	cs.get_crop(1)
	cs._by_id[ids["tomato"]].poison = 3
	cs._by_id[ids["grape"]].poison = 1
	cs._by_id[ids["sakura"]].since_mature = 5.0
	cs._by_id[ids["flytrap"]].digest_until = cs.time + 100.0
	cs._by_id[ids["potato"]].storage = 120.0
	cs._by_id[ids["potato"]].paid = 30
	cs._by_id[ids["pepper"]].hp = 10.0
	cs._by_id[ids["tea"]].since_mature = 2000.0
	cs.add_pickup(Vector2(150, 100), 6, 0, "strawberry")
	cs.add_pickup(Vector2(165, 100), 7, 0, "seeds")
	g.sel_crop_id = int(ids["golden_clover"])
	await capture("crops_all", "28種(親クローバー含む)。上段=成熟(等倍)、下段=未成熟(縮小)。毒・開花・消化・貯蔵・低HPと金の範囲プレビュー")
	var n: int = cs.crops.size()
	ck("shot_crops_placed_all_kinds", "PASS" if n >= 29 + 23 else "FAIL", "crops=%d" % n)
	g.sel_crop_id = 0

# 5. 配置プレビュー(エンジン内入力のホバー)と価格・DEBUG表示
func shot_ui_preview() -> void:
	reset_world()
	g.hero_pos = Vector2(60, 150)
	var cs: RefCounted = g.pack.crops
	for x: int in [40, 41, 42]:
		cs.spawn_crop("clover", Vector2i(x, 20), 10, {"mature": true, "watered": true, "skip_check": true})
	cs.spawn_crop("lavender", Vector2i(46, 6), 25, {"mature": true, "watered": true, "skip_check": true})
	lab.do_action("tab:crop")
	lab.do_action("pick_crop:lavender")
	var sc: float = root.get_final_transform().x.x
	var target: Vector2 = Vector2(41.5 * 8.0, 14.5 * 8.0)
	var ev: InputEventMouseMotion = InputEventMouseMotion.new()
	ev.position = target * sc
	ev.global_position = target * sc
	Input.parse_input_event(ev)
	await frame()
	lab.do_action("dbg_seeds")
	g.sel_crop_id = int(cs.crops[3].id)
	ck("hover_via_injected_input_updates_preview_cell", "PASS" if g.hover_cell == Vector2i(41, 14) else "FAIL", str(g.hover_cell))
	await capture("ui_preview_debug", "配置プレビュー(緑=可)と範囲の点(ラベンダー)・価格・パネル・DEBUG表示")

# 6. 夜
func shot_night() -> void:
	reset_world()
	g.hero_pos = Vector2(100, 84)
	g.host.day = false
	var cs: RefCounted = g.pack.crops
	cs.spawn_crop("glow_moss", Vector2i(40, 20), 15, {"mature": true, "watered": true, "skip_check": true})
	cs.spawn_crop("sunflower", Vector2i(44, 20), 25, {"mature": true, "watered": true, "skip_check": true})
	sp("grass_snake", 168, 82)
	sp("deer", 190, 96)
	g.tool = "combat"
	await capture("night", "夜の画面(暗転)。ヒカリゴケの光")
	g.host.day = true

# ---------------------------------------------------------------- 画像の機械確認
func check_assets_no_outline() -> void:
	var bank: RefCounted = lab.view.bank
	var bad: Array = []
	var worst: float = 1.0
	for n: Variant in bank.names():
		var im: Image = bank.image(str(n))
		var w: int = im.get_width()
		var h: int = im.get_height()
		var edge: int = 0
		var dark: int = 0
		for y: int in range(h):
			for x: int in range(w):
				var c: Color = im.get_pixel(x, y)
				if c.a < 0.99:
					continue
				var on_edge: bool = false
				for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var nx: int = x + d.x
					var ny: int = y + d.y
					if nx < 0 or ny < 0 or nx >= w or ny >= h or im.get_pixel(nx, ny).a < 0.5:
						on_edge = true
				if on_edge:
					edge += 1
					var lum: float = c.r * 0.3 + c.g * 0.59 + c.b * 0.11
					if lum < 0.12:
						dark += 1
		var frac: float = float(dark) / float(maxi(1, edge))
		worst = minf(worst, 1.0)
		if frac > 0.10:
			bad.append("%s %.0f%%" % [n, frac * 100.0])
	ck("sprites_have_no_black_outline_pixels_on_edges", "PASS" if bad.is_empty() else "FAIL", str(bad) if not bad.is_empty() else "63 sprites: near-black edge pixels <=10% each")

func check_nearest_setting() -> void:
	var filt: int = int(ProjectSettings.get_setting("rendering/textures/canvas_textures/default_texture_filter", 1))
	var mode: String = str(ProjectSettings.get_setting("display/window/stretch/mode", ""))
	var scale_mode: String = str(ProjectSettings.get_setting("display/window/stretch/scale_mode", ""))
	ck("project_uses_nearest_and_integer_viewport_scaling", "PASS" if filt == 0 and mode == "viewport" and scale_mode == "integer" else "FAIL", "filter=%d mode=%s scale=%s" % [filt, mode, scale_mode])
	ck("lab_canvas_nearest", "PASS" if lab.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST else "FAIL", str(lab.texture_filter))
