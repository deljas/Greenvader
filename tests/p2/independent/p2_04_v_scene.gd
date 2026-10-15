extends SceneTree
## Independent P2-04 verification on the real main.tscn. Input: engine-internal injection only (mouse motion/button, Esc key).
## Run: Godot --headless --fixed-fps N --path <p> --script res://tests/p2/independent/p2_04_v_scene.gd -- --hz=N
## Expected values come from the ticket: states U->clearing(all nests destroyed)->stable(no boar)->complete(greened==targets); cleared when all complete.
var results: Array[Dictionary] = []
var obs: Dictionary = {}
var main: Node
var hz: int = 60
var e: EnemyField
var w: WorldState
var play: PlayState
var player: Node2D
var notice: ZoneNotice
var mouse_screen: Vector2 = Vector2(320, 180)
var cleared_signals: int = 0

func _initialize() -> void:
	run.call_deferred()

func rec(id: String, cond: String, ok: bool, observed: String) -> void:
	results.append({"id": id, "condition": cond, "status": "PASS" if ok else "FAIL", "observed": observed})
	print("%s [%s] %s :: %s" % ["PASS" if ok else "FAIL", id, cond, observed])

func ticks(n: int) -> void:
	for i: int in n:
		await physics_frame

func secs(s: float) -> void:
	await ticks(roundi(s * hz))

func key_tap(code: Key) -> void:
	for pressed: bool in [true, false]:
		var ev: InputEventKey = InputEventKey.new()
		ev.physical_keycode = code
		ev.keycode = code
		ev.pressed = pressed
		Input.parse_input_event(ev)
		await process_frame

func aim_at(world_point: Vector2) -> void:
	var guess: Vector2 = world_point - player.position + Vector2(320, 180)
	for attempt: int in 4:
		var m: InputEventMouseMotion = InputEventMouseMotion.new()
		m.position = guess
		m.global_position = guess
		mouse_screen = guess
		Input.parse_input_event(m)
		await process_frame
		var achieved: Vector2 = player.get_global_mouse_position()
		if achieved.distance_to(world_point) < 0.6:
			break
		guess += world_point - achieved

func click() -> void:
	for pressed: bool in [true, false]:
		var ev: InputEventMouseButton = InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = mouse_screen
		ev.global_position = mouse_screen
		Input.parse_input_event(ev)
		await process_frame

func teleport(p: Vector2) -> void:
	player.simulation_position = p
	player.position = p.round()
	await ticks(3)

func zone_targets(z: int) -> Array[int]:
	var out: Array[int] = []
	for i: int in w.tile_count():
		if w.zone_of[i] == z and w.target[i] == 1:
			out.append(i)
	return out

func spot_near(center: Vector2, z: int, dist: float) -> Vector2:
	for deg: int in range(0, 360, 20):
		var p: Vector2 = center + Vector2(dist, 0).rotated(deg_to_rad(float(deg)))
		if Walker.is_clear(w, 4, p, Vector2(3, 2)) and w.zone_of[w.index_of(floori(p.x / 4), floori(p.y / 4))] == z:
			return p
	return Vector2.INF

func zname(z: int) -> String:
	return main.region_def.zones[z].display_name

func run() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--hz="):
			hz = int(a.trim_prefix("--hz="))
	Engine.physics_ticks_per_second = hz
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await ticks(3)
	e = main.enemies
	w = main.grid
	play = main.play
	player = main.player
	notice = main.zone_notice
	main.zone_progress.cleared.connect(func() -> void: cleared_signals += 1)
	obs["hz"] = hz
	obs["zone_names"] = []
	for z: ZoneDef in main.region_def.zones:
		obs["zone_names"].append(z.display_name)
	obs["start_label"] = main.zone_label.text
	rec("hud.start", "top bar at start shows the start zone name, stable (安定) and a percent", main.zone_label.text.contains(zname(0)) and main.zone_label.text.contains("安定") and main.zone_label.text.contains("％"), main.zone_label.text)
	rec("init.states", "start: zone 0 stable, all others unconquered, not cleared", w.zone_state[0] == 2 and not w.cleared, str(Array(w.zone_state)))

	# ---- pick zone Z: keep one nest, destroy the others ----
	var Z: int = 2
	var keep: Nest = null
	for n: Nest in e.nests:
		if n.zone == Z:
			if keep == null:
				keep = n
			else:
				e.destroy_nest(n)
	rec("trans.one_nest_left", "zone with 2 nests: one destroyed -> still unconquered", keep != null and w.zone_state[Z] == 0, "state=%d alive_nests=%d" % [w.zone_state[Z], e.alive_nest_count(Z)])
	await secs(25.0)
	var boars_z: int = e.boar_count_in_zone(Z)
	rec("trans.spawning", "unconquered zone with a live nest spawns boars", boars_z > 0, "boars=%d" % boars_z)
	# park boars (not moving) so that the shooter is not attacked
	for b: Boar in e.boars:
		b.wait = 1 << 30
	var center: Vector2 = keep.center_px(4)
	var spot: Vector2 = spot_near(center, Z, 30.0)
	rec("trans.spot", "found a standing spot near the nest in its zone", spot != Vector2.INF, str(spot))
	await teleport(spot)
	play.seeds = 60
	play.water = 60.0
	await aim_at(center)
	var shots: int = 0
	var state_hp1: int = -1
	while keep.alive and shots < 40:
		if keep.hp == 1:
			state_hp1 = w.zone_state[Z]
		await click()
		await secs(0.35)
		shots += 1
	rec("trans.nest_shot", "nest destroyed by injected clicks; zone still unconquered at 1 HP left", not keep.alive and state_hp1 == 0, "shots=%d state_at_hp1=%d" % [shots, state_hp1])
	var spawned_after: int = keep.spawned
	rec("trans.clearing", "all nests gone -> clearing (boars remain)", w.zone_state[Z] == 1 and e.boar_count_in_zone(Z) > 0, "state=%d boars=%d" % [w.zone_state[Z], e.boar_count_in_zone(Z)])
	rec("hud.clearing", "top bar (player in zone) shows name + 掃討中", main.zone_label.text.contains(zname(Z)) and main.zone_label.text.contains("掃討中"), main.zone_label.text)
	rec("hud.notice_clearing", "a notice for the clearing change was shown", notice.shown_log.size() >= 1 and notice.shown_log[notice.shown_log.size() - 1].contains(zname(Z)), str(notice.shown_log))
	# pause: notice and enemies stop; no lump sum at resume
	await key_tap(KEY_ESCAPE)
	var was_paused: bool = paused
	await ticks(2)
	var rem: float = notice.remaining
	var steps: int = e.steps_done
	var etime: float = e.time
	await secs(2.0)
	rec("pause.freeze", "Esc: tree paused, notice remaining and enemy steps unchanged over 2 s", was_paused and notice.remaining == rem and e.steps_done == steps and e.time == etime, "paused=%s rem %.3f->%.3f steps %d->%d" % [str(was_paused), rem, notice.remaining, steps, e.steps_done])
	await key_tap(KEY_ESCAPE)
	await ticks(2)
	rec("pause.nolump", "after resume, enemy time advanced < 0.2 s (no lump sum)", not paused and e.time - etime < 0.2 and rem - notice.remaining < 0.2, "enemy dt=%.3f notice dt=%.3f" % [e.time - etime, rem - notice.remaining])
	# kill the boars: one by injected clicks, the rest direct
	var target_boar: Boar = null
	for b: Boar in e.boars:
		if b.zone == Z:
			target_boar = b
			break
	await aim_at(e.boar_body_center(target_boar))
	for k: int in 3:
		await click()
		await secs(0.35)
	rec("trans.boar_clicked", "boar fell to 3 injected clicks", not e.boars.has(target_boar), "boars_left=%d" % e.boar_count_in_zone(Z))
	var left_before: int = e.boar_count_in_zone(Z)
	var hp_before: int = play.hp
	if left_before > 0:
		rec("trans.still_clearing", "boars left -> still clearing", w.zone_state[Z] == 1, "left=%d state=%d" % [left_before, w.zone_state[Z]])
	var guard: int = 0
	while e.boar_count_in_zone(Z) > 1 and guard < 20:
		for b: Boar in e.boars:
			if b.zone == Z:
				e.damage_boar(b, 99)
				break
		guard += 1
	if e.boar_count_in_zone(Z) == 1:
		rec("trans.last_boar_pending", "one boar left -> still clearing", w.zone_state[Z] == 1, "state=%d" % w.zone_state[Z])
		for b: Boar in e.boars:
			if b.zone == Z:
				e.damage_boar(b, 99)
	rec("trans.stable", "last boar gone -> stable", w.zone_state[Z] == 2 and e.boar_count_in_zone(Z) == 0, "state=%d" % w.zone_state[Z])
	await ticks(3)
	rec("hud.stable", "top bar shows 安定 for the zone", main.zone_label.text.contains(zname(Z)) and main.zone_label.text.contains("安定"), main.zone_label.text)
	rec("hud.notice_stable", "a notice for stable shown or queued (one at a time, 3 s each)", notice.shown_log.size() + notice.queue.size() >= 2 and (notice.shown_log + notice.queue.map(func(q: Dictionary) -> String: return q["text"])).any(func(s: String) -> bool: return s.contains("安定した")), "shown=%s queue=%d" % [str(notice.shown_log), notice.queue.size()])
	rec("trans.no_spawn_after", "no new spawn from the dead nest area", keep.spawned == spawned_after, "spawned %d" % keep.spawned)
	# ---- contact safety in the stable zone ----
	play.health.damaged.connect(func(_a: int, _s: Vector2) -> void: obs["hit_in_stable"] = true)
	await secs(20.0)
	rec("contact.none", "20 s in the stable zone: no boar, no damage", e.boar_count_in_zone(Z) == 0 and play.hp == hp_before and not obs.has("hit_in_stable"), "hp %d -> %d boars=%d" % [hp_before, play.hp, e.boar_count_in_zone(Z)])
	# ---- one tile short / complete ----
	var targets: Array[int] = zone_targets(Z)
	for k: int in targets.size() - 1:
		w.set_stage(targets[k], 2)
	await ticks(2)
	rec("green.one_short", "zone targets all but one greened -> stays stable", w.zone_state[Z] == 2, "greened=%d/%d pct=%d label=%s" % [w.zone_greened_count[Z], w.zone_target_count[Z], w.zone_greening_percent_floor(Z), main.zone_label.text])
	rec("hud.pct99", "label shows 99％ (floor, never 100 while one short)", main.zone_label.text.contains("99％") or w.zone_target_count[Z] < 100, main.zone_label.text)
	w.set_stage(targets[targets.size() - 1], 2)
	await ticks(3)
	rec("green.complete", "last target greened -> complete", w.zone_state[Z] == 3, "state=%d label=%s" % [w.zone_state[Z], main.zone_label.text])
	rec("hud.complete", "top bar shows 緑化完了 and 100", main.zone_label.text.contains("緑化完了") and main.zone_label.text.contains("100"), main.zone_label.text)
	rec("hud.notice_complete", "complete notice shown", notice.shown_log.any(func(s: String) -> bool: return s.contains("緑化が完了")), str(notice.shown_log))
	# follow: move to the start zone
	await teleport(Vector2(main.region_def.start_tile * 4) + Vector2(2, 2))
	await ticks(2)
	rec("hud.follow", "top bar follows the player back to the start zone", main.zone_label.text.contains(zname(0)) and main.zone_label.text.contains("安定"), main.zone_label.text)
	# ---- finish every other zone -> cleared ----
	for n: Nest in e.nests:
		if n.alive:
			e.destroy_nest(n)
	for b: Boar in e.boars.duplicate():
		e.damage_boar(b, 99)
	rec("clear.all_stable", "all nests/boars gone: zones 1..6 stable (zone 0 stable)", w.zone_state[0] == 2 and not w.cleared, str(Array(w.zone_state)))
	for z: int in w.zone_count:
		if w.zone_state[z] == 3:
			continue
		var ts: Array[int] = zone_targets(z)
		for i: int in ts.size():
			if z == 0 and i == ts.size() - 1:
				continue
			w.set_stage(ts[i], 2)
	await ticks(2)
	rec("clear.not_yet", "start zone one tile short: not cleared, no clear notice", not w.cleared and cleared_signals == 0 and w.zone_state[0] == 2, str(Array(w.zone_state)))
	var z0: Array[int] = zone_targets(0)
	w.set_stage(z0[z0.size() - 1], 2)
	await ticks(3)
	var clear_notices: int = 0
	for s: String in notice.shown_log:
		if s == ZoneHud.CLEARED_TEXT:
			clear_notices += 1
	var queued: int = 0
	for q: Dictionary in notice.queue:
		if q["text"] == ZoneHud.CLEARED_TEXT:
			queued += 1
	rec("clear.cleared", "all complete -> cleared flag, one signal, clear notice shown/queued once", w.cleared and cleared_signals == 1 and clear_notices + queued == 1 and Array(w.zone_state) == [3, 3, 3, 3, 3, 3, 3], "cleared=%s signals=%d notices=%d+%d states=%s" % [str(w.cleared), cleared_signals, clear_notices, queued, str(Array(w.zone_state))])
	obs["notice_log"] = notice.shown_log.duplicate()
	obs["label_final"] = main.zone_label.text
	await secs(12.0)
	rec("clear.go_on", "play continues after clear: player moves via simulation, no second clear signal", cleared_signals == 1 and is_instance_valid(main) and w.cleared, "signals=%d label=%s" % [cleared_signals, main.zone_label.text])
	# save round-trip of the whole main state, if the API exists
	var d: Dictionary = w.to_dict()
	var w2: WorldState = WorldState.from_dict(JSON.parse_string(JSON.stringify(d)), w.terrain_defs)
	rec("save.cleared", "cleared world saves/loads with cleared=true and all complete", w2 != null and w2.cleared and w2.all_zones_complete(), "")
	var f: FileAccess = FileAccess.open("res://evidence/p2/p2-04/independent/checks_scene_%d.json" % hz, FileAccess.WRITE)
	f.store_string(JSON.stringify({"results": results, "observations": obs}, "  "))
	f.close()
	var fails: int = 0
	for r: Dictionary in results:
		if r["status"] != "PASS":
			fails += 1
	print("RESULT scene hz=%d checks=%d failures=%d" % [hz, results.size(), fails])
	quit(1 if fails > 0 else 0)
