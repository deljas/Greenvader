extends Node3D
## POC-05 display of the wall vegetation (vines + moss). Reads the WallGrowth state only (never writes it). Each building
## instance gets its own Node3D group "WallVeg_<instance_id>" (separate from the building node; POC-06 can follow the
## instance's transparency by instance_id). Chart-local points are placed with the holder's position/yaw and the model's
## centring offset, exactly like PlacementView. Shared meshes/materials; the moss meshes carry a per-patch coverage parameter.
const Parts: GDScript = preload("res://scripts/poc/environment/wall_parts.gd")
const Layout: GDScript = preload("res://scripts/poc/environment/wall_layout.gd")
const MossShader: Shader = preload("res://scripts/poc/environment/wall_moss.gdshader")

var growth: RefCounted
var parts: RefCounted = Parts.new()
var tuning: Dictionary = {}
## instance_id -> {group: Node3D, leaves: MultiMeshInstance3D, stems: MultiMeshInstance3D, moss: Array[ShaderMaterial], progress: Dictionary}
var groups: Dictionary = {}
var _seen_serial: int = -1
var redraws: int = 0

func build(source: RefCounted, wall_tuning: Dictionary) -> void:
	growth = source
	tuning = wall_tuning
	for child: Node in get_children():
		child.queue_free()
	groups.clear()
	for entry: Dictionary in growth.entries:
		_build_entry(entry)
	_seen_serial = -1
	sync()

func _instances(parent: Node3D, mesh: Mesh, material_: Material, count: int) -> MultiMeshInstance3D:
	var node: MultiMeshInstance3D = MultiMeshInstance3D.new()
	var mm: MultiMesh = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = count
	node.multimesh = mm
	node.material_override = material_
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	return node

func _build_entry(entry: Dictionary) -> void:
	var group: Node3D = Node3D.new()
	group.name = "WallVeg_" + String(entry["id"])
	group.position = Vector3(entry["pos"].x, 0.0, entry["pos"].y)
	group.rotation = Vector3(0.0, float(entry["yaw"]), 0.0)
	add_child(group)
	var frame: Node3D = Node3D.new()
	frame.name = "Frame"
	frame.position = entry["offset"]
	group.add_child(frame)
	var point_count: int = 0
	for path: Dictionary in entry["paths"]:
		point_count += (path["points"] as Array).size()
	var record: Dictionary = {
		"group": group,
		"leaves": _instances(frame, parts.leaves, parts.foliage_material, point_count),
		"stems": _instances(frame, parts.stem, parts.stem_material, point_count),
		"moss": [] as Array[ShaderMaterial],
		"points": point_count,
	}
	var moss_off: float = float(tuning.get("moss_stand_off_m", 0.03))
	for patch: Dictionary in entry["patches"]:
		var material_: ShaderMaterial = ShaderMaterial.new()
		material_.shader = MossShader
		material_.set_shader_parameter("coverage", 0.0)
		var mesh: ArrayMesh = _moss_mesh(entry["surfaces"][int(patch["surface"])], patch, moss_off)
		if mesh != null:
			var node: MeshInstance3D = MeshInstance3D.new()
			node.mesh = mesh
			node.material_override = material_
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			frame.add_child(node)
		record["moss"].append(material_)
	groups[entry["id"]] = record

func _moss_mesh(surface: Dictionary, patch: Dictionary, stand_off: float) -> ArrayMesh:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var span: Vector2 = patch["span"]
	var divisions: int = Layout.moss_divisions(span)
	var added: int = 0
	for row: int in divisions:
		for col: int in divisions:
			var corners: Array[Dictionary] = []
			var valid: bool = true
			for xy: Vector2 in [Vector2(col, row), Vector2(col + 1, row), Vector2(col + 1, row + 1), Vector2(col, row + 1)]:
				var uv: Vector2 = Layout.moss_uv(patch["center"], span, divisions, xy)
				if not Layout.moss_corner_ok(surface, uv):
					valid = false
				var hit: Dictionary = Layout.sample(surface, uv.x, uv.y)
				hit["position"] += hit["normal"] * stand_off
				hit["uv"] = xy / float(divisions)
				hit["uv2"] = uv + (patch["phase"] as Vector2)
				corners.append(hit)
			if not valid:
				continue
			for index: int in [0, 2, 1, 0, 3, 2]:
				var vertex: Dictionary = corners[index]
				st.set_normal(vertex["normal"])
				st.set_uv(vertex["uv"])
				st.set_uv2(vertex["uv2"])
				st.add_vertex(vertex["position"])
				added += 1
	return st.commit() if added > 0 else null

## Redraws only when the growth state changed.
func sync() -> void:
	if growth == null or growth.serial == _seen_serial:
		return
	_seen_serial = growth.serial
	redraws += 1
	var hidden: Transform3D = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 0.00001), Vector3.ZERO)
	var leaf_size: float = float(tuning.get("leaf_scale", 0.85))
	var stem_size: float = float(tuning.get("stem_scale", 1.8))
	for entry: Dictionary in growth.entries:
		var record: Dictionary = groups[entry["id"]]
		var progress: Dictionary = {}
		for root: Dictionary in entry["roots"]:
			progress[int(root["path"])] = float(root["progress"])
		var leaves: MultiMesh = (record["leaves"] as MultiMeshInstance3D).multimesh
		var stems: MultiMesh = (record["stems"] as MultiMeshInstance3D).multimesh
		var cursor: int = 0
		for path_index: int in entry["paths"].size():
			var path: Dictionary = entry["paths"][path_index]
			var points: Array = path["points"]
			var root: int = path_index if int(path["parent"]) < 0 else int(path["parent"])
			var grown: float = float(progress.get(root, 0.0)) * float(entry["durations"][root]) - float(path["start"])
			for j: int in points.size():
				var hit: Dictionary = points[j]
				var leaf_scale: float = clampf((grown - float(hit["distance"])) / 0.24, 0.00001, 1.0)
				if j % 4 == 0:
					var leaf_basis: Basis = Parts.facing(hit["normal"]) * Basis(Vector3.FORWARD, float(j) * 0.8)
					leaves.set_instance_transform(cursor, Transform3D(leaf_basis.scaled(Vector3.ONE * leaf_scale * leaf_size), hit["position"]))
				else:
					leaves.set_instance_transform(cursor, hidden)
				if j == 0:
					stems.set_instance_transform(cursor, hidden)
				else:
					var a: Vector3 = points[j - 1]["position"]
					var span: float = float(hit["distance"]) - float(points[j - 1]["distance"])
					var fraction: float = clampf((grown - float(points[j - 1]["distance"])) / maxf(span, 0.000001), 0.00001, 1.0)
					var b: Vector3 = a.lerp(hit["position"], fraction)
					var delta: Vector3 = b - a
					if delta.length_squared() < 0.00000001:
						stems.set_instance_transform(cursor, hidden)
					else:
						stems.set_instance_transform(cursor, Transform3D(Basis(Quaternion(Vector3.UP, delta.normalized())).scaled(Vector3(stem_size, delta.length(), stem_size)), (a + b) * 0.5))
				cursor += 1
		var materials: Array = record["moss"]
		for i: int in entry["moss"].size():
			(materials[i] as ShaderMaterial).set_shader_parameter("coverage", clampf(float(entry["moss"][i]["progress"]), 0.0, 1.0))

## Instance ids that have vegetation (POC-06 follows the building's occlusion per instance_id).
func instance_ids() -> PackedStringArray:
	var ids: PackedStringArray = []
	for id: Variant in groups.keys():
		ids.append(String(id))
	return ids

func group_of(instance_id: String) -> Node3D:
	return (groups[instance_id]["group"] as Node3D) if groups.has(instance_id) else null
