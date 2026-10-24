extends "res://tests/poc3/sprite_view/self_gpu.gd"
## Limited followup: isolate native crops from building overhangs, then test a controlled depth blocker.
var observations: Dictionary = {}

func image_now() -> Image:
	await frames(3)
	RenderingServer.force_draw(false)
	return viewport.get_texture().get_image()

func visible_pixels(node: Node3D, shown: Image) -> int:
	node.hide()
	var hidden: Image = await image_now()
	node.show()
	var count: int = 0
	var foot: Vector2 = world.camera.unproject_position(node.render_foot)
	var bounds: Rect2i = Rect2i(Vector2i(foot)-Vector2i(35,40),Vector2i(70,50)).intersection(Rect2i(0,0,640,360))
	for y: int in range(bounds.position.y,bounds.end.y):
		for x: int in range(bounds.position.x,bounds.end.x):
			if shown.get_pixel(x,y)!=hidden.get_pixel(x,y): count+=1
	return count

func run() -> void:
	check("startup_minimized_isolated",root.unfocusable and root.mode==Window.MODE_MINIMIZED and ProjectSettings.get_setting("display/window/size/no_focus",false) and OS.get_user_data_dir().contains("evidence/poc3/sprite_view/self/profile/"))
	if checks.back().status=="FAIL":
		finish("visual_followup.json")
		return
	session=Session.new()
	var center: Vector2i = open_cell()
	if center.x<0:
		check("fixture_open_ground",false)
		finish("visual_followup.json")
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
	var placed: Array[Dictionary] = []
	for pair: Array in [["clover",Vector2i(-2,2)],["carrot",Vector2i(2,-2)],["clover",Vector2i(-5,5)]]:
		placed.append(session.place_plant(pair[0],center+pair[1]))
	for index: int in 2:
		session.plants[index].age=session.plants[index].maturity
		session.plants[index].mature=true
	var pos: Vector2 = Coords.cell_center_logic(center+Vector2i(4,4))
	session.enemies.append({"id":900,"kind":"boar","pos":pos,"home":pos,"hp":20.0,"max_hp":20.0,"phase":"idle"})
	viewport=SubViewport.new()
	viewport.size=Vector2i(640,360)
	viewport.own_world_3d=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	world=World.new()
	viewport.add_child(world)
	var before: String = JSON.stringify(session.to_dict(),"",false,true).sha256_text()
	world.build(session,viewport)
	# This isolates grass readability; the original full-scene images remain as evidence.
	world.placement_view.hide()
	world.wall_view.hide()
	world.actor.display_sprite.hide()
	world.actor.shadow_board.hide()
	world.actor.formation_sprite.hide()
	world.sync(0.0)
	check("cover_mask_preserves_game_snapshot",before==JSON.stringify(session.to_dict(),"",false,true).sha256_text())
	var cover_ok: bool = true
	for plant: Dictionary in session.plants:
		var cell: Vector2i = plant.cell
		var tile: int = session.state.index_of(cell.x,cell.y)
		cover_ok=cover_ok and world.ground.shown_soil[tile]==0 and world.ground.shown_pave[tile]==0 and world.ground.soil_multimesh.get_instance_transform(tile).origin.y < -10 and world.ground.pave_multimesh.get_instance_transform(tile).origin.y < -10
	check("cover_observation_and_render_transform_match",cover_ok)
	var shown: Image = await image_now()
	check("isolated_grass_capture",shown.save_png(OUT+"grass_followup.png")==OK)
	for index: int in session.plants.size():
		var plant: Dictionary = session.plants[index]
		var node: Node3D = world.entities["plants"+str(plant.id)]
		var count: int = await visible_pixels(node,shown)
		observations["crop"+str(index)]={"kind":plant.kind,"state":node.visual_state,"screen_foot":world.camera.unproject_position(node.render_foot),"visible_delta_pixels":count,"source_pixels":node.snapshot().source_pixels}
		check("native_crop_visible_"+str(index),count>5)
	var boar: Node3D = world.entities["enemies900"]
	var clear_count: int = await visible_pixels(boar,shown)
	observations.boar={"screen_foot":world.camera.unproject_position(boar.render_foot),"clear_delta_pixels":clear_count}
	check("native_boar_visible",clear_count>20)
	session.enemies[0].phase="windup"
	world.sync(0.0)
	var windup: Image = await image_now()
	check("windup_followup_capture",windup.save_png(OUT+"windup_followup.png")==OK)
	# A ground-standing opaque wall crosses one side of the sprite, retaining the other side for comparison.
	var blocker: MeshInstance3D = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size=Vector3(0.4,1.1,0.25)
	blocker.mesh=box
	var material_: StandardMaterial3D = StandardMaterial3D.new()
	material_.albedo_color=Color("737d83")
	blocker.material_override=material_
	world.add_child(blocker)
	var forward: Vector3 = Vector3(world.camera.global_basis.z.x,0,world.camera.global_basis.z.z).normalized()
	blocker.global_position=boar.render_foot+forward*0.25+world.camera.global_basis.x*0.15+Vector3.UP*0.55
	var wall: Image = await image_now()
	check("controlled_wall_capture",wall.save_png(OUT+"wall_followup.png")==OK)
	var wall_count: int = await visible_pixels(boar,wall)
	observations.boar.wall_delta_pixels=wall_count
	check("wall_depth_occludes_part_of_body",wall_count>0 and wall_count<clear_count)
	# Switching to the mesh fallback restores the crop's exact ground cover; removing a crop does too.
	var cell: Vector2i = session.plants[0].cell
	var tile: int = session.state.index_of(cell.x,cell.y)
	world.sprite_catalog.definitions.erase("plants:clover")
	world.sync(0.0)
	check("mesh_fallback_restores_cover",world.entities["plants"+str(session.plants[0].id)] is MeshInstance3D and (world.ground.shown_soil[tile]>0 or world.ground.shown_pave[tile]>0))
	cell=session.plants[1].cell
	tile=session.state.index_of(cell.x,cell.y)
	session.remove_plant(session.plants[1].id)
	var removed: String = JSON.stringify(session.to_dict(),"",false,true).sha256_text()
	world.sync(0.0)
	check("removed_crop_restores_cover_game_unchanged",(world.ground.shown_soil[tile]>0 or world.ground.shown_pave[tile]>0) and removed==JSON.stringify(session.to_dict(),"",false,true).sha256_text())
	check("stayed_minimized_no_focus",root.unfocusable and root.mode==Window.MODE_MINIMIZED)
	var file: FileAccess = FileAccess.open(OUT+"visual_observations.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(observations,"  "))
	file.close()
	session.close()
	finish("visual_followup.json")
