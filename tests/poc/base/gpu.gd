extends SceneTree
## POC-01 GPU capture checks (needs a real renderer; do NOT run with --headless):
## godot --path <repo> --script res://tests/poc/base/gpu.gd
## No OS-level input, no cursor movement; the window is marked unfocusable. Images go to evidence/poc/01/.
const Config: GDScript = preload("res://scripts/poc/poc_config.gd")
const Coords: GDScript = preload("res://scripts/poc/poc_coords.gd")
const OUT: String = "res://evidence/poc/01/"

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

func _save(image: Image, name: String) -> void:
	image.save_png(ProjectSettings.globalize_path(OUT + name))

func _scaled(image: Image, factor: int) -> Image:
	var copy: Image = image.duplicate()
	copy.resize(image.get_width() * factor, image.get_height() * factor, Image.INTERPOLATE_NEAREST)
	return copy

func _mask(index: int) -> Image:
	return main.actor.frame_texture(index, 1).get_image()

func _sprite_pixels(image: Image, index: int, foot: Vector2) -> Dictionary:
	var mask: Image = _mask(index)
	var origin: Vector2i = Vector2i(roundi(foot.x) - mask.get_width() / 2, roundi(foot.y) - mask.get_height())
	var colors: Dictionary = {}
	var pixels: Array[Color] = []
	for y: int in mask.get_height():
		for x: int in mask.get_width():
			if mask.get_pixel(x, y).a > 0.5:
				var c: Color = image.get_pixel(origin.x + x, origin.y + y)
				colors[c.to_html()] = true
				pixels.append(c)
	return {"colors": colors, "pixels": pixels}

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		print("NOT_RUN gpu (headless display server)")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	main = load("res://scenes/poc.tscn").instantiate()
	root.add_child(main)
	main.auto_process = false
	main.window_size_override = Vector2i(1920, 1080)
	await _frames(2)
	print("renderer=", RenderingServer.get_video_adapter_name(), " display=", DisplayServer.get_name(), " window=", root.size)
	main.session.position = Coords.cell_center_logic(Vector2i(17, 14))
	main.session.set_aim(Coords.cell_center_logic(Vector2i(21, 17)))
	main.walking = false
	for index: int in 2:
		var res: Vector2i = Config.RESOLUTIONS[index]
		var tag: String = str(res.x)
		main.set_resolution(index, Vector2i(1920, 1080))
		main.tick(0.0, Vector2.ZERO)
		var image: Image = await _grab()
		check("gpu.size_" + tag, image.get_size() == res, str(image.get_size()))
		_save(image, "render_%s.png" % tag)
		_save(_scaled(image, 3 if index == 0 else 2), "render_%s_as_1920x1080.png" % tag)
		var shot: Image = root.get_texture().get_image()
		_save(shot, "screen_%s_with_hud.png" % tag)
		_save(_scaled(shot, 3 if index == 0 else 2), "screen_%s_with_hud_as_1920x1080.png" % tag)
		check("gpu.hud_capture_size_" + tag, shot.get_size() == res or shot.get_size().x >= res.x, str(shot.get_size()))
		var snap: Dictionary = main.actor.snapshot()
		check("gpu.sync_flags_" + tag, snap["matching_texture"] and snap["matching_feet"] and snap["matching_flip"], str(snap))
		var foot: Vector2 = snap["foot_screen"]
		var base: Dictionary = _sprite_pixels(image, index, foot)
		check("gpu.sprite_palette_" + tag, base["colors"].size() >= 6 and base["colors"].size() <= 16, "unique colors under sprite mask=%d" % base["colors"].size())
		# shadow board really casts: hide it and compare outside the sprite mask
		main.actor.shadow_board.visible = false
		var no_shadow: Image = await _grab()
		main.actor.shadow_board.visible = true
		var diff: int = 0
		for y: int in res.y:
			for x: int in res.x:
				if image.get_pixel(x, y) != no_shadow.get_pixel(x, y):
					diff += 1
		check("gpu.shadow_cast_" + tag, diff > 20, "differing px with/without shadow board=%d" % diff)
		_save(no_shadow, "render_%s_no_shadow.png" % tag)
		# camera follow: sub-pixel and multi-pixel moves keep the sprite pixels identical (no blur)
		var worst_mismatch: int = 0
		var changed_max: int = 0
		var start: Vector2 = main.session.position
		var pixel_m: float = main.camera.size / float(res.y)
		for offset_px: float in [0.37, 0.81, 1.5, 3.3]:
			main.session.position = start + Coords.screen_dir_to_ground(Vector2(1.0, 0.3).normalized()) * offset_px * pixel_m / Config.M_PER_LOGIC_PX
			main.tick(0.0, Vector2.ZERO)
			var moved_image: Image = await _grab()
			var moved_snap: Dictionary = main.actor.snapshot()
			var moved: Dictionary = _sprite_pixels(moved_image, index, moved_snap["foot_screen"])
			var mismatches: int = 0
			for i: int in base["pixels"].size():
				if base["pixels"][i] != moved["pixels"][i]:
					mismatches += 1
			worst_mismatch = maxi(worst_mismatch, mismatches)
			var world_changed: int = 0
			for y: int in range(0, res.y, 3):
				for x: int in range(0, res.x, 3):
					if image.get_pixel(x, y) != moved_image.get_pixel(x, y):
						world_changed += 1
			changed_max = maxi(changed_max, world_changed)
			if offset_px == 1.5:
				_save(moved_image, "render_%s_moved.png" % tag)
		check("gpu.no_blur_follow_" + tag, worst_mismatch == 0, "worst sprite pixel mismatches over 4 sub-pixel moves=%d of %d; background samples changed (proves the camera moved)=%d" % [worst_mismatch, base["pixels"].size(), changed_max])
		check("gpu.follow_moved_world_" + tag, changed_max > 20, "changed=%d" % changed_max)
		main.session.position = start
	main.queue_free()
	await _frames(2)
	print("RESULT passes=%d failures=%d" % [passes, failures])
	quit(1 if failures > 0 else 0)
