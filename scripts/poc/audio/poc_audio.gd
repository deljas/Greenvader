extends Node
## WTH-02 PoC sound: short action sounds and ambient loops, all synthesised in code (no external material; origin "self made, code
## generated"). Display/effect only: it reads the session and listens to its signals, it never writes to it, and nothing here
## feeds back into the simulation. Tuning in data/poc/audio.json; the mute choice (M key) is kept in user://poc_ui_settings.json.
## Action sounds: seed, water, place, pickup, hit, nest, zone, clear. Ambient: wind (always, small), rain (follows the rain level),
## birds (more often the greener the town). While calm (pause / menu / viewpoint) ambient is softened and action sounds are dropped.
const TUNING_PATH: String = "res://data/poc/audio.json"
const RATE: int = 22050
const ACTIONS: Array[StringName] = [&"seed", &"water", &"place", &"pickup", &"hit", &"nest", &"zone", &"clear"]
const POOL_SIZE: int = 6
const LOG_LIMIT: int = 256
## Where the UI setting (mute) is kept; tests point it elsewhere.
static var settings_path: String = "user://poc_ui_settings.json"
static var _stream_cache: Dictionary = {}

## Tests point the UI setting file elsewhere.
static func use_settings_path(path: String) -> void:
	settings_path = path

var tuning: Dictionary = {}
var muted: bool = false
## Action sounds actually started, in order (capped); tests read it as the "what was requested" hook.
var requested: Array[StringName] = []
var started_count: int = 0
var dropped_muted: int = 0
var dropped_calm: int = 0
var bird_count: int = 0
## Returns true while the game is paused / a menu or the viewpoint is shown. Set by PocMain.
var calm_provider: Callable = Callable()
var _session: RefCounted
var _connections: Array[Array] = []
var _pool: Array[AudioStreamPlayer] = []
var _wind: AudioStreamPlayer
var _rain: AudioStreamPlayer
var _bird_pool: Array[AudioStreamPlayer] = []
var _bird_wait: float = 6.0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _last_seeds: int = 0
var _bird_turn: int = 0
## Last computed linear volumes (observability): wind, rain, birds (0 when muted).
var last_levels: Dictionary = {"wind": 0.0, "rain": 0.0, "birds": 0.0, "action": 0.0}

static func load_tuning(path: String = TUNING_PATH) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}

func _init(tuning_: Dictionary = {}) -> void:
	name = "PocAudio"
	tuning = tuning_ if not tuning_.is_empty() else load_tuning()
	muted = bool(tuning.get("muted", false))
	var saved: Variant = null
	if FileAccess.file_exists(settings_path):
		saved = JSON.parse_string(FileAccess.get_file_as_string(settings_path))
	if saved is Dictionary and (saved as Dictionary).has("muted"):
		muted = bool((saved as Dictionary)["muted"])
	_rng.seed = int((tuning.get("birds", {}) as Dictionary).get("seed", 1))
	_build_streams()
	for i: int in POOL_SIZE:
		_pool.append(_make_player("Action%d" % i))
	for i: int in 2:
		_bird_pool.append(_make_player("Bird%d" % i))
	_wind = _make_player("Wind")
	_wind.stream = _stream_cache["wind"]
	_rain = _make_player("Rain")
	_rain.stream = _stream_cache["rain"]

func _ready() -> void:
	_apply_ambient(0.0, 0.0, false)

func _make_player(player_name: String) -> AudioStreamPlayer:
	var player: AudioStreamPlayer = AudioStreamPlayer.new()
	player.name = player_name
	player.volume_db = -80.0
	add_child(player)
	return player

# ---------------------------------------------------------------- settings

func toggle_mute() -> bool:
	set_muted(not muted)
	return muted

func set_muted(value: bool) -> void:
	muted = value
	if muted:
		for player: AudioStreamPlayer in _pool + _bird_pool:
			player.stop()
	_apply_ambient(0.0, 0.0, false)
	_write_settings()

func _write_settings() -> void:
	var file: FileAccess = FileAccess.open(settings_path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"muted": muted}))
		file.close()

func master() -> float:
	return clampf(float(tuning.get("master", 0.8)), 0.0, 1.0)

func category_gain(category: String) -> float:
	return 0.0 if muted else master() * clampf(float((tuning.get("categories", {}) as Dictionary).get(category, 1.0)), 0.0, 1.0)

func is_calm() -> bool:
	return calm_provider.is_valid() and bool(calm_provider.call())

static func _db(linear: float) -> float:
	return linear_to_db(linear) if linear > 0.0005 else -80.0

# ---------------------------------------------------------------- session hooks

## Listens to the events of `session` (replaces the previous session's hooks).
func attach(session: RefCounted) -> void:
	detach()
	_session = session
	_last_seeds = session.play.seeds
	_hook(session.play.seeds_changed, _on_seeds_changed)
	_hook(session.projectiles.enemy_hit, _on_enemy_hit)
	if session.enemies != null:
		_hook(session.enemies.nest_defeated, _on_nest_defeated)
	_hook(session.state.zone_state_changed, _on_zone_state_changed)
	if session.zone_progress != null:
		_hook(session.zone_progress.cleared, _on_cleared)

func detach() -> void:
	for pair: Array in _connections:
		var sig: Signal = pair[0]
		if sig.is_connected(pair[1]):
			sig.disconnect(pair[1])
	_connections.clear()
	_session = null

func _hook(sig: Signal, callable: Callable) -> void:
	sig.connect(callable)
	_connections.append([sig, callable])

func _on_seeds_changed(count: int) -> void:
	if count > _last_seeds:
		play_action(&"pickup")
	_last_seeds = count

func _on_enemy_hit(_kind: String, _point: Vector2, _info: Dictionary) -> void:
	play_action(&"hit")

func _on_nest_defeated(_nest: Variant) -> void:
	play_action(&"nest")

func _on_zone_state_changed(_zone: int, old_state: int, new_state: int) -> void:
	if new_state > old_state:
		play_action(&"zone")

func _on_cleared() -> void:
	play_action(&"clear")

# ---------------------------------------------------------------- playing

## Starts an action sound. Returns false when it was dropped (muted, calm, unknown).
func play_action(sound: StringName) -> bool:
	if not _stream_cache.has(String(sound)) or not ACTIONS.has(sound):
		return false
	if muted:
		dropped_muted += 1
		return false
	if is_calm():
		dropped_calm += 1
		return false
	var player: AudioStreamPlayer = _pool[0]
	for candidate: AudioStreamPlayer in _pool:
		if not candidate.playing:
			player = candidate
			break
	var gain: float = category_gain("action") * float((tuning.get("action_gain", {}) as Dictionary).get(String(sound), 1.0))
	player.stream = _stream_cache[String(sound)]
	player.volume_db = _db(gain)
	if is_inside_tree():
		player.play()
	requested.append(sound)
	if requested.size() > LOG_LIMIT:
		requested.remove_at(0)
	started_count += 1
	last_levels["action"] = gain
	return true

## Per frame: ambient levels from the session (wind always, rain with the rain level, birds with the greening).
func update(delta: float) -> void:
	if _session == null:
		_apply_ambient(0.0, 0.0, is_calm())
		return
	var levels: Dictionary = _session.weather.levels_at(_session.clock.elapsed)
	var calm: bool = is_calm()
	_apply_ambient(float(levels["overcast"]), float(levels["rain"]), calm)
	if calm or muted:
		return
	var birds: Dictionary = tuning.get("birds", {})
	var start: float = float(birds.get("start_percent", 5))
	var full: float = maxf(float(birds.get("full_percent", 100)), start + 1.0)
	var percent: float = float(_session.greening_percent())
	if percent < start:
		return
	_bird_wait -= delta
	if _bird_wait > 0.0:
		return
	var amount: float = clampf((percent - start) / (full - start), 0.0, 1.0)
	var interval: float = lerpf(float(birds.get("interval_s_at_start", 18.0)), float(birds.get("interval_s_at_full", 3.5)), amount)
	_bird_wait = interval * _rng.randf_range(0.7, 1.3)
	_play_bird(category_gain("birds"))

func _play_bird(gain: float) -> void:
	var player: AudioStreamPlayer = _bird_pool[_bird_turn % _bird_pool.size()]
	var variant: int = _rng.randi_range(0, 2)
	_bird_turn += 1
	player.stream = _stream_cache["bird%d" % variant]
	player.volume_db = _db(gain)
	if is_inside_tree():
		player.play()
	bird_count += 1
	last_levels["birds"] = gain

func _apply_ambient(overcast: float, rain: float, calm: bool) -> void:
	var soft: float = clampf(float(tuning.get("calm_factor", 0.25)), 0.0, 1.0) if calm else 1.0
	var wind: float = category_gain("wind") * (1.0 + float(tuning.get("overcast_wind_boost", 0.4)) * clampf(overcast, 0.0, 1.0)) * soft
	var rain_gain: float = category_gain("rain") * clampf(rain, 0.0, 1.0) * soft
	if rain < float(tuning.get("rain_min_level", 0.05)):
		rain_gain = 0.0
	wind = clampf(wind, 0.0, 1.0)
	rain_gain = clampf(rain_gain, 0.0, 1.0)
	last_levels["wind"] = wind
	last_levels["rain"] = rain_gain
	for pair: Array in [[_wind, wind], [_rain, rain_gain]]:
		var player: AudioStreamPlayer = pair[0]
		player.volume_db = _db(float(pair[1]))
		if float(pair[1]) > 0.0005:
			if not player.playing and is_inside_tree():
				player.play()
		elif player.playing:
			player.stop()

## Number of players currently producing sound (observability).
func playing_count() -> int:
	var count: int = 0
	for player: AudioStreamPlayer in _pool + _bird_pool:
		if player.playing:
			count += 1
	for player: AudioStreamPlayer in [_wind, _rain]:
		if player.playing:
			count += 1
	return count

# ---------------------------------------------------------------- synthesis

func _build_streams() -> void:
	if not _stream_cache.is_empty():
		return
	var noise: RandomNumberGenerator = RandomNumberGenerator.new()
	noise.seed = 77123
	_stream_cache["seed"] = _wav(_synth_seed())
	_stream_cache["water"] = _wav(_synth_water(noise))
	_stream_cache["place"] = _wav(_synth_place())
	_stream_cache["pickup"] = _wav(_synth_pickup())
	_stream_cache["hit"] = _wav(_synth_hit(noise))
	_stream_cache["nest"] = _wav(_synth_nest(noise))
	_stream_cache["zone"] = _wav(_synth_arpeggio([523.25, 659.25, 783.99], 0.12, 0.35))
	_stream_cache["clear"] = _wav(_synth_arpeggio([523.25, 659.25, 783.99, 1046.5, 1318.5], 0.16, 0.9))
	_stream_cache["wind"] = _wav(_synth_wind(noise), true)
	_stream_cache["rain"] = _wav(_synth_rain(noise), true)
	for i: int in 3:
		_stream_cache["bird%d" % i] = _wav(_synth_bird(i))

func _buf(seconds: float) -> PackedFloat32Array:
	var data: PackedFloat32Array = PackedFloat32Array()
	data.resize(int(seconds * float(RATE)))
	return data

## Float samples (-1..1) -> 16 bit mono AudioStreamWAV; looped streams loop over the whole buffer.
func _wav(samples: PackedFloat32Array, loop: bool = false) -> AudioStreamWAV:
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i: int in samples.size():
		bytes.encode_s16(i * 2, clampi(roundi(samples[i] * 32000.0), -32768, 32767))
	var stream: AudioStreamWAV = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = false
	stream.data = bytes
	if loop:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = samples.size()
	return stream

func _synth_seed() -> PackedFloat32Array:
	var data: PackedFloat32Array = _buf(0.09)
	var phase: float = 0.0
	for i: int in data.size():
		var t: float = float(i) / float(RATE)
		phase += TAU * (640.0 + 5800.0 * t) / float(RATE)
		data[i] = sin(phase) * pow(1.0 - t / 0.09, 2.0) * minf(t / 0.003, 1.0) * 0.5
	return data

func _synth_water(noise: RandomNumberGenerator) -> PackedFloat32Array:
	var data: PackedFloat32Array = _buf(0.22)
	var low: float = 0.0
	for i: int in data.size():
		var t: float = float(i) / float(RATE)
		low += (noise.randf_range(-1.0, 1.0) - low) * 0.22
		data[i] = low * (0.6 + 0.4 * sin(TAU * 38.0 * t)) * sin(PI * t / 0.22) * 1.3
	return data

func _synth_place() -> PackedFloat32Array:
	var data: PackedFloat32Array = _buf(0.18)
	var phase: float = 0.0
	for i: int in data.size():
		var t: float = float(i) / float(RATE)
		phase += TAU * (190.0 - 500.0 * t) / float(RATE)
		data[i] = (sin(phase) * exp(-t * 22.0) + 0.3 * sin(TAU * 420.0 * t) * exp(-t * 70.0)) * 0.7
	return data

func _synth_pickup() -> PackedFloat32Array:
	var data: PackedFloat32Array = _buf(0.2)
	for i: int in data.size():
		var t: float = float(i) / float(RATE)
		var local: float = t if t < 0.07 else t - 0.07
		var f: float = 880.0 if t < 0.07 else 1318.5
		data[i] = (sin(TAU * f * local) + 0.25 * sin(TAU * f * 2.0 * local)) * exp(-local * 22.0) * minf(local / 0.004, 1.0) * 0.4
	return data

func _synth_hit(noise: RandomNumberGenerator) -> PackedFloat32Array:
	var data: PackedFloat32Array = _buf(0.16)
	var low: float = 0.0
	for i: int in data.size():
		var t: float = float(i) / float(RATE)
		low += (noise.randf_range(-1.0, 1.0) - low) * 0.5
		data[i] = (low * exp(-t * 32.0) * 0.7 + sin(TAU * 150.0 * t) * exp(-t * 26.0) * 0.6) * 0.8
	return data

func _synth_nest(noise: RandomNumberGenerator) -> PackedFloat32Array:
	var data: PackedFloat32Array = _buf(0.7)
	var low: float = 0.0
	var phase: float = 0.0
	for i: int in data.size():
		var t: float = float(i) / float(RATE)
		low += (noise.randf_range(-1.0, 1.0) - low) * 0.16
		phase += TAU * maxf(70.0 - 60.0 * t, 38.0) / float(RATE)
		var crackle: float = 0.0
		for start: float in [0.12, 0.24, 0.36]:
			if t >= start and t < start + 0.06:
				crackle += noise.randf_range(-1.0, 1.0) * exp(-(t - start) * 60.0) * 0.5
		data[i] = (low * exp(-t * 5.0) * 0.9 + sin(phase) * exp(-t * 6.0) * 0.8 + crackle) * 0.75
	return data

func _synth_arpeggio(notes: Array, step: float, tail: float) -> PackedFloat32Array:
	var data: PackedFloat32Array = _buf(step * float(notes.size() - 1) + tail)
	for index: int in notes.size():
		var f: float = float(notes[index])
		var start: int = int(step * float(index) * float(RATE))
		var decay: float = 9.0 if index < notes.size() - 1 else 3.2
		for i: int in range(start, data.size()):
			var local: float = float(i - start) / float(RATE)
			if local > 1.6:
				break
			data[i] += (sin(TAU * f * local) + 0.3 * sin(TAU * f * 2.0 * local)) * exp(-local * decay) * minf(local / 0.005, 1.0) * 0.22
	return data

## Seamless loop: the tail is cross-faded into the head.
func _loop_fade(raw: PackedFloat32Array, length: int, fade: int) -> PackedFloat32Array:
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(length)
	for i: int in length:
		if i < fade:
			var w: float = smoothstep(0.0, 1.0, float(i) / float(fade))
			out[i] = raw[i] * w + raw[length + i] * (1.0 - w)
		else:
			out[i] = raw[i]
	return out

func _synth_wind(noise: RandomNumberGenerator) -> PackedFloat32Array:
	var length: int = RATE * 4
	var fade: int = RATE / 2
	var raw: PackedFloat32Array = PackedFloat32Array()
	raw.resize(length + fade)
	var a: float = 0.0
	var b: float = 0.0
	for i: int in raw.size():
		var t: float = float(i) / float(RATE)
		a += (noise.randf_range(-1.0, 1.0) - a) * 0.035
		b += (a - b) * 0.12
		var swell: float = 0.55 + 0.3 * sin(TAU * t / 4.0) + 0.15 * sin(TAU * 3.0 * t / 4.0 + 1.3)
		raw[i] = b * swell * 5.5
	return _loop_fade(raw, length, fade)

func _synth_rain(noise: RandomNumberGenerator) -> PackedFloat32Array:
	var length: int = RATE * 3
	var fade: int = RATE / 2
	var raw: PackedFloat32Array = PackedFloat32Array()
	raw.resize(length + fade)
	var low: float = 0.0
	for i: int in raw.size():
		var white: float = noise.randf_range(-1.0, 1.0)
		low += (white - low) * 0.35
		var value: float = (white - low) * 0.32
		if noise.randf() < 0.0016:
			value += noise.randf_range(-0.5, 0.5)
		raw[i] = value
	return _loop_fade(raw, length, fade)

func _synth_bird(variant: int) -> PackedFloat32Array:
	var chirps: int = 2 + variant
	var data: PackedFloat32Array = _buf(0.14 * float(chirps) + 0.1)
	for c: int in chirps:
		var start: float = 0.14 * float(c)
		var base: float = 2300.0 + 420.0 * float(variant) + 260.0 * float(c)
		var phase: float = 0.0
		for i: int in range(int(start * float(RATE)), mini(int((start + 0.1) * float(RATE)), data.size())):
			var local: float = float(i) / float(RATE) - start
			phase += TAU * (base + 900.0 * sin(PI * local / 0.1) * (1.0 if variant != 1 else -1.0) + 40.0 * sin(TAU * 28.0 * local)) / float(RATE)
			data[i] += sin(phase) * sin(PI * local / 0.1) * 0.3
	return data
