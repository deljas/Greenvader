extends CanvasLayer
## POC-08 UI layer: title, pause menu, help panel, greening badge and the short save / load messages.
## Display only: it owns no game state. Buttons emit `chosen(action)`; PocMain does the work. While a menu is open the dimmer and
## the panel stop the mouse (the clicks never reach the game), and PocMain keeps the game clock paused.
signal chosen(action: StringName)

const HELP_LINES: Array[String] = [
	"操作説明",
	"移動　W A S D / 矢印キー　　調べる　E",
	"おたすけ植物　Q 設置モード（種類切替）→左クリックで置く・右クリックで終了　近くで E=持ち上げ",
	"種をまく　左クリック　　水をまく　右クリック",
	"植物の切替　Tab / マウスホイール",
	"Esc　メニュー（再開・保存・読込・操作説明）",
	"T　画面の文字の表示/非表示（景色を見る・撮る時）",
	"F3　倍速",
	"マウスの方向を向きます。内部画面は640×360固定です。",
	"保存　メニューの「保存」または F5（1枠）",
	"読込　メニューの「読込」（保存がある時のみ）",
	"目的：敵の巣をすべて壊して街を緑にする。",
	"内部緑化率が100％になると緑化完了。",
]

var root: Control
var dim: ColorRect
var title_panel: PanelContainer
var pause_panel: PanelContainer
var help_panel: PanelContainer
var title_message: Label
var pause_message: Label
var title_buttons: Dictionary = {}
var pause_buttons: Dictionary = {}
var badge: Label
var toast: Label
var help_back: StringName = &"back_pause"
## Controls that must stop game clicks while visible (PocMain adds them to its ui_controls).
var blockers: Array[Control] = []
var _toast_left: float = 0.0
## POL-02: false keeps the badge and the toast hidden (menus are not affected).
var text_visible: bool = true
var _theme: Theme = Theme.new()

func _ready() -> void:
	layer = 20
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = _theme
	add_child(root)
	badge = Label.new()
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_theme_color_override(&"font_shadow_color", Color(0, 0, 0, 0.9))
	badge.add_theme_constant_override(&"shadow_offset_x", 1)
	badge.add_theme_constant_override(&"shadow_offset_y", 1)
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	root.add_child(badge)
	toast = Label.new()
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.add_theme_color_override(&"font_color", Color("fff4c2"))
	toast.add_theme_color_override(&"font_shadow_color", Color(0, 0, 0, 0.95))
	toast.add_theme_constant_override(&"shadow_offset_x", 1)
	toast.add_theme_constant_override(&"shadow_offset_y", 1)
	toast.visible = false
	root.add_child(toast)
	dim = ColorRect.new()
	dim.color = Color(0.03, 0.05, 0.04, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.visible = false
	root.add_child(dim)
	blockers.append(dim)
	title_panel = _make_panel("グリーンベーダー　3D PoC", [["new_game", "新規開始"], ["continue", "続きから"], ["backup", "バックアップから続ける"], ["help", "操作説明"]], title_buttons)
	title_message = title_panel.get_meta(&"message")
	pause_panel = _make_panel("ポーズ", [["resume", "再開"], ["save", "保存"], ["load", "読込"], ["backup", "バックアップから読込"], ["help", "操作説明"], ["title", "タイトルへ"]], pause_buttons)
	pause_message = pause_panel.get_meta(&"message")
	help_panel = PanelContainer.new()
	var box: VBoxContainer = VBoxContainer.new()
	help_panel.add_child(box)
	var help_label: Label = Label.new()
	help_label.text = "\n".join(HELP_LINES)
	box.add_child(help_label)
	var back: Button = Button.new()
	back.text = "戻る"
	back.pressed.connect(func() -> void: chosen.emit(&"help_back"))
	box.add_child(back)
	help_panel.set_meta(&"back", back)
	help_panel.visible = false
	help_panel.set_anchors_preset(Control.PRESET_CENTER)
	help_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	help_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	root.add_child(help_panel)
	blockers.append(help_panel)
	blockers.append(title_panel)
	blockers.append(pause_panel)

func _make_panel(title: String, entries: Array, store: Dictionary) -> PanelContainer:
	var panel: PanelContainer = PanelContainer.new()
	var box: VBoxContainer = VBoxContainer.new()
	panel.add_child(box)
	var heading: Label = Label.new()
	heading.text = title
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override(&"font_size", int(_theme.default_font_size * 1.6))
	box.add_child(heading)
	var message: Label = Label.new()
	message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message.add_theme_color_override(&"font_color", Color("ffd34a"))
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.custom_minimum_size.x = 200
	box.add_child(message)
	for entry: Array in entries:
		var button: Button = Button.new()
		button.text = String(entry[1])
		button.pressed.connect(func() -> void: chosen.emit(StringName(entry[0])))
		box.add_child(button)
		store[StringName(entry[0])] = button
	panel.set_meta(&"message", message)
	panel.visible = false
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	root.add_child(panel)
	return panel

func set_scale_for(res: Vector2i) -> void:
	_theme.default_font_size = 10 * res.x / 640
	var size_px: int = _theme.default_font_size
	for panel: PanelContainer in [title_panel, pause_panel]:
		panel.get_child(0).get_child(0).add_theme_font_size_override(&"font_size", int(size_px * 1.6))
		(panel.get_meta(&"message") as Label).custom_minimum_size.x = 22 * size_px
	toast.position = Vector2(0, res.y - 85 * size_px / 10)
	toast.size = Vector2(res.x, 2 * size_px)
	badge.position = Vector2(res.x - 300 * size_px / 10 - 4, res.y - 5 * size_px - 6)
	badge.size = Vector2(300 * size_px / 10, 4 * size_px)
	for panel: Control in [title_panel, pause_panel, help_panel]:
		panel.reset_size()

func menu_open() -> bool:
	return dim.visible

func _show_only(panel: Control) -> void:
	for p: Control in [title_panel, pause_panel, help_panel]:
		p.visible = p == panel
	dim.visible = panel != null
	if panel != null:
		panel.reset_size()

## info: PocSave.slot_info(). Continue is disabled without a saved game.
func show_title(info: Dictionary, message: String = "") -> void:
	_show_only(title_panel)
	(title_buttons[&"continue"] as Button).disabled = not bool(info.get("slot", false))
	(title_buttons[&"continue"] as Button).text = "続きから" if bool(info.get("slot", false)) else "続きから（保存なし）"
	(title_buttons[&"backup"] as Button).visible = bool(info.get("backup", false))
	title_message.text = message if not message.is_empty() else (String(info.get("slot_text", "")) if bool(info.get("slot", false)) else "保存データはありません")
	title_panel.reset_size()
	(title_buttons[&"new_game"] as Button).grab_focus()

func show_pause(info: Dictionary, message: String = "") -> void:
	_show_only(pause_panel)
	(pause_buttons[&"load"] as Button).disabled = not bool(info.get("slot", false))
	(pause_buttons[&"backup"] as Button).visible = bool(info.get("backup", false))
	pause_message.text = message if not message.is_empty() else (String(info.get("slot_text", "")) if bool(info.get("slot", false)) else "保存データはありません")
	pause_panel.reset_size()
	(pause_buttons[&"resume"] as Button).grab_focus()

func show_help(back_to: StringName) -> void:
	help_back = back_to
	_show_only(help_panel)
	(help_panel.get_meta(&"back") as Button).grab_focus()

func hide_menus() -> void:
	_show_only(null)

func set_menu_message(text: String) -> void:
	if title_panel.visible:
		title_message.text = text
		title_panel.reset_size()
	if pause_panel.visible:
		pause_message.text = text
		pause_panel.reset_size()

func show_toast(text: String, seconds: float = 3.0) -> void:
	toast.text = text
	toast.visible = text_visible
	_toast_left = seconds

func set_badge(percent: int, greened: int, targets: int, zones: String) -> void:
	var full: bool = targets > 0 and greened == targets
	badge.text = "内部緑化率 %d％（%d/%d）%s\n%s" % [percent, greened, targets, "　★緑化完了" if full else "", zones]
	badge.add_theme_color_override(&"font_color", Color("ffd34a") if full else Color("e8f5d6"))

func set_text_visible(value: bool) -> void:
	text_visible = value
	badge.visible = value
	toast.visible = value and _toast_left > 0.0

func tick(delta: float) -> void:
	if _toast_left > 0.0:
		_toast_left -= delta
		if _toast_left <= 0.0:
			toast.visible = false
