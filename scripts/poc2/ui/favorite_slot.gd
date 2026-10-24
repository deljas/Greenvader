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

## cost < 0 means "no price shown" (empty slot). An unaffordable price is tinted, never hidden.
func set_slot(index: int, plant_kind: String, icon: String, plant_name: String, selected: bool = false, cost: int = -1, affordable: bool = true) -> void:
	slot_index = index
	kind = plant_kind
	text = "%d %s" % [index+1,icon if not plant_kind.is_empty() else "·"]
	if not plant_kind.is_empty() and cost >= 0:
		text += " ●%d" % cost
	tooltip_text = plant_name if not plant_kind.is_empty() else "空の枠"
	var tint: Color = Color("e8907e")
	for style: String in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]:
		if cost >= 0 and not plant_kind.is_empty() and not affordable: add_theme_color_override(style,tint)
		else: remove_theme_color_override(style)
	modulate = Color("f4db90") if selected else Color.WHITE

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if not registration_enabled or not data is Dictionary:
		return false
	return data.get("type","") == "plant_favorite" and data.get("kind") is String and data.kind in allowed_kinds

func _drop_data(at_position: Vector2, data: Variant) -> void:
	if _can_drop_data(at_position,data):
		assignment_requested.emit(slot_index,String(data.kind))
