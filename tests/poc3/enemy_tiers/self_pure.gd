extends SceneTree
## Prepared without running Godot. Run once only after the parent grants execution.
const Tiers: GDScript = preload("res://scripts/poc2/simulation/enemy_tiers.gd")
const OUT: String = "res://evidence/poc3/enemy_tiers/self/"
var checks: Array[Dictionary] = []

func _init() -> void:
	call_deferred("run")

func check(label: String, passed: bool, detail: Variant = "") -> void:
	checks.append({"name":label,"status":"PASS" if passed else "FAIL","detail":detail})
	print(JSON.stringify(checks.back()))

func boundaries() -> bool:
	# 0.1m per logic pixel. Explicit expected bands, including equality boundaries.
	var start: Vector2=Vector2(450.0,450.0)
	for example: Array in [[179.99,0],[180.0,1],[319.99,1],[320.0,2]]:
		var actual: int=Tiers.tier_for(start,start+Vector2(example[0],0.0))
		check("boundary_"+str(example[0])+"px",actual==example[1],actual)
	check("distance_is_euclidean",Tiers.tier_for(start,start+Vector2(108.0,144.0))==1)
	check("valid_tier_range",not Tiers.valid_tier(-1) and Tiers.valid_tier(0) and Tiers.valid_tier(1) and Tiers.valid_tier(2) and not Tiers.valid_tier(3))
	return true

func multipliers() -> bool:
	# Decimal expectations are supplied directly rather than copying multiplier math.
	for row: Array in [[20.0,[20.0,26.0,34.0]],[40.0,[40.0,52.0,68.0]],[100.0,[100.0,130.0,170.0]],[240.0,[240.0,312.0,408.0]]]:
		var correct: bool=true
		for tier: int in 3: correct=correct and is_equal_approx(Tiers.hp(row[0],tier),row[1][tier])
		check("hp_base_"+str(row[0]),correct)
	for row: Array in [[5.0,[5.0,6.0,7.0]],[12.0,[12.0,14.4,16.8]],[10.0,[10.0,12.0,14.0]]]:
		var correct: bool=true
		for tier: int in 3: correct=correct and is_equal_approx(Tiers.attack(row[0],tier),row[1][tier])
		check("attack_base_"+str(row[0]),correct)
	for row: Array in [[6,[6,9,12]],[15,[15,22,30]],[30,[30,45,60]],[80,[80,120,160]],[200,[200,300,400]]]:
		var correct: bool=true
		for tier: int in 3: correct=correct and Tiers.reward(row[0],tier,true)==row[1][tier] and Tiers.reward(row[0],tier,false)==0
		check("initial_reward_and_spawned_zero_base_"+str(row[0]),correct)
	return true

func run() -> void:
	if not OS.get_user_data_dir().replace("\\","/").contains("evidence/poc3/enemy_tiers/self/profile/"):
		push_error("profile not isolated"); quit(1); return
	for method: String in ["boundaries","multipliers"]:
		if call(method)!=true: check(method+"_completed",false,"runtime error")
	var failures: int=0
	for row: Dictionary in checks:
		if row.status=="FAIL": failures+=1
	var file: FileAccess=FileAccess.open(OUT+"pure_results.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures},"  "))
	file.close()
	quit(1 if failures else 0)
