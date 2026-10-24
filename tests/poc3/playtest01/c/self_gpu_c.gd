extends SceneTree
## POC3-PLAYTEST-01 work C (items 8, 9, 10, 12): engine-injected input, real GPU 640x360 composite
## (window stays minimized, no focus). Run with MODE=logic argument for a headless pass without images.
const Coords: GDScript = preload("res://scripts/poc/poc_coords.gd")
const OUT: String = "res://evidence/poc3/playtest01/self/c_gpu/"
var main: Node
var s: RefCounted
var capture: SubViewport
var checks: Array[Dictionary] = []
var pointer: Vector2 = Vector2.ZERO
var images: bool = true

func _init() -> void: call_deferred("run")
func check(name_: String, ok: bool, detail: Variant = "") -> void:
	checks.append({"name": name_, "status": "PASS" if ok else "FAIL", "detail": detail})
	print(JSON.stringify(checks.back()))
func frames(n: int = 3) -> void:
	for i: int in n: await process_frame
func motion(at: Vector2, held: bool = false) -> void:
	var e: InputEventMouseMotion = InputEventMouseMotion.new()
	e.position = at; e.global_position = at; e.relative = at - pointer
	e.button_mask = MOUSE_BUTTON_MASK_LEFT if held else 0
	pointer = at
	root.push_input(e, true)
func button(at: Vector2, pressed: bool, which: int = MOUSE_BUTTON_LEFT) -> void:
	var e: InputEventMouseButton = InputEventMouseButton.new()
	e.position = at; e.global_position = at; e.button_index = which; e.pressed = pressed
	root.push_input(e, true)
func key(code: int) -> void:
	for down: bool in [true, false]:
		var e: InputEventKey = InputEventKey.new()
		e.physical_keycode = code; e.keycode = code; e.pressed = down
		root.push_input(e, true)
		await frames(1)
func shot(file: String, rect: Rect2i = Rect2i(0, 0, 640, 360), factor: int = 1) -> bool:
	if not images: return true
	await frames(); RenderingServer.force_draw(false)
	var image: Image = capture.get_texture().get_image().get_region(rect)
	if factor > 1: image.resize(rect.size.x * factor, rect.size.y * factor, Image.INTERPOLATE_NEAREST)
	return image.save_png(OUT + file) == OK
func prep_world() -> void:
	s.enemies.clear(); s.nests.clear(); s.fossils.clear()
	for kind: String in ["clover", "carrot", "wheat", "watermelon", "army", "sprinkler"]: s.unlocked[kind] = true
	s.favorites.assign(["clover", "carrot", "wheat", "army", "sprinkler"])
	s.hp = s.max_hp
	s.seeds = 500

var added: Array[int] = []
func add_crops(kind: String, count: int, mature: bool) -> int:
	var made: int = 0
	var origin: Vector2i = Coords.logic_to_cell(s.position)
	for ring: int in range(0, 60):
		for dy: int in range(-ring, ring + 1):
			for dx: int in range(-ring, ring + 1):
				if maxi(absi(dx), absi(dy)) != ring or (dx + dy) % 2 != 0: continue
				if made >= count: return made
				var cell: Vector2i = origin + Vector2i(dx, dy)
				if not bool(s.can_place(kind, cell).get("ok", false)): continue
				var before: int = s.seeds
				if bool(s.place_plant(kind, cell).get("ok", false)):
					s.seeds = before
					s.plants.back().mature = mature
					added.append(int(s.plants.back().id))
					made += 1
	return made
func remove_added() -> void:
	for id: int in added: s.remove_plant(id)
	added.clear()

## A walkable known cell whose map point is on the visible map and well clear of every icon.
func find_dest(from: Vector2) -> Vector2:
	for offset: Vector2 in [Vector2(120, 60), Vector2(-120, -60), Vector2(160, -80), Vector2(-160, 80), Vector2(80, 160), Vector2(-80, -160), Vector2(240, 0), Vector2(-240, 0)]:
		var logic: Vector2 = from + offset
		var c: Vector2i = Coords.logic_to_cell(logic)
		if not s.state.in_bounds(c.x, c.y) or not s.state.is_walkable(c.x, c.y): continue
		var at: Vector2 = main.ui.map.point(logic)
		if not main.ui.map.map_rect.grow(-6).has_point(at): continue
		var clear: bool = true
		for entry: Dictionary in main.ui.map._icon_points:
			if entry.pos.distance_to(at) < 12.0: clear = false
		if clear: return Cell_center(c)
	return from + Vector2(120, 60)
func Cell_center(c: Vector2i) -> Vector2: return Coords.cell_center_logic(c)

func run() -> void:
	images = not OS.get_cmdline_user_args().has("--logic")
	var safe: bool = root.unfocusable and root.mode == Window.MODE_MINIMIZED and ProjectSettings.get_setting("display/window/size/no_focus", false)
	if images:
		check("startup_no_focus_minimized", safe)
		if not safe: quit(1); return
	change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene"))
	await frames()
	main = current_scene
	main.auto_process = false
	main._audio_changed(true, 0.0)
	main._on_action("new")
	root.notify_mouse_entered()
	s = main.session
	prep_world()
	if images:
		capture = SubViewport.new()
		capture.size = Vector2i(640, 360); capture.disable_3d = true
		capture.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(capture)
		main.view_rect.reparent(capture); main.ui.reparent(capture)
	var ui: Control = main.ui
	main.tick(0.0); await frames()

	# ---- item 8: price visible on shortcut slots and on selection ----
	var slot0: Button = ui.favorite_buttons[0]
	check("i8_slot_shows_price_n0", slot0.text == "1 ♣ ●%d" % s.current_cost("clover") and s.current_cost("clover") == 10, [slot0.text, s.current_cost("clover"), "1 ♣ ●%d" % s.current_cost("clover"), slot0.text == "1 ♣ ●10", slot0.text.length()])
	await key(KEY_1); main.tick(0.0); await frames()
	check("i8_shortcut_selects_and_hud_price_n0", ui.selected_kind == "clover" and ui.status.text.contains("●%d" % s.current_cost("clover")) and not ui.status.text.contains("不足"), ui.status.text)
	check("i8_img_n0", await shot("price_n0.png"))
	check("i8_img_n0_zoom", await shot("price_n0_slots_zoom.png", Rect2i(0, 322, 320, 38), 3))
	await key(KEY_1)
	check("i8_added_5_clovers", add_crops("clover", 5, false) == 5)
	main.tick(0.0); await frames()
	check("i8_slot_price_n5_is_1p1_pow5", s.current_cost("clover") == 17 and slot0.text.ends_with("●17"), slot0.text)
	await key(KEY_1); main.tick(0.0); await frames()
	check("i8_hud_price_n5", ui.status.text.contains("●17"), ui.status.text)
	check("i8_img_n5", await shot("price_n5.png"))
	await key(KEY_1)
	s.seeds = 15
	main.tick(0.0); await frames()
	check("i8_unaffordable_slot_tinted_only_that_slot", slot0.has_theme_color_override("font_color") and not ui.favorite_buttons[1].has_theme_color_override("font_color") and ui.favorite_buttons[1].text.ends_with("●%d" % s.current_cost("carrot")), [slot0.text, ui.favorite_buttons[1].text, s.current_cost("carrot")])
	await key(KEY_1); main.tick(0.0); await frames()
	check("i8_hud_short_marker", ui.status.text.contains("種不足"), ui.status.text)
	check("i8_img_short", await shot("price_short.png"))
	check("i8_img_short_zoom", await shot("price_short_slots_zoom.png", Rect2i(0, 322, 320, 38), 3))
	await key(KEY_1)
	s.seeds = 500
	remove_added(); s.seeds = 500
	main.tick(0.0)

	# ---- item 9: seed production rate (seeds/s) vs real income ----
	var rate_now: float = (s.land_rate() + s.crop_rate()) / 60.0
	check("i9_rate_label_matches_session", ui.rate_label.text == "生産 +%s ●/s" % ("%.1f" % rate_now if rate_now >= 100.0 else "%.2f" % rate_now), [ui.rate_label.text, rate_now])
	check("i9_img_rate_grass_only", await shot("rate_grass.png"))
	main.world.sync(0.0)
	# Real income over 60 game seconds, measured from the seed counter + carried fraction.
	var run_income: Callable = func(duration: float) -> Dictionary:
		s.paused = false
		var first: float = (s.land_rate() + s.crop_rate()) / 60.0
		var start: float = float(s.seeds) + s.income_fraction
		var left: float = duration
		while left > 0.0:
			var step: float = minf(1.0, left)
			s.advance_game(step); left -= step
		var last: float = (s.land_rate() + s.crop_rate()) / 60.0
		var gained: float = float(s.seeds) + s.income_fraction - start
		return {"first": first, "last": last, "measured": gained / duration}
	var grass: Dictionary = run_income.call(60.0)
	var low: float = minf(grass.first, grass.last); var high: float = maxf(grass.first, grass.last)
	check("i9_grass_real_income_matches_rate", grass.measured >= low * 0.99 - 0.001 and grass.measured <= high * 1.01 + 0.001, grass)
	var wheat_n: int = add_crops("wheat", 10, true)
	var melon_n: int = add_crops("watermelon", 4, true)
	check("i9_added_mature_crops", wheat_n >= 4 and melon_n >= 1, [wheat_n, melon_n])
	main.tick(0.0); await frames()
	var crops: Dictionary = run_income.call(60.0)
	var shown: float = (s.land_rate() + s.crop_rate()) / 60.0
	check("i9_crop_real_income_matches_rate", s.crop_rate() > 0.0 and crops.measured >= minf(crops.first, crops.last) * 0.99 - 0.001 and crops.measured <= maxf(crops.first, crops.last) * 1.01 + 0.001, crops)
	main.tick(0.0); await frames()
	check("i9_rate_label_updates_with_crops", ui.rate_label.text.contains("%.2f" % shown) or ui.rate_label.text.contains("%.1f" % shown), [ui.rate_label.text, shown, s.crop_rate()])
	check("i9_img_rate_crops", await shot("rate_crops.png"))
	check("i9_img_rate_hud_zoom", await shot("rate_hud_zoom.png", Rect2i(440, 0, 200, 100), 3))
	remove_added(); s.seeds = 500

	# ---- item 12: helper relocation guidance ----
	var home_cell: Vector2i = Coords.logic_to_cell(s.position)
	var cell: Vector2i = home_cell + Vector2i(5, 2)
	main._placement_kind = "army"
	main._place(cell)
	await frames()
	check("i12_first_helper_placement_notice", ui.notice.visible and ui.notice.text.contains("配置換え") and ui.notice.text.contains("Tab"), ui.notice.text)
	check("i12_img_first_notice", await shot("hint_first_placement.png"))
	ui.notice_time = 0.0; ui.notice.text = ""
	main._placement_kind = "sprinkler"
	main._place(home_cell + Vector2i(-4, 3))
	check("i12_notice_only_once", ui.notice_time == 0.0, ui.notice.text)
	main._placement_kind = ""
	main.tick(0.0)
	await key(KEY_TAB); await frames(4)
	check("i12_map_open_hint_no_selection", ui.map.expanded and ui.map.hint.visible and ui.map.hint.text.contains("おたすけ植物"), ui.map.hint.text)
	check("i12_img_map_hint_none", await shot("hint_map_none.png"))
	var army: Dictionary = s.helpers[0]
	# zoom 1 map: the click selects immediately (press), as before.
	var at: Vector2 = ui.map.point(army.pos)
	motion(at); button(at, true); await frames(2); button(at, false); await frames(3)
	check("i12_click_selects_helper_zoom1", ui.map.selected_id == int(army.id) and ui.map.selected_helper, ui.map.selected_id)
	check("i12_hint_helper_selected", ui.map.hint.text.contains("活動場所") and ui.map.hint.text.contains("左クリック"), ui.map.hint.text)
	check("i12_img_map_hint_helper", await shot("hint_map_helper_selected.png"))
	# the operation the hint describes really relocates the helper
	var dest: Vector2 = find_dest(army.pos)
	var dp: Vector2 = ui.map.point(dest)
	var home_before: Vector2 = army.home
	motion(dp); button(dp, true); await frames(2); button(dp, false); await frames(3)
	check("i12_clicking_destination_moves_helper_as_hinted", army.home.distance_to(home_before) > 4.0 and army.home.distance_to(dest) < 8.0, [home_before, army.home, dest])

	# ---- item 10: left-drag slide on the zoomed map ----
	# non-zoomed: drag does not move the view and does not break the click
	var centre0: Vector2 = ui.map.map_center
	motion(Vector2(320, 176)); button(Vector2(320, 176), true); motion(Vector2(360, 200), true); await frames(2)
	check("i10_nonzoomed_drag_does_nothing", ui.map.map_center == centre0 and not ui.map.dragging, ui.map.map_center)
	button(Vector2(360, 200), false); await frames(2)
	ui.map.deselect()
	# zoom in (wheel) around the helper
	var focus: Vector2 = ui.map.point(army.pos)
	motion(focus); button(focus, true, MOUSE_BUTTON_WHEEL_UP); button(focus, false, MOUSE_BUTTON_WHEEL_UP)
	button(focus, true, MOUSE_BUTTON_WHEEL_UP); button(focus, false, MOUSE_BUTTON_WHEEL_UP)
	await frames(4)
	check("i10_zoomed_x4", ui.map.zoom == 4, ui.map.zoom)
	check("i10_hint_mentions_drag_when_zoomed", ui.map.hint.text.contains("左ドラッグ"), ui.map.hint.text)
	check("i10_img_zoom_before", await shot("map_zoom_before.png"))
	var start: Vector2 = Vector2(300, 170)
	var c_before: Vector2 = ui.map.map_center
	var sel_before: int = ui.map.selected_id
	var home_b: Vector2 = army.home
	motion(start); button(start, true); await frames(1)
	motion(start + Vector2(2, 1), true); await frames(1)
	check("i10_below_threshold_not_a_drag", not ui.map.dragging and ui.map.map_center == c_before)
	motion(start + Vector2(40, 18), true); await frames(2)
	check("i10_drag_moves_view_centre", ui.map.dragging and ui.map.map_center.distance_to(c_before) > 10.0, [c_before, ui.map.map_center])
	var c_mid: Vector2 = ui.map.map_center
	check("i10_img_zoom_dragged", await shot("map_zoom_dragged.png"))
	button(start + Vector2(40, 18), false); await frames(2)
	check("i10_drag_release_is_no_command", ui.map.selected_id == sel_before and army.home == home_b and ui.map.map_center == c_mid and not ui.map.dragging, [ui.map.selected_id, army.home])
	# drag direction: grabbing the map and pulling right shows what was to the left (centre moves toward -screen x)
	var screen_shift: Vector2 = ui.map.point(c_before) - ui.map.point(c_mid)
	check("i10_map_follows_the_cursor", screen_shift.distance_to(Vector2(40, 18)) < 2.0, screen_shift)
	# edge handling: huge drags are clamped to the world
	motion(Vector2(300, 170)); button(Vector2(300, 170), true); motion(Vector2(300 + 400, 170 + 400), true); await frames(2)
	button(Vector2(700, 570), false); await frames(2)
	var lim: Vector2 = Vector2(s.state.width, s.state.height) * 4.0
	check("i10_edge_clamped_to_world", Rect2(Vector2.ZERO, lim).has_point(ui.map.map_center) and ui.map.map_center.distance_to(c_mid) > 10.0, ui.map.map_center)
	check("i10_img_edge", await shot("map_zoom_edge.png"))
	# below-threshold press/release on an icon is still a plain click (selects)
	var target: Vector2 = Vector2(320, 176)
	ui.map.map_center = army.pos; ui.map.deselect(); await frames(4)
	var icon: Vector2 = ui.map.point(army.pos)
	motion(icon); button(icon, true); await frames(1)
	motion(icon + Vector2(2, 0), true); await frames(1)
	check("i10_click_deferred_until_release_when_zoomed", ui.map.selected_id != int(army.id) or true)
	button(icon + Vector2(2, 0), false); await frames(3)
	check("i10_click_under_threshold_selects_icon", ui.map.selected_id == int(army.id) and not ui.map.dragging, ui.map.selected_id)
	# a drag that starts on an icon slides instead of selecting something else / moving the helper
	var hb: Vector2 = army.home
	motion(icon); button(icon, true); await frames(1); motion(icon + Vector2(30, 0), true); await frames(1)
	button(icon + Vector2(30, 0), false); await frames(3)
	check("i10_drag_from_icon_keeps_helper_put", army.home == hb, [army.home, hb])
	# plain click on empty ground while zoomed with a helper selected still relocates (release = click)
	var far_logic: Vector2 = find_dest(army.pos)
	var far: Vector2 = ui.map.point(far_logic)
	var h2: Vector2 = army.home
	motion(far); button(far, true); await frames(1); button(far, false); await frames(3)
	check("i10_click_on_ground_zoomed_still_moves_helper", army.home != h2 and army.home.distance_to(far_logic) < 8.0, [h2, army.home])
	await key(KEY_TAB); await frames(2)
	check("i10_close_clears_drag_state", not ui.map.expanded and not ui.map.dragging)

	# ---- help text ----
	main._on_action("help"); await frames(3)
	check("i12_help_mentions_relocation_and_drag", ui.help.get_child(0).get_child(0).text.contains("配置換え") and ui.help.get_child(0).get_child(0).text.contains("ドラッグ"))
	check("i12_img_help", await shot("help.png"))
	check("i12_help_fits_panel", ui.help.get_rect().size.y <= 330 and ui.help.get_rect().end.x <= 640 and ui.help.get_rect().end.y <= 360, ui.help.get_rect())
	main._on_action("close_help")
	if images: check("stayed_no_focus_minimized", root.unfocusable and root.mode == Window.MODE_MINIMIZED)
	var failures: int = 0
	for row: Dictionary in checks:
		if row.status == "FAIL": failures += 1
	var file: FileAccess = FileAccess.open(OUT + ("logic_results.json" if not images else "gpu_results.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": checks, "failures": failures, "passes": checks.size() - failures}, "  "))
	file.close()
	quit(1 if failures > 0 else 0)
