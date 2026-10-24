extends SceneTree
## Restricted recheck for TECH-QV-01 mouse event retention. No OS input.
const OUT: String = "res://evidence/quarter-view/self/"
var lab: Node2D
var checks: Array[Dictionary] = []
var failures: int = 0

func _initialize() -> void:
	root.unfocusable = true
	run.call_deferred()

func check(name_: String, ok: bool) -> void:
	checks.append({"name": name_, "status": "PASS" if ok else "FAIL", "logical": str(lab.marker_logical), "cell": str(lab.marker_cell), "stored_screen": str(lab.mouse_screen_position)})
	print("%s %s logical=%s cell=%s screen=%s" % ["PASS" if ok else "FAIL", name_, lab.marker_logical, lab.marker_cell, lab.mouse_screen_position])
	if not ok:
		failures += 1

func run() -> void:
	lab = load("res://scenes/quarter_view_lab.tscn").instantiate()
	root.add_child(lab)
	lab.set_physics_process(false)
	lab.auto_input = false
	lab.camera_follow = false
	await process_frame
	lab.camera.position = Vector2(70, 365)
	lab.present()
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.position = Vector2(494, 413)
	event.global_position = event.position
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	lab._physics_process(0.0)
	check("engine_mouse_event_known_ground", lab.marker_logical.distance_to(Vector2(550, 466)) < 0.01 and lab.marker_cell == Vector2i(137, 116))
	# With no new mouse event, a camera change must reproject the retained point.
	lab.camera.position = Vector2(40, 344)
	lab._physics_process(0.0)
	check("stationary_mouse_camera_reprojection", lab.marker_logical.distance_to(Vector2(514, 460)) < 0.01 and lab.mouse_screen_position == Vector2(494, 413))
	lab.camera.position = Vector2(70, 365)
	lab.present()
	event = InputEventMouseMotion.new()
	event.position = Vector2(520, 400)
	event.global_position = event.position
	root.notify_mouse_entered()
	root.push_input(event, true)
	lab._physics_process(0.0)
	check("viewport_local_mouse_event", lab.marker_logical.distance_to(Vector2(550, 440)) < 0.01 and lab.marker_cell == Vector2i(137, 110))
	var file: FileAccess = FileAccess.open(OUT + "mouse-r2-results.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": checks, "failures": failures, "physical_OS_input": "NOT_RUN", "GPU_r2": "NOT_RUN - independent limited recheck follows"}, "\t"))
	print("SELF_MOUSE_R2_DONE failures=%d" % failures)
	quit(1 if failures else 0)
