extends SceneTree
## Independent GPU: items 2 (anim frames), 4 (wet look), 6/8 (price UI), 9 (rate label). Offscreen composite, no focus.
const Coords: GDScript = preload("res://scripts/poc/poc_coords.gd")
const OUT: String = "res://evidence/poc3/playtest01/independent/gpu_a/"
var main: Node
var s: RefCounted
var capture: SubViewport
var checks: Array[Dictionary] = []
var pointer: Vector2 = Vector2.ZERO
const C: Vector2i = Vector2i(192, 188)

func _init() -> void: call_deferred("run")
func chk(n: String, ok: bool, d: Variant = "") -> void:
	checks.append({"name": n, "status": "PASS" if ok else "FAIL", "detail": d})
	print(JSON.stringify(checks.back()))
func frames(n: int = 2) -> void:
	for i: int in n: await process_frame
func motion(at: Vector2) -> void:
	var e: InputEventMouseMotion = InputEventMouseMotion.new()
	e.position = at; e.global_position = at; e.relative = at - pointer
	pointer = at
	root.push_input(e, true)
func button(at: Vector2, pressed: bool, which: int) -> void:
	var e: InputEventMouseButton = InputEventMouseButton.new()
	e.position = at; e.global_position = at; e.button_index = which; e.pressed = pressed
	root.push_input(e, true)
func key(code: int) -> void:
	for down: bool in [true, false]:
		var e: InputEventKey = InputEventKey.new()
		e.physical_keycode = code; e.keycode = code; e.pressed = down
		root.push_input(e, true)
		await frames(1)
func grab() -> Image:
	await frames(2); RenderingServer.force_draw(false)
	return capture.get_texture().get_image()
func scr(c: Vector2i) -> Vector2:
	return main.world.camera.unproject_position(Coords.ground3(Coords.logic_to_ground(Coords.cell_center_logic(c))))
func scrp(p: Vector2) -> Vector2:
	return main.world.camera.unproject_position(Coords.ground3(Coords.logic_to_ground(p)))
func avg(img: Image, at: Vector2, r: int = 2) -> Color:
	var sum: Color = Color(0, 0, 0, 0); var n: int = 0
	for y: int in range(int(at.y) - r, int(at.y) + r + 1):
		for x: int in range(int(at.x) - r, int(at.x) + r + 1):
			if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height(): continue
			sum += img.get_pixel(x, y); n += 1
	return sum / float(n)
func dist(a: Color, b: Color) -> float:
	return (absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)) * 255.0
func crop_hash(img: Image, center: Vector2) -> int:
	var rect: Rect2i = Rect2i(Vector2i(center) - Vector2i(24, 40), Vector2i(48, 56)).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	return hash(img.get_region(rect).get_data())
func prep() -> void:
	s.enemies.clear(); s.nests.clear(); s.fossils.clear()
	for y: int in range(180, 196):
		for x: int in range(176, 210): s.state.set_stage(s.state.index_of(x, y), WorldState.STAGE_EMPTY)
	s.position = Coords.cell_center_logic(C + Vector2i(-5, 0))
	s.water = 100.0; s.hp = s.max_hp
	s.known.fill(1)
	main.world.sync(0.0)

func run() -> void:
	var safe: bool = root.unfocusable and root.mode == Window.MODE_MINIMIZED
	chk("startup_no_focus_minimized", safe)
	if not safe: quit(1); return
	change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene"))
	await frames()
	main = current_scene
	main.auto_process = false
	main._audio_changed(true, 0.0)
	main._on_action("new")
	root.notify_mouse_entered()
	s = main.session
	capture = SubViewport.new()
	capture.size = Vector2i(640, 360); capture.disable_3d = true
	capture.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(capture)
	main.view_rect.reparent(capture); main.ui.reparent(capture)
	prep()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	# ---------- item 4: wet vs dry, three growth stages
	for st: int in [WorldState.STAGE_SEED, WorldState.STAGE_SPROUT1, WorldState.STAGE_SPROUT2]:
		prep()
		for y: int in range(185, 192):
			for x: int in range(189, 199): s.state.set_stage(s.state.index_of(x, y), st)
		s.sow_width = 5
		# water left half only: aim cell (191,188) width5 covers x189..193
		s.water_at(Coords.cell_center_logic(Vector2i(191, 188)))
		main.tick(0.0); main.world.sync(0.0)
		var img: Image = await grab()
		img.save_png(ProjectSettings.globalize_path(OUT + "wet_stage%d.png" % st))
		var z: Image = img.get_region(Rect2i(Vector2i(scr(Vector2i(194, 188))) - Vector2i(80, 40), Vector2i(160, 80)))
		z.resize(640, 320, Image.INTERPOLATE_NEAREST)
		z.save_png(ProjectSettings.globalize_path(OUT + "wet_stage%d_zoom.png" % st))
		# compare means over a 5x5-cell area wet vs dry, row-matched
		var wet_sum: Color = Color(0,0,0,0); var dry_sum: Color = Color(0,0,0,0); var nw: int = 0; var nd: int = 0
		for y: int in range(186, 191):
			for x: int in range(189, 199):
				var c: Color = avg(img, scr(Vector2i(x, y)), 3)
				if x <= 193: wet_sum += c; nw += 1
				else: dry_sum += c; nd += 1
		var wm: Color = wet_sum / float(nw); var dm: Color = dry_sum / float(nd)
		chk("item4_wet_distinguishable_stage%d" % st, dist(wm, dm) > 30.0, {"wet": wm.to_html(false), "dry": dm.to_html(false), "dist": dist(wm, dm)})
	# ---------- item 2: water animation frames via engine mouse input
	prep()
	for y: int in range(185, 192):
		for x: int in range(189, 196): s.state.set_stage(s.state.index_of(x, y), WorldState.STAGE_SEED)
	s.sow_width = 3
	main.tick(0.0)
	var aim: Vector2 = scr(C)
	motion(aim); await frames(1); main.tick(0.0)
	var water0: float = s.water
	button(aim, true, MOUSE_BUTTON_RIGHT)
	var rows: Array = []
	var hashes: Array = []
	var spent_t: float = -1.0
	var done_t: float = -1.0
	var t: float = 0.0
	var player_screen: Vector2 = scrp(s.position)
	var strip: Array = []
	var saved: int = 0
	for i: int in 50:
		main.tick(0.02); t += 0.02
		var img2: Image = await grab()
		var h: int = crop_hash(img2, player_screen)
		hashes.append(h)
		if spent_t < 0.0 and s.water < water0: spent_t = t
		rows.append([snappedf(t, 0.01), String(main.world.fire_kind), s.water])
		if i % 5 == 0 and saved < 10:
			var rect: Rect2i = Rect2i(Vector2i(player_screen) - Vector2i(32, 48), Vector2i(64, 64)).intersection(Rect2i(Vector2i.ZERO, img2.get_size()))
			var part: Image = img2.get_region(rect); part.resize(rect.size.x * 3, rect.size.y * 3, Image.INTERPOLATE_NEAREST); strip.append(part); saved += 1
		if i == 49: button(aim, false, MOUSE_BUTTON_RIGHT)
	# distinct consecutive states
	var changes: int = 0
	for i: int in range(1, hashes.size()):
		if hashes[i] != hashes[i - 1]: changes += 1
	var kinds: Array = rows.map(func(r: Array) -> String: return r[1])
	var last_water_idx: int = -1
	for i: int in rows.size():
		if kinds[i] == "water": last_water_idx = i
	chk("item2_water_anim_runs_until_about_800ms", last_water_idx >= 38 and last_water_idx <= 41, {"last_index": last_water_idx, "t_end": rows[last_water_idx][0] if last_water_idx >= 0 else -1})
	chk("item2_water_spent_at_about_400ms_once", spent_t >= 0.38 and spent_t <= 0.46 and absf(s.water - (water0 - 9.0)) < 0.01, {"spent_t": spent_t, "water": s.water})
	chk("item2_sprite_pixels_change_at_least_6_times_in_800ms", changes >= 6, {"changes": changes})
	if not strip.is_empty():
		var w: int = (strip[0] as Image).get_width(); var hh: int = (strip[0] as Image).get_height()
		var sheet: Image = Image.create(w * strip.size(), hh, false, (strip[0] as Image).get_format())
		for i: int in strip.size(): sheet.blit_rect(strip[i], Rect2i(Vector2i.ZERO, Vector2i(w, hh)), Vector2i(i * w, 0))
		sheet.save_png(ProjectSettings.globalize_path(OUT + "water_anim_sheet.png"))
	# held button for 1.7 s on already-watered area: no re-animation, no spending
	chk("item3_hold_after_effect_exhausted_no_further_spend", absf(s.water - (water0 - 9.0)) < 0.01 and String(main.world.fire_kind) == "", {"water": s.water})
	# seed anim: 4 frames / 400ms
	var bare: Vector2i = C + Vector2i(-1, 6)
	s.seeds = 50
	var aim2: Vector2 = scr(bare)
	motion(aim2); await frames(1); main.tick(0.0)
	var seed0: int = s.seeds
	button(aim2, true, MOUSE_BUTTON_LEFT)
	button(aim2, false, MOUSE_BUTTON_LEFT)
	var sh: Array = []
	var sk: Array = []
	var t2: float = 0.0
	for i: int in 25:
		main.tick(0.02); t2 += 0.02
		var im: Image = await grab()
		sh.append(crop_hash(im, scrp(s.position)))
		sk.append(String(main.world.fire_kind))
	var seed_last: int = -1
	for i: int in sk.size():
		if sk[i] == "seed": seed_last = i
	var distinct: Dictionary = {}
	for i: int in range(0, seed_last + 1): distinct[sh[i]] = true
	chk("item2_seed_anim_about_400ms_4_frames", seed_last >= 18 and seed_last <= 21 and distinct.size() >= 3 and s.seeds < seed0, {"last": seed_last, "distinct": distinct.size(), "seeds": [seed0, s.seeds]})

	# ---------- item 6/8: price UI n=0..5, all crop kinds
	prep()
	s.seeds = 100000
	for k: String in ["clover", "carrot", "wheat", "rafflesia", "watermelon"]: s.unlocked[k] = true
	s.favorites.assign(["clover", "carrot", "wheat", "rafflesia", "watermelon"])
	for y: int in range(170, 200):
		for x: int in range(160, 230): s.state.set_stage(s.state.index_of(x, y), WorldState.STAGE_MATURE)
	var table: Dictionary = {"clover": [10, 11, 13, 14, 15, 17], "carrot": [15, 17, 19, 20, 22, 25], "wheat": [40, 44, 49, 54, 59, 65], "rafflesia": [40, 44, 49, 54, 59, 65], "watermelon": [120, 132, 146, 160, 176, 194]}
	var ui: Control = main.ui
	var okslot: bool = true; var okhud: bool = true; var seen: Array = []; var bad: Array = []
	var kinds_list: Array = ["clover", "carrot", "wheat", "rafflesia", "watermelon"]
	for n: int in 6:
		main.tick(0.0); await frames(1)
		for i: int in 5:
			var k: String = kinds_list[i]
			var want: int = table[k][n]
			var slot: Button = ui.favorite_buttons[i]
			if not slot.text.ends_with("●%d" % want): okslot = false; bad.append(["slot", n, k, slot.text, want])
			await key(KEY_1 + i)
			main.tick(0.0); await frames(1)
			if ui.selected_kind != k or not ui.status.text.contains("●%d" % want): okhud = false; bad.append(["hud", n, k, ui.status.text, want, ui.selected_kind])
			seen.append([n, k, slot.text, ui.status.text])
			await key(KEY_1 + i)
		if n == 0 or n == 5:
			(await grab()).save_png(ProjectSettings.globalize_path(OUT + "price_n%d.png" % n))
		for i: int in 5:
			var k: String = kinds_list[i]
			var sz: Array = s.CATALOG[k].size
			var placed: Dictionary = {"ok": false}
			for dy: int in range(165, 215):
				for dx: int in range(150, 240):
					var cell: Vector2i = Vector2i(dx, dy)
					if bool(s.can_place(k, cell).get("ok", false)):
						placed = s.place_plant(k, cell)
						break
				if bool(placed.ok): break
			if not bool(placed.ok): okslot = false; bad.append(["place_fail", k, n, placed, sz])
	chk("item6_8_slot_text_matches_formula_n0_to_5_all_kinds", okslot, bad.slice(0, 6))
	chk("item6_8_shortcut_key_hud_price_matches_n0_to_5", okhud, bad.slice(0, 6))
	# unaffordable tint
	s.seeds = 5
	main.tick(0.0); await frames(1)
	await key(KEY_1); main.tick(0.0); await frames(1)
	chk("item8_unaffordable_marked", ui.status.text.contains("種不足") and ui.favorite_buttons[0].has_theme_color_override("font_color"), ui.status.text)
	(await grab()).save_png(ProjectSettings.globalize_path(OUT + "price_short.png"))
	await key(KEY_1)

	# ---------- item 9: label vs real income per short window
	s.plants.clear(); main.tick(0.0); await frames(1)
	var worst: float = 0.0
	var rows9: Array = []
	for w: int in 5:
		main.tick(0.0); await frames(2)
		var lab: float = float(ui.rate_label.text.split("+")[1].split(" ")[0])
		s.seeds = 0; s.income_fraction = 0.0
		for k2: int in 10: s.advance_game(0.1)
		var got: float = (float(s.seeds) + s.income_fraction) / 1.0
		rows9.append([lab, snappedf(got, 0.001)])
		worst = maxf(worst, absf(lab - got))
	chk("item9_label_equals_income_per_second_grass", worst <= 0.02, rows9)
	for y: int in range(170, 200):
		for x: int in range(160, 230): s.state.set_stage(s.state.index_of(x, y), WorldState.STAGE_MATURE)
	s.seeds = 100000
	for i: int in 6:
		s.place_plant("watermelon", Vector2i(165 + i * 5, 190)); s.place_plant("wheat", Vector2i(165 + i * 5, 195))
	for p: Dictionary in s.plants: p.mature = true
	main.tick(0.0); await frames(2)
	var lab1: float = float(ui.rate_label.text.split("+")[1].split(" ")[0])
	s.seeds = 0; s.income_fraction = 0.0
	for k3: int in 10: s.advance_game(0.1)
	var got1: float = float(s.seeds) + s.income_fraction
	chk("item9_label_equals_income_per_second_with_crops", s.crop_rate() > 0.0 and absf(lab1 - got1) <= 0.02, {"label": lab1, "measured": got1, "crop_per_min": s.crop_rate()})
	(await grab()).save_png(ProjectSettings.globalize_path(OUT + "rate_with_crops.png"))
	var f: int = 0
	for r: Dictionary in checks:
		if r.status == "FAIL": f += 1
	var fa: FileAccess = FileAccess.open(OUT + "results.json", FileAccess.WRITE)
	fa.store_string(JSON.stringify({"checks": checks, "failures": f}, "  ")); fa.close()
	quit(1 if f else 0)
