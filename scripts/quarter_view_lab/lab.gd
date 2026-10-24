extends Node2D
## Isolated technical map; deliberately plain colour faces, no new finished art.
const QuarterProjection: GDScript = preload("res://scripts/quarter_view_lab/projection.gd")
const TILE: int = 4
const MAP_TILES: int = 192
const SPEED: float = 100.0 # Internal screen pixels/second, in all input directions.
const HALF: Vector2 = Vector2(2, 2)
const BUILDING: Rect2i = Rect2i(304, 272, 144, 144)
const LOW: Rect2i = Rect2i(480, 320, 48, 24)
const START: Vector2 = Vector2(480, 440)

var grid: WorldState
var logical_position: Vector2 = START
var camera: Camera2D
var actors: Node2D
var flower: Sprite2D
var marker: Polygon2D
var info: Label
var props: Array[Dictionary] = []
var marker_logical: Vector2 = Vector2.ZERO
var marker_cell: Vector2i = Vector2i.ZERO
var mouse_screen_position: Vector2 = Vector2.ZERO
var fade_enabled: bool = true
var camera_follow: bool = true
var auto_input: bool = true
var occluded: bool = false

func _ready() -> void:
	var window: Window = get_window()
	window.title = "グリーンベーダー｜クォータービュー技術確認"
	window.content_scale_size = Vector2i(960, 540)
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	window.content_scale_stretch = Window.CONTENT_SCALE_STRETCH_INTEGER
	window.min_size = Vector2i(960, 540)
	window.size = Vector2i(1920, 1080) if OS.get_cmdline_user_args().has("--1080") else Vector2i(960, 540)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_build_grid()
	_build_ground()
	actors = Node2D.new()
	actors.z_index = 1
	actors.y_sort_enabled = true
	add_child(actors)
	_build_prism(BUILDING, 112, Color("b1b4aa"), Color("8e9991"), Color("a3aaa0"))
	_build_prism(LOW, 12, Color("b8aa8d"), Color("a59981"), Color("aea28b"))
	flower = Sprite2D.new()
	flower.name = "ExistingFlower"
	flower.texture = PixelArt.flower()
	flower.centered = false
	flower.offset = Vector2(-8, -14)
	actors.add_child(flower)
	marker = Polygon2D.new()
	marker.color = Color(1.0, 0.82, 0.36, 0.85)
	marker.z_index = 0
	add_child(marker)
	camera = Camera2D.new()
	camera.position_smoothing_enabled = false
	add_child(camera)
	_build_ui()
	mouse_screen_position = get_viewport().get_mouse_position()
	present()

func _build_grid() -> void:
	var ground: TerrainDef = TerrainDef.new()
	ground.id = 0
	ground.walkable = true
	ground.is_target = true
	var wall: TerrainDef = TerrainDef.new()
	wall.id = 1
	wall.walkable = false
	wall.is_target = false
	var defs: Array[TerrainDef] = [ground, wall]
	grid = WorldState.new(MAP_TILES, MAP_TILES, defs, 2701)
	for rect: Rect2i in [BUILDING, LOW]:
		for v: int in range(rect.position.y / TILE, rect.end.y / TILE):
			for u: int in range(rect.position.x / TILE, rect.end.x / TILE):
				grid.terrain[grid.index_of(u, v)] = 1
	grid.apply_terrain_defs()
	# A fixed mature patch demonstrates that the state remains a logical grid.
	grid.debug_fill_stage(Rect2i(112, 112, 20, 16), WorldState.STAGE_MATURE)

func _build_ground() -> void:
	var extent: int = MAP_TILES * TILE
	var raster: Image = Image.create(extent * 2, extent, false, Image.FORMAT_RGBA8)
	raster.fill(Color("283b35"))
	for y: int in extent:
		for x: int in extent * 2:
			var uv: Vector2 = QuarterProjection.unproject(Vector2(x - extent + 0.5, y + 0.5))
			var tile: Vector2i = Vector2i(floori(uv.x / TILE), floori(uv.y / TILE))
			if not grid.in_bounds(tile.x, tile.y):
				continue
			var index: int = grid.index_of(tile.x, tile.y)
			var on_path: bool = uv.x >= 256 and uv.x < 576 and uv.y >= 224 and uv.y < 488
			var color: Color = Color("929c90") if on_path else Color("75966c")
			if grid.stage[index] == WorldState.STAGE_MATURE:
				color = Color("8db579")
			if grid.terrain[index] == 1:
				color = Color("7f887e")
			# Local modular paving marks, never a broad lighting gradient.
			if on_path and (int(uv.x) % 32 == 0 or int(uv.y) % 32 == 0):
				color = color.lightened(0.09)
			raster.set_pixel(x, y, color)
	var ground: Sprite2D = Sprite2D.new()
	ground.name = "ProjectedLogicalGround"
	ground.texture = ImageTexture.create_from_image(raster)
	ground.centered = false
	ground.position = Vector2(-extent, 0)
	add_child(ground)

## Rasterize a vertical prism into one-pixel-wide slices. Each slice sorts at
## its own nearest ground edge, not at the building centre or one south corner.
## At fixed screen x, uv=(x/2+y,y-x/2), giving these interval endpoints.
func _build_prism(rect: Rect2i, height: int, roof: Color, left: Color, right: Color) -> void:
	var columns: Array[Sprite2D] = []
	var x0: int = rect.position.x - rect.end.y
	var x1: int = rect.end.x - rect.position.y
	for x: int in range(x0, x1):
		var sx: float = x + 0.5
		var far_y: float = maxf(rect.position.x - sx * 0.5, rect.position.y + sx * 0.5)
		var near_y: float = minf(rect.end.x - sx * 0.5, rect.end.y + sx * 0.5)
		var first: int = ceili(far_y - height - 0.5)
		var end: int = ceili(near_y - 0.5)
		var image: Image = Image.create(1, maxi(1, end - first), false, Image.FORMAT_RGBA8)
		var face: Color = left if sx < rect.end.x - rect.end.y else right
		for y: int in range(first, end):
			image.set_pixel(0, y - first, roof if y + 0.5 < near_y - height else face)
		var slice: Sprite2D = Sprite2D.new()
		slice.texture = ImageTexture.create_from_image(image)
		slice.centered = false
		slice.position = Vector2(x, end)
		slice.offset = Vector2(0, first - end)
		actors.add_child(slice)
		columns.append(slice)
	props.append({"footprint": rect, "height": height, "columns": columns, "faded": false})

func _build_ui() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	add_child(layer)
	var font: SystemFont = SystemFont.new()
	font.font_names = PackedStringArray(["Yu Gothic UI", "Meiryo"])
	var title: Label = Label.new()
	title.position = Vector2(16, 10)
	title.add_theme_font_override("font", font)
	title.add_theme_font_size_override("font_size", 16)
	title.text = "クォータービュー技術確認｜仮の色面・既存の花"
	layer.add_child(title)
	info = Label.new()
	info.position = Vector2(16, 480)
	info.add_theme_font_override("font", font)
	info.add_theme_font_size_override("font_size", 13)
	layer.add_child(info)

func _physics_process(delta: float) -> void:
	if auto_input:
		var direction: Vector2 = Vector2(
			float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)),
			float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN)) - float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP)))
		move_screen(direction, delta)
	present()
	set_mouse_screen(mouse_screen_position)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		mouse_screen_position = event.position

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_F:
			fade_enabled = not fade_enabled
		elif event.physical_keycode == KEY_C:
			camera_follow = not camera_follow
		elif event.physical_keycode == KEY_R:
			logical_position = START

func move_screen(direction: Vector2, delta: float) -> void:
	var motion: Vector2 = QuarterProjection.unproject(direction.normalized() * SPEED * delta)
	logical_position = Walker.move(grid, TILE, logical_position, motion, HALF)

func present() -> void:
	flower.position = QuarterProjection.project(logical_position).round()
	if camera_follow:
		camera.position = (flower.position + Vector2(0, -60)).round()
	camera.force_update_scroll()
	occluded = false
	for prop: Dictionary in props:
		var overlap: bool = false
		var flower_rect: Rect2 = Rect2(flower.position + flower.offset, Vector2(16, 16))
		for column: Sprite2D in prop.columns:
			var column_rect: Rect2 = Rect2(column.position + column.offset, column.texture.get_size())
			if flower.position.y < column.position.y and flower_rect.intersects(column_rect):
				overlap = true
				break
		prop.faded = overlap and fade_enabled
		occluded = occluded or overlap
		for column: Sprite2D in prop.columns:
			column.modulate.a = 0.28 if prop.faded else 1.0
	info.text = "WASD / 矢印：画面方向に等速移動　F：遮蔽透過　C：追従　R：開始位置\n論理 (%.1f, %.1f)　地面セル (%d, %d)　遮蔽 %s　960×540 → 1080pは2倍" % [logical_position.x, logical_position.y, marker_cell.x, marker_cell.y, "透過中" if occluded and fade_enabled else "なし / 無効"]

func screen_to_ground(screen: Vector2) -> Vector2:
	return QuarterProjection.unproject(get_viewport().get_canvas_transform().affine_inverse() * screen)

func set_mouse_screen(screen: Vector2) -> void:
	marker_logical = screen_to_ground(screen)
	marker_cell = Vector2i(floori(marker_logical.x / TILE), floori(marker_logical.y / TILE))
	var origin: Vector2 = Vector2(marker_cell * TILE)
	var points: PackedVector2Array = PackedVector2Array()
	for corner: Vector2 in [Vector2.ZERO, Vector2(TILE, 0), Vector2(TILE, TILE), Vector2(0, TILE)]:
		points.append(QuarterProjection.project(origin + corner).round())
	marker.polygon = points

