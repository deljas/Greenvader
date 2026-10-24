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
var patch_records: Array[Dictionary] = []
var moss_entries: Array[Dictionary] = []
var individual_moss: bool = false

func setup(def: Dictionary, shared_moss: ShaderMaterial, shared_cracks: ShaderMaterial, options: Dictionary = {}) -> void:
	definition = def
	individual_moss = options.get("individual_moss",false)
	moss_material = shared_moss
	crack_material = shared_cracks
	moss = Node3D.new()
	moss.name = "IndependentMoss"
	add_child(moss)
	cracks = Node3D.new()
	cracks.name = "IndependentCracks"
	add_child(cracks)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = int(def["seed"])+7291
	var patch_index: int = 0
	for surface: Dictionary in def["surfaces"]:
		var u: float = 0.48
		while u<float(surface["width"])-0.20:
			var large: bool = patch_index%3==1
			var size_: float = 2.0 if large else 1.0
			var span: Vector2 = Vector2(size_*rng.randf_range(0.85,1.13),size_*rng.randf_range(0.83,1.12))
			span *= float(options.get("moss_span_scale",1.0))
			var center: Vector2 = Vector2(u+rng.randf_range(-0.18,0.18),rng.randf_range(0.40,0.94))
			var phase: Vector2 = Vector2(rng.randf()*31.0,rng.randf()*31.0)
			_patch(moss,surface,center,span,false,moss_material,phase)
			var roof_span: Vector2 = Vector2(size_*rng.randf_range(0.82,1.08),size_*rng.randf_range(0.70,0.90))
			var roof_center: Vector2 = Vector2(u+rng.randf_range(-0.17,0.17),float(surface["height"])+1.30+rng.randf_range(-0.12,0.12))
			if not options.get("walls_only",false):
				_patch(moss,surface,roof_center,roof_span,true,moss_material,phase+Vector2(5,9))
			u += rng.randf_range(0.90,1.38)
			patch_index += 1
		if options.get("include_cracks",true):
			_patch(cracks,surface,Vector2(float(surface["width"])*0.43,float(surface["height"])*0.75),Vector2(0.72,0.85),false,crack_material)
			_patch(cracks,surface,Vector2(float(surface["width"])*0.82,float(surface["height"])*0.45),Vector2(0.62,0.90),false,crack_material)

func _patch(parent: Node3D, surface: Dictionary, center: Vector2, span: Vector2, roof: bool, material_: Material, phase: Vector2 = Vector2.ZERO) -> void:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var added: int = 0
	# Small chart cells follow curved surfaces and leave openings clear.
	# Preserve the crack sheet's original 6x6 geometry; larger moss uses <=.16 chart cells.
	var divisions: int = 6 if parent==cracks else maxi(6,ceili(maxf(span.x,span.y)/0.16))
	for row: int in divisions:
		for col: int in divisions:
			var corners: Array[Dictionary] = []
			var valid: bool = true
			for xy: Vector2 in [Vector2(col,row),Vector2(col+1,row),Vector2(col+1,row+1),Vector2(col,row+1)]:
				var uv: Vector2 = center+(xy/float(divisions)-Vector2.ONE*0.5)*span
				if uv.x<0.05 or uv.x>float(surface["width"])-0.05 or (not roof and (uv.y<0.03 or uv.y>float(surface["height"])-0.03 or Geometry.blocked_surface(surface,uv.x,uv.y,0.08))):
					valid = false
				var hit: Dictionary = Geometry.path_sample(definition,surface,uv.x,uv.y) if roof else Geometry.sample(surface,uv.x,uv.y)
				if hit.is_empty():
					valid = false
				else:
					hit["position"] += hit["normal"]*(0.132 if surface["kind"]=="plane" and not roof else 0.035)
					hit["uv"] = xy/float(divisions)
					hit["uv2"] = uv+phase
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
	if parent==moss:
		patch_records.append({"surface_kind":surface["kind"],"surface_width":surface["width"],"center":[center.x,center.y],"span":[span.x,span.y],"phase":[phase.x,phase.y],"roof":roof,"divisions":divisions,"vertices":added})
	if added>0:
		var mesh: MeshInstance3D = MeshInstance3D.new()
		mesh.mesh = st.commit()
		if parent==moss and individual_moss:
			mesh.material_override = material_.duplicate()
			mesh.material_override.set_shader_parameter("coverage",0.0)
		else:
			mesh.material_override = material_
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mesh)
		if parent==moss:
			moss_entries.append({"mesh":mesh,"surface":surface,"center":center,"roof":roof})

func set_patch_progress(index: int, value: float) -> void:
	if individual_moss:
		var material_: ShaderMaterial = moss_entries[index]["mesh"].material_override
		material_.set_shader_parameter("coverage",clampf(value,0,1))
