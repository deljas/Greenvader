extends SceneTree
## HLP-02 independent verification (headless): condition 1 (Gatlinger). Own save-free; own aggregation of stock / seeds / wasted.
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

func place_gat(m: RefCounted, o: Vector2i) -> Dictionary:
	m.helpers.add_seeds(5)
	m.position = cc(o)
	m.set_aim(cc(o))
	m.helper_mode = 0
	return m.place_helper()

func radius_px() -> float:
	var cfg: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/poc/helpers.json"))
	for k: Variant in cfg["kinds"]:
		if String(k["key"]) == "gatlinger":
			return float(k["radius_m"]) * 10.0
	return 0.0

func new_cells(m: RefCounted, before: PackedByteArray, centre: Vector2, r: float, min_stage: int) -> int:
	var st: WorldState = m.state
	var n: int = 0
	for y: int in st.height:
		for x: int in st.width:
			var i: int = st.index_of(x, y)
			if Vector2((x + 0.5) * 4.0, (y + 0.5) * 4.0).distance_to(centre) <= r and st.target[i] == 1 and before[i] < min_stage and st.stage[i] >= min_stage and st.occupant[i] == 0:
				n += 1
	return n

func _run() -> void:
	var R: float = radius_px()
	info("gatlinger radius px (from data) = %.1f" % R)
	_work_and_compare(R, Vector2i(76, 92), "A")
	_work_and_compare(R, Vector2i(94, 90), "B")
	_fair_compare(R)
	_obstacles(R)
	_stock_zero(R)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var f: FileAccess = FileAccess.open(OUT + "gat.log", FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\nRESULT passes=%d failures=%d\n" % [passes, fails])
	f.close()
	print("RESULT passes=%d failures=%d" % [passes, fails])
	for m: RefCounted in keep: m.close()
	quit(1 if fails > 0 else 0)

func _work_and_compare(R: float, origin: Vector2i, tag: String) -> void:
	var base: RefCounted = mk()
	var g: RefCounted = mk()
	var pr: Dictionary = place_gat(g, origin)
	check(tag + ".gat.placed", bool(pr["ok"]), str(pr.get("reason", "")))
	var centre: Vector2 = cc(origin)
	var uid: int = int(pr["uid"])
	var plant: Dictionary = g.helpers.plant_by_uid(uid)
	var before_b: PackedByteArray = base.state.stage.duplicate()
	var before_g: PackedByteArray = g.state.stage.duplicate()
	var st: WorldState = g.state
	var receives: int = 0
	var fires: int = 0
	var last_stock: float = float(plant["stock"])
	var last_serial: int = g.helpers.fire_serial
	var stock_bad: bool = false
	var bad_targets: Array[String] = []
	var far_fire: int = 0
	var seen_cells: Dictionary = {}
	var dup: int = 0
	var max_stock: float = 0.0
	var blocked_cells: int = 0
	var window: float = 80.0
	g.position = Vector2(88 * 4.0, 86 * 4.0)
	base.position = g.position
	var t: float = 0.0
	var r80_b: int = 0
	var r80_g: int = 0
	var rs80_b: int = 0
	var rs80_g: int = 0
	while t < 300.0:
		g.advance_game(0.1)
		base.advance_game(0.1)
		t += 0.1
		var s: float = float(plant["stock"])
		if s < -0.0001 or s > 12.0001: stock_bad = true
		max_stock = maxf(max_stock, s)
		var ds: float = s - last_stock
		var dserial: int = g.helpers.fire_serial - last_serial
		fires += dserial
		var inc: int = int(round(ds + float(dserial)))
		receives += inc
		if dserial > 0:
			for k: int in range(g.helpers.flights.size() - dserial, g.helpers.flights.size()):
				var f: Dictionary = g.helpers.flights[k]
				var cx: int = int(f["cx"]); var cy: int = int(f["cy"])
				var ci: int = st.index_of(cx, cy)
				var tp: Vector2 = Vector2((cx + 0.5) * 4.0, (cy + 0.5) * 4.0)
				var why: String = ""
				if tp.distance_to(centre) > R + 0.01: why += "range "
				if st.target[ci] != 1 or not st.is_walkable(cx, cy): why += "notgreenable "
				if st.stage[ci] != 0: why += "seeded_already "
				if st.occupant[ci] != 0: why += "occupied "
				if g.shot_blocked(centre, tp): why += "wall "
				if seen_cells.has(ci) and st.stage[ci] == 0: pass
				var inflight: int = 0
				for f2: Dictionary in g.helpers.flights:
					if int(f2["cx"]) == cx and int(f2["cy"]) == cy: inflight += 1
				if inflight > 1: dup += 1
				seen_cells[ci] = true
				if why != "": bad_targets.append("%d,%d:%s" % [cx, cy, why])
		last_stock = s
		last_serial = g.helpers.fire_serial
		if absf(t - window) < 0.05:
			r80_b = new_cells(base, before_b, centre, R, 1)
			r80_g = new_cells(g, before_g, centre, R, 1)
			rs80_b = new_cells(base, before_b, centre, R, 2)
			rs80_g = new_cells(g, before_g, centre, R, 2)
	var h: RefCounted = g.helpers
	var st0: float = 0.0
	var inflight_now: int = h.flights.size()
	check(tag + ".gat.stock_in_bounds", not stock_bad, "max stock seen %.1f" % max_stock)
	check(tag + ".gat.accounting", float(plant["stock"]) + float(fires) == st0 + float(receives), "receives=%d fires=%d stock=%.1f" % [receives, fires, float(plant["stock"])])
	check(tag + ".gat.fires_equal_seeded_wasted_inflight", fires == h.seeded_total + h.wasted_total + inflight_now, "fires=%d seeded=%d wasted=%d inflight=%d" % [fires, h.seeded_total, h.wasted_total, inflight_now])
	check(tag + ".gat.fired_something", fires >= 20, "fires=%d" % fires)
	check(tag + ".gat.all_targets_valid_at_fire", bad_targets.is_empty(), str(bad_targets.slice(0, 5)))
	check(tag + ".gat.no_inflight_duplicates", dup == 0, "dup=%d" % dup)
	check(tag + ".gat.low_waste", float(h.wasted_total) <= 0.1 * float(maxi(fires, 1)), "wasted=%d of %d" % [h.wasted_total, fires])
	info("window %.0fs (cells newly planted stage>=1 in radius): base=%d gat=%d ; stage>=2: base=%d gat=%d" % [window, r80_b, r80_g, rs80_b, rs80_g])
	var ratio: float = float(r80_g) / float(maxi(r80_b, 1))
	info("front speed multiple (stage>=1, 80s) = %.2f (base zero? %s)" % [ratio, str(r80_b == 0)])
	check(tag + ".gat.frontier_faster_than_natural", r80_g > r80_b and ratio >= 1.3, "ratio %.2f" % ratio)
	info("300s: base new(stage>=1)=%d gat=%d" % [new_cells(base, before_b, centre, R, 1), new_cells(g, before_g, centre, R, 1)])
	# remote sources: any gatlinger-planted cells far from existing green at the time? count distinct target cells' distance to nearest pre-existing plant
	var far_pts: int = 0
	for ci: int in seen_cells.keys():
		var x: int = ci % st.width
		var y: int = ci / st.width
		var near_old: bool = false
		for dy: int in range(-3, 4):
			for dx: int in range(-3, 4):
				if st.in_bounds(x + dx, y + dy) and before_g[st.index_of(x + dx, y + dy)] != 0:
					near_old = true
		if not near_old: far_pts += 1
	check(tag + ".gat.seeds_remote_origins", far_pts > 0, "targets with no pre-existing plant within 3 cells: %d of %d" % [far_pts, seen_cells.size()])

## Same natural origin in both sessions: an 8x8 mature island on empty ground; one session also has a Gatlinger on a 4x4 part of it.
func _fair_compare(R: float) -> void:
	var spot: Vector2i = Vector2i(6, 6)
	var a: RefCounted = mk()
	var b: RefCounted = mk()
	for m: RefCounted in [a, b]:
		m.state.debug_fill_stage(Rect2i(spot, Vector2i(8, 8)), WorldState.STAGE_MATURE)
		for bo: Boar in m.enemies.boars.duplicate(): m.enemies.remove_boar(bo)
		m.position = Vector2(88 * 4.0, 86 * 4.0)
	var pr: Dictionary = place_gat(b, spot)
	check("fair.placed", bool(pr["ok"]))
	var centre: Vector2 = cc(spot)
	var ba: PackedByteArray = a.state.stage.duplicate()
	var bb: PackedByteArray = b.state.stage.duplicate()
	var t: float = 0.0
	var marks: Array = [40.0, 80.0, 160.0]
	var ratios: Array[float] = []
	while t < 160.05:
		a.advance_game(0.1)
		b.advance_game(0.1)
		t += 0.1
		if not marks.is_empty() and absf(t - float(marks[0])) < 0.05:
			var w: float = float(marks.pop_front())
			var n1a: int = new_cells(a, ba, centre, R, 1)
			var n1b: int = new_cells(b, bb, centre, R, 1)
			var n2a: int = new_cells(a, ba, centre, R, 2)
			var n2b: int = new_cells(b, bb, centre, R, 2)
			info("fair t=%.0fs new cells in radius: natural stage>=1 %d, with gatlinger %d (x%.2f); stage>=2: %d vs %d (x%.2f)" % [w, n1a, n1b, float(n1b) / float(maxi(n1a, 1)), n2a, n2b, float(n2b) / float(maxi(n2a, 1))])
			ratios.append(float(n1b) / float(maxi(n1a, 1)))
	check("fair.faster_at_all_marks", ratios.size() == 3 and ratios[0] > 1.2 and ratios[1] > 1.2 and ratios[2] > 1.2, str(ratios))

func _obstacles(R: float) -> void:
	# island mature block near nest 1 (water / building / nest / walls within range checked by invariants at every fire)
	var m: RefCounted = mk()
	var st: WorldState = m.state
	var nest: Nest = m.enemies.nests[1]
	var nc: Vector2 = nest.center_px(4) / 4.0
	var spot: Vector2i = Vector2i(-1, -1)
	var best: float = INF
	for y: int in range(4, st.height - 8):
		for x: int in range(4, st.width - 8):
			var ok: bool = true
			for yy: int in range(y, y + 4):
				for xx: int in range(x, x + 4):
					var i: int = st.index_of(xx, yy)
					ok = ok and st.is_walkable(xx, yy) and st.target[i] == 1 and st.occupant[i] == 0 and st.zone_at(i) == 1
			if ok:
				var d: float = absf(Vector2(x + 2, y + 2).distance_to(nc) - 8.0)
				if d < best:
					best = d
					spot = Vector2i(x, y)
	check("obs.island_found", spot.x >= 0, str(spot))
	st.debug_fill_stage(Rect2i(spot, Vector2i(4, 4)), WorldState.STAGE_MATURE)
	var pr: Dictionary = place_gat(m, spot)
	check("obs.placed", bool(pr["ok"]))
	var plant: Dictionary = m.helpers.plant_by_uid(int(pr["uid"]))
	var centre: Vector2 = cc(spot)
	# inventory of obstacle kinds in range (teeth)
	var nest_in: bool = Vector2(nest.center_px(4)).distance_to(centre) < R
	var bld: int = 0
	var wall: int = 0
	for y: int in st.height:
		for x: int in st.width:
			var p: Vector2 = Vector2((x + 0.5) * 4.0, (y + 0.5) * 4.0)
			if p.distance_to(centre) <= R:
				var i: int = st.index_of(x, y)
				if not st.is_walkable(x, y) or st.target[i] == 0: bld += 1
				elif st.stage[i] == 0 and m.shot_blocked(centre, p): wall += 1
	info("obstacle teeth: nest in range=%s, non-greenable cells in range=%d, wall-shadowed free cells=%d" % [str(nest_in), bld, wall])
	m.enemies.add_nest  # keep nest alive; boars disabled below
	for b: Boar in m.enemies.boars.duplicate(): m.enemies.remove_boar(b)
	m.position = Vector2(88 * 4.0, 86 * 4.0)
	var bad: Array[String] = []
	var fired: int = 0
	var last_serial: int = m.helpers.fire_serial
	var nrect: Rect2i = nest.rect()
	var in_nest: int = 0
	for step: int in 1200:
		plant["stock"] = 12.0
		m.advance_game(0.1)
		for b: Boar in m.enemies.boars.duplicate(): m.enemies.remove_boar(b)
		var d: int = m.helpers.fire_serial - last_serial
		last_serial = m.helpers.fire_serial
		for k: int in range(m.helpers.flights.size() - d, m.helpers.flights.size()):
			if d <= 0: break
			var f: Dictionary = m.helpers.flights[k]
			var cx: int = int(f["cx"]); var cy: int = int(f["cy"])
			fired += 1
			var ci: int = st.index_of(cx, cy)
			var tp: Vector2 = Vector2((cx + 0.5) * 4.0, (cy + 0.5) * 4.0)
			var why: String = ""
			if nrect.has_point(Vector2i(cx, cy)): in_nest += 1; why += "nest "
			if not st.is_walkable(cx, cy) or st.target[ci] != 1: why += "ground "
			if st.occupant[ci] != 0: why += "occ "
			if st.stage[ci] != 0: why += "seeded "
			if m.shot_blocked(centre, tp): why += "wall "
			if tp.distance_to(centre) > R + 0.01: why += "range "
			if why != "": bad.append("%d,%d:%s" % [cx, cy, why])
	check("obs.targets_never_invalid", bad.is_empty() and fired > 30, "fired=%d bad=%s" % [fired, str(bad.slice(0, 5))])
	check("obs.nest_cells_never_seeded", in_nest == 0)
	# gatlinger targets never include nest cells even with a live nest in range
	check("obs.nest_still_alive_occupied", nest.alive and st.occupant[st.index_of(nest.tile.x, nest.tile.y)] != 0)

func _stock_zero(_R: float) -> void:
	var m: RefCounted = mk()
	var st: WorldState = m.state
	var spot: Vector2i = Vector2i(6, 6)
	st.debug_fill_stage(Rect2i(spot, Vector2i(4, 4)), WorldState.STAGE_MATURE)
	var pr: Dictionary = place_gat(m, spot)
	check("zero.placed", bool(pr["ok"]), str(pr.get("reason", "")))
	m.position = Vector2(88 * 4.0, 86 * 4.0)
	for b: Boar in m.enemies.boars.duplicate(): m.enemies.remove_boar(b)
	var plant: Dictionary = m.helpers.plant_by_uid(int(pr["uid"]))
	var max_mature: int = 0
	for i: int in 150:
		m.advance_game(0.1)
		max_mature = maxi(max_mature, own_mature(st, spot, 60.0))
	check("zero.no_fire_without_stock", m.helpers.fire_serial == 0 and float(plant["stock"]) == 0.0, "serial=%d stock=%.1f mature_around_max=%d (15s)" % [m.helpers.fire_serial, float(plant["stock"]), max_mature])
	plant["stock"] = 3.0
	for i: int in 150:
		m.advance_game(0.1)
		max_mature = maxi(max_mature, own_mature(st, spot, 60.0))
	check("zero.mature_stayed_below_receive_threshold", max_mature < 8, "max %d" % max_mature)
	check("zero.exactly_stock_fired_then_stops", m.helpers.fire_serial == 3 and float(plant["stock"]) == 0.0, "serial=%d stock=%.1f" % [m.helpers.fire_serial, float(plant["stock"])])
	check("zero.three_accounted", m.helpers.seeded_total + m.helpers.wasted_total + m.helpers.flights.size() == 3, "seeded=%d wasted=%d" % [m.helpers.seeded_total, m.helpers.wasted_total])

func own_mature(st: WorldState, o: Vector2i, r: float) -> int:
	var c: Vector2 = cc(o)
	var n: int = 0
	for y: int in st.height:
		for x: int in st.width:
			if Rect2i(o, Vector2i(4, 4)).has_point(Vector2i(x, y)): continue
			if st.stage[st.index_of(x, y)] == WorldState.STAGE_MATURE and Vector2((x + 0.5) * 4.0, (y + 0.5) * 4.0).distance_to(c) <= r: n += 1
	return n
