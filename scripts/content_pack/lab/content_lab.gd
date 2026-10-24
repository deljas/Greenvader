extends Node2D
## 追加コンテンツの専用確認画面(640x360)。入力を lab_game へ渡し、lab_view で描く。
## 本番へ渡す部品(scripts/content_pack の窓口)をそのまま使う。通常ゲームの入口・保存領域は使わない。
const Game: GDScript = preload("res://scripts/content_pack/lab/lab_game.gd")
const View: GDScript = preload("res://scripts/content_pack/lab/lab_view.gd")

var game: RefCounted
var view: RefCounted
var ui: Dictionary = {"t": 0.0, "mouse": Vector2(-10, -10)}
var auto_step: bool = true   # false なら _process で時間を進めない(テストが step を直接呼ぶ)

func _init() -> void:
	game = Game.new()
	view = View.new()

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	game.note("CONTENT LAB READY", "ui")

func _process(delta: float) -> void:
	if not bool(ui.get("freeze", false)):
		ui.t = float(ui.t) + delta
	if auto_step:
		game.step(delta)
	queue_redraw()

func _draw() -> void:
	view.draw(self, game, ui)

# ---------------------------------------------------------------- 入力
func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		var k: InputEventKey = event
		if k.pressed and not k.echo:
			_key(k)
	elif event is InputEventMouseMotion:
		_mouse_move((event as InputEventMouseMotion).position)
	elif event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		_mouse_move(mb.position)
		if mb.pressed:
			_click(mb.position, mb.button_index, mb.shift_pressed)

func _key(k: InputEventKey) -> void:
	game.msg = ""
	match k.physical_keycode:
		KEY_SPACE: game.toggle_pause()
		KEY_N: game.toggle_day()
		KEY_1: game.set_speed(1)
		KEY_2: game.set_speed(10)
		KEY_3: game.set_speed(60)
		KEY_R: game.tool = "remove" if game.tool != "remove" else "combat"
		KEY_ESCAPE: game.tool = "combat"
		KEY_TAB: game.toggle_tab()
		KEY_G: game.toggle_page()
		KEY_M: game.show_detect = not game.show_detect
		KEY_F5: game.save()
		KEY_F9: game.load_save()
		KEY_H: game.show_hidden = not game.show_hidden

func _mouse_move(p: Vector2) -> void:
	ui.mouse = p
	if p.x < float(View.MAP_W) and p.y < float(View.MAP_H) and p.x >= 0.0 and p.y >= 0.0:
		var w: Vector2 = p / View.S
		game.set_aim_to(w)
		game.update_hover(game.cell_of(w))

func _click(p: Vector2, button: int, shift: bool) -> void:
	game.msg = ""
	if p.x >= float(View.PANEL_X):
		if button == MOUSE_BUTTON_LEFT:
			for b: Dictionary in view.buttons(game):
				if (b.r as Rect2).has_point(p):
					do_action(str(b.action))
					return
		return
	if p.y >= float(View.MAP_H) or p.x < 0.0 or p.y < 0.0:
		return
	var w: Vector2 = p / View.S
	if game.tool == "combat":
		if button == MOUSE_BUTTON_LEFT:
			if shift:
				game.tackle(w)
			else:
				game.shoot(w)
		elif button == MOUSE_BUTTON_RIGHT:
			if shift:
				game.bazooka(w)
			else:
				game.do_water(w)
		return
	if button == MOUSE_BUTTON_RIGHT:
		game.tool = "combat"
		return
	if button != MOUSE_BUTTON_LEFT:
		return
	match game.tool:
		"enemy": game.spawn_enemy(game.sel_enemy, w)
		"crop": game.place(game.sel_crop, game.cell_of(w))
		"remove": game.remove_at(game.cell_of(w))

func do_action(a: String) -> void:
	var parts: PackedStringArray = a.split(":")
	match parts[0]:
		"tab": game.tab = parts[1]
		"pick_enemy":
			game.sel_enemy = parts[1]
			game.tool = "enemy"
		"pick_crop":
			game.sel_crop = parts[1]
			game.tool = "crop"
		"origin": game.origin = parts[1]
		"tool": game.tool = parts[1]
		"day": game.toggle_day()
		"pause": game.toggle_pause()
		"speed": game.set_speed(int(parts[1]))
		"save": game.save()
		"load": game.load_save()
		"dbg_roll_hit": game.debug_roll(true)
		"dbg_roll_miss": game.debug_roll(false)
		"dbg_seeds": game.debug_seeds()
		"dbg_mature": game.debug_mature()
		"dbg_water": game.debug_water_all()
		"clear_enemies": game.clear_enemies()

## テスト用: パネルのボタンの中心(viewport座標)。見つからなければ (-1,-1)。
func button_center(action: String) -> Vector2:
	for b: Dictionary in view.buttons(game):
		if str(b.action) == action:
			return (b.r as Rect2).get_center()
	return Vector2(-1, -1)
