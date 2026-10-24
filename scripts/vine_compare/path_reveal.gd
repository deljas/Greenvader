extends RefCounted
## Comparison-only inferred growth. Geometry and materials are never authored here.
## Graph edges come from delivered triangles; virtual edges use metadata roots /
## junctions, otherwise nearest stem attachment. Finished state uses original Mesh.
var records: Array[Dictionary] = []
var points: Array[Vector3] = []
var graph: Array[Array] = []
var components: Array[Dictionary] = []
var distances: PackedFloat32Array = PackedFloat32Array()
var heap: Array[Vector2] = []
var root_point: Vector3 = Vector3.ZERO
var root_vertex: int = -1
var maximum: float = 0
var triangle_count: int = 0
var shown_triangles: int = 0
var metadata_links: int = 0
var estimated_links: int = 0
var progress: float = 100

static func vector(value: Variant, fallback: Vector3 = Vector3.ZERO) -> Vector3:
	if value is Array and value.size()==3 and (value[0] is float or value[0] is int):
		return Vector3(value[0],value[1],value[2])
	return fallback

func _edge(a: int, b: int, extra: float = 0.0) -> void:
	if a==b: return
	var length_: float = maxf(points[a].distance_to(points[b])+extra,0.00001)
	graph[a].append(Vector2(b,length_))
	graph[b].append(Vector2(a,length_))

func setup(model: Node3D, metadata: Dictionary) -> void:
	var connections: Dictionary = metadata.get("connections",{})
	root_point = vector(connections.get("root"))
	root_point = vector(connections.get("parent_socket"),root_point)
	var descriptions: Dictionary = {}
	for description: Dictionary in metadata.get("meshes",[]):
		descriptions[String(description.get("name","")).to_lower()] = description.get("layer","")
	for node: Node in model.find_children("*","MeshInstance3D",true,false):
		var instance: MeshInstance3D = node as MeshInstance3D
		if instance.mesh==null: continue
		var mesh: Mesh = instance.mesh
		var label: String = String(instance.name).to_lower()
		var layer: String = descriptions.get(label,label)
		var foliage: bool = "leav" in layer or "leaf" in layer or "lamina" in label or "foliage" in label or "petiole" in label or "flower" in layer or "fruit" in layer
		var record: Dictionary = {"node":instance,"original":mesh,"layer":layer,"name":label,"foliage":foliage,"surfaces":[],"ids":[]}
		var transform_: Transform3D = model.global_transform.affine_inverse()*instance.global_transform
		var welded: Dictionary = {}
		for surface: int in range(mesh.get_surface_count()):
			var arrays: Array = mesh.surface_get_arrays(surface)
			if mesh.surface_get_primitive_type(surface)!=Mesh.PRIMITIVE_TRIANGLES: continue
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var mapping: PackedInt32Array = PackedInt32Array()
			for vertex: Vector3 in vertices:
				var p: Vector3 = transform_*vertex
				var key: Vector3i = Vector3i((p*10000).round())
				if not welded.has(key):
					welded[key] = points.size()
					points.append(p)
					graph.append([])
					record["ids"].append(points.size()-1)
				mapping.append(welded[key])
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			if indices.is_empty():
				for i: int in range(vertices.size()): indices.append(i)
			for i: int in range(0,indices.size()-2,3):
				var a: int = mapping[indices[i]]
				var b: int = mapping[indices[i+1]]
				var c: int = mapping[indices[i+2]]
				_edge(a,b)
				_edge(b,c)
				_edge(c,a)
				triangle_count += 1
			record["surfaces"].append({"arrays":arrays,"indices":indices,"mapping":mapping,"material":mesh.surface_get_material(surface)})
		records.append(record)
	if points.is_empty(): return
	var visited: Dictionary = {}
	for record_index: int in range(records.size()):
		var record: Dictionary = records[record_index]
		for id_: int in record["ids"]:
			if visited.has(id_): continue
			var queue: Array[int] = [id_]
			var ids: Array[int] = []
			visited[id_] = true
			var cursor: int = 0
			var center: Vector3 = Vector3.ZERO
			while cursor<queue.size():
				var current: int = queue[cursor]
				cursor += 1
				ids.append(current)
				center += points[current]
				for edge: Vector2 in graph[current]:
					var other: int = int(edge.x)
					if not visited.has(other):
						visited[other] = true
						queue.append(other)
			components.append({"ids":ids,"record":record_index,"center":center/ids.size(),"foliage":record["foliage"]})
	# Connect structural components before foliage. Explicit metadata branches
	# constrain parent choice; unavailable/ambiguous parents use bounded nearest
	# attachment instead. No recursive parent walk (cycles cannot loop).
	var stems: Array[int] = []
	var foliage: Array[int] = []
	for i: int in range(components.size()):
		if components[i]["foliage"]: foliage.append(i)
		else: stems.append(i)
	if stems.is_empty():
		stems.append(foliage.pop_front())
	stems.sort_custom(func(a: int,b: int) -> bool:
		return _distance_to_component(root_point,components[a])<_distance_to_component(root_point,components[b]))
	var connected: Array[int] = []
	var structural: Array[int] = []
	for component_index: int in stems:
		var component: Dictionary = components[component_index]
		var record: Dictionary = records[component["record"]]
		var hint: Dictionary = _hint(record,connections)
		var attachment: Vector3 = hint.get("point",root_point)
		var own: int = _nearest(attachment,component["ids"])
		if connected.is_empty():
			root_vertex = own
		else:
			var candidates: Array[int] = connected
			if hint.has("parent"):
				var explicit: Array[int] = []
				for previous: int in structural:
					var parent_record: Dictionary = records[components[previous]["record"]]
					if _matches(parent_record,hint["parent"]): explicit.append_array(components[previous]["ids"])
				if not explicit.is_empty(): candidates = explicit
			if hint.has("point"):
				metadata_links += 1
			else:
				# Closest structural attachment near this component's root end.
				attachment = points[own]
				estimated_links += 1
			var parent: int = _nearest(attachment,candidates)
			_edge(parent,own)
		connected.append_array(component["ids"])
		structural.append(component_index)
	for component_index: int in foliage:
		var component: Dictionary = components[component_index]
		var parent: int = _nearest(component["center"],connected)
		var own: int = _nearest(points[parent],component["ids"])
		# A short explicit delay follows the attached stem instead of revealing
		# remote leaves at the same moment as their root.
		_edge(parent,own,0.12)
		estimated_links += 1
	_dijkstra()
	for record: Dictionary in records:
		for surface: Dictionary in record["surfaces"]:
			var thresholds: PackedFloat32Array = PackedFloat32Array()
			var indices: PackedInt32Array = surface["indices"]
			var mapping: PackedInt32Array = surface["mapping"]
			for i: int in range(0,indices.size()-2,3):
				thresholds.append(maxf(distances[mapping[indices[i]]],maxf(distances[mapping[indices[i+1]]],distances[mapping[indices[i+2]]])))
			surface["thresholds"] = thresholds
	set_growth(100)

func _matches(record: Dictionary, label: String) -> bool:
	var needle: String = label.to_lower()
	return record["layer"]==needle or record["name"]==needle or String(record["name"]).ends_with("_"+needle)

func _hint(record: Dictionary, connections: Dictionary) -> Dictionary:
	for value: Variant in connections.get("branches",[]):
		if not value is Dictionary: continue
		var branch: Dictionary = value
		if not _matches(record,String(branch.get("layer",branch.get("name","")))): continue
		var result: Dictionary = {}
		if branch.get("root_glb") is Array: result["point"] = vector(branch["root_glb"])
		elif branch.get("connection") is Array: result["point"] = vector(branch["connection"])
		var parent: Variant = branch.get("parent")
		if parent is String: result["parent"] = parent
		elif parent is Dictionary:
			result["parent"] = String(parent.get("parent",""))
			if not result.has("point") and parent.get("point_blender") is Array:
				var b: Vector3 = vector(parent["point_blender"])
				result["point"] = Vector3(b.x,b.z,-b.y)
		return result
	for value: Variant in connections.get("path_connections",[]):
		if not value is Dictionary: continue
		if _matches(record,String(value.get("branch",""))):
			return {"point":vector(value.get("junction")),"parent":String(value.get("parent",""))}
	return {}

func _distance_to_component(p: Vector3, component: Dictionary) -> float:
	return points[_nearest(p,component["ids"])].distance_squared_to(p)

func _nearest(p: Vector3, ids: Array) -> int:
	var result: int = ids[0]
	var best: float = INF
	for id_: int in ids:
		var distance: float = p.distance_squared_to(points[id_])
		if distance<best:
			best = distance
			result = id_
	return result

func _push(value: Vector2) -> void:
	heap.append(value)
	var i: int = heap.size()-1
	while i>0:
		var parent: int = (i-1)/2
		if heap[parent].x<=value.x: break
		heap[i] = heap[parent]
		i = parent
	heap[i] = value

func _pop() -> Vector2:
	var result: Vector2 = heap[0]
	var last: Vector2 = heap.pop_back()
	if heap.is_empty(): return result
	var i: int = 0
	while i*2+1<heap.size():
		var child: int = i*2+1
		if child+1<heap.size() and heap[child+1].x<heap[child].x: child += 1
		if heap[child].x>=last.x: break
		heap[i] = heap[child]
		i = child
	heap[i] = last
	return result

func _dijkstra() -> void:
	distances.resize(points.size())
	distances.fill(INF)
	distances[root_vertex] = 0
	_push(Vector2(0,root_vertex))
	while not heap.is_empty():
		var item: Vector2 = _pop()
		var current: int = int(item.y)
		if item.x>distances[current]+0.00001: continue
		for edge: Vector2 in graph[current]:
			var other: int = int(edge.x)
			var candidate: float = item.x+edge.y
			if candidate<distances[other]:
				distances[other] = candidate
				_push(Vector2(candidate,other))
	for distance: float in distances:
		if is_finite(distance): maximum = maxf(maximum,distance)

func set_growth(value: float) -> void:
	progress = clampf(value,0,100)
	shown_triangles = 0
	for record: Dictionary in records:
		var node: MeshInstance3D = record["node"]
		if progress>=100:
			node.visible = true
			node.mesh = record["original"]
			continue
		if progress<=0:
			node.visible = false
			continue
		var growing: ArrayMesh = ArrayMesh.new()
		for surface: Dictionary in record["surfaces"]:
			var indices: PackedInt32Array = surface["indices"]
			var thresholds: PackedFloat32Array = surface["thresholds"]
			var visible_indices: PackedInt32Array = PackedInt32Array()
			for i: int in range(thresholds.size()):
				if thresholds[i]<=maximum*progress/100:
					visible_indices.append(indices[i*3])
					visible_indices.append(indices[i*3+1])
					visible_indices.append(indices[i*3+2])
			if visible_indices.is_empty(): continue
			var arrays: Array = surface["arrays"].duplicate()
			arrays[Mesh.ARRAY_INDEX] = visible_indices
			growing.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
			growing.surface_set_material(growing.get_surface_count()-1,surface["material"])
			shown_triangles += visible_indices.size()/3
		node.visible = growing.get_surface_count()>0
		if node.visible: node.mesh = growing
	if progress>=100: shown_triangles = triangle_count

func snapshot() -> Dictionary:
	return {"vertices":points.size(),"components":components.size(),"triangles":triangle_count,"shown_triangles":shown_triangles,"metadata_links":metadata_links,"estimated_links":estimated_links,"root":str(root_point),"root_vertex":root_vertex,"distance":maximum,"progress":progress}
