extends Node3D
## POL-01 readability aids, display only (the session never reads anything here): a filled disc on the ground under the
## player's feet (not an outline, not drawn on top of everything: it is an ordinary depth-tested transparent disc), a weak
## local light that follows the player at night, and the night lamps (an OmniLight3D per street lamp of the placement, on only
## while it is dark). All of it is driven from the single game clock through the day state EnvironmentView passes to apply().
## Tuning: data/poc/environment.json "readability".
const Coords: GDScript = preload("res://scripts/poc/poc_coords.gd")

var marker: MeshInstance3D
var marker_material: StandardMaterial3D
var player_light: OmniLight3D
var lamp_lights: Array[OmniLight3D] = []
var lamp_bulbs: Array[MeshInstance3D] = []
var tuning: Dictionary = {}
## Last applied values (observability / tests).
var last_night: float = 0.0
var last_marker_alpha: float = 0.0
var last_player_light_energy: float = 0.0
var last_lamp_energy: float = 0.0
var _lamp_energy_max: float = 0.0
var _foot: Vector3 = Vector3.ZERO
var see_through: bool = false
## Enemy foot markers (display only): one MultiMesh of flat ellipses under every boar, red-orange so it differs from the
## player's pale disc. Layer 32 like the player's disc (not in the water reflection, casts no shadow).
var enemy_marker: MultiMeshInstance3D
var enemy_material: StandardMaterial3D
var enemy_capacity: int = 0
var last_enemy_alpha: float = 0.0
var last_enemy_count: int = 0

func setup(tuning_: Dictionary, placement: RefCounted, holders: Dictionary) -> void:
	tuning = tuning_.get("readability", {})
	var disc: Dictionary = tuning.get("marker", {})
	marker = MeshInstance3D.new()
	marker.name = "FootMarker"
	var mesh: CylinderMesh = CylinderMesh.new()
	mesh.top_radius = float(disc.get("radius_m", 0.42))
	mesh.bottom_radius = mesh.top_radius
	mesh.height = 0.01
	mesh.radial_segments = 24
	mesh.rings = 1
	marker.mesh = mesh
	marker_material = StandardMaterial3D.new()
	marker_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	marker_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	marker_material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	marker_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	marker_material.albedo_color = Color(String(disc.get("color", "cfefff")))
	marker.material_override = marker_material
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	marker.layers = 32 # own layer: seen by the main camera only (16 is the hidden reflection-copy layer, 1 the water reflection, 8 shadows)
	marker.visible = bool(disc.get("enabled", true))
	add_child(marker)
	var foe: Dictionary = tuning.get("enemy_marker", {})
	enemy_marker = MultiMeshInstance3D.new()
	enemy_marker.name = "EnemyMarkers"
	var foe_mesh: CylinderMesh = CylinderMesh.new()
	foe_mesh.top_radius = 1.0
	foe_mesh.bottom_radius = 1.0
	foe_mesh.height = 0.01
	foe_mesh.radial_segments = 20
	foe_mesh.rings = 1
	enemy_material = StandardMaterial3D.new()
	enemy_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	enemy_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	enemy_material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	enemy_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	enemy_material.albedo_color = Color(String(foe.get("color", "ff6a2a")))
	var multi: MultiMesh = MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = foe_mesh
	multi.instance_count = 0
	enemy_marker.multimesh = multi
	enemy_marker.material_override = enemy_material
	enemy_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	enemy_marker.layers = 32
	enemy_marker.visible = bool(foe.get("enabled", true))
	enemy_marker.extra_cull_margin = 200.0
	add_child(enemy_marker)
	var local: Dictionary = tuning.get("player_light", {})
	player_light = OmniLight3D.new()
	player_light.name = "PlayerLight"
	player_light.light_color = Color(String(local.get("color", "ffe0b0")))
	player_light.omni_range = float(local.get("range_m", 3.6))
	player_light.omni_attenuation = float(local.get("attenuation", 1.2))
	player_light.light_specular = 0.0
	player_light.shadow_enabled = false
	player_light.light_energy = 0.0
	player_light.visible = false
	add_child(player_light)
	var lamps: Dictionary = tuning.get("lamps", {})
	_lamp_energy_max = float(lamps.get("energy", 2.2))
	if placement != null and bool(lamps.get("enabled", true)):
		var head: Array = lamps.get("head_local", [0.4, 3.0, 0.0])
		var head_local: Vector3 = Vector3(float(head[0]), float(head[1]), float(head[2]))
		for inst: Dictionary in placement.instances:
			if String(inst["asset"]) != String(lamps.get("asset", "PRP-001")) or not holders.has(inst["id"]):
				continue
			var holder: Node3D = holders[inst["id"]]
			var at: Vector3 = holder.transform * head_local
			var light: OmniLight3D = OmniLight3D.new()
			light.name = "Lamp_" + String(inst["id"])
			light.position = at
			light.light_color = Color(String(lamps.get("color", "ffc880")))
			light.omni_range = float(lamps.get("range_m", 6.0))
			light.omni_attenuation = float(lamps.get("attenuation", 1.3))
			light.light_specular = 0.0
			light.shadow_enabled = bool(lamps.get("shadow", false))
			light.light_energy = 0.0
			light.visible = false
			add_child(light)
			lamp_lights.append(light)
			var bulb: MeshInstance3D = MeshInstance3D.new()
			var sphere: SphereMesh = SphereMesh.new()
			sphere.radius = float(lamps.get("bulb_radius_m", 0.1))
			sphere.height = sphere.radius * 2.0
			sphere.radial_segments = 8
			sphere.rings = 4
			bulb.mesh = sphere
			var glow: StandardMaterial3D = StandardMaterial3D.new()
			glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			glow.albedo_color = Color(String(lamps.get("bulb_color", "fff0c0")))
			bulb.material_override = glow
			bulb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			bulb.position = at
			bulb.visible = false
			add_child(bulb)
			lamp_bulbs.append(bulb)

## `day` = poc_day.gd state (from the one game clock). night is 0 in the day and 1 in the dark.
func apply(day: Dictionary) -> void:
	var night: float = clampf(float(day["night"]), 0.0, 1.0)
	last_night = night
	var disc: Dictionary = tuning.get("marker", {})
	last_marker_alpha = lerpf(float(disc.get("alpha_day", 0.3)), float(disc.get("alpha_night", 0.62)), night)
	var color: Color = marker_material.albedo_color
	color.a = last_marker_alpha
	marker_material.albedo_color = color
	var foe: Dictionary = tuning.get("enemy_marker", {})
	last_enemy_alpha = lerpf(float(foe.get("alpha_day", 0.28)), float(foe.get("alpha_night", 0.6)), night)
	var foe_color: Color = enemy_material.albedo_color
	foe_color.a = last_enemy_alpha
	enemy_material.albedo_color = foe_color
	var local: Dictionary = tuning.get("player_light", {})
	last_player_light_energy = float(local.get("energy", 0.9)) * night if bool(local.get("enabled", true)) else 0.0
	player_light.light_energy = last_player_light_energy
	player_light.visible = last_player_light_energy > 0.001
	last_lamp_energy = _lamp_energy_max * night
	for i: int in lamp_lights.size():
		lamp_lights[i].light_energy = last_lamp_energy
		lamp_lights[i].visible = last_lamp_energy > 0.001
		lamp_bulbs[i].visible = night > 0.05

## Follows the player's (pixel-snapped) feet. `toward_camera` is the horizontal unit vector from the player to the camera.
func follow(foot: Vector3, toward_camera: Vector3) -> void:
	_foot = foot
	var disc: Dictionary = tuning.get("marker", {})
	marker.position = Vector3(foot.x, float(disc.get("height_m", 0.07)), foot.z)
	var local: Dictionary = tuning.get("player_light", {})
	player_light.position = foot + Vector3.UP * float(local.get("height_m", 1.5)) + toward_camera * float(local.get("toward_camera_m", 0.9))

## Places one ellipse under every living boar (a single draw call however many there are). Display only.
func sync_enemies(boars: Array) -> void:
	var foe: Dictionary = tuning.get("enemy_marker", {})
	var multi: MultiMesh = enemy_marker.multimesh
	if boars.size() > enemy_capacity:
		enemy_capacity = maxi(boars.size() * 2, 32)
		multi.instance_count = enemy_capacity
	var rx: float = float(foe.get("radius_m", 0.34))
	var rz: float = rx * float(foe.get("squash", 0.7))
	var height: float = float(foe.get("height_m", 0.06))
	var n: int = 0
	for boar: Variant in boars:
		if int(boar.hp) <= 0:
			continue
		var ground: Vector2 = Coords.logic_to_ground(boar.pos)
		multi.set_instance_transform(n, Transform3D(Basis.from_scale(Vector3(rx, 1.0, rz)), Vector3(ground.x, height, ground.y)))
		n += 1
	multi.visible_instance_count = n
	last_enemy_count = n

func snapshot() -> Dictionary:
	var on: int = 0
	for light: OmniLight3D in lamp_lights:
		on += 1 if light.visible else 0
	return {"night": last_night, "marker_alpha": last_marker_alpha, "player_light": last_player_light_energy, "lamp_energy": last_lamp_energy, "lamps": lamp_lights.size(), "lamps_on": on, "enemy_markers": last_enemy_count, "enemy_alpha": last_enemy_alpha}

## While a building/tree hides the player (a faded instance exists) the faded surface's depth pre-pass would reject the disc
## behind it; the disc is then drawn without the depth test (after the transparent surfaces). Otherwise it is depth-tested.
func set_see_through(on: bool) -> void:
	if on == see_through:
		return
	see_through = on
	marker_material.no_depth_test = on
	marker_material.render_priority = 20 if on else 0
