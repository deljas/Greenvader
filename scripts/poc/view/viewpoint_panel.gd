extends PanelContainer
## WTH-02 panorama panel (greening rate, time, weather; Japanese). Display only: it shows the text it is given and never takes the mouse.
var label: Label
## POL-02: true (text hidden with T) keeps the panel invisible; the wanted state is kept and comes back with T.
var suppressed: bool = false:
	set(value):
		suppressed = value
		visible = _wanted and not suppressed
var _wanted: bool = false

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	label = Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override(&"font_color", Color("fff4c2"))
	add_child(label)
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.05, 0.04, 0.8)
	style.set_content_margin_all(4.0)
	add_theme_stylebox_override(&"panel", style)
	visible = false

## Top centre of a `res` sized screen; the font follows the render resolution (10 px at 640).
func layout(res: Vector2i) -> void:
	var font: int = 10 * res.x / 640
	label.add_theme_font_size_override(&"font_size", font)
	reset_size()
	position = Vector2((float(res.x) - size.x) * 0.5, float(font) * 3.0)

func show_text(text: String, res: Vector2i) -> void:
	label.text = text
	_wanted = true
	visible = not suppressed
	layout(res)

func hide_panel() -> void:
	_wanted = false
	visible = false
