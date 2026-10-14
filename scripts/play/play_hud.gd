class_name PlayHud
extends HBoxContainer
## Bottom HUD: seeds, water gauge, greening rate, HP and the selected plant. Text is Japanese in the project's
## unsmoothed font; the gauges are flat rectangles on whole pixels.

const GAUGE_WIDTH: int = 96
const GAUGE_HEIGHT: int = 7
const HP_GAUGE_WIDTH: int = 40
const GAUGE_BACK: Color = Color("2b3a37")
const GAUGE_FILL: Color = Color("63b8cf")
const GAUGE_FILL_LOW: Color = Color("dcab72")
const HP_FILL: Color = Color("e0707a")
const HP_FILL_LOW: Color = Color("f2c14e")

class Gauge extends Control:
	var fraction: float = 0.0
	var low: bool = false
	var gauge_width: int = GAUGE_WIDTH
	var fill_color: Color = GAUGE_FILL
	var low_color: Color = GAUGE_FILL_LOW

	func _init(width: int = GAUGE_WIDTH, fill: Color = GAUGE_FILL, low_fill: Color = GAUGE_FILL_LOW) -> void:
		gauge_width = width
		fill_color = fill
		low_color = low_fill
		custom_minimum_size = Vector2(width, GAUGE_HEIGHT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		draw_rect(Rect2(0, 0, gauge_width, GAUGE_HEIGHT), GAUGE_BACK)
		var inner: int = gauge_width - 2
		var filled: int = floori(clampf(fraction, 0.0, 1.0) * inner)
		if filled > 0:
			draw_rect(Rect2(1, 1, filled, GAUGE_HEIGHT - 2), low_color if low else fill_color)

var seed_label: Label
var water_label: Label
var gauge: Gauge
var green_label: Label
var hp_label: Label
var hp_gauge: Gauge
var plant_label: Label
var _seed_text: String = ""
var _water_text: String = ""
var _green_text: String = ""
var _hp_text: String = ""
var _plant_text: String = ""

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 8)
	seed_label = _label()
	add_child(seed_label)
	water_label = _label()
	add_child(water_label)
	gauge = Gauge.new()
	gauge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add_child(gauge)
	green_label = _label()
	add_child(green_label)
	hp_label = _label()
	add_child(hp_label)
	hp_gauge = Gauge.new(HP_GAUGE_WIDTH, HP_FILL, HP_FILL_LOW)
	hp_gauge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add_child(hp_gauge)
	plant_label = _label()
	add_child(plant_label)

func _label() -> Label:
	var label: Label = Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

## The selection line: every plant kind in order, the current one in brackets (a cultivated plant with its seed cost), e.g. "通常 [にんじん:3] キウイ".
static func selection_text(play: PlayState) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for index: int in play.selectable.size():
		var def: PlantDef = play.selectable[index]
		var name: String = def.display_name if not def.display_name.is_empty() else String(def.key)
		if index != play.selected_index:
			parts.append(name)
		elif def.is_cultivated():
			parts.append("[%s:%d]" % [name, def.seed_cost])
		else:
			parts.append("[%s]" % name)
	return "植物 " + " ".join(parts)

## Cheap to call every frame: labels and the gauges are touched only when their text changes.
func refresh(play: PlayState, world: WorldState) -> void:
	var seed_text: String = "  種 %d/%d" % [play.available_seeds(), play.tuning.seed_max]
	if seed_text != _seed_text:
		_seed_text = seed_text
		seed_label.text = seed_text
	var water_value: int = floori(play.water)
	var water_text: String = "水分 %d" % water_value
	if water_text != _water_text:
		_water_text = water_text
		water_label.text = water_text
		gauge.fraction = play.water / play.tuning.water_max
		gauge.low = not play.can_fire_water()
		gauge.queue_redraw()
	var green_text: String = "緑化 %d％" % world.greening_percent_floor()
	if green_text != _green_text:
		_green_text = green_text
		green_label.text = green_text
	var hp_text: String = "HP %d/%d" % [play.hp, play.hp_max]
	if hp_text != _hp_text:
		_hp_text = hp_text
		hp_label.text = hp_text
		hp_gauge.fraction = float(play.hp) / float(play.hp_max)
		hp_gauge.low = play.hp * 3 <= play.hp_max
		hp_gauge.queue_redraw()
	var plant_text: String = selection_text(play)
	if plant_text != _plant_text:
		_plant_text = plant_text
		plant_label.text = plant_text
