extends Node
## Independent delivery inspection map. No simulation, collisions or growth.
const CATEGORIES: Array[String] = ["BLD", "VIN", "MOS", "TRE", "GND", "PRP"]
const TITLES: Array[String] = ["建物", "ツタ", "コケ", "樹木", "地面", "小物"]
const SPACING: Array[float] = [17.0,4.0,2.1,8.0,6.0,5.0]
const CATEGORY_SIZE: Array[float] = [43.0,12.0,7.0,24.0,16.0,14.0]
const SCREEN_RIGHT: Vector3 = Vector3(0.70710678,0,-0.70710678)
var assets: Array[Dictionary] = []
var render_view: SubViewport
var doubled_view: SubViewport
var world: Node3D
var camera: Camera3D
var sun: DirectionalLight3D
var camera_target: Vector3 = Vector3.ZERO
var category_index: int = 0
var selected_index: int = -1
var keys: Dictionary = {}
var sun_azimuth: float = 320.0
var sun_elevation: float = 52.0
var category_select: OptionButton
var asset_select: OptionButton
var azimuth_slider: HSlider
var elevation_slider: HSlider
var hud: Label
var id_labels: Array[Label] = []

func _ready() -> void:
	var window: Window = get_window()
	window.title = "グリーンベーダー｜納品アセット24件 展示マップ"
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
	camera.far = 120.0
	world.add_child(camera)
	camera.current = true
	_load_assets()
	_texture(self,render_view.get_texture(),Vector2(640,360))
	doubled_view = SubViewport.new()
	doubled_view.size = Vector2i(1920,1080)
	doubled_view.disable_3d = true
	doubled_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(doubled_view)
	_texture(doubled_view,render_view.get_texture(),Vector2(1920,1080))
	_build_ui()
	focus_category(0)

func _texture(parent: Node, texture: Texture2D, dimensions: Vector2) -> void:
	var rect: TextureRect = TextureRect.new()
	rect.texture = texture
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	rect.size = dimensions
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(rect)

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
	sun.directional_shadow_max_distance = 90
	sun.shadow_bias = 0.06
	sun.shadow_normal_bias = 0.6
	sun.light_angular_distance = 0
	sun.light_color = Color(1,0.98,0.90)
	sun.light_energy = 1.35
	world.add_child(sun)
	update_sun()

func _box(parent: Node3D, label: String, center: Vector3, dimensions: Vector3, color: Color) -> MeshInstance3D:
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = dimensions
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 1
	var node: MeshInstance3D = MeshInstance3D.new()
	node.name = label
	node.mesh = mesh
	node.material_override = mat
	node.position = center
	parent.add_child(node)
	return node

func _load_assets() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/models/delivery_showcase/manifest.json"))
	for value: Dictionary in manifest["assets"]:
		var entry: Dictionary = value.duplicate(true)
		var category: int = CATEGORIES.find(entry["category"])
		var slot: int = assets.size()%4
		var anchor: Node3D = Node3D.new()
		anchor.name = entry["id"]
		anchor.position = Vector3(category*110.0,0,0)+SCREEN_RIGHT*(slot-1.5)*SPACING[category]
		world.add_child(anchor)
		var scene: PackedScene = load(entry["scene"]) as PackedScene
		assert(scene!=null,"Missing delivered model: "+str(entry["id"]))
		var model: Node3D = scene.instantiate() as Node3D
		anchor.add_child(model)
		var bounds: AABB = model_bounds(model)
		var metadata: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(entry["metadata"]))
		var id: String = entry["id"]
		# Keep delivered Y-up orientation. Most assets have their attachment root
		# at Y=0; whole rigid objects rest at their actual mesh minimum instead.
		var is_attachment: bool = category in [1,2]
		if not is_attachment:
			model.position = Vector3(-bounds.get_center().x,-bounds.position.y,-bounds.get_center().z)
		elif id in ["VIN-047","MOS-003","MOS-024"]:
			model.position.y = 0.012
		else:
			model.position.y = 0.012
		_receiver(anchor,model,id,bounds)
		entry["node"] = model
		entry["anchor"] = anchor
		entry["bounds"] = model_bounds(model)
		entry["metadata_data"] = metadata
		entry["scale"] = model.scale
		entry["contact_type"] = metadata.get("contact_type","ground_contact")
		assets.append(entry)
	# A continuous, deliberately untextured floor for each category only.
	for category: int in range(6):
		_box(world,"PlainFloor"+CATEGORIES[category],Vector3(category*110.0,-0.15,0),Vector3(90,0.3,55),Color("687365"))

static func model_bounds(model: Node3D) -> AABB:
	var meshes: Array[Node] = model.find_children("*","MeshInstance3D",true,false)
	var result: AABB = AABB()
	var first: bool = true
	for node: Node in meshes:
		var mesh: MeshInstance3D = node as MeshInstance3D
		var box: AABB = model.global_transform.affine_inverse()*mesh.global_transform*mesh.get_aabb()
		if first:
			result = box
			first = false
		else:
			result = result.merge(box)
	return result

func _receiver(anchor: Node3D, model: Node3D, id: String, bounds: AABB) -> void:
	var color: Color = Color("92978a")
	if id in ["VIN-007","VIN-032","VIN-060"]:
		var width: float = maxf(bounds.size.x+0.5,3.0)
		var height: float = maxf(bounds.end.y+0.2,3.0)
		var center_x: float = bounds.get_center().x
		if id=="VIN-007":
			# Window lower-left=(.18,.8), dimensions1.4x1.2 per metadata.
			_box(anchor,"WindowLowerWall",Vector3(center_x,0.4,-0.105),Vector3(width,0.8,0.2),color)
			_box(anchor,"WindowUpperWall",Vector3(center_x,2.5,-0.105),Vector3(width,1.0,0.2),color)
			_box(anchor,"WindowLeftWall",Vector3(-0.36,1.4,-0.105),Vector3(1.08,1.2,0.2),color)
			_box(anchor,"WindowRightWall",Vector3(1.82,1.4,-0.105),Vector3(0.48,1.2,0.2),color)
			_box(anchor,"WindowDarkRecess",Vector3(0.88,1.4,-0.18),Vector3(1.4,1.2,0.04),Color("35423f"))
		else:
			_box(anchor,"WallReceiver",Vector3(center_x,height*0.5,-0.105),Vector3(width,height,0.2),color)
		if id=="VIN-060":
			# Blender slab [-1.1,-.5,1.25]..[1.1,0,1.4] mapped to Y-up.
			_box(anchor,"ProjectingLedge",Vector3(0,1.325,0.25),Vector3(2.2,0.15,0.5),color)
	elif id=="MOS-012":
		_box(anchor,"InnerCornerZ",Vector3(0.28,0.45,-0.065),Vector3(0.7,0.9,0.12),color)
		_box(anchor,"InnerCornerX",Vector3(-0.065,0.45,0.28),Vector3(0.12,0.9,0.7),color)
	elif id=="MOS-035":
		# Recreate only the documented reference receiver, not a new delivered
		# asset: flared root collar r=.27+.40*(1-s)^2*(.8+.2*cos4a).
		var surface: SurfaceTool = SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		for j: int in range(20):
			for i: int in range(64):
				var points: Array[Vector3] = []
				for uv: Vector2 in [Vector2(i,j),Vector2(i+1,j),Vector2(i+1,j+1),Vector2(i,j+1)]:
					var s: float = uv.y/20.0
					var a: float = uv.x/64.0*TAU
					var radius: float = 0.27+0.40*pow(1-s,2)*(0.8+0.2*cos(4*a))
					points.append(Vector3(radius*cos(a),0.7*s,-radius*sin(a)))
				for index: int in [0,2,1,0,3,2]:
					surface.add_vertex(points[index])
		surface.generate_normals()
		var receiver: MeshInstance3D = MeshInstance3D.new()
		receiver.name = "RootCollarReceiver"
		receiver.mesh = surface.commit()
		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.albedo_color = Color("735f47")
		mat.roughness = 1
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		receiver.material_override = mat
		receiver.position.y = model.position.y
		anchor.add_child(receiver)

func _build_ui() -> void:
	var theme_: Theme = Theme.new()
	theme_.default_font_size = 11
	var panel: PanelContainer = PanelContainer.new()
	panel.theme = theme_
	panel.position = Vector2(6,4)
	panel.size = Vector2(628,64)
	add_child(panel)
	var rows: VBoxContainer = VBoxContainer.new()
	panel.add_child(rows)
	var first: HBoxContainer = HBoxContainer.new()
	rows.add_child(first)
	category_select = OptionButton.new()
	category_select.fit_to_longest_item = false
	category_select.custom_minimum_size.x = 90
	for i: int in range(6):
		category_select.add_item(CATEGORIES[i]+" "+TITLES[i])
	category_select.item_selected.connect(focus_category)
	first.add_child(category_select)
	asset_select = OptionButton.new()
	asset_select.fit_to_longest_item = false
	asset_select.clip_text = true
	asset_select.custom_minimum_size.x = 288
	asset_select.item_selected.connect(func(index: int) -> void:
		if index==0: focus_category(category_index)
		else: focus_asset(category_index*4+index-1))
	first.add_child(asset_select)
	var home: Button = Button.new()
	home.text = "カテゴリ全景"
	home.pressed.connect(func() -> void: focus_category(category_index))
	first.add_child(home)
	for action: int in [-1,1]:
		var zoom: Button = Button.new()
		zoom.text = "＋" if action<0 else "−"
		zoom.pressed.connect(func() -> void: zoom_camera(action))
		first.add_child(zoom)
	var light_row: HBoxContainer = HBoxContainer.new()
	rows.add_child(light_row)
	var az_label: Label = Label.new()
	az_label.text = "太陽 方位"
	light_row.add_child(az_label)
	azimuth_slider = HSlider.new()
	azimuth_slider.min_value = 0
	azimuth_slider.max_value = 360
	azimuth_slider.value = sun_azimuth
	azimuth_slider.custom_minimum_size.x = 160
	azimuth_slider.value_changed.connect(func(value: float) -> void: sun_azimuth=value; update_sun())
	light_row.add_child(azimuth_slider)
	var el_label: Label = Label.new()
	el_label.text = "仰角"
	light_row.add_child(el_label)
	elevation_slider = HSlider.new()
	elevation_slider.min_value = 5
	elevation_slider.max_value = 85
	elevation_slider.value = sun_elevation
	elevation_slider.custom_minimum_size.x = 140
	elevation_slider.value_changed.connect(func(value: float) -> void: sun_elevation=value; update_sun())
	light_row.add_child(elevation_slider)
	hud = Label.new()
	hud.add_theme_font_size_override("font_size",11)
	light_row.add_child(hud)
	var footer: Label = Label.new()
	footer.position = Vector2(7,337)
	footer.add_theme_font_size_override("font_size",11)
	footer.text = "WASD/矢印:移動  1〜6:カテゴリ  Tab:次の部品  Q/E・ホイール:ズーム  R:全景"
	add_child(footer)
	for entry: Dictionary in assets:
		var label: Label = Label.new()
		label.text = entry["id"]
		label.add_theme_font_size_override("font_size",11)
		label.add_theme_color_override("font_color",Color("f5efd5"))
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(label)
		id_labels.append(label)

func focus_category(index: int) -> void:
	category_index = clampi(index,0,5)
	selected_index = -1
	category_select.select(category_index)
	asset_select.clear()
	asset_select.add_item("全4件 / 元の縮尺")
	for i: int in range(category_index*4,category_index*4+4):
		asset_select.add_item(assets[i]["id"]+" "+assets[i]["name"])
	asset_select.select(0)
	var height: float = 0
	for i: int in range(category_index*4,category_index*4+4):
		var b: AABB = assets[i]["bounds"]
		height = maxf(height,b.end.y)
	camera_target = Vector3(category_index*110.0,height*0.5,0)
	camera.size = CATEGORY_SIZE[category_index]
	_update_camera()

func focus_asset(index: int) -> void:
	var new_category: int = index/4
	if category_index!=new_category:
		focus_category(new_category)
	selected_index = index
	asset_select.select(index%4+1)
	var model: Node3D = assets[index]["node"]
	var bounds: AABB = assets[index]["bounds"]
	camera_target = model.global_transform*bounds.get_center()
	var height: float = bounds.size.y*0.866+(bounds.size.x+bounds.size.z)*0.36
	camera.size = maxf(3.0,height*1.55)
	_update_camera()

func zoom_camera(direction: int) -> void:
	camera.size = clampf(camera.size*(0.85 if direction<0 else 1.0/0.85),2.0,100.0)
	_update_camera()

func _update_camera() -> void:
	# Pixel snap view motion along camera-plane axes, keep simulation target
	# unsnapped. Rotation fixed at elevation30/azimuth45 throughout.
	var pixel: float = camera.size/360.0
	var right: Vector3 = SCREEN_RIGHT
	var up: Vector3 = Vector3(-0.35355339,0.8660254,-0.35355339)
	var snapped: Vector3 = camera_target
	snapped += right*(snappedf(snapped.dot(right),pixel)-snapped.dot(right))
	snapped += up*(snappedf(snapped.dot(up),pixel)-snapped.dot(up))
	camera.position = snapped+Vector3(22,22*sqrt(2.0/3.0),22)
	camera.look_at(snapped)
	_update_hud()

func update_sun() -> void:
	var azimuth: float = deg_to_rad(sun_azimuth)
	var elevation: float = deg_to_rad(sun_elevation)
	sun.position = Vector3(sin(azimuth)*cos(elevation),sin(elevation),cos(azimuth)*cos(elevation))*15
	sun.look_at(Vector3.ZERO)
	_update_hud()

func _update_hud() -> void:
	if hud!=null:
		hud.text = "%d° / %d°  範囲%.1fm"%[sun_azimuth,sun_elevation,camera.size]

func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key: InputEventKey = event as InputEventKey
		var code: int = key.physical_keycode if key.physical_keycode!=0 else key.keycode
		if not key.pressed:
			keys.erase(code)
		elif not key.echo and not get_viewport().gui_get_focus_owner() is LineEdit:
			keys[code] = true
			if code>=KEY_1 and code<=KEY_6: focus_category(code-KEY_1)
			if code==KEY_TAB: focus_asset(category_index*4+(0 if selected_index<0 else (selected_index+1)%4))
			if code==KEY_R: focus_category(category_index)
			if code==KEY_Q: zoom_camera(-1)
			if code==KEY_E: zoom_camera(1)
	elif event is InputEventMouseButton:
		var mouse: InputEventMouseButton = event as InputEventMouseButton
		if mouse.pressed and mouse.button_index==MOUSE_BUTTON_WHEEL_UP: zoom_camera(-1)
		if mouse.pressed and mouse.button_index==MOUSE_BUTTON_WHEEL_DOWN: zoom_camera(1)

func _notification(what: int) -> void:
	if what==NOTIFICATION_APPLICATION_FOCUS_OUT:
		keys.clear()

func _process(delta: float) -> void:
	var movement: Vector2 = Vector2.ZERO
	if keys.has(KEY_A) or keys.has(KEY_LEFT): movement.x -= 1
	if keys.has(KEY_D) or keys.has(KEY_RIGHT): movement.x += 1
	if keys.has(KEY_W) or keys.has(KEY_UP): movement.y -= 1
	if keys.has(KEY_S) or keys.has(KEY_DOWN): movement.y += 1
	if movement!=Vector2.ZERO:
		movement = movement.normalized()
		camera_target += (SCREEN_RIGHT*movement.x+Vector3(0.70710678,0,0.70710678)*movement.y)*delta*camera.size*0.65
		_update_camera()
	for i: int in range(assets.size()):
		var model: Node3D = assets[i]["node"]
		var bounds: AABB = assets[i]["bounds"]
		var bottom: Vector3 = model.global_transform*Vector3(bounds.get_center().x,bounds.position.y,bounds.get_center().z)
		var screen: Vector2 = camera.unproject_position(bottom)
		var label: Label = id_labels[i]
		label.visible = i/4==category_index and not camera.is_position_behind(bottom) and screen.x>30 and screen.x<600 and screen.y>76 and screen.y<310
		label.position = screen+Vector2(-24,8)

func wait_render() -> void:
	for i: int in range(5):
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
