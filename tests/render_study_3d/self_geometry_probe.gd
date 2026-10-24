extends SceneTree
const Geometry: GDScript = preload("res://scripts/render_study_3d/ruin_geometry.gd")

func _initialize() -> void:
	var holder: Node3D = Node3D.new()
	var parts: Dictionary = Geometry.build(holder)
	var roof: Mesh = parts["roof"].get_child(0).mesh
	print("ROOF top winding dot normal = ", top_sign(roof))
	print("BOX top winding dot normal = ", top_sign(BoxMesh.new()))
	holder.free()
	quit()

func top_sign(mesh: Mesh) -> float:
	var arrays: Array = mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	for i: int in range(0, indices.size() if not indices.is_empty() else vertices.size(), 3):
		var a: int = indices[i] if not indices.is_empty() else i
		var b: int = indices[i+1] if not indices.is_empty() else i+1
		var c: int = indices[i+2] if not indices.is_empty() else i+2
		if normals[a].y > 0.99:
			return (vertices[b]-vertices[a]).cross(vertices[c]-vertices[a]).normalized().dot(normals[a])
	return 0.0
