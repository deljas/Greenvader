extends Node3D
## Shared native-pixel vertical card, with separate shadow/effect children and a stable foot anchor.
const Catalog: GDScript = preload("res://scripts/poc2/view/entity_sprite_catalog.gd")
const DISPLAY: int = 64
const SHADOW: int = 8
var body: Sprite3D
var shadow: Sprite3D
var effects: Node3D
var visual_state: String = "idle"
var direction: StringName = &"down"
var render_foot: Vector3 = Vector3.ZERO
var pixel_size: float = 0.0
var sampled: Dictionary = {}

func _init() -> void:
	body = _card("Body",DISPLAY,GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	shadow = _card("Shadow",SHADOW,GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY)
	effects = Node3D.new()
	effects.name = "Effects"
	add_child(effects)

func _card(label: String, layer: int, cast: int) -> Sprite3D:
	var card: Sprite3D = Sprite3D.new()
	card.name = label
	card.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	card.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	card.alpha_scissor_threshold = 0.5
	card.alpha_antialiasing_mode = BaseMaterial3D.ALPHA_ANTIALIASING_OFF
	card.shaded = true
	card.double_sided = true
	card.cast_shadow = cast
	card.layers = layer
	add_child(card)
	return card

func pose(definition: Dictionary, presentation: Dictionary, foot: Vector3, camera: Camera3D, sun: DirectionalLight3D, elapsed: float) -> void:
	visual_state = presentation.state
	direction = presentation.direction
	sampled = Catalog.sample(definition,visual_state,direction,elapsed)
	if sampled.is_empty():
		visible = false
		return
	visible = true
	pixel_size = camera.size / 360.0
	var screen: Vector2 = camera.unproject_position(foot)
	var correction: Vector2 = screen.round()-screen
	var forward: Vector3 = Vector3(camera.global_basis.z.x,0,camera.global_basis.z.z).normalized()
	var tilt: float = -camera.global_basis.y.dot(forward)
	render_foot = foot + camera.global_basis.x*correction.x*pixel_size + forward*correction.y*pixel_size/tilt
	var upright: float = 1.0/maxf(camera.global_basis.y.dot(Vector3.UP),0.1)
	var anchor: Vector2 = sampled.anchor
	var extent: Vector2 = Vector2(sampled.frame_pixels)
	if sampled.flip: anchor.x = extent.x-anchor.x
	# Horizontal as well as vertical anchors are supported; every frame is centred on the same foot.
	body.global_basis = Basis(camera.global_basis.x,Vector3.UP*upright,forward)
	var normal: Vector3 = Vector3(sun.global_basis.z.x,0,sun.global_basis.z.z).normalized()
	shadow.global_basis = Basis(Vector3.UP.cross(normal),Vector3.UP*upright,normal)
	for card: Sprite3D in [body,shadow]:
		card.pixel_size = pixel_size
		card.global_position = render_foot + card.global_basis.x*(extent.x*0.5-anchor.x)*pixel_size + Vector3.UP*(anchor.y-extent.y*0.5)*pixel_size*upright
		card.texture = sampled.texture
		card.flip_h = sampled.flip
	body.modulate = Color("f2c372") if visual_state=="windup" else (Color(1.5,1.5,1.5) if visual_state=="hit" else Color.WHITE)
	effects.global_transform = Transform3D(Basis.IDENTITY,render_foot)

func snapshot() -> Dictionary:
	var body_foot: Vector3 = _foot_of(body)
	var shadow_foot: Vector3 = _foot_of(shadow)
	return {"state":visual_state,"direction":String(direction),"clip_state":sampled.get("clip_state",""),"frame":sampled.get("frame",0),"source_pixels":sampled.get("frame_pixels",Vector2i.ZERO),"anchor":sampled.get("anchor",Vector2.ZERO),"pixel_size":pixel_size,"foot":render_foot,"body_foot":body_foot,"shadow_foot":shadow_foot,"shadow_matches":body.texture==shadow.texture and body_foot.is_equal_approx(render_foot) and shadow_foot.is_equal_approx(render_foot) and body.flip_h==shadow.flip_h}

func _foot_of(card: Sprite3D) -> Vector3:
	if sampled.is_empty(): return Vector3.ZERO
	var anchor: Vector2 = sampled.anchor
	var extent: Vector2 = Vector2(sampled.frame_pixels)
	if card.flip_h: anchor.x = extent.x-anchor.x
	return card.global_position + card.global_basis.x*(anchor.x-extent.x*0.5)*pixel_size + card.global_basis.y*(extent.y*0.5-anchor.y)*pixel_size
