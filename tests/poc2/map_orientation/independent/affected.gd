extends "res://tests/poc2/map_orientation/independent/verify.gd"
## Only harness-blocked and fixture-affected conditions; initial PASS conditions are not repeated.
func run() -> void:
	change_scene_to_packed(Main); await frames()
	main=current_scene; main.auto_process=false
	main.save_dir="user://poc2_map_orientation_independent_20261023"
	main._on_action("new")
	var s: RefCounted=main.session
	var map: Control=main.ui.map
	s.seeds=1000; s.unlocked.gatlinger=true
	s.place_helper("gatlinger",Vector2i(196,188),37)
	var h: Dictionary=s.helpers[0]
	var original_terrain: PackedByteArray=s.state.terrain.duplicate()
	var original_stage: PackedByteArray=s.state.stage.duplicate()
	s.known.fill(1); s.visible.fill(1)
	key(KEY_M); await frames()
	mouse(map.point(h.pos),MOUSE_BUTTON_WHEEL_UP); await frames()
	mouse(map.point(h.pos),MOUSE_BUTTON_WHEEL_UP); await frames()
	mouse(map.point(h.pos)); await frames()
	var target: Vector2=Coords.cell_center_logic(Vector2i(174,172))
	var pixel: Vector2=map.point(target)
	check("order_fixture_walkable_clear_of_buttons",s.is_walkable_logic(target) and map.map_rect.has_point(pixel) and not map.remove_button.get_global_rect().has_point(pixel) and not map.supply_button.get_global_rect().has_point(pixel),{"pixel":str(pixel),"button":str(map.remove_button.get_global_rect())})
	var before: Vector2=h.home
	mouse(pixel); await frames()
	var expected: Vector2=Coords.cell_center_logic(Coords.logic_to_cell(map.logic_at(pixel)))
	check("engine_order_hits_projected_destination",h.home==expected and h.home!=before,{"actual":str(h.home),"expected":str(expected)})
	map.set_expanded(true); await frames()
	s.visible.fill(0); map.refresh_terrain(); map.queue_redraw(); await frames()
	var hidden: Image=shot("remembered-hidden")
	var enemies: Array[Dictionary]=s.enemies.duplicate()
	var nests: Array[Dictionary]=s.nests.duplicate()
	var fossils: Array[Dictionary]=s.fossils.duplicate()
	s.enemies.clear(); s.nests.clear(); s.fossils.clear(); map.queue_redraw(); await frames()
	var absent: Image=root.get_texture().get_image()
	check("unknown_entities_leave_no_map_pixels",hidden.get_region(Rect2i(map.map_rect)).get_data()==absent.get_region(Rect2i(map.map_rect)).get_data())
	s.enemies.assign(enemies); s.nests.assign(nests); s.fossils.assign(fossils)
	var edge: Dictionary=h.duplicate(true)
	edge.id=987654; edge.pos=Vector2(894,894); edge.home=edge.pos
	s.helpers.append(edge); map.queue_redraw(); await frames()
	var edge_pixel: Vector2=map.point(edge.pos)
	mouse(edge_pixel); await frames()
	check("last_cell_icon_remains_selectable",map.selected_id==edge.id and map.selected_helper,{"logic":str(edge.pos),"pixel":str(edge_pixel),"inverse":str(map.logic_at(edge_pixel)),"selected_id":map.selected_id})
	shot("last-cell-icon")
	s.helpers.erase(edge); map.deselect()
	check("map_does_not_mutate_world_tiles",s.state.terrain==original_terrain and s.state.stage==original_stage)
	check("pixel_viewport_nearest_integer",main.render_view.size==Vector2i(640,360) and main.view_rect.texture_filter==CanvasItem.TEXTURE_FILTER_NEAREST and root.content_scale_stretch==Window.CONTENT_SCALE_STRETCH_INTEGER and root.content_scale_size==Vector2i(640,360),{"window":str(root.size),"final_transform":str(root.get_final_transform()),"map_texture_filter":map.texture_filter})
	key(KEY_M); await frames()
	s.position+=Vector2(5.3,-3.1); main.world.sync(0); await frames()
	terrain_check(map,"moving_mini_terrain_agrees_with_pick")
	projection_check(map,"moving_mini_still_matches_camera")
	shot("mini-moved")
	finish()
