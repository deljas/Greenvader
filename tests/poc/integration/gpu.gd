extends SceneTree
## POC-09 integration C: representative GPU screens at 640 and 960 (real renderer, NOT --headless):
##   godot --path <repo> --script res://tests/poc/integration/gpu.gd
## No OS-level input, no cursor movement, no foregrounding (root.unfocusable = true). Images -> evidence/poc/09/.
## One run on town_01 (fixed seeds) driven by the test-side bot (public session API only), handed to the scene with
## main.replace_session() at each capture point (the same path a loaded save takes). Per resolution:
## combat (normal camera), stable (daytime, partly green), 100 % (daytime), 100 % at night, occlusion behind a building, title.
## Game-time fast-forward is used only to reach the next midday (no state is written other than by the bot's play).
const Config: GDScript = preload("res://scripts/poc/poc_config.gd")
const Coords: GDScript = preload("res://scripts/poc/poc_coords.gd")
const Session: GDScript = preload("res://scripts/poc/poc_session.gd")
const Day: GDScript = preload("res://scripts/poc/environment/poc_day.gd")
const Bot: GDScript = preload("res://tests/poc/integration/bot.gd")
const OUT: String = "res://evidence/poc/09/"
const STAND: Vector2i = Vector2i(78, 84)
const WATER_BANK: Vector2i = Vector2i(44, 55)

var failures: int = 0
var passes: int = 0
var main: Node
var s: RefCounted
var bot: RefCounted
var stats: PackedStringArray = PackedStringArray()
var checks: Array[String] = []

func check(name: String, ok: bool, detail: String = "") -> void:
	var line: String = "%s %s %s" % ["PASS" if ok else "FAIL", name, detail]
	checks.append(line)
	print(line)
	if ok:
		passes += 1
	else:
		failures += 1

func _init() -> void:
	root.unfocusable = true
	_run.call_deferred()

func _frames(n: int) -> void:
	for i: int in n:
		await process_frame
	await RenderingServer.frame_post_draw

func _save(image: Image, name: String) -> void:
	image.save_png(ProjectSettings.globalize_path(OUT + name))

func _measure(image: Image) -> Dictionary:
	var green: int = 0
	var dark: int = 0
	var sum: Color = Color(0, 0, 0)
	var count: int = image.get_width() * image.get_height()
	for y: int in image.get_height():
		for x: int in image.get_width():
			var c: Color = image.get_pixel(x, y)
			sum += c
			if c.g > c.r + 0.04 and c.g > c.b + 0.04:
				green += 1
			if c.get_luminance() < 0.05:
				dark += 1
	return {"green": snappedf(float(green) / float(count), 0.0001), "dark": snappedf(float(dark) / float(count), 0.0001), "mean_luma": snappedf((sum / float(count)).get_luminance(), 0.0001)}

func settle() -> void:
	for i: int in 14:
		main.tick(0.05, Vector2.ZERO)

## Hands the bot's session to the scene, builds every view from it and captures both the 3D view and the whole window.
func capture(tag: String, res_index: int) -> Image:
	main.replace_session(s)
	main.set_resolution(res_index, Vector2i(1920, 1080))
	settle()
	await _frames(4)
	var image: Image = main.render_view.get_texture().get_image()
	var res: String = "640" if res_index == 0 else "960"
	var name: String = "%s_%s.png" % [tag, res]
	_save(image, name)
	var full: Image = root.get_texture().get_image()
	_save(full, "%s_%s_window.png" % [tag, res])
	var m: Dictionary = _measure(image)
	m["hour"] = snappedf(s.day_hour(), 0.01)
	m["t"] = snappedf(s.clock.elapsed, 0.1)
	m["greened"] = "%d/%d" % [s.state.greened_count, s.state.target_count]
	m["boars"] = s.enemies.boars.size()
	m["size"] = "%dx%d" % [image.get_width(), image.get_height()]
	m["window_png"] = "%dx%d" % [full.get_width(), full.get_height()]
	stats.append("%s: %s" % [name, m])
	print("INFO ", stats[stats.size() - 1])
	return image

func both(tag: String) -> Array:
	var a: Image = await capture(tag, 0)
	var b: Image = await capture(tag, 1)
	return [a, b]

func advance_to_hour(hour: float) -> void:
	var need: float = fposmod(hour - s.day_hour(), 24.0) / 24.0 * float(s.env_tuning["day_seconds"])
	var left: float = need
	while left > 0.0:
		var piece: float = minf(left, 0.25)
		s.advance_game(piece)
		left -= piece

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		print("NOT_RUN gpu (headless display server)")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	print("renderer=", RenderingServer.get_video_adapter_name(), " display=", DisplayServer.get_name(), " window=", root.size)
	main = load("res://scenes/poc.tscn").instantiate()
	main.set_meta(&"poc_town", true)
	root.add_child(main)
	main.auto_process = false
	main.window_size_override = Vector2i(1920, 1080)
	await _frames(3)
	main.save_dir = "user://poc_saves_integration/"
	# ---------------- title of a fresh start (untouched session, the screen run_poc.bat opens with)
	for res_index: int in 2:
		main.set_resolution(res_index, Vector2i(1920, 1080))
		main.open_title()
		await _frames(4)
		var full: Image = root.get_texture().get_image()
		var name: String = "title_%s.png" % ("640" if res_index == 0 else "960")
		_save(full, name)
		var m: Dictionary = _measure(full)
		stats.append("%s: %dx%d %s" % [name, full.get_width(), full.get_height(), m])
		print("INFO ", stats[stats.size() - 1])
	main.new_game()
	await _frames(2)
	# ---------------- play up to a fight at the north nest
	var size: Vector2i = Session.town_size()
	s = Session.new(size.x, size.y)
	s.paving = Session.paving_from(s.env_tuning)
	s.load_combat(Session.TOWN_SETUP)
	bot = Bot.new(s)
	bot.guard_until = 4000.0
	var info: Dictionary = bot.sow(STAND, 8, true)
	bot.restock(36, 200.0)
	bot.idle(20.0)
	var nest: Nest = s.enemies.nest_by_id(3)
	bot.stop_when = func() -> bool: return nest.hp < nest.hp_max and s.enemies.boars.size() >= 2 and s.projectiles.shots.size() > 0
	var guard: int = 0
	while not bot.stopped and nest.alive and guard < 8:
		guard += 1
		bot.kill_nest(nest, 150.0)
		if s.play.seeds < 4:
			bot.restock(36, 200.0)
	check("C0.combat_state_reached", nest.alive and nest.hp < nest.hp_max and s.enemies.boars.size() >= 2, "t=%.1f nest hp %d/%d boars=%d shots=%d hp=%d" % [s.clock.elapsed, nest.hp, nest.hp_max, s.enemies.boars.size(), s.projectiles.shots.size(), s.play.hp])
	bot.stop_when = Callable()
	bot.stopped = false
	var combat_imgs: Array = await both("combat")
	# ---------------- finish the nests and enemies
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
	var guard2: int = 0
	while s.state.zone_state[1] < WorldState.ZONE_STABLE and guard2 < 50:
		guard2 += 1
		bot.idle(2.0)
	check("C0b.stable_reached", s.state.zone_state[1] >= WorldState.ZONE_STABLE, "t=%.1f hour %.1f" % [s.clock.elapsed, s.day_hour()])
	# From here the player gives no input (the stable screens show the scene exactly as the free-running game continues).
	bot.detach()
	advance_to_hour(12.0)
	check("C0c.partly_green_at_midday_after_stable", s.state.greened_count < s.state.target_count and s.state.zone_state[1] == WorldState.ZONE_STABLE, "t=%.1f hour %.2f greened %d/%d" % [s.clock.elapsed, s.day_hour(), s.state.greened_count, s.state.target_count])
	var stable_imgs: Array = await both("stable")
	# ---------------- run on to exact 100 %
	var limit: float = s.clock.elapsed + 1200.0
	while s.state.greened_count != s.state.target_count and s.clock.elapsed < limit:
		s.advance_game(0.25)
	check("C0d.hundred_percent", s.state.greened_count == s.state.target_count and s.state.cleared, "t=%.1f hour %.2f" % [s.clock.elapsed, s.day_hour()])
	var night_hour: float = s.day_hour()
	# 100 % reached in the evening/night -> capture the night screen right now (as played); otherwise advance to 23:00.
	if not (night_hour >= 20.0 or night_hour < 4.0):
		advance_to_hour(23.0)
	var night_imgs: Array = await both("full_night")
	advance_to_hour(12.0)
	var day_imgs: Array = await both("full_day")
	# ---------------- occlusion (player behind a building), daytime, 100 %
	await _occlusion_shots()
	# ---------------- numeric sanity of the images
	var night_luma: float = _measure(night_imgs[0])["mean_luma"]
	var day_luma: float = _measure(day_imgs[0])["mean_luma"]
	var combat_green: float = _measure(combat_imgs[0])["green"]
	var day_green: float = _measure(day_imgs[0])["green"]
	check("C1.night_darker_than_day", night_luma < day_luma, "mean luma night %.4f day %.4f (640)" % [night_luma, day_luma])
	check("C1.full_day_greener_than_combat", day_green > combat_green, "green share 100%% day %.4f vs combat start %.4f (640)" % [day_green, combat_green])
	check("C1.sizes_640_960", combat_imgs[0].get_width() == 640 and combat_imgs[1].get_width() == 960 and stable_imgs[1].get_height() == 540, "")
	var file: FileAccess = FileAccess.open(ProjectSettings.globalize_path(OUT + "C_gpu_stats.txt"), FileAccess.WRITE)
	file.store_string("\n".join(stats) + "\n\n" + "\n".join(checks))
	file.close()
	main.queue_free()
	await _frames(2)
	print("RESULT passes=%d failures=%d" % [passes, failures])
	quit(1 if failures > 0 else 0)

func _occlusion_shots() -> void:
	main.replace_session(s)
	main.set_resolution(0, Vector2i(1920, 1080))
	var ov: Node = main.occlusion_view
	var half: Vector2 = Config.player_half_px()
	var spot: Vector2 = Vector2.INF
	var group_id: String = ""
	for entry: Dictionary in ov.occlusion.entries:
		var inst: Dictionary = s.placement.get_instance(String(entry["ids"][0]))
		if String(inst["kind"]) != "building":
			continue
		var p: Vector2 = inst["pos"]
		for k: int in range(3, 12):
			var foot: Vector3 = Vector3(p.x - 0.5 * float(k) * 0.707107, 0.04, p.y - 0.5 * float(k) * 0.707107)
			var logic: Vector2 = Coords.ground_to_logic(Vector2(foot.x, foot.z))
			var keys: Array = ov.occlusion.raw_occluders(ov.occlusion.sample_points(foot, 1.42, main.camera.global_basis.x), main.camera.global_basis.z).keys()
			if Walker.is_clear(s.state, Config.TILE_PX, logic, half) and keys == [String(entry["group"])]:
				spot = logic
				group_id = String(entry["group"])
				break
		if spot != Vector2.INF:
			break
	check("C2.occlusion_spot_found", spot != Vector2.INF, "group %s" % group_id)
	s.position = spot
	for res_index: int in 2:
		main.set_resolution(res_index, Vector2i(1920, 1080))
		for i: int in 30:
			main.tick(0.05, Vector2.ZERO)
		await _frames(4)
		var image: Image = main.render_view.get_texture().get_image()
		var name: String = "occlusion_%s.png" % ("640" if res_index == 0 else "960")
		_save(image, name)
		_save(root.get_texture().get_image(), name.replace(".png", "_window.png"))
		var faded: PackedStringArray = ov.faded_instances()
		check("C2.occlusion_active_%s" % ("640" if res_index == 0 else "960"), faded == PackedStringArray([group_id]), "faded=%s alpha=%.2f hour %.1f" % [faded, main.placement_view.instance_alpha(group_id), s.day_hour()])
		stats.append("%s: faded=%s" % [name, faded])
