extends "res://tests/poc/integration/full_flow.gd"
## WTH-03 integration C + D: representative GPU screens and a short performance record (real renderer, NOT --headless):
##   godot --path <repo> --script res://tests/poc/integration/full_gpu.gd
## No OS-level input / cursor / foregrounding (root.unfocusable). Session A (play by the bot, public API): helper plants working at the
## front (day) -> viewpoint (E, panorama) -> night -> rain (the clock is moved to a daytime rain by a display fixture, clock only) ->
## perf windows (10 s at 640 and 960, real time, combat with helper plants in rain). Session B: new game played to stable, then no
## input to exact 100 % -> 100 % screens. Images + stats -> evidence/weather/03/.
const Day: GDScript = preload("res://scripts/poc/environment/poc_day.gd")
const WeatherScript: GDScript = preload("res://scripts/poc/environment/poc_weather.gd")
const PocSaveScript: GDScript = preload("res://scripts/poc/save/poc_save.gd")

var main: Node
var stats: PackedStringArray = PackedStringArray()
var perf_rows: Array[Dictionary] = []

func _init() -> void:
	super()
	root.unfocusable = true

func _frames(n: int) -> void:
	for i: int in n:
		await process_frame
	await RenderingServer.frame_post_draw

func settle() -> void:
	for i: int in 14:
		main.tick(0.05, Vector2.ZERO)

func _measure(image: Image) -> Dictionary:
	var green: int = 0
	var dark: int = 0
	var count: int = image.get_width() * image.get_height()
	var sum: float = 0.0
	for y: int in image.get_height():
		for x: int in image.get_width():
			var c: Color = image.get_pixel(x, y)
			sum += c.get_luminance()
			if c.g > c.r + 0.04 and c.g > c.b + 0.04:
				green += 1
			if c.get_luminance() < 0.05:
				dark += 1
	return {"green": snappedf(float(green) / float(count), 0.0001), "dark": snappedf(float(dark) / float(count), 0.0001), "mean_luma": snappedf(sum / float(count), 0.0001)}

## Hands session `sess` to the scene, builds the views, captures the 3D view and the whole window.
func capture(tag: String, res_index: int, sess: RefCounted, tick_first: bool = true) -> Image:
	if main.session != sess:
		main.replace_session(sess)
	main.set_resolution(res_index, Vector2i(1920, 1080))
	if tick_first:
		settle()
	await _frames(4)
	var image: Image = main.render_view.get_texture().get_image()
	var res: String = "640" if res_index == 0 else "960"
	image.save_png(ProjectSettings.globalize_path(OUT + "%s_%s.png" % [tag, res]))
	var full: Image = root.get_texture().get_image()
	full.save_png(ProjectSettings.globalize_path(OUT + "%s_%s_window.png" % [tag, res]))
	var m: Dictionary = _measure(image)
	m["hour"] = snappedf(sess.day_hour(), 0.01)
	m["t"] = snappedf(sess.clock.elapsed, 0.1)
	m["weather"] = sess.weather_text()
	m["greened"] = "%d/%d" % [sess.state.greened_count, sess.state.target_count]
	m["boars"] = sess.enemies.boars.size()
	m["helpers"] = sess.helpers.plants.size()
	m["viewing"] = main.is_viewing()
	m["size"] = "%dx%d" % [image.get_width(), image.get_height()]
	stats.append("%s_%s: %s" % [tag, res, m])
	print("INFO ", stats[stats.size() - 1])
	return image

func both(tag: String, sess: RefCounted, tick_first: bool = true) -> Array:
	var a: Image = await capture(tag, 0, sess, tick_first)
	var b: Image = await capture(tag, 1, sess, tick_first)
	return [a, b]

func set_time(sess: RefCounted, t: float) -> void:
	sess.clock.load_dict({"version": 1, "elapsed": t, "growth_ticks": int(t / sess.clock.growth_period), "spread_ticks": int(t / sess.clock.spread_period)})
	sess.growth.ticks = sess.clock.growth_ticks
	sess.state.growth_tick = sess.clock.growth_ticks
	sess.weather.update(t)

func find_day_rain(sess: RefCounted, after: float) -> float:
	var w: RefCounted = sess.weather
	for k: int in 2000:
		var t: float = after + 15.0 * float(k)
		var index: int = w.index_at(t)
		var seg: Dictionary = w.segments[index]
		var hour: float = Day.hour_at(t, sess.env_tuning)
		if int(seg["type"]) == WeatherScript.RAIN and t - float(seg["start"]) >= 30.0 and float(seg["start"]) + float(seg["duration"]) - t >= 90.0 and hour >= 9.0 and hour <= 15.5:
			return t
	return -1.0

func _mean(values: PackedFloat64Array) -> float:
	if values.is_empty():
		return 0.0
	var sum: float = 0.0
	for v: float in values:
		sum += v
	return sum / float(values.size())

func measure_window(label: String, res_index: int, vsync_off: bool) -> void:
	main.set_resolution(res_index, Vector2i(1920, 1080))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED if vsync_off else DisplayServer.VSYNC_ENABLED)
	var vsync_mode: int = DisplayServer.window_get_vsync_mode()
	var rid: RID = main.render_view.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(rid, true)
	main.auto_process = true
	await _frames(30)
	var deltas: PackedFloat64Array = PackedFloat64Array()
	var gpu_ms: PackedFloat64Array = PackedFloat64Array()
	var boars_min: int = 1 << 30
	var boars_max: int = 0
	var helpers_min: int = 1 << 30
	var t_start: int = Time.get_ticks_usec()
	var last: int = t_start
	var game0: float = s.clock.elapsed
	while float(Time.get_ticks_usec() - t_start) / 1.0e6 < 10.0:
		await process_frame
		var now: int = Time.get_ticks_usec()
		deltas.append(float(now - last) / 1000.0)
		last = now
		gpu_ms.append(RenderingServer.viewport_get_measured_render_time_gpu(rid))
		boars_min = mini(boars_min, s.enemies.boars.size())
		boars_max = maxi(boars_max, s.enemies.boars.size())
		helpers_min = mini(helpers_min, s.helpers.plants.size())
	main.auto_process = false
	var sorted: PackedFloat64Array = deltas.duplicate()
	sorted.sort()
	var avg: float = _mean(deltas)
	var worst: float = sorted[sorted.size() - 1]
	var over: int = 0
	for d: float in deltas:
		over += 1 if d > 17.2 else 0
	var row: Dictionary = {"label": label, "vsync_mode": vsync_mode, "frames": deltas.size(), "avg_frame_ms": snappedf(avg, 0.01), "avg_fps": snappedf(1000.0 / avg, 0.1), "p99_frame_ms": snappedf(sorted[mini(int(float(sorted.size()) * 0.99), sorted.size() - 1)], 0.01), "worst_frame_ms": snappedf(worst, 0.01), "min_fps_from_worst": snappedf(1000.0 / worst, 0.1), "frames_over_17.2ms": over, "viewport_gpu_ms_avg": snappedf(_mean(gpu_ms), 0.01), "boars_min": boars_min, "boars_max": boars_max, "helpers_min": helpers_min, "game_seconds": snappedf(s.clock.elapsed - game0, 0.1), "weather": s.weather_text(), "hour": snappedf(s.day_hour(), 0.1), "hp": s.play.hp}
	perf_rows.append(row)
	print("PERF ", JSON.stringify(row))

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		print("NOT_RUN gpu (headless display server)")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	print("renderer=", RenderingServer.get_video_adapter_name(), " display=", DisplayServer.get_name(), " window=", root.size, " refresh=", DisplayServer.screen_get_refresh_rate(), " vsync(initial)=", DisplayServer.window_get_vsync_mode())
	main = load("res://scenes/poc.tscn").instantiate()
	main.set_meta(&"poc_town", true)
	root.add_child(main)
	main.auto_process = false
	main.window_size_override = Vector2i(1920, 1080)
	await _frames(3)
	main.save_dir = "user://poc_saves_integration/"
	main.audio.muted = true   # object field only: nothing audible on the player's machine, the user's settings file is not touched

	# ------------------------------------------------------------ session A: helper plants at the front
	s = make_session()
	audio = AudioScript.new()
	audio.muted = false
	audio.calm_provider = func() -> bool: return s.paused
	audio.attach(s)
	viewpoint = ViewpointScript.new(s)
	bot = Bot.new(s)
	bot.audio = audio
	bot.guard_until = 3000.0
	var res: Dictionary = bot.sow(STAND, 8, true)
	var sown: PackedInt32Array = res["sown"]
	var cultivated: int = 0
	var tries: int = 0
	while cultivated < 3 and tries < 5 and s.play.seeds >= 3:
		tries += 1
		var spots: Array[Vector2i] = []
		for k: int in 12:
			var n: int = (k + 2 * cultivated) % 12
			spots.append(Vector2i(79 + (n % 3) * 3, 76 + n * 2))
		if place_cultivated("にんじん" if cultivated % 2 == 0 else "キウイ", spots):
			cultivated += 1
	end_cultivation_selection()
	var source: Vector2i = bot.nearest_source_cell()
	var limit: float = 260.0
	while s.clock.elapsed < limit and not bot.stopped and placed_log.size() < 2:
		bot.idle(2.0)
		if helper_chore():
			bot.go(source, 100.0, 3.0)
			continue
		if s.play.seeds < 14:
			bot.restock(30, 100.0)
	# stand next to the Gatlinger (or the first helper) so the working front is in view
	var anchor: Dictionary = {}
	for plant: Dictionary in s.helpers.plants:
		if anchor.is_empty() or String(plant["kind"]) == "gatlinger":
			anchor = plant
	if not anchor.is_empty():
		var rect: Rect2i = s.helpers.plant_rect(anchor)
		bot.go(bot.nearest_clear(Vector2i(rect.position.x + 6, rect.position.y + 2)), 90.0, 3.0)
	bot.idle(12.0)
	var alive_kinds: Array = []
	for plant: Dictionary in s.helpers.plants:
		alive_kinds.append(String(plant["kind"]))
	check("C0.front_state", s.helpers.plants.size() >= 2 and Day.phase_label(s.day_state()) == "昼", "t=%.1f hour %.1f weather %s helpers %s (placed log %s) boars=%d seeded=%d pulses=%d kills=%d" % [s.clock.elapsed, s.day_hour(), s.weather_text(), alive_kinds, str(placed_log), s.enemies.boars.size(), s.helpers.seeded_total, s.helpers.pulses_total, s.helpers.kills_total])
	var front_imgs: Array = await both("front_day", s)

	# viewpoint (E at the spot through the real scene), world stopped
	bot.go(viewpoint.cell, 150.0, 2.0)
	main.replace_session(s)
	main.tick(0.0, Vector2.ZERO)
	var t_before: float = s.clock.elapsed
	main.interact()
	for i: int in 10:
		main.tick(0.05, Vector2.ZERO)
	var view_imgs: Array = await both("lookout", s)
	check("C1.lookout_world_stopped", main.is_viewing() and s.clock.elapsed == t_before and main.notice.text == "", "viewing=%s clock %.3f -> %.3f notice=[%s]" % [str(main.is_viewing()), t_before, s.clock.elapsed, main.notice.text])
	main.leave_viewpoint()

	# night (natural time: keep playing with the bot until it is night)
	var guard: int = 0
	while s.day_hour() < 22.0 and s.day_hour() > 8.0 and guard < 400:
		guard += 1
		bot.idle(2.0)
	var night_imgs: Array = await both("night", s)

	# rain: display fixture, clock only
	var rain_t: float = find_day_rain(s, s.clock.elapsed + 30.0)
	check("C2.daytime_rain_found", rain_t > 0.0, "t=%.1f" % rain_t)
	set_time(s, rain_t)
	bot.idle(2.0)
	var rain_imgs: Array = await both("rain_day", s)
	var rain_overlay: bool = main.weather_view != null
	stats.append("rain fixture: clock moved to t=%.1f hour %.2f weather %s (display fixture only, clock fields only)" % [s.clock.elapsed, s.day_hour(), s.weather_text()])

	# ------------------------------------------------------------ D: performance (combat + helper plants + rain, real time, no input)
	bot.detach()
	main.replace_session(s)
	await _frames(5)
	var fight: Dictionary = {"t": s.clock.elapsed, "boars": s.enemies.boars.size(), "boar_cap": s.enemy_tuning.boar_cap, "helpers": s.helpers.plants.size(), "weather": s.weather_text(), "nests_alive": s.enemies.alive_nest_count(-1), "hp": s.play.hp}
	print("INFO perf state ", fight)
	await measure_window("640 vsync(config)", 0, false)
	await measure_window("960 vsync(config)", 1, false)
	await measure_window("640 vsync off", 0, true)
	await measure_window("960 vsync off", 1, true)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	var perf_report: Dictionary = {"adapter": RenderingServer.get_video_adapter_name(), "refresh_hz": DisplayServer.screen_get_refresh_rate(), "state": fight, "windows": perf_rows}
	var pf: FileAccess = FileAccess.open(ProjectSettings.globalize_path(OUT + "D_perf.json"), FileAccess.WRITE)
	pf.store_string(JSON.stringify(perf_report, "  ", false, true))
	pf.close()
	s.close()

	# ------------------------------------------------------------ session B: to stable, then no input to 100 %
	s = make_session()
	bot = Bot.new(s)
	bot.audio = null
	bot.guard_until = 3000.0
	bot.sow(STAND, 8, true)
	bot.restock(36, 200.0)
	var rounds: int = 0
	while s.enemies.alive_nest_count(-1) > 0 and rounds < 30 and not bot.stopped:
		rounds += 1
		if s.play.seeds < 30:
			bot.restock(38, 200.0)
		var best: Nest = null
		var best_d: float = 1.0e12
		for n: Nest in s.enemies.nests:
			if n.alive:
				var d: float = n.center_px(Config.TILE_PX).distance_to(s.position)
				if d < best_d:
					best_d = d
					best = n
		bot.kill_nest(best)
	bot.hunt_boars(500.0)
	var g2: int = 0
	while s.state.zone_state[1] < WorldState.ZONE_STABLE and g2 < 50:
		g2 += 1
		bot.idle(2.0)
	bot.detach()
	var lim: float = s.clock.elapsed + 1200.0
	while s.state.greened_count != s.state.target_count and s.clock.elapsed < lim:
		s.advance_game(0.25)
	check("C3.hundred_percent_reached", s.state.greened_count == s.state.target_count and s.state.cleared, "t=%.1f hour %.2f weather %s" % [s.clock.elapsed, s.day_hour(), s.weather_text()])
	var need: float = fposmod(12.0 - s.day_hour(), 24.0) / 24.0 * float(s.env_tuning["day_seconds"])
	var left: float = need
	while left > 0.0:
		var piece: float = minf(left, 0.25)
		s.advance_game(piece)
		left -= piece
	var full_imgs: Array = await both("full_100", s)

	# ------------------------------------------------------------ numeric sanity
	var m_night: float = _measure(night_imgs[0])["mean_luma"]
	var m_front: float = _measure(front_imgs[0])["mean_luma"]
	var m_full_g: float = _measure(full_imgs[0])["green"]
	var m_front_g: float = _measure(front_imgs[0])["green"]
	check("C4.night_darker_than_day", m_night < m_front, "mean luma night %.4f front day %.4f (640)" % [m_night, m_front])
	check("C4.hundred_percent_greener_than_front", m_full_g > m_front_g, "green share 100%% %.4f vs front %.4f (640)" % [m_full_g, m_front_g])
	check("C4.sizes", front_imgs[0].get_width() == 640 and front_imgs[1].get_width() == 960 and rain_imgs[1].get_height() == 540 and view_imgs[0].get_width() == 640, "")
	var file: FileAccess = FileAccess.open(ProjectSettings.globalize_path(OUT + "C_gpu_stats.txt"), FileAccess.WRITE)
	file.store_string("\n".join(stats) + "\n\n" + "\n".join(checks))
	file.close()
	s.close()
	main.queue_free()
	await _frames(2)
	print("RESULT passes=%d failures=%d" % [passes, failures])
	quit(1 if failures > 0 else 0)
