extends SceneTree
const Scene: PackedScene = preload("res://scenes/greening_map.tscn")
const Session: GDScript = preload("res://scripts/greening_map/session.gd")
const OUT: String = "res://evidence/wall-clip/self/"
var lab: Node
var rows: Array[Dictionary] = []
var checks: Array[Dictionary] = []
var failures: int = 0

func _initialize() -> void:
	root.unfocusable = true
	create_timer(70).timeout.connect(func() -> void: quit(99))
	run.call_deferred()

func run() -> void:
	quit(2)

func setup_lab() -> bool:
	lab = Scene.instantiate()
	lab.automatic = false
	root.add_child(lab)
	lab.session.paused = true
	return DisplayServer.get_name()!="headless" and not RenderingServer.get_video_adapter_name().is_empty()

func check(ok: bool, id: String, detail: String = "") -> void:
	checks.append({"id":id,"status":"PASS" if ok else "FAIL","detail":detail})
	if not ok:
		failures += 1
	print(checks[-1])

func key(code: int, pressed: bool) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	await process_frame

func press_wall(start: Vector2, codes: Array[int]) -> void:
	lab.session.position = Session.to_logic(start)
	for code: int in codes:
		await key(code,true)
	for i: int in 3:
		lab.step(0.5) # 1.5s deliberate pressure, same production input path.
	for code: int in codes:
		await key(code,false)
	lab.update_actor(Vector2.ZERO)

func geometry_row(label_: String) -> Dictionary:
	var sprite: Sprite3D = lab.actor.display_sprite
	var half_width: float = 8.0*lab.actor.pixel_world
	var half_height: float = 12.0*lab.actor.pixel_world
	var corners: Array = []
	for xy: Vector2 in [Vector2(-1,-1),Vector2(1,-1),Vector2(1,1),Vector2(-1,1)]:
		var p: Vector3 = sprite.global_position+sprite.global_basis.x*half_width*xy.x+sprite.global_basis.y*half_height*xy.y
		corners.append([p.x,p.y,p.z])
	var foot: Vector3 = lab.actor.render_foot
	return {"label":label_,"logical_position":[lab.session.position.x,lab.session.position.y],"half_logic":str(Session.HALF),"render_foot":[foot.x,foot.y,foot.z],"corners":corners,"display_up":str(sprite.global_basis.y),"sync":lab.actor.sync_snapshot()}

func capture(label_: String, representative: bool = false) -> void:
	await lab.wait_render()
	var image_: Image = lab.render_view.get_texture().get_image()
	image_.save_png(OUT+label_+"_world_640.png")
	var ui: Image = root.get_texture().get_image()
	ui.resize(1920,1080,Image.INTERPOLATE_NEAREST)
	ui.save_png(OUT+label_+"_ui_1920.png")
	var center: Vector2i = Vector2i(lab.camera.unproject_position(lab.actor.render_foot).round())
	var crop: Image = image_.get_region(Rect2i(center-Vector2i(40,60),Vector2i(80,80)))
	crop.resize(480,480,Image.INTERPOLATE_NEAREST)
	crop.save_png(OUT+label_+"_closeup_6x.png")
	if representative:
		var output: Image = lab.doubled_view.get_texture().get_image()
		output.save_png(OUT+label_+"_world_1920.png")
		image_.resize(1920,1080,Image.INTERPOLATE_NEAREST)
		check(output.get_data()==image_.get_data(),"nearest3_exact")
	print("IMAGE "+ProjectSettings.globalize_path(OUT+label_+"_ui_1920.png"))

func visible_pixels() -> Dictionary:
	# Paired actual GPU frames isolate visible sprite pixels without its shadow.
	lab.actor.shadow_board.visible = false
	lab.actor.display_sprite.visible = true
	await lab.wait_render()
	var on: Image = lab.render_view.get_texture().get_image()
	lab.actor.display_sprite.visible = false
	await lab.wait_render()
	var off: Image = lab.render_view.get_texture().get_image()
	lab.actor.display_sprite.visible = true
	lab.actor.shadow_board.visible = true
	var foot: Vector2i = Vector2i(lab.camera.unproject_position(lab.actor.render_foot).round())
	var changed: int = 0
	for y: int in range(foot.y-25,foot.y+1):
		for x: int in range(foot.x-9,foot.x+9):
			if on.get_pixel(x,y)!=off.get_pixel(x,y):
				changed += 1
	var texture: Image = lab.actor.display_sprite.texture.get_image()
	var expected: int = 0
	for y: int in texture.get_height():
		for x: int in texture.get_width():
			if texture.get_pixel(x,y).a>=0.5:
				expected += 1
	return {"visible":changed,"opaque_fixture_pixels":expected}
