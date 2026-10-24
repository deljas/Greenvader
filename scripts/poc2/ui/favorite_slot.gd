extends Button
## A reusable HUD/list slot. It emits intent and never changes the saved favorites itself.
signal assignment_requested(slot: int, kind: String)
var slot_index: int = 0
var kind: String = ""
var registration_enabled: bool = false
var allowed_kinds: Array[String] = []

func _ready() -> void:
	custom_minimum_size = Vector2(42,26)
	focus_mode = Control.FOCUS_NONE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

func set_slot(index: int, plant_kind: String, icon: String, plant_name: String, selected: bool = false) -> void:
	slot_index = index
	kind = plant_kind
	text = "%d %s" % [index+1,icon if not plant_kind.is_empty() else "·"]
	tooltip_text = plant_name if not plant_kind.is_empty() else "空の枠"
	modulate = Color("f4db90") if selected else Color.WHITE

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if not registration_enabled or not data is Dictionary:
		return false
	return data.get("type","") == "plant_favorite" and data.get("kind") is String and data.kind in allowed_kinds

func _drop_data(at_position: Vector2, data: Variant) -> void:
	if _can_drop_data(at_position,data):
		assignment_requested.emit(slot_index,String(data.kind))
