extends SceneTree
## One focused real-GPU pass. Hidden/unfocusable; no OS input or foreground operations.
const Coords: GDScript = preload("res://scripts/poc/poc_coords.gd")
const OUT: String = "res://evidence/spr01/fire-directions/game-self/"
var main: Node
var checks: Array[Dictionary] = []
var failures: int = 0

func _init() -> void:
	root.unfocusable = true
	_run.call_deferred()

func check(label: String, ok: bool, detail: Variant = null) -> void:
	checks.append({"name": label, "ok": ok, "detail": detail})
	print("PASS " if ok else "FAIL ", label, " ", detail)
	if not ok:
		failures += 1

func frames() -> void:
	for i: int in 3:
		await process_frame
	await RenderingServer.frame_post_draw

func capture(label: String) -> void:
	await frames()
	main.render_view.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT + label + ".png"))

func point(direction: String) -> Vector2:
	var unit: Vector2 = {"left": Vector2.LEFT, "right": Vector2.RIGHT, "up": Vector2.UP, "down": Vector2.DOWN}[direction]
	return main.camera.unproject_position(main.player_ground3()) - Vector2(0, 10) + unit * 40.0

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		print("NOT_RUN GPU")
		quit(2)
		return
	main = load("res://scenes/poc.tscn").instantiate()
	main.set_meta(&"poc_town", true)
	root.add_child(main)
	main.auto_process = false
	main.audio.muted = true
	main.set_text_visible(false)
	await frames()
	var socket_results: Array[Dictionary] = []
	for direction: String in ["left", "right", "up"]:
		for kind: String in ["seed", "water"]:
			main._cancel_fire()
			main.tick(0.0, Vector2.ZERO)
			main.session.projectiles.shots.clear()
			main.session.play.seeds = 100
			main.session.play.water = 100.0
			var pos: Vector2 = point(direction)
			main.place_aim_at(pos)
			var begun: Dictionary = main.click_fire(pos, kind == "water")
			check(kind + "_" + direction + "_starts_correct_direction", bool(begun.ok) and String(main.actor.direction) == direction and main.actor.frame == 0)
			await capture(kind + "_" + direction + "_000")
			var release_ms: float = 66.0 if kind == "seed" else 400.0
			main.tick((release_ms - 1.0) / 1000.0, Vector2.ZERO)
			await capture(kind + "_" + direction + "_hold")
			var layer: AtlasTexture = main.actor.display_sprite.texture as AtlasTexture
			var fx: AtlasTexture = main.actor.formation_sprite.texture as AtlasTexture
			var row: int = {"left": 1, "right": 2, "up": 3}[direction]
			var snap: Dictionary = main.actor.snapshot()
			var centre: Vector2 = main.camera.unproject_position(main.actor.display_sprite.global_position)
			var formation_centre: Vector2 = main.camera.unproject_position(main.actor.formation_sprite.global_position)
			check(kind + "_" + direction + "_atlas_formation_shadow_grid", layer.region.position.y == row * 36 and fx.region.position.y == row * 36 and snap.matching_texture and snap.matching_feet and not main.actor.display_sprite.flip_h and centre.distance_to(centre.round()) < 0.001 and centre.distance_to(formation_centre) < 0.001)
			main.tick(0.001, Vector2.ZERO)
			await capture(kind + "_" + direction + "_release")
			var shot: Dictionary = main.session.projectiles.shots.back()
			var socket: Vector2 = main.fire_action.release_socket(StringName(kind), StringName(direction))
			var expected: Vector2 = main.camera.unproject_position(main.actor.render_foot) + socket - Vector2(12, 34)
			var actual: Vector2 = main.camera.unproject_position(main.play_view.flight_pool[0].global_position)
			socket_results.append({"kind": kind, "direction": direction, "socket": socket, "expected_screen": expected, "projectile_screen": actual, "logical_origin": shot.origin, "player_position": main.session.position})
			check(kind + "_" + direction + "_release_socket_and_logical_origin", expected.distance_to(actual) < 0.001 and Vector2(shot.origin) == main.session.position and main.actor.frame == (1 if kind == "seed" else 4), socket_results.back())
			main.tick(0.05, Vector2.ZERO)
			await capture(kind + "_" + direction + "_flight")
			main.tick((400.0 if kind == "seed" else 800.0) / 1000.0 - main.fire_action.elapsed_ms / 1000.0, Vector2.RIGHT)
			await capture(kind + "_" + direction + "_walk")
			check(kind + "_" + direction + "_directional_walk_recovery", not main.fire_action.active and main.actor.walking and main.actor.fire_kind == &"" and main.actor.snapshot().matching_texture and (main.actor.display_sprite.texture as AtlasTexture).atlas.resource_path.ends_with("walk-normal.png"))
	# Facing follows the current pointer during charge; logical aim stays the accepted click target.
	main.place_aim_at(point("left"))
	main.click_fire(point("left"), true)
	var target: Vector2 = main.fire_action.aim
	main.place_aim_at(point("right"))
	main.tick(0.4, Vector2.ZERO)
	var current_shot: Dictionary = main.session.projectiles.shots.back()
	var current_socket: Vector2 = main.fire_action.release_socket(&"water", &"right")
	var expected_socket: Vector2 = main.camera.unproject_position(main.actor.render_foot) + current_socket - Vector2(12, 34)
	var projected: Vector2 = main.camera.unproject_position(main.play_view.flight_pool.back().global_position)
	check("charge_turns_with_mouse_without_locking_aim", main.actor.direction == &"right" and Vector2(current_shot.target) == target and expected_socket.distance_to(projected) < 0.001)
	main._cancel_fire()
	main.click_fire(point("down"), true)
	main.tick(0.08, Vector2.ZERO)
	var held: float = main.fire_action.elapsed_ms
	main.open_pause_menu()
	main.tick(0.5, Vector2.ZERO)
	check("menu_holds_directional_action_clock", main.fire_action.elapsed_ms == held)
	main.close_menu()
	var file: FileAccess = FileAccess.open(OUT + "gpu-results.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": checks, "failures": failures, "renderer": RenderingServer.get_video_adapter_name(), "socket_results": socket_results, "not_run": ["Physical input and user art evaluation", "Full regressions/weather/performance/export"]}, "\t"))
	file.close()
	main.session.close()
	main.queue_free()
	await process_frame
	quit(failures)
