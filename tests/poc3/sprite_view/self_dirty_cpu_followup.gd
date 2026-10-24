extends "res://tests/poc3/sprite_view/self_gpu.gd"
## Correct headless check: CPU mirror and dirty count, never renderer transform readback.

func run() -> void:
	if not OS.get_user_data_dir().contains("evidence/poc3/sprite_view/self/profile/"):
		quit(1)
		return
	session=Session.new()
	var center: Vector2i = open_cell()
	if center.x<0:
		quit(1)
		return
	session.known.fill(1)
	var tile: int = session.state.index_of(center.x,center.y)
	session.state.set_stage(tile,WorldState.STAGE_MATURE)
	session.place_plant("clover",center)
	viewport=SubViewport.new()
	viewport.size=Vector2i(640,360)
	viewport.own_world_3d=true
	root.add_child(viewport)
	world=World.new()
	viewport.add_child(world)
	world.build(session,viewport)
	var before_updates: int = world.ground.cell_updates
	session.state.set_stage(tile,WorldState.STAGE_SPROUT2)
	var expected_dirty: int = session.state.dirty_tiles.size()
	world.sync(0.0)
	var actual_updates: int = world.ground.cell_updates-before_updates
	check("dirty_mask_cpu_mirror_matches_actual_dirty_count",expected_dirty>0 and actual_updates==expected_dirty and world.ground.shown_soil[tile]==0 and world.ground.shown_pave[tile]==0)
	var file: FileAccess = FileAccess.open(OUT+"dirty_cpu_observations.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"source_dirty_cells":expected_dirty,"ground_updates":actual_updates,"shown_soil":int(world.ground.shown_soil[tile]),"shown_pave":int(world.ground.shown_pave[tile]),"headless_soil_readback_y":world.ground.soil_multimesh.get_instance_transform(tile).origin.y,"headless_pave_readback_y":world.ground.pave_multimesh.get_instance_transform(tile).origin.y},"  "))
	file.close()
	session.close()
	finish("dirty_cpu_followup.json")
