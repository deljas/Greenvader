extends Node3D
## POC-02 display layer for a placement: one holder per instance (feet origin aligned like the town lab: AABB centre
## on x/z, bottom at y=0), per-instance material copies (so alpha / growth of one instance never touches the others
## that share the same GLB), decorative puddles and an optional obstacle-cell debug overlay.
const Config: GDScript = preload("res://scripts/poc/poc_config.gd")
const Coords: GDScript = preload("res://scripts/poc/poc_coords.gd")

var placement: RefCounted
## instance_id -> Node3D holder (position = placement pos, rotation.y = yaw).
var holders: Dictionary = {}
## instance_id -> Array[BaseMaterial3D] (surface override copies owned by that instance only).
var materials: Dictionary = {}
var overlay: MeshInstance3D
## POC-06: depth handling of a faded instance's own material copies (single-layer look instead of back faces showing
## through). Restored together with transparency when the instance is opaque again. Set from data/poc/occlusion.json.
var fade_depth_draw_mode: int = BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY
var fade_transparency_mode: int = BaseMaterial3D.TRANSPARENCY_ALPHA

func build(source: RefCounted) -> void:
	placement = source
	for child: Node in get_children():
		child.queue_free()
	holders.clear()
	materials.clear()
	overlay = null
	for inst: Dictionary in placement.instances:
		if inst["kind"] == "puddle":
			_add_puddle(inst)
		else:
			_add_model(inst)

func _add_model(inst: Dictionary) -> void:
	var entry: Dictionary = placement.catalog[inst["asset"]]
	var shape: Dictionary = placement.asset_shape(inst["asset"])
	var scene: PackedScene = load(entry["glb"]) as PackedScene
	var holder: Node3D = Node3D.new()
	holder.name = inst["id"]
	add_child(holder)
	var model: Node3D = scene.instantiate() as Node3D
	model.position = shape["offset"]
	holder.add_child(model)
	holders[inst["id"]] = holder
	materials[inst["id"]] = _own_materials(model)
	_place_holder(inst)

func _place_holder(inst: Dictionary) -> void:
	var holder: Node3D = holders[inst["id"]]
	var pos: Vector2 = inst["pos"]
	holder.position = Vector3(pos.x, 0.0, pos.y)
	holder.rotation = Vector3(0.0, inst["yaw"], 0.0)

## Gives every mesh surface of this instance its own material copy. Returns the copies.
func _own_materials(model: Node3D) -> Array:
	var own: Array = []
	for child: Node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance: MeshInstance3D = child as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		for surface: int in mesh_instance.mesh.get_surface_count():
			var source: Material = mesh_instance.get_active_material(surface)
			if source is BaseMaterial3D:
				var copy: BaseMaterial3D = (source as BaseMaterial3D).duplicate() as BaseMaterial3D
				copy.set_meta(&"base_alpha", copy.albedo_color.a)
				copy.set_meta(&"base_transparency", copy.transparency)
				copy.set_meta(&"base_depth_draw", copy.depth_draw_mode)
				mesh_instance.set_surface_override_material(surface, copy)
				own.append(copy)
	return own

func _add_puddle(inst: Dictionary) -> void:
	var disc: CylinderMesh = CylinderMesh.new()
	disc.top_radius = inst["radius"]
	disc.bottom_radius = inst["radius"]
	disc.height = 0.01
	disc.radial_segments = 24
	disc.rings = 1
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color(0.26, 0.42, 0.52, 0.85)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.roughness = 0.25
	var node: MeshInstance3D = MeshInstance3D.new()
	node.name = inst["id"]
	node.mesh = disc
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pos: Vector2 = inst["pos"]
	node.position = Vector3(pos.x, 0.02, pos.y)
	add_child(node)
	holders[inst["id"]] = node

## Re-applies the instance transforms after Placement.move_instance (visual only).
func refresh_transforms() -> void:
	for inst: Dictionary in placement.instances:
		if holders.has(inst["id"]):
			var node: Node3D = holders[inst["id"]]
			var pos: Vector2 = inst["pos"]
			if inst["kind"] == "puddle":
				node.position = Vector3(pos.x, 0.02, pos.y)
			else:
				_place_holder(inst)

## Per-instance transparency. Only this instance's own material copies change.
func set_instance_alpha(instance_id: String, alpha: float) -> bool:
	if not materials.has(instance_id):
		return false
	for material: BaseMaterial3D in materials[instance_id]:
		var base_alpha: float = material.get_meta(&"base_alpha")
		var color: Color = material.albedo_color
		color.a = base_alpha * clampf(alpha, 0.0, 1.0)
		material.albedo_color = color
		if alpha < 0.999:
			material.transparency = fade_transparency_mode
			material.depth_draw_mode = fade_depth_draw_mode
		else:
			material.transparency = material.get_meta(&"base_transparency")
			material.depth_draw_mode = material.get_meta(&"base_depth_draw")
	return true

func instance_alpha(instance_id: String) -> float:
	if not materials.has(instance_id) or (materials[instance_id] as Array).is_empty():
		return -1.0
	return (materials[instance_id][0] as BaseMaterial3D).albedo_color.a

## Instance ids of all material copies of an instance (for isolation checks).
func material_ids(instance_id: String) -> PackedInt64Array:
	var ids: PackedInt64Array = PackedInt64Array()
	for material: Material in materials.get(instance_id, []):
		ids.append(material.get_instance_id())
	return ids

## Translucent red quads on every obstacle cell (debug picture of the logical obstacle layer).
func set_overlay(visible_: bool) -> void:
	if overlay != null:
		overlay.queue_free()
		overlay = null
	if not visible_:
		return
	var vertices: PackedVector3Array = PackedVector3Array()
	var colors: PackedColorArray = PackedColorArray()
	var indices: PackedInt32Array = PackedInt32Array()
	var cell: float = Config.CELL_M
	for y: int in placement.height:
		for x: int in placement.width:
			var index: int = y * placement.width + x
			var color: Color
			if placement.obstacle[index] == 1:
				color = Color(0.95, 0.15, 0.1, 0.55)
			elif placement.puddle[index] == 1:
				color = Color(0.2, 0.5, 0.95, 0.45)
			else:
				continue
			var x0: float = Coords.ORIGIN.x + float(x) * cell
			var z0: float = Coords.ORIGIN.y + float(y) * cell
			var base: int = vertices.size()
			vertices.append(Vector3(x0, 0.06, z0))
			vertices.append(Vector3(x0 + cell, 0.06, z0))
			vertices.append(Vector3(x0 + cell, 0.06, z0 + cell))
			vertices.append(Vector3(x0, 0.06, z0 + cell))
			for k: int in 4:
				colors.append(color)
			indices.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))
	var data: Array = []
	data.resize(Mesh.ARRAY_MAX)
	data[Mesh.ARRAY_VERTEX] = vertices
	data[Mesh.ARRAY_COLOR] = colors
	data[Mesh.ARRAY_INDEX] = indices
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, data)
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0, material)
	overlay = MeshInstance3D.new()
	overlay.name = "ObstacleOverlay"
	overlay.mesh = mesh
	overlay.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(overlay)
