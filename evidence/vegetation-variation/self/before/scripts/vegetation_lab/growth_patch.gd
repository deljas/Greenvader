extends Node3D
const Geometry: GDScript = preload("res://scripts/vegetation_lab/building_geometry.gd")
var definition: Dictionary
var grass_candidates: Array[Dictionary] = []
var paths: Array[Dictionary] = []
var grass_nodes: Array[MultiMeshInstance3D] = []
var leaf_node: MultiMeshInstance3D
var stem_node: MultiMeshInstance3D
var progress: float = 0.0
var duration: float = 0.0
var pose_signature: String = ""
var growth_events: Array[Dictionary] = []

func setup(def: Dictionary, library: RefCounted) -> void:
	definition = def
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = int(def["seed"])
	var extent: Vector2 = def["extent"]
	for x: int in range(int(-extent.x/0.36),int(extent.x/0.36)):
		for z: int in range(int(-extent.y/0.36),int(extent.y/0.36)):
			var p: Vector2 = Vector2(x*0.36+rng.randf_range(-0.10,0.10),z*0.36+rng.randf_range(-0.10,0.10))
			if Geometry.ground_allowed(def,p):
				grass_candidates.append({"position":Vector3(p.x,0.02,p.y),"angle":rng.randf()*TAU,"threshold":rng.randf()*0.65,"variant":rng.randi_range(0,1)})
	for variant: int in 2:
		grass_nodes.append(_instances(library.grasses[variant],library.foliage_material,grass_candidates.size()))
	for surface: Dictionary in def["surfaces"]:
		var u: float = 0.32
		while u < float(surface["width"])-0.20:
			var safe: bool = true
			for hole: Rect2 in surface["holes"]:
				if u > hole.position.x-0.40 and u < hole.end.x+0.40:
					safe = false
			if safe:
				var points: Array[Dictionary] = []
				var length_: float = float(surface["height"])+1.65
				var steps: int = ceili(length_/0.10)
				for step: int in range(steps+1):
					var d: float = float(step)/steps*length_
					var uv: float = u+sin(d*2.2+u)*0.035
					var hit: Dictionary = Geometry.path_sample(def,surface,uv,d)
					if hit.is_empty():
						break
					_register_point(points,hit,Vector2(uv,d))
				var parent_index: int = paths.size()
				_add_path(points,surface,0.0,-1,-1)
				# Both directions share the trunk's exact junction, then spread in UV.
				for height_: float in [0.62,1.38,2.38,3.45,4.35]:
					if height_ > float(surface["height"])-0.20:
						continue
					var junction: int = mini(roundi(height_/length_*steps),points.size()-1)
					var origin: Dictionary = points[junction]
					for direction: float in [-1.0,1.0]:
						var branch: Array[Dictionary] = [origin.duplicate()]
						branch[0]["distance"] = 0.0
						for n: int in range(1,17):
							var bu: float = float(origin["u"])+direction*n*0.085
							var bv: float = float(origin["v"])+n*0.042
							if bu < 0.18 or bu > float(surface["width"])-0.18 or bv > float(surface["height"])-0.20 or Geometry.blocked_surface(surface,bu,bv,0.34):
								break
							_register_point(branch,Geometry.sample(surface,bu,bv),Vector2(bu,bv))
						if branch.size()>3:
							_add_path(branch,surface,float(origin["distance"]),parent_index,junction)
			u += 0.63
	var point_count: int = 0
	for path: Dictionary in paths:
		point_count += path["points"].size()
	leaf_node = _instances(library.leaves,library.foliage_material,point_count)
	stem_node = _instances(library.stem,library.stem_material,point_count)
	set_growth(0)

func _instances(mesh: Mesh, material_: Material, count: int) -> MultiMeshInstance3D:
	var node: MultiMeshInstance3D = MultiMeshInstance3D.new()
	var mm: MultiMesh = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = count
	node.multimesh = mm
	node.material_override = material_
	add_child(node)
	return node

func set_growth(value: float) -> void:
	progress = clampf(value/100.0,0,1)
	var hidden: Transform3D = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE*0.00001),Vector3.ZERO)
	for variant: int in 2:
		for i: int in grass_candidates.size():
			var candidate: Dictionary = grass_candidates[i]
			var scale_: float = clampf((progress-float(candidate["threshold"]))/0.35,0.00001,1.0)
			var transform_: Transform3D = Transform3D(Basis(Vector3.UP,candidate["angle"]).scaled(Vector3.ONE*scale_),candidate["position"])
			grass_nodes[variant].multimesh.set_instance_transform(i,transform_ if candidate["variant"]==variant else hidden)
	growth_events.clear()
	var cursor: int = 0
	var pose_rows: Array[Transform3D] = []
	for path: Dictionary in paths:
		var points: Array = path["points"]
		var grown: float = clampf((progress-0.08)/0.92,0,1)*duration-float(path["start"])
		growth_events.append({"parent":path["parent"],"start":path["start"],"grown":grown,"junction":path["junction"]})
		for j: int in points.size():
			var hit: Dictionary = points[j]
			var leaf_scale: float = clampf((grown-float(hit["distance"]))/0.24,0.00001,1.0)
			var leaf_basis: Basis = Geometry.facing(hit["normal"])*Basis(Vector3.FORWARD,float(j)*0.8)
			var leaf_transform: Transform3D = Transform3D(leaf_basis.scaled(Vector3.ONE*leaf_scale),hit["position"]) if j%2==0 else hidden
			leaf_node.multimesh.set_instance_transform(cursor,leaf_transform)
			pose_rows.append(leaf_transform)
			if j==0:
				stem_node.multimesh.set_instance_transform(cursor,hidden)
			else:
				var a: Vector3 = points[j-1]["position"]
				var b: Vector3 = hit["position"]
				var fraction: float = clampf((grown-float(points[j-1]["distance"]))/(float(hit["distance"])-float(points[j-1]["distance"])),0.00001,1)
				b = a.lerp(b,fraction)
				var delta: Vector3 = b-a
				if delta.length_squared() < 0.00000001:
					stem_node.multimesh.set_instance_transform(cursor,hidden)
				else:
					var basis_: Basis = Basis(Quaternion(Vector3.UP,delta.normalized())).scaled(Vector3(1,delta.length(),1))
					stem_node.multimesh.set_instance_transform(cursor,Transform3D(basis_,(a+b)*0.5))
			cursor += 1

	pose_signature = str(pose_rows).sha256_text()

func layout_signature() -> String:
	return str(grass_candidates,paths).sha256_text()

func _register_point(points: Array[Dictionary], hit: Dictionary, uv: Vector2) -> void:
	hit["position"] += hit["normal"]*0.22
	hit["u"] = uv.x
	hit["v"] = uv.y
	hit["distance"] = 0.0 if points.is_empty() else float(points[-1]["distance"])+Vector3(points[-1]["position"]).distance_to(hit["position"])
	points.append(hit)

func _add_path(points: Array[Dictionary], surface: Dictionary, start: float, parent_index: int, junction: int) -> void:
	if points.size()<2:
		return
	var length_: float = points[-1]["distance"]
	paths.append({"points":points,"surface":surface,"length":length_,"start":start,"parent":parent_index,"junction":junction})
	duration = maxf(duration,start+length_+0.24)
