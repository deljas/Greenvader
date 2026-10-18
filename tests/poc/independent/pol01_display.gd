extends SceneTree
## POL-01 independent check 4: foot disc / local light / street lamps / water are display only; lamps follow the game clock only.
##   godot --headless --path <repo> --script res://tests/poc/independent/pol01_display.gd
const Session: GDScript = preload("res://scripts/poc/poc_session.gd")
var passes: int = 0
var fails: int = 0

func check(name: String, ok: bool, detail: String = "") -> void:
	if ok:
		passes += 1
	else:
		fails += 1
	print("PASS " if ok else "FAIL ", name, " ", detail)

func _init() -> void:
	_run.call_deferred()

func sha(b: PackedByteArray) -> String:
	var c: HashingContext = HashingContext.new()
	c.start(HashingContext.HASH_SHA256)
	c.update(b)
	return c.finish().hex_encode().substr(0, 16)

func sig(s: RefCounted) -> String:
	var st: WorldState = s.state
	return JSON.stringify([sha(st.stage), sha(st.plant_id), sha(st.growth.to_byte_array()), sha(st.moisture), sha(st.terrain), st.greened_count, st.target_count, Array(st.zone_state), s.clock.growth_ticks, s.clock.spread_ticks, s.far.ticks, s.enemies.boars.size(), s.play.seeds, s.play.water, s.clock.elapsed])

func _run() -> void:
	change_scene_to_file("res://scenes/poc.tscn")
	for i: int in 6:
		await process_frame
	var main: Node = current_scene
	main.auto_process = false
	(main.ui.title_buttons[&"new_game"] as Button).pressed.emit()
	for i: int in 4:
		await process_frame
	var s: RefCounted = main.session
	var size: Vector2i = Session.town_size()
	var ref: RefCounted = Session.new(size.x, size.y)
	ref.paving = Session.paving_from(ref.env_tuning)
	check("ref_load", ref.load_combat(Session.TOWN_SETUP))
	check("same_start", s.clock.elapsed == ref.clock.elapsed and sig(s) == sig(ref), "\nA=%s\nB=%s" % [sig(s), sig(ref)])
	var rd: Node3D = main.readability
	var snap0: Dictionary = rd.snapshot()
	check("ten_lamps", int(snap0["lamps"]) == 10, str(snap0))
	# lamp lights sit at the placed PRP-001 lamps
	var lamp_ids: Array[String] = []
	for inst: Dictionary in s.placement.instances:
		if inst["asset"] == "PRP-001":
			lamp_ids.append(inst["id"])
	var near_ok: int = 0
	for light: OmniLight3D in rd.lamp_lights:
		var id: String = light.name.trim_prefix("Lamp_")
		var inst: Dictionary = s.placement.get_instance(id)
		var p: Vector2 = inst["pos"]
		if Vector2(light.position.x, light.position.z).distance_to(p) < 0.7 and light.position.y > 2.0:
			near_ok += 1
	check("lamp_lights_on_placed_lamps", near_ok == 10 and lamp_ids.size() == 10, "%d/%d lights within 0.7 m of PRP-001 positions" % [near_ok, lamp_ids.size()])
	# disc is a filled mesh: CylinderMesh, material opaque-ish fill; no outline construction
	var fm: MeshInstance3D = rd.marker
	check("disc_filled_cylinder", fm.mesh is CylinderMesh and (fm.mesh as CylinderMesh).height < 0.05 and (fm.mesh as CylinderMesh).top_radius > 0.2, "%s r=%.2f" % [fm.mesh.get_class(), (fm.mesh as CylinderMesh).top_radius])
	var rsrc: String = FileAccess.get_file_as_string("res://scripts/poc/environment/readability_view.gd")
	# step both with identical (zero) player input across 1.1 days with a mixed multiplier
	main.session.multiplier = 16.0
	ref.multiplier = 16.0
	var table: Array[String] = []
	var night_on: Dictionary = {}
	var total_steps: int = 0
	for step: int in 170:
		main.tick(0.25, Vector2.ZERO)
		ref.advance(0.25)
		total_steps += 1
		if step % 6 == 0:
			var hour: float = fposmod(8.0 + s.clock.elapsed / 25.0, 24.0)
			var sn: Dictionary = rd.snapshot()
			night_on[int(hour)] = int(sn["lamps_on"])
			table.append("h%.1f:%d/%d" % [hour, int(sn["lamps_on"]), int(sn["lamps"])])
	print("INFO lamps_on by game hour (session elapsed %.0f s): %s" % [s.clock.elapsed, " ".join(table)])
	check("display_does_not_change_world", sig(s) == sig(ref), "views on vs display-free session after %d ticks, elapsed %.1f" % [total_steps, s.clock.elapsed])
	# lamps by hour: noon off, deep night on
	var noon_off: bool = true
	var night_all: bool = true
	var hours_seen: int = 0
	for h: int in night_on:
		hours_seen += 1
		if h >= 10 and h <= 15 and int(night_on[h]) != 0:
			noon_off = false
		if (h >= 22 or h <= 3) and int(night_on[h]) != 10:
			night_all = false
	check("lamps_off_by_day_on_by_night", noon_off and night_all and hours_seen >= 15, "hours seen %d" % hours_seen)
	# lamps are a pure function of the game clock: pause for real time, and the state follows only elapsed (set via advance_game)
	var before: Dictionary = rd.snapshot()
	main.session.paused = true
	for i: int in 30:
		main.tick(0.25, Vector2.ZERO)
	var paused_snap: Dictionary = rd.snapshot()
	check("paused_clock_keeps_lamp_state", before == paused_snap, "")
	main.session.paused = false
	# jump the game clock to hour ~12 and ~1 using advance_game only and confirm via fresh sync
	var results: Array[String] = []
	for target_hour: float in [12.0, 1.0]:
		var now_h: float = fposmod(8.0 + s.clock.elapsed / 25.0, 24.0)
		var need: float = fposmod(target_hour - now_h, 24.0) * 25.0
		main.session.multiplier = 1.0
		s.advance_game(need)
		main.env_view.sync()
		var sn2: Dictionary = rd.snapshot()
		results.append("h%.1f lamps_on=%d night=%.2f" % [fposmod(8.0 + s.clock.elapsed / 25.0, 24.0), int(sn2["lamps_on"]), float(sn2["night"])])
		if target_hour == 12.0:
			check("noon_lamps_off", int(sn2["lamps_on"]) == 0 and float(sn2["night"]) < 0.01 and float(sn2["player_light"]) < 0.001, results[-1])
		else:
			check("night_lamps_on", int(sn2["lamps_on"]) == 10 and float(sn2["night"]) > 0.9 and float(sn2["player_light"]) > 0.1, results[-1])
	# water view only reads: terrain unchanged, greened count identical to display-free ref advanced to same elapsed
	ref.advance_game(s.clock.elapsed - ref.clock.elapsed)
	check("world_equal_after_jumps", sig(s) == sig(ref))
	print("RESULT pass=%d fail=%d" % [passes, fails])
	quit(1 if fails > 0 else 0)
