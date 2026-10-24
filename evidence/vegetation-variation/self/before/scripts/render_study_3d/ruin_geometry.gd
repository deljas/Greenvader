extends RefCounted
## Small original 3D ruin. Geometry, not a billboard or a baked illustration.
const Surface: Shader = preload("res://assets/render_study_3d/concrete.gdshader")

static func material(color: Color, kind: float = 0.0) -> ShaderMaterial:
	var result: ShaderMaterial = ShaderMaterial.new()
	result.shader = Surface
	result.set_shader_parameter("base_color", color)
	result.set_shader_parameter("surface_kind", kind)
	return result

static func box(parent: Node3D, label: String, center: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	var node: MeshInstance3D = MeshInstance3D.new()
	node.name = label
	node.mesh = mesh
	node.material_override = mat
	node.position = center
	parent.add_child(node)
	return node

static func build(parent: Node3D) -> Dictionary:
	var concrete: ShaderMaterial = material(Color("a1a393"))
	var roof_mat: ShaderMaterial = material(Color("898f80"))
	var recess: ShaderMaterial = material(Color("303a35"))
	var metal: ShaderMaterial = material(Color("6d8182"), 2.0)
	var rust: ShaderMaterial = material(Color("78624c"), 2.0)
	var ground: Node3D = Node3D.new()
	ground.name = "GroundAndPavement"
	parent.add_child(ground)
	box(ground, "Soil", Vector3(0, -0.17, 0), Vector3(45, 0.25, 45), material(Color("626f55"), 3.0))
	box(ground, "RegularPavingGrid", Vector3(0.0, -0.025, 0.1), Vector3(13.76, 0.08, 12.04), material(Color("727b71"), 1.0))
	var walls: Node3D = Node3D.new()
	walls.name = "StructuralWalls"
	parent.add_child(walls)
	# Openings are absent geometry, with thickness reveals and a pane recessed
	# behind the outer face. They cast/receive real directional-light shadows.
	_wall(walls, true, 2.4, 6.0, [Rect2(-2.45, 0.92, 1.38, 1.20), Rect2(0.55, 0.12, 1.28, 2.11)], concrete)
	_wall(walls, false, 3.0, 4.8, [Rect2(-1.55, 0.92, 1.22, 1.20), Rect2(0.68, 0.92, 1.04, 1.20)], concrete)
	box(walls, "BackWall", Vector3(0, 1.4, -2.4), Vector3(6, 2.8, 0.30), concrete)
	box(walls, "LeftWall", Vector3(-3.0, 1.4, 0), Vector3(0.30, 2.8, 4.8), concrete)
	_window(walls, true, 2.4, -1.76, 1.38, concrete, recess, rust)
	_window(walls, false, 3.0, -0.94, 1.22, concrete, recess, rust)
	_window(walls, false, 3.0, 1.20, 1.04, concrete, recess, rust)
	var door: Node3D = Node3D.new()
	door.name = "ClosedRustedDoor"
	parent.add_child(door)
	box(door, "RecessedSteel", Vector3(1.19, 1.14, 2.30), Vector3(1.19, 2.04, 0.08), metal)
	for x: float in [0.55, 1.83]:
		box(door, "Frame", Vector3(x, 1.15, 2.44), Vector3(0.07, 2.16, 0.15), rust)
	box(door, "LintelWithOverhang", Vector3(1.19, 2.30, 2.45), Vector3(1.65, 0.17, 0.58), concrete)
	box(door, "HandlePlate", Vector3(1.59, 1.10, 2.36), Vector3(0.09, 0.20, 0.045), rust)
	box(door, "Handle", Vector3(1.54, 1.12, 2.40), Vector3(0.16, 0.035, 0.065), rust)
	for y: float in [0.43, 1.80]:
		box(door, "Hinge", Vector3(0.66, y, 2.38), Vector3(0.07, 0.17, 0.055), rust)
	box(door, "UpperStep", Vector3(1.19, 0.10, 2.78), Vector3(1.61, 0.20, 0.62), concrete)
	box(door, "LowerStep", Vector3(1.19, 0.035, 3.16), Vector3(1.93, 0.10, 0.38), concrete)
	var roof: Node3D = Node3D.new()
	roof.name = "ChippedRoofAndParapet"
	parent.add_child(roof)
	var outline: PackedVector2Array = PackedVector2Array([Vector2(-3.22,-2.62), Vector2(3.22,-2.62), Vector2(3.22,1.55), Vector2(2.94,1.64), Vector2(2.88,1.94), Vector2(2.44,2.10), Vector2(2.32,2.62), Vector2(-0.75,2.62), Vector2(-0.83,2.45), Vector2(-1.18,2.44), Vector2(-1.35,2.62), Vector2(-3.22,2.62)])
	_prism(roof, "RealMissingCornerSlab", outline, 2.72, 0.24, roof_mat)
	# Several independent irregular parapet segments and exposed reinforcement.
	for i: int in 9:
		var x: float = -2.92 + float(i) * 0.66
		var h: float = 0.23 + float((i * 7) % 4) * 0.045
		if i != 3 and i != 7:
			box(roof, "FrontParapet", Vector3(x, 2.96 + h * 0.5, 2.47), Vector3(0.61, h, 0.23), concrete)
		box(roof, "BackParapet", Vector3(x, 3.09, -2.48), Vector3(0.62, 0.26, 0.23), concrete)
	for side: float in [-1.0, 1.0]:
		for i: int in 6:
			if side > 0 and i > 3:
				continue
			box(roof, "SideParapet", Vector3(side * 3.07, 3.07 + float(i % 3) * 0.035, -2.1 + float(i) * 0.77), Vector3(0.23, 0.24 + float(i % 3) * 0.07, 0.69), concrete)
	for x: float in [-2.70, -2.48, 1.69, 1.84]:
		var rod: MeshInstance3D = box(roof, "ExposedRebar", Vector3(x, 3.33, 2.45), Vector3(0.035, 0.75, 0.035), rust)
		rod.rotation.z = 0.13 if x < 0 else -0.06
	var rubble: Node3D = Node3D.new()
	rubble.name = "SeparateRubble"
	parent.add_child(rubble)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 301035
	for i: int in 24:
		var x: float = rng.randf_range(-3.9, 3.9)
		var z: float = rng.randf_range(2.85, 3.75) if i < 15 else rng.randf_range(-2.3, 2.5)
		if i >= 15:
			x = 3.5 + rng.randf_range(-0.1, 0.65)
		if x > 0.05 and x < 2.15 and z > 2.7:
			continue
		var w: float = rng.randf_range(0.16, 0.46)
		var h: float = rng.randf_range(0.12, 0.30)
		var piece: MeshInstance3D = box(rubble, "ConcreteFragment", Vector3(x, h * 0.5 + 0.02, z), Vector3(w, h, w * 0.7), concrete)
		piece.rotation = Vector3(rng.randf_range(-0.2, 0.2), rng.randf_range(-1.5, 1.5), rng.randf_range(-0.14, 0.14))
	_build_grass(parent)
	return {"walls": walls, "roof": roof, "door": door, "rubble": rubble, "ground": ground}

static func _wall(parent: Node3D, along_x: bool, fixed: float, length_: float, holes: Array[Rect2], mat: Material) -> void:
	var edges: Array[float] = [-length_ * 0.5, length_ * 0.5]
	for hole: Rect2 in holes:
		edges.append(hole.position.x)
		edges.append(hole.end.x)
	edges.sort()
	for i: int in range(edges.size() - 1):
		var left: float = edges[i]
		var right: float = edges[i + 1]
		var center: float = (left + right) * 0.5
		var opening: Rect2 = Rect2()
		for hole: Rect2 in holes:
			if center > hole.position.x and center < hole.end.x:
				opening = hole
		var bands: Array[Vector2] = []
		if opening.size == Vector2.ZERO:
			bands.append(Vector2(0, 2.8))
		else:
			bands.append(Vector2(0, opening.position.y))
			bands.append(Vector2(opening.end.y, 2.8))
		for band: Vector2 in bands:
			var height: float = band.y - band.x
			if height <= 0.001:
				continue
			var pos: Vector3 = Vector3(center, (band.x + band.y) * 0.5, fixed) if along_x else Vector3(fixed, (band.x + band.y) * 0.5, center)
			var size_: Vector3 = Vector3(right-left, height, 0.30) if along_x else Vector3(0.30, height, right-left)
			box(parent, "WallOpeningBand", pos, size_, mat)

static func _window(parent: Node3D, along_x: bool, fixed: float, center: float, width: float, concrete: Material, recess: Material, metal: Material) -> void:
	var pos: Vector3 = Vector3(center, 1.52, fixed - 0.16) if along_x else Vector3(fixed - 0.16, 1.52, center)
	var size_: Vector3 = Vector3(width - 0.06, 1.16, 0.045) if along_x else Vector3(0.045, 1.16, width - 0.06)
	box(parent, "RecessedDarkWindow", pos, size_, recess)
	var sill: Vector3 = Vector3(center, 0.94, fixed + 0.08) if along_x else Vector3(fixed + 0.08, 0.94, center)
	box(parent, "ProjectingWindowSill", sill, Vector3(width+0.14,0.10,0.48) if along_x else Vector3(0.48,0.10,width+0.14), concrete)
	var mullion: Vector3 = Vector3(center + width * 0.15, 1.52, fixed - 0.08) if along_x else Vector3(fixed - 0.08, 1.52, center + width * 0.15)
	box(parent, "OldWindowMullion", mullion, Vector3(0.045,1.10,0.045), metal)

static func _prism(parent: Node3D, label: String, outline: PackedVector2Array, base: float, thickness: float, mat: Material) -> void:
	var surface: SurfaceTool = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var indices: PackedInt32Array = Geometry2D.triangulate_polygon(outline)
	for i: int in range(0, indices.size(), 3):
		for layer: int in 2:
			var normal: Vector3 = Vector3.UP if layer == 1 else Vector3.DOWN
			for corner: int in 3:
				var idx: int = indices[i + (corner if layer == 1 else 2-corner)]
				var p: Vector2 = outline[idx]
				surface.set_normal(normal)
				surface.add_vertex(Vector3(p.x, base + thickness * layer, p.y))
	for i: int in outline.size():
		var a: Vector2 = outline[i]
		var b: Vector2 = outline[(i+1) % outline.size()]
		var normal: Vector3 = Vector3(b.y-a.y, 0, a.x-b.x).normalized()
		var corners: Array[Vector3] = [Vector3(a.x,base,a.y), Vector3(b.x,base,b.y), Vector3(b.x,base+thickness,b.y), Vector3(a.x,base+thickness,a.y)]
		for index: int in [0, 1, 2, 0, 2, 3]:
			surface.set_normal(normal)
			surface.add_vertex(corners[index])
	var node: MeshInstance3D = MeshInstance3D.new()
	node.name = label
	node.mesh = surface.commit()
	node.material_override = mat
	parent.add_child(node)

static func _build_grass(parent: Node3D) -> void:
	var holder: Node3D = Node3D.new()
	holder.name = "SeparateSmallGrassPatches"
	parent.add_child(holder)
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color("5d8043")
	mat.roughness = 1.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 3301
	for center: Vector3 in [Vector3(-3.45,0.02,2.65), Vector3(-2.80,0.02,3.25), Vector3(3.65,0.02,2.6), Vector3(3.8,0.02,-1.2), Vector3(-4.2,0.02,-2.7), Vector3(2.6,0.02,-3.4)]:
		var st: SurfaceTool = SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for i: int in 28:
			var p: Vector3 = center + Vector3(rng.randf_range(-0.36,0.36),0,rng.randf_range(-0.30,0.30))
			var h: float = rng.randf_range(0.16,0.43)
			var tip: Vector3 = p + Vector3(rng.randf_range(-0.12,0.12),h,rng.randf_range(-0.1,0.1))
			for vertex: Vector3 in [p+Vector3(-0.025,0,0), p+Vector3(0.025,0,0), tip]:
				st.set_normal(Vector3(0.15,0.7,0.6).normalized())
				st.add_vertex(vertex)
		var patch: MeshInstance3D = MeshInstance3D.new()
		patch.mesh = st.commit()
		patch.material_override = mat
		holder.add_child(patch)
