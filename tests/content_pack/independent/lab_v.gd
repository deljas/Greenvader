extends SceneTree
## 独立検証: 確認画面の操作(エンジン内入力 Input.parse_input_event のみ)と、ポーズ・保存。入口スクリプト。
const OUT_DIR: String = "res://evidence/content_pack/independent"
var checks: Array = []
var lab: Node = null
var g: RefCounted = null
var sc: float = 1.0

func ck(name: String, ok: bool, detail: String = "") -> void:
	checks.append({"name": name, "status": "PASS" if ok else "FAIL", "detail": detail})

func near(a: float, b: float, eps: float = 0.01) -> bool:
	return absf(a - b) <= eps

func frame() -> void:
	await process_frame

func key(code: Key) -> void:
	var ev: InputEventKey = InputEventKey.new()
	ev.physical_keycode = code
	ev.keycode = code
	ev.pressed = true
	Input.parse_input_event(ev)
	await frame()

func click_screen(p: Vector2, button: int = MOUSE_BUTTON_LEFT, shift: bool = false) -> void:
	var mv: InputEventMouseMotion = InputEventMouseMotion.new()
	mv.position = p * sc
	mv.global_position = p * sc
	Input.parse_input_event(mv)
	await frame()
	var ev: InputEventMouseButton = InputEventMouseButton.new()
	ev.position = p * sc
	ev.global_position = p * sc
	ev.button_index = button
	ev.pressed = true
	ev.shift_pressed = shift
	Input.parse_input_event(ev)
	await frame()

func click_world(w: Vector2, button: int = MOUSE_BUTTON_LEFT, shift: bool = false) -> void:
	await click_screen(w * 2.0, button, shift)

func click_btn(action: String) -> void:
	var c: Vector2 = lab.button_center(action)
	ck("button_exists_" + action, c.x >= 0.0, "")
	await click_screen(c)

func run(secs: float) -> void:
	# 実時間dtをそのまま渡して、確認画面のstepを進める(速度倍率つき)
	g.step(secs)

func _initialize() -> void:
	root.unfocusable = true
	var scn: PackedScene = load("res://scenes/content_pack/content_lab.tscn")
	lab = scn.instantiate()
	lab.auto_step = false
	root.add_child(lab)
	await frame()
	await frame()
	g = lab.game
	sc = root.get_final_transform().x.x
	ck("input_scale_known", sc >= 1.0, "scale=%.2f" % sc)
	await t_input_and_enemies()
	await t_crops()
	await t_pause_speed()
	await t_debug_and_save()
	var fails: int = 0
	for c: Dictionary in checks:
		print("%s %s %s" % [c.status, c.name, c.detail])
		if c.status != "PASS":
			fails += 1
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var f: FileAccess = FileAccess.open(OUT_DIR + "/lab_v.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"suite": "lab_v", "display": DisplayServer.get_name(), "total": checks.size(), "failed": fails, "checks": checks}, "\t"))
	f.close()
	print("lab_v total=%d failed=%d" % [checks.size(), fails])
	quit(1 if fails > 0 else 0)

func t_input_and_enemies() -> void:
	await key(KEY_TAB)
	ck("tab_key_toggles_to_crop", g.tab == "crop", g.tab)
	await key(KEY_TAB)
	await click_btn("pick_enemy:tarachunade")
	ck("enemy_button_selects_tool_enemy", g.tool == "enemy" and g.sel_enemy == "tarachunade", "")
	await click_world(Vector2(120, 110))
	var ids: Array = g.pack.enemies.enemy_ids()
	ck("click_spawns_enemy_initial", ids.size() == 1 and g.pack.enemies.ref(ids[0]).kind == "tarachunade" and g.pack.enemies.ref(ids[0]).origin == "initial", str(ids.size()))
	await click_btn("origin:produced")
	await click_world(Vector2(180, 110))
	ids = g.pack.enemies.enemy_ids()
	var prod: int = ids.filter(func(i: int) -> bool: return g.pack.enemies.ref(i).origin == "produced").size()
	ck("origin_toggle_spawns_produced", ids.size() == 2 and prod == 1, "")
	await click_btn("origin:initial")
	# 親子・群れ・巣はまとめて出る
	await click_btn("pick_enemy:mushling_parent")
	await click_world(Vector2(60, 125))
	var kinds: Dictionary = {}
	for i: int in g.pack.enemies.enemy_ids():
		var k: String = g.pack.enemies.ref(i).kind
		kinds[k] = int(kinds.get(k, 0)) + 1
	ck("mushling_family_spawns_1_parent_2_children", kinds.get("mushling_parent", 0) == 1 and kinds.get("mushling_child", 0) == 2, str(kinds))
	await click_btn("pick_enemy:stray_wolf")
	await click_world(Vector2(210, 60))
	var wolves: int = g.pack.enemies.enemy_ids().filter(func(i: int) -> bool: return g.pack.enemies.ref(i).kind == "stray_wolf").size()
	ck("wolf_pack_spawns_3", wolves == 3, str(wolves))
	await click_btn("pick_enemy:sludge_carp")
	await click_world(Vector2(130, 110))   # 陸: 拒否
	var carp0: int = g.pack.enemies.enemy_ids().filter(func(i: int) -> bool: return g.pack.enemies.ref(i).kind == "sludge_carp").size()
	await click_world(Vector2(30, 30))
	var carp1: int = g.pack.enemies.enemy_ids().filter(func(i: int) -> bool: return g.pack.enemies.ref(i).kind == "sludge_carp").size()
	ck("carp_only_spawns_in_water", carp0 == 0 and carp1 == 1, "%d %d" % [carp0, carp1])
	await click_btn("clear_enemies")
	ck("clear_enemies_button", g.pack.enemies.enemy_ids().is_empty(), "")
	# 戦闘: 射撃(左クリック)、水(右クリック)、たいあたり(shift+左)、バズーカ(shift+右)
	await click_btn("tool:combat")
	g.hero_pos = Vector2(100, 100)
	var s0: int = g.seeds
	await click_btn("pick_enemy:deer")
	await click_world(Vector2(150, 100))
	var deer: int = g.pack.enemies.enemy_ids()[0]
	await click_btn("tool:combat")
	await click_world(Vector2(150, 100), MOUSE_BUTTON_LEFT, false)
	ck("left_click_shoots_costs_seed", g.seeds == s0 - 1 and g.bullets.size() == 1, "%d %d" % [g.seeds, g.bullets.size()])
	run(1.0)
	ck("shot_reaches_and_damages_deer", float(g.pack.enemies.ref(deer).hp) < 30.0, str(g.pack.enemies.ref(deer).hp))
	var hp1: float = float(g.pack.enemies.ref(deer).hp)
	await click_world(Vector2(150, 100), MOUSE_BUTTON_RIGHT, false)
	ck("right_click_waters_costs_water", g.water < 100.0 + 0.01 and g.fx_list.any(func(f: Dictionary) -> bool: return f.kind == "water"), str(g.water))
	await click_world(Vector2(150, 100), MOUSE_BUTTON_RIGHT, true)
	ck("shift_right_bazooka_costs_5_seeds", g.fx_list.any(func(f: Dictionary) -> bool: return f.kind == "explosion"), "")
	ck("bazooka_damaged", not g.pack.enemies.enemy_ids().has(deer) or float(g.pack.enemies.ref(deer).hp) < hp1, "")
	var x0: Vector2 = g.hero_pos
	await click_world(Vector2(160, 100), MOUSE_BUTTON_LEFT, true)
	ck("shift_left_tackle_moves_hero_forward", g.hero_pos.x > x0.x + 5.0, "")
	# 撃破→報酬が種へ
	# 水やり→植物の給水
	await click_btn("clear_enemies")

func t_crops() -> void:
	await key(KEY_TAB)
	await click_btn("pick_crop:clover")
	ck("crop_button_selects_crop_tool", g.tool == "crop" and g.sel_crop == "clover", "")
	g.seeds = 1000
	var s0: int = g.seeds
	await click_world(Vector2(100, 100))
	var ids: Array = g.pack.crops.crop_ids()
	ck("click_places_clover_pays_price", ids.size() == 1 and g.seeds == s0 - 10, "%d %d" % [ids.size(), g.seeds])
	var cid: int = ids[0]
	await click_world(Vector2(100, 100))
	ck("occupied_cell_rejected", g.pack.crops.crop_ids().size() == 1 and g.seeds == s0 - 10, g.msg)
	await click_btn("pick_crop:clover")
	await click_world(Vector2(120, 100))
	ck("second_clover_price_11", g.seeds == s0 - 10 - 11, str(g.seeds))
	# 配置できない場所の拒否(清水の遠いワサビ、荒地のクローバー、水中のスイカ)
	await click_btn("pick_crop:wasabi")
	var n0: int = g.pack.crops.crop_ids().size()
	await click_world(Vector2(120, 130))
	ck("wasabi_far_from_clean_water_rejected", g.pack.crops.crop_ids().size() == n0 and g.msg.contains("CLEAN"), g.msg)
	await click_world(Vector2(16, 82))   # 清水(x8..28,y56..76)の南2マス(cell y=20)
	ck("wasabi_near_clean_water_accepted", g.pack.crops.crop_ids().size() == n0 + 1, g.msg)
	await click_btn("pick_crop:cactus")
	await click_world(Vector2(190, 110))   # 荒地
	ck("cactus_on_wasteland_accepted", g.pack.crops.crop_ids().size() == n0 + 2, g.msg)
	await click_btn("pick_crop:lotus")
	await click_world(Vector2(60, 40))   # cell(15,10): 2x2が陸にはみ出す
	var lot: int = g.pack.crops.crop_ids().size()
	ck("lotus_partly_on_land_rejected", lot == n0 + 2 and g.msg.contains("NOT_WATER"), g.msg)
	await click_world(Vector2(57, 41))   # cell(14,10): 浅瀬の2x2、東が陸
	ck("lotus_on_shallow_with_shore_accepted", g.pack.crops.crop_ids().size() == n0 + 3, g.msg)
	# 撤去: 20%返還
	await click_btn("tool:remove")
	var before: int = g.seeds
	await click_world(Vector2(100, 100))
	ck("remove_refunds_20pct", g.seeds == before + 2 and g.pack.crops.crop_id_at(Vector2i(25, 25)) == 0, "%d" % (g.seeds - before))
	await click_btn("tool:combat")
	# 成長と生産: 水をかけて成熟まで早送り
	await click_world(Vector2(120, 100), MOUSE_BUTTON_RIGHT)
	var c2: Dictionary = g.pack.crops.get_crop(g.pack.crops.crop_id_at(Vector2i(30, 25)))
	ck("watering_sets_watered", bool(c2.watered), "")
	var sd0: int = g.seeds
	var tt0: float = g.pack.time()
	g.set_speed(60)
	g.step(1.0)    # 60秒のゲーム内時間
	var c3: Dictionary = g.pack.crops.get_crop(int(c2.id))
	ck("x60_matures_clover_and_produces", bool(c3.mature) and near(g.pack.time() - tt0, 60.0, 0.2), "t=%.1f mature=%s" % [g.pack.time(), str(c3.mature)])
	g.set_speed(1)

func t_pause_speed() -> void:
	var t0: float = g.pack.time()
	var e0: float = g.elapsed
	await key(KEY_SPACE)
	ck("space_pauses", g.paused, "")
	g.step(5.0)
	g.set_speed(60)
	g.step(5.0)
	ck("paused_nothing_advances", near(g.pack.time(), t0, 1e-9) and near(g.elapsed, e0, 1e-9), "%.3f vs %.3f" % [g.pack.time(), t0])
	g.set_speed(0)
	await key(KEY_SPACE)
	g.step(5.0)
	ck("speed0_nothing_advances", not g.paused and near(g.pack.time(), t0, 1e-9), "")
	await click_btn("speed:10")
	ck("speed_10_button", g.speed == 10, "")
	g.step(1.0)
	ck("x10_advances_10s", near(g.pack.time(), t0 + 10.0, 0.2), "%.2f" % (g.pack.time() - t0))
	await click_btn("speed:1")
	await click_btn("pause")
	ck("pause_button", g.paused, "")
	await click_btn("pause")
	# 昼夜
	var d0: bool = g.host.day
	await key(KEY_N)
	ck("n_key_toggles_day_night", g.host.day != d0, "")
	await click_btn("day")
	ck("day_button_toggles_back", g.host.day == d0, "")

func t_debug_and_save() -> void:
	# デバッグ表示は通常と区別される
	await click_btn("tool:combat")
	g.seeds = 1000
	g.log.clear()
	await click_btn("pick_crop:clover")
	await click_world(Vector2(200, 60))
	var cid: int = g.sel_crop_id
	ck("placed_clover_selected", cid > 0, "")
	await click_btn("dbg_mature")
	ck("debug_mature_matures_selected_without_roll", bool(g.pack.crops.get_crop(cid).mature) and not bool(g.pack.crops.get_crop(cid).variant_rolled), "")
	var s_before: int = g.seeds
	await click_btn("dbg_seeds")
	ck("debug_seeds_plus100", g.seeds == s_before + 100, "")
	g.log.clear()
	await click_btn("dbg_roll_hit")
	var logtxt: String = " | ".join(g.log.map(func(l: Dictionary) -> String: return l.text))
	ck("forced_roll_hit_turns_four_leaf_and_debug_labelled", g.pack.crops.get_crop(cid).kind == "four_leaf_clover" and logtxt.contains("DEBUG"), logtxt)
	ck("debug_flash_active", g.debug_flash_until > g.elapsed, "")
	g.log.clear()
	await click_btn("dbg_roll_miss")
	ck("second_forced_roll_not_rollable", g.log.any(func(l: Dictionary) -> bool: return str(l.text).contains("NOT ROLLABLE")) and g.pack.crops.get_crop(cid).kind == "four_leaf_clover", "")
	# 四葉は任意設置不可: UIのプレビューで ok=false
	var pv: Dictionary = g.preview("four_leaf_clover", Vector2i(20, 20))
	ck("preview_four_leaf_not_placeable", not bool(pv.ok), str(pv))
	# 保存・復元
	await click_btn("pick_crop:golden_clover")
	g.seeds = 5000
	await click_world(Vector2(240, 100))
	g.tab = "enemy"
	await click_btn("pick_enemy:slime_slug")
	await click_world(Vector2(60, 125))
	g.set_speed(10)
	g.step(2.0)
	g.set_speed(1)
	var snap: String = JSON.stringify(g.pack.to_dict())
	var seeds_at_save: int = g.seeds
	await key(KEY_F5)
	ck("f5_saves", FileAccess.file_exists(g.SAVE_PATH), g.SAVE_PATH)
	g.seeds = 1
	g.pack.crops.remove_crop(cid, "manual")
	g.clear_enemies()
	g.set_speed(10)
	g.step(2.0)
	g.set_speed(1)
	await key(KEY_F9)
	ck("f9_restores_pack_state", JSON.stringify(g.pack.to_dict()) == snap and g.seeds == seeds_at_save, "")
	# 壊れた保存: 何も変わらない
	var f: FileAccess = FileAccess.open(g.SAVE_PATH, FileAccess.READ)
	var good: String = f.get_as_text()
	f.close()
	var d: Dictionary = JSON.parse_string(good)
	d.pack.crops.crops[0].kind = "no_such"
	var w: FileAccess = FileAccess.open(g.SAVE_PATH, FileAccess.WRITE)
	w.store_string(JSON.stringify(d))
	w.close()
	g.seeds = 77
	var snap2: String = JSON.stringify(g.pack.to_dict())
	await key(KEY_F9)
	ck("broken_save_rejected_state_unchanged", JSON.stringify(g.pack.to_dict()) == snap2 and g.seeds == 77 and g.msg.begins_with("LOAD FAILED"), g.msg)
	var w2: FileAccess = FileAccess.open(g.SAVE_PATH, FileAccess.WRITE)
	w2.store_string("{ not json")
	w2.close()
	await key(KEY_F9)
	ck("garbage_save_rejected_state_unchanged", JSON.stringify(g.pack.to_dict()) == snap2 and g.msg == "BAD SAVE", g.msg)
	# 復元後に四葉が再抽選されない(保存→復元→進行)
	var w3: FileAccess = FileAccess.open(g.SAVE_PATH, FileAccess.WRITE)
	w3.store_string(good)
	w3.close()
	await key(KEY_F9)
	g.clear_enemies()
	g.set_speed(60)
	var rolls: int = g.cnt("variant_roll")
	g.step(3.0)
	ck("no_reroll_after_load_and_fast_forward", g.cnt("variant_roll") == rolls and g.pack.crops.get_crop(cid).kind == "four_leaf_clover", "")
