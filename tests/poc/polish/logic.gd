extends SceneTree
## POL-01 logic checks (headless OK): godot --headless --path <repo> --script res://tests/poc/polish/logic.gd
## Night lamps / foot marker / local light from the single game clock, display toggles do not touch the simulation,
## walking speed and substeps, town building yaw. (Tempo / 100 % bound: tests/poc/polish/tempo.gd.)
const Config: GDScript = preload("res://scripts/poc/poc_config.gd")
const Coords: GDScript = preload("res://scripts/poc/poc_coords.gd")
var failures: int = 0
var passes: int = 0
var main: Node
var s: RefCounted

func check(name: String, ok: bool, detail: String = "") -> void:
	print("PASS " if ok else "FAIL ", name, " ", detail)
	if ok:
		passes += 1
	else:
		failures += 1

func _init() -> void:
	_run.call_deferred()

func set_hour(hour: float) -> void:
	var elapsed: float = fposmod(hour - float(s.env_tuning["start_hour"]), 24.0) / 24.0 * float(s.env_tuning["day_seconds"])
	s.clock.load_dict({"version": 1, "elapsed": elapsed, "growth_ticks": int(elapsed / s.clock.growth_period), "spread_ticks": int(elapsed / s.clock.spread_period)})
	s.growth.ticks = s.clock.growth_ticks
	s.state.growth_tick = s.clock.growth_ticks
	main.tick(0.0, Vector2.ZERO)

func sig() -> String:
	return "%d/%d/%d/%d/%d" % [hash(s.state.terrain), hash(s.state.target), hash(s.state.stage), s.state.target_count, s.state.greened_count]

func _run() -> void:
	main = load("res://scenes/poc.tscn").instantiate()
	main.set_meta(&"poc_town", true)
	root.add_child(main)
	main.auto_process = false
	main.window_size_override = Vector2i(1920, 1080)
	await process_frame
	await process_frame
	s = main.session
	var r: Node = main.readability
	check("readability.built", r != null and r.lamp_lights.size() == 10, "lamps=%d" % (r.lamp_lights.size() if r != null else -1))
	# lamps sit at the PRP-001 placements (head offset in the lamp frame), above the ground
	var lamps_ok: bool = true
	var k: int = 0
	for inst: Dictionary in s.placement.instances:
		if String(inst["asset"]) == "PRP-001":
			var p: Vector2 = inst["pos"]
			var l: Vector3 = r.lamp_lights[k].position
			lamps_ok = lamps_ok and Vector2(l.x, l.z).distance_to(p) < 0.9 and l.y > 2.0
			k += 1
	check("lamps.at_PRP001_positions", lamps_ok and k == 10)
	set_hour(12.0)
	var day_on: int = r.snapshot()["lamps_on"]
	var day_player: float = r.player_light.light_energy
	var day_alpha: float = r.marker_material.albedo_color.a
	check("lamps.off_by_day", day_on == 0 and day_player == 0.0 and not r.player_light.visible, str(r.snapshot()))
	set_hour(0.0)
	check("lamps.on_at_night", int(r.snapshot()["lamps_on"]) == 10 and r.lamp_lights[0].light_energy > 1.0 and r.player_light.visible and r.player_light.light_energy > 0.5, str(r.snapshot()))
	check("marker.alpha_day_night_as_tuned", is_equal_approx(day_alpha, 0.3) and is_equal_approx(r.marker_material.albedo_color.a, 0.62), "day %.2f night %.2f" % [day_alpha, r.marker_material.albedo_color.a])
	# clock-only: the same elapsed gives the same lamps regardless of how it was reached; hour 8 start = lamps off
	check("lamps.follow_clock_not_wallclock", true if int(r.snapshot()["lamps_on"]) == 10 else false)
	set_hour(8.0)
	check("lamps.off_at_start_hour", int(r.snapshot()["lamps_on"]) == 0)
	# follow the player: marker under the feet and light above/near them, both moving with the player
	set_hour(0.0)
	s.position = Coords.ground_to_logic(Vector2(7.6, 11.2))
	main.tick(0.0, Vector2.ZERO)
	var a: Vector3 = r.marker.global_position
	var pa: Vector3 = r.player_light.global_position
	s.position = Coords.ground_to_logic(Vector2(9.6, 11.2))
	main.tick(0.0, Vector2.ZERO)
	var b: Vector3 = r.marker.global_position
	var pb: Vector3 = r.player_light.global_position
	check("marker.follows_player", a.distance_to(b) > 1.5 and absf(b.y - 0.07) < 0.001 and Vector2(b.x, b.z).distance_to(Vector2(main.actor.render_foot.x, main.actor.render_foot.z)) < 0.001, "%s -> %s" % [a, b])
	check("player_light.follows_player", pa.distance_to(pb) > 1.5 and pb.y > 1.0 and Vector2(pb.x, pb.z).distance_to(Vector2(b.x, b.z)) < 1.2)
	# not an outline, not always on top: depth test on unless a faded building hides the player
	check("marker.is_filled_disc_depth_tested", r.marker.mesh is CylinderMesh and not r.marker_material.no_depth_test and r.marker_material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA)
	# display toggles never change the simulation: greening / targets / terrain identical, shots and walking unaffected
	var before: String = sig()
	var elapsed: float = s.clock.elapsed
	for node: Node in r.lamp_lights:
		node.visible = not node.visible
	r.marker.visible = false
	r.set_see_through(true)
	r.player_light.light_energy = 5.0
	check("display_change.simulation_untouched", sig() == before and is_equal_approx(s.clock.elapsed, elapsed))
	r.set_see_through(false)
	# speed 4.8 m/s, diagonal normalised, unaffected by the time multiplier, substeps cannot jump 0.4 m cells
	s.position = Coords.ground_to_logic(Vector2(7.6, 11.2))
	var p0: Vector2 = s.position
	s.multiplier = 16.0
	s.walk(Vector2(1.0, 0.0), 0.1)
	var axis: float = (s.position - p0).length()
	s.position = p0
	s.walk(Vector2(1.0, 1.0).normalized(), 0.1)
	var diag: float = (s.position - p0).length()
	s.multiplier = 1.0
	check("walk.speed_4_8_diag_normalised_multiplier_free", Config.WALK_SPEED_MPS == 4.8 and absf(axis - 4.8) < 0.01 * 4.8 + 0.05 and absf(axis - diag) < 0.01, "axis %.3f px diag %.3f px (expect %.3f)" % [axis, diag, Config.walk_speed_px() * 0.1])
	var worst: float = 0.25 * Config.walk_speed_px()
	check("walk.max_motion_substepped_below_cell", worst / ceilf(worst / Walker.MAX_SUBSTEP) <= Walker.MAX_SUBSTEP + 1e-6 and Walker.MAX_SUBSTEP < float(Config.TILE_PX), "frame max %.2f px in substeps of <= %.2f px (cell %d px)" % [worst, Walker.MAX_SUBSTEP, Config.TILE_PX])
	# a long frame against a building wall never passes through it
	var wall_cell: Vector2i = Vector2i(-1, -1)
	for y: int in s.state.height:
		for x: int in range(10, s.state.width):
			if not s.state.is_walkable(x, y) and s.state.is_walkable(x - 1, y) and s.state.is_walkable(x - 2, y) and s.state.is_walkable(x - 3, y) and x > 20 and x < 100 and y > 20:
				wall_cell = Vector2i(x, y)
				break
		if wall_cell.x >= 0:
			break
	s.position = Coords.cell_center_logic(Vector2i(wall_cell.x - 3, wall_cell.y))
	for i: int in 20:
		s.walk(Coords.ground_dir_to_screen(Vector2(1.0, -1.0).normalized() * 0.0 + Vector2(1.0, 0.0)), 0.25)
	var cell: Vector2i = Coords.logic_to_cell(s.position)
	check("walk.no_tunnelling_at_max_frame", s.state.is_walkable(cell.x, cell.y) and cell.x < wall_cell.x or wall_cell.y != cell.y, "wall %s player %s" % [wall_cell, cell])
	# building yaw variety (rotation only, no negative scale)
	var yaws: Dictionary = {}
	for inst: Dictionary in s.placement.instances:
		if String(inst["kind"]) == "building":
			yaws[snappedf(rad_to_deg(float(inst["yaw"])), 1.0)] = true
	var no_flip: bool = true
	for h: Variant in main.placement_view.holders.values():
		no_flip = no_flip and (h as Node3D).scale.is_equal_approx(Vector3.ONE)
	check("town.building_yaws_vary_no_mirror", yaws.size() >= 3 and no_flip, "yaws=%s" % [yaws.keys()])
	main.queue_free()
	await process_frame
	print("RESULT passes=%d failures=%d" % [passes, failures])
	quit(1 if failures > 0 else 0)
