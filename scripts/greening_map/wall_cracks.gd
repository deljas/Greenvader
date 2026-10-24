extends Node3D
## Separate receiving-only surface ribbons; not holes, baked shadows or building albedo.
const Geometry: GDScript = preload("res://scripts/vegetation_lab/building_geometry.gd")
var records: Array[Dictionary] = []

func setup(def: Dictionary) -> void:
	var material_: StandardMaterial3D = StandardMaterial3D.new()
	material_.albedo_color = Color("505b4c")
	material_.roughness = 1
	material_.cull_mode = BaseMaterial3D.CULL_DISABLED
	for surface: Dictionary in def["surfaces"]:
		var st: SurfaceTool = SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var vertices: int = 0
		for x: float in [float(surface["width"])*0.43,float(surface["width"])*0.83]:
			var y: float = float(surface["height"])*0.68
			var points: Array[Vector2] = [Vector2(x,y+0.47),Vector2(x-0.12,y+0.18),Vector2(x+0.03,y),Vector2(x-0.09,y-0.28),Vector2(x+0.05,y-0.52)]
			for i: int in range(points.size()-1):
				var a: Vector2 = points[i]
				var b: Vector2 = points[i+1]
				var side: Vector2 = Vector2(-(b-a).y,(b-a).x).normalized()*0.0275
				if Geometry.blocked_surface(surface,a.x,a.y,0.12) or Geometry.blocked_surface(surface,b.x,b.y,0.12):
					continue
				var blocked: bool = false
				for awning: Rect2 in surface.get("awnings",[]):
					blocked = blocked or awning.grow(0.15).has_point(a) or awning.grow(0.15).has_point(b)
				if blocked:
					continue
				for uv: Vector2 in [a-side,b+side,b-side,a-side,a+side,b+side]:
					var hit: Dictionary = Geometry.sample(surface,uv.x,uv.y)
					st.set_normal(hit["normal"])
					st.add_vertex(hit["position"]+hit["normal"]*0.135)
					vertices += 1
				records.append({"surface":surface,"a":a,"b":b,"width":0.055})
		if vertices>0:
			var node: MeshInstance3D = MeshInstance3D.new()
			node.mesh = st.commit()
			node.material_override = material_
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(node)
