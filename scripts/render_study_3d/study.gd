extends Node
## Isolated GPU 3D -> 960x540 -> nearest 2x. No simulation/game-state dependency.
const Geometry: GDScript = preload("res://scripts/render_study_3d/ruin_geometry.gd")
const INTERNAL: Vector2i = Vector2i(960, 540)
const OUTPUT: Vector2i = Vector2i(1920, 1080)
const TARGET: Vector3 = Vector3(0, 0.8, 0)
const CAMERA_HOME: Vector3 = TARGET + Vector3(14.0, 14.0 * sqrt(2.0/3.0), 14.0)
const TIMES: Array[Dictionary] = [
	{"id":"morning", "title":"朝", "sun":Vector3(8,4.0,-6), "color":Color(1.0,0.87,0.70), "energy":1.25},
	{"id":"noon", "title":"昼", "sun":Vector3(-5,10,6), "color":Color(1.0,0.98,0.90), "energy":1.35},
	{"id":"evening", "title":"夕", "sun":Vector3(-8,3.2,5), "color":Color(1.0,0.70,0.44), "energy":1.15}
]
var render_view: SubViewport
var doubled_view: SubViewport
var world: Node3D
var camera: Camera3D
var sun: DirectionalLight3D
var time_index: int = 1
var title_label: Label
var parts: Dictionary

func _ready() -> void:
	var window: Window = get_window()
	window.title = "グリーンベーダー｜3D材質と時刻別の影"
	window.content_scale_size = INTERNAL
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	window.content_scale_stretch = Window.CONTENT_SCALE_STRETCH_INTEGER
	window.min_size = INTERNAL
	window.size = OUTPUT
	render_view = SubViewport.new()
	render_view.name = "Actual3DAt960"
	render_view.size = INTERNAL
	render_view.own_world_3d = true
	render_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	render_view.msaa_3d = Viewport.MSAA_DISABLED
	render_view.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	render_view.use_taa = false
	render_view.use_debanding = false
	add_child(render_view)
	world = Node3D.new()
	render_view.add_child(world)
	parts = Geometry.build(world)
	_build_environment()
	camera = Camera3D.new()
	camera.name = "OrthogonalYaw45Pitch30"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.size = 10.2
	camera.near = 0.1
	camera.far = 80.0
	world.add_child(camera)
	camera.position = CAMERA_HOME
	camera.look_at(TARGET)
	camera.current = true
	doubled_view = SubViewport.new()
	doubled_view.name = "NearestGPUOutput1920"
	doubled_view.size = OUTPUT
	doubled_view.disable_3d = true
	doubled_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(doubled_view)
	_texture_rect(doubled_view, render_view.get_texture(), OUTPUT)
	_texture_rect(self, render_view.get_texture(), INTERNAL)
	_build_ui()
	set_time(1)
	if OS.get_cmdline_user_args().has("--capture"):
		_capture_user.call_deferred()

func _build_environment() -> void:
	var env: Environment = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("687465")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("b4c4cc")
	env.ambient_light_energy = 0.42
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.ssao_enabled = false
	env.ssil_enabled = false
	env.sdfgi_enabled = false
	env.glow_enabled = false
	env.fog_enabled = false
	var we: WorldEnvironment = WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	sun = DirectionalLight3D.new()
	sun.name = "RealTimeSun"
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 42.0
	sun.shadow_bias = 0.035
	sun.shadow_normal_bias = 0.45
	sun.light_angular_distance = 0.0
	world.add_child(sun)

func set_time(index: int) -> void:
	time_index = clampi(index, 0, 2)
	var settings: Dictionary = TIMES[time_index]
	var sun_position: Vector3 = settings["sun"]
	sun.position = sun_position
	sun.look_at(Vector3.ZERO)
	sun.light_color = settings["color"]
	sun.light_energy = settings["energy"]
	if title_label != null:
		title_label.text = "3D描画試作　" + String(settings["title"]) + "　｜　1 朝　2 昼　3 夕"

func _texture_rect(parent: Node, tex: Texture2D, pixels: Vector2i) -> void:
	var rect: TextureRect = TextureRect.new()
	rect.texture = tex
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	rect.size = pixels
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(rect)

func _build_ui() -> void:
	var panel: ColorRect = ColorRect.new()
	panel.color = Color(0.08,0.12,0.11,0.90)
	panel.size = Vector2(960,34)
	add_child(panel)
	var font: SystemFont = SystemFont.new()
	font.font_names = PackedStringArray(["Yu Gothic UI","Meiryo"])
	title_label = Label.new()
	title_label.position = Vector2(16,7)
	title_label.add_theme_font_override("font",font)
	title_label.add_theme_font_size_override("font_size",15)
	add_child(title_label)
	for i: int in 3:
		var button: Button = Button.new()
		button.text = ["朝","昼","夕"][i]
		button.position = Vector2(774+i*58,4)
		button.size = Vector2(52,26)
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_font_override("font",font)
		button.pressed.connect(set_time.bind(i))
		add_child(button)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key: InputEventKey = event as InputEventKey
		if key.keycode >= KEY_1 and key.keycode <= KEY_3:
			set_time(key.keycode - KEY_1)

func wait_render() -> void:
	for i: int in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw

func save_views(folder: String, label_: String) -> Dictionary:
	await wait_render()
	var image: Image = render_view.get_texture().get_image()
	var doubled: Image = doubled_view.get_texture().get_image()
	var first: Error = image.save_png(folder.path_join(label_ + "_960.png"))
	var second: Error = doubled.save_png(folder.path_join(label_ + "_1920.png"))
	return {"source":image,"doubled":doubled,"ok":first == OK and second == OK}

func _capture_user() -> void:
	var folder: String = "res://evidence/render-study-3d/self/manual-capture"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	for i: int in 3:
		set_time(i)
		await save_views(folder, String(TIMES[i]["id"]))
	set_time(1)
	print("3D capture saved to " + ProjectSettings.globalize_path(folder))
