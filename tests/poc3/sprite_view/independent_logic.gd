extends SceneTree
const Catalog: GDScript = preload("res://scripts/poc2/view/entity_sprite_catalog.gd")
const State: GDScript = preload("res://scripts/poc2/view/entity_sprite_state.gd")
const Card: GDScript = preload("res://scripts/poc2/view/entity_sprite.gd")
const OUT: String = "res://evidence/poc3/sprite_view/independent/"
var rows: Array[Dictionary] = []

func _init() -> void:
	call_deferred("run")

func check(id: String, ok: bool, detail: Variant = "") -> void:
	rows.append({"id":id,"status":"PASS" if ok else "FAIL","detail":detail})
	print(JSON.stringify(rows.back()))

func state_checks() -> bool:
	var resolver: RefCounted = State.new()
	var entity: Dictionary = {"pos":Vector2(7,5),"hp":40.0,"phase":"idle","owner":55,"size":Vector2i(3,4),"payload":{"watered":true,"cost":120}}
	var expected: Dictionary = entity.duplicate(true)
	var idle: Dictionary = resolver.resolve("enemies",entity,10.0)
	check("STATE_READ_ONLY_NESTED",idle.state == "idle" and entity == expected)
	entity.phase = "windup"
	var windup: String = resolver.resolve("enemies",entity,11.0).state
	entity.hp = 39.0
	var hit: String = resolver.resolve("enemies",entity,11.1).state
	entity.phase = "attack"
	var attack: String = resolver.resolve("enemies",entity,12.0).state
	entity.phase = "eating"
	var eat: String = resolver.resolve("enemies",entity,13.0).state
	check("ENEMY_TELEGRAPH_HIT_ATTACK_EAT",windup == "windup" and hit == "hit" and attack == "attack" and eat == "eat")
	var helper: RefCounted = State.new()
	var worker: Dictionary = {"pos":Vector2.ZERO,"hp":50.0,"kind":"sprinkler","status":"watering"}
	var water: String = helper.resolve("helpers",worker,0.0).state
	worker.pos = Vector2(-1,-1)
	worker.status = "retreating"
	var flee: String = helper.resolve("helpers",worker,1.0).state
	worker.status = "working"
	worker.pos = Vector2(-2,-2)
	var move: Dictionary = helper.resolve("helpers",worker,2.0)
	check("HELPER_WATER_FLEE_MOVE",water == "water" and flee == "flee" and move.state == "move" and move.direction == &"up")
	var crop: RefCounted = State.new()
	var plant: Dictionary = {"pos":Vector2.ZERO,"age":0.0,"mature":false}
	var planted: String = crop.resolve("plants",plant,0.0).state
	plant.age = 0.25
	var growing: String = crop.resolve("plants",plant,1.0).state
	plant.mature = true
	check("CROP_STAGE_TRANSITIONS",planted == "planted" and growing == "growing" and crop.resolve("plants",plant,2.0).state == "mature")
	return true

func catalog_checks() -> bool:
	var catalog: RefCounted = Catalog.new()
	var boar: Dictionary = Catalog.sample(catalog.definition_for("enemies","boar"),"attack",&"left",3.0)
	var sprout: Dictionary = Catalog.sample(catalog.definition_for("plants","clover"),"growing",&"up",1.0)
	var mature: Dictionary = Catalog.sample(catalog.definition_for("plants","clover"),"mature",&"up",1.0)
	check("NATIVE_ART_AND_MISSING_ART_FALLBACK",boar.texture.get_size() == Vector2(32,18) and sprout.texture.get_size() == Vector2(8,8) and mature.texture.get_size() == Vector2(16,16) and boar.flip and catalog.definition_for("plants","watermelon").is_empty() and catalog.definition_for("nests","mother").is_empty())
	var directional: Dictionary = {"clips":{"idle":{"directions":{"up":{"frames":[sprout.texture,mature.texture],"fps":2.0,"anchor":Vector2i(3,7)},"down":Catalog.clip(boar.texture,Vector2i(5,16))}}}}
	catalog.register("nests","independent",directional)
	# The catalog must own the registered definition; a later source-array edit must not replace it.
	directional.clips.idle.directions.up.anchor = Vector2i(99,99)
	var sample: Dictionary = Catalog.sample(catalog.definition_for("nests","independent"),"windup",&"up",0.75)
	check("DIRECTION_ANIMATION_AND_DEFINITION_OWNERSHIP",sample.texture == mature.texture and sample.frame == 1 and sample.anchor == Vector2(3,7) and sample.clip_state == "idle")
	return true

func card_checks() -> bool:
	var viewport: SubViewport = SubViewport.new()
	viewport.size = Vector2i(640,360)
	viewport.own_world_3d = true
	root.add_child(viewport)
	var camera: Camera3D = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.size = 18.5
	viewport.add_child(camera)
	camera.position = Vector3(8,8,8)
	camera.look_at(Vector3.ZERO)
	camera.current = true
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	viewport.add_child(sun)
	sun.rotation_degrees = Vector3(-50,25,0)
	var card: Node3D = Card.new()
	viewport.add_child(card)
	var img: Image = Image.create(13,21,false,Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	var texture: ImageTexture = ImageTexture.create_from_image(img)
	var definition: Dictionary = {"clips":{"idle":Catalog.clip(texture,Vector2i(2,19))},"mirror_left":true}
	var original: Dictionary = definition.duplicate(true)
	var foot: Vector3 = Vector3(0.173,0,0.291)
	card.pose(definition,{"state":"idle","direction":&"right"},foot,camera,sun,0.0)
	# In a 640x360 native card, an anchor is an image-pixel offset from the projected centre.
	# This checks through camera projection, rather than snapshot's own foot reconstruction.
	var anchor_screen: Vector2 = camera.unproject_position(card.body.global_position) + Vector2(-4.5,8.5)
	var foot_screen: Vector2 = camera.unproject_position(foot).round()
	check("ASYMMETRIC_ANCHOR_PIXEL_FOOT",anchor_screen.distance_to(foot_screen) < 0.001 and absf(card.render_foot.y) < 0.00001,{"anchor_screen":str(anchor_screen),"expected_pixel":str(foot_screen)})
	card.pose(definition,{"state":"idle","direction":&"left"},foot,camera,sun,0.5)
	var flipped_anchor: Vector2 = camera.unproject_position(card.body.global_position) + Vector2(4.5,8.5)
	var shadow_anchor: Vector3 = card.shadow.to_global(Vector3(4.5,-8.5,0)*(18.5/360.0))
	check("FLIP_KEEPS_BODY_SHADOW_GROUND_FOOT",flipped_anchor.distance_to(foot_screen) < 0.001 and shadow_anchor.distance_to(card.render_foot) < 0.00001 and card.body.flip_h and card.shadow.flip_h and not card.body.global_position.is_equal_approx(card.shadow.global_position))
	check("NATIVE_SCALE_NEAREST_SEPARATE_LAYERS",card.body.texture.get_size() == Vector2(13,21) and is_equal_approx(card.body.pixel_size,18.5/360.0) and card.body.texture_filter == BaseMaterial3D.TEXTURE_FILTER_NEAREST and card.shadow.texture_filter == BaseMaterial3D.TEXTURE_FILTER_NEAREST and card.body.layers == 64 and card.shadow.layers == 8 and card.body.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and card.shadow.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY and card.effects != card.body and card.effects.global_position.is_equal_approx(card.render_foot))
	check("CARD_DEFINITION_READ_ONLY",definition == original)
	viewport.free()
	return true

func run() -> void:
	if not OS.get_user_data_dir().replace("\\","/").contains("evidence/poc3/sprite_view/independent/profile/"):
		quit(2)
		return
	for method: String in ["state_checks","catalog_checks","card_checks"]:
		if call(method) != true: check("COMPLETED_"+method,false,"test aborted")
	var failed: int = 0
	for row: Dictionary in rows:
		if row.status == "FAIL": failed += 1
	var output: FileAccess = FileAccess.open(OUT+"results.json",FileAccess.WRITE)
	output.store_string(JSON.stringify({"checks":rows,"failures":failed,"engine":Engine.get_version_info(),"user_dir":OS.get_user_data_dir()},"  "))
	output.close()
	quit(1 if failed else 0)
