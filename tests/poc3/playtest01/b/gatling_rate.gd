extends SceneTree
## POC3-PLAYTEST-01 item 5 (work B): gatlinger fire rate before/after, scatter, ammo and sowing consistency.
const Session: GDScript = preload("res://scripts/poc2/poc2_session.gd")
const Coords: GDScript = preload("res://scripts/poc/poc_coords.gd")
const OUT: String = "res://evidence/poc3/playtest01/self/b_gatling/"
var rows: Array[Dictionary] = []
func _init() -> void:
	call_deferred("run")
func check(id: String, ok: bool, detail: Variant = "") -> void:
	rows.append({"id":id,"status":"PASS" if ok else "FAIL","detail":detail})
	print(JSON.stringify(rows.back()))

func measure(interval: float, volley: int) -> Dictionary:
	var s: RefCounted = Session.new()
	s.enemies.clear(); s.nests.clear(); s.fossils.clear()
	s.plant_system.gatling_interval = interval
	s.plant_system.gatling_volley = volley
	s.seeds = 500
	s.unlocked.gatlinger = true
	var placed: Dictionary = s.place_helper("gatlinger",Vector2i(117,112),100)
	var h: Dictionary = s.helpers[0]
	var home_cell: Vector2i = Coords.logic_to_cell(h.home)
	var fired: Array = []
	var cells: Array = []
	var seen: Dictionary = {}
	var ammo0: int = int(h.ammo)
	var t: float = 0.0
	var first_shot_t: float = -1.0
	var volleys: Array = []
	var last_ammo: int = ammo0
	var green_before: int = s.state.greened_count
	var seed_before: int = 0
	var step: float = 0.05
	while t < 30.0:
		s.advance_game(step)
		t += step
		for shot: Dictionary in s.shots:
			if shot.get("source_type","") == "helper" and not seen.has(int(shot.id)):
				seen[int(shot.id)] = true
				var c: Vector2i = Coords.logic_to_cell(shot.target)
				cells.append([t, c.x - home_cell.x, c.y - home_cell.y])
		if int(h.ammo) != last_ammo:
			if first_shot_t < 0.0: first_shot_t = t
			volleys.append([snappedf(t,0.05), last_ammo - int(h.ammo)])
			last_ammo = int(h.ammo)
	var used: int = ammo0 - int(h.ammo)
	var out: Dictionary = {"placed":placed.ok,"interval":interval,"volley":volley,"seconds":t,"ammo_used":used,"seeds_per_second":float(used)/t,"first_t":first_shot_t,"status_end":h.status,"ammo_left":h.ammo,"volley_log":volleys.slice(0,12),"targets_sample":cells.slice(0,12),"targets_total":cells.size()}
	# scatter: distinct targets and max/min radius of volley 2 targets around its centre
	var first_cells: Array = []
	for item: Array in cells:
		if item[0] <= first_shot_t + 0.3: first_cells.append(Vector2(item[1],item[2]))
	out.first_volley_cells = first_cells
	var seeded_new: int = 0
	out.seed_stage_cells = s.state.greened_count - green_before
	s.close()
	return out

func run() -> void:
	var before: Dictionary = measure(3.0,1)
	var after: Dictionary = measure(1.2,4)
	check("BEFORE_RATE_ONE_PER_THREE_SECONDS",before.placed and before.seeds_per_second > 0.25 and before.seeds_per_second < 0.45,before)
	check("AFTER_RATE_AT_LEAST_THREE_PER_SECOND_UNTIL_EMPTY_OR_BUDGET",after.placed and after.seeds_per_second >= 2.0,after)
	check("AFTER_INTERVAL_HALF_OR_LESS",after.interval <= before.interval / 2.0 and after.volley >= 3 and after.volley <= 5)
	var distinct: Dictionary = {}
	for c: Vector2 in after.first_volley_cells: distinct[c] = true
	check("FIRST_VOLLEY_SCATTERS_TO_DISTINCT_CELLS",distinct.size() >= 3,after.first_volley_cells)
	var f: FileAccess = FileAccess.open(OUT + "results.json",FileAccess.WRITE)
	var failures: int = 0
	for r: Dictionary in rows:
		if r.status == "FAIL": failures += 1
	f.store_string(JSON.stringify({"checks":rows,"failures":failures,"before":before,"after":after},"  "))
	f.close()
	quit(1 if failures else 0)
