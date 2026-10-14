extends Node
## Read-only observer for P0-VERIFY. Instantiates the real res://scenes/main.tscn and
## logs state every physics frame. It never injects input and never writes game state.
## Usage: godot --path <proj> res://tests/independent/p0_verify_observer.tscn -- --vlog=<file>

var game: Node
var log_file: FileAccess
var frame: int = 0
var type_cache: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_physics_priority = 1000
	var path: String = "user://p0_verify_observer.log"
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--vlog="):
			path = argument.trim_prefix("--vlog=")
	log_file = FileAccess.open(path, FileAccess.WRITE)
	game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(game)
	var info: Dictionary = {
		"t": Time.get_unix_time_from_system(),
		"window_mode": DisplayServer.window_get_mode(),
		"window_size": DisplayServer.window_get_size(),
		"window_pos": DisplayServer.window_get_position(),
		"screen": DisplayServer.window_get_current_screen(),
		"viewport": get_viewport().get_visible_rect().size,
		"renderer": RenderingServer.get_current_rendering_method(),
		"adapter": RenderingServer.get_video_adapter_name(),
		"min_size": get_window().min_size,
		"cmdline": OS.get_cmdline_args(),
		"physics_ticks": Engine.physics_ticks_per_second,
	}
	log_file.store_line("S," + JSON.stringify(info, "", true, true))

func _input(event: InputEvent) -> void:
	if log_file == null:
		return
	var t: float = Time.get_unix_time_from_system()
	if event is InputEventKey:
		var key: InputEventKey = event
		log_file.store_line("E,%.6f,key,keycode=%d,physical=%d,pressed=%s,echo=%s" % [t, key.keycode, key.physical_keycode, key.pressed, key.echo])
	elif event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		log_file.store_line("E,%.6f,mouse,button=%d,pressed=%s,pos=%s" % [t, mb.button_index, mb.pressed, mb.position])

func shot_type(sprite: Sprite2D) -> String:
	var key: int = sprite.get_instance_id()
	if not type_cache.has(key):
		type_cache[key] = sprite.texture.get_image().get_pixel(2, 1).to_html(false)
	return type_cache[key]

func _physics_process(_delta: float) -> void:
	frame += 1
	var player: Node2D = game.get("player")
	var camera: Camera2D = game.get("camera")
	var shots: Array = game.get("preview_projectiles")
	var parts: PackedStringArray = []
	for shot: Dictionary in shots:
		var sprite: Sprite2D = shot["sprite"]
		var p: Vector2 = shot["position"]
		parts.append("%s@%.3f:%.3f/%d:%d/age%.3f" % [shot_type(sprite), p.x, p.y, int(sprite.position.x), int(sprite.position.y), shot["age"]])
	var sim: Vector2 = player.get("simulation_position")
	var aim: Vector2 = player.get("aim_direction")
	var c: Vector2 = camera.get_screen_center_position()
	log_file.store_line("F,%d,%.6f,%.4f,%.4f,%.1f,%.1f,%.5f,%.5f,%s,%d,%s,%.1f,%.1f,%.1f,%.1f,%.2f,%.2f,%s" % [
		frame, Time.get_unix_time_from_system(), sim.x, sim.y, player.position.x, player.position.y, aim.x, aim.y,
		get_tree().paused, shots.size(), game.get("condition"), camera.position.x, camera.position.y, c.x, c.y,
		get_viewport().get_mouse_position().x, get_viewport().get_mouse_position().y, ";".join(parts)])
	if frame % 20 == 0:
		var rects: Dictionary = {}
		var buttons: Array = game.get("weather_buttons")
		var names: Array[String] = ["sunny", "rain", "night"]
		for index: int in buttons.size():
			var b: Button = buttons[index]
			var r: Rect2 = b.get_global_rect()
			rects[names[index]] = [r.position.x, r.position.y, r.size.x, r.size.y, b.disabled]
		var panel: Control = game.get("pause_panel")
		var resume: Button = panel.get_child(0).get_child(1)
		var rr: Rect2 = resume.get_global_rect()
		rects["resume"] = [rr.position.x, rr.position.y, rr.size.x, rr.size.y, panel.visible]
		rects["win"] = DisplayServer.window_get_size()
		log_file.store_line("R,%.6f,%s" % [Time.get_unix_time_from_system(), JSON.stringify(rects, "", true, true)])
	log_file.flush()
