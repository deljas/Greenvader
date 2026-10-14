class_name FlowerPlayer
extends Node2D
## Simulation coordinates remain continuous; only the presentation is rounded.

const SPEED: float = 96.0
signal presentation_updated(location: Vector2)
var simulation_position: Vector2 = Vector2(480, 368)
## Walkable pixel rectangle; main sets it from the region size.
var world_bounds: Rect2 = Rect2(32, 32, 1984, 1984)
var aim_direction: Vector2 = Vector2.RIGHT
var visual: Sprite2D
var light: PointLight2D
var glow: Sprite2D

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	visual = Sprite2D.new()
	visual.texture = PixelArt.flower()
	visual.centered = false
	visual.position = Vector2(-8, -14)
	add_child(visual)
	light = PointLight2D.new()
	light.texture = PixelArt.halo()
	light.color = Color("f7d9a5")
	light.energy = 0.65
	light.texture_scale = 1.35
	light.shadow_enabled = false
	add_child(light)
	glow = Sprite2D.new()
	glow.texture = PixelArt.halo()
	glow.modulate = Color(1.0, 0.68, 0.44, 0.24)
	glow.position = Vector2(0, -6)
	var material: CanvasItemMaterial = CanvasItemMaterial.new()
	material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	glow.material = material
	add_child(glow)
	position = simulation_position.round()

func _physics_process(delta: float) -> void:
	var direction: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	simulation_position += direction * SPEED * delta
	simulation_position = simulation_position.clamp(world_bounds.position, world_bounds.end)
	position = simulation_position.round()
	presentation_updated.emit(position)
	var target: Vector2 = get_global_mouse_position() - position
	if target.length_squared() > 1.0:
		aim_direction = target.normalized()
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(-6, 0, 12, 3), Color(0.13, 0.22, 0.19, 0.45))
	var marker: Vector2 = (aim_direction * 19.0).round()
	draw_rect(Rect2(marker - Vector2.ONE, Vector2(3, 3)), Color("ffe5a0"))
