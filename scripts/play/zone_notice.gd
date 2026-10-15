class_name ZoneNotice
extends PanelContainer
## Short notices in a small panel (P2-04): "<zone> became stable", "all zones greened". Messages queue up (a few at most) and
## show one after the other; the node is pausable, so a paused game neither shows nor ages them. Positions and size are whole
## pixels; the text is the project's unsmoothed Japanese font.

const SHOW_SECONDS: float = 3.0
const CLEARED_SECONDS: float = 8.0
const QUEUE_MAX: int = 6
const PANEL_SIZE: Vector2 = Vector2(320, 22)

var label: Label
var queue: Array[Dictionary] = []
var current_text: String = ""
var remaining: float = 0.0
## Observability for tests: every text that was shown, in order.
var shown_log: Array[String] = []

func setup(ui_theme: Theme, at: Vector2) -> void:
	theme = ui_theme
	position = at
	size = PANEL_SIZE
	custom_minimum_size = PANEL_SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_PAUSABLE
	label = Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	visible = false

## Queues a notice (the oldest waiting one is dropped when the queue is full).
func push(text: String, seconds: float = SHOW_SECONDS) -> void:
	if text.is_empty():
		return
	if current_text.is_empty():
		_show(text, seconds)
		return
	if queue.size() >= QUEUE_MAX:
		queue.pop_front()
	queue.append({"text": text, "seconds": seconds})

func _show(text: String, seconds: float) -> void:
	current_text = text
	remaining = seconds
	shown_log.append(text)
	if label != null:
		label.text = text
	visible = true

## Ages the shown notice by `delta` game seconds and moves on to the next one.
func advance(delta: float) -> void:
	if current_text.is_empty():
		return
	remaining -= delta
	if remaining > 0.0:
		return
	if queue.is_empty():
		current_text = ""
		visible = false
		return
	var next: Dictionary = queue.pop_front()
	_show(String(next["text"]), float(next["seconds"]))

func _process(delta: float) -> void:
	advance(delta)
