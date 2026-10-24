extends Node2D
## Isolated art viewer: no WorldState, saves, simulation or normal-game changes.

const Raster: GDScript = preload("res://scripts/art_study/study_raster.gd")
var variant: int = 0
var images: Array[Image] = []
var textures: Array[ImageTexture] = []
var raster_builds: int = 0
var picture: Sprite2D
var choice_label: Label
var buttons: Array[Button] = []

func _ready() -> void:
	get_window().title = "グリーンベーダー｜草と広葉樹の比較"
	get_window().min_size = Vector2i(1280, 720)
	get_window().size = Vector2i(1280, 720)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	for rich: bool in [false, true]:
		var image: Image = Raster.composition(rich)
		images.append(image)
		textures.append(ImageTexture.create_from_image(image))
		raster_builds += 1
	picture = Sprite2D.new()
	picture.centered = false
	add_child(picture)
	_build_ui()
	select_variant(0)

func _build_ui() -> void:
	var font: SystemFont = SystemFont.new()
	font.font_names = PackedStringArray(["Yu Gothic UI", "Meiryo", "Noto Sans CJK JP"])
	_label("草と広葉樹の比較", Vector2i(18, 10), 16, font)
	choice_label = _label("", Vector2i(235, 12), 13, font)
	for i: int in 2:
		var button: Button = Button.new()
		button.text = "A 控えめ" if i == 0 else "B 豊か"
		button.position = Vector2(426 + i * 102, 9)
		button.size = Vector2(94, 28)
		button.add_theme_font_override("font", font)
		button.add_theme_font_size_override("font_size", 13)
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(select_variant.bind(i))
		add_child(button)
		buttons.append(button)
	_label("同じ短草・色・光で、背の高い房の密度だけを比較", Vector2i(18, 326), 13, font)
	_label("A / B キーでも切替　　花 16px ・ 種 ・ イノシシは既存の大きさ", Vector2i(18, 344), 11, font)

func _label(value: String, at: Vector2i, size_px: int, font: Font) -> Label:
	var label: Label = Label.new()
	label.text = value
	label.position = at
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", size_px)
	label.add_theme_color_override("font_color", Color("e0e2c9"))
	add_child(label)
	return label

func select_variant(index: int) -> void:
	variant = clampi(index, 0, 1)
	picture.texture = textures[variant]
	choice_label.text = "A：控えめな房" if variant == 0 else "B：豊かな房"
	for i: int in buttons.size():
		buttons[i].modulate = Color("e5efba") if i == variant else Color("9cad9f")

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key: InputEventKey = event as InputEventKey
		if key.keycode == KEY_A or key.keycode == KEY_1:
			select_variant(0)
		elif key.keycode == KEY_B or key.keycode == KEY_2:
			select_variant(1)
