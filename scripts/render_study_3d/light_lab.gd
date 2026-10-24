extends "res://scripts/render_study_3d/sprite_shadow_lab.gd"
## Interactive light study. World=layer1, sun card=layer2, point card=layer3.
const WORLD_LAYER: int = 1
const SUN_CARD_LAYER: int = 2
const POINT_CARD_LAYER: int = 4
var sun_enabled: bool = true
var sun_azimuth: float = 320.1944
var sun_elevation: float = 52.0
var point_enabled: bool = true
var orbit_running: bool = true
var orbit_angle: float = 45.0
var orbit_speed: float = 90.0
var point_light: OmniLight3D
var point_marker: MeshInstance3D
var point_board: Sprite3D
var azimuth_slider: HSlider
var azimuth_spin: SpinBox
var elevation_slider: HSlider
var elevation_spin: SpinBox
var orbit_slider: HSlider
var orbit_spin: SpinBox
var sun_check: CheckBox
var point_check: CheckBox
var orbit_check: CheckBox
var sun_status: Label
var ui_panel: Panel

func _ready() -> void:
	super._ready()
	get_window().title = "グリーンベーダー｜太陽角度と周回点光源"
	shadow_board.layers = SUN_CARD_LAYER
	study.sun.light_cull_mask = WORLD_LAYER | SUN_CARD_LAYER | POINT_CARD_LAYER
	study.sun.shadow_caster_mask = WORLD_LAYER | SUN_CARD_LAYER
	var direction: Vector3 = study.sun.global_basis.z
	sun_azimuth = fposmod(rad_to_deg(atan2(direction.x,direction.z)),360.0)
	sun_elevation = rad_to_deg(asin(clampf(direction.y,-1.0,1.0)))
	point_light = OmniLight3D.new()
	point_light.name = "OrbitPointLight"
	point_light.light_color = Color("a9d8ff")
	point_light.light_energy = 5.0
	point_light.omni_range = 11.0
	point_light.omni_attenuation = 1.15
	point_light.shadow_enabled = true
	point_light.shadow_blur = 1.0
	point_light.shadow_bias = 0.10
	point_light.shadow_normal_bias = 1.0
	point_light.light_cull_mask = WORLD_LAYER | SUN_CARD_LAYER | POINT_CARD_LAYER
	point_light.shadow_caster_mask = WORLD_LAYER | POINT_CARD_LAYER
	study.world.add_child(point_light)
	RenderingServer.positional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_HARD)
	point_board = _sprite("PointLightShadowOnly", GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY)
	point_board.layers = POINT_CARD_LAYER
	point_marker = MeshInstance3D.new()
	point_marker.name = "NonShadowingPointMarker"
	var sphere: SphereMesh = SphereMesh.new()
	sphere.radius = 0.085
	sphere.height = 0.17
	point_marker.mesh = sphere
	point_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var marker_material: StandardMaterial3D = StandardMaterial3D.new()
	marker_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	marker_material.albedo_color = Color("b6e4ff")
	point_marker.material_override = marker_material
	study.world.add_child(point_marker)
	_build_light_ui()
	set_sun_angles(sun_azimuth,sun_elevation)
	set_orbit_angle(orbit_angle)

func _process(delta: float) -> void:
	super._process(delta)
	if point_light != null:
		if orbit_running:
			set_orbit_angle(orbit_angle + orbit_speed * delta)
		_sync_point_board()

func apply_pose(index: int, flip: bool, logical_foot: Vector3) -> void:
	super.apply_pose(index,flip,logical_foot)
	# super._ready invokes the virtual pose method before point construction.
	if point_board != null and point_light != null:
		_sync_point_board()

func _sync_point_board() -> void:
	var normal: Vector3 = point_light.global_position - render_foot
	normal.y = 0.0
	if normal.length_squared() < 0.000001:
		normal = Vector3.FORWARD
	normal = normal.normalized()
	point_board.global_basis = Basis(Vector3.UP.cross(normal),Vector3.UP,normal)
	point_board.global_position = render_foot + Vector3.UP * (48.0 * pixel_world * 0.5)
	point_board.texture = textures[frame_index]
	point_board.flip_h = flipped

func set_sun_angles(azimuth: float, elevation: float) -> void:
	sun_azimuth = clampf(azimuth,0.0,360.0)
	sun_elevation = clampf(elevation,-90.0,90.0)
	# Euler basis is finite even at +/-90, without look_at parallel-to-up.
	study.sun.global_basis = Basis.from_euler(Vector3(-deg_to_rad(sun_elevation),deg_to_rad(sun_azimuth),0.0))
	study.sun.visible = sun_enabled and sun_elevation > 0.0
	apply_pose(frame_index,flipped,render_foot)
	_sync_ui()

func set_sun_enabled(value: bool) -> void:
	sun_enabled = value
	set_sun_angles(sun_azimuth,sun_elevation)

func set_point_enabled(value: bool) -> void:
	point_enabled = value
	point_light.visible = value
	point_marker.visible = value
	_sync_ui()

func set_orbit_running(value: bool) -> void:
	orbit_running = value
	_sync_ui()

func set_orbit_angle(value: float) -> void:
	orbit_angle = fposmod(value,360.0)
	var radians: float = deg_to_rad(orbit_angle)
	point_light.position = Vector3(sin(radians)*5.3,2.4,cos(radians)*4.6)
	point_marker.position = point_light.position
	_sync_point_board()
	_sync_ui()

func _sync_ui() -> void:
	if azimuth_slider == null:
		return
	azimuth_slider.set_value_no_signal(sun_azimuth)
	azimuth_spin.set_value_no_signal(sun_azimuth)
	elevation_slider.set_value_no_signal(sun_elevation)
	elevation_spin.set_value_no_signal(sun_elevation)
	orbit_slider.set_value_no_signal(orbit_angle)
	orbit_spin.set_value_no_signal(orbit_angle)
	sun_check.set_pressed_no_signal(sun_enabled)
	point_check.set_pressed_no_signal(point_enabled)
	orbit_check.set_pressed_no_signal(orbit_running)
	sun_status.text = "直射OFF（仰角 ≤ 0）" if sun_elevation <= 0.0 else ("直射ON" if sun_enabled else "直射OFF（スイッチ）")

func _build_light_ui() -> void:
	var font: SystemFont = SystemFont.new()
	font.font_names = PackedStringArray(["Yu Gothic UI","Meiryo"])
	var theme: Theme = Theme.new()
	theme.default_font = font
	theme.default_font_size = 11
	ui_panel = Panel.new()
	ui_panel.position = Vector2(6,34)
	ui_panel.size = Vector2(158,298)
	ui_panel.theme = theme
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.07,0.11,0.10,0.94)
	ui_panel.add_theme_stylebox_override("panel",style)
	add_child(ui_panel)
	var title: Label = Label.new()
	title.text = "太陽角度 / 周回する点光源"
	title.position = Vector2(12,7)
	title.theme = theme
	title.add_theme_font_size_override("font_size",13)
	add_child(title)
	_text("太陽の角度",Vector2(9,6),12)
	sun_check = _check("太陽ON",Vector2(7,24),set_sun_enabled)
	var pair: Array = _angle_row("方位角 °",49,0,360,sun_azimuth,func(v: float) -> void: set_sun_angles(v,sun_elevation))
	azimuth_slider = pair[0]
	azimuth_spin = pair[1]
	pair = _angle_row("仰角 °",92,-90,90,sun_elevation,func(v: float) -> void: set_sun_angles(sun_azimuth,v))
	elevation_slider = pair[0]
	elevation_spin = pair[1]
	sun_status = _text("",Vector2(9,138),10)
	_text("方位 0°:+Z / 90°:+X",Vector2(9,156),9)
	point_check = _check("点光源ON",Vector2(7,182),set_point_enabled)
	orbit_check = _check("自動周回",Vector2(7,207),set_orbit_running)
	pair = _angle_row("周回位置 °",234,0,360,orbit_angle,set_orbit_angle)
	orbit_slider = pair[0]
	orbit_spin = pair[1]
	_text("キャラ受光なし / 影板は近似",Vector2(9,278),9)

func _text(value: String, at: Vector2, size_: int) -> Label:
	var label: Label = Label.new()
	label.text = value
	label.position = at
	label.add_theme_font_size_override("font_size",size_)
	ui_panel.add_child(label)
	return label

func _check(value: String, at: Vector2, handler: Callable) -> CheckBox:
	var button: CheckBox = CheckBox.new()
	button.text = value
	button.position = at
	button.toggled.connect(handler)
	ui_panel.add_child(button)
	return button

func _angle_row(value: String, y: float, minimum: float, maximum: float, initial: float, handler: Callable) -> Array:
	_text(value,Vector2(9,y),11)
	var slider: HSlider = HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = 0.1
	slider.value = initial
	slider.position = Vector2(9,y+19)
	slider.size = Vector2(72,20)
	ui_panel.add_child(slider)
	var spin: SpinBox = SpinBox.new()
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = 0.1
	spin.value = initial
	spin.position = Vector2(87,y+15)
	spin.size = Vector2(64,24)
	ui_panel.add_child(spin)
	slider.value_changed.connect(handler)
	spin.value_changed.connect(handler)
	return [slider,spin]

func light_snapshot() -> Dictionary:
	var snapshot: Dictionary = sync_snapshot()
	var point_foot: Vector3 = point_board.global_position - Vector3.UP * (48.0*pixel_world*0.5)
	snapshot["point_texture_match"] = point_board.texture == display_sprite.texture
	snapshot["point_flip_match"] = point_board.flip_h == display_sprite.flip_h
	snapshot["point_foot_match"] = point_foot.distance_to(render_foot) < 0.00001
	snapshot["sun_basis_finite"] = study.sun.global_basis.is_finite() and shadow_board.global_basis.is_finite()
	snapshot["point_basis_finite"] = point_board.global_basis.is_finite()
	snapshot["azimuth"] = sun_azimuth
	snapshot["elevation"] = sun_elevation
	snapshot["direct_sun"] = study.sun.visible
	snapshot["orbit_angle"] = orbit_angle
	snapshot["point_position"] = point_light.position
	return snapshot
