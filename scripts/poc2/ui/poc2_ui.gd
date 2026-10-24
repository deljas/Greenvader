extends Control
const Map: GDScript = preload("res://scripts/poc2/ui/map_ui.gd")
const PlantList: GDScript = preload("res://scripts/poc2/ui/plant_list.gd")
const FavoriteSlot: GDScript = preload("res://scripts/poc2/ui/favorite_slot.gd")
signal chosen(action: String)
signal placement(kind: String)
signal audio_changed(is_muted: bool, volume: float)
var session: RefCounted
var map: Control
var status: Label
var economy: Label
var rate_label: Label
var _helper_hint_shown: bool = false
var hud: PanelContainer
var hp_bar: ProgressBar
var water_bar: ProgressBar
var map_button: Button
var help_button: Button
var notice: Label
var sow_notice: Label
var water_notice: Label
var water_plan_empty: bool = true
var palette: HBoxContainer
var menu: PanelContainer
var help: PanelContainer
var supply: PanelContainer
var plant_list: PanelContainer
var selected_kind: String = ""
var selected_slot: int = -1
var audio_muted: bool = false
var audio_volume: float = 1.0
var mute_button: CheckButton
var volume_slider: HSlider
var notice_time: float = 0.0
var favorite_buttons: Array[Button] = []
const KEYS: Array[String] = ["clover","carrot","wheat","rafflesia","watermelon","army","gatlinger","sprinkler"]
const SYMBOLS: Array[String] = ["♣","●","♜","✿","◆","⚑","➤","≋"]
const RANKS: Dictionary = {"clover":1,"carrot":2,"army":2,"wheat":3,"gatlinger":3,"sprinkler":3,"rafflesia":4,"watermelon":5}
const DESCRIPTIONS: Dictionary = {"clover":"小さな土地で種を生産します。","carrot":"近くにいる主人公の回復を助けます。","wheat":"種を多く生産します。近くの動物を引き寄せます。","rafflesia":"近くの動物を遠ざけ、虫を引き寄せます。","watermelon":"広い土地を使って種を生産します。","army":"前線で敵と戦います。","gatlinger":"投入した種で射撃と播種を行います。","sprinkler":"水を補給して周囲へ給水します。"}

func _ready() -> void:
	size=Vector2(640,360)
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	var theme_: Theme=Theme.new()
	theme_.default_font_size=12
	theme=theme_
	hud=PanelContainer.new()
	hud.position=Vector2(456,6)
	hud.custom_minimum_size=Vector2(178,84)
	add_child(hud)
	var hud_box: VBoxContainer=VBoxContainer.new()
	hud_box.add_theme_constant_override("separation",1)
	hud.add_child(hud_box)
	status=Label.new()
	status.add_theme_font_size_override("font_size",12)
	hud_box.add_child(status)
	economy=Label.new()
	economy.add_theme_font_size_override("font_size",12)
	hud_box.add_child(economy)
	rate_label=Label.new()
	rate_label.add_theme_font_size_override("font_size",12)
	hud_box.add_child(rate_label)
	hp_bar=_status_bar(hud_box,"HP")
	water_bar=_status_bar(hud_box,"水")
	notice=Label.new()
	notice.position=Vector2(8,308)
	notice.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(notice)
	sow_notice=Label.new()
	sow_notice.position=Vector2(23,284)
	sow_notice.mouse_filter=Control.MOUSE_FILTER_IGNORE
	sow_notice.hide()
	add_child(sow_notice)
	water_notice=Label.new()
	water_notice.position=Vector2(23,266)
	water_notice.mouse_filter=Control.MOUSE_FILTER_IGNORE
	water_notice.hide()
	add_child(water_notice)
	palette=HBoxContainer.new()
	palette.position=Vector2(6,330)
	palette.add_theme_constant_override("separation",3)
	add_child(palette)
	for index: int in 5:
		var button: Button=FavoriteSlot.new()
		palette.add_child(button)
		button.set_slot(index,"","","")
		favorite_buttons.append(button)
		button.pressed.connect(func() -> void: select_slot(button.slot_index))
	var list_button: Button=Button.new()
	list_button.text="E 一覧"
	list_button.focus_mode=Control.FOCUS_NONE
	list_button.pressed.connect(func() -> void: chosen.emit("plants"))
	palette.add_child(list_button)
	map_button=Button.new()
	map_button.text="Tab"
	map_button.tooltip_text="全体マップ（時間停止）"
	map_button.position=Vector2(6,116)
	map_button.size=Vector2(34,24)
	map_button.pressed.connect(func() -> void:
		if not has_modal(): map.set_expanded(not map.expanded))
	add_child(map_button)
	help_button=Button.new()
	help_button.text="?"
	help_button.position=Vector2(604,330)
	help_button.size=Vector2(30,24)
	help_button.pressed.connect(func() -> void:
		if not has_modal(): chosen.emit("help"))
	add_child(help_button)
	map=Map.new()
	add_child(map)
	map.notified.connect(show_notice)
	menu=PanelContainer.new()
	menu.position=Vector2(220,90)
	menu.size=Vector2(200,180)
	add_child(menu)
	menu.hide()
	help=PanelContainer.new()
	help.position=Vector2(75,45)
	help.size=Vector2(490,270)
	add_child(help)
	var help_box: VBoxContainer=VBoxContainer.new()
	help.add_child(help_box)
	var label: Label=Label.new()
	label.text="WASD / 矢印：移動　マウス：照準・配置位置\n左クリック / 長押し：種射撃・範囲播種\n右クリック / 長押し：給水（水が効くマスだけ）\nShift＋左 / 右クリック：スキル1 / 2（1回）\nホイール：範囲 1/3/5/7（播種・給水共通）\n色：緑＝播種予定、黄＝種不足、青＝給水予定、薄紫＝水不足\n1〜5 / 左下5枠：植物選択・解除　左で1株設置\nE：植物一覧・登録　Tab / ミニマップ：全体マップ\n一覧・マップ中は停止。ホイールはスクロール / ズーム\n右クリック / Esc：保持・選択を取消、Escで戻る\nF5：保存　F1：説明　Esc：メニュー（音量・ミュート）\n水辺補給・化石への接近回収は自動です。\nおたすけ植物の配置換え：Tabのマップでアイコンを選び、移動先を左クリック\nマップ拡大中は左ドラッグで移動できます。"
	label.add_theme_font_size_override("font_size",12)
	help_box.add_child(label)
	var back: Button=Button.new()
	back.text="閉じる"
	back.pressed.connect(func() -> void: chosen.emit("close_help"))
	help_box.add_child(back)
	help.hide()
	supply=PanelContainer.new()
	add_child(supply)
	supply.hide()
	plant_list=PlantList.new()
	add_child(plant_list)
	plant_list.closed.connect(func() -> void: chosen.emit("close_plants"))
	plant_list.assignment_requested.connect(_assign_favorite)

func _status_bar(box: VBoxContainer, caption: String) -> ProgressBar:
	var line: HBoxContainer=HBoxContainer.new()
	box.add_child(line)
	var label: Label=Label.new()
	label.text=caption
	label.custom_minimum_size.x=22
	label.add_theme_font_size_override("font_size",11)
	line.add_child(label)
	var bar: ProgressBar=ProgressBar.new()
	bar.custom_minimum_size=Vector2(138,10)
	bar.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	bar.show_percentage=false
	line.add_child(bar)
	return bar

func set_sow_preview(plan: Dictionary) -> void:
	sow_notice.visible=not plan.is_empty()
	if sow_notice.visible:
		if plan.get("attack",false):
			sow_notice.text="%d　攻撃%s" % [plan.cost,"（種不足）" if plan.cost==0 else ""]
		else:
			sow_notice.text="%d　播種 %d×%d%s" % [plan.cost,plan.width,plan.width,"（遮蔽）" if plan.get("blocked",false) else ""]
	queue_redraw()

## Water plan next to the seed plan: how much water the aimed area will use, or why nothing happens.
func set_water_preview(plan: Dictionary) -> void:
	water_notice.visible=not plan.is_empty()
	if water_notice.visible:
		if plan.get("blocked",false): water_notice.text="0　給水（遮蔽）"
		elif plan.get("no_effect",false): water_notice.text="0　給水対象なし"
		else: water_notice.text="%d　給水 %d×%d%s" % [plan.cost,plan.width,plan.width,"（水不足）" if not (plan.unaffordable as Array).is_empty() else ""]
	water_plan_empty=plan.is_empty() or plan.get("blocked",false) or plan.get("no_effect",false)
	queue_redraw()

func _draw() -> void:
	if water_notice!=null and water_notice.visible:
		# Small solid drop silhouette, integer coordinates, no outline or filtering.
		draw_colored_polygon(PackedVector2Array([Vector2(14,265),Vector2(18,271),Vector2(17,275),Vector2(11,275),Vector2(10,271)]),Color("8c9a9f") if water_plan_empty else Color("62bff0"))
	if sow_notice!=null and sow_notice.visible:
		# Small solid seed silhouette, integer coordinates, no outline or filtering.
		draw_colored_polygon(PackedVector2Array([Vector2(10,291),Vector2(13,288),Vector2(17,288),Vector2(19,291),Vector2(16,295),Vector2(12,294)]),Color("edce7d"))

func bind(source: RefCounted) -> void:
	session=source
	selected_slot=-1
	selected_kind=""
	plant_list.hide()
	plant_list.cancel_registration()
	map.bind(source)
	refresh()

func select_kind(kind: String) -> void:
	# Retain the entry point for existing cancel paths, using slot identity for actual selection.
	if kind==selected_kind:
		clear_selection()
		return
	for index: int in 5:
		if session.favorites[index]==kind:
			select_slot(index)
			return

## One-time guidance after the first helper placement: moving a helper happens on the all-map.
func note_helper_placed() -> void:
	if _helper_hint_shown: return
	_helper_hint_shown=true
	show_notice("おたすけ植物はTabのマップで選び、移動先を左クリックすると配置換えできます")
	notice_time=7.0

func clear_selection() -> void:
	selected_slot=-1
	selected_kind=""
	placement.emit(selected_kind)
	refresh()

func select_slot(index: int) -> void:
	if session==null or index<0 or index>=5 or plant_list.visible: return
	var kind: String=session.favorites[index]
	if index==selected_slot or kind.is_empty() or not bool(session.unlocked.get(kind,false)):
		clear_selection()
		return
	selected_slot=index
	selected_kind=kind
	placement.emit(kind)
	refresh()

func icon_for(kind: String) -> String:
	var index: int=KEYS.find(kind)
	return SYMBOLS[index] if index>=0 else ""

func _icons() -> Dictionary:
	var out: Dictionary={}
	for kind: String in KEYS: out[kind]=icon_for(kind)
	return out

func list_rows() -> Array[Dictionary]:
	var kinds: Array[String]=[]
	for kind: String in KEYS:
		if bool(session.unlocked.get(kind,false)): kinds.append(kind)
	kinds.sort_custom(func(a: String,b: String) -> bool: return int(RANKS[a])<int(RANKS[b]) if RANKS[a]!=RANKS[b] else KEYS.find(a)<KEYS.find(b))
	var rows: Array[Dictionary]=[]
	for kind: String in kinds:
		var stats: Dictionary=session.plant_stats(kind)
		var definition: Dictionary=session.CATALOG[kind]
		rows.append({"kind":kind,"icon":icon_for(kind),"name":String(Map.NAMES[kind]),"description":String(DESCRIPTIONS[kind]),"count":int(stats.count),"rate":float(stats.rate_per_second),"cost":session.current_cost(kind),"mature_rate":float(definition.rate)/60.0,"produces":float(definition.rate)>0.0})
	return rows

func show_plant_list() -> void:
	plant_list.set_rows(list_rows())
	plant_list.set_favorites(session.favorites,_icons(),Map.NAMES)
	plant_list.open_list()
	refresh()

func _assign_favorite(index: int, kind: String) -> void:
	var result: Dictionary=session.set_favorite(index,kind)
	if not bool(result.get("ok",false)): show_notice(String(result.reason))
	elif index==selected_slot: clear_selection()
	refresh()

func has_modal() -> bool:
	return menu.visible or help.visible or supply.visible or plant_list.visible

func refresh() -> void:
	if session==null: return
	var stats: Dictionary=session.snapshot()
	status.text="%s 設置 ●%d%s" % [icon_for(selected_kind),session.current_cost(selected_kind),"（種不足）" if session.current_cost(selected_kind)>session.seeds else ""] if not selected_kind.is_empty() else "範囲 %d×%d（播種・給水）" % [session.sow_width,session.sow_width]
	status.tooltip_text="ホイールで範囲を変更。新しく播種するマス・水が効くマスだけ種・水を使います。" if selected_kind.is_empty() else ""
	economy.text="所持 ●%d　緑 %.1f%%" % [session.seeds,float(stats.get("green_percent",0))]
	economy.tooltip_text="収入 / 分：緑地 %.1f ＋ 栽培 %.1f" % [float(stats.get("land_rate",0)),float(stats.get("crop_rate",0))]
	# The same land+crop rates the session credits every tick (per minute), shown per second.
	var per_second: float=(float(stats.get("land_rate",0))+float(stats.get("crop_rate",0)))/60.0
	rate_label.text="生産 +%s ●/s" % (("%.1f" % per_second) if per_second>=100.0 else ("%.2f" % per_second))
	rate_label.tooltip_text="全体の種の生産速度（緑地 %.2f ＋ 栽培 %.2f ●/s）" % [float(stats.get("land_rate",0))/60.0,float(stats.get("crop_rate",0))/60.0]
	hp_bar.max_value=session.max_hp
	hp_bar.value=session.hp
	water_bar.max_value=session.max_water
	water_bar.value=session.water
	for index: int in 5:
		var kind: String=session.favorites[index]
		var price: int=session.current_cost(kind) if not kind.is_empty() else -1
		favorite_buttons[index].set_slot(index,kind,icon_for(kind),String(Map.NAMES.get(kind,"")),selected_slot==index,price,price<=session.seeds)
	palette.visible=not map.expanded and not menu.visible and not help.visible and not plant_list.visible and not supply.visible
	hud.visible=not menu.visible and not help.visible and not plant_list.visible
	map_button.visible=not has_modal()
	help_button.visible=not has_modal() and not map.expanded
	if plant_list.visible:
		plant_list.set_rows(list_rows())
		plant_list.set_favorites(session.favorites,_icons(),Map.NAMES)

func _process(delta: float) -> void:
	notice_time=maxf(notice_time-delta,0)
	notice.visible=notice_time>0
	refresh()

func show_notice(text: String) -> void:
	var message: String=explain(text)
	if message.is_empty(): return
	notice.text=message
	notice_time=4.0

func show_menu(title: bool = false) -> void:
	for child: Node in menu.get_children(): child.free()
	menu.position=Vector2(220,90 if title else 30)
	menu.size=Vector2(200,180)
	var box: VBoxContainer=VBoxContainer.new()
	menu.add_child(box)
	var label: Label=Label.new()
	label.text="グリーンベーダー PoC3 作業版" if title else "一時停止"
	box.add_child(label)
	var actions: Array[String]=[]
	actions.assign(["new","load","help"] if title else ["resume","plants","save","load","new","help"])
	for action: String in actions:
		var button: Button=Button.new()
		button.text={"new":"新しく始める","load":"続きから","help":"操作説明","resume":"再開","save":"保存","plants":"植物一覧 E"}[action]
		box.add_child(button)
		button.pressed.connect(func() -> void: chosen.emit(action))
	mute_button=CheckButton.new()
	mute_button.text="ミュート"
	mute_button.button_pressed=audio_muted
	mute_button.focus_mode=Control.FOCUS_NONE
	mute_button.toggled.connect(func(value: bool) -> void:
		audio_muted=value
		audio_changed.emit(audio_muted,audio_volume))
	box.add_child(mute_button)
	var volume_row: HBoxContainer=HBoxContainer.new()
	box.add_child(volume_row)
	var volume_label: Label=Label.new()
	volume_label.text="音量"
	volume_row.add_child(volume_label)
	volume_slider=HSlider.new()
	volume_slider.min_value=0.0
	volume_slider.max_value=1.0
	volume_slider.step=0.05
	volume_slider.value=audio_volume
	volume_slider.custom_minimum_size=Vector2(120,16)
	volume_slider.focus_mode=Control.FOCUS_NONE
	volume_slider.value_changed.connect(func(value: float) -> void:
		audio_volume=value
		audio_changed.emit(audio_muted,audio_volume))
	volume_row.add_child(volume_slider)
	menu.show()
	refresh()

func blocks(pixel: Vector2) -> bool:
	if menu.visible or help.visible or supply.visible or plant_list.visible: return true
	if hud.visible and hud.get_global_rect().has_point(pixel): return true
	if map.expanded or map.map_rect.has_point(pixel): return true
	if palette.visible and palette.get_global_rect().has_point(pixel): return true
	return (pixel.x>598 and pixel.y>326) or (pixel.x<42 and pixel.y>=116 and pixel.y<=144)



static func explain(text: String) -> String:
	var translations: Dictionary = {
		"not_enough_seeds":"種が足りません", "locked":"化石で解放できます", "unexplored":"まだ探索していない場所です",
		"outside_map":"マップの外です", "blocked_ground":"ここには置けません", "occupied":"ほかの植物と重なります",
		"requires_green":"必要な範囲を緑化してください", "out_of_range":"届きません", "no_water":"水がありません",
		"blocked":"建物に遮られています", "aim_required":"狙う場所を指定してください", "not_found":"対象が見つかりません",
		"invalid_amount":"補給量を確認してください", "loaded":"再開しました", "paused_or_downed":"今は行動できません", "no_effect":"給水の効果があるマスがありません"}
	if text in ["cooldown", "cooldown_or_paused"]: return ""
	if text.begins_with("化石を発見: "):
		var kind: String = text.trim_prefix("化石を発見: ")
		return "化石を発見：" + String(Map.NAMES.get(kind,kind))
	return String(translations.get(text,text))



