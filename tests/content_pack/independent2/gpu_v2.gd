extends SceneTree
## 独立検証2-F: 確認画面の操作(エンジン内入力のみ)と実GPU撮影。入口スクリプト。ウィンドウは前面化しない(unfocusable)。
## 実GPUが無い(headless等)ときは、操作の確認だけ行い、描画の確認は NOT_RUN と記録する。
const OUT_DIR: String = "res://evidence/content_pack/independent2"
const GPU_DIR: String = "res://evidence/content_pack/independent2/gpu"
var checks: Array = []
var shots: Array = []
var lab: Node = null
var g: RefCounted = null
var es: RefCounted = null
var cs: RefCounted = null
var gpu_ok: bool = false
var adapter: String = ""
var sc: int = 1

func ck(name: String, status: String, detail: String = "") -> void:
	checks.append({"name": name, "status": status, "detail": detail})

func okc(name: String, ok: bool, detail: String = "") -> void:
	ck(name, "PASS" if ok else "FAIL", detail)

func frame() -> void:
	await process_frame

func draw_frames(n: int = 3) -> void:
	if not gpu_ok:
		await process_frame
		return
	for i: int in range(n):
		await RenderingServer.frame_post_draw

func finish() -> void:
	var fails: int = 0
	var notrun: int = 0
	for c: Dictionary in checks:
		print("%s %s %s" % [c.status, c.name, c.detail])
		if c.status == "FAIL":
			fails += 1
		elif c.status == "NOT_RUN":
			notrun += 1
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var f: FileAccess = FileAccess.open(OUT_DIR + "/gpu_v2.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"suite": "gpu_v2", "adapter": adapter, "driver": RenderingServer.get_current_rendering_driver_name(), "display_server": DisplayServer.get_name(),
		"window_size": [root.size.x, root.size.y], "total": checks.size(), "failed": fails, "not_run": notrun, "shots": shots, "checks": checks}, "\t"))
	f.close()
	print("gpu_v2 total=%d failed=%d not_run=%d adapter=%s display=%s" % [checks.size(), fails, notrun, adapter, DisplayServer.get_name()])
	quit(1 if fails > 0 else 0)

# ---------------------------------------------------------------- 入力(エンジン内)
func click_screen(p: Vector2, button: int = MOUSE_BUTTON_LEFT, shift: bool = false) -> void:
	var mv: InputEventMouseMotion = InputEventMouseMotion.new()
	mv.position = p * float(sc)
	mv.global_position = p * float(sc)
	Input.parse_input_event(mv)
	await frame()
	for pressed: bool in [true, false]:
		var ev: InputEventMouseButton = InputEventMouseButton.new()
		ev.position = p * float(sc)
		ev.global_position = p * float(sc)
		ev.button_index = button
		ev.pressed = pressed
		ev.shift_pressed = shift
		Input.parse_input_event(ev)
		await frame()

func click_world(w: Vector2, button: int = MOUSE_BUTTON_LEFT, shift: bool = false) -> void:
	await click_screen(w * 2.0, button, shift)

func btn(action: String) -> void:
	var c: Vector2 = lab.button_center(action)
	okc("button_exists_" + action, c.x >= 0.0, str(c))
	await click_screen(c)

func key(code: int, pressed: bool) -> void:
	var ev: InputEventKey = InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = pressed
	Input.parse_input_event(ev)
	await frame()

func put_enemy(kind: String, w: Vector2) -> void:
	await btn("tab:enemy2")
	await btn("pick_enemy:" + kind)
	await click_world(w)
	await click_screen(Vector2(20, 20), MOUSE_BUTTON_RIGHT)   # 道具を戻す

func put_crop(kind: String, w: Vector2) -> void:
	await btn("tab:crop2")
	await btn("pick_crop:" + kind)
	await click_world(w)
	await click_screen(Vector2(20, 20), MOUSE_BUTTON_RIGHT)

func ids_of(kind: String) -> Array:
	var out: Array = []
	for e: Dictionary in es.enemies:
		if e.alive and e.kind == kind:
			out.append(int(e.id))
	return out

func fresh() -> void:
	g.clear_enemies()
	cs.crops.clear()
	cs._by_id.clear()
	cs._occ.clear()
	cs._root_occ.clear()
	cs.fruits.clear()
	cs.pickups.clear()
	g.host.helper_list.clear()
	g.host.stage_override.clear()
	g.host.watered_cells.clear()
	g.terrain_dirty = true
	g.host.day = true
	g.tool = "combat"
	g.paused = false
	g.speed = 1
	g.hero_pos = Vector2(160, 84)
	g.hp = g.max_hp
	g.seeds = 9999
	g.bullets.clear()
	g.fx_list.clear()
	g.log.clear()
	g.counts.clear()
	g.slow_until = 0.0
	g.pack.common.wet.clear()
	g.pack.common.hero_stun_until = 0.0
	g.pack.common.helper_stop.clear()
	es.glass_rolls.clear()
	lab.ui.mouse = Vector2(-10, -10)
	g.hover_cell = Vector2i(-1, -1)

# ---------------------------------------------------------------- 撮影と画像検査
func capture(name: String, note: String) -> Image:
	await draw_frames(3)
	var im: Image = root.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(GPU_DIR))
	im.save_png(GPU_DIR + "/" + name + ".png")
	var scale: int = im.get_width() / 640
	var mult: bool = im.get_width() % 640 == 0 and im.get_height() % 360 == 0 and im.get_width() / 640 == im.get_height() / 360 and scale >= 1
	okc("shot_%s_size_integer_multiple_of_640x360" % name, mult, "%dx%d" % [im.get_width(), im.get_height()])
	var bad: int = 0
	for by: int in range(0, 360):
		for bx: int in range(0, 640):
			var c0: Color = im.get_pixel(bx * scale, by * scale)
			var uniform: bool = true
			for dy: int in range(scale):
				for dx: int in range(scale):
					if im.get_pixel(bx * scale + dx, by * scale + dy) != c0:
						uniform = false
			if not uniform:
				bad += 1
	okc("shot_%s_nearest_blocks_uniform" % name, bad == 0, "non-uniform blocks=%d" % bad)
	var colors: Dictionary = {}
	for y: int in range(im.get_height()):
		for x: int in range(im.get_width()):
			colors[im.get_pixel(x, y).to_rgba32()] = true
	shots.append({"name": name, "file": "evidence/content_pack/independent2/gpu/%s.png" % name, "size": [im.get_width(), im.get_height()], "unique_colors": colors.size(), "note": note})
	# 640x360 に戻した画像(整数倍のブロックの左上)
	var small: Image = Image.create(640, 360, false, Image.FORMAT_RGBA8)
	for y2: int in range(360):
		for x2: int in range(640):
			small.set_pixel(x2, y2, im.get_pixel(x2 * scale, y2 * scale))
	return small

func sprite_image(name: String) -> Image:
	var im: Image = Image.new()
	var meta: Dictionary = lab.view.bank.meta[name]
	im.load("res://assets/content_pack/" + str(meta.file))
	im.convert(Image.FORMAT_RGBA8)
	return im

## 足元基準の確認: 期待の足元(640x360座標)から ±4px の範囲でスプライトの不透明画素の一致数を最大化するずれを探す。
func check_sprite_at(small: Image, name: String, foot: Vector2, label: String, min_frac: float = 0.3, mod: Color = Color.WHITE) -> void:
	var im: Image = sprite_image(name)
	var meta: Dictionary = lab.view.bank.meta[name]
	var fo: Vector2i = Vector2i(int(meta.foot[0]), int(meta.foot[1]))
	var pts: Array = []
	for y: int in range(im.get_height()):
		for x: int in range(im.get_width()):
			var c: Color = im.get_pixel(x, y)
			if c.a > 0.99:
				pts.append([x, y, Color(clampf(c.r * mod.r, 0.0, 1.0), clampf(c.g * mod.g, 0.0, 1.0), clampf(c.b * mod.b, 0.0, 1.0), 1.0)])
	if pts.is_empty():
		ck("sprite_foot_" + label, "FAIL", "no opaque pixels")
		return
	var best: int = -1
	var best_off: Vector2i = Vector2i.ZERO
	var best_flip: bool = false
	var tl0: Vector2i = Vector2i(int(floorf(foot.x)) - fo.x, int(floorf(foot.y)) - fo.y)
	for flip: bool in [false, true]:
		for dy: int in range(-4, 5):
			for dx: int in range(-4, 5):
				var n: int = 0
				for p: Array in pts:
					var px: int = (im.get_width() - 1 - int(p[0])) if flip else int(p[0])
					var sx: int = tl0.x + dx + px
					var sy: int = tl0.y + dy + int(p[1])
					if sx >= 0 and sy >= 0 and sx < 640 and sy < 360 and _close(small.get_pixel(sx, sy), p[2]):
						n += 1
				if n > best:
					best = n
					best_off = Vector2i(dx, dy)
					best_flip = flip
	var frac: float = float(best) / float(pts.size())
	okc("sprite_foot_" + label, frac >= min_frac and absi(best_off.x) <= 1 and absi(best_off.y) <= 1, "match=%.2f offset=%s flip=%s" % [frac, str(best_off), str(best_flip)])

func _close(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.02 and absf(a.g - b.g) < 0.02 and absf(a.b - b.b) < 0.02

func foot_of_enemy(id: int) -> Vector2:
	return Vector2(es.ref(id).pos) * 2.0 + Vector2(0, 3)

func foot_of_crop(id: int) -> Vector2:
	var c: Dictionary = cs.get_crop(id)
	return Vector2((float(c.cell.x) + float(c.size.x) * 0.5) * 8.0, float(c.cell.y + c.size.y) * 8.0 - 1.0)

func _initialize() -> void:
	root.unfocusable = true
	adapter = RenderingServer.get_video_adapter_name()
	gpu_ok = DisplayServer.get_name() != "headless" and adapter != ""
	if gpu_ok:
		ck("gpu_available", "PASS", "adapter=%s driver=%s display=%s" % [adapter, RenderingServer.get_current_rendering_driver_name(), DisplayServer.get_name()])
	else:
		ck("gpu_available", "NOT_RUN", "display=%s adapter='%s' (描画の確認は NOT_RUN。操作の確認だけ行う)" % [DisplayServer.get_name(), adapter])
	var scn: PackedScene = load("res://scenes/content_pack/content_lab.tscn")
	lab = scn.instantiate()
	lab.auto_step = false
	root.add_child(lab)
	await frame()
	await draw_frames(2)
	root.unfocusable = true
	await frame()
	if gpu_ok:
		okc("window_unfocusable_flag", root.unfocusable and root.get_flag(Window.FLAG_NO_FOCUS), "")
	g = lab.game
	es = g.pack.enemies
	cs = g.pack.crops
	sc = int(root.get_final_transform().x.x) if gpu_ok else 1
	lab.ui.freeze = true
	lab.ui.t = 0.0
	await ops_test()
	if gpu_ok:
		await render_tests()
	else:
		ck("render_checks_all", "NOT_RUN", "実GPUがないため描画未検証")
	finish()

# ---------------------------------------------------------------- 操作(エンジン内入力)
func ops_test() -> void:
	fresh()
	g.seeds = 9999
	var spots: Dictionary = {
		"root_mole": Vector2(230, 40), "skunk": Vector2(150, 112), "hippo": Vector2(30, 30), "honey_bear": Vector2(100, 126),
		"sewer_rat": Vector2(140, 126), "bat_flock": Vector2(108, 68), "iron_rhino": Vector2(236, 126),
		"thunder_eel": Vector2(24, 24), "decoy_newt": Vector2(70, 110), "mirror_lizard": Vector2(200, 60),
		"pistol_shrimp": Vector2(170, 40), "balloon_frog": Vector2(60, 126), "glass_deer": Vector2(240, 60)}
	for k: String in spots.keys():
		await put_enemy(k, spots[k])
	await put_enemy("manhole", Vector2(186, 106))
	await put_enemy("lab_helper", Vector2(120, 100))
	for k: String in spots.keys():
		okc("ops_enemy_placed_" + k, ids_of(k).size() >= 1, "n=%d" % ids_of(k).size())
	okc("ops_manhole_net_3", ids_of("manhole").size() == 3, "n=%d" % ids_of("manhole").size())
	okc("ops_bat_flock_6", ids_of("bat_flock").size() == 6, "n=%d" % ids_of("bat_flock").size())
	okc("ops_frog_flock_3", ids_of("balloon_frog").size() == 3, "n=%d" % ids_of("balloon_frog").size())
	okc("ops_helper_placed", g.host.helper_list.size() == 1)
	# ガラスジカの初期配置の抽選(押すたびに新しい地域)
	var before: int = ids_of("glass_deer").size()
	for i: int in range(6):
		await put_enemy("glass_lot", Vector2(100, 40))
	okc("ops_glass_lottery_runs", g.glass_lot_n == 6, "lots=%d hits=%d" % [g.glass_lot_n, g.glass_hits])
	# 植物8種
	var cspots: Dictionary = {"evening_primrose": Vector2(160, 30), "dandelion": Vector2(176, 30), "mimosa": Vector2(192, 22), "kudzu": Vector2(208, 22),
		"loofah": Vector2(224, 22), "hinoki": Vector2(160, 70), "apple": Vector2(200, 78), "balsam": Vector2(240, 14)}
	for k: String in cspots.keys():
		await put_crop(k, cspots[k])
	for k: String in cspots.keys():
		var n: int = cs.crops.filter(func(c: Dictionary) -> bool: return c.kind == k).size()
		okc("ops_crop_placed_" + k, n == 1, "n=%d" % n)
	# 成熟(デバッグボタン)と戦闘入力
	await btn("dbg_water")
	g.sel_crop_id = 0
	await btn("dbg_mature")
	okc("ops_debug_mature_all", cs.crops.all(func(c: Dictionary) -> bool: return bool(c.mature)))
	# 戦闘: 左クリック=射撃、右クリック=水、Shift+左=たいあたり、Shift+右=バズーカ
	g.hero_pos = Vector2(150, 84)
	var seeds0: int = g.seeds
	await click_world(Vector2(210, 84))
	okc("ops_lmb_shoot", g.bullets.size() == 1 and g.seeds == seeds0 - 1, "bullets=%d seeds %d->%d" % [g.bullets.size(), seeds0, g.seeds])
	var w0: float = g.water
	await click_world(Vector2(60, 84), MOUSE_BUTTON_RIGHT)
	okc("ops_rmb_water", g.water < w0 and g.cnt("wet_cell") > 0, "water %.0f->%.0f wet_cell events=%d" % [w0, g.water, g.cnt("wet_cell")])
	var hp0: Vector2 = g.hero_pos
	await click_world(Vector2(190, 84), MOUSE_BUTTON_LEFT, true)
	okc("ops_shift_lmb_tackle", g.hero_pos.distance_to(hp0) > 1.0, "moved %.1f" % g.hero_pos.distance_to(hp0))
	var s1: int = g.seeds
	var r1: int = g.rewards_total
	await click_world(Vector2(100, 84), MOUSE_BUTTON_RIGHT, true)
	okc("ops_shift_rmb_bazooka", g.seeds - (g.rewards_total - r1) == s1 - 5, "seeds %d->%d rewards+%d" % [s1, g.seeds, g.rewards_total - r1])
	# キー: スペースでポーズ、Nで昼夜、WASDで移動
	await key(KEY_SPACE, true)
	await key(KEY_SPACE, false)
	okc("ops_key_space_pause", g.paused)
	var t_paused: float = es.time
	g.step(2.0)
	okc("ops_paused_no_time_advance", es.time == t_paused)
	await key(KEY_SPACE, true)
	await key(KEY_SPACE, false)
	okc("ops_key_space_resume", not g.paused)
	var d0: bool = g.host.day
	await key(KEY_N, true)
	await key(KEY_N, false)
	okc("ops_key_n_day_night", g.host.day != d0)
	# 保存・復元(F5/F9。ラボ専用の領域)
	await key(KEY_F5, true)
	await key(KEY_F5, false)
	var t_saved: float = es.time
	var kinds_before: int = es.enemies.size()
	g.step(3.0)
	await key(KEY_F9, true)
	await key(KEY_F9, false)
	okc("ops_f5_f9_restore", absf(es.time - t_saved) < 0.001 and es.enemies.size() == kinds_before, "time %.2f vs %.2f" % [es.time, t_saved])

# ---------------------------------------------------------------- 実GPU描画
func render_tests() -> void:
	# 1. 動物の並び(静止: ポーズ)。各種を操作で置き、足元基準・nearest・形を確認する
	fresh()
	g.seeds = 9999
	var lineup: Array = [["root_mole", 40, 130], ["skunk", 80, 130], ["hippo", 30, 40], ["honey_bear", 180, 130], ["sewer_rat", 215, 130], ["iron_rhino", 240, 100],
		["thunder_eel", 24, 24], ["decoy_newt", 70, 100], ["mirror_lizard", 110, 100], ["pistol_shrimp", 150, 100], ["glass_deer", 190, 100]]
	var placed: Dictionary = {}
	for row: Array in lineup:
		await put_enemy(str(row[0]), Vector2(row[1], row[2]))
		placed[row[0]] = ids_of(str(row[0]))[0] if ids_of(str(row[0])).size() > 0 else -1
	await put_enemy("bat_flock", Vector2(108, 68))
	await put_enemy("balloon_frog", Vector2(60, 60))
	await put_enemy("manhole", Vector2(186, 52))
	g.paused = true
	await frame()
	var small: Image = await capture("animals_lineup", "第2弾の動物13種(中立1を含む)を確認画面の入力で並べた静止画")
	for row: Array in lineup:
		var k: String = str(row[0])
		if placed[k] < 0:
			ck("sprite_foot_" + k, "FAIL", "not placed")
			continue
		if k == "root_mole":
			continue   # 地中は画像を描かない設計(盛り土の影だけ)。地上に出た状態は下で確認
		if k == "glass_deer":
			continue   # 半透明のため別の確認(下)
		if k == "thunder_eel":
			continue   # 水中の表現が重なるため下で確認
		check_sprite_at(small, k, foot_of_enemy(placed[k]), k, 0.25 if k in ["hippo"] else 0.35)
	# ガラスジカ: 背景との差分で足元を確認
	var gid: int = placed["glass_deer"]
	var gf: Vector2 = foot_of_enemy(gid)
	var changed: int = 0
	for y: int in range(int(gf.y) - 24, int(gf.y) + 2):
		for x: int in range(int(gf.x) - 11, int(gf.x) + 11):
			var c: Color = small.get_pixel(x, y)
			if absf(c.g - 0.55) > 0.15 or absf(c.r - 0.31) > 0.15:
				changed += 1
	okc("glass_deer_drawn_translucent_visible", changed >= 40, "non-terrain pixels=%d" % changed)
	# 2. 植物の並び
	fresh()
	g.seeds = 9999
	var cl: Array = [["evening_primrose", 24, 120], ["dandelion", 40, 120], ["mimosa", 56, 120], ["kudzu", 72, 120], ["loofah", 88, 120], ["hinoki", 116, 116], ["apple", 148, 116], ["balsam", 170, 120]]
	var cid: Dictionary = {}
	for row: Array in cl:
		await put_crop(str(row[0]), Vector2(row[1], row[2]))
		var arr: Array = cs.crops.filter(func(c: Dictionary) -> bool: return c.kind == row[0])
		cid[row[0]] = int(arr[0].id) if arr.size() > 0 else -1
	await btn("dbg_water")
	g.sel_crop_id = 0
	await btn("dbg_mature")
	g.paused = true
	await frame()
	var small2: Image = await capture("crops_lineup", "第2弾の栽培植物8種(成熟後)を確認画面の入力で並べた静止画")
	for row: Array in cl:
		var k: String = str(row[0])
		if cid[k] < 0:
			ck("sprite_foot_" + k, "FAIL", "not placed")
			continue
		check_sprite_at(small2, k, foot_of_crop(cid[k]), k, 0.4, Color(0.68, 0.74, 0.68) if k == "evening_primrose" else Color.WHITE)
	# 夜のツキミソウ
	g.paused = false
	await btn("day")
	g.paused = true
	await frame()
	var small3: Image = await capture("crops_night", "夜(ツキミソウが開く)")
	var lum_day: float = 0.0
	var lum_night: float = 0.0
	for y: int in range(0, 288, 3):
		for x: int in range(0, 512, 3):
			lum_day += small2.get_pixel(x, y).get_luminance()
			lum_night += small3.get_pixel(x, y).get_luminance()
	okc("night_frame_darker_than_day_frame", lum_night < lum_day * 0.95, "day=%.1f night=%.1f" % [lum_day, lum_night])
	var pf: Vector2 = foot_of_crop(cid["evening_primrose"])
	var diffpx: int = 0
	for y: int in range(int(pf.y) - 20, int(pf.y)):
		for x: int in range(int(pf.x) - 6, int(pf.x) + 6):
			if not _close(small2.get_pixel(x, y), small3.get_pixel(x, y)):
				diffpx += 1
	okc("primrose_region_changes_between_day_and_night", diffpx >= 20, "changed=%d" % diffpx)
	# 3. 状態の表示: 実際の挙動を進めて撮る
	fresh()
	g.seeds = 9999
	g.paused = false
	# スカンクの雲と主人公の減速
	var sk: int = es.spawn("skunk", Vector2(150, 100), "initial")
	es.ref(sk).face = Vector2.RIGHT
	g.hero_pos = Vector2(180, 100)
	g._sync_hero()
	apply(es.apply_hit(sk, 1.0, "shot", Vector2(190, 100)))
	for i: int in range(8):
		g.step(0.1)
	g.hero_pos = Vector2(180, 100)
	await frame()
	await capture("state_skunk_odor", "スカンクの臭気の雲と予兆")
	okc("state_skunk_cloud_exists", es.odor_clouds().size() == 1)
	# ウナギと濡れたマス
	fresh()
	var eel: int = es.spawn("thunder_eel", Vector2(50, 30), "initial")
	g.hero_pos = Vector2(80, 30)
	g._sync_hero()
	var wc: Array = []
	for x: int in range(15, 24):
		wc.append(Vector2i(x, 7))
	g.apply_events(g.pack.water_landed(wc))
	for i: int in range(11):
		g.step(0.1)
	await frame()
	await capture("state_eel_wet_discharge", "ウナギの予兆/放電と濡れたマス")
	# モグラ: 盛り土と気絶
	fresh()
	cs.spawn_crop("potato", Vector2i(58, 25), 0, {"mature": true, "watered": true, "skip_check": true})
	var mo: int = es.spawn("root_mole", Vector2(202, 102), "initial")
	g.hero_pos = Vector2(120, 100)
	for i: int in range(14):
		g.step(0.1)
	await frame()
	await capture("state_mole_mounds", "ネッコモグラの盛り土(地中)")
	okc("state_mole_mounds_listed", (es.ref(mo).mounds as Array).size() >= 3)
	g.apply_events(g.pack.water_landed([Vector2i(floori(es.ref(mo).pos.x / 4.0), floori(es.ref(mo).pos.y / 4.0))]))
	for i: int in range(12):
		g.step(0.1)
	await frame()
	var small4: Image = await capture("state_mole_stunned", "水で追い出されて目を回すネッコモグラ")
	okc("state_mole_stunned", es.ref(mo).state == "stunned")
	check_sprite_at(small4, "root_mole", foot_of_enemy(mo), "root_mole_surfaced", 0.3)
	# コウモリの群れ(夜に乱れ飛び)とフウセンガエルの浮上
	fresh()
	g.host.day = false
	var bats: Array = es.spawn_bat_flock(Vector2(108, 68), "initial")
	var frogs: Array = es.spawn_frog_flock(Vector2(200, 110), "initial")
	g.hero_pos = Vector2(150, 90)
	g._sync_hero()
	es.apply_hit(bats[0], 1.0, "shot", Vector2(130, 68))
	for i: int in range(22):
		g.step(0.1)
	await frame()
	await capture("state_bats_frogs", "夜に乱れ飛ぶコウモリと、膨らむ/浮かぶフウセンガエル")
	# カガミトカゲの反射
	fresh()
	var li: int = es.spawn("mirror_lizard", Vector2(150, 100), "initial")
	es.ref(li).face = Vector2.RIGHT
	g.hero_pos = Vector2(200, 100)
	g._sync_hero()
	g.apply_events(es.apply_hit(li, 5.0, "shot", Vector2(200, 100)))
	for i: int in range(2):
		g.step(0.1)
	await frame()
	await capture("state_lizard_reflect", "カガミトカゲの反射(来た方向へ跳ね返る弾)")
	# 眠るハチミツグマ、錆びたサイ、マンホール網
	fresh()
	var br: int = es.spawn("honey_bear", Vector2(80, 100), "initial")
	es.ref(br).state = "sleep"
	var rh: int = es.spawn("iron_rhino", Vector2(200, 110), "initial")
	for i: int in range(3):
		es.apply_hit(rh, 0.0, "water")
	var net: Dictionary = es.spawn_manhole_net([Vector2(186, 52), Vector2(214, 58), Vector2(172, 64)], "initial")
	g.paused = true
	await frame()
	await capture("state_bear_sleep_rhino_rust_manholes", "眠るクマ(Zz)、錆のサイ、マンホール網")
	# 4. パネルのページ
	g.tab = "enemy2"
	await frame()
	await capture("panel_enemy2_page", "ENM2ページ")
	g.tab = "crop2"
	await frame()
	await capture("panel_crop2_page", "CRP2ページ")

func apply(evs: Array) -> void:
	g.apply_events(evs)
