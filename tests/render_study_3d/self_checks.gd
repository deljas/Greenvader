extends SceneTree
## Bounded GPU capture, no OS input or focus/foreground API. Each light once.
const Scene: PackedScene = preload("res://scenes/render_study_3d.tscn")
const OUT: String = "res://evidence/render-study-3d/self/"
var study: Node
var results: Array[Dictionary] = []
var failures: int = 0

func _initialize() -> void:
	root.unfocusable = true
	run.call_deferred()

func check(ok: bool, id: String, detail: String = "") -> void:
	results.append({"id":id,"status":"PASS" if ok else "FAIL","detail":detail})
	print("%s %s %s" % ["PASS" if ok else "FAIL",id,detail])
	if not ok:
		failures += 1

func run() -> void:
	study = Scene.instantiate()
	root.add_child(study)
	await process_frame
	check(study.render_view.size == Vector2i(960,540) and study.doubled_view.size == Vector2i(1920,1080), "viewport.sizes")
	check(study.camera.projection == Camera3D.PROJECTION_ORTHOGONAL and study.time_index == 1, "camera.default_noon_orthogonal")
	check(not study.render_view.use_taa and study.render_view.msaa_3d == Viewport.MSAA_DISABLED and study.render_view.screen_space_aa == Viewport.SCREEN_SPACE_AA_DISABLED, "output.no_temporal_or_spatial_AA")
	check(study.parts["walls"].get_child_count() > 15 and study.parts["roof"].get_child_count() > 15 and study.parts["rubble"].get_child_count() > 10, "geometry.openings_roof_rubble", "separate meshes; no source picture")
	var origin: Vector2 = study.camera.unproject_position(Vector3.ZERO)
	var x_step: Vector2 = study.camera.unproject_position(Vector3(1,0,0)) - origin
	var z_step: Vector2 = study.camera.unproject_position(Vector3(0,0,1)) - origin
	var vertical: Vector2 = study.camera.unproject_position(Vector3(0,1,0)) - origin
	check(absf(absf(x_step.y/x_step.x)-0.5) < 0.001 and absf(absf(z_step.y/z_step.x)-0.5) < 0.001 and absf(vertical.x) < 0.001, "projection.2to1_verticals", str([x_step,z_step,vertical]))
	var key: InputEventKey = InputEventKey.new()
	key.keycode = KEY_1
	key.pressed = true
	Input.parse_input_event(key)
	await process_frame
	check(study.time_index == 0, "input.engine_time_switch")
	study.set_time(1)
	var method: String = RenderingServer.get_current_rendering_method()
	var device: String = RenderingServer.get_video_adapter_name()
	var gpu: bool = method != "gl_compatibility" and DisplayServer.get_name() != "headless" and not device.is_empty()
	if gpu:
		var noon: Image
		var hashes: Array[String] = []
		for i: int in 3:
			study.set_time(i)
			var label_: String = String(study.TIMES[i]["id"])
			var captured: Dictionary = await study.save_views(OUT, label_)
			var image: Image = captured["source"]
			var doubled: Image = captured["doubled"]
			check(captured["ok"] and image.get_size() == Vector2i(960,540) and doubled.get_size() == Vector2i(1920,1080), "GPU."+label_, device)
			var exact: Image = image.duplicate()
			exact.resize(1920,1080,Image.INTERPOLATE_NEAREST)
			check(exact.get_data() == doubled.get_data(), "nearest2x."+label_, "GPU 1920 output equals duplicated 960 pixels")
			hashes.append(image.get_data().hex_encode().sha256_text())
			if i == 1:
				noon = image
		check(hashes[0] != hashes[1] and hashes[1] != hashes[2] and hashes[0] != hashes[2], "GPU.light_variants_differ")
		study.set_time(1)
		study.sun.shadow_enabled = false
		await study.wait_render()
		var no_shadow: Image = study.render_view.get_texture().get_image()
		no_shadow.save_png(OUT + "noon_shadow_disabled_reference_960.png")
		var changed: int = 0
		for y: int in 540:
			for x: int in 960:
				if no_shadow.get_pixel(x,y) != noon.get_pixel(x,y):
					changed += 1
		check(changed > 500, "GPU.real_shadow_toggle", "%d pixels change when only real-time shadow is disabled" % changed)
		study.sun.shadow_enabled = true
		# One short camera translation sequence, fixed noon, five sampled frames.
		for i: int in 5:
			study.camera.position = study.CAMERA_HOME + Vector3(0.035 * i, 0, 0.025 * i)
			await study.wait_render()
			study.render_view.get_texture().get_image().save_png(OUT + "camera_noon_%02d_960.png" % i)
		check(study.camera.position != study.CAMERA_HOME, "camera.short_sequence_saved", "five GPU frames; visual stability assessed separately")
		study.camera.position = study.CAMERA_HOME
	else:
		results.append({"id":"GPU.images_and_shadows","status":"NOT_RUN","detail":"Headless dummy logic pass only"})
	results.append({"id":"native.initial_focus_and_display","status":"NOT_RUN","detail":"Hidden process + root.unfocusable; initial focus invariance and actual native presentation not measured"})
	results.append({"id":"physical.OS_input","status":"NOT_RUN","detail":"No OS input, cursor move or foreground API"})
	var file: FileAccess = FileAccess.open(OUT + ("gpu-results.json" if gpu else "logic-results.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":results,"failures":failures,"renderer":method,"device":device,"engine":Engine.get_version_info(),"sun_settings":study.TIMES},"\t"))
	file.close()
	print("SELF_DONE failures=%d renderer=%s device=%s" % [failures,method,device])
	quit(1 if failures else 0)
