extends Node
## POC-05 lighting from the single game clock. Drives the one key DirectionalLight3D (the hard-shadow caster): the sun by day,
## the moon at night, so every sprite shadow board that follows that light stays in sync round the clock. Also sets the
## ambient light and background. The hour is recomputed from session.clock.elapsed on every sync (no state of its own except
## the last values, kept for observability).
const Day: GDScript = preload("res://scripts/poc/environment/poc_day.gd")

var session: RefCounted
var environment: Environment
var key_light: DirectionalLight3D
var water: Node
## POL-01 optional readability aids (marker, night lights); fed with the day state on every sync.
var readability: Node
var tuning: Dictionary = {}
## Last applied values (observability / tests).
var last_state: Dictionary = {}
var last_is_moon: bool = false

func setup(source: RefCounted, environment_: Environment, light: DirectionalLight3D, water_view: Node) -> void:
	session = source
	environment = environment_
	key_light = light
	water = water_view
	tuning = session.env_tuning
	sync()

func sync() -> void:
	var day: Dictionary = Day.state(session.day_hour(), tuning)
	last_state = day
	var light_tuning: Dictionary = tuning.get("light", {})
	var ambient: Dictionary = tuning.get("ambient", {})
	var is_moon: bool = float(day["altitude"]) <= 0.0
	last_is_moon = is_moon
	var source: Vector3 = day["moon_source"] if is_moon else day["source"]
	key_light.global_transform = Transform3D(Basis.looking_at(-source, Vector3.UP), Vector3(0.0, 10.0, 0.0))
	if is_moon:
		key_light.light_color = Color(String(light_tuning.get("moon_color", "90b5e0")))
		key_light.light_energy = float(light_tuning.get("moon_energy", 0.16)) * float(day["moon_power"])
	else:
		key_light.light_color = day["sun_color"]
		key_light.light_energy = float(light_tuning.get("sun_energy", 0.8)) * float(day["sun_power"])
	var daylight: float = float(day["daylight"])
	environment.ambient_light_color = Color(String(ambient.get("night_color", "6b85b5"))).lerp(Color(String(ambient.get("day_color", "9fadb8"))), daylight)
	environment.ambient_light_energy = lerpf(float(ambient.get("night_energy", 0.22)), float(ambient.get("day_energy", 0.55)), daylight)
	environment.background_color = Color(String(ambient.get("night_background", "172334"))).lerp(Color(String(ambient.get("day_background", "29332f"))), daylight)
	if water != null:
		water.set_daylight(daylight)
	if readability != null:
		readability.apply(day)

func hour_text() -> String:
	return "%s（%s）" % [Day.clock_text(float(last_state.get("hour", 0.0))), Day.phase_label(last_state)]
