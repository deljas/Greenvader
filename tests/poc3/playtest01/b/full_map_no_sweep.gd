extends SceneTree
## POC3-PLAYTEST-01 item 13: all hostiles removed, no input, fair sweep disabled by the PoC3 tuning override.
## Measures game time to exact 100 % (isolated targets included) and where it stalls if it does.
const Session: GDScript = preload("res://scripts/poc2/poc2_session.gd")
const OUT: String = "res://evidence/poc3/playtest01/self/b_full_map/"
var rows: Array[Dictionary] = []
var obs: Dictionary = {}

func _init() -> void:
	call_deferred("run")

func check(id: String, ok: bool, detail: Variant = "") -> void:
	rows.append({"id":id,"status":"PASS" if ok else "FAIL","detail":detail})
	print(JSON.stringify(rows.back()))

func run() -> void:
	if not "--b-authorized" in OS.get_cmdline_user_args():
		quit(2)
		return
	var s: RefCounted = Session.new()
	for nest: Dictionary in s.nests.duplicate():
		s.combat_system.damage_nest(nest,float(nest.hp)+1.0)
	for enemy: Dictionary in s.enemies.duplicate():
		s.combat_system.damage_enemy(enemy,float(enemy.hp)+1.0)
	s.advance_game(1.0)
	check("STABLE_AFTER_CLEAR",s.nests.is_empty() and s.enemies.is_empty() and s.state.zone_state[0]>=WorldState.ZONE_STABLE)
	check("SWEEP_DELAY_EFFECTIVELY_INFINITE",s.sim_tuning.far_sweep_start_delay_seconds>=1.0e8,s.sim_tuning.far_sweep_start_delay_seconds)
	var island: Array[int] = []
	for y: int in range(146,150):
		for x: int in range(150,154):
			var index: int = s.state.index_of(x,y)
			if s.state.target[index]==1: island.append(index)
	var start_clock: float = s.clock.elapsed
	var start_green: int = s.state.greened_count
	var old_max: float = s.clock.max_advance
	s.clock.max_advance=120.0
	var cap: float = 86400.0
	var last_green: int = start_green
	var last_change: float = s.clock.elapsed
	var timeline: Array = []
	var top_edge_before: int = 0
	while not s.state.is_fully_greened() and s.clock.elapsed-start_clock<=cap and s.clock.elapsed-last_change<7200.0:
		s.clock.advance(120.0)
		if s.state.greened_count!=last_green:
			last_green=s.state.greened_count
			last_change=s.clock.elapsed
		if int((s.clock.elapsed-start_clock)/600.0)>timeline.size():
			timeline.append([int(s.clock.elapsed-start_clock),s.state.greened_count])
	s.clock.max_advance=old_max
	s.advance_game(1.0)
	var island_green: int = 0
	for index: int in island:
		if s.state.stage[index]>=WorldState.GREENED_MIN_STAGE: island_green+=1
	# Remaining non-green targets (if any): count and bounding box
	var missing: int = 0
	var box: Rect2i = Rect2i()
	var first: bool = true
	for index: int in s.state.tile_count():
		if s.state.target[index]==1 and s.state.stage[index]<WorldState.GREENED_MIN_STAGE:
			missing+=1
			var c: Vector2i = Vector2i(index%s.state.width,index/s.state.width)
			if first: box=Rect2i(c,Vector2i(1,1)); first=false
			else: box=box.expand(c)
	obs={"game_seconds":s.clock.elapsed-start_clock,"game_minutes":(s.clock.elapsed-start_clock)/60.0,"start_green":start_green,"greened":s.state.greened_count,"targets":s.state.target_count,"missing":missing,"missing_box":[box.position,box.end],"sweep_planted":s.far.total_sweep_planted,"island_planted":s.far.total_island_planted,"island_before_targets":island.size(),"island_green":island_green,"timeline":timeline,"input_events":0}
	check("FULL_MAP_100_WITHOUT_SWEEP",s.state.greened_count==s.state.target_count and s.state.is_fully_greened() and s.state.cleared and s.state.counters_consistent(),obs)
	check("NO_SWEEP_PLANTING",s.far.total_sweep_planted==0,s.far.total_sweep_planted)
	check("ISLAND_GREENED",island.size()>0 and island_green==island.size(),{"green":island_green,"targets":island.size()})
	check("NO_REINVASION",s.enemies.is_empty() and s.nests.is_empty())
	s.close()
	var failures: int = 0
	for row: Dictionary in rows:
		if row.status=="FAIL": failures+=1
	var file: FileAccess = FileAccess.open(OUT+"results.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":rows,"failures":failures,"observations":obs},"  "))
	file.close()
	quit(1 if failures else 0)
