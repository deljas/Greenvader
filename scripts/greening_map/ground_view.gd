extends Node3D
## Pure state -> mesh transforms; never changes gameplay arrays/counters.
const Session: GDScript = preload("res://scripts/greening_map/session.gd")
const Parts: GDScript = preload("res://scripts/vegetation_lab/plant_parts.gd")
const Geometry: GDScript = preload("res://scripts/render_study_3d/ruin_geometry.gd")
var library: RefCounted = Parts.new()
var grass: Array[MultiMeshInstance3D] = []
var seeds: MultiMeshInstance3D
var samples: Array[Dictionary] = []
var visual_stages: PackedByteArray = PackedByteArray()
var visual_growth: PackedInt32Array = PackedInt32Array()
var stage_counts: Array[int] = [0,0,0,0,0]
var pavement_cracks: MultiMeshInstance3D
var pavement_positions: Array[Vector3] = []
var pavement_angles: Array[float] = []
var terrain_floors: Array[MultiMeshInstance3D] = []
const CRACK_PATH: Array[Vector2] = [Vector2(-0.18,-0.12),Vector2(-0.08,-0.04),Vector2(0.025,-0.07),Vector2(0.09,0.02),Vector2(0.17,0.12)]

func setup(state: WorldState) -> void:
	var tile: BoxMesh = BoxMesh.new()
	tile.size = Vector3(Session.CELL,0.08,Session.CELL)
	var materials: Array[Material] = [Geometry.material(Color("777a63"),3),Geometry.material(Color("777a63"),3),Geometry.material(Color("8b8b6d"),3),Geometry.material(Color("477c89"),3),Geometry.material(Color("6a7068")),Geometry.material(Color("477c89"),3),Geometry.material(Color("777d72"),1)]
	for terrain: int in 7:
		var node: MultiMeshInstance3D = _instances(tile,materials[terrain],state.tile_count())
		node.layers = 2 # Floor undersides must not occlude the planar reflection view.
		terrain_floors.append(node)
		for index: int in state.tile_count():
			var p: Vector2 = Session.cell_center(index)
			var hidden: bool = state.terrain[index]!=terrain
			node.multimesh.set_instance_transform(index,Transform3D(Basis.IDENTITY.scaled(Vector3.ONE*(0.00001 if hidden else 1.0)),Vector3(p.x,-0.04,p.y)))
	for variant: int in 2:
		grass.append(_instances(library.grasses[variant],library.foliage_material,state.tile_count()*3))
	var seed_mesh: BoxMesh = BoxMesh.new()
	seed_mesh.size = Vector3(0.10,0.045,0.075)
	seeds = _instances(seed_mesh,Geometry.material(Color("f0d98b")),state.tile_count())
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 81026
	for index: int in state.tile_count():
		var p: Vector2 = Session.cell_center(index)
		for k: int in 3:
			samples.append({"position":Vector3(p.x+rng.randf_range(-0.13,0.13),0.008,p.y+rng.randf_range(-0.13,0.13)),"angle":rng.randf()*TAU,"variant":rng.randi_range(0,1)})
		var angle_: float = float(state.sprout_slot[index])*PI*0.5
		var crack_origin: Vector3 = Vector3(p.x,0.008,p.y)
		pavement_angles.append(angle_)
		pavement_positions.append(crack_origin+Basis(Vector3.UP,angle_)*Vector3(CRACK_PATH[1].x,0,CRACK_PATH[1].y))
	var crack_material: ShaderMaterial = ShaderMaterial.new()
	var shader_: Shader = Shader.new()
	shader_.code = "shader_type spatial; render_mode cull_disabled; varying float progress; void vertex(){progress=INSTANCE_CUSTOM.r;} void fragment(){if(UV.x>progress) discard; ALBEDO=vec3(0.13,0.16,0.12); ROUGHNESS=1.0;}"
	crack_material.shader = shader_
	pavement_cracks = _instances(_crack_mesh(),crack_material,state.tile_count(),true)
	pavement_cracks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	refresh(state)

func _instances(mesh: Mesh, material_: Material, count: int, custom: bool = false) -> MultiMeshInstance3D:
	var node: MultiMeshInstance3D = MultiMeshInstance3D.new()
	node.multimesh = MultiMesh.new()
	node.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	node.multimesh.use_custom_data = custom
	node.multimesh.mesh = mesh
	node.multimesh.instance_count = count
	node.material_override = material_
	add_child(node)
	return node

func refresh(state: WorldState) -> void:
	visual_stages = state.stage.duplicate()
	visual_growth = state.growth.duplicate()
	stage_counts = [0,0,0,0,0]
	var hidden: Transform3D = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE*0.00001),Vector3.ZERO)
	for index: int in state.tile_count():
		var stage: int = state.stage[index]
		stage_counts[stage] += 1
		var p: Vector2 = Session.cell_center(index)
		var paved: bool = state.terrain[index]==6
		var seed_position: Vector3 = pavement_positions[index]+Vector3.UP*0.022 if paved else Vector3(p.x,0.03,p.y)
		seeds.multimesh.set_instance_transform(index,Transform3D(Basis.IDENTITY,seed_position) if stage==WorldState.STAGE_SEED else hidden)
		pavement_cracks.multimesh.set_instance_transform(index,Transform3D(Basis(Vector3.UP,pavement_angles[index]),Vector3(p.x,0.004,p.y)) if paved and stage>0 else hidden)
		var crack_length: float = 0.0 if stage==0 else (0.36 if stage==1 else 0.58+0.42*clampf(float(state.growth[index])/120000.0,0,1))
		if stage==WorldState.STAGE_MATURE:
			crack_length = 1.0
		pavement_cracks.multimesh.set_instance_custom_data(index,Color(crack_length,0,0,1))
		var scale_: float = 0.0
		if stage>=WorldState.STAGE_SPROUT1:
			scale_ = 0.23+0.50*clampf(float(state.growth[index])/120000.0,0,1)
			if stage==WorldState.STAGE_MATURE:
				scale_ = 0.78
		for k: int in 3:
			var instance: int = index*3+k
			var data: Dictionary = samples[instance]
			for variant: int in 2:
				var transform_: Transform3D = hidden
				if scale_>0 and data["variant"]==variant and (not paved or k==0):
					var display_scale: float = scale_*0.50 if paved else scale_
					transform_ = Transform3D(Basis(Vector3.UP,data["angle"]).scaled(Vector3.ONE*display_scale),pavement_positions[index] if paved else data["position"])
				grass[variant].multimesh.set_instance_transform(instance,transform_)

func _crack_mesh() -> ArrayMesh:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for segment: int in range(CRACK_PATH.size()-1):
		var a: Vector2 = CRACK_PATH[segment]
		var b: Vector2 = CRACK_PATH[segment+1]
		var side: Vector2 = Vector2(-(b-a).y,(b-a).x).normalized()*0.0275
		var corners: Array[Vector2] = [a-side,a+side,b+side,b-side]
		for index: int in [0,2,1,0,3,2]:
			var v: Vector2 = corners[index]
			st.set_normal(Vector3.UP)
			st.set_uv(Vector2(float(segment+(1 if index>=2 else 0))/4.0,0))
			st.add_vertex(Vector3(v.x,0,v.y))
	return st.commit()
