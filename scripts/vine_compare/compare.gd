extends Node
const Parts: GDScript = preload("res://scripts/vegetation_lab/plant_parts.gd")
const Patch: GDScript = preload("res://scripts/vegetation_lab/growth_patch.gd")
const Definitions: GDScript = preload("res://scripts/vegetation_lab/building_defs.gd")
const Geometry: GDScript = preload("res://scripts/vegetation_lab/building_geometry.gd")
const Reveal: GDScript = preload("res://scripts/vine_compare/path_reveal.gd")
const DEFAULT_PATH: String = "C:/godot/greenvader_asset_deliveries/assets/vines"
const RIGHT: Vector3 = Vector3(0.70710678,0,-0.70710678)
var render_view: SubViewport
var doubled_view: SubViewport
var world: Node3D
var camera: Camera3D
var sun: DirectionalLight3D
var left: Node3D
var right: Node3D
var left_receiver: Node3D
var right_receiver: Node3D
var old_patch: Node3D
var library: RefCounted = Parts.new()
var definition: Dictionary
var model: Node3D
var reveal: RefCounted
var metadata: Dictionary = {}
var inventory: Array[Dictionary] = []
var current_id: int = 7
var growth: float = 100
var playing: bool = false
var play_duration: float = 16.0
var sun_azimuth: float = 320
var sun_elevation: float = 52
var last_error: String = ""
var path_field: LineEdit
var id_field: LineEdit
var asset_select: OptionButton
var density_select: OptionButton
var receiver_select: OptionButton
var growth_slider: HSlider
var play_button: Button
var azimuth_slider: HSlider
var elevation_slider: HSlider
var status: Label
var names: Label

func _ready() -> void:
	var window: Window = get_window()
	window.title = "グリーンベーダー｜旧ツタ / 納品ツタ 比較"
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
	camera.size = 6.8
	camera.far = 100
	world.add_child(camera)
	camera.current = true
	left = Node3D.new()
	left.position = -RIGHT*2.6
	world.add_child(left)
	right = Node3D.new()
	right.position = RIGHT*2.6
	world.add_child(right)
	_box(world,Vector3(0,-0.13,0),Vector3(60,0.25,60),Color("687365"))
	var holes: Array[Rect2] = [Rect2(0.65,0.85,1.2,1.1)]
	definition = {"id":"old","shape":"box","size":Vector3(3,2.8,0.2),"color":Color("92978a"),"seed":501,"extent":Vector2.ZERO,"walkway":{"from":Vector2.ZERO,"to":Vector2.ZERO,"half_width":0.0},"surfaces":[Definitions.plane(Vector3(-1.5,0,0),Vector3.RIGHT,Vector3.BACK,3,2.8,holes)]}
	_build_old()
	_texture(self,render_view.get_texture(),Vector2(640,360))
	doubled_view = SubViewport.new()
	doubled_view.size = Vector2i(1920,1080)
	doubled_view.disable_3d = true
	doubled_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(doubled_view)
	_texture(doubled_view,render_view.get_texture(),Vector2(1920,1080))
	_ui()
	reload_inventory()
	_update_camera()

func _environment() -> void:
	var env: Environment = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("566359")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("b4c4cc")
	env.ambient_light_energy = 0.42
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var node: WorldEnvironment = WorldEnvironment.new()
	node.environment = env
	world.add_child(node)
	RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_HARD)
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 65
	sun.shadow_bias = 0.06
	sun.shadow_normal_bias = 0.6
	sun.light_angular_distance = 0
	sun.light_color = Color(1,0.98,0.90)
	sun.light_energy = 1.35
	world.add_child(sun)
	update_sun()

func _texture(parent: Node, texture: Texture2D, dimensions: Vector2) -> void:
	var rect: TextureRect = TextureRect.new()
	rect.texture = texture
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	rect.size = dimensions
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(rect)

func _box(parent: Node3D, center: Vector3, dimensions: Vector3, color: Color) -> MeshInstance3D:
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = dimensions
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 1
	var node: MeshInstance3D = MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = mat
	node.position = center
	parent.add_child(node)
	return node

func _build_old() -> void:
	if old_patch!=null: old_patch.free()
	old_patch = Patch.new()
	left.add_child(old_patch)
	old_patch.setup(definition,library,{"include_ground":false,"walls_only":true,"sparse_windows":density_select==null or density_select.selected==0})
	set_growth(growth)

func _row(parent: Node, at: Vector2) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.position = at
	row.add_theme_constant_override("separation",4)
	parent.add_child(row)
	return row

func _button(parent: Node, text: String, action: Callable) -> Button:
	var result: Button = Button.new()
	result.text = text
	result.pressed.connect(action)
	parent.add_child(result)
	return result

func _ui() -> void:
	var layer: Control = Control.new()
	var theme_: Theme = Theme.new()
	theme_.default_font_size = 10
	layer.theme = theme_
	add_child(layer)
	for area: Rect2 in [Rect2(3,2,634,74),Rect2(3,281,634,77)]:
		var panel: ColorRect = ColorRect.new()
		panel.position = area.position
		panel.size = area.size
		panel.color = Color(0.09,0.13,0.11,0.88)
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(panel)
	var path_row: HBoxContainer = _row(layer,Vector2(7,4))
	path_field = LineEdit.new()
	path_field.text = DEFAULT_PATH
	path_field.custom_minimum_size = Vector2(532,20)
	path_field.text_submitted.connect(func(_text: String) -> void: reload_inventory())
	path_row.add_child(path_field)
	_button(path_row,"再読込",reload_inventory)
	var select_row: HBoxContainer = _row(layer,Vector2(7,28))
	_button(select_row,"前",func() -> void: step_id(-1))
	asset_select = OptionButton.new()
	asset_select.fit_to_longest_item = false
	asset_select.clip_text = true
	asset_select.custom_minimum_size.x = 253
	asset_select.item_selected.connect(func(index: int) -> void: select_id(inventory[index]["number"]))
	select_row.add_child(asset_select)
	_button(select_row,"次",func() -> void: step_id(1))
	id_field = LineEdit.new()
	id_field.text = "007"
	id_field.custom_minimum_size.x = 42
	id_field.max_length = 8
	id_field.text_submitted.connect(func(text: String) -> void: select_text(text))
	select_row.add_child(id_field)
	_button(select_row,"IDへ",func() -> void: select_text(id_field.text))
	density_select = OptionButton.new()
	density_select.add_item("旧:小マップ疎密")
	density_select.add_item("旧:lab密度")
	density_select.item_selected.connect(func(_index: int) -> void: _build_old())
	select_row.add_child(density_select)
	var controls: HBoxContainer = _row(layer,Vector2(7,52))
	receiver_select = OptionButton.new()
	for name_: String in ["受け面:自動", "共通の窓壁", "受け面なし"]: receiver_select.add_item(name_)
	receiver_select.item_selected.connect(func(_index: int) -> void: _receivers())
	controls.add_child(receiver_select)
	_button(controls,"＋",func() -> void: zoom(0.85))
	_button(controls,"−",func() -> void: zoom(1/0.85))
	_button(controls,"18.5m",func() -> void: camera.size=18.5; _update_camera())
	var az: Label = Label.new()
	az.text = "方位"
	controls.add_child(az)
	azimuth_slider = HSlider.new()
	azimuth_slider.custom_minimum_size.x = 97
	azimuth_slider.max_value = 360
	azimuth_slider.value = sun_azimuth
	azimuth_slider.value_changed.connect(func(value: float) -> void: sun_azimuth=value; update_sun())
	controls.add_child(azimuth_slider)
	var el: Label = Label.new()
	el.text = "仰角"
	controls.add_child(el)
	elevation_slider = HSlider.new()
	elevation_slider.custom_minimum_size.x = 97
	elevation_slider.min_value = 5
	elevation_slider.max_value = 85
	elevation_slider.value = sun_elevation
	elevation_slider.value_changed.connect(func(value: float) -> void: sun_elevation=value; update_sun())
	controls.add_child(elevation_slider)
	names = Label.new()
	names.position = Vector2(8,79)
	names.size = Vector2(624,16)
	names.clip_text = true
	layer.add_child(names)
	var growth_row: HBoxContainer = _row(layer,Vector2(8,283))
	var label: Label = Label.new()
	label.text = "同期成長"
	growth_row.add_child(label)
	growth_slider = HSlider.new()
	growth_slider.custom_minimum_size.x = 553
	growth_slider.max_value = 100
	growth_slider.step = 1
	growth_slider.value = growth
	growth_slider.value_changed.connect(set_growth)
	growth_row.add_child(growth_slider)
	var playback: HBoxContainer = _row(layer,Vector2(8,307))
	for value: int in [0,25,50,75,100]:
		_button(playback,str(value)+"%",func() -> void: growth_slider.value=value)
	play_button = _button(playback,"再生",func() -> void: set_playing(not playing))
	_button(playback,"先頭へ",func() -> void: set_playing(false); set_growth(0))
	var note: Label = Label.new()
	note.text = "推定成長（三角形を順次表示）"
	playback.add_child(note)
	status = Label.new()
	status.position = Vector2(8,335)
	status.size = Vector2(624,18)
	status.clip_text = true
	layer.add_child(status)

func reload_inventory() -> bool:
	var folder: String = path_field.text.strip_edges().replace("\\","/").trim_suffix("/")
	var directory: DirAccess = DirAccess.open(folder)
	if directory==null: return _error("フォルダを読めません: "+folder)
	var found: Array[Dictionary] = []
	for child: String in directory.get_directories():
		var full: String = folder.path_join(child)
		var file: String = full.path_join("metadata.json")
		if not FileAccess.file_exists(file): continue
		var json: JSON = JSON.new()
		if json.parse(FileAccess.get_file_as_string(file))!=OK or not json.data is Dictionary: continue
		var meta: Dictionary = json.data
		var id: String = String(meta.get("asset_id",""))
		if not id.begins_with("VIN-") or not id.trim_prefix("VIN-").is_valid_int(): continue
		var glbs: Array[String] = []
		for filename: String in DirAccess.get_files_at(full):
			if filename.get_extension().to_lower()=="glb": glbs.append(full.path_join(filename))
		if glbs.is_empty(): continue
		glbs.sort()
		found.append({"number":id.trim_prefix("VIN-").to_int(),"id":id,"name":meta.get("name",child),"file":glbs[0],"metadata":meta})
	if found.is_empty(): return _error("VINのmetadataとGLBがありません")
	found.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return a["number"]<b["number"])
	inventory = found
	asset_select.clear()
	for entry: Dictionary in inventory: asset_select.add_item(entry["id"]+" "+entry["name"])
	var number: int = current_id
	if _index(number)<0: number = inventory[0]["number"]
	return select_id(number)

func _index(number: int) -> int:
	for i: int in range(inventory.size()):
		if inventory[i]["number"]==number: return i
	return -1

func select_text(text: String) -> bool:
	var number: String = text.strip_edges().to_upper().trim_prefix("VIN-")
	if not number.is_valid_int(): return _error("IDは数値、またはVIN-007の形式です")
	return select_id(number.to_int())

func step_id(direction: int) -> void:
	if inventory.is_empty(): return
	var index: int = posmod(_index(current_id)+direction,inventory.size())
	select_id(inventory[index]["number"])

func select_id(number: int) -> bool:
	var index: int = _index(number)
	if index<0: return _error("VIN-%03dは一覧にありません。元フォルダを再読込してください"%number)
	var entry: Dictionary = inventory[index]
	var file: FileAccess = FileAccess.open(entry["file"],FileAccess.READ)
	if file==null or file.get_length()<20: return _error("GLBが読めません: "+String(entry["file"]))
	if file.get_32()!=0x46546c67: return _error("GLBヘッダーが不正です")
	file.close()
	var document: GLTFDocument = GLTFDocument.new()
	var state: GLTFState = GLTFState.new()
	var error: Error = document.append_from_file(entry["file"],state)
	if error!=OK: return _error("GLB読込失敗: "+error_string(error))
	var loaded: Node3D = document.generate_scene(state) as Node3D
	if loaded==null: return _error("GLBシーンを生成できません")
	if loaded.find_children("*","MeshInstance3D",true,false).is_empty():
		loaded.free()
		return _error("GLBにメッシュがありません")
	if model!=null: model.free()
	model = loaded
	right.add_child(model)
	metadata = entry["metadata"]
	current_id = number
	var bounds: AABB = _bounds(model)
	# Placement offset is fixed for this model, independent of growth.
	model.position = Vector3(-bounds.get_center().x,maxf(0,-bounds.position.y),-bounds.get_center().z)
	reveal = Reveal.new()
	reveal.setup(model,metadata)
	asset_select.select(index)
	id_field.text = "%03d"%number
	last_error = ""
	_receivers()
	set_growth(growth)
	return true

func _bounds(root_: Node3D) -> AABB:
	var first: bool = true
	var bounds: AABB = AABB()
	for child: Node in root_.find_children("*","MeshInstance3D",true,false):
		var instance: MeshInstance3D = child as MeshInstance3D
		var box: AABB = root_.global_transform.affine_inverse()*instance.global_transform*instance.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	return bounds

func _error(message: String) -> bool:
	last_error = message
	print("[vine compare] "+message)
	if status!=null:
		status.text = "読込エラー（前の表示を保持）: "+message
	return false

func _window(parent: Node3D, origin: Vector3, width: float, height: float, hole: Rect2) -> void:
	var holes: Array[Rect2] = [hole]
	var surface: Dictionary = Definitions.plane(origin,Vector3.RIGHT,Vector3.BACK,width,height,holes)
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color("92978a")
	mat.roughness = 1
	Geometry._plane_wall(parent,surface,mat)
	_box(parent,origin+Vector3(hole.get_center().x,hole.get_center().y,-0.18),Vector3(hole.size.x,hole.size.y,0.05),Color("35423f"))

func _receivers() -> void:
	if left_receiver!=null: left_receiver.free()
	if right_receiver!=null: right_receiver.free()
	left_receiver = Node3D.new()
	left.add_child(left_receiver)
	right_receiver = Node3D.new()
	right.add_child(right_receiver)
	if receiver_select.selected==2: return
	_window(left_receiver,Vector3(-1.5,0,-0.11),3,2.8,Rect2(0.65,0.85,1.2,1.1))
	if model==null: return
	right_receiver.position = model.position
	var bounds: AABB = _bounds(model)
	var contact: String = metadata.get("contact_type","wall_attachment")
	var c: Dictionary = metadata.get("connections",{})
	if receiver_select.selected==1:
		_window(right_receiver,Vector3(-1.5,0,-0.11),3,2.8,Rect2(0.65,0.85,1.2,1.1))
		return
	if "ground" in contact and not "wall" in contact: return
	var width: float = maxf(3,bounds.size.x+0.4)
	var height: float = maxf(2.8,bounds.end.y+0.1)
	if current_id==7:
		_window(right_receiver,Vector3(bounds.get_center().x-width/2,0,-0.11),width,height,Rect2(0.18-(bounds.get_center().x-width/2),0.8,1.4,1.2))
	elif "curved" in contact:
		var radius: float = float(c.get("receiver_radius_m",c.get("review_column_radius",c.get("review_pipe_radius",0.35))))
		var cylinder: CylinderMesh = CylinderMesh.new()
		cylinder.top_radius = radius
		cylinder.bottom_radius = radius
		cylinder.height = height
		cylinder.radial_segments = 32
		var receiver: MeshInstance3D = MeshInstance3D.new()
		receiver.mesh = cylinder
		receiver.position.y = height/2
		var material_: StandardMaterial3D = StandardMaterial3D.new()
		material_.albedo_color = Color("92978a")
		receiver.material_override = material_
		right_receiver.add_child(receiver)
	else:
		_box(right_receiver,Vector3(bounds.get_center().x,height/2,-0.12),Vector3(width,height,0.2),Color("92978a"))
		if current_id==60:
			_box(right_receiver,Vector3(0,1.325,0.25),Vector3(2.2,0.15,0.5),Color("92978a"))

func set_growth(value: float) -> void:
	growth = clampf(value,0,100)
	if growth_slider!=null: growth_slider.set_value_no_signal(growth)
	if old_patch!=null:
		var values: Dictionary = {}
		for root_: int in old_patch.root_durations: values[root_] = growth/100
		old_patch.set_root_progress(values)
		old_patch.set_growth(growth)
		old_patch.visible = growth>0
	if reveal!=null: reveal.set_growth(growth)
	_update_text()

func set_playing(value: bool) -> void:
	playing = value
	play_button.text = "停止" if playing else "再生"
	if playing and growth>=100: set_growth(0)

func _update_text() -> void:
	if status==null: return
	if not last_error.is_empty():
		status.text = "読込エラー（前の表示を保持）: "+last_error
		return
	var contact: String = metadata.get("contact_type","wall_attachment")
	var type_: String = "床" if "ground" in contact and not "wall" in contact else ("曲面" if "curved" in contact else ("吊り" if "suspended" in contact else "壁/複合"))
	names.text = "左:旧ツタ（元部品・元色）                 右:VIN-%03d  %s用・元縮尺"%[current_id,type_]
	status.text = "%d件  成長%.0f%%  太陽%d°/%d°  同率は時間・被覆率の一致を意味しません"%[inventory.size(),growth,sun_azimuth,sun_elevation]

func update_sun() -> void:
	var a: float = deg_to_rad(sun_azimuth)
	var e: float = deg_to_rad(sun_elevation)
	sun.position = Vector3(sin(a)*cos(e),sin(e),cos(a)*cos(e))*15
	sun.look_at(Vector3.ZERO)
	_update_text()

func zoom(multiplier: float) -> void:
	camera.size = clampf(camera.size*multiplier,3.0,25.0)
	_update_camera()

func _update_camera() -> void:
	var target: Vector3 = Vector3(0,1.35,0)
	camera.position = target+Vector3(22,22*sqrt(2.0/3.0),22)
	camera.look_at(target)

func _process(delta: float) -> void:
	if playing:
		set_growth(minf(100,growth+delta*100/play_duration))
		if growth>=100: set_playing(false)

func wait_render() -> void:
	for i: int in range(4):
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
