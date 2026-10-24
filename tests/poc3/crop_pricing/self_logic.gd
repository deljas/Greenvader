extends SceneTree
const Session: GDScript = preload("res://scripts/poc2/poc2_session.gd")
const Save: GDScript = preload("res://scripts/poc2/save/poc2_save.gd")
const Coords: GDScript = preload("res://scripts/poc/poc_coords.gd")
const Equivalent: GDScript = preload("res://tests/poc2/view/equivalence.gd")
const OUT: String = "res://evidence/poc3/crop_pricing/self/"
var checks: Array[Dictionary] = []

func _init() -> void:
	call_deferred("run")

func check(label: String, passed: bool, detail: Variant = "") -> void:
	checks.append({"name":label,"status":"PASS" if passed else "FAIL","detail":detail})
	print(JSON.stringify(checks.back()))

func finish() -> void:
	var failures: int=0
	for row: Dictionary in checks:
		if row.status=="FAIL": failures+=1
	var file: FileAccess=FileAccess.open(OUT+"logic_results.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures},"  "))
	file.close()
	quit(1 if failures else 0)

func prices() -> bool:
	var s: RefCounted=Session.new(false)
	# Independently supplied decimal examples; the pricing formula is not copied.
	for example: Array in [[0,120],[5,154],[10,196],[20,319]]:
		s.plants.clear()
		for index: int in int(example[0]):
			s.plants.append({"kind":"watermelon","hp":80.0,"mature":false})
		check("watermelon_n"+str(example[0]),s.current_cost("watermelon")==example[1] and s.plant_stats("watermelon").count==example[0],s.current_cost("watermelon"))
	s.plants.append({"kind":"carrot","hp":30.0,"mature":true})
	s.plants.append({"kind":"watermelon","hp":0.0,"mature":true})
	check("different_kind_and_defeated_independent",s.current_cost("watermelon")==319 and s.current_cost("carrot")==16 and s.plant_stats("watermelon").count==20)
	check("helpers_keep_fixed_prices",s.current_cost("army")==25 and s.current_cost("gatlinger")==30 and s.current_cost("sprinkler")==20)
	for index: int in 1000: s.plants.append({"kind":"watermelon","hp":80.0,"mature":false})
	check("unrepresentable_price_stays_positive_unaffordable",s.current_cost("watermelon")>1000000000)
	# No systems were built on this price-only session.
	return true

func transactions() -> bool:
	var s: RefCounted=Session.new()
	s.unlocked.watermelon=true; s.unlocked.gatlinger=true; s.seeds=1000
	var paid: Array[int]=[]
	for x: int in [182,186,190]:
		var placed: Dictionary=s.place_plant("watermelon",Vector2i(x,184))
		if not placed.ok:
			check("continuous_real_placements",false,placed); s.close(); return true
		paid.append(int(s.plants.back().cost))
	check("continuous_real_placements",paid==[120,126,133] and s.seeds==621 and s.current_cost("watermelon")==139,paid)
	var count: int=s.plants.size()
	var before: int=s.seeds
	var blocked: Dictionary=s.place_plant("watermelon",Vector2i(182,184))
	check("blocked_placement_no_charge_no_count",not blocked.ok and s.seeds==before and s.plants.size()==count)
	s.seeds=138
	var insufficient: Dictionary=s.place_plant("watermelon",Vector2i(194,184))
	check("insufficient_no_charge_no_count",not insufficient.ok and s.seeds==138 and s.plants.size()==count)
	var first: int=s.plants[0].id
	var removed: Dictionary=s.remove_plant(first)
	check("manual_refund_actual_paid_and_price_falls",removed.ok and removed.refund==24 and s.seeds==162 and s.current_cost("watermelon")==133)
	s.plants[0].hp=0.0
	before=s.seeds
	s.plant_system.cleanup_defeated()
	check("enemy_destruction_no_refund_price_falls",s.seeds==before and s.plants.size()==1 and s.current_cost("watermelon")==126 and s.plant_stats("watermelon").count==1)
	s.plants[0].watered=true
	var saved: Dictionary=Save.save_game(s)
	var loaded: Dictionary=Save.load_game()
	check("actual_json_keeps_historical_cost_current_count_water",saved.ok and loaded.ok and loaded.session.plants[0].cost==133 and loaded.session.current_cost("watermelon")==126 and loaded.session.plants[0].watered and Equivalent.same(s.to_dict(),loaded.session.to_dict()) if loaded.ok else false)
	if loaded.ok: loaded.session.close()
	var baseline: Dictionary=s.to_dict()
	for value: Variant in [0,-5,1.25,1.0e20,INF]:
		var bad: Dictionary=baseline.duplicate(true)
		bad.entities.plants[0].cost=value
		var rejected: Dictionary=s.restore(bad)
		check("reject_invalid_paid_"+str(value),not rejected.ok and Equivalent.same(baseline,s.to_dict()),rejected)
	# A high historical payment remains valid after unrelated old plants vanished.
	var historical: Dictionary=baseline.duplicate(true)
	historical.entities.plants[0].cost=1234
	var accepted: Dictionary=s.restore(historical)
	var historical_id: int=s.plants[0].id
	check("historical_payment_not_rebuilt_from_current_n",accepted.ok and s.plants[0].cost==1234 and s.current_cost("watermelon")==126 and s.removal_refund(historical_id,false)==246)
	# Older working saves stored base cost, which is still an actual payment.
	var old: Dictionary=baseline.duplicate(true)
	old.entities.plants[0].cost=120
	check("old_base_payment_remains_valid",s.restore(old).ok and s.plants[0].cost==120)
	s.seeds=200
	var helper: Dictionary=s.place_helper("gatlinger",Vector2i(198,184),7)
	if helper.ok:
		var helper_save: Dictionary=s.to_dict()
		helper_save.entities.helpers[0].cost=31
		check("helper_price_still_strict_on_restore",not s.restore(helper_save).ok)
		var helper_removed: Dictionary=s.remove_helper(helper.id)
		check("gatlinger_unused_ammo_refund_maintained",helper_removed.ok and helper_removed.refund==13 and s.seeds==176)
	else:
		check("helper_fixture",false,helper)
	s.close()
	return true

func reservation() -> bool:
	var s: RefCounted=Session.new()
	s.enemies.clear(); s.nests.clear(); s.fossils.clear()
	s.seeds=12; s.sow_width=3
	s.position=Coords.cell_center_logic(Vector2i(187,188))
	s.set_aim(Coords.cell_center_logic(Vector2i(191,188)))
	for y: int in range(187,190):
		for x: int in range(190,193): s.state.set_stage(s.state.index_of(x,y),WorldState.STAGE_EMPTY)
	var shot: Dictionary=s.fire()
	var crop: Dictionary=s.place_plant("clover",Vector2i(182,184))
	s.combat_system._shots(0.25)
	var planted: int=0
	for y: int in range(187,190):
		for x: int in range(190,193):
			if s.state.stage[s.state.index_of(x,y)]==WorldState.STAGE_SEED: planted+=1
	check("flying_area_reservation_other_spending_no_negative",shot.ok and crop.ok and s.seeds==0 and planted==2 and s.plants[0].cost==10 and s.current_cost("clover")==11 and s.shots.is_empty(),{"seeds":s.seeds,"area_seeded":planted})
	s.close()
	return true

func run() -> void:
	if not OS.get_user_data_dir().replace("\\","/").contains("evidence/poc3/crop_pricing/self/profile/"):
		push_error("profile not isolated"); quit(1); return
	for method: String in ["prices","transactions","reservation"]:
		if call(method)!=true: check(method+"_completed",false,"runtime error")
	finish()
