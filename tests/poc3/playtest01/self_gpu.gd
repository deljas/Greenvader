extends SceneTree
## POC3-PLAYTEST-01 work A, real GPU images at 640x360 (offscreen composite; window stays minimized, no focus).
const Coords: GDScript = preload("res://scripts/poc/poc_coords.gd")
const OUT: String = "res://evidence/poc3/playtest01/self/"
var main: Node
var s: RefCounted
var capture: SubViewport
var checks: Array[Dictionary] = []
const C: Vector2i = Vector2i(192, 188)

func _init() -> void: call_deferred("run")
func check(name_: String, ok: bool, detail: Variant = "") -> void:
	checks.append({"name": name_, "status": "PASS" if ok else "FAIL", "detail": detail})
	print(JSON.stringify(checks.back()))
func frames(n: int = 3) -> void:
	for i: int in n: await process_frame
func motion(at: Vector2) -> void:
	var e: InputEventMouseMotion = InputEventMouseMotion.new()
	e.position = at; e.global_position = at
	root.push_input(e, true)
func at_cell(cell: Vector2i) -> Vector2:
	return main.world.camera.unproject_position(Coords.ground3(Coords.logic_to_ground(Coords.cell_center_logic(cell))))
func shot(file: String) -> bool:
	await frames(); RenderingServer.force_draw(false)
	return capture.get_texture().get_image().save_png(OUT + file) == OK
func shot_zoom(file: String, rect: Rect2i, factor: int) -> bool:
	await frames(); RenderingServer.force_draw(false)
	var image: Image = capture.get_texture().get_image().get_region(rect)
	image.resize(rect.size.x * factor, rect.size.y * factor, Image.INTERPOLATE_NEAREST)
	return image.save_png(OUT + file) == OK
func prep() -> void:
	for y: int in range(183, 193):
		for x: int in range(180, 205): s.state.set_stage(s.state.index_of(x, y), WorldState.STAGE_EMPTY)
	for y: int in range(185, 192):
		for x: int in range(189, 196): s.state.set_stage(s.state.index_of(x, y), WorldState.STAGE_SEED)
	s.position = Coords.cell_center_logic(Vector2i(186, 188))
	s.water = 100.0
	main.world.sync(0.0)
func aim_at(cell: Vector2i) -> void:
	motion(at_cell(cell)); await frames(1); main.tick(0.0)

func run() -> void:
	var safe: bool = root.unfocusable and root.mode == Window.MODE_MINIMIZED and ProjectSettings.get_setting("display/window/size/no_focus", false)
	check("startup_no_focus_minimized", safe)
	if not safe or not OS.get_user_data_dir().replace("\\", "/").contains("evidence/poc3/playtest01/self/profile/"):
		quit(1); return
	change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene"))
	await frames()
	main = current_scene
	main.auto_process = false
	main._audio_changed(true, 0.0)
	main._on_action("new")
	root.notify_mouse_entered()
	s = main.session
	s.enemies.clear(); s.nests.clear(); s.fossils.clear()
	capture = SubViewport.new()
	capture.size = Vector2i(640, 360); capture.disable_3d = true
	capture.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(capture)
	main.view_rect.reparent(capture); main.ui.reparent(capture)
	prep()
	# 1/3: preview, 7x7 with water for 20 cells (shortage) and a droplet HUD.
	s.sow_width = 7; s.water = 20.0
	await aim_at(C)
	var plan: Dictionary = main.world.water_plan
	var shown: int = 0
	for n: MeshInstance3D in main.world.water_cells:
		if n.visible: shown += 1
	check("preview_7_short_water", plan.cost == 20 and plan.affordable.size() == 20 and plan.unaffordable.size() == 29 and shown == 49 and main.ui.water_notice.visible and main.ui.water_notice.text.begins_with("20") and main.ui.water_notice.text.contains("水不足"), main.ui.water_notice.text)
	check("img_preview_short", await shot("water_preview_7_short.png"))
	s.water = 100.0; s.sow_width = 3
	main.tick(0.0)
	check("preview_3_full", main.world.water_plan.cost == 9 and main.ui.water_notice.text.contains("3×3"))
	check("img_preview_3", await shot("water_preview_3.png"))
	# No-effect aim: bare ground far from the grown block.
	await aim_at(Vector2i(183, 188))
	check("preview_no_effect", main.world.water_plan.no_effect and main.ui.water_notice.text.contains("対象なし"))
	check("img_preview_no_effect", await shot("water_preview_no_effect.png"))
	# Click on no-effect: no animation, no spend, reason shown.
	var before: float = s.water
	main._water_wait = 0.0
	main._water()
	check("no_effect_click_no_anim_no_spend", s.water == before and main.world.fire_kind == &"" and not main._water_pending and main.ui.notice.text.contains("必要がある") or main.ui.notice.text.contains("効果"), main.ui.notice.text)
	# Real click on a valid area: water is spent at the 400ms release, animation runs 800ms.
	s.sow_width = 3
	await aim_at(C)
	main._water_wait = 0.0
	main._water()
	check("repeat_wait_set_to_animation_length", is_equal_approx(main._water_wait, 0.8))
	var frames_seen: Array[int] = []
	var spent_at: float = -1.0
	var t: float = 0.0
	var captured_mid: bool = false
	var captured_release: bool = false
	while t < 0.86:
		main.tick(0.02); t += 0.02
		if main.world.fire_kind == &"water" and (frames_seen.is_empty() or frames_seen[-1] != main.world.fire_frame): frames_seen.append(main.world.fire_frame)
		if spent_at < 0.0 and s.water < 100.0: spent_at = t
		if not captured_mid and t >= 0.30:
			captured_mid = true
			check("img_anim_frame3_forming", await shot("water_anim_frame3.png"))
		if not captured_release and t >= 0.46:
			captured_release = true
			check("img_anim_frame4_release", await shot("water_anim_frame4_release.png"))
	check("anim_plays_all_7_frames_to_800ms", frames_seen == [0, 1, 2, 3, 4, 5, 6] and main.world.fire_kind == &"", frames_seen)
	check("water_spent_at_release_400ms", spent_at >= 0.38 and spent_at <= 0.44 and is_equal_approx(s.water, 91.0), {"spent_at": spent_at, "water": s.water})
	main.tick(0.0)
	check("img_wet_3x3", await shot("water_wet_3x3.png"))
	# Larger wet area for visibility of the new watered look, then dry-vs-wet in one frame.
	s.sow_width = 7; s.water = 100.0; s.position = Coords.cell_center_logic(Vector2i(186, 188))
	s.water_at(Coords.cell_center_logic(Vector2i(194, 188)))
	main.tick(0.0)
	await aim_at(Vector2i(183, 186))
	check("img_wet_area", await shot("water_wet_area.png"))
	check("img_wet_area_zoom", await shot_zoom("water_wet_area_zoom4x.png", Rect2i(290, 170, 130, 80), 4))
	check("wet_layer_counts", main.world.ground.visible_count("wet") > 9, main.world.ground.visible_count("wet"))
	# Crop wet patch.
	s.unlocked["clover"] = true
	s.state.set_stage(s.state.index_of(188, 190), WorldState.STAGE_MATURE)
	s.seeds = 100
	var placed: Dictionary = s.place_plant("clover", Vector2i(188, 190))
	s.sow_width = 1
	s.water_at(Coords.cell_center_logic(Vector2i(188, 190)))
	main.tick(0.0)
	check("crop_watered_patch_shown", bool(placed.ok) and main.world.ground.shown_wet[s.state.index_of(188, 190)] == 1)
	# Sprinkler ring 12m (placement preview).
	s.unlocked["sprinkler"] = true
	s.favorites[1] = "sprinkler"
	main.ui.select_slot(1)
	await aim_at(Vector2i(190, 188))
	check("sprinkler_ring_scale_2", main.world.helper_effects.ring.visible and is_equal_approx(main.world.helper_effects.ring.scale.x, 2.0))
	check("img_sprinkler_ring", await shot("sprinkler_ring_12m.png"))
	main.ui.clear_selection()
	main.tick(0.0)
	check("integer_nearest_rendering", main.render_view.size == Vector2i(640, 360) and main.view_rect.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST and main.render_view.msaa_3d == Viewport.MSAA_DISABLED)
	check("stayed_no_focus_minimized", root.unfocusable and root.mode == Window.MODE_MINIMIZED)
	var failures: int = 0
	for row: Dictionary in checks:
		if row.status == "FAIL": failures += 1
	var file: FileAccess = FileAccess.open(OUT + "gpu_results.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": checks, "failures": failures}, "  "))
	file.close()
	s.close()
	quit(1 if failures > 0 else 0)
