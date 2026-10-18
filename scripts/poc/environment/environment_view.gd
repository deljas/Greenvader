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
## WTH-01 optional weather display (rain overlay, cloud shadows); fed with the weather levels and the day state on every sync.
var weather_view: Node
## Last weather levels applied (observability / tests): {type, overcast, rain, ...}.
var last_weather: Dictionary = {}
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
	var weather: Dictionary = session.weather.levels_at(session.clock.elapsed)
	last_weather = weather
	var wl: Dictionary = session.weather.tuning.get("light", {})
	var overcast: float = float(weather["overcast"])
	var rain: float = float(weather["rain"])
	var sun_mul: float = clampf(1.0 - overcast * float(wl.get("sun_cloud", 0.5)) - rain * float(wl.get("sun_rain", 0.18)), 0.0, 1.0)
	var ambient_mul: float = clampf(1.0 - overcast * float(wl.get("ambient_cloud", 0.1)) - rain * float(wl.get("ambient_rain", 0.1)), 0.0, 1.0)
	var grey: Color = Color(String(wl.get("overcast_color", "8a97a3")))
	var grey_mix: float = overcast * float(wl.get("overcast_color_mix", 0.45))
	var background_mul: float = clampf(1.0 - overcast * float(wl.get("background_dim", 0.18)) - rain * 0.08, 0.0, 1.0)
	var source: Vector3 = day["moon_source"] if is_moon else day["source"]
	key_light.global_transform = Transform3D(Basis.looking_at(-source, Vector3.UP), Vector3(0.0, 10.0, 0.0))
	if is_moon:
		key_light.light_color = Color(String(light_tuning.get("moon_color", "90b5e0")))
		key_light.light_energy = float(light_tuning.get("moon_energy", 0.16)) * float(day["moon_power"]) * lerpf(1.0, 0.6, minf(overcast, 1.0))
	else:
		key_light.light_color = (day["sun_color"] as Color).lerp(grey, grey_mix)
		key_light.light_energy = float(light_tuning.get("sun_energy", 0.8)) * float(day["sun_power"]) * sun_mul
	var daylight: float = float(day["daylight"])
	environment.ambient_light_color = Color(String(ambient.get("night_color", "6b85b5"))).lerp(Color(String(ambient.get("day_color", "9fadb8"))), daylight).lerp(grey, grey_mix * daylight)
	environment.ambient_light_energy = lerpf(float(ambient.get("night_energy", 0.22)), float(ambient.get("day_energy", 0.55)), daylight) * ambient_mul
	var background: Color = Color(String(ambient.get("night_background", "172334"))).lerp(Color(String(ambient.get("day_background", "29332f"))), daylight)
	environment.background_color = Color(background.r * background_mul, background.g * background_mul, background.b * background_mul)
	if water != null:
		water.set_daylight(daylight)
		water.set_weather(overcast, rain, session.clock.elapsed)
	if weather_view != null:
		weather_view.apply(weather, day, session.clock.elapsed)
	if readability != null:
		readability.apply(day)
		readability.sync_enemies(session.enemies.boars if session.enemies != null else [])

func hour_text() -> String:
	return "%s（%s）" % [Day.clock_text(float(last_state.get("hour", 0.0))), Day.phase_label(last_state)]

func weather_text() -> String:
	return session.weather_text()
