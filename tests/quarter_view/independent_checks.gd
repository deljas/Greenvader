extends SceneTree
## Independent acceptance checks. Expectations come from TECH-QV-01 geometry.
## Only engine events; unfocusable GPU window; native capture is read-only.
const OUT: String = "res://evidence/quarter-view/independent/"
const QuarterMap: GDScript = preload("res://scripts/quarter_view_lab/projection.gd")
var lab: Node2D
var results: Array[Dictionary] = []
var bad: int = 0

func _initialize() -> void:
	root.unfocusable = true
	run.call_deferred()

func check(id: String, ok: bool, detail: String = "") -> void:
	results.append({"id": id, "status": "PASS" if ok else "FAIL", "detail": detail})
	print("%s %s %s" % ["PASS" if ok else "FAIL", id, detail])
	if not ok:
		bad += 1

func frames(n: int = 3) -> void:
	for i: int in n:
		await process_frame

func key(code: Key, down: bool) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = down
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func capture(label: String) -> Image:
	await frames()
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	image.save_png(OUT + label + ".png")
	return image

func flower_pixels(image: Image) -> int:
	# Compare actual opaque art pixels, so an incorrect depth relationship fails.
	var art: Image = lab.flower.texture.get_image()
	var origin: Vector2i = Vector2i(root.get_canvas_transform() * (lab.flower.position + lab.flower.offset))
	var matching: int = 0
	for y: int in 16:
		for x: int in 16:
			var pixel: Color = art.get_pixel(x, y)
			if pixel.a > 0.99 and image.get_pixel(origin.x + x, origin.y + y).is_equal_approx(pixel):
				matching += 1
	return matching

func native_compare(reference: Image) -> void:
	var native_path: String = ProjectSettings.globalize_path(OUT + "native_1080.png")
	var handle: int = DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE, 0)
	var helper: String = ProjectSettings.globalize_path("res://tests/independent/p0_verify_printwindow.ps1")
	var pid: int = OS.create_process("powershell", ["-NoProfile", "-WindowStyle", "Hidden", "-ExecutionPolicy", "Bypass", "-File", helper, "-Hwnd", str(handle), "-Out", native_path])
	var count: int = 0
	while pid > 0 and OS.is_process_running(pid) and count < 600:
		await process_frame
		count += 1
	if pid > 0 and OS.is_process_running(pid):
		OS.kill(pid)
	var native: Image = Image.load_from_file(native_path) if FileAccess.file_exists(native_path) else null
	if native == null:
		results.append({"id": "native_2x", "status": "NOT_RUN", "detail": "No native readback"})
		return
	check("native_dimensions", native.get_size() == Vector2i(1920,1080) and reference.get_size() == Vector2i(960,540), str([native.get_size(),reference.get_size()]))
	if native.get_size() != Vector2i(1920,1080):
		return
	var mismatches: int = 0
	var nonuniform: int = 0
	for y: int in 540:
		for x: int in 960:
			var a: Color = native.get_pixel(2*x,2*y)
			if a != reference.get_pixel(x,y):
				mismatches += 1
			for dy: int in 2:
				for dx: int in 2:
					if native.get_pixel(2*x+dx,2*y+dy) != a:
						nonuniform += 1
	check("native_2x", mismatches == 0 and nonuniform == 0, "518400 blocks: original mismatches=%d nonuniform pixels=%d" % [mismatches,nonuniform])

func run() -> void:
	if OS.get_cmdline_user_args().has("--mouse-only"):
		lab = load("res://scenes/quarter_view_lab.tscn").instantiate()
		root.add_child(lab)
		lab.set_physics_process(false)
		lab.auto_input = false
		lab.camera_follow = false
		await frames()
		lab.camera.position = Vector2(70,365)
		lab.present()
		var e: InputEventMouseMotion = InputEventMouseMotion.new()
		e.position = Vector2(494,413)
		e.global_position = e.position
		root.notify_mouse_entered()
		root.push_input(e,true)
		print("MOUSE_DIAGNOSTIC viewport=%s event=%s canvas=%s" % [root.get_mouse_position(),e.position,root.get_canvas_transform()])
		lab._physics_process(0.0)
		check("mouse_viewport_local_event",lab.marker_logical.distance_to(Vector2(550,466))<0.01,str([lab.marker_logical,lab.marker_cell]))
		# Direct public conversion is independently checked against the same specified point.
		lab.set_mouse_screen(Vector2(494,413))
		check("mouse_known_ground_and_cell",lab.marker_logical.distance_to(Vector2(550,466))<0.01 and lab.marker_cell==Vector2i(137,116),str([lab.marker_logical,lab.marker_cell]))
		lab.present()
		await capture("mouse_marker_960")
	elif OS.get_cmdline_user_args().has("--smoke"):
		var main: Node = load("res://scenes/main.tscn").instantiate()
		root.add_child(main)
		await frames(8)
		var image: Image = await capture("normal_game_smoke_640")
		check("normal_game_smoke", main.player != null and main.grid.width == 512 and image.get_size() == Vector2i(640,360), "grid=%s viewport=%s" % [main.grid.width,image.get_size()])
	else:
		await run_lab()
	results.append({"id":"physical_OS_input", "status":"NOT_RUN", "detail":"User manual check; no OS input or cursor movement"})
	var result_name: String = "mouse-results.json" if OS.get_cmdline_user_args().has("--mouse-only") else ("smoke-results.json" if OS.get_cmdline_user_args().has("--smoke") else "results.json")
	var file: FileAccess = FileAccess.open(OUT + result_name, FileAccess.WRITE)
	file.store_string(JSON.stringify({"engine": Engine.get_version_info(),"renderer":RenderingServer.get_current_rendering_method(),"checks":results,"failures":bad}, "\t"))
	print("INDEPENDENT_DONE failures=%d" % bad)
	quit(1 if bad else 0)

func run_lab() -> void:
	lab = load("res://scenes/quarter_view_lab.tscn").instantiate()
	root.add_child(lab)
	lab.auto_input = false
	lab.set_physics_process(false)
	await frames()
	check("projection_basis", QuarterMap.project(Vector2.ZERO) == Vector2.ZERO and QuarterMap.project(Vector2(4,0)) == Vector2(4,2) and QuarterMap.project(Vector2(0,4)) == Vector2(-4,2) and QuarterMap.unproject(Vector2(-8,12)) == Vector2(8,16))
	check("grid_footprints", lab.grid.target_count == 35496 and not lab.grid.is_walkable(76,68) and lab.grid.is_walkable(75,68) and not lab.grid.is_walkable(120,80), str(lab.grid.target_count))
	# Specification footprint [304,448]x[272,416]; feet extend 2 in each axis.
	var starts: Array[Vector2] = [Vector2(292,340),Vector2(460,340),Vector2(376,260),Vector2(376,428)]
	var ends: Array[Vector2] = [Vector2(302,340),Vector2(450,340),Vector2(376,270),Vector2(376,418)]
	var inputs: Array[Vector2] = [Vector2(2,1),Vector2(-2,-1),Vector2(-2,1),Vector2(2,-1)]
	var observed: Array[Vector2] = []
	var walls: bool = true
	for i: int in 4:
		lab.logical_position = starts[i]
		lab.move_screen(inputs[i],0.5)
		observed.append(lab.logical_position)
		walls = walls and lab.logical_position.distance_to(ends[i]) < 0.01
	check("wall_contact_four_faces",walls,str(observed))
	var route: Array[Vector2] = [Vector2(300,268),Vector2(452,268),Vector2(452,420),Vector2(300,420),Vector2(300,268)]
	var cursor: Vector2 = route[0]
	var circuit: bool = true
	for i: int in range(1,route.size()):
		cursor = Walker.move(lab.grid,4,cursor,route[i]-cursor,Vector2(2,2))
		circuit = circuit and cursor.distance_to(route[i]) < 0.01
	check("close_clear_circuit",circuit,str(cursor))
	lab.logical_position = Vector2(468,330)
	lab.move_screen(Vector2(2,1),0.4)
	check("low_foot_contact",lab.logical_position.distance_to(Vector2(478,330))<0.01,str(lab.logical_position))
	# Actual engine key state is read by the scene. Quarter second -> 25 screen px.
	lab.auto_input = true
	lab.logical_position = Vector2(600,560)
	key(KEY_W,true)
	lab._physics_process(0.25)
	key(KEY_W,false)
	var up: Vector2 = QuarterMap.project(lab.logical_position)-Vector2(40,580)
	lab.logical_position = Vector2(600,560)
	key(KEY_D,true)
	key(KEY_S,true)
	lab._physics_process(0.25)
	key(KEY_D,false)
	key(KEY_S,false)
	var diagonal: Vector2 = QuarterMap.project(lab.logical_position)-Vector2(40,580)
	lab.auto_input = false
	check("engine_input_direction_equal_speed",up.distance_to(Vector2(0,-25))<0.05 and absf(diagonal.length()-25)<0.05 and diagonal.x>0 and diagonal.y>0,str([up,diagonal]))
	# Freeze camera at two distinct integer translations; inject to a known cell centre.
	lab.camera_follow = false
	lab.camera.position = Vector2(70,365)
	lab.present()
	var mouse: InputEventMouseMotion = InputEventMouseMotion.new()
	# Logical (550,466) -> known projected (84,508), camera centre (70,365).
	mouse.position = Vector2(494,413)
	mouse.global_position = mouse.position
	Input.parse_input_event(mouse)
	Input.flush_buffered_events()
	lab._physics_process(0.0)
	check("mouse_camera_inverse",lab.marker_logical.distance_to(Vector2(550,466))<0.01 and lab.marker_cell==Vector2i(137,116),str([lab.marker_logical,lab.marker_cell]))
	lab.camera.position = Vector2(40,344)
	lab.present()
	var art: Image = lab.flower.texture.get_image()
	var opaque: int = 0
	for y: int in 16:
		for x: int in 16:
			if art.get_pixel(x,y).a>0.99:
				opaque += 1
	var positions: Array[Vector2] = [Vector2(480,440),Vector2(376,432),Vector2(464,344)]
	var names: Array[String] = ["front_960","left_side_front_960","right_side_front_960"]
	for i: int in positions.size():
		lab.logical_position = positions[i]
		lab.fade_enabled = false
		lab.present()
		var image: Image = await capture(names[i])
		var count: int = flower_pixels(image)
		check(names[i]+"_full_flower",count==opaque,"visible=%d expected=%d" % [count,opaque])
	lab.logical_position = Vector2(288,256)
	lab.fade_enabled = false
	lab.present()
	var hidden: Image = await capture("behind_opaque_960")
	var hidden_count: int = flower_pixels(hidden)
	lab.fade_enabled = true
	lab.present()
	var faded: Image = await capture("behind_faded_960")
	check("behind_depth_and_fade",hidden_count<opaque and lab.occluded and lab.props[0].faded and hidden.get_data()!=faded.get_data(),"opaque visible=%d/%d faded=%s" % [hidden_count,opaque,lab.props[0].faded])
	lab.camera_follow = true
	lab.logical_position = Vector2(600.125,560.25)
	lab.move_screen(Vector2(1,1),0.017)
	lab.present()
	await capture("diagonal_camera_960")
	var transform: Transform2D = root.get_canvas_transform()
	check("integer_camera_and_pixels",lab.flower.position==lab.flower.position.round() and lab.camera.position==lab.camera.position.round() and transform.origin==transform.origin.round() and lab.texture_filter==CanvasItem.TEXTURE_FILTER_NEAREST and lab.camera.zoom==Vector2.ONE,str([lab.flower.position,lab.camera.position,transform]))
	lab.logical_position = Vector2(480,440)
	lab.present()
	root.size = Vector2i(1920,1080)
	await frames(6)
	var original: Image = await capture("same_frame_original_960")
	await native_compare(original)
