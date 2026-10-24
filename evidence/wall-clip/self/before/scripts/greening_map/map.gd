extends Node
const Session: GDScript = preload("res://scripts/greening_map/session.gd")
const Ground: GDScript = preload("res://scripts/greening_map/ground_view.gd")
const Actor: GDScript = preload("res://scripts/greening_map/actor.gd")
const Definitions: GDScript = preload("res://scripts/vegetation_lab/building_defs.gd")
const Buildings: GDScript = preload("res://scripts/vegetation_lab/building_geometry.gd")
const Geometry: GDScript = preload("res://scripts/render_study_3d/ruin_geometry.gd")
const Water: GDScript = preload("res://scripts/greening_map/water_surface.gd")
var water_surface: Node
var session: RefCounted = Session.new()
var render_view: SubViewport
var doubled_view: SubViewport
var world: Node3D
var camera: Camera3D
var sun: DirectionalLight3D
var ground_view: Node3D
var actor: Node3D
var keys: Dictionary = {}
var automatic: bool = true
var animation_time: float = 0.0
var refresh_time: float = 0.0
var facing_left: bool = false
var blockers: Array[AABB] = []
var azimuth_slider: HSlider
var azimuth_number: SpinBox
var multiplier_select: OptionButton
var pause_check: CheckBox
var refill_button: Button
var hud: Label
var feedback: Label
var marker: MeshInstance3D
var marker_time: float = 0

func _ready() -> void:
	var window: Window = get_window()
	window.title = "グリーンベーダー｜歩行・地面緑化の小マップ試作"
	window.content_scale_size = Vector2i(640,360)
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	window.content_scale_stretch = Window.CONTENT_SCALE_STRETCH_INTEGER
	window.min_size = Vector2i(640,360)
	window.size = Vector2i(1920,1080)
	render_view = SubViewport.new()
	render_view.size = Vector2i(640,360)
	render_view.own_world_3d = true
	render_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	render_view.msaa_3d = Viewport.MSAA_DISABLED
	render_view.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	render_view.use_taa = false
	render_view.use_debanding = false
	add_child(render_view)
	world = Node3D.new()
	render_view.add_child(world)
	_environment()
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.size = 18.5
	camera.far = 100
	world.add_child(camera)
	var target: Vector3 = Vector3(0,0.9,0)
	camera.position = target+Vector3(22,22*sqrt(2.0/3.0),22)
	camera.look_at(target)
	camera.current = true
	ground_view = Ground.new()
	world.add_child(ground_view)
	ground_view.setup(session.state)
	var definitions: Array[Dictionary] = Definitions.all()
	for item: Dictionary in Session.BUILDINGS:
		var definition: Dictionary = definitions[item["definition"]].duplicate(true)
		var building: Node3D = Node3D.new()
		var p: Vector2 = item["center"]
		building.position = Vector3(p.x,0.12,p.y)
		world.add_child(building)
		Buildings.build(building,definition)
		# Old lab paving is not the ground of this map.
		building.get_node("Paving").free()
		var rect: Rect2i = item["footprint"]
		var size_: Vector2 = Vector2(rect.size)*Session.CELL
		var base: Vector2 = Session.ORIGIN+Vector2(rect.position)*Session.CELL
		var foundation: MeshInstance3D = Geometry.box(world,"VisibleBlockedFoundation",Vector3(base.x+size_.x/2,0.04,base.y+size_.y/2),Vector3(size_.x,0.16,size_.y),Geometry.material(Color("747a70")))
		foundation.layers = 2
		blockers.append(AABB(Vector3(base.x,0,base.y),Vector3(size_.x,float(definition["size"].y)+1.1,size_.y)))
	actor = Actor.new()
	world.add_child(actor)
	actor.setup(camera,sun)
	water_surface = Water.new()
	add_child(water_surface)
	water_surface.setup(render_view,camera,world,session.state)
	water_surface.add_cosmetic_puddle(world)
	marker = Geometry.box(world,"LastLanding",Vector3.ZERO,Vector3(0.15,0.03,0.15),Geometry.material(Color("e8ce7f")))
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	marker.visible = false
	_texture(self,render_view.get_texture(),Vector2(640,360))
	doubled_view = SubViewport.new()
	doubled_view.size = Vector2i(1920,1080)
	doubled_view.disable_3d = true
	doubled_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(doubled_view)
	_texture(doubled_view,render_view.get_texture(),Vector2(1920,1080))
	_build_ui()
	update_actor(Vector2.ZERO)
	update_hud()

func _environment() -> void:
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("566359")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("b4c4cc")
	environment.ambient_light_energy = 0.42
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var env: WorldEnvironment = WorldEnvironment.new()
	env.environment = environment
	world.add_child(env)
	RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_HARD)
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 65
	sun.shadow_bias = 0.1
	sun.shadow_normal_bias = 1.0
	sun.shadow_blur = 1
	sun.light_angular_distance = 0
	sun.light_color = Color(1,0.98,0.90)
	sun.light_energy = 1.35
	world.add_child(sun)
	set_azimuth(320)

func _texture(parent: Node, texture: Texture2D, size_: Vector2) -> void:
	var rect: TextureRect = TextureRect.new()
	rect.texture = texture
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	rect.size = size_
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(rect)

func _build_ui() -> void:
	var panel: PanelContainer = PanelContainer.new()
	panel.position = Vector2(6,5)
	panel.size = Vector2(628,54)
	var theme_: Theme = Theme.new()
	var font: SystemFont = SystemFont.new()
	font.font_names = PackedStringArray(["Yu Gothic UI","Meiryo"])
	theme_.default_font = font
	theme_.default_font_size = 12
	panel.theme = theme_
	add_child(panel)
	var rows: VBoxContainer = VBoxContainer.new()
	panel.add_child(rows)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation",10)
	rows.add_child(row)
	hud = Label.new()
	hud.custom_minimum_size.x = 275
	row.add_child(hud)
	multiplier_select = OptionButton.new()
	for label_: String in ["成長 ×1","成長 ×4"]:
		multiplier_select.add_item(label_)
	multiplier_select.select(1)
	multiplier_select.item_selected.connect(func(index: int) -> void: session.multiplier = 1.0 if index==0 else 4.0)
	row.add_child(multiplier_select)
	pause_check = CheckBox.new()
	pause_check.text = "成長停止"
	pause_check.toggled.connect(func(value: bool) -> void: session.paused = value)
	row.add_child(pause_check)
	refill_button = Button.new()
	refill_button.text = "試作補給"
	refill_button.pressed.connect(func() -> void: session.refill(); update_hud())
	row.add_child(refill_button)
	var row2: HBoxContainer = HBoxContainer.new()
	row2.add_theme_constant_override("separation",8)
	rows.add_child(row2)
	var label_: Label = Label.new()
	label_.text = "太陽方位"
	row2.add_child(label_)
	azimuth_slider = HSlider.new()
	azimuth_slider.max_value = 360
	azimuth_slider.custom_minimum_size.x = 210
	azimuth_slider.value_changed.connect(set_azimuth)
	row2.add_child(azimuth_slider)
	azimuth_number = SpinBox.new()
	azimuth_number.max_value = 360
	azimuth_number.suffix = "°"
	azimuth_number.value_changed.connect(set_azimuth)
	row2.add_child(azimuth_number)
	var note: Label = Label.new()
	note.text = "固定仰角52°・見た目のみ"
	row2.add_child(note)
	set_azimuth(320)
	feedback = Label.new()
	feedback.theme = theme_
	feedback.position = Vector2(10,318)
	add_child(feedback)
	var instructions: Label = Label.new()
	instructions.theme = theme_
	instructions.position = Vector2(10,339)
	instructions.text = "WASD/矢印 移動　左:種 / 右:水（3m）　種→芽→草　｜小マップ試作"
	add_child(instructions)

func set_azimuth(value: float) -> void:
	var azimuth: float = deg_to_rad(value)
	var elevation: float = deg_to_rad(52.0)
	sun.position = Vector3(sin(azimuth)*cos(elevation),sin(elevation),cos(azimuth)*cos(elevation))*15
	sun.look_at(Vector3.ZERO)
	if azimuth_slider!=null:
		azimuth_slider.set_value_no_signal(value)
		azimuth_number.set_value_no_signal(value)
	if actor!=null:
		update_actor(Vector2.ZERO)

func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key: InputEventKey = event as InputEventKey
		var code: int = key.physical_keycode if key.physical_keycode!=0 else key.keycode
		if not key.pressed:
			keys.erase(code)
		elif not key.echo and not get_viewport().gui_get_focus_owner() is LineEdit:
			keys[code] = true

func _notification(what: int) -> void:
	if what==NOTIFICATION_APPLICATION_FOCUS_OUT:
		keys.clear()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse: InputEventMouseButton = event as InputEventMouseButton
		if mouse.pressed and mouse.button_index in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT]:
			handle_ground_press(mouse.position,mouse.button_index==MOUSE_BUTTON_RIGHT)

func screen_to_ground(screen: Vector2) -> Variant:
	if screen.x<0 or screen.x>=640 or screen.y<0 or screen.y>=360:
		return null
	var origin: Vector3 = camera.project_ray_origin(screen)
	var direction: Vector3 = camera.project_ray_normal(screen)
	var hit: Variant = Plane(Vector3.UP,0).intersects_ray(origin,direction)
	if hit==null:
		return null
	for box: AABB in blockers:
		if box.intersects_segment(origin,hit)!=null:
			return null
	return Vector2(hit.x,hit.z)

func handle_ground_press(screen: Vector2, water: bool) -> bool:
	if screen.y<=64 or screen.y>=315:
		return false
	var hit: Variant = screen_to_ground(screen)
	if hit==null:
		session.last_result = "建物の陰/画面外には散布できません"
		update_hud()
		return false
	var accepted: bool = session.scatter(hit,water)
	if accepted:
		marker.position = Vector3(hit.x,0.045,hit.y)
		marker.visible = true
		marker_time = 0.65
		ground_view.refresh(session.state)
	update_hud()
	return accepted

func _physics_process(delta: float) -> void:
	if automatic:
		step(delta)

func step(delta: float) -> void:
	var direction: Vector2 = Vector2(float(keys.has(KEY_D) or keys.has(KEY_RIGHT))-float(keys.has(KEY_A) or keys.has(KEY_LEFT)),float(keys.has(KEY_S) or keys.has(KEY_DOWN))-float(keys.has(KEY_W) or keys.has(KEY_UP)))
	var motion: Vector2 = session.walk(direction,delta)
	if motion.length_squared()>0.0000001:
		animation_time += delta
		if direction.x!=0:
			facing_left = direction.x<0
	session.advance(delta)
	marker_time -= delta
	marker.visible = marker_time>0
	refresh_time += delta
	if refresh_time>=0.15:
		refresh_time = 0
		ground_view.refresh(session.state)
	update_actor(motion)
	update_hud()

func update_actor(motion: Vector2) -> void:
	var ground: Vector2 = Session.to_ground(session.position)
	actor.pose(Vector3(ground.x,0.016,ground.y),int(animation_time*6)%4 if motion.length_squared()>0 else 1,facing_left)

func update_hud() -> void:
	if hud!=null:
		hud.text = "緑化 %d%%　種 %d　水 %.0f　 %.0f秒" % [session.state.greening_percent_floor(),session.play.seeds,session.play.water,session.clock.elapsed]
		feedback.text = session.last_result

func wait_render() -> void:
	for i: int in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw

func _exit_tree() -> void:
	session.close()
