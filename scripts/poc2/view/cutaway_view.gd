extends Node
## Display-only cutaway. The original materials and shadows are restored on release.
const Judge: GDScript = preload("res://scripts/poc/occlusion/occlusion.gd")
const Cut: Shader = preload("res://scripts/poc2/view/cutaway.gdshader")
var judge: RefCounted = Judge.new()
var placement_view: Node3D
var camera: Camera3D
var records: Dictionary = {}
var wall_view: Node3D
var last_raw: Dictionary = {}

func setup(placed: Node3D, camera_: Camera3D, walls: Node3D) -> void:
	placement_view = placed
	camera = camera_
	wall_view = walls
	judge.tuning = Judge.load_tuning()
	judge.tuning["target_alpha"] = 0.24
	var entries: Array = []
	var cache: Dictionary = {}
	for id: Variant in placed.holders:
		var parts: Array = []
		var holder: Node3D = placed.holders[id]
		for node: Node in holder.find_children("*", "MeshInstance3D", true, false):
			var mesh: MeshInstance3D = node as MeshInstance3D
			if mesh.mesh != null:
				parts.append(Judge.make_part(mesh, cache))
		if not parts.is_empty():
			entries.append({"group": String(id), "ids": [String(id)], "parts": parts})
	judge.set_entries(entries)

func update(delta: float, foot: Vector3, height: float) -> void:
	judge.refresh_parts()
	last_raw = judge.raw_occluders(judge.sample_points(foot, height, camera.global_basis.x), camera.global_basis.z)
	judge.step(last_raw, delta)
	for entry: Dictionary in judge.entries:
		var id: String = entry.group
		var alpha: float = judge.alpha_of(id)
		if alpha < 0.999:
			if not records.has(id):
				_begin(id)
			for item: Dictionary in records[id]:
				for material_: ShaderMaterial in item["cut"]:
					material_.set_shader_parameter("fade", alpha)
					material_.set_shader_parameter("cut_height", foot.y + 1.6)
		elif records.has(id):
			_restore(id)
		if wall_view != null and wall_view.groups.has(id):
			var group: Node3D = wall_view.groups[id].group
			group.visible = alpha >= 0.999

func _begin(id: String) -> void:
	var list: Array = []
	var holder: Node3D = placement_view.holders[id]
	for child: Node in holder.find_children("*", "MeshInstance3D", true, false):
		var node: MeshInstance3D = child as MeshInstance3D
		if node.mesh == null: continue
		var original: Array = []
		var cuts: Array[ShaderMaterial] = []
		for surface: int in node.mesh.get_surface_count():
			var old: Material = node.get_surface_override_material(surface)
			original.append(old)
			var material_: ShaderMaterial = ShaderMaterial.new()
			material_.shader = Cut
			var base: BaseMaterial3D = node.get_active_material(surface) as BaseMaterial3D
			if base != null:
				material_.set_shader_parameter("base_color", base.albedo_color)
				material_.set_shader_parameter("textured", base.albedo_texture != null)
				material_.set_shader_parameter("base_texture", base.albedo_texture)
				material_.set_shader_parameter("vertex_color", base.vertex_color_use_as_albedo)
			cuts.append(material_)
			node.set_surface_override_material(surface, material_)
		# A shadow-only twin keeps the original full-height building shadow stable.
		var shadow: MeshInstance3D = MeshInstance3D.new()
		shadow.mesh = node.mesh
		shadow.transform = node.transform
		shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		node.get_parent().add_child(shadow)
		list.append({"node": node, "original": original, "cut": cuts, "cast": node.cast_shadow, "shadow": shadow})
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	records[id] = list

func _restore(id: String) -> void:
	for item: Dictionary in records[id]:
		var node: MeshInstance3D = item.node
		for surface: int in item.original.size():
			node.set_surface_override_material(surface, item.original[surface])
		node.cast_shadow = item.cast
		(item.shadow as Node).queue_free()
	records.erase(id)

