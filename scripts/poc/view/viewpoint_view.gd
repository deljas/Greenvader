extends Node3D
## WTH-02 display of the viewpoint spot: a pale ring with a green centre disc and a short post, readable on any ground and at night
## (a little emission). No outline, no logic. Built from data/poc/viewpoint.json "marker".
const Coords: GDScript = preload("res://scripts/poc/poc_coords.gd")

func build(cell: Vector2i, tuning: Dictionary) -> void:
	var m: Dictionary = tuning.get("marker", {})
	var ground: Vector2 = Coords.cell_center_ground(cell)
	position = Vector3(ground.x, 0.0, ground.y)
	var emission: float = float(m.get("emission", 0.35))
	_disc("Ring", float(m.get("ring_radius_m", 1.3)), 0.14, Color(String(m.get("ring_color", "f3e7a6"))), emission, 0.0)
	_disc("Inner", float(m.get("inner_radius_m", 0.85)), 0.17, Color(String(m.get("inner_color", "3f7a4c"))), emission * 0.5, 0.0)
	var height: float = float(m.get("post_height_m", 1.1))
	var post: MeshInstance3D = MeshInstance3D.new()
	post.name = "Post"
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(0.16, height, 0.16)
	post.mesh = box
	post.material_override = _material(Color(String(m.get("post_color", "f3e7a6"))), emission)
	post.position = Vector3(0.0, height * 0.5, 0.0)
	add_child(post)
	var cap: MeshInstance3D = MeshInstance3D.new()
	cap.name = "Cap"
	var cap_box: BoxMesh = BoxMesh.new()
	cap_box.size = Vector3(0.55, 0.14, 0.55)
	cap.mesh = cap_box
	cap.material_override = _material(Color(String(m.get("ring_color", "f3e7a6"))), emission)
	cap.position = Vector3(0.0, height + 0.07, 0.0)
	add_child(cap)

func _material(color: Color, emission: float) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	material.metallic_specular = 0.0
	material.emission_enabled = emission > 0.0
	material.emission = color
	material.emission_energy_multiplier = emission
	return material

func _disc(node_name: String, radius: float, height: float, color: Color, emission: float, lift: float) -> void:
	var disc: MeshInstance3D = MeshInstance3D.new()
	disc.name = node_name
	var mesh: CylinderMesh = CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 24
	mesh.rings = 1
	disc.mesh = mesh
	disc.material_override = _material(color, emission)
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	disc.position = Vector3(0.0, height * 0.5 + lift, 0.0)
	add_child(disc)
