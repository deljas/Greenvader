extends Node
const Definitions: GDScript = preload("res://scripts/vegetation_lab/building_defs.gd")
const Geometry: GDScript = preload("res://scripts/vegetation_lab/building_geometry.gd")
const Parts: GDScript = preload("res://scripts/vegetation_lab/plant_parts.gd")
const Patch: GDScript = preload("res://scripts/vegetation_lab/growth_patch.gd")
const Layers: GDScript = preload("res://scripts/vegetation_lab/surface_layers.gd")
var layers: Array[Node3D] = []
var moss_check: CheckBox
var moss_slider: HSlider
var moss_number: SpinBox
var crack_check: CheckBox
var moss_material: ShaderMaterial
var crack_material: ShaderMaterial
var library: RefCounted
var definitions: Array[Dictionary]
var patches: Array[Node3D] = []
var centers: Array[Vector3] = [Vector3(-7.2,0,7.2),Vector3.ZERO,Vector3(7.2,0,-7.2)]
var render_view: SubViewport
var doubled_view: SubViewport
var camera: Camera3D
var slider: HSlider
var number: SpinBox
var view_select: OptionButton
var presets: Array[Button] = []
var world: Node3D

func _ready() -> void:
	var window: Window = get_window()
	window.title = "共通植生の成長｜3棟比較"
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
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("687465")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("b4c4cc")
	environment.ambient_light_energy = 0.42
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var env: WorldEnvironment = WorldEnvironment.new()
	env.environment = environment
	world.add_child(env)
	RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_HARD)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 65
	sun.shadow_bias = 0.1
	sun.shadow_normal_bias = 1.0
	sun.shadow_blur = 1.0
	sun.light_angular_distance = 0
	sun.light_color = Color(1,0.98,0.90)
	sun.light_energy = 1.35
	world.add_child(sun)
	sun.position = Vector3(-5,10,6)
	sun.look_at(Vector3.ZERO)
	moss_material = ShaderMaterial.new()
	moss_material.shader = Layers.Moss
	crack_material = ShaderMaterial.new()
	crack_material.shader = Layers.Cracks
	library = Parts.new()
	definitions = Definitions.all()
	for i: int in 3:
		var building: Node3D = Node3D.new()
		building.position = centers[i]
		world.add_child(building)
		Geometry.build(building,definitions[i])
		var patch: Node3D = Patch.new()
		building.add_child(patch)
		patch.setup(definitions[i],library)
		patches.append(patch)
		var layer: Node3D = Layers.new()
		building.add_child(layer)
		layer.setup(definitions[i],moss_material,crack_material)
		layers.append(layer)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.far = 100
	world.add_child(camera)
	camera.current = true
	set_view(0)
	_texture(self,render_view.get_texture(),Vector2(640,360))
	doubled_view = SubViewport.new()
	doubled_view.size = Vector2i(1920,1080)
	doubled_view.disable_3d = true
	doubled_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(doubled_view)
	_texture(doubled_view,render_view.get_texture(),Vector2(1920,1080))
	_build_ui()
	set_growth(50)

func _texture(parent: Node, texture: Texture2D, size_: Vector2) -> void:
	var rect: TextureRect = TextureRect.new()
	rect.texture = texture
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	rect.size = size_
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(rect)

func _build_ui() -> void:
	var panel: PanelContainer = PanelContainer.new()
	panel.position = Vector2(6,6)
	panel.size = Vector2(628,34)
	var theme_: Theme = Theme.new()
	var font: SystemFont = SystemFont.new()
	font.font_names = PackedStringArray(["Yu Gothic UI","Meiryo"])
	theme_.default_font = font
	theme_.default_font_size = 13
	panel.theme = theme_
	add_child(panel)
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation",6)
	panel.add_child(row)
	var label_: Label = Label.new()
	label_.text = " 緑化率"
	row.add_child(label_)
	slider = HSlider.new()
	slider.custom_minimum_size.x = 160
	slider.max_value = 100
	slider.value_changed.connect(set_growth)
	row.add_child(slider)
	number = SpinBox.new()
	number.custom_minimum_size.x = 65
	number.max_value = 100
	number.suffix = "%"
	number.value_changed.connect(set_growth)
	row.add_child(number)
	for value: int in [0,50,100]:
		var button: Button = Button.new()
		button.text = str(value)
		button.custom_minimum_size.x = 40
		button.pressed.connect(set_growth.bind(float(value)))
		row.add_child(button)
		presets.append(button)
	view_select = OptionButton.new()
	for title: String in ["3棟一覧","A 横長","B 縦長","C 円塔"]:
		view_select.add_item(title)
	view_select.item_selected.connect(set_view)
	row.add_child(view_select)
	var panel2: PanelContainer = PanelContainer.new()
	panel2.position = Vector2(6,42)
	panel2.size = Vector2(628,30)
	panel2.theme = theme_
	add_child(panel2)
	var row2: HBoxContainer = HBoxContainer.new()
	row2.add_theme_constant_override("separation",10)
	panel2.add_child(row2)
	moss_check = CheckBox.new()
	moss_check.text = "苔"
	moss_check.button_pressed = true
	moss_check.toggled.connect(set_moss_enabled)
	row2.add_child(moss_check)
	moss_slider = HSlider.new()
	moss_slider.max_value = 100
	moss_slider.custom_minimum_size.x = 155
	moss_slider.value_changed.connect(set_moss_amount)
	row2.add_child(moss_slider)
	moss_number = SpinBox.new()
	moss_number.max_value = 100
	moss_number.suffix = "%"
	moss_number.custom_minimum_size.x = 65
	moss_number.value_changed.connect(set_moss_amount)
	row2.add_child(moss_number)
	crack_check = CheckBox.new()
	crack_check.text = "ひび割れ（独立模様）"
	crack_check.toggled.connect(set_cracks_enabled)
	row2.add_child(crack_check)
	set_moss_amount(60)
	set_cracks_enabled(false)
	var note: Label = Label.new()
	note.position = Vector2(12,337)
	note.text = "A 横長平屋　　　　　B 縦長角形　　　　　C レンガ円塔　｜　共通部品・固定昼光"
	note.theme = theme_
	add_child(note)

func set_growth(value: float) -> void:
	if slider != null:
		slider.set_value_no_signal(value)
		number.set_value_no_signal(value)
	for patch: Node3D in patches:
		patch.set_growth(value)

func set_view(index: int) -> void:
	var target: Vector3 = Vector3(0,1.1,0)
	camera.size = 18.3
	if index > 0:
		# Leave the upper 72 internal pixels clear for both control rows.
		target = centers[index-1]+Vector3.UP*(float(definitions[index-1]["size"].y)*0.40+0.50)
		camera.size = 12.8 if index < 3 else 13.8
	camera.position = target+Vector3(22,22*sqrt(2.0/3.0),22)
	camera.look_at(target)

func wait_render() -> void:
	for i: int in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw

func set_moss_enabled(enabled: bool) -> void:
	for layer: Node3D in layers:
		layer.moss.visible = enabled

func set_moss_amount(value: float) -> void:
	moss_slider.set_value_no_signal(value)
	moss_number.set_value_no_signal(value)
	moss_material.set_shader_parameter("coverage",value/100.0)

func set_cracks_enabled(enabled: bool) -> void:
	for layer: Node3D in layers:
		layer.cracks.visible = enabled
