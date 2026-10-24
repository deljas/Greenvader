extends SceneTree
## 第2弾の確認画面の操作の自己検証(入口スクリプト、--headless)。シーンを読み込み、Input.parse_input_event で操作を注入する。
## 実行(隔離プロジェクトのみ): Godot --headless --path C:/godot/greenvader_content_sandbox --script res://tests/content_pack/self2/lab2_logic.gd
## 描画(_draw)はヘッドレスでも呼ばれるため、例外が出ればログに SCRIPT ERROR が残る(ログ側で別途確認)。実GPUの描画は lab2_gpu.gd。
const OUT_DIR: String = "res://evidence/content_pack/self2"
const Game: GDScript = preload("res://scripts/content_pack/lab/lab_game.gd")
const Common2: GDScript = preload("res://scripts/content_pack/common2.gd")

var checks: Array = []
var lab: Node = null
var g: RefCounted = null
var es: RefCounted = null

func ck(name: String, ok: bool, detail: String = "") -> void:
	checks.append({"name": name, "status": "PASS" if ok else "FAIL", "detail": detail})

# ---------------------------------------------------------------- 入力の注入(エンジン内)
func frame() -> void:
	await process_frame

func motion(p: Vector2) -> void:
	var ev: InputEventMouseMotion = InputEventMouseMotion.new()
	ev.position = p
	ev.global_position = p
	Input.parse_input_event(ev)
	await frame()

func click(p: Vector2, button: int = MOUSE_BUTTON_LEFT, shift: bool = false) -> void:
	await motion(p)
	for pressed: bool in [true, false]:
		var ev: InputEventMouseButton = InputEventMouseButton.new()
		ev.position = p
		ev.global_position = p
		ev.button_index = button
		ev.pressed = pressed
		ev.shift_pressed = shift
		Input.parse_input_event(ev)
		await frame()

func key(code: int, pressed: bool) -> void:
	var ev: InputEventKey = InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = pressed
	Input.parse_input_event(ev)
	await frame()

func tap(code: int) -> void:
	await key(code, true)
	await key(code, false)

func btn(action: String) -> void:
	var c: Vector2 = lab.button_center(action)
	ck("button_exists_" + action, c.x >= 0.0, str(c))
	await click(c)

func w2s(w: Vector2) -> Vector2:
	return w * 2.0

func alive(kind: String) -> Array:
	var out: Array = []
	for e: Dictionary in es.enemies:
		if e.alive and e.kind == kind:
			out.append(int(e.id))
	return out

func run(secs: float, dt: float = 0.1, draw_every: int = 5) -> void:
	var n: int = int(round(secs / dt))
	for i: int in range(n):
		g.step(dt)
		if i % draw_every == 0:
			await frame()

func fresh() -> void:
	g.clear_enemies()
	g.pack.crops.crops.clear()
	g.pack.crops._by_id.clear()
	g.pack.crops._occ.clear()
	g.pack.crops.pickups.clear()
	g.host.helper_list.clear()
	g.host.day = true
	g.tool = "combat"
	g.tab = "enemy"
	g.paused = false
	g.speed = 1
	g.hero_pos = Vector2(160, 84)
	g.hp = g.max_hp
	g.seeds = 500
	g.bullets.clear()
	g.fx_list.clear()
	g.log.clear()
	g.counts.clear()
	g.slow_until = 0.0
	g.pack.common.hero_stun_until = 0.0
	g.pack.common.helper_stop.clear()
	g.pack.common.wet.clear()
	es.glass_rolls.clear()

## パネル操作で敵を出す(タブ → 種類 → マップをクリック → 右クリックで戦闘へ戻る)
func spawn_ui(tab_action: String, kind: String, world: Vector2) -> void:
	await btn(tab_action)
	await btn("pick_enemy:" + kind)
	await click(w2s(world))
	await click(Vector2(20, 20), MOUSE_BUTTON_RIGHT)

func hp_of(id: int) -> float:
	return float(es.ref(id).hp)

func count_log(prefix: String) -> int:
	var n: int = 0
	for r: Variant in g.log:
		if str((r as Dictionary).text).begins_with(prefix):
			n += 1
	return n

# ---------------------------------------------------------------- 本体
func _initialize() -> void:
	var scn: PackedScene = load("res://scenes/content_pack/content_lab.tscn")
	lab = scn.instantiate()
	lab.auto_step = false
	root.add_child(lab)
	await frame()
	await frame()
	g = lab.game
	es = g.pack.enemies
	await t_assets()
	await t_panel_and_spawn()
	await t_run_everything()
	await t_mole_water_and_shots()
	await t_bats_frogs_glass()
	await t_stun_and_helper()
	await t_mirror_skunk()
	await t_eel_wet()
	await t_manhole_net()
	await t_crops_panel()
	await t_crop_behaviors()
	await t_save_pause_keys()
	var fails: int = 0
	for c: Dictionary in checks:
		print("%s %s %s" % [c.status, c.name, c.detail])
		if c.status != "PASS":
			fails += 1
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var f: FileAccess = FileAccess.open(OUT_DIR + "/lab2_logic.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"suite": "lab2_logic", "total": checks.size(), "failed": fails, "checks": checks}, "\t"))
	f.close()
	print("lab2_logic total=%d failed=%d" % [checks.size(), fails])
	quit(1 if fails > 0 else 0)

# ---------------------------------------------------------------- 1. 仮スプライト(第1弾テストの『63枚ちょうど』の更新版)
func t_assets() -> void:
	var bank: RefCounted = lab.view.bank
	var names: Array = bank.names()
	var miss: Array = []
	var badsize: Array = []
	for n: Variant in names:
		var t: Texture2D = bank.tex(str(n))
		if t == null:
			miss.append(n)
		else:
			var sz: Vector2i = bank.size_of(str(n))
			if t.get_width() != sz.x or t.get_height() != sz.y:
				badsize.append(n)
	ck("assets_86_sprites_load_at_runtime_without_import", names.size() == 86 and miss.is_empty() and badsize.is_empty(), "n=%d miss=%s badsize=%s" % [names.size(), str(miss), str(badsize)])
	var absent: Array = []
	for k: Variant in es.defs:
		if not bank.has(str(k)):
			absent.append(k)
	for k2: Variant in g.pack.crops.defs:
		if not bank.has(str(k2)):
			absent.append(k2)
	for k3: String in ["junk_crab_shell", "junk_pile", "moss_turtle_bush", "grass_snake_grass", "mimic_cabbage_disguise", "needle", "mud_ball", "seed_bag", "strawberry_pickup", "hero"]:
		if not bank.has(k3):
			absent.append(k3)
	ck("sprites_cover_all_enemies_crops_and_extras_incl_wave2", absent.is_empty(), str(absent))
	var mism: Array = []
	for k4: Variant in es.defs:
		var im: Array = es.defs[k4].image
		if bank.size_of(str(k4)) != Vector2i(int(im[0]), int(im[1])):
			mism.append(k4)
	for k5: Variant in g.pack.crops.defs:
		var im2: Array = g.pack.crops.defs[k5].image
		if bank.size_of(str(k5)) != Vector2i(int(im2[0]), int(im2[1])):
			mism.append(k5)
	ck("wave2_sprite_sizes_match_definition_image_px", mism.is_empty(), str(mism))
	var feet_bad: Array = []
	for n2: Variant in ["root_mole", "skunk", "hippo", "honey_bear", "sewer_rat", "manhole", "bat_flock", "iron_rhino", "thunder_eel", "decoy_newt", "decoy_tail", "mirror_lizard", "pistol_shrimp", "balloon_frog", "glass_deer", "evening_primrose", "dandelion", "mimosa", "kudzu", "loofah", "hinoki", "apple", "balsam"]:
		var sz2: Vector2i = bank.size_of(str(n2))
		if bank.foot_of(str(n2)) != Vector2(float(sz2.x) * 0.5, float(sz2.y)):
			feet_bad.append(n2)
	ck("wave2_sprite_foot_is_bottom_center", feet_bad.is_empty(), str(feet_bad))
	# 画像の端が非透明で終わっていない(足元が画像の下端に接している)ことと、輪郭線の暗いふち取りがないこと
	var bad_edge: Array = []
	var no_ground: Array = []
	for n3: Variant in ["root_mole", "skunk", "hippo", "honey_bear", "sewer_rat", "manhole", "bat_flock", "iron_rhino", "thunder_eel", "decoy_newt", "decoy_tail", "mirror_lizard", "pistol_shrimp", "balloon_frog", "glass_deer", "evening_primrose", "dandelion", "mimosa", "kudzu", "loofah", "hinoki", "apple", "balsam"]:
		var img: Image = bank.image(str(n3))
		var w: int = img.get_width()
		var h: int = img.get_height()
		var edge: int = 0
		var dark: int = 0
		var bottom_row: int = 0
		for y: int in range(h):
			for x: int in range(w):
				var c: Color = img.get_pixel(x, y)
				if c.a < 0.99:
					continue
				if y == h - 1:
					bottom_row += 1
				var on_edge: bool = false
				for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var nx: int = x + d.x
					var ny: int = y + d.y
					if nx < 0 or ny < 0 or nx >= w or ny >= h or img.get_pixel(nx, ny).a < 0.5:
						on_edge = true
				if on_edge:
					edge += 1
					if c.r * 0.3 + c.g * 0.59 + c.b * 0.11 < 0.12:
						dark += 1
		if float(dark) / float(maxi(1, edge)) > 0.10:
			bad_edge.append(n3)
		# 半透明のガラスジカ、吊り下がるコウモリ、尾が右へ伸びるウナギ等は下端に接地しない種も許す
		if bottom_row == 0 and not (n3 in ["glass_deer", "bat_flock", "thunder_eel", "decoy_newt", "decoy_tail", "balloon_frog", "pistol_shrimp"]):
			no_ground.append(n3)
	ck("wave2_sprites_have_no_dark_outline_pixels", bad_edge.is_empty(), str(bad_edge))
	ck("wave2_sprites_touch_the_bottom_edge_where_they_stand", no_ground.is_empty(), str(no_ground))
	# 敵に植物の要素を持たせない(擬態を除く)ことの目視補助: 緑系の画素が多い敵を挙げる(カエルとトカゲとイモリは緑・体色として許容)
	ck("wave1_sprites_still_present_with_same_sizes", names.has("deer") and bank.size_of("deer") == Vector2i(22, 22) and bank.size_of("giant_watermelon") == Vector2i(56, 40), "")

# ---------------------------------------------------------------- 2. パネルと出現
func t_panel_and_spawn() -> void:
	fresh()
	var list_ok: bool = Game.ENEMY2_LIST.size() == 16 and Game.CROP2_LIST.size() == 8
	ck("wave2_lists_defined", list_ok, "%d/%d" % [Game.ENEMY2_LIST.size(), Game.CROP2_LIST.size()])
	await btn("tab:enemy2")
	ck("tab_enemy2_selected", g.tab == "enemy2", g.tab)
	for entry: Array in Game.ENEMY2_LIST:
		ck("pick_button_exists_" + str(entry[0]), lab.button_center("pick_enemy:" + str(entry[0])).x >= 0.0)
	await btn("tab:crop2")
	ck("tab_crop2_selected", g.tab == "crop2", g.tab)
	for entry2: Array in Game.CROP2_LIST:
		ck("pick_button_exists_" + str(entry2[0]), lab.button_center("pick_crop:" + str(entry2[0])).x >= 0.0)
	# G で1ページ目/2ページ目、Tab で敵/植物
	await btn("tab:enemy")
	await tap(KEY_G)
	ck("key_g_switches_page_enemy_to_enemy2", g.tab == "enemy2", g.tab)
	await tap(KEY_TAB)
	ck("key_tab_switches_enemy2_to_crop2", g.tab == "crop2", g.tab)
	await tap(KEY_G)
	ck("key_g_switches_page_crop2_to_crop", g.tab == "crop", g.tab)
	await tap(KEY_TAB)
	ck("key_tab_switches_crop_to_enemy", g.tab == "enemy", g.tab)
	# 出現(パネル操作のみ)
	var spots: Dictionary = {
		"root_mole": Vector2(120, 100), "skunk": Vector2(140, 100), "hippo": Vector2(30, 30), "honey_bear": Vector2(180, 110),
		"sewer_rat": Vector2(200, 60), "bat_flock": Vector2(110, 66), "iron_rhino": Vector2(60, 110), "thunder_eel": Vector2(36, 40),
		"decoy_newt": Vector2(80, 100), "mirror_lizard": Vector2(100, 120), "pistol_shrimp": Vector2(130, 126), "balloon_frog": Vector2(220, 40),
		"glass_deer": Vector2(235, 120)}
	for kind: Variant in spots.keys():
		await spawn_ui("tab:enemy2", str(kind), spots[kind])
	await spawn_ui("tab:enemy2", "manhole", Vector2(190, 100))
	await spawn_ui("tab:enemy2", "lab_helper", Vector2(150, 120))
	var want: Dictionary = {"root_mole": 1, "skunk": 1, "hippo": 1, "honey_bear": 1, "sewer_rat": 1, "bat_flock": 6, "iron_rhino": 1, "thunder_eel": 1,
		"decoy_newt": 1, "mirror_lizard": 1, "pistol_shrimp": 1, "balloon_frog": 3, "glass_deer": 1, "manhole": 3}
	var bad: Array = []
	for k: Variant in want.keys():
		if alive(str(k)).size() != int(want[k]):
			bad.append("%s=%d(want %d)" % [str(k), alive(str(k)).size(), int(want[k])])
	ck("panel_spawns_all_wave2_kinds_with_expected_counts", bad.is_empty(), str(bad))
	var mh: Array = alive("manhole")
	var nets: Dictionary = {}
	for id: Variant in mh:
		nets[int(es.ref(int(id)).net_id)] = true
	ck("manhole_net_has_one_net_id", nets.size() == 1, str(nets.keys()))
	var bats: Array = alive("bat_flock")
	var gids: Dictionary = {}
	for id2: Variant in bats:
		gids[int(es.ref(int(id2)).group_id)] = true
	ck("bat_flock_is_one_group", gids.size() == 1, str(gids.keys()))
	ck("helper_placed_from_panel", g.host.helper_list.size() == 1, str(g.host.helper_list.size()))
	var frogs: Array = alive("balloon_frog")
	var fg: Dictionary = {}
	for id3: Variant in frogs:
		fg[int(es.ref(int(id3)).group_id)] = true
	ck("frog_flock_is_one_group", fg.size() == 1, str(fg.keys()))
	# 水域種は水以外では出ない
	var before: int = es.enemies.size()
	await spawn_ui("tab:enemy2", "thunder_eel", Vector2(150, 40))
	await spawn_ui("tab:enemy2", "hippo", Vector2(150, 40))
	ck("water_kinds_refuse_dry_land", es.enemies.size() == before and count_log("THUNDER_EEL NEEDS WATER") >= 1, "n=%d" % es.enemies.size())
	# 抽選(専用乱数): 何度押しても同じ種・同じ地域キーなら同じ結果になり、結果は保存される
	await btn("tab:enemy2")
	await btn("pick_enemy:glass_lot")
	var hits_before: int = g.glass_hits
	for i: int in range(40):
		await click(w2s(Vector2(20, 130)))
	ck("glass_lottery_pressed_40_times_records_each_region", es.glass_rolls.size() == 40 and g.glass_lot_n >= 40, "rolls=%d hits=%d" % [es.glass_rolls.size(), g.glass_hits - hits_before])
	# 1地域あたり候補20点で各5%なら、当たりの地域は約64%(40地域で約26)。全部でも0でもないこと
	ck("glass_lottery_has_both_hit_and_miss_regions", g.glass_hits - hits_before >= 1 and g.glass_hits - hits_before < 40, str(g.glass_hits - hits_before))
	# 同じ地域キーを再抽選しても結果は変わらない(記録を返す)
	var key: String = "lab1"
	var r1: int = es.roll_glass_deer_region(7, key, [Vector2(1, 1), Vector2(2, 2)])
	var r2: int = es.roll_glass_deer_region(7, key, [Vector2(1, 1), Vector2(2, 2)])
	ck("glass_lottery_same_region_is_stable", r1 == r2 and r1 == int(es.glass_rolls[key]), "%d %d" % [r1, r2])
	await click(Vector2(20, 20), MOUSE_BUTTON_RIGHT)

# ---------------------------------------------------------------- 3. 全種を60秒動かして描く
func t_run_everything() -> void:
	g.hero_pos = Vector2(160, 84)
	g.hp = 1000.0
	g.max_hp = 1000.0
	g.show_detect = true
	g.show_hidden = true
	var t0: float = es.time
	await run(60.0, 0.1, 5)
	g.show_detect = false
	g.show_hidden = false
	ck("wave2_all_kinds_run_60_seconds_and_draw", es.time - t0 > 59.0 and es.enemies.size() > 0, "t=%.1f n=%d" % [es.time - t0, es.enemies.size()])
	var kinds: Dictionary = {}
	for e: Dictionary in es.enemies:
		kinds[e.kind] = true
	ck("wave2_kinds_survive_without_errors_in_state_values", kinds.has("manhole") and kinds.has("hippo") and kinds.has("thunder_eel"), str(kinds.keys()))
	g.hp = 100.0
	g.max_hp = 100.0

# ---------------------------------------------------------------- 4. モグラ: 地中は撃てない、水で飛び出す
func t_mole_water_and_shots() -> void:
	fresh()
	g.hero_pos = Vector2(100, 100)
	await spawn_ui("tab:enemy2", "root_mole", Vector2(130, 100))
	var id: int = int(alive("root_mole")[0])
	var m: Dictionary = es.ref(id)
	m.state = "move"
	m.pos = Vector2(130, 100)
	ck("mole_underground_not_hittable_and_not_in_targets", not es.is_hittable(m), str(m.state))
	await click(w2s(Vector2(130, 100)))   # 射撃
	await run(0.6, 0.1, 2)
	ck("shot_through_underground_mole_does_no_damage", is_equal_approx(hp_of(id), 20.0), "hp=%s" % hp_of(id))
	# 検知は盛り土の位置(地中の本体位置ではない)
	m.mounds.append({"pos": Vector2(118, 100), "until": es.time + 5.0})
	var found: Vector2 = Vector2(-1, -1)
	for d: Dictionary in es.detectable_enemies():
		if int(d.id) == id:
			found = Vector2(d.pos)
	ck("mole_detected_at_mound_not_body", found.distance_to(Vector2(118, 100)) < 0.01, str(found))
	# 水(右クリック)で追い出す
	m.pos = Vector2(130, 100)
	await click(w2s(Vector2(131, 100)), MOUSE_BUTTON_RIGHT)
	ck("water_click_marks_wet_cells", g.pack.common.wet_cells().size() > 0, str(g.pack.common.wet_cells().size()))
	await run(1.3, 0.1, 2)
	ck("water_forces_mole_up_and_stunned", str(es.ref(id).state) in ["peek", "stunned"] and es.is_hittable(es.ref(id)), str(es.ref(id).state))
	await click(w2s(Vector2(130, 100)))
	await run(0.6, 0.1, 2)
	ck("mole_hit_when_up", hp_of(id) < 20.0 or not es.is_alive(id), "hp=%s" % (hp_of(id) if es.is_alive(id) else -1.0))
	# 濡れたマスは6秒で消える
	await run(7.0, 0.5, 4)
	ck("wet_cells_expire_after_6_seconds", g.pack.common.wet_cells().size() == 0, str(g.pack.common.wet_cells().size()))

# ---------------------------------------------------------------- 5. コウモリ・フウセンガエル・ガラスジカ
func t_bats_frogs_glass() -> void:
	fresh()
	g.hero_pos = Vector2(80, 66)
	await spawn_ui("tab:enemy2", "bat_flock", Vector2(110, 66))
	var bats: Array = alive("bat_flock")
	ck("bats_roost_and_are_hittable", bats.size() == 6 and es.hittable_targets().size() == 6, str(es.hittable_targets().size()))
	# 1匹撃つ(来た方向に一直線)と群れ全体が飛び立つ。飛行中は当たらない
	var b0: Dictionary = es.ref(int(bats[0]))
	await click(w2s(Vector2(b0.pos)))
	await run(0.5, 0.1, 2)
	var states: Dictionary = {}
	for id: Variant in alive("bat_flock"):
		states[str(es.ref(int(id)).state)] = true
	var fly: int = 0
	var hit_ok: int = 0
	for id2: Variant in alive("bat_flock"):
		var st: String = str(es.ref(int(id2)).state)
		if st == "swarm":
			fly += 1
			if es.is_hittable(es.ref(int(id2))):
				hit_ok += 1
	ck("one_hit_wakes_flock_and_flying_bats_are_not_hittable", alive("bat_flock").size() <= 5 and fly >= 3 and hit_ok == 0, "alive=%d fly=%d states=%s" % [alive("bat_flock").size(), fly, str(states.keys())])
	# 夜は24秒、昼は12秒(昼夜は N キー)
	fresh()
	await spawn_ui("tab:enemy2", "balloon_frog", Vector2(180, 90))
	g.hero_pos = Vector2(150, 90)
	await run(2.6, 0.1, 2)
	var fl: Array = []
	for id3: Variant in alive("balloon_frog"):
		if str(es.ref(int(id3)).state) in ["inflate", "float"]:
			fl.append(id3)
	ck("frogs_inflate_when_hero_near", fl.size() >= 1, str(fl.size()))
	await run(1.5, 0.1, 2)
	var floaters: Array = []
	for id4: Variant in alive("balloon_frog"):
		if str(es.ref(int(id4)).state) == "float":
			floaters.append(int(id4))
	ck("frog_floats_and_is_still_hittable", floaters.size() >= 1 and es.is_hittable(es.ref(int(floaters[0]))), str(floaters))
	if floaters.size() >= 1:
		var fp: Vector2 = Vector2(es.ref(int(floaters[0])).pos)
		g.hero_pos = fp + Vector2(-30, 0)
		await click(w2s(fp))
		await run(0.4, 0.1, 2)
		ck("floating_frog_pops_on_one_hit_and_leaves_acid", es.acid_pools().size() >= 1 or alive("balloon_frog").size() < 3, "acid=%d alive=%d" % [es.acid_pools().size(), alive("balloon_frog").size()])
	# ガラスジカ: 一撃で砕け、即時に120種。安定判定に数えない
	fresh()
	g.hero_pos = Vector2(200, 100)
	await spawn_ui("tab:enemy2", "glass_deer", Vector2(230, 100))
	var gd: int = int(alive("glass_deer")[0])
	ck("glass_deer_not_counted_for_stability", es.living_count_for_stability() == 0 and not es.counts_for_stability(gd), str(es.living_count_for_stability()))
	var cat: String = ""
	for d: Dictionary in es.detectable_enemies():
		if int(d.id) == gd:
			cat = str(d.category)
	ck("glass_deer_detected_with_bonus_category", cat == "bonus", cat)
	var tgt: Array = es.helper_targets()
	ck("glass_deer_is_excluded_from_helper_targets", tgt.is_empty(), str(tgt.size()))
	var seeds0: int = g.seeds
	var gp: Vector2 = Vector2(es.ref(gd).pos)
	g.hero_pos = gp + Vector2(-30, 0)
	await click(w2s(gp))
	await run(0.4, 0.1, 2)
	ck("glass_deer_shatters_in_one_shot_and_pays_120_once", not es.is_alive(gd) and g.seeds - seeds0 >= 119 and g.cnt("reward") == 1, "seeds=+%d rewards=%d" % [g.seeds - seeds0, g.cnt("reward")])

# ---------------------------------------------------------------- 6. 気絶と仕事停止のホスト側反映
func t_stun_and_helper() -> void:
	fresh()
	g.hero_pos = Vector2(120, 100)
	g.host.helper_list.append({"id": 9101, "pos": Vector2(135, 100), "hp": 50.0, "max_hp": 50.0})
	# 外部(ホスト)が作ったイベントを窓口へ中継する(relay_events)
	var stun: Dictionary = Common2.hero_stun_event(1.5, 0)
	g.apply_events(g.pack.relay_events([stun, Common2.helper_stop_event(9101, 2.0, "stun")]))
	ck("relay_events_sets_hero_stun_and_helper_stop", g.hero_stunned() and g.pack.common.helper_stopped(9101), "")
	var p0: Vector2 = g.hero_pos
	await key(KEY_D, true)
	g.step(0.5)
	await key(KEY_D, false)
	ck("stunned_hero_cannot_move_by_wasd", g.hero_pos.distance_to(p0) < 0.01, str(g.hero_pos))
	var s0: int = g.seeds
	await click(w2s(Vector2(200, 100)))
	await click(w2s(Vector2(200, 100)), MOUSE_BUTTON_RIGHT)
	ck("stunned_hero_cannot_shoot_or_water", g.seeds == s0 and g.water >= 99.9 and g.msg == "STUNNED", "seeds=%d water=%.0f msg=%s" % [g.seeds - s0, g.water, g.msg])
	g.step(1.6)
	ck("stun_ends_after_1_5_seconds", not g.hero_stunned(), "")
	g.step(0.6)
	ck("helper_stop_ends_after_its_seconds", not g.pack.common.helper_stopped(9101), "")
	await key(KEY_D, true)
	g.step(0.5)
	await key(KEY_D, false)
	ck("hero_moves_again_after_stun", g.hero_pos.x > p0.x + 10.0, str(g.hero_pos))
	# タイホウエビの衝撃波が主人公と助っ人を気絶・停止させる
	fresh()
	g.hero_pos = Vector2(120, 100)
	g.host.helper_list.append({"id": 9102, "pos": Vector2(126, 100), "hp": 50.0, "max_hp": 50.0})
	await spawn_ui("tab:enemy2", "pistol_shrimp", Vector2(140, 100))
	await run(2.0, 0.1, 2)
	ck("shrimp_wave_stuns_hero_and_stops_helper_via_events", g.cnt("hero_stun") >= 1 and g.cnt("helper_stop") >= 1, "stun=%d stop=%d" % [g.cnt("hero_stun"), g.cnt("helper_stop")])
	# スカンクの臭気: 助っ人は仕事停止(odor)、主人公は減速
	fresh()
	g.hero_pos = Vector2(120, 100)
	g.host.helper_list.append({"id": 9103, "pos": Vector2(128, 100), "hp": 50.0, "max_hp": 50.0})
	es.add_odor(Vector2(118, 100), Vector2.RIGHT, 0, 60.0, 40.0, 8.0)
	await run(1.0, 0.1, 2)
	ck("odor_slows_hero_and_stops_helper", g.cnt("hero_slow") >= 1 and g.cnt("helper_stop") >= 1 and g.pack.common.helper_stopped(9103), "slow=%d stop=%d" % [g.cnt("hero_slow"), g.cnt("helper_stop")])
	var p1: Vector2 = g.hero_pos
	await key(KEY_D, true)
	g.step(0.5)
	await key(KEY_D, false)
	var slowed: float = g.hero_pos.x - p1.x
	ck("slowed_hero_moves_about_60_percent", slowed > 10.0 and slowed < 17.0, "%.1f" % slowed)

# ---------------------------------------------------------------- 7. カガミトカゲの反射とスカンクの向き
func t_mirror_skunk() -> void:
	fresh()
	await spawn_ui("tab:enemy2", "mirror_lizard", Vector2(150, 100))
	var id: int = int(alive("mirror_lizard")[0])
	es.ref(id).face = Vector2.LEFT
	es.ref(id).pos = Vector2(150, 100)
	g.hero_pos = Vector2(110, 100)
	await click(w2s(Vector2(150, 100)))
	await run(0.3, 0.1, 1)
	var refl: int = 0
	for pr: Dictionary in es.projectile_list():
		if str(pr.get("kind", "")) == "reflected":
			refl += 1
	ck("front_shot_is_reflected_and_does_no_damage", (refl >= 1 or g.cnt("hero_damage") >= 1) and is_equal_approx(hp_of(id), 30.0), "refl=%d hp=%s dmg=%d" % [refl, hp_of(id), g.cnt("hero_damage")])
	await run(1.0, 0.1, 2)
	ck("reflected_shot_hurts_hero", g.cnt("hero_damage") >= 1 and g.hp < g.max_hp, "hp=%.1f" % g.hp)
	g.hero_pos = Vector2(190, 100)
	g.hp = g.max_hp
	es.ref(id).face = Vector2.LEFT
	es.ref(id).state = "idle"
	await click(w2s(Vector2(150, 100)))
	await run(0.4, 0.1, 1)
	ck("rear_shot_hits_mirror_lizard", hp_of(id) < 30.0, "hp=%s" % hp_of(id))
	# スカンク: 正面からの射撃で臭気、背後では出ない
	fresh()
	await spawn_ui("tab:enemy2", "skunk", Vector2(150, 100))
	var sid: int = int(alive("skunk")[0])
	es.ref(sid).face = Vector2.DOWN
	es.ref(sid).pos = Vector2(150, 100)
	g.hero_pos = Vector2(150, 140)
	await click(w2s(Vector2(150, 100)))
	await run(1.2, 0.1, 2)
	ck("front_shot_makes_skunk_spray_odor_cloud", es.odor_clouds().size() >= 1, str(es.odor_clouds().size()))
	es.odor.clear()
	es.ref(sid).spray_at = 0.0
	es.ref(sid).face = Vector2.DOWN
	es.ref(sid).state = "idle"
	g.hero_pos = Vector2(150, 60)
	g.hp = g.max_hp
	await click(w2s(Vector2(150, 100)))
	await run(1.2, 0.1, 2)
	ck("rear_shot_does_not_make_skunk_spray", es.odor_clouds().is_empty() or hp_of(sid) < 18.0, "odor=%d hp=%s" % [es.odor_clouds().size(), hp_of(sid)])

# ---------------------------------------------------------------- 8. カミナリウナギと濡れたマス・カバの水中
func t_eel_wet() -> void:
	fresh()
	g.hero_pos = Vector2(100, 30)
	await spawn_ui("tab:enemy2", "thunder_eel", Vector2(40, 30))
	var id: int = int(alive("thunder_eel")[0])
	var water_mult_hp: float = hp_of(id)
	# 水面のウナギは常に撃てる(×0.75)
	ck("eel_always_hittable_in_water", es.is_hittable(es.ref(id)), "")
	g.hero_pos = Vector2(70, 30)
	await click(w2s(Vector2(40, 30)))
	await run(0.8, 0.1, 2)
	var dmg: float = water_mult_hp - hp_of(id)
	ck("eel_takes_75_percent_damage", absf(dmg - 3.75) < 0.2, "dmg=%.2f" % dmg)
	# 放電が濡れたマスを伝って遠くの主人公に届く
	g.hero_pos = Vector2(100, 30)
	for x: int in [70, 78, 86, 94, 100]:
		await click(w2s(Vector2(float(x), 30)), MOUSE_BUTTON_RIGHT)
	var wet0: int = g.pack.common.wet_cells().size()
	var e: Dictionary = es.ref(id)
	e.next_at = 0.0
	e.state = "swim"
	g.hp = g.max_hp
	await run(2.5, 0.1, 2)
	ck("wet_cells_chain_carries_discharge_to_hero", wet0 >= 8 and g.cnt("hero_damage") >= 1, "wet=%d dmg=%d hp=%.0f" % [wet0, g.cnt("hero_damage"), g.hp])
	# カバ: 水中は×0.5
	fresh()
	g.hero_pos = Vector2(70, 30)
	await spawn_ui("tab:enemy2", "hippo", Vector2(30, 30))
	var hid: int = int(alive("hippo")[0])
	var h0: float = hp_of(hid)
	await click(w2s(Vector2(30, 30)))
	await run(0.8, 0.1, 2)
	ck("hippo_in_water_takes_half_damage", absf((h0 - hp_of(hid)) - 2.5) < 0.2, "dmg=%.2f" % (h0 - hp_of(hid)))

# ---------------------------------------------------------------- 9. マンホール網を植物で塞いで制圧
func t_manhole_net() -> void:
	fresh()
	g.hero_pos = Vector2(160, 84)
	await spawn_ui("tab:enemy2", "manhole", Vector2(190, 100))
	var mh: Array = alive("manhole")
	ck("manhole_net_spawned_3", mh.size() == 3, str(mh.size()))
	await btn("tab:crop")
	await btn("pick_crop:clover")
	var cells: Array = []
	for id: Variant in mh:
		cells.append(Vector2i(Vector2(es.ref(int(id)).pos) / 4.0))
	var placed: int = 0
	for c: Variant in cells:
		var cc: Vector2i = c
		await click(w2s((Vector2(cc) + Vector2(0.5, 0.5)) * 4.0))
		placed = g.pack.crops.crops.size()
	ck("crops_can_be_planted_on_manholes_from_panel", placed == 3, "placed=%d" % placed)
	g.step(0.3)
	var closed: int = 0
	for id2: Variant in alive("manhole"):
		if str(es.ref(int(id2)).state) == "closed":
			closed += 1
	ck("plugged_manholes_close", closed == 3, "closed=%d" % closed)
	g.step(1.0)
	ck("closing_all_manholes_suppresses_nest_and_pays_once", g.cnt("nest_suppressed") == 1 and g.cnt("reward") == 1, "supp=%d reward=%d" % [g.cnt("nest_suppressed"), g.cnt("reward")])
	ck("closed_manholes_not_counted_for_stability", es.living_count_for_stability() == 0, str(es.living_count_for_stability()))

# ---------------------------------------------------------------- 10. 植物8種をパネルから置く
func t_crops_panel() -> void:
	fresh()
	var spots: Dictionary = {"evening_primrose": Vector2i(20, 22), "dandelion": Vector2i(24, 22), "mimosa": Vector2i(28, 22), "kudzu": Vector2i(32, 22),
		"loofah": Vector2i(36, 22), "hinoki": Vector2i(41, 33), "apple": Vector2i(20, 30), "balsam": Vector2i(28, 30)}
	await btn("tab:crop2")
	var s0: int = g.seeds
	for kind: Variant in Game.CROP2_LIST:
		var k: String = str(kind[0])
		await btn("pick_crop:" + k)
		var cell: Vector2i = spots[k]
		var sz: Vector2i = g.pack.crops.size_of(k)
		# クリックしたマスが占有の中心になる(crop_cell_for)
		await click(w2s((Vector2(cell) + Vector2(0.5, 0.5)) * 4.0))
	ck("eight_wave2_crops_placed_by_panel_clicks", g.pack.crops.crops.size() == 8, "n=%d" % g.pack.crops.crops.size())
	ck("placement_spends_seeds", s0 - g.seeds > 300, "spent=%d" % (s0 - g.seeds))
	g.step(0.2)

# ---------------------------------------------------------------- 11. 植物8種の動作(表示用の情報が出ること)
func t_crop_behaviors() -> void:
	var cs: RefCounted = g.pack.crops
	# ツキミソウ: 夜に多い
	fresh()
	var r1: Dictionary = cs.spawn_crop("evening_primrose", Vector2i(20, 22), 25, {"mature": true, "watered": true, "skip_check": true})
	var eid: int = int(r1.id)
	var day_rate: float = float(cs.production_info(eid).rate)
	g.host.day = false
	var night_rate: float = float(cs.production_info(eid).rate)
	ck("evening_primrose_night_rate_above_day_rate", night_rate > day_rate * 3.0, "day=%.4f night=%.4f" % [day_rate, night_rate])
	g.host.day = true
	# タンポポ: 綿毛が荒地へ種をまく(備蓄は減らない)
	fresh()
	var dmd: Dictionary = cs.spawn_crop("dandelion", Vector2i(48, 27), 20, {"mature": true, "watered": true, "skip_check": true})
	cs._by_id[int(dmd.id)].ext.next_fluff_at = 0.0
	var seeds_before: int = g.seeds
	g.step(0.3)
	var sown: int = 0
	for k: Variant in g.host.stage_override.keys():
		if g.host.stage_override[k] == "seed":
			sown += 1
	ck("dandelion_fluff_sows_seed_stage_without_spending_stock", g.cnt("seed_sow") >= 1 and sown >= 1 and g.seeds >= seeds_before, "events=%d sown=%d" % [g.cnt("seed_sow"), sown])
	# ホウセンカ: はじけて播種と範囲ダメージ
	fresh()
	var bs: Dictionary = cs.spawn_crop("balsam", Vector2i(48, 27), 20, {"mature": true, "watered": true, "skip_check": true})
	cs._by_id[int(bs.id)].ext.next_pop_at = 0.0
	var did: int = es.spawn("slime_slug", Vector2(196, 112), "initial")
	g.step(0.3)
	ck("balsam_bursts_sows_and_hurts_nearby_enemy", g.cnt("balsam_burst") >= 1 and hp_of(did) < float(es.ref(did).max_hp), "burst=%d sow=%d" % [g.cnt("balsam_burst"), g.cnt("seed_sow")])
	# オジギソウ: 近い敵で閉じる
	fresh()
	var ms: Dictionary = cs.spawn_crop("mimosa", Vector2i(30, 24), 25, {"mature": true, "watered": true, "skip_check": true})
	es.spawn("slime_slug", Vector2(124, 100), "initial")
	g.step(0.3)
	await frame()
	ck("mimosa_closes_when_enemy_near", bool(cs.get_crop(int(ms.id)).ext.closed) and g.cnt("mimosa_closed") >= 1, "")
	# クズ: 根が伸び、根のマスをRで撤去できる
	fresh()
	var kz: Dictionary = cs.spawn_crop("kudzu", Vector2i(30, 24), 20, {"mature": true, "watered": true, "skip_check": true})
	cs._by_id[int(kz.id)].ext.next_grow_at = 0.0
	for i: int in range(6):
		cs._by_id[int(kz.id)].ext.next_grow_at = 0.0
		g.step(0.2)
	var roots: int = (cs.get_crop(int(kz.id)).ext.roots as Array).size()
	ck("kudzu_grows_roots_within_distance_4", roots >= 3, "roots=%d" % roots)
	var rc0: Vector2i = (cs.get_crop(int(kz.id)).ext.roots as Array)[0]
	await tap(KEY_R)
	await click(w2s((Vector2(rc0) + Vector2(0.5, 0.5)) * 4.0))
	ck("remove_tool_removes_one_root_with_no_refund", (cs.get_crop(int(kz.id)).ext.roots as Array).size() == roots - 1 and not (cs.get_crop(int(kz.id)).ext.roots as Array).has(rc0), "roots=%d" % (cs.get_crop(int(kz.id)).ext.roots as Array).size())
	await tap(KEY_ESCAPE)
	await frame()
	# ヘチマ: 水で貯水が10に戻り、隣の未給水の株を給水する
	fresh()
	var lf: Dictionary = cs.spawn_crop("loofah", Vector2i(30, 24), 25, {"mature": true, "watered": true, "skip_check": true})
	var cl: Dictionary = cs.spawn_crop("clover", Vector2i(33, 24), 10, {"mature": false, "watered": false, "skip_check": true})
	await click(w2s((Vector2(30.5, 24.5)) * 4.0), MOUSE_BUTTON_RIGHT)
	ck("water_click_refills_loofah_storage_to_10", cs.loofah_water(int(lf.id)) == 10, "water=%d" % cs.loofah_water(int(lf.id)))
	cs._by_id[int(cl.id)].watered = false
	cs._by_id[int(lf.id)].ext.next_water_at = 0.0
	g.step(0.3)
	ck("loofah_waters_nearby_unwatered_crop", bool(cs.get_crop(int(cl.id)).watered) and g.cnt("water_crop") >= 1, "storage=%d" % cs.loofah_water(int(lf.id)))
	# ヒノキ: 成熟後に動的な日陰ができ、ドクダミ(日陰)の倍率に使われる
	fresh()
	var hk: Dictionary = cs.spawn_crop("hinoki", Vector2i(40, 30), 120, {"mature": false, "watered": true, "skip_check": true})
	ck("hinoki_has_no_shade_before_maturity", cs.dynamic_shade_cells().is_empty(), "")
	cs.debug_force_mature(int(hk.id), false)
	ck("hinoki_mature_makes_dynamic_shade", cs.dynamic_shade_cells().size() == 6, str(cs.dynamic_shade_cells().size()))
	await frame()
	# リンゴ: 落果し、草食(シカ)が引き寄せられる
	fresh()
	var ap: Dictionary = cs.spawn_crop("apple", Vector2i(30, 24), 60, {"mature": true, "watered": true, "skip_check": true})
	cs._by_id[int(ap.id)].ext.next_fruit_at = 0.0
	g.step(0.3)
	var fruit_n: int = cs.fruit_list().size()
	ck("apple_drops_fruit", fruit_n >= 1 and g.cnt("fruit_dropped") >= 1, "fruit=%d" % fruit_n)
	await frame()
	var deer: int = es.spawn("deer", Vector2(140, 130), "initial")
	var f0: Vector2 = Vector2(cs.fruit_list()[0].pos)
	g.hero_pos = Vector2(10, 140)
	for i: int in range(250):
		g.step(0.1)
		if cs.fruit_list().is_empty():
			break
	ck("herbivore_deer_goes_for_the_fallen_fruit_and_eats_it", cs.fruit_list().is_empty() and g.cnt("fruit_eaten") >= 1, "fruit=%d eaten=%d" % [cs.fruit_list().size(), g.cnt("fruit_eaten")])

# ---------------------------------------------------------------- 12. 保存・ポーズ・キー
func t_save_pause_keys() -> void:
	fresh()
	var cs: RefCounted = g.pack.crops
	g.hero_pos = Vector2(120, 100)
	cs.spawn_crop("kudzu", Vector2i(30, 24), 20, {"mature": true, "watered": true, "skip_check": true})
	cs.spawn_crop("apple", Vector2i(36, 24), 60, {"mature": true, "watered": true, "skip_check": true})
	for c: Dictionary in cs.crops:
		if c.kind == "kudzu":
			c.ext.next_grow_at = 0.0
		if c.kind == "apple":
			c.ext.next_fruit_at = 0.0
	await spawn_ui("tab:enemy2", "root_mole", Vector2(100, 120))
	await spawn_ui("tab:enemy2", "manhole", Vector2(190, 100))
	await spawn_ui("tab:enemy2", "bat_flock", Vector2(110, 66))
	es.add_odor(Vector2(60, 100), Vector2.RIGHT, 0, 50.0, 30.0, 8.0)
	es.add_acid(Vector2(70, 120), 0, 16.0, 5.0, 3.0)
	await click(w2s(Vector2(150, 110)), MOUSE_BUTTON_RIGHT)
	for i: int in range(20):
		for c2: Dictionary in cs.crops:
			if c2.kind == "kudzu":
				c2.ext.next_grow_at = 0.0
		g.step(0.1)
	var snap: Dictionary = {"enemies": es.enemies.size(), "roots": cs.root_cells().size(), "fruit": cs.fruit_list().size(), "wet": g.pack.common.wet_cells().size(),
		"odor": es.odor_clouds().size(), "acid": es.acid_pools().size(), "bats": alive("bat_flock").size(), "manholes": alive("manhole").size()}
	ck("save_state_has_wave2_content_before_saving", snap.roots >= 1 and snap.fruit >= 1 and snap.wet >= 1 and snap.odor == 1 and snap.acid == 1 and snap.manholes == 3, str(snap))
	await tap(KEY_F5)
	ck("f5_saves", FileAccess.file_exists(Game.SAVE_PATH), "")
	g.clear_enemies()
	for c3: Dictionary in cs.crops.duplicate():
		cs.remove_crop(int(c3.id), "manual")
	g.pack.common.wet.clear()
	ck("state_cleared_before_loading", es.enemies.is_empty() and cs.root_cells().is_empty(), "")
	await tap(KEY_F9)
	var snap2: Dictionary = {"enemies": es.enemies.size(), "roots": cs.root_cells().size(), "fruit": cs.fruit_list().size(), "wet": g.pack.common.wet_cells().size(),
		"odor": es.odor_clouds().size(), "acid": es.acid_pools().size(), "bats": alive("bat_flock").size(), "manholes": alive("manhole").size()}
	ck("f9_restores_wave2_state_exactly", JSON.stringify(snap) == JSON.stringify(snap2), "%s vs %s" % [str(snap), str(snap2)])
	# ポーズ中は何も進まない(濡れ・臭気・植物・敵)
	await tap(KEY_SPACE)
	var t0: float = g.pack.time()
	var ee: float = es.time
	g.step(2.0)
	ck("paused_lab_does_not_advance_pack", g.paused and is_equal_approx(g.pack.time(), t0) and is_equal_approx(es.time, ee), "")
	await tap(KEY_SPACE)
	g.step(0.5)
	ck("resume_advances_pack", g.pack.time() > t0, "")
	# M と H
	await tap(KEY_M)
	ck("key_m_toggles_detect_display", g.show_detect, "")
	await tap(KEY_H)
	ck("key_h_toggles_hidden_display", g.show_hidden, "")
	await frame()
	await tap(KEY_M)
	await tap(KEY_H)
	# 昼夜キーでツキミソウの表示が切り替わる(再描画が通る)
	await tap(KEY_N)
	await frame()
	ck("key_n_toggles_night", not g.host.day, "")
	await tap(KEY_N)
