extends SceneTree
## HLP-03 independent A: spread origin sync (new game / save-load / fixtures) + knockback guard. Own save namespace.
const Session: GDScript = preload("res://scripts/poc/poc_session.gd")
const PocSave: GDScript = preload("res://scripts/poc/save/poc_save.gd")
const Config: GDScript = preload("res://scripts/poc/poc_config.gd")
const Coords: GDScript = preload("res://scripts/poc/poc_coords.gd")
const DIR: String = "user://poc_saves_indep_hlp03/"
const OUT: String = "res://evidence/helper/03/independent/"
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

func _init() -> void:
	_run.call_deferred()

func mk_town() -> RefCounted:
	var size: Vector2i = Session.town_size()
	var m: RefCounted = Session.new(size.x, size.y)
	m.paving = Session.paving_from(m.env_tuning)
	m.load_combat(Session.TOWN_SETUP)
	keep.append(m)
	return m

func green_set(st: WorldState) -> PackedByteArray:
	var g: PackedByteArray = PackedByteArray()
	g.resize(st.tile_count())
	for i: int in st.tile_count():
		g[i] = 1 if (st.target[i] != 0 and st.stage[i] >= WorldState.STAGE_MATURE) else 0
	return g

func count(g: PackedByteArray) -> int:
	var n: int = 0
	for v: int in g: n += v
	return n

## new green cells (not in `base`), and how many of them touch (8-neighbour) a green cell of `base` or of the current set
func new_cells(st: WorldState, base: PackedByteArray) -> Array:
	var cur: PackedByteArray = green_set(st)
	var n: int = 0
	var adj: int = 0
	var w: int = st.width
	for i: int in st.tile_count():
		if cur[i] == 1 and base[i] == 0:
			n += 1
			var x: int = i % w
			var y: int = i / w
			var touch: bool = false
			for dy: int in range(-1, 2):
				for dx: int in range(-1, 2):
					if st.in_bounds(x + dx, y + dy) and cur[st.index_of(x + dx, y + dy)] == 1 and (dx != 0 or dy != 0):
						touch = true
			if touch: adj += 1
	return [n, adj]

func run_for(m: RefCounted, seconds: float) -> void:
	var left: float = seconds
	while left > 0.0:
		m.advance_game(0.5)
		left -= 0.5

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	for f: String in DirAccess.get_files_at(DIR): DirAccess.remove_absolute(DIR + f)
	_cond1()
	_cond2()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var f: FileAccess = FileAccess.open(OUT + "a.log", FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\nRESULT passes=%d failures=%d\n" % [passes, fails])
	f.close()
	for f2: String in DirAccess.get_files_at(DIR): DirAccess.remove_absolute(DIR + f2)
	print("RESULT passes=%d failures=%d" % [passes, fails])
	for m: RefCounted in keep: m.close()
	quit(1 if fails > 0 else 0)

func _cond1() -> void:
	var m: RefCounted = mk_town()
	var st: WorldState = m.state
	var base: PackedByteArray = green_set(st)
	var n0: int = count(base)
	check("c1.initial_mature_exists", n0 > 100, "initial mature cells=%d greened_count=%d" % [n0, st.greened_count])
	run_for(m, 180.0)
	var r: Array = new_cells(st, base)
	check("c1.new_game_spreads_from_initial_edge", r[0] > 0 and r[1] == r[0], "t=%.0fs new green cells=%d (touching other green=%d) greened_count=%d" % [m.clock.elapsed, r[0], r[1], st.greened_count])
	# save, load, then advance both the same time
	var saved: Dictionary = PocSave.save(m, DIR, {"resolution_index": 0})
	var loaded: Dictionary = PocSave.load_slot(DIR, false, Callable(self, "mk_town"))
	check("c1.save_load_ok", bool(saved["ok"]) and bool(loaded["ok"]), str(saved.get("reason", "")) + str(loaded.get("reason", "")))
	if not (bool(saved["ok"]) and bool(loaded["ok"])): return
	var c: RefCounted = loaded["session"]
	keep.append(c)
	var base_o: PackedByteArray = green_set(st)
	var base_c: PackedByteArray = green_set(c.state)
	check("c1.loaded_equal_at_save", base_o == base_c and st.greened_count == c.state.greened_count, "orig=%d copy=%d" % [st.greened_count, c.state.greened_count])
	run_for(m, 240.0)
	run_for(c, 240.0)
	var ro: Array = new_cells(st, base_o)
	var rc: Array = new_cells(c.state, base_c)
	check("c1.loaded_keeps_spreading", rc[0] > 0, "copy new cells after +240s=%d" % rc[0])
	check("c1.loaded_matches_original", green_set(st) == green_set(c.state) and hash(st.stage) == hash(c.state.stage) and st.greened_count == c.state.greened_count, "orig new=%d copy new=%d greened %d vs %d" % [ro[0], rc[0], st.greened_count, c.state.greened_count])
	# fixtures
	for path: String in ["res://data/poc/maps/fixture_02.json", "res://data/poc/maps/fixture_04.json"]:
		var f: RefCounted = Session.new()
		keep.append(f)
		var ok: bool = f.load_placement(path)
		var b: PackedByteArray = green_set(f.state)
		var nn: int = count(b)
		if nn == 0:
			check("c1.fixture_" + path.get_file(), ok, "load ok=%s, no initial mature cells (spread not applicable)" % ok)
			continue
		run_for(f, 240.0)
		var rf: Array = new_cells(f.state, b)
		check("c1.fixture_" + path.get_file(), ok and rf[0] > 0, "initial mature=%d new after 240s=%d" % [nn, rf[0]])

func _cond2() -> void:
	var m: RefCounted = mk_town()
	var st: WorldState = m.state
	var half: Vector2 = Config.player_half_px()
	var tp: float = Config.TILE_PX
	# find open cells adjacent to a wall (building terrain), try 4 directions
	var tried: int = 0
	var bad: int = 0
	var worst: String = ""
	var open_moved: float = 0.0
	var open_tried: int = 0
	var cell_list: Array[Vector2i] = []
	for y: int in range(3, st.height - 3, 7):
		for x: int in range(3, st.width - 3, 7):
			cell_list.append(Vector2i(x, y))
	for c0: Vector2i in cell_list:
		for dir: Vector2 in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
			if not Walker.is_clear(st, tp, Coords.cell_center_logic(c0), half): continue
			m.position = Coords.cell_center_logic(c0)
			m.play.health.invuln_steps = 0
			m.play.health.downed = false
			# walk in `dir` (ground) until stopped by a wall (max 3 s)
			var scr: Vector2 = Coords.ground_dir_to_screen(dir)
			var moved_total: float = 0.0
			for i: int in 30:
				moved_total += m.walk(scr, 0.1).length()
			var hit_wall: bool = moved_total < 28.0 * 0.1 * Config.walk_speed_px() / 30.0 * 30.0 * 0.99 - 1.0 and moved_total < 30 * 0.1 * Config.walk_speed_px() * 0.9
			var at: Vector2 = m.position
			if not hit_wall:
				# open: knock and measure
				m.play.health.hit(m.play, 1, at - dir * 6.0 * 1.0, at)
				for i: int in 40:
					m.advance_game(0.05)
				open_tried += 1
				open_moved += m.position.distance_to(at)
				continue
			tried += 1
			m.play.health.hit(m.play, 1, at - dir * 3.0, at)   # source behind the player -> pushed into the wall
			for i: int in 60:
				m.advance_game(0.05)
				if not m.is_walkable_logic(m.position):
					bad += 1
					worst = "cell %s dir %s pos %s" % [c0, dir, m.position]
					break
	check("c2.knockback_never_enters_wall", tried >= 10 and bad == 0, "wall-contact knocks=%d violations=%d %s" % [tried, bad, worst])
	check("c2.open_knockback_still_pushes", open_tried >= 5 and open_moved / float(open_tried) > 1.0, "open knocks=%d mean displacement=%.2f px (tuning knockback_px=%.1f)" % [open_tried, open_moved / float(maxi(open_tried, 1)), m.play.health.tuning.knockback_px])
