class_name PlayHud
extends HBoxContainer
## Bottom HUD: seeds, water gauge, greening rate. Text is Japanese in the project's unsmoothed font;
## the gauge is flat rectangles on whole pixels.

const GAUGE_WIDTH: int = 96
const GAUGE_HEIGHT: int = 7
const GAUGE_BACK: Color = Color("2b3a37")
const GAUGE_FILL: Color = Color("63b8cf")
const GAUGE_FILL_LOW: Color = Color("dcab72")

class Gauge extends Control:
	var fraction: float = 0.0
	var low: bool = false

	func _init() -> void:
		custom_minimum_size = Vector2(GAUGE_WIDTH, GAUGE_HEIGHT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		draw_rect(Rect2(0, 0, GAUGE_WIDTH, GAUGE_HEIGHT), GAUGE_BACK)
		var inner: int = GAUGE_WIDTH - 2
		var filled: int = floori(clampf(fraction, 0.0, 1.0) * inner)
		if filled > 0:
			draw_rect(Rect2(1, 1, filled, GAUGE_HEIGHT - 2), GAUGE_FILL_LOW if low else GAUGE_FILL)

var seed_label: Label
var water_label: Label
var gauge: Gauge
var green_label: Label
var _seed_text: String = ""
var _water_text: String = ""
var _green_text: String = ""

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

func _label() -> Label:
	var label: Label = Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

## Cheap to call every frame: labels and the gauge are touched only when their text changes.
func refresh(play: PlayState, world: WorldState) -> void:
	var seed_text: String = "  種 %d/%d" % [play.seeds, play.tuning.seed_max]
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
