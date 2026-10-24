extends SceneTree
const Session: GDScript = preload("res://scripts/poc2/poc2_session.gd")
const Save: GDScript = preload("res://scripts/poc2/save/poc2_save.gd")
const Equivalent: GDScript = preload("res://tests/poc2/view/equivalence.gd")
const OUT: String = "res://evidence/poc3/crop_pricing/independent/"
var checks: Array[Dictionary] = []

func _init() -> void:
	call_deferred("run")

func check(id: String, ok: bool, detail: Variant = "") -> void:
	checks.append({"id":id,"status":"PASS" if ok else "FAIL","detail":detail})
	print(JSON.stringify(checks.back()))

func count_prices() -> bool:
	var s: RefCounted = Session.new(false)
	for index: int in 10:
		s.plants.append({"kind":"watermelon","hp":80.0,"mature":false})
	s.plants.append({"kind":"watermelon","hp":0.0,"mature":true})
	s.plants.append({"kind":"wheat","hp":50.0,"mature":false})
	check("SAME_KIND_LIVING_IMMATURE_ONLY",s.current_cost("watermelon") == 196 and s.plant_stats("watermelon").count == 10 and s.current_cost("wheat") == 42,{"watermelon":s.current_cost("watermelon"),"wheat":s.current_cost("wheat")})
	s.helpers.append({"kind":"army","hp":80.0})
	s.helpers.append({"kind":"army","hp":80.0})
	check("HELPERS_FIXED",s.current_cost("army") == 25 and s.current_cost("gatlinger") == 30 and s.current_cost("sprinkler") == 20)
	return true

func transactions() -> bool:
	var s: RefCounted = Session.new()
	s.unlocked.wheat = true
	s.seeds = 300
	var payments: Array[int] = []
	for x: int in [182,186,190]:
		var result: Dictionary = s.place_plant("wheat",Vector2i(x,184))
		if not result.ok:
			check("FIXTURE_PLACEMENT",false,result)
			s.close()
			return true
		payments.append(int(s.plants.back().cost))
	# Independently evaluated decimal examples: 40,42,44.1 -> ceil 40,42,45;
	# next product is 46.305 -> 47. Do not copy current_cost into the oracle.
	check("CONSECUTIVE_PAYMENT_RECOMPUTED",payments == [40,42,45] and s.seeds == 173 and s.current_cost("wheat") == 47,{"paid":payments,"balance":s.seeds,"next":s.current_cost("wheat")})
	var original: Dictionary = s.to_dict()
	var occupied: Dictionary = s.place_plant("wheat",Vector2i(182,184))
	check("BLOCKED_NO_CHARGE_OR_COUNT",not occupied.ok and Equivalent.same(original,s.to_dict()),occupied)
	s.seeds = 46
	original = s.to_dict()
	var short: Dictionary = s.place_plant("wheat",Vector2i(194,184))
	check("INSUFFICIENT_NO_CHARGE_OR_COUNT",not short.ok and Equivalent.same(original,s.to_dict()),short)
	s.seeds = 173
	var removed: Dictionary = s.remove_plant(s.plants[1].id)
	check("REMOVE_PAID42_REFUND8_COUNT_DECREASE",removed.ok and removed.refund == 8 and s.seeds == 181 and s.current_cost("wheat") == 45 and s.plant_stats("wheat").count == 2)
	s.plants[0].hp = 0.0
	var price_before_cleanup: int = s.current_cost("wheat")
	s.plant_system.cleanup_defeated()
	check("DESTRUCTION_REFUND_ZERO_COUNT_DECREASE",s.seeds == 181 and s.plants.size() == 1 and s.plants[0].cost == 45 and price_before_cleanup == 42 and s.current_cost("wheat") == 42)
	original = s.to_dict()
	var saved: Dictionary = Save.save_game(s)
	var loaded: Dictionary = Save.load_game()
	var exact: bool = loaded.ok and Equivalent.same(original,loaded.session.to_dict())
	check("JSON_HISTORICAL_PAID_SURVIVES",saved.ok and exact and loaded.session.plants[0].cost == 45 and loaded.session.current_cost("wheat") == 42 if loaded.ok else false,{"saved":saved.ok,"loaded":loaded.ok,"same":exact})
	if loaded.ok:
		var refund: Dictionary = loaded.session.remove_plant(loaded.session.plants[0].id)
		check("RESTORED_REFUND_FROM_PAID_NOT_CURRENT",refund.ok and refund.refund == 9 and loaded.session.seeds == 190 and loaded.session.current_cost("wheat") == 40,{"refund":refund,"balance":loaded.session.seeds})
		loaded.session.close()
	else:
		check("RESTORED_REFUND_FROM_PAID_NOT_CURRENT",false,"load failed")
	var malformed: Dictionary = original.duplicate(true)
	malformed.entities.plants[0].cost = 45.5
	var rejected: Dictionary = s.restore(malformed)
	check("FRACTIONAL_PAYMENT_ATOMIC_REJECT",not rejected.ok and Equivalent.same(original,s.to_dict()),rejected)
	s.close()
	return true

func run() -> void:
	if not OS.get_user_data_dir().replace("\\","/").contains("evidence/poc3/crop_pricing/independent/profile/"):
		quit(2)
		return
	for method: String in ["count_prices","transactions"]:
		if call(method) != true: check(method+"_completed",false,"runtime abort")
	var failed: int = 0
	for row: Dictionary in checks:
		if row.status == "FAIL": failed += 1
	var file: FileAccess = FileAccess.open(OUT+"results.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failed,"engine":Engine.get_version_info(),"user_dir":OS.get_user_data_dir()},"  "))
	file.close()
	quit(1 if failed else 0)
