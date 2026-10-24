extends Node
const Cycle: GDScript = preload("res://scripts/town_lab/day_cycle.gd")
const Actor: GDScript = preload("res://scripts/town_lab/actor.gd")
const Water: GDScript = preload("res://scripts/town_lab/water.gd")
const RIGHT: Vector3 = Vector3(0.70710678,0,-0.70710678)
const DOWN: Vector3 = Vector3(0.70710678,0,0.70710678)
const SPEED: float = 3.2
const RADIUS: float = 0.54
const START: Vector2 = Vector2(0,3.2)
const BUILDINGS: Array[Dictionary] = [
	{"id":"BLD-007","at":Vector2(-13,-12),"angle":0.0},
	{"id":"BLD-019","at":Vector2(-13,11),"angle":PI},
	{"id":"BLD-038","at":Vector2(13,-12),"angle":0.0},
	{"id":"BLD-046","at":Vector2(13,11),"angle":PI},
	{"id":"BLD-079","at":Vector2(-20,21),"angle":PI},
	{"id":"BLD-091","at":Vector2(13,20.5),"angle":PI},
	{"id":"BLD-123","at":Vector2(-21,-21),"angle":0.0}]
var render_view: SubViewport
var doubled_view: SubViewport
var world: Node3D
var camera: Camera3D
var environment: Environment
var sun: DirectionalLight3D
var moon: DirectionalLight3D
var actor: Node3D
var water: Node
var lamps: Array[OmniLight3D] = []
var lamp_materials: Array[StandardMaterial3D] = []
var definitions: Dictionary = {}
var placements: Array[Dictionary] = []
var blockers: Array[Rect2] = []
var collision_grid: Dictionary = {}
var blocker_keys: Dictionary = {}
var position: Vector2 = START
var keys: Dictionary = {}
var animation_time: float = 0
var walking: bool = false
var facing_left: bool = false
var automatic: bool = true
var hour: float = 12
var cycle_seconds: float = 120
var time_speed: float = 1
var time_playing: bool = true
var follow: bool = true
var follow_size: float = 18.5
var overview_size: float = 58
var time_slider: HSlider
var play_button: Button
var follow_button: Button
var clock_label: Label
var hud: Label

func _ready() -> void:
	var window: Window = get_window()
	window.title = "グリーンベーダー｜街区・歩行・昼夜"
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
	camera.far = 150
	world.add_child(camera)
	camera.current = true
	var manifest: Array = JSON.parse_string(FileAccess.get_file_as_string("res://assets/models/town_lab/manifest.json"))
	for entry: Dictionary in manifest: definitions[entry["id"]]=entry
	_terrain()
	for item: Dictionary in BUILDINGS: _place(item["id"],item["at"],item["angle"],"building")
	_place("PRP-041",Vector2(-14,2),PI/2,"large_prop")
	_place("PRP-012",Vector2(-9,5.4),0,"large_prop")
	_place("PRP-017",Vector2(19,-5.8),0,"large_prop")
	_place("PRP-034",Vector2(5.2,-6.5),0,"small_prop")
	_place("PRP-005",Vector2(-21,5),0,"pole")
	_place("PRP-075",Vector2(-7,20),0,"large_prop")
	for at: Vector2 in [Vector2(-5,-4),Vector2(5,4),Vector2(-5,14),Vector2(5,-14)]:
		_place("PRP-001",at,0,"lamp")
		_lamp(at)
	_place("TRE-001",Vector2(-6,-20),0,"tree")
	_place("TRE-001",Vector2(22,8),1.2,"tree")
	actor = Actor.new()
	world.add_child(actor)
	actor.setup(camera)
	_update_camera()
	water = Water.new()
	add_child(water)
	water.setup(render_view,camera,world)
	_texture(self,render_view.get_texture(),Vector2(640,360))
	doubled_view = SubViewport.new()
	doubled_view.size = Vector2i(1920,1080)
	doubled_view.disable_3d = true
	doubled_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(doubled_view)
	_texture(doubled_view,render_view.get_texture(),Vector2(1920,1080))
	_ui()
	set_hour(hour)
	_update_actor(0)

func _environment() -> void:
	environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("566259")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var env: WorldEnvironment = WorldEnvironment.new()
	env.environment = environment
	world.add_child(env)
	RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_HARD)
	for i: int in range(2):
		var light: DirectionalLight3D = DirectionalLight3D.new()
		light.shadow_enabled = true
		light.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
		light.directional_shadow_max_distance = 95
		light.shadow_bias = 0.05
		light.shadow_normal_bias = 0.4
		light.light_angular_distance = 0
		light.shadow_caster_mask = 1|8|32
		world.add_child(light)
		if i==0: sun=light
		else: moon=light
	moon.light_color = Color("90b5e0")

func _box(at: Vector3, dimensions: Vector3, color: Color, parent: Node3D = null) -> MeshInstance3D:
	if parent==null: parent=world
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = dimensions
	var material_: StandardMaterial3D = StandardMaterial3D.new()
	material_.albedo_color = color
	material_.roughness = 0.95
	var node: MeshInstance3D = MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material_
	node.position = at
	node.layers = 2
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	return node

func _terrain() -> void:
	_box(Vector3(0,-0.09,0),Vector3(50,0.16,50),Color("6d7160"))
	_box(Vector3(0,-0.035,0),Vector3(49,0.07,7),Color("606967"))
	_box(Vector3(0,-0.03,0),Vector3(6,0.06,49),Color("626967"))
	for side: float in [-1,1]:
		for segment: float in [-1,1]:
			_box(Vector3(segment*14.65,0.005,side*4.15),Vector3(19.7,0.08,1.25),Color("899086"))
			_box(Vector3(side*3.7,0.006,segment*14.8),Vector3(1.25,0.08,19.4),Color("899086"))
	_box(Vector3(0,-0.025,16),Vector3(46,0.05,2.5),Color("737a70"))
	_box(Vector3(-21,-0.025,-10.5),Vector3(2.2,0.05,21),Color("7b8276"))
	for center: Vector2 in [Vector2(-13,-6.8),Vector2(13,-6.8),Vector2(-13,6),Vector2(13,6)]:
		_box(Vector3(center.x,-0.025,center.y),Vector3(14,0.05,4),Color("7e867b"))
	for x: int in range(-22,23,4):
		if abs(x)<5: continue
		_box(Vector3(x,0.008,0),Vector3(1.7,0.012,0.08),Color("b5ad88"))
	for x: int in range(-2,3):
		_box(Vector3(x*0.65,0.065,4.9),Vector3(0.34,0.012,1.0),Color("b7b7a3"))

func _world_bounds(root_: Node3D) -> AABB:
	var bounds: AABB = AABB()
	var first: bool = true
	for child: Node in root_.find_children("*","MeshInstance3D",true,false):
		var instance: MeshInstance3D = child as MeshInstance3D
		var box: AABB = instance.global_transform*instance.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	return bounds

func _place(id: String, at: Vector2, angle: float, kind: String) -> void:
	var entry: Dictionary = definitions[id]
	var scene: PackedScene = load(entry["scene"]) as PackedScene
	assert(scene!=null,"Cannot load "+id)
	var holder: Node3D = Node3D.new()
	holder.name = id+"_"+str(placements.size())
	world.add_child(holder)
	var model: Node3D = scene.instantiate() as Node3D
	holder.add_child(model)
	var local: AABB = _world_bounds(model)
	model.position = Vector3(-local.get_center().x,-local.position.y,-local.get_center().z)
	holder.position = Vector3(at.x,0,at.y)
	holder.rotation.y = angle
	var bounds: AABB = _world_bounds(model)
	if kind=="lamp":
		# Bulb light is inside the delivered lamp head. Excluding the lamp
		# housing from local-light casters avoids huge self-occlusion wedges.
		for child: Node in model.find_children("*","MeshInstance3D",true,false):
			(child as MeshInstance3D).layers = 32
	var before: int = blockers.size()
	if kind=="building":
		_building_collision(model)
	elif kind=="large_prop":
		_add_blocker(Rect2(Vector2(bounds.position.x,bounds.position.z),Vector2(bounds.size.x,bounds.size.z)))
	elif kind in ["lamp","pole","tree","small_prop"]:
		var radius: float = 0.25 if kind!="tree" else 0.45
		_add_blocker(Rect2(at-Vector2.ONE*radius,Vector2.ONE*radius*2))
	var c: Dictionary = entry["metadata"].get("connections",{})
	var door: Vector3 = Vector3(0,0,local.end.z)
	if c.get("entry_center") is Array:
		var values: Array = c["entry_center"]
		door = Vector3(values[0],values[1],values[2])
	if c.get("door_y_up") is Dictionary:
		var values: Array = c["door_y_up"]["center"]
		door = Vector3(values[0],0,values[2])
	var entry_world: Vector3 = holder.to_global(model.position+door)
	placements.append({"id":id,"name":entry["name"],"kind":kind,"node":holder,"model":model,"bounds":bounds,"entry":entry_world,
		"entry_direction":holder.basis*Vector3.BACK,"collision_rectangles":blockers.size()-before})

func _building_collision(model: Node3D) -> void:
	# Ground-height vertical triangle projections retain openings / under-gallery
	# space. Do not turn an entire open building volume or its roof into one box.
	for child: Node in model.find_children("*","MeshInstance3D",true,false):
		var instance: MeshInstance3D = child as MeshInstance3D
		var faces: PackedVector3Array = instance.mesh.get_faces()
		for i: int in range(0,faces.size()-2,3):
			var a: Vector3 = instance.global_transform*faces[i]
			var b: Vector3 = instance.global_transform*faces[i+1]
			var c: Vector3 = instance.global_transform*faces[i+2]
			var lo: Vector3 = a.min(b).min(c)
			var hi: Vector3 = a.max(b).max(c)
			if hi.y<0.15 or lo.y>1.6: continue
			var normal: Vector3 = (b-a).cross(c-a).normalized()
			if absf(normal.y)>0.8: continue
			_add_blocker(Rect2(Vector2(lo.x,lo.z),Vector2(hi.x-lo.x,hi.z-lo.z)).grow(0.025))

func _add_blocker(rect: Rect2) -> void:
	var key: String = str(rect.position.snapped(Vector2.ONE*0.025),rect.size.snapped(Vector2.ONE*0.025))
	if blocker_keys.has(key): return
	blocker_keys[key] = true
	var index: int = blockers.size()
	blockers.append(rect)
	var expanded: Rect2 = rect.grow(RADIUS)
	for x: int in range(floori(expanded.position.x/4),floori(expanded.end.x/4)+1):
		for z: int in range(floori(expanded.position.y/4),floori(expanded.end.y/4)+1):
			var cell: Vector2i = Vector2i(x,z)
			if not collision_grid.has(cell): collision_grid[cell]=[]
			collision_grid[cell].append(index)

func blocked(point: Vector2) -> bool:
	if absf(point.x)>24.45-RADIUS or absf(point.y)>24.45-RADIUS: return true
	for index: int in collision_grid.get(Vector2i(floori(point.x/4),floori(point.y/4)),[]):
		if blockers[index].grow(RADIUS).has_point(point): return true
	return false

func move_world(motion: Vector2) -> Vector2:
	var start: Vector2 = position
	var count: int = maxi(1,ceili(motion.length()/0.15))
	var part: Vector2 = motion/count
	for i: int in range(count):
		var candidate: Vector2 = position+Vector2(part.x,0)
		if not blocked(candidate): position=candidate
		candidate = position+Vector2(0,part.y)
		if not blocked(candidate): position=candidate
	return position-start

func _lamp(at: Vector2) -> void:
	var light: OmniLight3D = OmniLight3D.new()
	light.position = Vector3(at.x,2.95,at.y)
	light.light_color = Color("ffc48a")
	light.omni_range = 11
	light.omni_attenuation = 1.35
	light.shadow_enabled = true
	light.shadow_bias = 0.04
	light.shadow_normal_bias = 0.4
	light.shadow_caster_mask = 1
	world.add_child(light)
	lamps.append(light)
	var glow: MeshInstance3D = _box(light.position,Vector3(0.19,0.12,0.19),Color("e9bd81"))
	glow.layers = 1
	var mat: StandardMaterial3D = glow.material_override as StandardMaterial3D
	mat.emission_enabled = true
	mat.emission = Color("ffbe78")
	lamp_materials.append(mat)

func _texture(parent: Node, texture: Texture2D, dimensions: Vector2) -> void:
	var rect: TextureRect = TextureRect.new()
	rect.texture = texture
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	rect.size = dimensions
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(rect)

func _button(parent: Node, text: String, callback: Callable) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func _ui() -> void:
	var panel: PanelContainer = PanelContainer.new()
	panel.position = Vector2(5,4)
	panel.size = Vector2(630,57)
	var theme_: Theme = Theme.new()
	theme_.default_font_size = 10
	panel.theme = theme_
	add_child(panel)
	var rows: VBoxContainer = VBoxContainer.new()
	panel.add_child(rows)
	var first: HBoxContainer = HBoxContainer.new()
	rows.add_child(first)
	clock_label = Label.new()
	clock_label.custom_minimum_size.x = 38
	first.add_child(clock_label)
	time_slider = HSlider.new()
	time_slider.max_value = 24
	time_slider.step = 0.01
	time_slider.custom_minimum_size.x = 169
	time_slider.focus_mode = Control.FOCUS_NONE
	time_slider.value_changed.connect(set_hour)
	first.add_child(time_slider)
	for item: Array in [["朝",7.0],["昼",12.0],["夕",17.0],["夜",22.0]]:
		_button(first,item[0],func() -> void: set_hour(item[1]))
	play_button = _button(first,"停止",func() -> void: set_playing(not time_playing))
	var speed: OptionButton = OptionButton.new()
	speed.focus_mode = Control.FOCUS_NONE
	for value: float in [0.25,1.0,4.0]: speed.add_item("×"+str(value))
	speed.select(1)
	speed.item_selected.connect(func(index: int) -> void: time_speed=[0.25,1.0,4.0][index])
	first.add_child(speed)
	var compass: Label = Label.new()
	compass.text = "N↑ E→ S↓ W←"
	first.add_child(compass)
	var second: HBoxContainer = HBoxContainer.new()
	rows.add_child(second)
	follow_button = _button(second,"全景 [F]",toggle_camera)
	_button(second,"＋",func() -> void: zoom(0.85))
	_button(second,"−",func() -> void: zoom(1/0.85))
	_button(second,"開始地点 [R]",reset_position)
	hud = Label.new()
	second.add_child(hud)
	var footer: Label = Label.new()
	footer.position = Vector2(7,342)
	footer.add_theme_font_size_override("font_size",10)
	footer.text = "WASD/矢印:歩行　昼夜120秒/周　夜の月光・主街灯の人影は近似　水たまりは歩行可"
	add_child(footer)

func set_hour(value: float) -> void:
	hour = fposmod(value,24)
	var state: Dictionary = Cycle.state(hour)
	sun.position = state["source"]*30
	sun.look_at(Vector3.ZERO)
	sun.visible = state["sun_elevation"]>0 and state["sun_power"]>0.0001
	sun.light_energy = 1.5*state["sun_power"]
	sun.light_color = state["sun_color"]
	moon.position = state["moon_source"]*30
	moon.look_at(Vector3.ZERO)
	moon.light_energy = 0.16*state["night"]
	moon.visible = moon.position.y>0 and moon.light_energy>0.001
	environment.ambient_light_color = state["ambient_color"]
	environment.ambient_light_energy = state["ambient_energy"]
	environment.background_color = Color("172334").lerp(Color("566259"),state["daylight"])
	for i: int in range(lamps.size()):
		lamps[i].light_energy = 3.3*state["night"]
		lamps[i].visible = lamps[i].light_energy>0.002
		lamp_materials[i].emission_energy_multiplier = 1.9*state["night"]
	if water!=null:
		water.material_.set_shader_parameter("daylight",state["daylight"])
		water.material_.set_shader_parameter("sun_enabled",sun.visible)
	if time_slider!=null: time_slider.set_value_no_signal(hour)
	_update_hud()
	if actor!=null: _update_actor(0)

func advance_time(seconds: float) -> void:
	if time_playing: set_hour(hour+seconds*24/cycle_seconds*time_speed)

func set_playing(value: bool) -> void:
	time_playing = value
	play_button.text = "停止" if value else "再生"

func toggle_camera() -> void:
	follow = not follow
	follow_button.text = "全景 [F]" if follow else "追従 [F]"
	_update_camera()

func zoom(factor: float) -> void:
	if follow: follow_size=clampf(follow_size*factor,11,32)
	else: overview_size=clampf(overview_size*factor,35,75)
	_update_camera()
	_update_actor(0)

func reset_position() -> void:
	position = START
	follow = true
	follow_button.text = "全景 [F]"
	_update_camera()
	_update_actor(0)

func _update_camera() -> void:
	camera.size = follow_size if follow else overview_size
	var target: Vector3 = Vector3(position.x,1.2,position.y) if follow else Vector3(0,4.6,0)
	var pixel: float = camera.size/360
	var up: Vector3 = Vector3(-0.35355339,0.8660254,-0.35355339)
	target += RIGHT*(snappedf(target.dot(RIGHT),pixel)-target.dot(RIGHT))
	target += up*(snappedf(target.dot(up),pixel)-target.dot(up))
	camera.position = target+Vector3(30,30*sqrt(2.0/3.0),30)
	camera.look_at(target)
	if water!=null: water.sync_camera()
	_update_hud()

func _update_actor(delta: float) -> void:
	var directional: DirectionalLight3D = sun if sun.visible else moon
	actor.pose(Vector3(position.x,0.04,position.y),int(animation_time*6)%4 if walking else 1,facing_left,directional,lamps,delta)

func _update_hud() -> void:
	if hud!=null:
		clock_label.text = "%02d:%02d"%[floori(hour),floori(fposmod(hour,1)*60)]
		hud.text = "7棟 / 4水面　%s %.1fm"%["追従" if follow else "全景",camera.size]

func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key: InputEventKey = event as InputEventKey
		var code: int = key.physical_keycode if key.physical_keycode!=0 else key.keycode
		if not key.pressed: keys.erase(code)
		elif not key.echo:
			keys[code] = true
			if code==KEY_F: toggle_camera()
			if code==KEY_R: reset_position()

func _notification(what: int) -> void:
	if what==NOTIFICATION_APPLICATION_FOCUS_OUT: keys.clear()

func step(delta: float) -> void:
	var input_: Vector2 = Vector2(float(keys.has(KEY_D) or keys.has(KEY_RIGHT))-float(keys.has(KEY_A) or keys.has(KEY_LEFT)),float(keys.has(KEY_S) or keys.has(KEY_DOWN))-float(keys.has(KEY_W) or keys.has(KEY_UP))).limit_length(1)
	var ground: Vector3 = RIGHT*input_.x+DOWN*input_.y
	var motion: Vector2 = move_world(Vector2(ground.x,ground.z)*SPEED*delta)
	walking = motion.length_squared()>0.000001
	if walking:
		animation_time += delta
		if input_.x!=0: facing_left=input_.x<0
	advance_time(delta)
	_update_camera()
	_update_actor(delta)

func _physics_process(delta: float) -> void:
	if automatic: step(delta)

func wait_render() -> void:
	for i: int in range(5):
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
