extends SceneTree
const Coords: GDScript = preload("res://scripts/poc/poc_coords.gd")
const Geometry: GDScript = preload("res://scripts/poc2/view/camera_geometry.gd")
const OUT: String = "res://evidence/poc3/playtest01/self/rerun_C_map_info/"
var checks: Array[Dictionary] = []
var projection_rows: Array[Dictionary] = []
var main: Node
var capture_viewport: SubViewport

func _init() -> void:
	call_deferred("run")

func check(label: String, passed: bool) -> void:
	checks.append({"name":label,"status":"PASS" if passed else "FAIL"})
	print(checks.back())

func capture(name_: String) -> void:
	for index: int in 3:
		await process_frame
	RenderingServer.force_draw(false)
	var image: Image = capture_viewport.get_texture().get_image()
	check(name_+"_640_capture", not image.is_empty() and image.get_size() == Vector2i(640,360) and image.save_png(OUT+name_+".png") == OK)

func run() -> void:
	var safe: bool = ProjectSettings.get_setting("display/window/size/no_focus",false) and ProjectSettings.get_setting("display/window/size/mode",-1) == 1 and root.unfocusable and root.mode == Window.MODE_MINIMIZED
	check("startup_no_focus_minimized",safe)
	if not safe:
		quit(1)
		return
	change_scene_to_file(ProjectSettings.get_setting("application/run/main_scene"))
	for index: int in 3:
		await process_frame
	main = current_scene
	main.auto_process = false
	# Render the unchanged game canvas off-screen without restoring the minimized OS window.
	capture_viewport = SubViewport.new()
	capture_viewport.size = Vector2i(640,360)
	capture_viewport.disable_3d = true
	capture_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(capture_viewport)
	main.view_rect.reparent(capture_viewport)
	main.ui.reparent(capture_viewport)
	var session: RefCounted = main.session
	session.position = Vector2(448.25,448.125)
	main.world.sync(0.0)
	var camera: Camera3D = main.world.camera
	var agreement: bool = true
	# Ground points are produced by the actual engine camera rays, not helper formula copies.
	for pixel: Vector2 in [Vector2(320,180),Vector2(2,2),Vector2(638,358),Vector2(-2,180),Vector2(642,180),Vector2(320,-2),Vector2(320,362)]:
		var origin: Vector3 = camera.project_ray_origin(pixel)
		var ray: Vector3 = camera.project_ray_normal(pixel)
		var ground: Vector3 = origin + ray * (-origin.y/ray.y)
		var logic: Vector2 = Coords.ground_to_logic(Vector2(ground.x,ground.z))
		var actual: Vector2 = camera.unproject_position(ground)
		var helper: Vector2 = Geometry.project_ground(logic,camera.global_transform.affine_inverse())
		var engine_inside: bool = camera.is_position_in_frustum(ground)
		var helper_inside: bool = Geometry.contains_ground(logic,Geometry.transform_for(session.position).affine_inverse())
		agreement = agreement and helper.distance_to(actual) < 0.02 and helper_inside == engine_inside
		projection_rows.append({"requested_pixel":[pixel.x,pixel.y],"engine_pixel":[actual.x,actual.y],"helper_pixel":[helper.x,helper.y],"engine_inside":engine_inside,"helper_inside":helper_inside})
	check("shared_geometry_matches_real_camera_projection",agreement)
	session.position += Vector2(0.013,0.021)
	main.world.sync(0.0)
	var probe: Vector2 = session.position+Vector2(-83,71)
	var world_point: Vector3 = Coords.ground3(Coords.logic_to_ground(probe))
	check("pixel_snap_shared_after_fractional_movement", camera.unproject_position(world_point).distance_to(Geometry.project_ground(probe,Geometry.transform_for(session.position).affine_inverse())) < 0.02)
	# Compact display fixture: current circle/diamond, remembered square/bone, current bone.
	var enemy_template: Dictionary = session.enemies[0].duplicate(true)
	var nest_template: Dictionary = session.nests[0].duplicate(true)
	session.enemies.clear()
	session.nests.clear()
	session.fossils.clear()
	session.helpers.clear()
	session.state.stage.fill(0) # GPU-only fixture; never saved.
	session.known.fill(1)
	session.position = Vector2(448,448)
	enemy_template.id = session.allocate_id()
	enemy_template.pos = session.position+Vector2(30,-30)
	session.enemies.append(enemy_template)
	for definition: Dictionary in [{"delta":Vector2(-20,-20),"mother":false},{"delta":Vector2(-30,30),"mother":true},{"delta":Vector2(120,140),"mother":false}]:
		var item: Dictionary = nest_template.duplicate(true)
		item.id = session.allocate_id()
		item.pos = session.position+definition.delta
		item.home = item.pos
		item.mother = definition.mother
		item.kind = "mother" if item.mother else "boar"
		item.discovered = not item.mother
		session.nests.append(item)
	for delta: Vector2 in [Vector2(50,50),Vector2(140,120)]:
		session.fossils.append({"id":session.allocate_id(),"kind":"fossil","pos":session.position+delta,"unlock":"carrot","found":false,"discovered":true,"nest_id":-1})
	session.reveal()
	main._on_action("resume")
	main.world.sync(0.0)
	var map: Control = main.ui.map
	check("remembered_icons_outside_current_detection", not session.detected(session.nests[2].pos) and not session.detected(session.fossils[1].pos) and map.icon_style("nests",session.nests[2]).shape == "square" and map.icon_style("fossils",session.fossils[1]).shape == "fossil")
	await capture("minimap")
	var current_before: bool = session.detected(enemy_template.pos)
	map.set_expanded(true)
	map.zoom = 4
	map.map_center = Vector2(448,448)
	map.refresh_terrain()
	check("map_zoom_does_not_change_detection", session.detected(enemy_template.pos) == current_before)
	await capture("fullmap")
	check("pixel_display_and_shared_shapes", main.render_view.size == Vector2i(640,360) and main.view_rect.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST and root.content_scale_stretch == Window.CONTENT_SCALE_STRETCH_INTEGER and map.icon_style("nests",session.nests[1]).shape == "mother")
	check("stayed_minimized_no_focus",root.mode == Window.MODE_MINIMIZED and root.unfocusable)
	var failures: int = 0
	for result: Dictionary in checks:
		if result.status == "FAIL": failures += 1
	var file: FileAccess = FileAccess.open(OUT+"gpu_results.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"projection_rows":projection_rows,"root_unfocusable":root.unfocusable,"root_mode":root.mode,"not_run":["native_window_visual","physical_input","all_lighting","wide_regression"]},"  "))
	file.close()
	session.close()
	quit(1 if failures > 0 else 0)
