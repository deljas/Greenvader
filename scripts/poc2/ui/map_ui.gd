extends Control
## All-map / minimap share disclosure and icons. Commands only through session validation.
const Coords: GDScript = preload("res://scripts/poc/poc_coords.gd")
const WorldView: GDScript = preload("res://scripts/poc2/view/world_view.gd")
const NAMES: Dictionary = {"clover":"クローバー", "carrot":"ニンジン", "wheat":"小麦", "rafflesia":"ラフレシア", "watermelon":"スイカ", "army":"アーミー", "gatlinger":"ガトリンガー", "sprinkler":"スプリンクラー"}
signal toggled(open: bool)
signal notified(text: String)
var session: RefCounted
var expanded: bool = false
var zoom: int = 1
var map_center: Vector2 = Vector2(448,448)
var selected_id: int = -1
var selected_helper: bool = false
var map_rect: Rect2 = Rect2(6, 6, 108, 108)
var terrain_texture: ImageTexture
var remove_button: Button
var supply_button: Button
var popup: PanelContainer
var quantity: SpinBox
var _popup_action: String = ""
var _terrain_wait: float = 0.0
var _icon_points: Array[Dictionary] = []
var _terrain_source: Image
var _mini_center: Vector2 = Vector2.ZERO

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(640,360)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	remove_button = _button("×", "撤去")
	supply_button = _button("＋", "種を補給")
	remove_button.pressed.connect(func() -> void: open_popup("remove"))
	supply_button.pressed.connect(func() -> void: open_popup("supply"))
	popup = PanelContainer.new()
	popup.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(popup)
	popup.hide()

func _button(text: String, tip: String) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.tooltip_text = tip
	button.size = Vector2(22,20)
	button.focus_mode = Control.FOCUS_NONE
	add_child(button)
	button.hide()
	return button

func bind(source: RefCounted) -> void:
	session = source
	selected_id = -1
	popup.hide()
	refresh_terrain()

func set_expanded(value: bool) -> void:
	expanded = value
	zoom = 1
	map_center = Vector2(448,448)
	selected_id = -1
	popup.hide()
	map_rect = Rect2(208,64,224,224) if expanded else Rect2(6,6,108,108)
	toggled.emit(expanded)
	refresh_terrain()
	update_buttons()
	queue_redraw()

func deselect() -> void:
	selected_id = -1
	popup.hide()
	update_buttons()
	queue_redraw()

func _process(delta: float) -> void:
	if session == null: return
	_terrain_wait -= delta
	if _terrain_wait <= 0.0:
		_terrain_wait = 0.5
		refresh_terrain()
	elif not expanded and _snapped_mini_center() != _mini_center:
		# Reproject cached terrain whenever its shared, pixel-snapped centre moves.
		_mini_center = _snapped_mini_center()
		_rasterize_terrain()
	update_buttons()
	queue_redraw()

func refresh_terrain() -> void:
	if session == null: return
	var image: Image = Image.create(session.state.width, session.state.height, false, Image.FORMAT_RGB8)
	for index: int in session.state.tile_count():
		var color: Color = Color("151e20")
		if session.known[index] != 0:
			var terrain: int = session.state.terrain[index]
			color = Color("676856")
			if terrain == 3: color = Color("4d8eab")
			elif terrain == 4: color = Color("a5a292")
			elif session.state.stage[index] >= WorldState.GREENED_MIN_STAGE: color = Color("558a50")
			elif terrain == 6: color = Color("777872")
		image.set_pixel(index % session.state.width, index / session.state.width, color)
	_terrain_source = image
	_mini_center = _snapped_mini_center()
	_rasterize_terrain()

# Ground-plane projection of the fixed 45-degree yaw / 30-degree elevation camera.
# Its common sqrt(0.5) factor is absorbed by scale; preserve precision until draw.
static func project_ground(delta: Vector2) -> Vector2:
	return Vector2(delta.x-delta.y, (delta.x+delta.y)*0.5)

static func unproject_ground(delta: Vector2) -> Vector2:
	return Vector2(delta.x*0.5+delta.y, delta.y-delta.x*0.5)

func _scale() -> float:
	return float(zoom)*map_rect.size.x/float(session.state.width+session.state.height) if expanded else 1.5

func _center() -> Vector2:
	return map_center if expanded else _mini_center

func _snapped_mini_center() -> Vector2:
	return unproject_ground((project_ground(session.position/4.0)*1.5).round()/1.5)*4.0

func point_exact(logic: Vector2) -> Vector2:
	return map_rect.get_center()+project_ground((logic-_center())/4.0)*_scale()

func point(logic: Vector2) -> Vector2:
	return point_exact(logic).round()

func logic_at(pixel: Vector2) -> Vector2:
	return _center()+unproject_ground((pixel-map_rect.get_center())/_scale())*4.0

func _world_contains(logic: Vector2) -> bool:
	return Rect2(Vector2.ZERO,Vector2(session.state.width,session.state.height)*4.0).has_point(logic)

func _rasterize_terrain() -> void:
	if _terrain_source == null: return
	var extent: Vector2i = Vector2i(map_rect.size)
	var image: Image = Image.create(extent.x,extent.y,false,Image.FORMAT_RGBA8)
	for py: int in extent.y:
		for px: int in extent.x:
			var pixel: Vector2 = Vector2(px,py)+Vector2(0.5,0.5)
			if not expanded and pixel.distance_squared_to(map_rect.size*0.5)>54.0*54.0: continue
			var cell: Vector2i = Vector2i((logic_at(map_rect.position+pixel)/4.0).floor())
			var color: Color = Color("0d1517") # World exterior, distinct from undiscovered land.
			if session.state.in_bounds(cell.x,cell.y): color = _terrain_source.get_pixelv(cell)
			image.set_pixel(px,py,color)
	if terrain_texture != null and terrain_texture.get_size() == Vector2(extent):
		terrain_texture.update(image)
	else:
		terrain_texture = ImageTexture.create_from_image(image)

func disclosed(logic: Vector2) -> bool:
	return session.detected(logic)

func icon_style(category: String, item: Dictionary) -> Dictionary:
	if float(item.get("hp",1.0)) <= 0.0: return {}
	if category in ["plants","helpers"]:
		return {"shape":"square" if category == "plants" else "dot","color":WorldView.color_for(String(item.get("kind","")))}
	var live: bool = disclosed(item.pos)
	if category == "enemies":
		return {"shape":"dot","color":Color("e87e77")} if live else {}
	if category == "nests":
		if bool(item.get("mother",false)):
			return {"shape":"mother","color":Color("e87e77")} if live else {}
		if not live and not bool(item.get("discovered",false)): return {}
		return {"shape":"square","color":Color("dc7d65") if live else Color("82675e")}
	if category == "fossils":
		if bool(item.get("found",false)) or int(item.get("nest_id",-1)) >= 0: return {}
		return {"shape":"fossil","color":Color("efd99b")} if live or bool(item.get("discovered",false)) else {}
	return {}

func _draw_icon(at: Vector2, radius: float, style: Dictionary) -> void:
	var color: Color = style.color
	match String(style.shape):
		"square": draw_rect(Rect2(at-Vector2.ONE*radius,Vector2.ONE*radius*2),color)
		"mother":
			var size_: float = radius+1.0
			draw_colored_polygon(PackedVector2Array([at+Vector2(0,-size_),at+Vector2(size_,0),at+Vector2(0,size_),at+Vector2(-size_,0)]),color)
		"fossil":
			# The same tiny bone shape in both maps; it reveals no plant name.
			draw_rect(Rect2(at+Vector2(-radius,-1),Vector2(radius*2+1,2)),color)
			draw_rect(Rect2(at+Vector2(-radius,-radius),Vector2(2,radius*2+1)),color)
			draw_rect(Rect2(at+Vector2(radius-1,-radius),Vector2(2,radius*2+1)),color)
		_: draw_circle(at,radius,color)

func _draw() -> void:
	if session == null: return
	if expanded:
		draw_rect(Rect2(0,0,640,360), Color(0.04,0.07,0.07,0.96))
	if expanded:
		draw_rect(map_rect.grow(2), Color("a0ad93"))
		if terrain_texture != null: draw_texture_rect(terrain_texture,map_rect,false)
	else:
		draw_circle(map_rect.get_center(),55,Color("a0ad93"))
		if terrain_texture != null: draw_texture_rect(terrain_texture,map_rect,false)
	_icon_points.clear()
	for category: String in ["nests","enemies","fossils","plants","helpers"]:
		for item: Dictionary in session.get(category):
			var style: Dictionary = icon_style(category,item)
			if style.is_empty(): continue
			var at: Vector2 = point(item.pos)
			var radius: float = 3.0 if expanded else 2.0
			var margin: float = radius+1.0 if style.shape in ["mother","fossil"] else radius
			if not expanded and at.distance_to(map_rect.get_center())>50: continue
			if expanded and not map_rect.grow(-margin).has_point(at): continue
			_draw_icon(at,radius,style)
			if category in ["plants","helpers"]:
				if expanded:
					_icon_points.append({"pos":at,"id":int(item.id),"helper":category=="helpers","item":item})
					if int(item.id)==selected_id and (category=="helpers")==selected_helper:
						_ring(at,7,Color("ffffff"))
						if selected_helper:
							_map_line(at,point(item.home),Color("cadbbd"))
							var activity: float = 60.0 if String(item.kind)=="gatlinger" else 40.0
							for segment: int in 32:
								var start: Vector2 = item.home+Vector2.from_angle(float(segment)/32.0*TAU)*activity
								var finish: Vector2 = item.home+Vector2.from_angle(float(segment+1)/32.0*TAU)*activity
								_map_line(point(start),point(finish),Color(0.7,0.85,0.65,0.4))
					var gauge_y: float = 5.0
					gauge_y = _gauge(at,gauge_y,float(item.hp),float(item.max_hp),Color("89d579"))
					if category=="helpers" and String(item.kind)=="gatlinger":
						_gauge(at,gauge_y,float(item.ammo),float(item.capacity),Color("e6cf7a"))
					elif category=="helpers" and String(item.kind)=="sprinkler":
						_gauge(at,gauge_y,float(item.water),float(item.capacity),Color("75c8dc"))
					if String(item.get("status","")) in ["empty","no_water","blocked","stranded","waiting_water","no_water_route","unreachable"]:
						if map_rect.grow(-2).has_point(at+Vector2(5,-5)): draw_circle(at+Vector2(5,-5),2,Color("f4bb5e"))
	var player: Vector2 = point(session.position)
	if map_rect.grow(-3).has_point(player): draw_circle(player,3 if expanded else 2,Color("fff9dd"))

func _ring(at: Vector2, radius: float, color: Color) -> void:
	for segment: int in 24:
		_map_line(at+Vector2.from_angle(float(segment)/24.0*TAU)*radius,at+Vector2.from_angle(float(segment+1)/24.0*TAU)*radius,color)

func _map_line(start: Vector2, finish: Vector2, color: Color) -> void:
	# Clip before integer raster drawing; activity/home can be outside the zoomed viewport.
	var delta: Vector2 = finish-start
	var low: float = 0.0
	var high: float = 1.0
	var bounds: Rect2 = map_rect.grow(-1)
	for axis: int in 2:
		if absf(delta[axis])<0.00001:
			if start[axis]<bounds.position[axis] or start[axis]>bounds.end[axis]: return
		else:
			var first: float = (bounds.position[axis]-start[axis])/delta[axis]
			var last: float = (bounds.end[axis]-start[axis])/delta[axis]
			low=maxf(low,minf(first,last))
			high=minf(high,maxf(first,last))
			if low>high: return
	draw_line((start+delta*low).round(),(start+delta*high).round(),color,1,false)

func _map_rect(rectangle: Rect2, color: Color) -> void:
	var clipped: Rect2 = rectangle.intersection(map_rect)
	if clipped.has_area(): draw_rect(clipped,color)

func _gauge(at: Vector2, y: float, value: float, maximum: float, color: Color) -> float:
	if maximum<=0 or value>=maximum-0.001: return y
	_map_rect(Rect2(at+Vector2(-5,y),Vector2(10,2)),Color("28302a"))
	_map_rect(Rect2(at+Vector2(-5,y),Vector2(roundf(10*clampf(value/maximum,0,1)),2)),color)
	return y+3

func selected() -> Dictionary:
	if selected_id<0: return {}
	for item: Dictionary in (session.helpers if selected_helper else session.plants):
		if int(item.id)==selected_id and float(item.hp)>0: return item
	return {}

func update_buttons() -> void:
	var item: Dictionary = selected() if session != null else {}
	var show_buttons: bool = expanded and not item.is_empty() and not popup.visible
	if show_buttons: show_buttons = map_rect.grow(-3).has_point(point(item.pos))
	remove_button.visible = show_buttons
	supply_button.visible = show_buttons and selected_helper and String(item.get("kind",""))=="gatlinger"
	if not show_buttons: return
	var at: Vector2 = point(item.pos)
	remove_button.position = (at+Vector2(-24,-30)).clamp(Vector2(4,4),Vector2(612,332))
	supply_button.position = (at+Vector2(2,-30)).clamp(Vector2(4,4),Vector2(612,332))

func handle_click(event: InputEventMouseButton) -> bool:
	if not expanded:
		if event.position.distance_to(map_rect.get_center())<=54.0 and event.pressed and event.button_index==MOUSE_BUTTON_LEFT:
			set_expanded(true)
			return true
		return false
	if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN] and map_rect.has_point(event.position) and _world_contains(logic_at(event.position)) and not popup.visible:
		var anchor: Vector2=logic_at(event.position)
		zoom=clampi(zoom*2 if event.button_index==MOUSE_BUTTON_WHEEL_UP else zoom/2,1,4)
		# Preserve cursor anchor exactly; no clamping in ground axes after rotation.
		map_center=anchor-unproject_ground((event.position-map_rect.get_center())/_scale())*4.0
		if zoom==1: map_center=Vector2(session.state.width,session.state.height)*2.0
		refresh_terrain()
		update_buttons()
		queue_redraw()
		return true
	if event.button_index==MOUSE_BUTTON_RIGHT and event.pressed:
		deselect()
		return true
	if event.button_index!=MOUSE_BUTTON_LEFT or not event.pressed: return true
	# Popup and command controls own their clicks; they can NEVER become a movement command.
	if popup.visible or (remove_button.visible and remove_button.get_global_rect().has_point(event.position)) or (supply_button.visible and supply_button.get_global_rect().has_point(event.position)): return true
	if not map_rect.has_point(event.position):
		deselect()
		return true
	var closest: Dictionary = {}
	var best: float = 8.0
	for entry: Dictionary in _icon_points:
		var distance: float = event.position.distance_to(entry.pos)
		if distance<best:
			best=distance
			closest=entry
	if not closest.is_empty():
		selected_id=closest.id
		selected_helper=closest.helper
	elif not _world_contains(logic_at(event.position)):
		# A rounded edge icon can lie just outside the inverse-projected world.
		# Honour its visible hit target first, but never issue an exterior order.
		deselect()
	elif selected_helper and selected_id>=0:
		var result: Dictionary = session.move_helper(selected_id,logic_at(event.position))
		if not bool(result.get("ok",false)): notified.emit(String(result.get("reason","移動できません")))
		else: notified.emit("活動場所を変更しました")
	else: deselect()
	update_buttons()
	queue_redraw()
	return true

func open_popup(action: String) -> void:
	var item: Dictionary = selected()
	if item.is_empty(): return
	for child: Node in popup.get_children(): child.free()
	_popup_action=action
	var box: VBoxContainer = VBoxContainer.new()
	popup.add_child(box)
	var label: Label = Label.new()
	box.add_child(label)
	if action=="remove":
		label.text="撤去：種 %d 回収" % session.removal_refund(selected_id,selected_helper)
	else:
		label.text="種 %d / %d　備蓄 %d" % [item.ammo,item.capacity,session.seeds]
		quantity=SpinBox.new()
		quantity.min_value=0
		quantity.max_value=mini(int(item.capacity)-int(item.ammo),session.seeds)
		quantity.step=1
		quantity.value=quantity.max_value
		box.add_child(quantity)
	var buttons: HBoxContainer = HBoxContainer.new()
	box.add_child(buttons)
	for text: String in ["確定","戻る"]:
		var button: Button = Button.new()
		button.text=text
		buttons.add_child(button)
		if text=="確定": button.pressed.connect(confirm_popup)
		else: button.pressed.connect(func() -> void: popup.hide(); update_buttons())
	popup.position=(point(item.pos)+Vector2(8,-40)).clamp(Vector2(8,8),Vector2(410,250))
	popup.show()
	update_buttons()

func confirm_popup() -> void:
	var result: Dictionary
	if _popup_action=="supply": result=session.supply_helper(selected_id,int(quantity.value))
	elif selected_helper: result=session.remove_helper(selected_id)
	else: result=session.remove_plant(selected_id)
	if bool(result.get("ok",false)):
		if _popup_action=="remove": selected_id=-1
	else: notified.emit(String(result.get("reason","操作できません")))
	popup.hide()
	update_buttons()
	queue_redraw()
