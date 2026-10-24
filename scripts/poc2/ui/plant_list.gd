extends PanelContainer
## Presentation-only plant list and registration staging. Parent validates/commits assignments.
const Row: GDScript = preload("res://scripts/poc2/ui/plant_list_row.gd")
const Slot: GDScript = preload("res://scripts/poc2/ui/favorite_slot.gd")
signal closed
signal assignment_requested(slot: int, kind: String)
signal registration_changed(kind: String)
var held_kind: String = ""
var rows: Dictionary = {}
var slots: Array[Button] = []
var row_box: VBoxContainer
var detail_label: Label
var held_label: Label
var names: Dictionary = {}
var symbols: Dictionary = {}
var _allowed: Array[String] = []

func _ready() -> void:
	position = Vector2(80,18)
	size = Vector2(480,324)
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var margin: MarginContainer = MarginContainer.new()
	for side: String in ["left","right","top","bottom"]:
		margin.add_theme_constant_override("margin_"+side,8)
	add_child(margin)
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation",4)
	margin.add_child(box)
	var title: Label = Label.new()
	title.text = "植物一覧"
	title.add_theme_font_size_override("font_size",16)
	box.add_child(title)
	var header: HBoxContainer = HBoxContainer.new()
	header.add_theme_constant_override("separation",4)
	box.add_child(header)
	var headings: Array[String] = ["","植物","株","種生産/s","コスト"]
	for index: int in headings.size():
		var label: Label = Label.new()
		label.text = headings[index]
		label.custom_minimum_size.x = Row.WIDTHS[index]
		label.add_theme_font_size_override("font_size",11)
		header.add_child(label)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0,144)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	row_box = VBoxContainer.new()
	row_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row_box.add_theme_constant_override("separation",1)
	scroll.add_child(row_box)
	detail_label = Label.new()
	detail_label.custom_minimum_size.y = 42
	detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_label.add_theme_font_size_override("font_size",12)
	detail_label.text = "植物にカーソルを合わせると説明を表示します。"
	box.add_child(detail_label)
	held_label = Label.new()
	held_label.add_theme_font_size_override("font_size",11)
	held_label.text = "一覧をクリック、または枠へドラッグして登録"
	box.add_child(held_label)
	var bottom: HBoxContainer = HBoxContainer.new()
	bottom.add_theme_constant_override("separation",4)
	box.add_child(bottom)
	for index: int in 5:
		var slot: Button = Slot.new()
		slot.registration_enabled = true
		bottom.add_child(slot)
		slot.set_slot(index,"","","")
		slot.pressed.connect(func() -> void: assign_held(slot.slot_index))
		slot.assignment_requested.connect(_assign)
		slots.append(slot)
	var spacer: Control = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(spacer)
	var close_button: Button = Button.new()
	close_button.text = "閉じる E"
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.pressed.connect(func() -> void: cancel_registration(true); closed.emit())
	bottom.add_child(close_button)
	hide()

func set_rows(data: Array[Dictionary]) -> void:
	_allowed.clear()
	for index: int in data.size():
		var entry: Dictionary = data[index]
		var kind: String = entry.kind
		_allowed.append(kind)
		var row: Button = rows.get(kind) as Button
		if row == null:
			row = Row.new()
			row_box.add_child(row)
			row.picked.connect(hold)
			row.hovered.connect(func(text: String) -> void: detail_label.text = text)
			rows[kind] = row
		row_box.move_child(row,index)
		row.set_data(entry)
	for kind: Variant in rows.keys():
		if String(kind) not in _allowed:
			rows[kind].queue_free()
			rows.erase(kind)
	for slot: Button in slots:
		slot.allowed_kinds.assign(_allowed)
	if not held_kind.is_empty() and held_kind not in _allowed:
		cancel_registration()

func set_favorites(favorites: Array, icons: Dictionary, plant_names: Dictionary) -> void:
	symbols = icons
	names = plant_names
	for index: int in slots.size():
		var kind: String = String(favorites[index])
		slots[index].set_slot(index,kind,String(icons.get(kind,"")),String(plant_names.get(kind,"")))

func open_list() -> void:
	cancel_registration()
	show()

func hold(kind: String) -> void:
	if kind not in _allowed: return
	held_kind = kind
	held_label.text = "%s %s → 登録する枠を選択　右クリック/Escで取消" % [String(symbols.get(kind,"")),String(names.get(kind,kind))]
	registration_changed.emit(kind)

func cancel_registration(cancel_drag: bool = false) -> void:
	if cancel_drag and is_inside_tree() and get_viewport().gui_is_dragging():
		get_viewport().gui_cancel_drag()
	held_kind = ""
	if held_label != null:
		held_label.text = "一覧をクリック、または枠へドラッグして登録"
	registration_changed.emit("")

func assign_held(index: int) -> void:
	if not held_kind.is_empty():
		_assign(index,held_kind)

func _assign(index: int, kind: String) -> void:
	if index < 0 or index >= 5 or kind not in _allowed: return
	assignment_requested.emit(index,kind)
	cancel_registration()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		cancel_registration(true)
		accept_event()

func _input(event: InputEvent) -> void:
	# Buttons may consume a right click before it bubbles to this panel's GUI handler.
	if is_visible_in_tree() and event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_RIGHT:
		cancel_registration(true)
		get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END and is_inside_tree() and not get_viewport().gui_is_drag_successful():
		cancel_registration()
