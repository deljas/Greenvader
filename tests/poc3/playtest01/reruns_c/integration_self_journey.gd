extends "res://tests/poc3/integration/self_core.gd"
## One bounded gameplay-API route, without resource/HP/unlock/terrain injection.
var trace: Array[Dictionary] = []

func travel(s: RefCounted, destination: Vector2) -> bool:
	var route: Array[Vector2i] = s.nav.route(s.position,destination)
	if route.is_empty(): return false
	for index: int in range(1,route.size()):
		var target: Vector2 = Coords.cell_center_logic(route[index])
		var attempts: int = 0
		while s.position.distance_to(target)>0.01 and attempts<12:
			var offset: Vector2 = target-s.position
			var dt: float = minf(offset.length()/48.0,0.125)
			s.walk(Coords.ground_dir_to_screen(offset.normalized()),dt)
			s.advance_game(dt)
			attempts+=1
		if s.position.distance_to(target)>0.01:
			trace.append({"blocked_step":index,"position":s.position,"target":target})
			return false
	return true

func collect(s: RefCounted, kind: String) -> bool:
	for fossil: Dictionary in s.fossils:
		if fossil.unlock==kind and int(fossil.nest_id)<0:
			if not travel(s,fossil.pos): return false
			s.reveal()
			trace.append({"collected":kind,"position":s.position,"elapsed":s.clock.elapsed})
			return bool(fossil.found) and bool(s.unlocked.get(kind,false))
	return false

func nest_present(s: RefCounted, id: int) -> bool:
	for nest: Dictionary in s.nests:
		if int(nest.id)==id: return true
	return false

func gameplay_route() -> bool:
	var s: RefCounted = Session.new()
	var carrot: bool = collect(s,"carrot")
	check("JOURNEY_WALK_REVEAL_UNLOCKS_CARROT",carrot,trace)
	if not carrot:
		s.close()
		return true
	var nearest: Dictionary = s.nests[0]
	var path: Array[Vector2i] = s.nav.route(s.position,nearest.pos)
	var staging: Vector2 = Vector2(-1,-1)
	for cell: Vector2i in path:
		var candidate: Vector2 = Coords.cell_center_logic(cell)
		var distance: float = candidate.distance_to(nearest.pos)
		if distance>=32.0 and distance<=56.0 and not s.placement.blocks_projectile(candidate,nearest.pos):
			staging=candidate
			break
	var approached: bool = staging.x>=0.0 and travel(s,staging)
	check("JOURNEY_APPROACH_ACTIVATES_NEAR_FRONT",approached and nearest.active,{"staging":staging,"active":nearest.active,"hp":s.hp})
	if not approached:
		s.close()
		return true
	var used_fire: int = 0
	var used_bazooka: int = 0
	var used_tackle: int = 0
	# Bounded 80-game-second combat. Uses normal HP, resources, cooldowns and AI.
	for tick: int in 320:
		if not nest_present(s,int(nearest.id)): break
		var target: Vector2 = nearest.pos
		var closest: float = 70.0
		for enemy: Dictionary in s.enemies:
			var distance: float = enemy.pos.distance_to(s.position)
			if distance<closest and not s.placement.blocks_projectile(s.position,enemy.pos):
				closest=distance
				target=enemy.pos
		s.set_aim(target)
		if closest<16.0 and s.clock.elapsed>=float(s.skill_ready[0]):
			if s.skill(0).ok: used_tackle+=1
		elif s.clock.elapsed>=float(s.skill_ready[1]) and s.seeds>=3:
			if s.skill(1).ok: used_bazooka+=1
		else:
			if s.fire().ok: used_fire+=1
		s.advance_game(0.25)
	var conquered: bool = not nest_present(s,int(nearest.id))
	check("JOURNEY_REAL_FIRE_SKILL_CONQUER_NEAR_NEST",conquered and used_bazooka>0 and used_fire+used_tackle>0,{"fire":used_fire,"bazooka":used_bazooka,"tackle":used_tackle,"hp":s.hp,"seed":s.seeds,"elapsed":s.clock.elapsed})
	if not conquered:
		s.close()
		return true
	check("JOURNEY_NEST_FOSSIL_UNLOCKS_ARMY",s.unlocked.get("army",false))
	var gat: bool = collect(s,"gatlinger")
	var sprinkler: bool = collect(s,"sprinkler")
	check("JOURNEY_EXPLORATION_UNLOCKS_WORKERS",gat and sprinkler,trace)
	# A different front is contacted by walking. Killing every remaining nest here
	# is not required; post-clear exact-100% has its separate explicit damage setup.
	var second: Dictionary = s.nests[0]
	var second_path: Array[Vector2i] = s.nav.route(s.position,second.pos)
	var second_goal: Vector2 = second.pos
	for cell: Vector2i in second_path:
		var candidate: Vector2 = Coords.cell_center_logic(cell)
		if candidate.distance_to(second.pos)<80.0:
			second_goal=candidate
			break
	var second_contact: bool = travel(s,second_goal)
	s.advance_game(0.25)
	check("JOURNEY_ANOTHER_DIRECTION_FRONT_ACTIVATES",second_contact and second.active,{"kind":second.kind,"home":second.home,"active":second.active,"position":s.position})
	var returned: bool = travel(s,s.start_position())
	check("JOURNEY_RETURNS_TO_CENTRAL_SUPPLY",returned)
	# Earn any missing investment from actual land income, not a balance injection.
	var needed: int = 15+25+30+5+20
	var budget_wait: float = 0.0
	while s.seeds<needed and budget_wait<1800.0:
		s.advance_game(10.0)
		budget_wait+=10.0
	var places: Dictionary = {}
	for kind: String in ["carrot","army","gatlinger","sprinkler"]:
		var result_: Dictionary = {"ok":false}
		for dy: int in range(-6,7):
			for dx: int in range(-6,7):
				var cell: Vector2i = Coords.logic_to_cell(s.start_position())+Vector2i(dx,dy)
				if not s.can_place(kind,cell).ok: continue
				result_=s.place_plant(kind,cell) if kind=="carrot" else s.place_helper(kind,cell,5 if kind=="gatlinger" else 0)
				break
			if result_.ok: break
		places[kind]=result_
	check("JOURNEY_PLACES_CROP_AND_THREE_HELPERS",s.plants.size()==1 and s.helpers.size()==3,{"results":places,"income_wait_game_seconds":budget_wait,"seeds":s.seeds})
	if s.plants.is_empty() or s.helpers.size()!=3:
		s.close()
		return true
	s.water_at(s.plants[0].pos)
	s.set_favorite(1,"carrot")
	s.set_favorite(2,"army")
	s.set_favorite(3,"gatlinger")
	s.set_favorite(4,"sprinkler")
	for helper: Dictionary in s.helpers:
		if helper.kind=="army": s.move_helper(int(helper.id),s.start_position()+Vector2(8,0))
	s.advance_game(0.25)
	var original: Dictionary = s.to_dict()
	var saved: Dictionary = Save.save_game(s)
	var restored: Dictionary = Save.load_game()
	check("JOURNEY_HELPERS_CROP_DISCOVERY_JSON_FULL_EQUAL",saved.ok and restored.ok and Equivalent.same(original,restored.session.to_dict()) if restored.ok else false,{"saved":saved.ok,"loaded":restored.ok})
	if restored.ok:
		var r: RefCounted = restored.session
		var elapsed: float = r.clock.elapsed
		r.advance_game(1.0)
		check("JOURNEY_RESTORED_SYSTEMS_CONTINUE",r.clock.elapsed>elapsed and r.helpers.size()==3 and r.plants.size()==1)
		r.close()
	s.close()
	return true

func run() -> void:
	if not OS.get_cmdline_user_args().has("--integration-authorized") or not OS.get_user_data_dir().replace("\\","/").contains("evidence/poc3/playtest01/self/rerun_C_integration/profile/"):
		quit(2)
		return
	if gameplay_route()!=true: check("gameplay_route_completed",false,"runtime abort")
	observations.trace=trace
	finish("journey_results.json")
