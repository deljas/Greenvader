extends SceneTree
## Attempted mature mesh readback without placement/exclusion helpers.
## NOT_RUN: the headless run returned unusable identity/origin-like MultiMesh
## transforms for all growth stages. Do not interpret its raw metrics as game
## failures or verified geometry. See independent/report.md. No retry performed.
const Defs = preload("res://scripts/vegetation_lab/building_defs.gd")
const Parts = preload("res://scripts/vegetation_lab/plant_parts.gd")
const Patch = preload("res://scripts/vegetation_lab/growth_patch.gd")
var summaries: Array[Dictionary] = []

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var library: RefCounted = Parts.new()
	for definition: Dictionary in Defs.all():
		var patch: Node3D = Patch.new()
		patch.setup(definition,library)
		var growth: Array[Dictionary] = []
		for percentage: int in [0,50,100]:
			patch.set_growth(percentage)
			var visible: int = 0
			var highest: float = 0
			for i: int in patch.leaf_node.multimesh.instance_count:
				var t: Transform3D = patch.leaf_node.multimesh.get_instance_transform(i)
				if t.basis.get_scale().length() > 0.01:
					visible += 1
					highest = maxf(highest,t.origin.y)
			growth.append({"percentage":percentage,"visible_leaf_clusters":visible,"highest_leaf_center":highest})
		var corridor: Dictionary = definition["walkway"]
		var start: Vector2 = corridor["from"]
		var direction: Vector2 = Vector2(corridor["to"])-start
		var min_clearance: float = INF
		var grass_violations: int = 0
		var vertex_count: int = 0
		for node: MultiMeshInstance3D in patch.grass_nodes:
			var vertices: PackedVector3Array = node.multimesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			for i: int in node.multimesh.instance_count:
				var t: Transform3D = node.multimesh.get_instance_transform(i)
				if t.basis.get_scale().length() < 0.01:
					continue
				for v: Vector3 in vertices:
					var actual: Vector3 = t*v
					var p: Vector2 = Vector2(actual.x,actual.z)
					var along: float = clampf((p-start).dot(direction)/direction.length_squared(),0,1)
					var clearance: float = (p-start-direction*along).length()-float(corridor["half_width"])
					min_clearance = minf(min_clearance,clearance)
					if clearance < -0.0001:
						grass_violations += 1
					vertex_count += 1
		var opening_hits: int = 0
		var wall_points: int = 0
		var minimum_surface_clearance: float = INF
		var leaf_vertices: PackedVector3Array = library.leaves.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var cursor: int = 0
		for path: Dictionary in patch.paths:
			var surface: Dictionary = path["surface"]
			for hit: Dictionary in path["points"]:
				var t: Transform3D = patch.leaf_node.multimesh.get_instance_transform(cursor)
				cursor += 1
				if t.basis.get_scale().length() < 0.01 or hit["distance"] > surface["height"]:
					continue
				for v: Vector3 in leaf_vertices:
					var actual: Vector3 = t*v
					var u: float
					var clearance: float
					if surface["kind"] == "cylinder":
						u = fposmod(atan2(actual.x,actual.z),TAU)*float(definition["radius"])
						clearance = Vector2(actual.x,actual.z).length()-float(definition["radius"])
					else:
						u = (actual-Vector3(surface["origin"])).dot(surface["tangent"])
						clearance = (actual-Vector3(surface["origin"])).dot(surface["normal"])-0.11
					minimum_surface_clearance = minf(minimum_surface_clearance,clearance)
					for hole: Rect2 in surface["holes"]:
						if u >= hole.position.x and u <= hole.end.x and actual.y >= hole.position.y and actual.y <= hole.end.y:
							opening_hits += 1
					wall_points += 1
		summaries.append({"building":definition["id"],"growth":growth,"grass_vertices":vertex_count,"grass_corridor_violations":grass_violations,"minimum_grass_corridor_clearance":min_clearance,"mature_wall_leaf_vertices":wall_points,"opening_projection_hits":opening_hits,"minimum_wall_leaf_surface_clearance":minimum_surface_clearance})
		patch.free()
	var file: FileAccess = FileAccess.open("res://evidence/vegetation-lab/independent/geometry-checks.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"method":"headless actual mature vertices; independent segment distance and opening projection, no Geometry helpers","buildings":summaries},"\t"))
	file.close()
	print(JSON.stringify(summaries))
	quit()
