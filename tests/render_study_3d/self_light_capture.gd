extends SceneTree
## Limited UI/angle/caster proof, then one 4s/48-sample orbit. No OS input.
const Scene: PackedScene = preload("res://scenes/light_lab.tscn")
const OUT: String = "res://evidence/render-study-3d/light-controls/self/"
var lab: Node
var results: Array[Dictionary] = []
var snapshots: Array[Dictionary] = []
var failures: int = 0

func _initialize() -> void:
	root.unfocusable = true
	create_timer(45.0).timeout.connect(func() -> void: quit(99))
	run.call_deferred()

func check(ok: bool, id: String, detail: String = "") -> void:
	results.append({"id":id,"status":"PASS" if ok else "FAIL","detail":detail})
	if not ok:
		failures += 1
	print("%s %s %s" % ["PASS" if ok else "FAIL",id,detail])

func capture(label_: String, representative: bool = false) -> Image:
	await lab.study.wait_render()
	var world: Image = lab.study.render_view.get_texture().get_image()
	var ui: Image = root.get_texture().get_image()
	ui.save_png(OUT+label_+"_ui_640.png")
	if representative:
		world.save_png(OUT+label_+"_world_640.png")
		var gpu3: Image = lab.study.doubled_view.get_texture().get_image()
		gpu3.save_png(OUT+label_+"_world_1920.png")
		var expected: Image = world.duplicate()
		expected.resize(1920,1080,Image.INTERPOLATE_NEAREST)
		check(gpu3.get_data() == expected.get_data(),"world.GPU_exact_3x")
		var ui3: Image = ui.duplicate()
		ui3.resize(1920,1080,Image.INTERPOLATE_NEAREST)
		ui3.save_png(OUT+label_+"_ui_1920.png")
		check(ui.get_size() == Vector2i(640,360),"UI.GPU_source_size","UI 1920 PNG is a nearest3x export from actual GPU root640")
	var snapshot: Dictionary = lab.light_snapshot()
	snapshot["sample"] = label_
	snapshots.append(snapshot)
	return world

func different_pixels(a: Image, b: Image) -> int:
	var count: int = 0
	for y: int in a.get_height():
		for x: int in a.get_width():
			if a.get_pixel(x,y) != b.get_pixel(x,y):
				count += 1
	return count

func run() -> void:
	lab = Scene.instantiate()
	lab.automatic = false
	root.add_child(lab)
	lab.orbit_check.button_pressed = false
	lab.apply_pose(0,false,lab.HOME)
	var gpu: bool = DisplayServer.get_name() != "headless" and not RenderingServer.get_video_adapter_name().is_empty()
	if not gpu:
		print("GPU NOT_RUN: structural load only")
		quit(2)
		return
	await capture("default",true)
	print("FIRST_IMAGE " + ProjectSettings.globalize_path(OUT+"default_ui_1920.png"))
	# UI-driven arbitrary fractional angles, not just presets.
	lab.point_check.button_pressed = false
	lab.azimuth_spin.value = 135.7
	lab.elevation_slider.value = 25.4
	check(absf(lab.azimuth_slider.value-135.7)<0.01 and absf(lab.elevation_spin.value-25.4)<0.01,"UI.slider_spin_sync")
	var sun_a: Image = await capture("sun_135_25")
	lab.azimuth_slider.value = 315.2
	lab.elevation_spin.value = 61.2
	var sun_b: Image = await capture("sun_315_61")
	check(different_pixels(sun_a,sun_b)>1000,"sun.representative_GPU_changes")
	lab.elevation_spin.value = 90.0
	check(lab.study.sun.global_basis.is_finite() and lab.shadow_board.global_basis.is_finite() and lab.study.sun.visible,"sun.zenith_finite")
	await capture("sun_zenith")
	lab.elevation_spin.value = -90.0
	check(lab.study.sun.global_basis.is_finite() and lab.shadow_board.global_basis.is_finite() and not lab.study.sun.visible and lab.sun_status.text.contains("直射OFF"),"sun.nadir_finite_direct_OFF")
	await capture("sun_below_horizon")
	lab.sun_check.button_pressed = false
	lab.point_check.button_pressed = true
	lab.orbit_spin.value = 45.0
	var before: float = lab.orbit_angle
	lab._process(0.1)
	check(is_equal_approx(lab.orbit_angle,before) and absf(lab.orbit_slider.value-45.0)<0.01,"orbit.pause_manual_position")
	var point_a: Image = await capture("point_only_45",true)
	# Both card types still exist. Only caster masks separate them.
	lab.shadow_board.visible = false
	var wrong_off: Image = await capture("point_only_wrong_sun_board_OFF")
	check(point_a.get_data()==wrong_off.get_data(),"mask.point_ignores_sun_board","world GPU bytes unchanged when sun-only card is removed")
	lab.shadow_board.visible = true
	lab.point_board.visible = false
	var own_off: Image = await capture("point_only_own_board_OFF")
	var shadow_pixels: int = different_pixels(point_a,own_off)
	check(shadow_pixels>10,"mask.point_own_board_has_shadow","own point-card OFF changes %d GPU pixels" % shadow_pixels)
	lab.point_board.visible = true
	lab.orbit_slider.value = 225.0
	var point_b: Image = await capture("point_only_225")
	lab.point_check.button_pressed = false
	var point_off: Image = await capture("point_OFF")
	check(different_pixels(point_a,point_b)>1000 and different_pixels(point_b,point_off)>1000,"point.positions_and_OFF_change_GPU")
	lab.point_check.button_pressed = true
	lab.sun_check.button_pressed = true
	lab.set_sun_angles(320.1944,52.0)
	lab.orbit_check.button_pressed = true
	before = lab.orbit_angle
	lab._process(0.1)
	check(lab.orbit_angle != before,"orbit.resume_advances")
	lab.orbit_check.button_pressed = false
	for i: int in 48:
		var time_: float = float(i)/12.0
		lab.set_orbit_angle(45.0+90.0*time_)
		lab.pose_at_time(time_)
		await capture("frames/orbit_%03d" % i)
	var all_sync: bool = true
	for snapshot: Dictionary in snapshots:
		all_sync = all_sync and snapshot["texture_match"] and snapshot["flip_match"] and snapshot["foot_match"] and snapshot["point_texture_match"] and snapshot["point_flip_match"] and snapshot["point_foot_match"] and snapshot["sun_basis_finite"] and snapshot["point_basis_finite"]
	check(all_sync,"sync.both_lights_all_samples","%d sampled states" % snapshots.size())
	check(lab.display_sprite.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and lab.point_marker.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,"display_marker_do_not_cast")
	var file: FileAccess = FileAccess.open(OUT+"snapshots.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(snapshots,"\t"))
	file.close()
	file = FileAccess.open(OUT+"checks.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":results,"failures":failures,"device":RenderingServer.get_video_adapter_name(),"sun_caster_mask":lab.study.sun.shadow_caster_mask,"point_caster_mask":lab.point_light.shadow_caster_mask,"point_shadow_pixels":shadow_pixels,"native":"NOT_RUN","physical_input":"NOT_RUN","video":"48 GPU PNGs, 12fps presentation, not measured runtime FPS"},"\t"))
	file.close()
	print("LIGHT_DONE failures=%d" % failures)
	quit(0 if failures==0 else 1)
