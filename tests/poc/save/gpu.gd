extends SceneTree
## POC-08 GPU capture of the UI (real renderer, NOT --headless):
## godot --path <repo> --script res://tests/poc/save/gpu.gd
## No OS-level input / cursor movement / foregrounding; the window is marked unfocusable. Images go to evidence/poc/08/.
## The root viewport (game + UI layer) is captured. States are reached by calling the same functions the buttons call.
const Coords: GDScript = preload("res://scripts/poc/poc_coords.gd")
const PocSave: GDScript = preload("res://scripts/poc/save/poc_save.gd")
const OUT: String = "res://evidence/poc/08/"
const DIR: String = "user://poc_saves_test_gpu/"

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

func _shot(name: String) -> Image:
	await _frames(4)
	var image: Image = root.get_texture().get_image()
	image.save_png(ProjectSettings.globalize_path(OUT + name))
	print("INFO ", name, " ", image.get_width(), "x", image.get_height())
	return image

func clean() -> void:
	for file: String in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR + file)

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		print("NOT_RUN gpu (headless display server)")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	DirAccess.make_dir_recursive_absolute(DIR)
	clean()
	print("renderer=", RenderingServer.get_video_adapter_name(), " display=", DisplayServer.get_name(), " window=", root.size)
	main = load("res://scenes/poc.tscn").instantiate()
	main.set_meta(&"poc_town", true)
	main.auto_process = false
	root.add_child(main)
	main.save_dir = DIR
	main.window_size_override = Vector2i(1920, 1080)
	await _frames(3)
	# some play so that the HUD has numbers: stand by the start, sow a few seeds
	var s: RefCounted = main.session
	for i: int in 30:
		main.tick(0.1, Vector2.ZERO)
	# --- title without a save, then with one
	main.save_game()
	main.open_title()
	await _shot("title_640.png")
	check("gpu.title_shown", main.ui.title_panel.visible and main.ui.dim.visible)
	main._on_ui_chosen(&"help")
	await _shot("help_640.png")
	check("gpu.help_shown", main.ui.help_panel.visible)
	main._on_ui_chosen(&"help_back")
	main._on_ui_chosen(&"new_game")
	# --- play a little: seeds and water at the start so the HUD changes
	s = main.session
	for i: int in 80:
		main.tick(0.1, Vector2(1, 0) if i < 40 else Vector2(0, 1))
	await _shot("hud_640.png")
	check("gpu.hud_badge", main.ui.badge.text.contains("内部緑化率"), main.ui.badge.text.get_slice("\n", 0))
	# --- pause menu
	main.open_pause_menu()
	await _shot("pause_640.png")
	check("gpu.pause_shown", main.ui.pause_panel.visible and s.paused)
	# --- save done
	main._on_ui_chosen(&"save")
	await _frames(3)
	await _shot("save_done_640.png")
	check("gpu.save_message", main.ui.pause_message.text.contains("保存しました"), main.ui.pause_message.text)
	# --- rejection message (a damaged slot; the backup is offered)
	main.save_game()
	var f: FileAccess = FileAccess.open(DIR + PocSave.SLOT_FILE, FileAccess.WRITE)
	f.store_string("{ damaged")
	f.close()
	main._on_ui_chosen(&"load")
	await _shot("reject_640.png")
	check("gpu.reject_message", main.ui.pause_message.text.contains("読み込めません") and (main.ui.pause_buttons[&"backup"] as Button).visible, main.ui.pause_message.text)
	main._on_ui_chosen(&"backup")
	await _frames(2)
	check("gpu.backup_loaded", main.menu == &"")
	# --- 960 HUD with a pause-less game view
	main.set_resolution(1)
	for i: int in 10:
		main.tick(0.1, Vector2.ZERO)
	await _shot("hud_960.png")
	main.open_pause_menu()
	await _shot("pause_960.png")
	main.close_menu()
	clean()
	DirAccess.remove_absolute(DIR)
	print("RESULT passes=%d failures=%d" % [passes, failures])
	quit(1 if failures > 0 else 0)
