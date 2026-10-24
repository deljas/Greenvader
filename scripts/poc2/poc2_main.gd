extends Node
## Independent PoC2 entry. No OS input automation; all game commands go to the session.
const Session: GDScript=preload("res://scripts/poc2/poc2_session.gd")
const View: GDScript=preload("res://scripts/poc2/view/world_view.gd")
const Ui: GDScript=preload("res://scripts/poc2/ui/poc2_ui.gd")
const Save: GDScript=preload("res://scripts/poc2/save/poc2_save.gd")
const Coords: GDScript=preload("res://scripts/poc/poc_coords.gd")
var session: RefCounted
var render_view: SubViewport
var view_rect: TextureRect
var world: Node3D
var ui: Control
var auto_process: bool=true
var save_dir: String=Save.DEFAULT_DIR
var cursor: Vector2=Vector2(320,180)
var cursor_known: bool=false
var menu: String=""
var _help_return: String=""
var _keys: Dictionary={}
var _primary: bool=false
var _secondary: bool=false
var _shot_wait: float=0.0
var _water_wait: float=0.0
var _last_autosave: float=0.0
var _message_serial: int=0
var _placement_kind: String=""
var muted: bool=false
var _tone: AudioStreamPlayer

func _ready() -> void:
	get_window().title="グリーンベーダー｜PoC 第二弾"
	get_window().content_scale_mode=Window.CONTENT_SCALE_MODE_VIEWPORT
	get_window().content_scale_aspect=Window.CONTENT_SCALE_ASPECT_KEEP
	get_window().content_scale_stretch=Window.CONTENT_SCALE_STRETCH_INTEGER
	get_window().content_scale_size=Vector2i(640,360)
	get_window().min_size=Vector2i(640,360)
	render_view=SubViewport.new()
	render_view.size=Vector2i(640,360)
	render_view.own_world_3d=true
	render_view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	render_view.msaa_3d=Viewport.MSAA_DISABLED
	render_view.screen_space_aa=Viewport.SCREEN_SPACE_AA_DISABLED
	render_view.use_taa=false
	render_view.use_debanding=false
	add_child(render_view)
	view_rect=TextureRect.new()
	view_rect.texture=render_view.get_texture()
	view_rect.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	view_rect.size=Vector2(640,360)
	view_rect.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(view_rect)
	ui=Ui.new()
	add_child(ui)
	ui.chosen.connect(_on_action)
	ui.placement.connect(func(kind: String) -> void: _placement_kind=kind)
	ui.map.toggled.connect(_map_toggled)
	_tone=AudioStreamPlayer.new()
	add_child(_tone)
	replace_session(Session.new())
	if get_tree().current_scene==self and not OS.get_cmdline_user_args().has("--no-title"):
		menu="title"
		ui.show_menu(true)
	_sync_pause()

func replace_session(candidate: RefCounted) -> void:
	_primary=false
	_secondary=false
	_keys.clear()
	if world!=null:
		render_view.remove_child(world)
		world.free()
	if session!=null and session!=candidate: session.close()
	session=candidate
	world=View.new()
	render_view.add_child(world)
	world.build(session,render_view)
	ui.bind(session)
	_placement_kind=""
	ui.selected_kind=""
	_last_autosave=session.clock.elapsed
	_message_serial=session.message_serial
	_sync_pause()

func is_paused() -> bool:
	return menu!="" or ui.map.expanded

func _sync_pause() -> void:
	if session!=null: session.paused=is_paused()

func _map_toggled(_open: bool) -> void:
	_primary=false
	_secondary=false
	_sync_pause()

func _process(delta: float) -> void:
	if auto_process: tick(delta)

func tick(delta: float) -> void:
	if session==null: return
	_sync_pause()
	if not is_paused():
		var movement: Vector2=Vector2(_axis(KEY_D,KEY_A,KEY_RIGHT,KEY_LEFT),_axis(KEY_S,KEY_W,KEY_DOWN,KEY_UP))
		session.walk(movement.limit_length(1.0),delta)
		if cursor_known: session.set_aim(world.pick(cursor))
		_shot_wait=maxf(_shot_wait-delta,0.0)
		_water_wait=maxf(_water_wait-delta,0.0)
		if cursor_known and not ui.blocks(cursor):
			if _primary and _placement_kind=="" and _shot_wait<=0.0: _fire()
			if _secondary and _water_wait<=0.0: _water()
		session.advance(delta)
		if session.clock.elapsed-_last_autosave>=60.0:
			_last_autosave=session.clock.elapsed
			var saved: Dictionary=Save.save_game(session,save_dir)
			if not bool(saved.get("ok",false)): ui.show_notice(String(saved.reason))
	if session.message_serial!=_message_serial:
		_message_serial=session.message_serial
		ui.show_notice(String(session.last_message))
	world.sync(delta)
	if cursor_known and _placement_kind!="" and not is_paused():
		var cell: Vector2i=Coords.logic_to_cell(world.pick(cursor))
		var check: Dictionary=session.can_place(_placement_kind,cell)
		var footprint: Array=session.CATALOG[_placement_kind].get("size",[1,1])
		world.set_preview(_placement_kind,cell,bool(check.get("ok",false)),Vector2i(int(footprint[0]),int(footprint[1])))
	else:
		world.marker.visible=false

func _axis(positive: int, negative: int, positive_alt: int, negative_alt: int) -> float:
	return float(bool(_keys.get(positive,false)) or bool(_keys.get(positive_alt,false)))-float(bool(_keys.get(negative,false)) or bool(_keys.get(negative_alt,false)))

func _input(event: InputEvent) -> void:
	if event is InputEventMouse:
		cursor=event.position
		cursor_known=true
	if event is InputEventKey:
		var key: int=event.physical_keycode if event.physical_keycode!=0 else event.keycode
		_keys[key]=event.pressed
	if event is InputEventMouseButton:
		if event.button_index==MOUSE_BUTTON_LEFT: _primary=event.pressed
		elif event.button_index==MOUSE_BUTTON_RIGHT: _secondary=event.pressed

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key: int=event.physical_keycode if event.physical_keycode!=0 else event.keycode
		if key==KEY_M and menu=="":
			ui.map.set_expanded(not ui.map.expanded)
		elif key==KEY_ESCAPE:
			_escape()
		elif key==KEY_F1:
			_on_action("close_help" if menu=="help" else "help")
		elif key==KEY_F5:
			save_game()
		elif key==KEY_N:
			muted=not muted
			ui.show_notice("音：消す" if muted else "音：出す")
		elif not is_paused():
			if key==KEY_Q: _result(session.skill(0),"bump")
			elif key==KEY_R: _result(session.skill(1),"bazooka")
			elif key==KEY_TAB: _cycle_palette()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		if menu!="": return
		if ui.map.handle_click(event):
			get_viewport().set_input_as_handled()
			return
		if ui.blocks(event.position): return
		if event.pressed:
			session.set_aim(world.pick(event.position))
			if event.button_index==MOUSE_BUTTON_LEFT:
				if _placement_kind!="": _place(Coords.logic_to_cell(world.pick(event.position)))
				else: _fire()
			elif event.button_index==MOUSE_BUTTON_RIGHT:
				if _placement_kind!="": ui.select_kind(_placement_kind)
				else: _water()

func _fire() -> void:
	_shot_wait=0.3
	var result: Dictionary=session.fire()
	_result(result,"seed")
	if bool(result.get("ok",false)): world.show_fire(&"seed")

func _water() -> void:
	_water_wait=0.3
	var result: Dictionary=session.water_at(world.pick(cursor))
	_result(result,"water")
	if bool(result.get("ok",false)): world.show_fire(&"water")

func _place(cell: Vector2i) -> void:
	if _placement_kind=="gatlinger":
		_placement_supply(cell)
		return
	var result: Dictionary=session.place_helper(_placement_kind,cell) if _placement_kind in ["army","sprinkler"] else session.place_plant(_placement_kind,cell)
	_result(result,"place")

func _placement_supply(cell: Vector2i) -> void:
	var check: Dictionary=session.can_place("gatlinger",cell)
	if not bool(check.get("ok",false)):
		_result(check)
		return
	for child: Node in ui.supply.get_children(): child.free()
	var box: VBoxContainer=VBoxContainer.new()
	ui.supply.add_child(box)
	var label: Label=Label.new()
	label.text="設置 種30　投入する種（上限100）"
	box.add_child(label)
	var quantity: SpinBox=SpinBox.new()
	quantity.min_value=0
	quantity.max_value=mini(100,maxi(session.seeds-30,0))
	quantity.step=1
	quantity.value=mini(20,int(quantity.max_value))
	box.add_child(quantity)
	var buttons: HBoxContainer=HBoxContainer.new()
	box.add_child(buttons)
	for text: String in ["設置","戻る"]:
		var button: Button=Button.new()
		button.text=text
		buttons.add_child(button)
		if text=="設置":
			button.pressed.connect(func() -> void:
				_result(session.place_helper("gatlinger",cell,int(quantity.value)),"place")
				ui.supply.hide()
				menu=""
				_sync_pause())
		else:
			button.pressed.connect(func() -> void: ui.supply.hide(); menu=""; _sync_pause())
	ui.supply.position=Vector2(205,140)
	ui.supply.show()
	menu="placement_supply"
	_primary=false
	_sync_pause()

func _cycle_palette() -> void:
	var keys: Array=ui.KEYS
	var index: int=keys.find(_placement_kind)
	for offset: int in keys.size():
		var next: String=keys[posmod(index+1+offset,keys.size())]
		if bool(session.unlocked.get(next,false)):
			if _placement_kind!="": ui.select_kind(_placement_kind)
			ui.select_kind(next)
			return

func _escape() -> void:
	if menu=="help": _on_action("close_help")
	elif menu=="placement_supply": ui.supply.hide(); menu=""; _sync_pause()
	elif menu!="": _on_action("resume")
	elif ui.map.expanded:
		if ui.map.selected_id>=0 or ui.map.popup.visible: ui.map.deselect()
		else: ui.map.set_expanded(false)
	elif _placement_kind!="": ui.select_kind(_placement_kind)
	else:
		menu="pause"
		ui.show_menu()
		_sync_pause()

func _on_action(action: String) -> void:
	_primary=false
	_secondary=false
	match action:
		"new":
			replace_session(Session.new())
			menu=""
			ui.menu.hide()
			ui.help.hide()
			ui.map.set_expanded(false)
		"resume":
			menu=""
			ui.menu.hide()
		"save": save_game()
		"load":
			var result: Dictionary=Save.load_game(save_dir)
			if bool(result.get("ok",false)):
				replace_session(result.session)
				menu=""
				ui.menu.hide()
				ui.map.set_expanded(false)
			ui.show_notice(String(result.reason))
		"help":
			if menu=="help": return
			_help_return=menu
			menu="help"
			ui.help.show()
			ui.menu.hide()
			ui.supply.hide()
		"close_help":
			menu=_help_return
			_help_return=""
			ui.help.hide()
			if menu in ["title","pause"]: ui.show_menu(menu=="title")
			elif menu=="placement_supply": ui.supply.show()
	_sync_pause()

func save_game() -> Dictionary:
	# Help is a temporary overlay; it must not grant save access to the unplayed title session.
	if menu=="title" or (menu=="help" and _help_return=="title"):
		return {"ok":false,"reason":"ゲーム開始後に保存できます"}
	var result: Dictionary=Save.save_game(session,save_dir)
	ui.show_notice(String(result.reason))
	return result

func _result(result: Dictionary, sound: String="") -> void:
	if not bool(result.get("ok",false)):
		ui.show_notice(String(result.get("reason","操作できません")))
	elif not sound.is_empty(): _play_tone(sound)

func _play_tone(kind: String) -> void:
	if muted: return
	var stream: AudioStreamWAV=AudioStreamWAV.new()
	stream.format=AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate=22050
	var samples: PackedByteArray=PackedByteArray()
	samples.resize(2205*2)
	var frequency: float={"seed":560.0,"water":330.0,"place":720.0,"bump":150.0,"bazooka":95.0}.get(kind,440.0)
	for index: int in 2205:
		var value: int=int(sin(float(index)/22050.0*frequency*TAU)*(1.0-float(index)/2205.0)*2200)
		samples.encode_s16(index*2,value)
	stream.data=samples
	_tone.stream=stream
	_tone.play()

func _notification(what: int) -> void:
	if what==NOTIFICATION_APPLICATION_FOCUS_OUT:
		_keys.clear()
		_primary=false
		_secondary=false


