extends Node3D
## Independent receiving-only surface sheets. Never changes a building material.
const Geometry: GDScript = preload("res://scripts/vegetation_lab/building_geometry.gd")
const Moss: Shader = preload("res://scripts/vegetation_lab/moss.gdshader")
const Cracks: Shader = preload("res://scripts/vegetation_lab/cracks.gdshader")
var moss: Node3D
var cracks: Node3D
var moss_material: ShaderMaterial
var crack_material: ShaderMaterial
var definition: Dictionary

func setup(def: Dictionary, shared_moss: ShaderMaterial, shared_cracks: ShaderMaterial) -> void:
	definition = def
	moss_material = shared_moss
	crack_material = shared_cracks
	moss = Node3D.new()
	moss.name = "IndependentMoss"
	add_child(moss)
	cracks = Node3D.new()
	cracks.name = "IndependentCracks"
	add_child(cracks)
	for surface: Dictionary in def["surfaces"]:
		var u: float = 0.50
		while u<float(surface["width"])-0.25:
			_patch(moss,surface,Vector2(u,0.50+0.10*sin(u*8)),Vector2(1.05,0.95),false,moss_material)
			_patch(moss,surface,Vector2(u,1.13+0.12*sin(u*3)),Vector2(0.72,0.70),false,moss_material)
			_patch(moss,surface,Vector2(u,float(surface["height"])+1.20),Vector2(1.0,0.68),true,moss_material)
			u += 0.85
		_patch(cracks,surface,Vector2(float(surface["width"])*0.43,float(surface["height"])*0.75),Vector2(0.72,0.85),false,crack_material)
		_patch(cracks,surface,Vector2(float(surface["width"])*0.82,float(surface["height"])*0.45),Vector2(0.62,0.90),false,crack_material)

func _patch(parent: Node3D, surface: Dictionary, center: Vector2, span: Vector2, roof: bool, material_: Material) -> void:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var added: int = 0
	# Small chart cells follow curved surfaces and leave openings clear.
	for row: int in 6:
		for col: int in 6:
			var corners: Array[Dictionary] = []
			var valid: bool = true
			for xy: Vector2 in [Vector2(col,row),Vector2(col+1,row),Vector2(col+1,row+1),Vector2(col,row+1)]:
				var uv: Vector2 = center+(xy/6.0-Vector2.ONE*0.5)*span
				if uv.x<0.05 or uv.x>float(surface["width"])-0.05 or (not roof and (uv.y<0.03 or uv.y>float(surface["height"])-0.03 or Geometry.blocked_surface(surface,uv.x,uv.y,0.08))):
					valid = false
				var hit: Dictionary = Geometry.path_sample(definition,surface,uv.x,uv.y) if roof else Geometry.sample(surface,uv.x,uv.y)
				if hit.is_empty():
					valid = false
				else:
					hit["position"] += hit["normal"]*(0.132 if surface["kind"]=="plane" and not roof else 0.035)
					hit["uv"] = xy/6.0
					hit["uv2"] = uv
				corners.append(hit)
			if not valid:
				continue
			for index: int in [0,2,1,0,3,2]:
				var vertex: Dictionary = corners[index]
				st.set_normal(vertex["normal"])
				st.set_uv(vertex["uv"])
				st.set_uv2(vertex["uv2"])
				st.add_vertex(vertex["position"])
				added += 1
	if added>0:
		var mesh: MeshInstance3D = MeshInstance3D.new()
		mesh.mesh = st.commit()
		mesh.material_override = material_
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mesh)
