extends Node3D
## Read-only helper labels, gauges and short action/impact marks. No game mutation.
const Coords: GDScript = preload("res://scripts/poc/poc_coords.gd")
var labels: Dictionary = {}
var pulses: Array[Dictionary] = []
var previous_shots: Dictionary = {}
var ring: MeshInstance3D

func _ready() -> void:
	ring=MeshInstance3D.new()
	var surface: SurfaceTool=SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index: int in 96:
		var a: float=TAU*float(index)/96.0
		var b: float=TAU*float(index+1)/96.0
		var p: Vector3=Vector3(cos(a),0,sin(a))
		var q: Vector3=Vector3(cos(b),0,sin(b))
		for vertex: Vector3 in [p*5.92,p*6.0,q*6.0,p*5.92,q*6.0,q*5.92]: surface.add_vertex(vertex)
	ring.mesh=surface.commit()
	var material: StandardMaterial3D=StandardMaterial3D.new()
	material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color=Color(0.7,0.95,0.65,0.55)
	material.no_depth_test=true # A range guide stays legible over the grass canopy.
	material.cull_mode=BaseMaterial3D.CULL_DISABLED
	ring.material_override=material
	ring.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring); ring.hide()

## radius_scale 1 = the 6m ring (army / gatlinger); the sprinkler ring is 12m (item 11).
func preview(at: Vector2, shown: bool, radius_scale: float = 1.0) -> void:
	ring.visible=shown
	ring.scale=Vector3(radius_scale,1.0,radius_scale)
	var ground: Vector2=Coords.logic_to_ground(at)
	ring.position=Vector3(ground.x,0.045,ground.y)

func _label() -> Label3D:
	var label: Label3D=Label3D.new()
	label.font_size=12; label.outline_size=0
	label.pixel_size=18.5/360.0
	label.billboard=BaseMaterial3D.BILLBOARD_ENABLED
	label.texture_filter=BaseMaterial3D.TEXTURE_FILTER_NEAREST
	label.no_depth_test=true
	label.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(label)
	return label

func _bar() -> Sprite3D:
	var bar: Sprite3D=Sprite3D.new()
	bar.pixel_size=18.5/360.0
	bar.billboard=BaseMaterial3D.BILLBOARD_ENABLED
	bar.texture_filter=BaseMaterial3D.TEXTURE_FILTER_NEAREST
	bar.no_depth_test=true
	bar.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(bar)
	return bar

func _gauge(bar: Sprite3D, value: float, maximum: float, color: Color, at: Vector3) -> bool:
	bar.visible=maximum>0.0 and value<maximum-0.001
	bar.position=at
	if not bar.visible: return false
	var amount: int=clampi(roundi(12.0*value/maximum),0,12)
	if int(bar.get_meta("amount",-1))!=amount:
		var pixels: Image=Image.create(12,2,false,Image.FORMAT_RGBA8)
		pixels.fill(Color("28302a"))
		if amount>0: pixels.fill_rect(Rect2i(0,0,amount,2),color)
		bar.texture=ImageTexture.create_from_image(pixels)
		bar.set_meta("amount",amount)
	return true

static func icon(helper: Dictionary, elapsed: float) -> String:
	var status: String=String(helper.get("status",""))
	if status=="fleeing": return "↶"
	if status in ["refilling","resupplying","returning_water"]: return "水↻"
	if status=="empty": return "種!"
	if status in ["no_water_route","unreachable","blocked"]: return "!"
	if helper.kind!="army" and bool(helper.get("sleeping",false)): return "Zzz"
	if float(helper.get("action_until",-1.0))>elapsed:
		return {"attack":"✧","sow":"• →","water":"· ✧ ·"}.get(String(helper.get("action_kind","")),"")
	return ""

func sync(source: RefCounted, visual_time: float) -> void:
	var alive: Dictionary={}
	for helper: Dictionary in source.helpers:
		if float(helper.hp)<=0.0: continue
		alive[helper.id]=true
		if not labels.has(helper.id): labels[helper.id]={"label":_label(),"bars":[_bar(),_bar(),_bar()]}
		var record: Dictionary=labels[helper.id]
		var label: Label3D=record.label
		var text_: String=icon(helper,source.clock.elapsed)
		label.text=text_; label.visible=not text_.is_empty()
		var at: Vector2=Coords.logic_to_ground(helper.pos)
		label.position=Vector3(at.x,1.15,at.y)
		var height: float=0.83
		if _gauge(record.bars[0],helper.hp,helper.max_hp,Color("89d579"),Vector3(at.x,height,at.y)): height-=0.15
		record.bars[1].hide(); record.bars[2].hide()
		if helper.kind=="gatlinger": _gauge(record.bars[1],helper.ammo,helper.capacity,Color("e6cf7a"),Vector3(at.x,height,at.y))
		if helper.kind=="sprinkler": _gauge(record.bars[2],helper.water,helper.capacity,Color("75c8dc"),Vector3(at.x,height,at.y))
	for id: Variant in labels.keys():
		if not alive.has(id):
			labels[id].label.queue_free()
			for bar: Sprite3D in labels[id].bars: bar.queue_free()
			labels.erase(id)
	var shots: Dictionary={}
	for shot: Dictionary in source.shots:
		if shot.get("source_type","player")=="helper": shots[shot.id]={"pos":shot.pos,"target":shot.target,"remaining":shot.remaining}
	for id: Variant in previous_shots:
		if not shots.has(id):
			var pulse: Label3D=_label()
			pulse.text="✧"; pulse.modulate=Color("dceca5")
			var at: Vector2=Coords.logic_to_ground(previous_shots[id].target if float(previous_shots[id].remaining)<20.0 else previous_shots[id].pos)
			pulse.position=Vector3(at.x,0.3,at.y)
			pulses.append({"node":pulse,"until":visual_time+0.2})
	previous_shots=shots
	for pulse: Dictionary in pulses.duplicate():
		if visual_time>=float(pulse.until): pulse.node.queue_free(); pulses.erase(pulse)
