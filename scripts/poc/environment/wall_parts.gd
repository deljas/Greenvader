extends RefCounted
## POC-05 shared vine / grass parts (ported from the vegetation lab's plant_parts.gd). One instance owns the Resources that every
## building / ground cell shares. Flat vertex colours, no outline.
var grasses: Array[ArrayMesh] = []
var leaves: ArrayMesh
var stem: CylinderMesh
var foliage_material: StandardMaterial3D
var stem_material: StandardMaterial3D

func _init() -> void:
	foliage_material = StandardMaterial3D.new()
	foliage_material.vertex_color_use_as_albedo = true
	foliage_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	foliage_material.roughness = 1.0
	foliage_material.metallic_specular = 0.0
	stem_material = StandardMaterial3D.new()
	stem_material.albedo_color = Color("426247")
	stem_material.roughness = 1.0
	stem_material.metallic_specular = 0.0
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i: int in 7:
		var angle: float = float(i) * 2.4
		var c: Vector3 = Vector3(cos(angle) * 0.14, sin(angle) * 0.15, 0.035 * float(i % 3))
		var tip: Vector3 = c + Vector3(cos(angle) * 0.19, sin(angle) * 0.17, 0.015)
		var side: Vector3 = Vector3(-sin(angle), cos(angle), 0.0) * 0.09
		triangle(st, c - side, tip, c + side, Color("397447"), Color("87a653"))
	leaves = st.commit()
	stem = CylinderMesh.new()
	stem.top_radius = 0.020
	stem.bottom_radius = 0.024
	stem.height = 1.0
	stem.radial_segments = 5

static func triangle(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, root_color: Color, tip_color: Color) -> void:
	var normal: Vector3 = (b - a).cross(c - a).normalized()
	var points: Array[Vector3] = [a, b, c]
	for i: int in 3:
		st.set_normal(normal)
		st.set_color(tip_color if i == 1 else root_color)
		st.add_vertex(points[i])

static func facing(normal: Vector3) -> Basis:
	var right: Vector3 = Vector3.UP.cross(normal)
	if right.length_squared() < 0.001:
		right = Vector3.RIGHT
	right = right.normalized()
	return Basis(right, normal.cross(right).normalized(), normal)
