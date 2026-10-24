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
var root_progress: Dictionary = {}
var root_durations: Dictionary = {}
var sparse_windows: bool = false
var leaf_records: Array[Dictionary] = []

func setup(def: Dictionary, library: RefCounted, options: Dictionary = {}) -> void:
	definition = def
	sparse_windows = options.get("sparse_windows",false)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = int(def["seed"])
	var extent: Vector2 = def["extent"]
	for x: int in range(int(-extent.x/0.36),int(extent.x/0.36)):
		for z: int in range(int(-extent.y/0.36),int(extent.y/0.36)):
			var p: Vector2 = Vector2(x*0.36+rng.randf_range(-0.10,0.10),z*0.36+rng.randf_range(-0.10,0.10))
			if Geometry.ground_allowed(def,p):
				grass_candidates.append({"position":Vector3(p.x,0.02,p.y),"angle":rng.randf()*TAU,"threshold":rng.randf()*0.65,"variant":rng.randi_range(0,1)})
	for variant: int in (2 if options.get("include_ground",true) else 0):
		grass_nodes.append(_instances(library.grasses[variant],library.foliage_material,grass_candidates.size()))
	# Separate RNG preserves the existing grass candidates bit-for-bit.
	var vine_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	vine_rng.seed = int(def["seed"])+7109
	var lane: int = 0
	for surface: Dictionary in ([] if sparse_windows else def["surfaces"]):
		var u: float = vine_rng.randf_range(0.24,0.34)
		while u < float(surface["width"])-0.20:
			var amplitude: float = 0.014 if lane%3==0 else vine_rng.randf_range(0.22,0.42)
			var phase: float = vine_rng.randf()*TAU
			var frequency: float = vine_rng.randf_range(1.15,1.85)
			var points: Array[Dictionary] = []
			var length_: float = float(surface["height"])+1.65
			var steps: int = ceili(length_/0.085)
			for step: int in range(steps+1):
				var d: float = float(step)/steps*length_
				var uv: float = clampf(u+amplitude*(sin(d*frequency+phase)-sin(phase)),0.20,float(surface["width"])-0.20)
				# Moving stems are checked at their actual UV, not their original lane.
				if d<=float(surface["height"]) and Geometry.blocked_surface(surface,uv,d,0.34):
					break
				if options.get("walls_only",false) and d>float(surface["height"])-0.34:
					break
				var hit: Dictionary = Geometry.path_sample(def,surface,uv,d)
				if hit.is_empty():
					break
				_register_point(points,hit,Vector2(uv,d))
			if points.size()>4:
				var parent_index: int = paths.size()
				_add_path(points,surface,0.0,-1,-1)
				paths[parent_index]["variation"] = {"amplitude":amplitude,"phase":phase,"frequency":frequency,"root_u":u}
				for height_: float in [0.62,1.38,2.38,3.45,4.35]:
					var branch_height: float = height_+vine_rng.randf_range(-0.16,0.16)
					if branch_height > minf(float(surface["height"])-0.20,float(points[-1]["v"])-0.10):
						continue
					var junction: int = mini(roundi(branch_height/length_*steps),points.size()-1)
					var origin: Dictionary = points[junction]
					for direction: float in [-1.0,1.0]:
						var branch: Array[Dictionary] = [origin.duplicate()]
						branch[0]["distance"] = 0.0
						var count: int = vine_rng.randi_range(10,20)
						var slope: float = vine_rng.randf_range(0.015,0.065)
						var bend: float = vine_rng.randf_range(-0.22,0.22)
						for n: int in range(1,count+1):
							var t: float = float(n)/count
							var bu: float = float(origin["u"])+direction*(n*0.075+sin(t*PI)*bend)
							var bv: float = float(origin["v"])+n*slope+sin(t*TAU)*bend
							if bu<0.18 or bu>float(surface["width"])-0.18 or bv<0.08 or bv>float(surface["height"])-(0.34 if options.get("walls_only",false) else 0.20) or Geometry.blocked_surface(surface,bu,bv,0.34):
								break
							_register_point(branch,Geometry.sample(surface,bu,bv),Vector2(bu,bv))
						if branch.size()>3:
							_add_path(branch,surface,float(origin["distance"]),parent_index,junction)
							paths[-1]["variation"] = {"bend":bend,"slope":slope,"steps":count}
			u += vine_rng.randf_range(0.55,0.88)
			lane += 1
	if sparse_windows:
		_window_routes(def)
	var point_count: int = 0
	for path: Dictionary in paths:
		point_count += path["points"].size()
	for index: int in paths.size():
		var path: Dictionary = paths[index]
		var root: int = index if path["parent"]<0 else int(path["parent"])
		root_durations[root] = maxf(float(root_durations.get(root,0)),float(path["start"])+float(path["length"])+0.24)
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
	for variant: int in grass_nodes.size():
		for i: int in grass_candidates.size():
			var candidate: Dictionary = grass_candidates[i]
			var scale_: float = clampf((progress-float(candidate["threshold"]))/0.35,0.00001,1.0)
			var transform_: Transform3D = Transform3D(Basis(Vector3.UP,candidate["angle"]).scaled(Vector3.ONE*scale_),candidate["position"])
			grass_nodes[variant].multimesh.set_instance_transform(i,transform_ if candidate["variant"]==variant else hidden)
	growth_events.clear()
	leaf_records.clear()
	var cursor: int = 0
	var pose_rows: Array[Transform3D] = []
	for path_index: int in paths.size():
		var path: Dictionary = paths[path_index]
		var points: Array = path["points"]
		var travelled: float = clampf((progress-0.08)/0.92,0,1)*duration
		if not root_progress.is_empty():
			var root: int = path_index if path["parent"]<0 else int(path["parent"])
			travelled = float(root_progress.get(root,0))*float(root_durations[root])
		var grown: float = travelled-float(path["start"])
		growth_events.append({"parent":path["parent"],"start":path["start"],"grown":grown,"junction":path["junction"]})
		for j: int in points.size():
			var hit: Dictionary = points[j]
			var leaf_scale: float = clampf((grown-float(hit["distance"]))/0.24,0.00001,1.0)
			var leaf_basis: Basis = Geometry.facing(hit["normal"])*Basis(Vector3.FORWARD,float(j)*0.8)
			var show_leaf: bool = j%(4 if sparse_windows else 2)==0
			var size_: float = leaf_scale*(0.52 if sparse_windows else 1.0)
			var leaf_transform: Transform3D = Transform3D(leaf_basis.scaled(Vector3.ONE*size_),hit["position"]) if show_leaf else hidden
			if sparse_windows and show_leaf and size_>0.001:
				leaf_records.append({"surface":path["surface"],"transform":leaf_transform,"u":hit["u"],"v":hit["v"]})
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

func set_root_progress(values: Dictionary) -> void:
	root_progress = values.duplicate()
	set_growth(progress*100.0)

func _window_routes(def: Dictionary) -> void:
	# Small-map option: derive a few complete routes from opening charts, never per-leaf data.
	for surface: Dictionary in def["surfaces"]:
		var window_index: int = 0
		var windows: Array[Rect2] = []
		for hole_: Rect2 in surface["holes"]:
			if hole_.position.y>=0.05:
				windows.append(hole_)
		var has_windows: bool = not windows.is_empty()
		if not has_windows:
			windows.append(Rect2(float(surface["width"])*0.42,float(surface["height"])*0.28,0.4,float(surface["height"])*0.50))
		for hole: Rect2 in windows:
			var side: float = -1.0 if window_index%2==0 else 1.0
			var u: float = hole.position.x-0.13 if side<0 else hole.end.x+0.13
			var root_u: float = u
			var clear_height: float = 0.0
			for door: Rect2 in surface["holes"]:
				if door.position.y<0.05 and door.grow(0.30).has_point(Vector2(root_u,0)):
					root_u = door.position.x-0.36 if side<0 else door.end.x+0.36
					clear_height = door.end.y+0.34
			var top: float = minf(hole.end.y+0.16,float(surface["height"])-0.30)
			var points: Array[Dictionary] = []
			var steps: int = ceili(top/0.085)
			for n: int in range(steps+1):
				var v: float = float(n)/steps*top
				var bend: float = sin(v*3.1+window_index*1.7)*0.13 if v<hole.position.y-0.10 else 0.0
				if not has_windows:
					bend = 0.23*(sin(v*2.1+0.8)-sin(0.8))
				# Door bypass needs a quieter lower stem so its leaf radius remains clear.
				if clear_height>0 and v<clear_height:
					bend *= 0.20
				var actual_u: float = lerpf(root_u,u,clampf((v-clear_height)/maxf(0.1,hole.position.y-clear_height),0,1))+bend
				if not _route_safe(surface,Vector2(actual_u,v)):
					break
				_register_point(points,Geometry.sample(surface,actual_u,v),Vector2(actual_u,v))
			if points.size()<5:
				continue
			var parent_index: int = paths.size()
			_add_path(points,surface,0,-1,-1)
			# One branch overlaps only the near edge of the glass; one spreads on the solid wall.
			for branch_index: int in 2:
				var height_: float = hole.position.y+hole.size.y*0.48 if branch_index==0 else 0.55
				var junction: int = mini(roundi(height_/top*steps),points.size()-1)
				var origin: Dictionary = points[junction]
				var branch: Array[Dictionary] = [origin.duplicate()]
				branch[0]["distance"] = 0.0
				var reach: float = minf(0.43,hole.size.x*0.22+0.13) if branch_index==0 and has_windows else 0.63
				var direction: float = -side if branch_index==0 else side
				for n: int in range(1,7):
					var t: float = float(n)/6
					var uv: Vector2 = Vector2(origin["u"]+direction*(reach*t+sin(t*TAU)*0.065),origin["v"]+0.13*t+sin(t*PI)*0.13)
					if not _route_safe(surface,uv):
						break
					_register_point(branch,Geometry.sample(surface,uv.x,uv.y),uv)
				if branch.size()>2:
					_add_path(branch,surface,float(origin["distance"]),parent_index,junction)
			window_index += 1

func _route_safe(surface: Dictionary, uv: Vector2) -> bool:
	if uv.x<0.25 or uv.x>float(surface["width"])-0.25 or uv.y>float(surface["height"])-0.25:
		return false
	for hole: Rect2 in surface["holes"]:
		if hole.position.y<0.05 and hole.grow(0.30).has_point(uv):
			return false
	for awning: Rect2 in surface.get("awnings",[]):
		if awning.grow(0.28).has_point(uv):
			return false
	return true
