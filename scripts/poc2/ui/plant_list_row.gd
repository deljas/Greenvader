extends Button
## One unlocked plant row. Picking/dragging means favorite registration, not placement.
signal picked(kind: String)
signal hovered(detail: String)
var kind: String = ""
var detail: String = ""
var icon_text: String = ""
var plant_name: String = ""
var columns: Array[Label] = []
const WIDTHS: Array[float] = [24.0,112.0,38.0,128.0,72.0]

func _ready() -> void:
	custom_minimum_size = Vector2(0,20)
	focus_mode = Control.FOCUS_NONE
	var line: HBoxContainer = HBoxContainer.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	line.add_theme_constant_override("separation",4)
	add_child(line)
	for width: float in WIDTHS:
		var label: Label = Label.new()
		label.custom_minimum_size.x = width
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.add_theme_font_size_override("font_size",12)
		line.add_child(label)
		columns.append(label)
	pressed.connect(func() -> void: picked.emit(kind))
	mouse_entered.connect(func() -> void: hovered.emit(detail))

static func production_text(per_second: float, produces_seeds: bool = true) -> String:
	if not produces_seeds:
		return "—"
	if per_second < 1.0:
		return "+%.3f ●/s" % per_second
	if per_second < 100.0:
		return "+%.2f ●/s" % per_second
	return "+%.1f ●/s" % per_second

func set_data(data: Dictionary) -> void:
	kind = String(data.kind)
	icon_text = String(data.icon)
	plant_name = String(data.name)
	detail = String(data.description) + "\n成熟1株　" + production_text(float(data.mature_rate),bool(data.produces))
	var texts: Array[String] = [icon_text,plant_name,str(int(data.count)),production_text(float(data.rate),bool(data.produces)),"● %d" % int(data.cost)]
	for index: int in columns.size():
		columns[index].text = texts[index]

func _get_drag_data(_at_position: Vector2) -> Variant:
	if kind.is_empty():
		return null
	picked.emit(kind)
	var preview: Label = Label.new()
	preview.text = icon_text + " " + plant_name
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_drag_preview(preview)
	return {"type":"plant_favorite","kind":kind}
