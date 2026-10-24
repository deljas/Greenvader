extends "res://tests/poc3/locust/self_integration.gd"
const World: GDScript=preload("res://scripts/poc2/view/world_view.gd")
var viewport: SubViewport
func frames() -> void:
	for tick: int in 3: await process_frame
func run() -> void:
	var safe: bool=root.unfocusable and root.mode==Window.MODE_MINIMIZED and ProjectSettings.get_setting("display/window/size/no_focus",false) and OS.get_user_data_dir().replace("\\","/").contains("evidence/poc3/locust/self/profile/")
	check("startup_minimized_no_focus_isolated",safe)
	if not safe: quit(1); return
	var s: RefCounted=fixture(1)
	var n: Dictionary=s.nests[0]
	for member: int in 5: s.combat_system.spawn(n,false)
	s.nests.clear()
	var cells: Array[Vector2i]=[Vector2i(108,110),Vector2i(110,108),Vector2i(114,109),Vector2i(116,112),Vector2i(110,116),Vector2i(114,116)]
	for index: int in 6:
		var e: Dictionary=s.enemies[index]
		e.pos=Coords.cell_center_logic(cells[index]); e.home=e.pos
		s.state.set_stage(s.state.index_of(cells[index].x,cells[index].y),WorldState.STAGE_MATURE)
	s.known.fill(1)
	s.advance_game(0.5)
	viewport=SubViewport.new(); viewport.size=Vector2i(640,360)
	viewport.own_world_3d=true; viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	viewport.msaa_3d=Viewport.MSAA_DISABLED; root.add_child(viewport)
	var world: Node3D=World.new(); viewport.add_child(world)
	world.build(s,viewport); world.sync(0.0)
	await frames()
	RenderingServer.force_draw(false)
	var image: Image=viewport.get_texture().get_image()
	check("eating_gpu_image",image.save_png(OUT+"eating.png")==OK)
	var structural: bool=world.entities.size()==6
	var observations: Array=[]
	for e: Dictionary in s.enemies:
		var node: MeshInstance3D=world.entities["enemies"+str(e.id)]
		structural=structural and e.phase=="eat" and node.get_child_count()==6 and is_equal_approx(node.scale.x,0.65) and node.scale.y<0.48
		observations.append({"id":e.id,"phase":e.phase,"height":node.scale.y,"legs":node.get_child_count(),"screen":str(world.camera.unproject_position(node.global_position))})
	check("six_separate_eat_meshes_legs_compressed_body",structural)
	check("remained_minimized_no_focus",root.unfocusable and root.mode==Window.MODE_MINIMIZED)
	var file: FileAccess=FileAccess.open(OUT+"gpu_results.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"observations":observations,"completed":true,"visual_review":"separate human/agent image inspection required"},"  "))
	file.close(); s.close()
	var failed: bool=false
	for row: Dictionary in checks: failed=failed or row.status=="FAIL"
	quit(1 if failed else 0)
