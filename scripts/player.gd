class_name FlowerPlayer
extends Node2D
## Simulation coordinates remain continuous; only the presentation is rounded.

const SPEED: float = 96.0
signal presentation_updated(location: Vector2)
var simulation_position: Vector2 = Vector2(480, 368)
## Walkable pixel rectangle; main sets it from the region size.
var world_bounds: Rect2 = Rect2(32, 32, 1984, 1984)
var aim_direction: Vector2 = Vector2.RIGHT
## Walking against the map (P1-06): null = free movement (older tests build a bare player).
var walk_world: WorldState
var walk_tile_px: int = 4
var walk_half: Vector2 = Vector2(3, 2)
## Damage state (P2-03): null = the player is never hurt (older tests build a bare player). While downed the controls are locked;
## while invulnerable the picture flickers.
var health: PlayerHealth
var visual: Sprite2D
var light: PointLight2D
var _look_down: bool = false
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
	if is_downed():
		direction = Vector2.ZERO
	step(direction * SPEED * delta)
	position = simulation_position.round()
	update_look()
	presentation_updated.emit(position)
	var target: Vector2 = get_global_mouse_position() - position
	if target.length_squared() > 1.0:
		aim_direction = target.normalized()
	queue_redraw()

func is_downed() -> bool:
	return health != null and health.downed

## Puts the player at `location` (return to the start) and tells the camera.
func teleport(location: Vector2) -> void:
	simulation_position = location.clamp(world_bounds.position, world_bounds.end)
	position = simulation_position.round()
	presentation_updated.emit(position)

## Picture of the damage state: lying dimmed while downed, flickering (dim / bright) while invulnerable, plain otherwise.
func update_look() -> void:
	if visual == null:
		return
	var down: bool = is_downed()
	if down != _look_down:
		_look_down = down
		visual.texture = PlayArt.flower_down() if down else PixelArt.flower()
		visual.position = Vector2(-8, -11) if down else Vector2(-8, -14)
	if down:
		visual.modulate = Color(0.62, 0.64, 0.78, 1.0)
	elif health != null and health.flicker_dim():
		visual.modulate = Color(1.0, 1.0, 1.0, 0.3)
	else:
		visual.modulate = Color.WHITE

## Moves the simulation position by `motion` px: against the map when walk_world is set (slides along water and
## buildings), then inside the world bounds.
func step(motion: Vector2) -> void:
	if walk_world != null:
		simulation_position = Walker.move(walk_world, walk_tile_px, simulation_position, motion, walk_half)
	else:
		simulation_position += motion
	simulation_position = simulation_position.clamp(world_bounds.position, world_bounds.end)

func _draw() -> void:
	draw_rect(Rect2(-6, 0, 12, 3), Color(0.13, 0.22, 0.19, 0.45))
	var marker: Vector2 = (aim_direction * 19.0).round()
	draw_rect(Rect2(marker - Vector2.ONE, Vector2(3, 3)), Color("ffe5a0"))
