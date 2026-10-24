extends "res://tests/poc3/sprite_view/self_logic.gd"
const Session: GDScript = preload("res://scripts/poc2/poc2_session.gd")
const World: GDScript = preload("res://scripts/poc2/view/world_view.gd")
const Coords: GDScript = preload("res://scripts/poc/poc_coords.gd")
const Card: GDScript = preload("res://scripts/poc2/view/entity_sprite.gd")
var viewport: SubViewport
var world: Node3D
var session: RefCounted

func frames(count: int = 2) -> void:
	for index: int in count: await process_frame

func capture(label: String) -> bool:
	RenderingServer.force_draw(false)
	return viewport.get_texture().get_image().save_png(OUT+label+".png")==OK

func open_cell() -> Vector2i:
	for y: int in range(30,194,4):
		for x: int in range(30,194,4):
			var clear: bool = true
			for dy: int in range(-7,8):
				for dx: int in range(-7,8):
					var index: int = session.state.index_of(x+dx,y+dy)
					if not session.state.is_walkable(x+dx,y+dy) or session.state.target[index]==0 or session.state.occupant[index]!=0: clear=false
			if clear: return Vector2i(x,y)
	return Vector2i(-1,-1)

func run() -> void:
	var safe: bool = root.unfocusable and root.mode==Window.MODE_MINIMIZED and ProjectSettings.get_setting("display/window/size/no_focus",false) and OS.get_user_data_dir().contains("evidence/poc3/sprite_view/self/profile/")
	check("startup_minimized_isolated",safe)
	if not safe:
		quit(1)
		return
	session=Session.new()
	var center: Vector2i = open_cell()
	if center.x<0:
		check("fixture_open_ground",false)
		finish("gpu_results.json")
		return
	session.position=Coords.cell_center_logic(center)
	session.enemies.clear()
	session.nests.clear()
	session.fossils.clear()
	session.plants.clear()
	session.helpers.clear()
	session.shots.clear()
	session.known.fill(1)
	for dy: int in range(-7,8):
		for dx: int in range(-7,8): session.state.set_stage(session.state.index_of(center.x+dx,center.y+dy),WorldState.STAGE_MATURE)
	session.unlocked.carrot=true
	session.seeds=1000
	var clover: Dictionary = session.place_plant("clover",center+Vector2i(-2,2))
	var carrot: Dictionary = session.place_plant("carrot",center+Vector2i(2,-2))
	check("fixture_real_plant_placement",clover.ok and carrot.ok)
	for plant: Dictionary in session.plants:
		plant.age=plant.maturity
		plant.mature=true
	var boar_pos: Vector2 = Coords.cell_center_logic(center+Vector2i(3,3))
	session.enemies.append({"id":900,"kind":"boar","pos":boar_pos,"home":boar_pos,"hp":20.0,"max_hp":20.0,"phase":"idle"})
	viewport=SubViewport.new()
	viewport.size=Vector2i(640,360)
	viewport.own_world_3d=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	viewport.msaa_3d=Viewport.MSAA_DISABLED
	root.add_child(viewport)
	world=World.new()
	viewport.add_child(world)
	var before: String = JSON.stringify(session.to_dict(),"",false,true).sha256_text()
	world.build(session,viewport)
	world.sync(0.0)
	var after: String = JSON.stringify(session.to_dict(),"",false,true).sha256_text()
	check("build_and_sync_do_not_mutate_game_snapshot",before==after)
	var node: Node3D = world.entities["enemies900"]
	var snap: Dictionary = node.snapshot()
	var foot_pixel: Vector2 = world.camera.unproject_position(node.render_foot)
	check("native_card_foot_pixel_and_shadow_pair",node is Card and foot_pixel.distance_to(foot_pixel.round())<0.001 and snap.shadow_matches and is_equal_approx(node.pixel_size,18.5/360.0))
	check("display_shadow_light_separation",node.body.layers==64 and node.shadow.layers==8 and node.body.texture_filter==BaseMaterial3D.TEXTURE_FILTER_NEAREST and world.actor.receiver_light.light_cull_mask==64 and world.actor.receiver_light.shadow_caster_mask==1)
	await frames(3)
	check("grass_crops_boar_capture",capture("grass_native"))
	# A walk/direction change and combat state affect presentation, never game rules.
	session.enemies[0].pos+=Vector2(2,-2)
	world.sync(0.0)
	check("real_position_move_direction",node.visual_state=="move" and node.direction==&"right")
	session.enemies[0].phase="windup"
	world.sync(0.0)
	check("windup_readable_state",node.visual_state=="windup")
	await frames()
	check("windup_capture",capture("windup"))
	session.enemies[0].hp=19.0
	world.sync(0.0)
	check("damage_reads_hit",node.visual_state=="hit")
	# Replace only the visual definition with an existing native crop texture.
	var gameplay: String = JSON.stringify(session.to_dict(),"",false,true).sha256_text()
	var collision: bool = session.state.is_walkable(center.x,center.y)
	var pick: Vector2 = world.pick(Vector2(320,180))
	world.sprite_catalog.register("enemies","boar",{"clips":{"idle":Catalog.clip(node.body.texture,Vector2i(16,16)),"hit":Catalog.clip(Catalog.sample(world.sprite_catalog.definition_for("plants","clover"),"mature",&"down",0.0).texture,Vector2i(8,15))}})
	world.sync(0.0)
	check("visual_swap_preserves_save_collision_pick",gameplay==JSON.stringify(session.to_dict(),"",false,true).sha256_text() and collision==session.state.is_walkable(center.x,center.y) and pick.is_equal_approx(world.pick(Vector2(320,180))))
	world.sprite_catalog.register("enemies","boar",{"clips":{"idle":Catalog.clip(node.body.texture,Vector2i(3,7))},"mirror_left":true})
	session.enemies[0].visual_direction="left"
	world.sync(0.0)
	var asymmetric: Dictionary = node.snapshot()
	check("asymmetric_flipped_anchor_shadow_feet",asymmetric.shadow_matches and not node.body.global_position.is_equal_approx(node.shadow.global_position))
	session.enemies[0].erase("visual_direction")
	# Restore the default definition before testing building depth, without modifying session.
	var defaults: RefCounted = Catalog.new()
	world.sprite_catalog.register("enemies","boar",defaults.definition_for("enemies","boar"))
	world.sync(0.0)
	var blocker: MeshInstance3D = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size=Vector3(0.5,1.4,0.2)
	blocker.mesh=box
	var material_: StandardMaterial3D = StandardMaterial3D.new()
	material_.albedo_color=Color("737d83")
	blocker.material_override=material_
	world.add_child(blocker)
	var forward: Vector3 = Vector3(world.camera.global_basis.z.x,0,world.camera.global_basis.z.z).normalized()
	blocker.global_position=node.render_foot+forward*0.15+Vector3.UP*0.7
	await frames()
	check("wall_edge_depth_capture",capture("wall_edge"))
	session.enemies.clear()
	world.sync(0.0)
	check("death_removes_node",not world.entities.has("enemies900"))
	check("stayed_minimized_no_focus",root.unfocusable and root.mode==Window.MODE_MINIMIZED)
	session.close()
	finish("gpu_results.json")
