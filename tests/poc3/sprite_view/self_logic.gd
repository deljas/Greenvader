extends SceneTree
const Catalog: GDScript = preload("res://scripts/poc2/view/entity_sprite_catalog.gd")
const State: GDScript = preload("res://scripts/poc2/view/entity_sprite_state.gd")
const OUT: String = "res://evidence/poc3/sprite_view/self/"
var checks: Array[Dictionary] = []

func _init() -> void:
	call_deferred("run")

func check(label: String, passed: bool) -> void:
	checks.append({"name":label,"status":"PASS" if passed else "FAIL"})
	print(checks.back())

func run() -> void:
	var catalog: RefCounted = Catalog.new()
	var boar: Dictionary = catalog.definition_for("enemies","boar")
	var native: Dictionary = Catalog.sample(boar,"idle",&"down",0.0)
	check("native_boar_32x18_no_resampling",native.frame_pixels==Vector2i(32,18) and native.texture.get_size()==Vector2(32,18))
	var small: Dictionary = Catalog.sample(catalog.definition_for("plants","clover"),"growing",&"down",0.0)
	var grown: Dictionary = Catalog.sample(catalog.definition_for("plants","clover"),"mature",&"down",0.0)
	check("clover_separate_native_growth_art",small.frame_pixels==Vector2i(8,8) and grown.frame_pixels==Vector2i(16,16) and small.anchor==Vector2(4,7) and grown.anchor==Vector2(8,15))
	check("large_unprovided_art_keeps_mesh",catalog.definition_for("plants","watermelon").is_empty() and catalog.definition_for("nests","mother").is_empty())
	var resolver: RefCounted = State.new()
	var enemy: Dictionary = {"pos":Vector2.ZERO,"hp":20.0,"phase":"idle"}
	var original: Dictionary = enemy.duplicate(true)
	check("enemy_idle_read_only",resolver.resolve("enemies",enemy,0.0).state=="idle" and enemy==original)
	enemy.pos=Vector2(1,-1)
	check("enemy_movement_direction",resolver.resolve("enemies",enemy,0.1).state=="move" and resolver.direction==&"right")
	var states_ok: bool = true
	for pair: Array in [["windup","windup"],["charge","attack"],["eating","eat"]]:
		enemy.phase=pair[0]
		states_ok=states_ok and resolver.resolve("enemies",enemy,0.2).state==pair[1]
	enemy.hp=19.0
	check("enemy_windup_attack_eat_hit",states_ok and resolver.resolve("enemies",enemy,0.3).state=="hit")
	var helper: RefCounted = State.new()
	var item: Dictionary = {"pos":Vector2.ZERO,"kind":"army","status":"guarding"}
	var helper_ok: bool = helper.resolve("helpers",item,0.0).state=="idle"
	for pair: Array in [["fighting","attack"],["sowing","sow"],["watering","water"],["fleeing","flee"]]:
		item.status=pair[0]
		helper_ok=helper_ok and helper.resolve("helpers",item,1.0).state==pair[1]
	item.status="moving"
	item.pos=Vector2(1,1)
	check("helper_idle_move_attack_sow_water_flee",helper_ok and helper.resolve("helpers",item,2.0).state=="move")
	var crop: RefCounted = State.new()
	item={"pos":Vector2.ZERO,"age":0.0,"mature":false}
	var crop_ok: bool = crop.resolve("plants",item,0.0).state=="planted"
	item.age=1.0
	crop_ok=crop_ok and crop.resolve("plants",item,1.0).state=="growing"
	item.mature=true
	check("crop_planted_growing_mature",crop_ok and crop.resolve("plants",item,2.0).state=="mature")
	enemy.visual_state="eat"
	enemy.visual_direction="up"
	check("future_state_direction_ingress",resolver.resolve("enemies",enemy,2.0).state=="eat" and resolver.direction==&"up")
	# Simulate supplied future four-direction animation definitions, without creating new art.
	var first: Dictionary = Catalog.clip(native.texture,Vector2i(16,16))
	first.frames=[native.texture,native.texture]
	first.fps=4.0
	var definition: Dictionary = {"clips":{"idle":{"directions":{"up":first,"down":Catalog.clip(grown.texture,Vector2i(8,15))}}}}
	var sampled: Dictionary = Catalog.sample(definition,"idle",&"up",0.3)
	check("direction_frames_and_fixed_anchor",sampled.frame==1 and sampled.texture==native.texture and sampled.anchor==Vector2(16,16))
	catalog.register("nests","custom",{"clips":{"idle":first}})
	check("fixed_nest_definition_replaceable",not catalog.definition_for("nests","custom").is_empty())
	finish("logic_results.json")

func finish(filename: String) -> void:
	var failures: int = 0
	for result: Dictionary in checks:
		if result.status=="FAIL": failures+=1
	var file: FileAccess = FileAccess.open(OUT+filename,FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures},"  "))
	file.close()
	quit(1 if failures>0 else 0)
