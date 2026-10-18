extends SceneTree
## HLP-02 independent verification (headless): condition 2 (Sprinkler).
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
	for n: Nest in m.enemies.nests.duplicate(): m.enemies.destroy_nest(n)
	for b: Boar in m.enemies.boars.duplicate(): m.enemies.remove_boar(b)
	keep.append(m)
	return m

func cc(o: Vector2i) -> Vector2:
	return (Vector2(o) + Vector2(2, 2)) * 4.0

## Own: any waterside terrain in the 6x6 ring around the 4x4 block.
func near_water(st: WorldState, o: Vector2i) -> bool:
	for y: int in range(o.y - 1, o.y + 5):
		for x: int in range(o.x - 1, o.x + 5):
			if st.in_bounds(x, y) and st.terrain_defs[st.terrain[st.index_of(x, y)]].is_waterside:
				return true
	return false

func block_ok(st: WorldState, o: Vector2i) -> bool:
	for y: int in range(o.y, o.y + 4):
		for x: int in range(o.x, o.x + 4):
			if not st.in_bounds(x, y): return false
			var i: int = st.index_of(x, y)
			if not st.is_walkable(x, y) or st.target[i] != 1 or st.occupant[i] != 0: return false
	return true

func find_block(st: WorldState, wet: bool, avoid_zone_out: bool = true) -> Vector2i:
	for y: int in range(3, st.height - 8):
		for x: int in range(3, st.width - 8):
			var o: Vector2i = Vector2i(x, y)
			if block_ok(st, o) and near_water(st, o) == wet and (wet or st.zone_at(st.index_of(x, y)) == 0):
				if wet or (x > 60 and y > 60):
					return o
	return Vector2i(-1, -1)

func place_spr(m: RefCounted, o: Vector2i) -> Dictionary:
	m.state.debug_fill_stage(Rect2i(o, Vector2i(4, 4)), WorldState.STAGE_MATURE)
	m.helpers.add_seeds(5)
	m.position = cc(o)
	m.set_aim(cc(o))
	m.helper_mode = 1
	return m.place_helper()

var phase: int = 0
func sow(st: WorldState, o: Vector2i, r: float, moist: int, fixed: bool = false) -> Array[int]:
	if not fixed: phase += 1
	var out: Array[int] = []
	var c: Vector2 = cc(o)
	for y: int in st.height:
		for x: int in st.width:
			if Vector2((x + 0.5) * 4.0, (y + 0.5) * 4.0).distance_to(c) <= r:
				var i: int = st.index_of(x, y)
				if st.can_plant(i) and (x + y + (0 if fixed else phase)) % 3 == 0:
					st.set_stage(i, WorldState.STAGE_SEED)
					st.set_moisture(i, moist)
					out.append(i)
	return out

func clear(st: WorldState, o: Vector2i, r: float) -> void:
	var c: Vector2 = cc(o)
	for y: int in st.height:
		for x: int in st.width:
			var i: int = st.index_of(x, y)
			if Vector2((x + 0.5) * 4.0, (y + 0.5) * 4.0).distance_to(c) <= r and st.target[i] == 1 and st.occupant[i] == 0 and st.stage[i] != 0:
				st.set_stage(i, WorldState.STAGE_EMPTY)

func away(m: RefCounted) -> void:
	m.position = Vector2(88 * 4.0, 86 * 4.0)

func _run() -> void:
	_shore()
	_inland()
	_growth()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var f: FileAccess = FileAccess.open(OUT + "spr.log", FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\nRESULT passes=%d failures=%d\n" % [passes, fails])
	f.close()
	print("RESULT passes=%d failures=%d" % [passes, fails])
	for m: RefCounted in keep: m.close()
	quit(1 if fails > 0 else 0)

func _shore() -> void:
	var m: RefCounted = mk()
	var st: WorldState = m.state
	var o: Vector2i = find_block(st, true)
	check("shore.block_found", o.x >= 0, str(o))
	var pr: Dictionary = place_spr(m, o)
	check("shore.placed", bool(pr["ok"]), str(pr.get("reason", "")))
	var plant: Dictionary = m.helpers.plant_by_uid(int(pr["uid"]))
	var stock0: float = float(plant["stock"])
	away(m)
	var pulses_seen: int = 0
	var rises: int = 0
	var rise_checks: int = 0
	var cells: Array[int] = []
	var last_p: int = m.helpers.pulses_total
	var dist_far: float = m.position.distance_to(cc(o))
	var t: float = 0.0
	var min_stock: float = 1e9
	while t < 600.0:
		if int(t * 10.0) % 50 == 0:
			clear(st, o, 30.0)
			cells = sow(st, o, 30.0, 0, true)
		var before: Dictionary = {}
		for i: int in cells: before[i] = int(st.moisture[i])
		m.advance_game(0.1)
		t += 0.1
		min_stock = minf(min_stock, float(plant["stock"]))
		if m.helpers.pulses_total > last_p:
			pulses_seen += 1
			for i: int in cells:
				if st.stage[i] >= 1 and st.stage[i] <= 3 and int(before[i]) < 60:
					rise_checks += 1
					if int(st.moisture[i]) > int(before[i]):
						rises += 1
		last_p = m.helpers.pulses_total
	check("shore.player_far_whole_run", dist_far > 100.0, "dist %.0f px" % dist_far)
	check("shore.pulses_continue_without_refill_600s", pulses_seen >= 100, "pulses=%d (600s)" % pulses_seen)
	check("shore.stock_not_consumed", min_stock >= stock0 - 0.001, "min stock %.1f start %.1f" % [min_stock, stock0])
	check("shore.moisture_rises_on_pulse", rise_checks > 50 and float(rises) >= 0.95 * float(rise_checks), "%d/%d" % [rises, rise_checks])

func _inland() -> void:
	var m: RefCounted = mk()
	var st: WorldState = m.state
	var o: Vector2i = find_block(st, false)
	check("inland.block_found", o.x >= 0 and not near_water(st, o), str(o))
	var pr: Dictionary = place_spr(m, o)
	check("inland.placed", bool(pr["ok"]), str(pr.get("reason", "")))
	var plant: Dictionary = m.helpers.plant_by_uid(int(pr["uid"]))
	away(m)
	var t: float = 0.0
	var cells: Array[int] = []
	var p_phase1: int = 0
	while t < 120.0:
		if int(t * 10.0) % 100 == 0:
			clear(st, o, 30.0)
			cells = sow(st, o, 30.0, 0, true)
		m.advance_game(0.1)
		t += 0.1
	p_phase1 = m.helpers.pulses_total
	var stock1: float = float(plant["stock"])
	check("inland.stops_when_stock_runs_out", p_phase1 == 3 and stock1 < 10.0, "pulses=%d stock=%.1f (start 30, cost 10)" % [p_phase1, stock1])
	# stays stopped
	for k: int in 600:
		if k % 100 == 0:
			clear(st, o, 30.0)
			sow(st, o, 30.0, 0, true)
		m.advance_game(0.1)
	check("inland.no_more_pulses_without_player", m.helpers.pulses_total == p_phase1, "pulses=%d" % m.helpers.pulses_total)
	# player approaches (stands 10 px from the block edge)
	m.position = cc(o) + Vector2(2.0 * 4.0 + 10.0, 0.0)
	var stock_before: float = float(plant["stock"])
	clear(st, o, 30.0)
	for k: int in 100:
		if k % 30 == 0:
			clear(st, o, 30.0)
			sow(st, o, 30.0, 0, true)
		m.advance_game(0.1)
	check("inland.refilled_by_player", float(plant["stock"]) > stock_before + 5.0 or m.helpers.pulses_total > p_phase1, "stock %.1f -> %.1f pulses %d" % [stock_before, float(plant["stock"]), m.helpers.pulses_total])
	check("inland.resumes_after_refill", m.helpers.pulses_total > p_phase1, "pulses %d -> %d" % [p_phase1, m.helpers.pulses_total])
	# player leaves again: no refill when far
	away(m)
	var s_far: float = float(plant["stock"])
	m.advance_game(0.5)
	var s_far2: float = float(plant["stock"])
	check("inland.no_refill_when_far", s_far2 <= s_far + 0.001)

func _growth() -> void:
	# two sessions with identical seeds/moisture 0: one with a sprinkler by the water, one without.
	var a: RefCounted = mk()
	var b: RefCounted = mk()
	var o: Vector2i = find_block(a.state, true)
	a.state.debug_fill_stage(Rect2i(o, Vector2i(4, 4)), WorldState.STAGE_MATURE)
	var pr: Dictionary = place_spr(b, o)
	check("growth.placed", bool(pr["ok"]))
	away(a); away(b)
	var ca: Array[int] = sow(a.state, o, 30.0, 0, true)
	var cb: Array[int] = sow(b.state, o, 30.0, 0, true)
	check("growth.same_seeds", ca == cb and ca.size() >= 10, "n=%d" % ca.size())
	var t: float = 0.0
	var first_a: float = -1.0
	var first_b: float = -1.0
	var mat_a: int = 0
	var mat_b: int = 0
	var marks: Array = [30.0, 60.0, 120.0]
	while t < 120.05:
		a.advance_game(0.1)
		b.advance_game(0.1)
		t += 0.1
		if not marks.is_empty() and absf(t - float(marks[0])) < 0.05:
			marks.pop_front()
			var sa: int = 0
			var sb: int = 0
			var wa: int = 0
			var wb: int = 0
			for i: int in ca:
				sa += int(a.state.stage[i])
				sb += int(b.state.stage[i])
				wa += int(a.state.moisture[i])
				wb += int(b.state.moisture[i])
			info("growth t=%.0fs: sum stage dry=%d sprinkler=%d ; sum moisture dry=%d sprinkler=%d (n=%d)" % [t, sa, sb, wa, wb, ca.size()])
			if t < 31.0:
				mat_a = sa
				mat_b = sb
	check("growth.sprinkler_grows_faster", mat_b > mat_a, "stage sums dry=%d sprinkler=%d at 30s" % [mat_a, mat_b])
