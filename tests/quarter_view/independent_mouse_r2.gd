extends SceneTree
## r2 restricted GPU recheck. Preserve the r1 suite and its failure evidence.
const OUT: String = "res://evidence/quarter-view/independent/"
var lab: Node2D
var checks: Array[Dictionary] = []
var failures: int = 0

func _initialize() -> void:
	root.unfocusable = true
	run.call_deferred()

func check(id: String, ok: bool, detail: String) -> void:
	checks.append({"id":id,"status":"PASS" if ok else "FAIL","detail":detail})
	print("%s %s %s" % ["PASS" if ok else "FAIL",id,detail])
	if not ok:
		failures += 1

func capture(name_: String) -> Image:
	for i: int in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	image.save_png(OUT+name_+".png")
	return image

func run() -> void:
	lab = load("res://scenes/quarter_view_lab.tscn").instantiate()
	root.add_child(lab)
	lab.auto_input = false
	lab.set_physics_process(false)
	lab.camera_follow = false
	await process_frame
	lab.camera.position = Vector2(70,365)
	lab.present()
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.position = Vector2(494,413)
	event.global_position = event.position
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	lab._physics_process(0.0)
	check("r2_engine_mouse_known_ground", lab.mouse_screen_position==Vector2(494,413) and lab.marker_logical.distance_to(Vector2(550,466))<0.01 and lab.marker_cell==Vector2i(137,116),"stored=%s logical=%s cell=%s" % [lab.mouse_screen_position,lab.marker_logical,lab.marker_cell])
	await capture("r2_mouse_known_ground_960")
	# No new mouse event. New canvas origin=(380,-115); screen(494,413)
	# means projected ground(114,528), hence logical(585,471), cell(146,117).
	lab.camera.position = Vector2(100,385)
	lab._physics_process(0.0)
	check("r2_stationary_mouse_camera_reprojection",lab.mouse_screen_position==Vector2(494,413) and lab.marker_logical.distance_to(Vector2(585,471))<0.01 and lab.marker_cell==Vector2i(146,117),"stored=%s logical=%s cell=%s" % [lab.mouse_screen_position,lab.marker_logical,lab.marker_cell])
	var marked: Image = await capture("r2_camera_reprojected_marker_960")
	lab.marker.visible = false
	var ground: Image = await capture("r2_marker_hidden_reference_960")
	# Cell centre: logical(586,470) -> projected(116,528) -> screen(496,413).
	# Its 8x4 bounding box has 16 filled diamond pixels at this exact grid phase.
	var center: Color = marked.get_pixel(496,413)
	var changed: int = 0
	for y: int in range(411,415):
		for x: int in range(492,500):
			if marked.get_pixel(x,y)!=ground.get_pixel(x,y):
				changed += 1
	check("r2_gpu_marker_expected_cell",marked.get_size()==Vector2i(960,540) and center.r>0.8 and center.g>0.65 and center.b<0.55 and marked.get_pixel(496,413)!=ground.get_pixel(496,413) and changed==16,"center=%s changed diamond pixels=%d expected=16" % [center,changed])
	checks.append({"id":"physical_OS_mouse","status":"NOT_RUN","detail":"No OS mouse movement or focus operation; user manual check"})
	var output: FileAccess = FileAccess.open(OUT+"mouse-r2-results.json",FileAccess.WRITE)
	output.store_string(JSON.stringify({"checks":checks,"failures":failures,"engine":Engine.get_version_info(),"renderer":RenderingServer.get_current_rendering_method(),"revision":"source-manifest-r2.json"},"\t"))
	print("INDEPENDENT_MOUSE_R2_DONE failures=%d" % failures)
	quit(1 if failures else 0)
