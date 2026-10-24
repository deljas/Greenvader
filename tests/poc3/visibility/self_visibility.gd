extends SceneTree
## One fixed fixture, before/after the distance-filter change. No OS input or save access.
const Session: GDScript = preload("res://scripts/poc2/poc2_session.gd")
const View: GDScript = preload("res://scripts/poc2/view/world_view.gd")
const Coords: GDScript = preload("res://scripts/poc/poc_coords.gd")
const OUT: String = "res://evidence/poc3/visibility/self/"
var checks: Array[Dictionary] = []
var targets: Array[Dictionary] = []
var session: RefCounted
var world: Node3D
var viewport: SubViewport
var before_mode: bool = false

func _init() -> void:
	call_deferred("run")

func check(label: String, passed: bool) -> void:
	checks.append({"name": label, "status": "PASS" if passed else "FAIL"})
	print(checks.back())

func node_visible(key: String) -> bool:
	return world.entities.has(key) and world.entities[key].visible

func fixture() -> void:
	session = Session.new()
	var enemy_template: Dictionary = session.enemies[0].duplicate(true)
	var nest_template: Dictionary = session.nests[0].duplicate(true)
	session.enemies.clear()
	session.nests.clear()
	session.fossils.clear()
	# This is a renderer fixture, not a changed game map: keep buildings out of the comparison.
	session.placement = null
	session.state.terrain.fill(0)
	session.base_terrain.fill(0)
	# Keep the existing terrain builder's Blocks mesh non-empty, outside this camera.
	session.state.terrain[0] = 4
	session.state.stage.fill(0)
	session.position = Vector2(446, 446)
	var names: Array[String] = ["enemy", "nest", "mother"]
	var directions: Array[Vector2] = [Vector2.LEFT, Vector2(-1,1).normalized(), Vector2.DOWN]
	for index: int in names.size():
		for distance: float in [64.0, 100.0]:
			var kind: String = names[index]
			var category: String = "enemies" if kind == "enemy" else "nests"
			var item: Dictionary = (enemy_template if kind == "enemy" else nest_template).duplicate(true)
			item.id = session.allocate_id()
			item.pos = session.position + directions[index] * distance
			item.home = item.pos
			item.hp = 100.0
			item.max_hp = 100.0
			item.kind = "boar" if kind == "enemy" else kind
			if category == "nests":
				item.mother = kind == "mother"
				item.scale = "small"
				item.active = false
				item.status = "dormant"
				item.last_contact = -100.0
				item.spawn_due = 0.0
			session.get(category).append(item)
			targets.append({"category": category, "id": item.id, "label": kind + (" near" if distance == 64.0 else " far"), "far": distance == 100.0, "pos": item.pos})
	for distance: float in [48.0, 100.0]:
		session.fossils.append({"id": session.allocate_id(), "kind": "fossil", "pos": session.position + Vector2.RIGHT * distance, "unlock": "carrot", "found": false, "nest_id": -1})
	session.reveal()
	viewport = SubViewport.new()
	viewport.size = Vector2i(640,360)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	world = View.new()
	viewport.add_child(world)
	world.build(session, viewport)
	if world.wall_view != null:
		world.wall_view.visible = false

func finish(extra: Dictionary = {}) -> void:
	var failed: int = 0
	for result: Dictionary in checks:
		if result.status == "FAIL":
			failed += 1
	var data: Dictionary = {"phase": "before" if before_mode else "after", "checks": checks, "failures": failed, "view_sha256": FileAccess.get_sha256("res://scripts/poc2/view/world_view.gd"), "startup_no_focus": ProjectSettings.get_setting("display/window/size/no_focus"), "startup_mode": ProjectSettings.get_setting("display/window/size/mode"), "runtime_unfocusable": root.unfocusable, "runtime_mode": root.mode}
	data.merge(extra)
	var path: String = OUT + ("before.json" if before_mode else "after.json")
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data, "  "))
	file.close()
	if session != null:
		session.close()
	quit(1 if failed > 0 else 0)

func run() -> void:
	before_mode = OS.get_cmdline_user_args().has("--before")
	var safe: bool = bool(ProjectSettings.get_setting("display/window/size/no_focus", false)) and int(ProjectSettings.get_setting("display/window/size/mode", -1)) == 1 and root.unfocusable and root.mode == Window.MODE_MINIMIZED
	check("startup_minimized_no_focus", safe)
	if not safe:
		finish({"gpu_status": "NOT_RUN", "reason": "unsafe startup settings; no restore attempted"})
		return
	fixture()
	var state_before: String = JSON.stringify(session.to_dict(), "", false, true).sha256_text()
	world.sync(0.0)
	check("render_does_not_mutate_session", state_before == JSON.stringify(session.to_dict(), "", false, true).sha256_text())
	var rows: Array[Dictionary] = []
	var all_expected: bool = true
	var old_boundary_valid: bool = true
	var labels: CanvasLayer = CanvasLayer.new()
	viewport.add_child(labels)
	for target: Dictionary in targets:
		var key: String = String(target.category) + str(target.id)
		var at: Vector3 = Coords.ground3(Coords.logic_to_ground(target.pos)) + Vector3.UP * 0.4
		var screen: Vector2 = world.camera.unproject_position(at)
		var in_camera: bool = world.camera.is_position_in_frustum(at) and Rect2(Vector2.ZERO,Vector2(640,360)).has_point(screen)
		var old_visible: bool = world._visible(target.pos)
		var shown: bool = node_visible(key)
		old_boundary_valid = old_boundary_valid and old_visible != bool(target.far) and in_camera
		all_expected = all_expected and shown == (not bool(target.far) if before_mode else true)
		rows.append({"label": target.label, "key": key, "old_visible": old_visible, "in_camera": in_camera, "screen": [screen.x, screen.y], "rendered": shown})
		var label: Label = Label.new()
		label.text = target.label
		label.position = screen + Vector2(10,-6)
		label.add_theme_font_size_override("font_size", 10)
		labels.add_child(label)
	check("all_three_types_cross_old_boundary_in_camera", old_boundary_valid)
	check("reproduce_distance_disappearance" if before_mode else "live_entities_visible_both_sides", all_expected)
	var near_fossil: Dictionary = session.fossils[0]
	var far_fossil: Dictionary = session.fossils[1]
	check("fossil_distance_filter_preserved", node_visible("fossils" + str(near_fossil.id)) and not node_visible("fossils" + str(far_fossil.id)))
	for index: int in 3:
		await process_frame
	RenderingServer.force_draw(false)
	var image: Image = viewport.get_texture().get_image()
	var drawn: bool = image != null and not image.is_empty() and image.get_size() == Vector2i(640,360)
	if drawn:
		drawn = image.get_pixel(320,180).get_luminance() > 0.001
	if drawn:
		image.save_png(OUT + ("before.png" if before_mode else "after.png"))
	check("minimized_gpu_image_available", drawn)
	check("pixel_settings_maintained", viewport.size == Vector2i(640,360) and viewport.msaa_3d == Viewport.MSAA_DISABLED and viewport.screen_space_aa == Viewport.SCREEN_SPACE_AA_DISABLED and ProjectSettings.get_setting("display/window/stretch/scale_mode") == "integer" and ProjectSettings.get_setting("rendering/textures/canvas_textures/default_texture_filter") == 0)
	if not before_mode:
		# Existing visible nodes must disappear on death/removal, independently of distance.
		var dead: Dictionary = session.enemies[0]
		var removed: Dictionary = session.nests[0]
		dead.hp = 0.0
		session.nests.erase(removed)
		near_fossil.found = true
		world._entities()
		check("death_and_removal_clear_render_nodes", not world.entities.has("enemies" + str(dead.id)) and not world.entities.has("nests" + str(removed.id)))
		check("found_fossil_hidden", not node_visible("fossils" + str(near_fossil.id)))
		# One existing combat tick: merely drawing far nests must not activate production.
		session.combat_system.advance(0.25)
		var far_dormant: bool = true
		for nest: Dictionary in session.nests:
			if nest.pos.distance_to(session.position) > 95.0:
				far_dormant = far_dormant and not nest.active and nest.status == "dormant"
		check("displayed_far_nests_remain_dormant", far_dormant)
	check("stayed_minimized_no_focus", root.mode == Window.MODE_MINIMIZED and root.unfocusable)
	finish({"targets": rows, "gpu_status": "PASS" if drawn else "NOT_RUN", "not_run": ["physical_input", "building_occlusion_regression", "map_information", "broad_gameplay_regression", "all_window_sizes"]})
