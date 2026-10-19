extends SceneTree
## POL-02 GPU captures (real renderer, NOT --headless): godot --path <repo> --script res://tests/poc/polish/text_toggle_gpu.gd
## root.unfocusable, no OS input / cursor / foregrounding. Captures the whole content (3D + UI) with the text shown / hidden.
const Config: GDScript = preload("res://scripts/poc/poc_config.gd")
const Coords: GDScript = preload("res://scripts/poc/poc_coords.gd")
const OUT: String = "res://evidence/polish/02/"
var main: Node
var s: RefCounted

func _init() -> void:
	root.unfocusable = true
	_run.call_deferred()

func _frames(n: int) -> void:
	for i: int in n:
		await process_frame
	await RenderingServer.frame_post_draw

func set_hour(hour: float) -> void:
	var elapsed: float = fposmod(hour - float(s.env_tuning["start_hour"]), 24.0) / 24.0 * float(s.env_tuning["day_seconds"])
	s.clock.load_dict({"version": 1, "elapsed": elapsed, "growth_ticks": int(elapsed / s.clock.growth_period), "spread_ticks": int(elapsed / s.clock.spread_period)})
	s.growth.ticks = s.clock.growth_ticks
	s.state.growth_tick = s.clock.growth_ticks

func shot(name: String) -> void:
	await _frames(4)
	var image: Image = root.get_texture().get_image()
	image.save_png(ProjectSettings.globalize_path(OUT + name + ".png"))
	print("INFO ", name, " ", image.get_size())

func key_t() -> void:
	var ev: InputEventKey = InputEventKey.new()
	ev.physical_keycode = KEY_T
	ev.pressed = true
	Input.parse_input_event(ev)
	await _frames(2)

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		print("NOT_RUN gpu (headless display server)")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	print("renderer=", RenderingServer.get_video_adapter_name(), " window=", root.size)
	main = load("res://scenes/poc.tscn").instantiate()
	main.set_meta(&"poc_town", true)
	root.add_child(main)
	main.auto_process = false
	main.window_size_override = Vector2i(1920, 1080)
	await _frames(3)
	s = main.session
	set_hour(0.0)
	s.position = Coords.ground_to_logic(Vector2(7.6, 11.2))
	for res_index: int in 2:
		main.set_resolution(res_index, Vector2i(1920, 1080))
		main.show_notice("テスト通知：夜の景色")
		main.ui.show_toast("保存しました（撮影用）", 60.0)
		for i: int in 30:
			main.tick(0.05, Vector2.ZERO)
		var w: int = Config.RESOLUTIONS[res_index].x
		await shot("night_%d_text_on" % w)
		await key_t()
		await shot("night_%d_text_off" % w)
		await key_t()
	# panorama
	set_hour(12.0)
	s.position = Coords.cell_center_logic(main.viewpoint.cell) + Vector2(14, 0)
	main.tick(0.1, Vector2.ZERO)
	main.set_resolution(0, Vector2i(1920, 1080))
	main.enter_viewpoint()
	await shot("view_640_text_on")
	await key_t()
	await shot("view_640_text_off")
	await key_t()
	print("RESULT done text_visible=", main.text_visible)
	quit(0)
