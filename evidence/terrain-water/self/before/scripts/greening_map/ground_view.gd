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

func setup(state: WorldState) -> void:
	var tile: BoxMesh = BoxMesh.new()
	tile.size = Vector3(Session.CELL,0.08,Session.CELL)
	var materials: Array[Material] = [Geometry.material(Color("777a63"),3),Geometry.material(Color("777a63"),3),Geometry.material(Color("8b8b6d"),3),Geometry.material(Color("477c89"),3),Geometry.material(Color("6a7068")),Geometry.material(Color("477c89"),3),Geometry.material(Color("777d72"),1)]
	for terrain: int in 7:
		var node: MultiMeshInstance3D = _instances(tile,materials[terrain],state.tile_count())
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
	refresh(state)

func _instances(mesh: Mesh, material_: Material, count: int) -> MultiMeshInstance3D:
	var node: MultiMeshInstance3D = MultiMeshInstance3D.new()
	node.multimesh = MultiMesh.new()
	node.multimesh.transform_format = MultiMesh.TRANSFORM_3D
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
		seeds.multimesh.set_instance_transform(index,Transform3D(Basis.IDENTITY,Vector3(p.x,0.03,p.y)) if stage==WorldState.STAGE_SEED else hidden)
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
				if scale_>0 and data["variant"]==variant:
					transform_ = Transform3D(Basis(Vector3.UP,data["angle"]).scaled(Vector3.ONE*scale_),data["position"])
				grass[variant].multimesh.set_instance_transform(instance,transform_)
