extends "res://tests/poc3/sprite_view/self_gpu.gd"
## Incremental ground-cover impact only. No GPU capture or broad logic rerun.

func run() -> void:
	if not OS.get_user_data_dir().contains("evidence/poc3/sprite_view/self/profile/"):
		quit(1)
		return
	session=Session.new()
	var center: Vector2i = open_cell()
	if center.x<0:
		check("fixture_open_ground",false)
		finish("cover_followup.json")
		return
	session.known.fill(1)
	var tile: int = session.state.index_of(center.x,center.y)
	session.state.set_stage(tile,WorldState.STAGE_MATURE)
	var planted: Dictionary = session.place_plant("clover",center)
	if not planted.ok:
		check("fixture_plant",false)
		finish("cover_followup.json")
		return
	viewport=SubViewport.new()
	viewport.size=Vector2i(640,360)
	viewport.own_world_3d=true
	root.add_child(viewport)
	world=World.new()
	viewport.add_child(world)
	world.build(session,viewport)
	var unchanged: String = JSON.stringify(session.to_dict(),"",false,true).sha256_text()
	var updates: int = world.ground.cell_updates
	world.sync(0.0)
	check("unchanged_sync_zero_ground_updates",world.ground.cell_updates==updates and world.ground.shown_soil[tile]==0 and world.ground.shown_pave[tile]==0 and unchanged==JSON.stringify(session.to_dict(),"",false,true).sha256_text())
	session.state.set_stage(tile,WorldState.STAGE_SPROUT2)
	world.sync(0.0)
	check("dirty_mask_cell_rehidden",world.ground.cell_updates==updates+1 and world.ground.shown_soil[tile]==0 and world.ground.shown_pave[tile]==0 and world.ground.soil_multimesh.get_instance_transform(tile).origin.y < -10 and world.ground.pave_multimesh.get_instance_transform(tile).origin.y < -10)
	var definition: Dictionary = world.sprite_catalog.definition_for("plants","clover")
	world.sprite_catalog.definitions.erase("plants:clover")
	var snapshot: String = JSON.stringify(session.to_dict(),"",false,true).sha256_text()
	world.sync(0.0)
	check("mesh_return_restores_cover_without_game_change",world.entities["plants"+str(planted.id)] is MeshInstance3D and (world.ground.shown_soil[tile]>0 or world.ground.shown_pave[tile]>0) and snapshot==JSON.stringify(session.to_dict(),"",false,true).sha256_text())
	world.sprite_catalog.register("plants","clover",definition)
	world.sync(0.0)
	session.remove_plant(planted.id)
	snapshot=JSON.stringify(session.to_dict(),"",false,true).sha256_text()
	world.sync(0.0)
	check("removed_crop_restores_cover_without_game_change",not world.entities.has("plants"+str(planted.id)) and (world.ground.shown_soil[tile]>0 or world.ground.shown_pave[tile]>0) and snapshot==JSON.stringify(session.to_dict(),"",false,true).sha256_text())
	session.close()
	finish("cover_followup.json")
