extends SceneTree
## POC-04 GPU capture checks (real renderer, NOT --headless):
## godot --path <repo> --script res://tests/poc/combat/gpu.gd
## No OS-level input / cursor movement; the window is marked unfocusable. Images go to evidence/poc/04/.
## Scene A: fighting (boars, nests, shots in flight). Scene B: right after the region became stable. Scene C: after 100 %.
const Config: GDScript = preload("res://scripts/poc/poc_config.gd")
const Coords: GDScript = preload("res://scripts/poc/poc_coords.gd")
const OUT: String = "res://evidence/poc/04/"

var failures: int = 0
var passes: int = 0
var main: Node

func check(name: String, ok: bool, detail: String = "") -> void:
	if ok:
		passes += 1
		print("PASS ", name, " ", detail)
	else:
		failures += 1
		print("FAIL ", name, " ", detail)

func _init() -> void:
	root.unfocusable = true
	_run.call_deferred()

func _frames(n: int) -> void:
	for i: int in n:
		await process_frame
	await RenderingServer.frame_post_draw

func _grab() -> Image:
	await _frames(3)
	return main.render_view.get_texture().get_image()

func _grab_full() -> Image:
	await _frames(1)
	return root.get_texture().get_image()

func _save(image: Image, name: String) -> void:
	image.save_png(ProjectSettings.globalize_path(OUT + name))

## Crop around `center` (render px), enlarged with nearest filtering, for a closer look at the sprites (the real image stays 1 texel = 1 px).
func _save_zoom(image: Image, center: Vector2, name: String) -> void:
	var size: Vector2i = Vector2i(160, 90)
	var origin: Vector2i = Vector2i(clampi(int(center.x) - 80, 0, image.get_width() - size.x), clampi(int(center.y) - 45, 0, image.get_height() - size.y))
	var crop: Image = image.get_region(Rect2i(origin, size))
	crop.resize(size.x * 5, size.y * 5, Image.INTERPOLATE_NEAREST)
	crop.save_png(ProjectSettings.globalize_path(OUT + name))

func _count_diff(a: Image, b: Image) -> int:
	var count: int = 0
	for y: int in a.get_height():
		for x: int in a.get_width():
			if a.get_pixel(x, y) != b.get_pixel(x, y):
				count += 1
	return count

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		print("NOT_RUN gpu (headless display server)")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	main = load("res://scenes/poc.tscn").instantiate()
	main.set_meta(&"poc_combat", true)
	root.add_child(main)
	main.auto_process = false
	main.window_size_override = Vector2i(1920, 1080)
	await _frames(3)
	print("renderer=", RenderingServer.get_video_adapter_name(), " display=", DisplayServer.get_name(), " window=", root.size)
	var s: RefCounted = main.session
	check("gpu.combat_session", s.combat_mode and main.enemy_view != null and s.enemies.nests.size() == 3)
	# Scene A: let the nests spawn, keep the player in the safe patch, then shoot at the northern nest from open ground.
	for i: int in 160:
		main.tick(0.25, Vector2.ZERO)
	var nest: Nest = s.enemies.nests[0]
	s.position = Coords.cell_center_logic(Vector2i(24, 13))
	s.enemy_tuning.contact_damage = 0
	# Staging for the picture only: the spawned boars are moved onto open ground in front of the camera (the tall ruin hides the
	# area where they happened to be), beside the line of fire, and held still.
	var stage_cells: Array[Vector2i] = [Vector2i(17, 10), Vector2i(19, 12), Vector2i(21, 10), Vector2i(28, 10), Vector2i(30, 12), Vector2i(32, 10), Vector2i(20, 8), Vector2i(30, 8)]
	for i: int in s.enemies.boars.size():
		var staged: Boar = s.enemies.boars[i]
		staged.pos = Coords.cell_center_logic(stage_cells[i % stage_cells.size()])
		staged.wait = 1000000
		staged.goal = Vector2.INF
	main.tick(0.0, Vector2.ZERO)
	var center: Vector2 = nest.center_px(Config.TILE_PX)
	s.set_aim(center)
	s.play.add_seeds(40)
	for k: int in 3:
		s.fire(false, center)
		main.tick(0.03, Vector2.ZERO)
	main.tick(0.03, Vector2.ZERO)
	var fight: Image = await _grab()
	var fight_full: Image = await _grab_full()
	_save(fight, "scene_a_fight_640.png")
	_save_zoom(fight, main.camera.unproject_position(Vector3(Coords.logic_to_ground(s.position).x, 0.0, Coords.logic_to_ground(s.position).y)), "scene_a_fight_zoom.png")
	_save(fight_full, "scene_a_fight_full_640.png")
	var snap: Dictionary = main.enemy_view.snapshot()
	for boar: Boar in s.enemies.boars:
		var g: Vector2 = Coords.logic_to_ground(boar.pos)
		print("INFO boar ", boar.id, " cell=", Coords.logic_to_cell(boar.pos), " screen=", main.camera.unproject_position(Vector3(g.x, 0.0, g.y)))
	var pg: Vector2 = Coords.logic_to_ground(s.position)
	print("INFO player screen=", main.camera.unproject_position(Vector3(pg.x, 0.0, pg.y)))
	var shots: int = main.play_view.snapshot()["shots_visible"]
	check("gpu.fight_entities_shown", int(snap["boars"]) >= 1 and int(snap["nests"]) == 3 and bool(snap["shadow_pairs_match"]) and shots >= 1, "%s shots=%d" % [snap, shots])
	main.enemy_view.visible = false
	var without: Image = await _grab()
	main.enemy_view.visible = true
	check("gpu.enemy_sprites_change_picture", _count_diff(fight, without) > 300, "diff=%d" % _count_diff(fight, without))
	check("gpu.hud_shows_zone_state", main.hud.text.contains("未制圧") and main.hud.text.contains("残巣") and main.hud.text.contains("残敵") and main.hud.text.contains("HP"), main.hud.text.replace("\n", " | "))
	# Scene B: finish the region (nests, boars) through the game rules, let the notice show.
	for n: Nest in s.enemies.nests:
		s.enemies.damage_nest(n, 99)
	for boar: Boar in s.enemies.boars.duplicate():
		s.enemies.damage_boar(boar, 99)
	s.position = Coords.cell_center_logic(Vector2i(24, 20))
	main.tick(0.25, Vector2.ZERO)
	main.tick(0.25, Vector2.ZERO)
	var stable: Image = await _grab()
	var stable_full: Image = await _grab_full()
	_save(stable, "scene_b_stable_640.png")
	_save_zoom(stable, main.camera.unproject_position(Vector3(Coords.logic_to_ground(s.position).x, 0.0, Coords.logic_to_ground(s.position).y)), "scene_b_stable_zoom.png")
	_save(stable_full, "scene_b_stable_full_640.png")
	snap = main.enemy_view.snapshot()
	check("gpu.stable_state_shown", s.state.zone_state[1] == WorldState.ZONE_STABLE and int(snap["boars"]) == 0 and int(snap["ruins"]) == 3 and int(snap["carcasses"]) >= 1 and main.hud.text.contains("安定") and main.notice.text.contains("安定した"), "%s notice=%s" % [snap, main.notice.text])
	check("gpu.stable_picture_differs_from_fight", _count_diff(fight, stable) > 300)
	# Scene C: no input; far seeding finishes the region.
	for i: int in 1000:
		main.tick(0.25, Vector2.ZERO)
	var done: Image = await _grab()
	var done_full: Image = await _grab_full()
	_save(done, "scene_c_complete_640.png")
	_save(done_full, "scene_c_complete_full_640.png")
	check("gpu.complete_state_shown", s.state.greened_count == s.state.target_count and main.hud.text.contains("緑化完了") and _count_diff(stable, done) > 1000, "greened=%d/%d" % [s.state.greened_count, s.state.target_count])
	main.queue_free()
	await _frames(2)
	print("RESULT passes=%d failures=%d" % [passes, failures])
	quit(1 if failures > 0 else 0)
