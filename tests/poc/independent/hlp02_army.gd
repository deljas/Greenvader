extends SceneTree
## HLP-02 independent verification (headless): condition 3 (Army) with real EnemyField boars.
const Session: GDScript = preload("res://scripts/poc/poc_session.gd")
const OUT: String = "res://evidence/helper/02/independent/"
var passes: int = 0
var fails: int = 0
var lines: PackedStringArray = PackedStringArray()
var keep: Array[RefCounted] = []

func check(name: String, ok: bool, detail: String = "") -> void:
	if ok: passes += 1
	else: fails += 1
	var line: String = "%s %s %s" % ["PASS" if ok else "FAIL", name, detail]
	lines.append(line)
	print(line)

func info(text: String) -> void:
	lines.append("INFO " + text)
	print("INFO ", text)

func _init() -> void:
	_run.call_deferred()

func mk() -> RefCounted:
	var size: Vector2i = Session.town_size()
	var m: RefCounted = Session.new(size.x, size.y)
	m.paving = Session.paving_from(m.env_tuning)
	m.load_combat(Session.TOWN_SETUP)
	keep.append(m)
	return m

func cc(o: Vector2i) -> Vector2:
	return (Vector2(o) + Vector2(2, 2)) * 4.0

func region_ok(st: WorldState, x0: int, y0: int, w: int, h: int, zone: int) -> bool:
	for y: int in range(y0, y0 + h):
		for x: int in range(x0, x0 + w):
			if not st.in_bounds(x, y): return false
			var i: int = st.index_of(x, y)
			if not st.is_walkable(x, y) or st.target[i] == 0 or st.occupant[i] != 0 or (zone >= 0 and st.zone_at(i) != zone): return false
	return true

func place_army(m: RefCounted, o: Vector2i) -> Dictionary:
	m.state.debug_fill_stage(Rect2i(o, Vector2i(4, 4)), WorldState.STAGE_MATURE)
	m.helpers.add_seeds(5)
	m.position = cc(o)
	m.set_aim(cc(o))
	m.helper_mode = 2
	return m.place_helper()

func _run() -> void:
	var R: float = 0.0
	var cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/poc/helpers.json"))
	for k: Variant in cfg["kinds"]:
		if String(k["key"]) == "army": R = float(k["radius_m"]) * 10.0
	info("army defence radius px (data) = %.1f" % R)
	_real(R)
	_wall(R)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var f: FileAccess = FileAccess.open(OUT + "army.log", FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\nRESULT passes=%d failures=%d\n" % [passes, fails])
	f.close()
	print("RESULT passes=%d failures=%d" % [passes, fails])
	for m: RefCounted in keep: m.close()
	quit(1 if fails > 0 else 0)

func _real(R: float) -> void:
	var m: RefCounted = mk()
	var st: WorldState = m.state
	var nest: Nest = m.enemies.nests[1]
	var nc: Vector2 = nest.center_px(4) / 4.0
	var spot: Vector2i = Vector2i(-1, -1)
	var best: float = INF
	for y: int in range(3, st.height - 8):
		for x: int in range(3, st.width - 8):
			if region_ok(st, x, y, 4, 4, 1):
				var d: float = absf(Vector2(x + 2, y + 2).distance_to(nc) - 8.0)
				if d < best:
					best = d
					spot = Vector2i(x, y)
	check("real.spot", spot.x >= 0, "%s dist to nest %.1f cells" % [str(spot), Vector2(spot + Vector2i(2, 2)).distance_to(nc)])
	var pr: Dictionary = place_army(m, spot)
	check("real.placed", bool(pr["ok"]), str(pr.get("reason", "")))
	var plant: Dictionary = m.helpers.plant_by_uid(int(pr["uid"]))
	var home: Vector2 = cc(spot)
	m.position = Vector2(88 * 4.0, 86 * 4.0)
	var max_d: float = 0.0
	var bad_cell: int = 0
	var out_of_radius_boar_steps: int = 0
	var inside_boar_steps: int = 0
	var seen: Dictionary = {}
	var vanished_far: int = 0
	var vanished: int = 0
	var killed_ids: Array[int] = []
	var t: float = 0.0
	var spawned_before: int = m.enemies.total_spawned
	while t < 400.0:
		m.advance_game(0.05)
		t += 0.05
		var u: Vector2 = m.helpers.unit_pos(plant)
		max_d = maxf(max_d, u.distance_to(home))
		var uc: Vector2i = Vector2i(floori(u.x / 4.0), floori(u.y / 4.0))
		if not st.in_bounds(uc.x, uc.y) or not st.is_walkable(uc.x, uc.y): bad_cell += 1
		var now: Dictionary = {}
		for b: Boar in m.enemies.boars:
			now[b.id] = b.pos
			var d: float = b.pos.distance_to(home)
			if d > R: out_of_radius_boar_steps += 1
			else: inside_boar_steps += 1
		for id: Variant in seen.keys():
			if not now.has(id):
				vanished += 1
				if (seen[id] as Vector2).distance_to(home) > R + 3.0: vanished_far += 1
		seen = now
		if plant.is_empty(): break
	var h: RefCounted = m.helpers
	check("real.boars_from_nest_came_in_range", inside_boar_steps > 0 and m.enemies.total_spawned > spawned_before, "spawned=%d inside-steps=%d outside-steps=%d" % [m.enemies.total_spawned, inside_boar_steps, out_of_radius_boar_steps])
	check("real.boars_killed", h.kills_total >= 1 and vanished >= 1, "kills_total=%d vanished=%d" % [h.kills_total, vanished])
	check("real.kills_only_inside_radius", vanished_far == 0, "far-vanish %d" % vanished_far)
	check("real.unit_never_beyond_radius", max_d <= R + 0.01, "max %.2f of %.1f" % [max_d, R])
	check("real.unit_always_on_walkable_cell", bad_cell == 0, "bad=%d" % bad_cell)
	check("real.outside_boars_existed_not_chased", out_of_radius_boar_steps > 0, "")
	# return home with no targets
	for b: Boar in m.enemies.boars.duplicate(): m.enemies.remove_boar(b)
	for n: Nest in m.enemies.nests.duplicate(): m.enemies.destroy_nest(n)
	var decoy: Boar = Boar.new()
	decoy.id = 9100
	decoy.zone = 1
	decoy.hp = 500
	decoy.home = home
	var dpos: Vector2 = home + Vector2(0.0, 24.0)
	decoy.pos = dpos
	m.enemies.boars.append(decoy)
	for k: int in 40:
		decoy.pos = dpos
		decoy.hp = 500
		m.advance_game(0.05)
	var away_pos: Vector2 = m.helpers.unit_pos(plant)
	check("real.teeth_unit_left_post_for_decoy", away_pos.distance_to(home) > 6.0, "%.1f px from post" % away_pos.distance_to(home))
	m.enemies.remove_boar(decoy)
	m.advance_game(15.0)
	var back: Vector2 = m.helpers.unit_pos(plant)
	info("unit before idle %s after 15s idle %s home %s" % [str(away_pos), str(back), str(home)])
	check("real.returns_to_post_when_no_target", back.distance_to(home) < 1.5 and not plant.is_empty())

## Boar held behind a one-cell wall: the army must not hurt it; the same boar in the open (control) is hurt.
func _wall(_R: float) -> void:
	var m: RefCounted = mk()
	var st: WorldState = m.state
	for n: Nest in m.enemies.nests.duplicate(): m.enemies.destroy_nest(n)
	for b: Boar in m.enemies.boars.duplicate(): m.enemies.remove_boar(b)
	var wall: Vector2i = Vector2i(-1, -1)
	for y: int in range(4, st.height - 6):
		for x: int in range(8, st.width - 4):
			var w: Vector2i = Vector2i(x, y)
			if not m.placement.projectile_blocked_cell(w) or m.placement.projectile_blocked_cell(Vector2i(x + 1, y)) or m.placement.projectile_blocked_cell(Vector2i(x - 1, y)):
				continue
			if region_ok(st, x - 6, y - 1, 4, 4, -1) and region_ok(st, x - 2, y, 2, 1, -1) and region_ok(st, x + 1, y, 3, 1, -1) and st.zone_at(st.index_of(x - 6, y)) == st.zone_at(st.index_of(x + 1, y)):
				wall = w
				break
		if wall.x >= 0: break
	check("wall.found", wall.x >= 0, str(wall))
	if wall.x < 0: return
	var o: Vector2i = Vector2i(wall.x - 6, wall.y - 1)
	var pr: Dictionary = place_army(m, o)
	check("wall.placed", bool(pr["ok"]), str(pr.get("reason", "")))
	var plant: Dictionary = m.helpers.plant_by_uid(int(pr["uid"]))
	m.position = Vector2(88 * 4.0, 86 * 4.0)
	var boar: Boar = Boar.new()
	boar.id = 9001
	boar.zone = st.zone_at(st.index_of(wall.x + 1, wall.y))
	boar.hp = 60
	boar.home = Vector2(wall.x + 1, wall.y) * 4.0
	var spot: Vector2 = Vector2(float(wall.x + 1) * 4.0 + 0.5, (float(wall.y) + 0.5) * 4.0)
	boar.pos = spot
	m.enemies.boars.append(boar)
	var min_gap: float = INF
	for k: int in 600:
		boar.pos = spot
		boar.hp = maxi(boar.hp, 1)
		m.advance_game(0.05)
		min_gap = minf(min_gap, m.helpers.unit_pos(plant).distance_to(spot))
	var hurt: int = 60 - boar.hp
	info("behind wall: min unit-boar distance %.2f px (reach 6), boar damage %d, wall cell %s" % [min_gap, hurt, str(wall)])
	check("wall.no_attack_through_wall", hurt == 0, "damage %d" % hurt)
	check("wall.teeth_unit_came_within_reach", min_gap <= 6.0, "min gap %.2f" % min_gap)
	# control: same plant, boar in the open on the unit's own side at a comparable spot
	var ctrl_spot: Vector2 = Vector2(float(wall.x - 1) * 4.0 + 0.5, (float(wall.y) + 0.5) * 4.0)
	boar.hp = 60
	for k: int in 200:
		boar.pos = ctrl_spot
		boar.hp = mini(boar.hp, 60)
		m.advance_game(0.05)
		if boar.hp <= 0: break
	check("wall.control_open_side_is_attacked", boar.hp < 60 or not m.enemies.boars.has(boar), "hp %d" % boar.hp)
