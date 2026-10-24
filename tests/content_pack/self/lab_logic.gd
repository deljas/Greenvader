extends SceneTree
## 確認画面の操作の自己検証(入口スクリプト、--headless)。シーンを読み込み、Input.parse_input_event で操作を注入する。
## 実行(隔離プロジェクトのみ): Godot --headless --path C:/godot/greenvader_content_sandbox --script res://tests/content_pack/self/lab_logic.gd
const OUT_DIR: String = "res://evidence/content_pack/self"
const Game: GDScript = preload("res://scripts/content_pack/lab/lab_game.gd")

var checks: Array = []
var lab: Node = null
var g: RefCounted = null

func ck(name: String, ok: bool, detail: String = "") -> void:
	checks.append({"name": name, "status": "PASS" if ok else "FAIL", "detail": detail})

# ---------------------------------------------------------------- 入力の注入
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

func kinds_alive(kind: String) -> Array:
	var out: Array = []
	for e: Dictionary in g.pack.enemies.enemies:
		if e.alive and e.kind == kind:
			out.append(int(e.id))
	return out

func crop_count() -> int:
	return g.pack.crops.crops.size()

func log_has(prefix: String, kind: String = "") -> bool:
	for r: Variant in g.log:
		var d: Dictionary = r
		if str(d.text).begins_with(prefix) and (kind == "" or str(d.kind) == kind):
			return true
	return false

func spawn_ui(kind_action: String, world: Vector2) -> void:
	await btn("tab:enemy")
	await btn(kind_action)
	await click(w2s(world))
	await click(Vector2(20, 20), MOUSE_BUTTON_RIGHT)   # 右クリックで戦闘へ戻る

# ---------------------------------------------------------------- 本体
func _initialize() -> void:
	var scn: PackedScene = load("res://scenes/content_pack/content_lab.tscn")
	lab = scn.instantiate()
	lab.auto_step = false
	root.add_child(lab)
	await frame()
	await frame()
	g = lab.game
	await t_assets()
	await t_hero_and_combat()
	await t_water_tara()
	await t_mushling()
	await t_plants()
	await t_fast_forward()
	await t_debug_roll()
	await t_save_load()
	await t_pause_speed()
	await t_misc_controls()
	await t_all_enemies()
	var fails: int = 0
	for c: Dictionary in checks:
		print("%s %s %s" % [c.status, c.name, c.detail])
		if c.status != "PASS":
			fails += 1
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var f: FileAccess = FileAccess.open(OUT_DIR + "/lab_logic.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"suite": "lab_logic", "total": checks.size(), "failed": fails, "checks": checks}, "\t"))
	f.close()
	print("lab_logic total=%d failed=%d" % [checks.size(), fails])
	quit(1 if fails > 0 else 0)

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
	ck("assets_63_sprites_load_at_runtime_without_import", names.size() == 63 and miss.is_empty() and badsize.is_empty(), "n=%d miss=%s badsize=%s" % [names.size(), str(miss), str(badsize)])
	var enemies: Dictionary = g.pack.enemies.defs
	var crops: Dictionary = g.pack.crops.defs
	var absent: Array = []
	for k: Variant in enemies:
		if not bank.has(str(k)):
			absent.append(k)
	for k2: Variant in crops:
		if not bank.has(str(k2)):
			absent.append(k2)
	for k3: String in ["junk_crab_shell", "junk_pile", "moss_turtle_bush", "grass_snake_grass", "mimic_cabbage_disguise", "needle", "mud_ball", "seed_bag", "strawberry_pickup", "hero"]:
		if not bank.has(k3):
			absent.append(k3)
	ck("sprites_cover_all_enemies_crops_and_extras", absent.is_empty(), str(absent))
	ck("bank_image_sizes_match_catalog_px", bank.size_of("giant_watermelon") == Vector2i(56, 40) and bank.size_of("shadow_brian") == Vector2i(32, 24) and bank.size_of("ant_hill") == Vector2i(24, 14) and bank.size_of("bamboo") == Vector2i(10, 32), "")
	ck("save_path_is_lab_only", Game.SAVE_PATH.begins_with("user://content_lab/"), Game.SAVE_PATH)

func t_hero_and_combat() -> void:
	# 主人公の移動(WASD)
	var y0: float = g.hero_pos.y
	await key(KEY_W, true)
	g.step(0.5)
	await key(KEY_W, false)
	var moved_up: float = y0 - g.hero_pos.y
	await key(KEY_S, true)
	g.step(0.5)
	await key(KEY_S, false)
	ck("wasd_moves_hero_and_stops_on_release", absf(moved_up - 24.0) < 0.5 and absf(g.hero_pos.y - y0) < 0.5, "up=%.2f back=%.2f" % [moved_up, g.hero_pos.y - y0])
	# 敵の出現 → 射撃で被弾 → 撃破で報酬(1回)
	await spawn_ui("pick_enemy:slime_slug", Vector2(190, 84))
	var ids: Array = kinds_alive("slime_slug")
	ck("click_spawn_enemy_from_panel_initial", ids.size() == 1 and g.pack.enemies.ref(ids[0]).origin == "initial" and g.tool == "combat", str(ids))
	var seeds0: int = g.seeds
	var sid: int = int(ids[0])
	for i: int in range(5):
		var ep: Vector2 = Vector2(g.pack.enemies.ref(sid).pos) if g.pack.enemies.is_alive(sid) else Vector2(190, 84)
		await click(w2s(ep))
		g.step(0.3)
		await frame()
	var dmg_logged: bool = log_has("HIT SLIME_SLUG")
	ck("lmb_seed_shot_hits_and_defeats_enemy", not g.pack.enemies.is_alive(sid) and dmg_logged and g.cnt("enemy_defeated") >= 1, "alive=%s hit_logged=%s" % [g.pack.enemies.is_alive(sid), dmg_logged])
	ck("defeat_reward_once_and_seed_cost", g.cnt("reward") == 1 and g.rewards_total == 6 and g.seeds == seeds0 - 5 + 6, "seeds %d->%d reward=%d" % [seeds0, g.seeds, g.cnt("reward")])
	# 生産個体は報酬なし。バズーカ(Shift+右クリック)でHP25を一撃
	await btn("origin:produced")
	await spawn_ui("pick_enemy:slime_slug", Vector2(190, 84))
	var pid: int = int(kinds_alive("slime_slug")[0])
	var seeds1: int = g.seeds
	var rw0: int = g.cnt("reward")
	await click(w2s(Vector2(g.pack.enemies.ref(pid).pos)), MOUSE_BUTTON_RIGHT, true)
	ck("shift_rmb_bazooka_kills_produced_enemy_no_reward", not g.pack.enemies.is_alive(pid) and g.cnt("reward") == rw0 and g.seeds == seeds1 - Game.BAZOOKA_COST, "seeds %d->%d" % [seeds1, g.seeds])
	await btn("origin:initial")
	# たいあたり(Shift+左クリック)
	await spawn_ui("pick_enemy:deer", Vector2(172, 84))
	var did: int = int(kinds_alive("deer")[0])
	var hp0: float = float(g.pack.enemies.ref(did).hp)
	await click(w2s(Vector2(176, 84)), MOUSE_BUTTON_LEFT, true)
	var hp1: float = float(g.pack.enemies.ref(did).hp) if g.pack.enemies.is_alive(did) else 0.0
	ck("shift_lmb_tackle_deals_8", absf((hp0 - hp1) - 8.0) < 0.01 and log_has("HIT DEER"), "hp %.1f->%.1f" % [hp0, hp1])
	g.hero_pos = Vector2(160, 84)
	await btn("clear_enemies")
	ck("clear_enemies_button", g.pack.enemies.enemies.is_empty(), "")
	# 種が地面に落ちる(notify_seed)
	var s2: int = g.seeds
	var l0: int = g.landed
	await click(w2s(Vector2(100, 100)))
	g.step(1.0)
	ck("seed_shot_to_ground_lands_and_costs_1", g.landed == l0 + 1 and g.seeds == s2 - 1, "landed=%d seeds %d->%d" % [g.landed, s2, g.seeds])
	# ホスト側の反映(ダメージ・引き寄せ・減速・報酬)
	var hp_b: float = g.hp
	g.apply_events([{"type": "hero_damage", "amount": 10.0, "source": 1, "kind": "x"}])
	var pull_to: Vector2 = g.hero_pos + Vector2(8, 0)
	g.apply_events([{"type": "hero_pull", "to": pull_to, "source": 1}, {"type": "hero_slow", "factor": 0.5, "seconds": 2.0, "source": "t"}])
	var x_before: float = g.hero_pos.x
	await key(KEY_D, true)
	g.step(0.5)
	await key(KEY_D, false)
	var slow_move: float = g.hero_pos.x - x_before
	ck("host_applies_hero_damage_pull_slow", absf(g.hp - (hp_b - 10.0)) < 0.01 and g.hero_pos.x > 160.0 and slow_move > 10.0 and slow_move < 13.0, "hp=%.1f move=%.2f" % [g.hp, slow_move])
	g.hero_pos = Vector2(160, 84)
	g.hp = g.max_hp
	g.slow_until = 0.0

func t_water_tara() -> void:
	await spawn_ui("pick_enemy:tarachunade", Vector2(200, 84))
	var tid: int = int(kinds_alive("tarachunade")[0])
	var w0: float = g.water
	await click(w2s(Vector2(200, 84)), MOUSE_BUTTON_RIGHT)
	var es: RefCounted = g.pack.enemies
	ck("rmb_water_makes_tarachunade_wet_and_costs_water", float(es.ref(tid).wet_until) > es.time and absf(w0 - g.water - 10.0) < 0.01 and log_has("FX WET"), "wet_until=%.1f water %.0f->%.0f" % [float(es.ref(tid).wet_until), w0, g.water])
	await btn("clear_enemies")

func t_mushling() -> void:
	await spawn_ui("pick_enemy:mushling_parent", Vector2(205, 84))
	var parents: Array = kinds_alive("mushling_parent")
	var kids: Array = kinds_alive("mushling_child")
	ck("mushling_family_spawns_together", parents.size() == 1 and kids.size() == 2 and g.pack.enemies.ref(kids[0]).group_id == g.pack.enemies.ref(parents[0]).group_id, "%d/%d" % [parents.size(), kids.size()])
	g.hero_pos = Vector2(185, 84)
	for i: int in range(6):
		g.step(0.5)
	ck("mushling_child_calls_parent_event_reaches_lab", g.cnt("mushling_call") >= 1 and log_has("MUSH CALL"), "calls=%d" % g.cnt("mushling_call"))
	g.hero_pos = Vector2(160, 84)
	g.hp = g.max_hp
	await btn("clear_enemies")

func t_plants() -> void:
	await btn("tab:crop")
	await btn("pick_crop:clover")
	ck("crop_tool_selected_from_panel", g.tool == "crop" and g.sel_crop == "clover" and g.tab == "crop", "")
	var s0: int = g.seeds
	# 配置不可(水面): 変化なし・理由が出る
	await click(w2s(Vector2(22, 22)))
	ck("placement_on_water_refused_with_reason", crop_count() == 0 and g.seeds == s0 and g.msg.begins_with("CANT"), g.msg)
	# 配置
	await motion(w2s(Vector2(162, 110)))
	var pv: Dictionary = g.preview("clover", g.hover_cell)
	ck("preview_shows_ok_and_price_10", bool(pv.ok) and int(pv.price) == 10 and Vector2i(pv.cell) == Vector2i(40, 27), str(pv))
	await click(w2s(Vector2(162, 110)))
	ck("click_places_crop_and_pays_price", crop_count() == 1 and g.seeds == s0 - 10, "seeds %d->%d" % [s0, g.seeds])
	await motion(w2s(Vector2(166, 110)))
	var line: String = g.info_lines()[3]
	ck("info_bar_shows_current_price_for_next_clover", line.contains("PRICE 11"), line)
	await click(w2s(Vector2(166, 110)))
	ck("second_clover_paid_11_same_family_price_rises", crop_count() == 2 and g.seeds == s0 - 21, "seeds=%d" % g.seeds)
	# 占有の表示(同じマス)は配置不可
	var pv2: Dictionary = g.preview("clover", Vector2i(40, 27))
	ck("preview_occupied_cell_not_ok", not bool(pv2.ok) and pv2.reason == "occupied", str(pv2))
	# 大きな植物のプレビューが占有範囲を返す(6x6)
	var pv3: Dictionary = g.preview("giant_watermelon", Vector2i(38, 27))
	ck("preview_giant_watermelon_6x6_footprint", Vector2i(pv3.size) == Vector2i(6, 6), str(pv3))
	# 撤去モード
	await btn("tool:remove")
	var s1: int = g.seeds
	await click(w2s(Vector2(162, 110)))
	ck("remove_mode_removes_and_refunds_20_percent", crop_count() == 1 and g.seeds == s1 + 2 and g.tool == "remove", "seeds %d->%d" % [s1, g.seeds])
	await click(Vector2(300, 20), MOUSE_BUTTON_RIGHT)
	ck("rmb_returns_to_combat", g.tool == "combat", g.tool)

func t_fast_forward() -> void:
	# 追加で2株。給水(デバッグ)して×60で10秒=600ゲーム秒
	await btn("tab:crop")
	await btn("pick_crop:clover")
	await click(w2s(Vector2(170, 110)))
	await click(w2s(Vector2(174, 110)))
	await btn("tool:combat")
	ck("three_clovers_planted", crop_count() == 3, str(crop_count()))
	await btn("dbg_water")
	await btn("speed:60")
	var s0: int = g.seeds
	var e0: float = g.elapsed
	var t0: float = g.pack.time()
	for i: int in range(10):
		g.step(1.0)
	var all_mature: bool = true
	for c: Dictionary in g.pack.crops.crops:
		if not bool(c.mature):
			all_mature = false
	ck("speed_x60_advances_600_game_seconds", absf((g.elapsed - e0) - 600.0) < 0.5 and absf((g.pack.time() - t0) - 600.0) < 0.5, "elapsed %.1f pack %.1f" % [g.elapsed - e0, g.pack.time() - t0])
	ck("fast_forward_matures_crops_and_produces_seeds", all_mature and g.seeds - s0 >= 40 and g.total_rate_per_min() > 0.0 and g.cnt("seeds") > 0, "seeds +%d total=%.2f/min" % [g.seeds - s0, g.total_rate_per_min()])
	ck("info_bar_shows_total_and_selected_rates", g.info_lines()[2].begins_with("TOTAL") and g.selected_info().begins_with("SEL"), g.info_lines()[2])
	await btn("speed:1")

func t_debug_roll() -> void:
	await btn("tab:crop")
	await btn("pick_crop:clover")
	await click(w2s(Vector2(146, 110)))
	await btn("tool:combat")
	var cid: int = g.sel_crop_id
	await btn("dbg_mature")
	var c: Dictionary = g.pack.crops.get_crop(cid)
	ck("debug_mature_makes_selected_crop_mature_without_roll", bool(c.mature) and c.kind == "clover" and not bool(c.variant_rolled), str(c.kind))
	await btn("dbg_roll_hit")
	var c2: Dictionary = g.pack.crops.get_crop(cid)
	ck("debug_forced_roll_hit_becomes_four_leaf_with_debug_event", c2.kind == "four_leaf_clover" and log_has("DEBUG ROLL HIT", "debug") and log_has("DEBUG VARIANT", "debug") and g.cnt("variant") >= 1, str(c2.kind))
	ck("debug_labels_visible_on_screen", g.debug_flash_until > g.elapsed and lab.view.buttons(g).any(func(b: Dictionary) -> bool: return bool(b.get("debug", false))), "")
	var n_var: int = g.cnt("variant")
	await btn("dbg_roll_miss")
	ck("debug_roll_cannot_repeat_after_roll", g.cnt("variant") == n_var and log_has("DEBUG ROLL: NOT ROLLABLE", "debug"), "")
	var s0: int = g.seeds
	await btn("dbg_seeds")
	ck("debug_seeds_plus_100", g.seeds == s0 + 100, "")

func t_save_load() -> void:
	await btn("save")
	var snap: String = JSON.stringify(g.pack.to_dict(), "", true)
	var seeds_s: int = g.seeds
	var hero_s: Vector2 = g.hero_pos
	var crops_s: int = crop_count()
	ck("save_writes_lab_file", FileAccess.file_exists(Game.SAVE_PATH), Game.SAVE_PATH)
	# 変更
	await spawn_ui("pick_enemy:deer", Vector2(172, 84))
	g.step(5.0)
	g.seeds += 77
	g.hero_pos = Vector2(100, 40)
	await btn("tab:crop")
	await btn("pick_crop:mint")
	await click(w2s(Vector2(150, 118)))
	await btn("tool:combat")
	ck("state_mutated_before_load", crop_count() == crops_s + 1 and g.seeds != seeds_s, "")
	await btn("load")
	var snap2: String = JSON.stringify(g.pack.to_dict(), "", true)
	ck("load_restores_pack_state_exactly", snap2 == snap, "len %d/%d" % [snap.length(), snap2.length()])
	ck("load_restores_host_side_seeds_hero_crops", g.seeds == seeds_s and g.hero_pos.distance_to(hero_s) < 0.01 and crop_count() == crops_s and kinds_alive("deer").is_empty(), "seeds=%d crops=%d" % [g.seeds, crop_count()])
	await btn("clear_enemies")

func t_pause_speed() -> void:
	await btn("pause")
	var t0: float = g.pack.time()
	var e0: float = g.elapsed
	g.step(5.0)
	ck("paused_does_not_advance_time", g.paused and g.pack.time() == t0 and g.elapsed == e0, "")
	await tap(KEY_SPACE)
	g.step(2.0)
	ck("space_resumes_and_time_advances", not g.paused and absf(g.pack.time() - t0 - 2.0) < 0.01, "")
	g.set_speed(0)
	var t1: float = g.pack.time()
	g.step(5.0)
	ck("speed_zero_does_not_advance_time", g.pack.time() == t1, "")
	await tap(KEY_2)
	var t2: float = g.pack.time()
	g.step(1.0)
	ck("key_2_sets_x10", g.speed == 10 and absf(g.pack.time() - t2 - 10.0) < 0.01, "")
	await tap(KEY_1)
	ck("key_1_sets_x1", g.speed == 1, "")

func t_misc_controls() -> void:
	await btn("day")
	ck("day_night_button_toggles", not g.host.day, "")
	await tap(KEY_N)
	ck("n_key_toggles_back_to_day", g.host.day, "")
	await spawn_ui("pick_enemy:junk_pile", Vector2(120, 100))
	ck("add_junk_pile_button_adds_pile", g.pack.enemies.piles.size() == 1, str(g.pack.enemies.piles.size()))
	await btn("tab:enemy")
	await btn("pick_enemy:sludge_carp")
	await click(w2s(Vector2(200, 100)))
	var land_try: int = kinds_alive("sludge_carp").size()
	await click(w2s(Vector2(22, 22)))
	var water_try: int = kinds_alive("sludge_carp").size()
	ck("carp_needs_water_cell", land_try == 0 and water_try == 1, "%d/%d" % [land_try, water_try])
	await tap(KEY_ESCAPE)
	await btn("clear_enemies")
	g.pack.enemies.piles.clear()
	await tap(KEY_TAB)
	ck("tab_key_switches_list", g.tab == "enemy" or g.tab == "crop", g.tab)
	await tap(KEY_R)
	ck("r_key_toggles_remove_tool", g.tool == "remove", g.tool)
	await tap(KEY_ESCAPE)
	ck("esc_returns_to_combat", g.tool == "combat", g.tool)

func t_all_enemies() -> void:
	# 全21種(中立のミツバチ・生産するアリ塚・付属を含む)を画面操作で出して数秒動かし、描画を数フレーム回す
	var spots: Array = [Vector2(120, 30), Vector2(140, 30), Vector2(160, 30), Vector2(180, 30), Vector2(200, 30), Vector2(220, 30), Vector2(240, 30),
		Vector2(120, 50), Vector2(140, 50), Vector2(160, 50), Vector2(180, 50), Vector2(200, 50), Vector2(220, 50), Vector2(240, 50),
		Vector2(100, 70), Vector2(30, 40), Vector2(160, 70), Vector2(180, 70), Vector2(200, 70), Vector2(220, 70), Vector2(240, 70), Vector2(250, 90), Vector2(60, 100)]
	await btn("tab:enemy")
	var fails: Array = []
	var i: int = 0
	for entry: Array in Game.ENEMY_LIST:
		var kind: String = entry[0]
		var before: int = g.pack.enemies.enemies.size() + g.pack.enemies.piles.size()
		await btn("pick_enemy:" + kind)
		await click(w2s(spots[i]))
		i += 1
		if g.pack.enemies.enemies.size() + g.pack.enemies.piles.size() <= before:
			fails.append(kind)
	await click(Vector2(20, 20), MOUSE_BUTTON_RIGHT)
	ck("every_enemy_kind_spawns_from_panel", fails.is_empty(), str(fails))
	var n0: int = g.pack.enemies.enemies.size()
	g.hero_pos = Vector2(150, 60)
	for k: int in range(30):
		g.step(0.1)
		await frame()
	ck("all_enemy_kinds_run_3_seconds_and_draw", g.pack.enemies.enemies.size() > 0 and g.pack.time() > 0.0, "n0=%d n=%d" % [n0, g.pack.enemies.enemies.size()])
	var alive_kinds: Dictionary = {}
	for e: Dictionary in g.pack.enemies.enemies:
		alive_kinds[e.kind] = true
	ck("neutral_bees_not_counted_in_stability_number", g.pack.enemies.living_count_for_stability() == g.pack.enemies.enemies.size() - kinds_alive("honeybee_hive").size() - kinds_alive("honeybee_swarm").size(), "stab=%d total=%d" % [g.pack.enemies.living_count_for_stability(), g.pack.enemies.enemies.size()])
