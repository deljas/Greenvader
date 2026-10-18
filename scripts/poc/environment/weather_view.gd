extends Node3D
## WTH-01 weather display (nothing here is game state): the cloud shadows (a dynamic dark-patch quad on the ground, world-space
## noise driven by the game clock) and the rain streaks (a screen-space overlay on an integer pixel grid, sizes proportional to the
## render resolution). No full-screen blur, no refraction, no distortion, no outline. Fed by EnvironmentView.sync().
const CloudShader: Shader = preload("res://scripts/poc/environment/cloud_shadow.gdshader")
const RainShader: Shader = preload("res://scripts/poc/environment/rain_screen.gdshader")

var camera: Camera3D
var rain_rect: ColorRect
var tuning: Dictionary = {}
var cloud_tuning: Dictionary = {}
var rain_tuning: Dictionary = {}
var cloud_mesh: MeshInstance3D
var cloud_material: ShaderMaterial
var rain_material: ShaderMaterial
var rain_time: float = 0.0
var session: RefCounted
var resolution: Vector2i = Vector2i(640, 360)
## Last applied values (observability / tests).
var last_cloud_strength: float = 0.0
var last_rain_intensity: float = 0.0

func setup(session_: RefCounted, camera_: Camera3D, rain_rect_: ColorRect) -> void:
	session = session_
	camera = camera_
	rain_rect = rain_rect_
	tuning = session.weather.tuning
	var display: Dictionary = tuning.get("display", {})
	cloud_tuning = display.get("cloud_shadow", {})
	rain_tuning = display.get("rain_streaks", {})
	var extent: float = float(cloud_tuning.get("extent_m", 56.0))
	cloud_material = ShaderMaterial.new()
	cloud_material.shader = CloudShader
	cloud_material.set_shader_parameter("darkness", float(cloud_tuning.get("darkness", 0.42)))
	cloud_material.set_shader_parameter("scale_m", float(cloud_tuning.get("scale_m", 11.0)))
	var wind: Array = cloud_tuning.get("speed_mps", [0.55, 0.3])
	cloud_material.set_shader_parameter("wind", Vector2(float(wind[0]), float(wind[1])))
	cloud_material.set_shader_parameter("steps", float(cloud_tuning.get("steps", 4)))
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(extent, extent)
	cloud_mesh = MeshInstance3D.new()
	cloud_mesh.name = "CloudShadow"
	cloud_mesh.mesh = plane
	cloud_mesh.material_override = cloud_material
	cloud_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	cloud_mesh.layers = 32 # the main camera only (the water reflection camera sees layer 1)
	cloud_mesh.visible = false
	add_child(cloud_mesh)
	if rain_rect != null:
		rain_material = ShaderMaterial.new()
		rain_material.shader = RainShader
		rain_material.set_shader_parameter("cell_px", float(rain_tuning.get("cell_px", 12)))
		rain_material.set_shader_parameter("length_px", float(rain_tuning.get("length_px", 8)))
		rain_material.set_shader_parameter("speed_px_s", float(rain_tuning.get("speed_px_s", 220.0)))
		rain_material.set_shader_parameter("density", float(rain_tuning.get("density", 0.32)))
		rain_material.set_shader_parameter("slant", float(rain_tuning.get("slant", 0.35)))
		rain_material.set_shader_parameter("drop_alpha", float(rain_tuning.get("alpha", 0.5)))
		rain_material.set_shader_parameter("drop_color", Color(String(rain_tuning.get("color", "c8dcf0"))))
		rain_rect.material = rain_material
		rain_rect.visible = false
	set_resolution(resolution)

## Streak sizes follow the render resolution (1x at 640, 1.5x at 960); the grid step is a whole number of render pixels.
func set_resolution(size: Vector2i) -> void:
	resolution = size
	if rain_material != null:
		var scale_: float = float(size.x) / 640.0
		rain_material.set_shader_parameter("rect_size", Vector2(size))
		rain_material.set_shader_parameter("res_scale", scale_)
		rain_material.set_shader_parameter("unit", ceilf(scale_))

func _process(delta: float) -> void:
	if session != null and not session.paused:
		rain_time += delta

func _ground_focus() -> Vector3:
	var eye: Vector3 = camera.global_position
	var forward: Vector3 = -camera.global_basis.z
	if forward.y > -0.0001:
		return Vector3(eye.x, 0.0, eye.z)
	var t: float = -eye.y / forward.y
	return Vector3(eye.x + forward.x * t, 0.0, eye.z + forward.z * t)

func apply(weather: Dictionary, day: Dictionary, elapsed: float) -> void:
	var overcast: float = float(weather["overcast"])
	var rain: float = float(weather["rain"])
	# Cloud shadows need sun: gone at night, thin under a covered sky and in rain.
	var strength: float = float(day["sun_power"]) * (1.0 - 0.2 * overcast - 0.45 * rain)
	last_cloud_strength = strength
	cloud_mesh.visible = strength > 0.01
	if cloud_mesh.visible:
		var focus: Vector3 = _ground_focus()
		cloud_mesh.global_position = Vector3(roundf(focus.x), float(cloud_tuning.get("height_m", 0.012)), roundf(focus.z))
		cloud_material.set_shader_parameter("strength", strength)
		cloud_material.set_shader_parameter("coverage", lerpf(float(cloud_tuning.get("coverage_clear", 0.5)), float(cloud_tuning.get("coverage_cloudy", 0.72)), overcast))
		cloud_material.set_shader_parameter("shadow_time", elapsed)
	last_rain_intensity = rain
	if rain_rect != null:
		rain_rect.visible = rain > 0.01
		if rain_rect.visible:
			rain_material.set_shader_parameter("intensity", rain)
			rain_material.set_shader_parameter("rain_time", rain_time)
