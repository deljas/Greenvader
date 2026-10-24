extends Node
## POC-06 thin Node around occlusion.gd: collects the placed GLB meshes, runs the judgement every frame for the player
## and applies the fade to the display only.
##  - buildings / props / trees: per-instance material copies (PlacementView.set_instance_alpha, alpha ~0.4).
##  - while an instance is faded: its display meshes stop casting shadows, a SHADOWS_ONLY copy (layer SHADOW_LAYER, in the
##    sun's shadow_caster_mask) keeps the ground shadow, and an opaque reflection copy (layer REFLECT_LAYER, hidden from
##    the main camera, visible to the water reflection camera) keeps the building in the water reflection.
##  - single_layer: every opaque-origin surface of a faded instance gets a depth-only pre-pass material (alpha 0, depth_draw
##    ALWAYS, render_priority below everything) chained before its faded colour material (next_pass), so only the nearest
##    surface is blended (no stack of walls / roof / inner faces that would hide the player again). The sprite already
##    sits in the opaque depth buffer, so the surfaces behind it are rejected and the sprite keeps its full colour.
##  - wall vegetation (WallView group "WallVeg_<id>") follows with GeometryInstance3D.transparency (shared leaf/stem
##    materials are not touched).
## Nothing here is read by collision / enemies / greening / shots (WorldState and Placement are never written).
const Occlusion: GDScript = preload("res://scripts/poc/occlusion/occlusion.gd")
const SHADOW_LAYER: int = 8
const REFLECT_LAYER: int = 16
const ALL_LAYERS: int = 1048575
const DEPTH_PRIORITY: int = -64

var occlusion: RefCounted = Occlusion.new()
var placement_view: Node3D
var wall_view: Node3D
var water_view: Node3D
var camera: Camera3D
var enabled: bool = true
## instance_id -> {displays: [{node, cast}], copies: Array[MeshInstance3D]}; only for instances currently faded.
var fading: Dictionary = {}
var vegetation_fading: Dictionary = {}
var last_raw: Dictionary = {}
var updates: int = 0

func setup(placement_view_: Node3D, wall_view_: Node3D, camera_: Camera3D, water_view_: Node3D, tuning: Dictionary = {}) -> void:
	placement_view = placement_view_
	wall_view = wall_view_
	camera = camera_
	water_view = water_view_
	var merged: Dictionary = Occlusion.load_tuning() if tuning.is_empty() else tuning
	occlusion.tuning = merged
	enabled = bool(merged["enabled"])
	placement_view.fade_depth_draw_mode = _depth_mode(String(merged["depth_draw"]))
	placement_view.fade_transparency_mode = _transparency_mode(String(merged["transparency"]))
	camera.cull_mask = ALL_LAYERS & ~REFLECT_LAYER
	if not RenderingServer.frame_pre_draw.is_connected(_on_pre_draw):
		RenderingServer.frame_pre_draw.connect(_on_pre_draw)
		RenderingServer.frame_post_draw.connect(_on_post_draw)
	bind()

static func _depth_mode(name: String) -> int:
	match name:
		"opaque_only":
			return BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY
		"disabled":
			return BaseMaterial3D.DEPTH_DRAW_DISABLED
		_:
			return BaseMaterial3D.DEPTH_DRAW_ALWAYS

static func _transparency_mode(name: String) -> int:
	return BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS if name == "pre_pass" else BaseMaterial3D.TRANSPARENCY_ALPHA

## (Re)collects the occluder meshes of the current placement view. Restores everything first (safe after a rebuild).
func bind() -> void:
	_restore_all()
	var entries: Array = []
	var groups: Dictionary = {}
	var cache: Dictionary = {}
	for inst: Dictionary in placement_view.placement.instances:
		if inst["kind"] == "puddle" or not placement_view.holders.has(inst["id"]):
			continue
		var holder: Node3D = placement_view.holders[inst["id"]]
		var asset: Dictionary = placement_view.placement.catalog.get(inst["asset"], {})
		var key: String = Occlusion.group_key(String(inst["id"]), String(asset.get("occlusion_group", "instance")))
		if not groups.has(key):
			groups[key] = {"group": key, "ids": [], "parts": []}
			entries.append(groups[key])
		groups[key]["ids"].append(String(inst["id"]))
		for child: Node in holder.find_children("*", "MeshInstance3D", true, false):
			var node: MeshInstance3D = child as MeshInstance3D
			if node.mesh != null and node.visible:
				groups[key]["parts"].append(Occlusion.make_part(node, cache))
	occlusion.set_entries(entries)
	last_raw = {}

## Clears fades and the hysteresis; the next update snaps to the current raw result (no fade across rebuilds / resolution switches).
func reset() -> void:
	_restore_all()
	occlusion.reset_state()
	last_raw = {}

func set_enabled(on: bool) -> void:
	enabled = on
	if not on:
		reset()

## foot: world position of the player's feet, height_m: world height of the sprite.
func update(delta: float, foot: Vector3, height_m: float) -> void:
	if not enabled or placement_view == null:
		return
	updates += 1
	occlusion.refresh_parts()
	var points: PackedVector3Array = occlusion.sample_points(foot, height_m, camera.global_basis.x)
	last_raw = occlusion.raw_occluders(points, camera.global_basis.z)
	occlusion.step(last_raw, delta)
	for entry: Dictionary in occlusion.entries:
		_apply(entry, occlusion.alpha_of(entry["group"]))

func _apply(entry: Dictionary, alpha: float) -> void:
	for id: String in entry["ids"]:
		var is_fading: bool = fading.has(id)
		if alpha < 0.999:
			if not is_fading:
				_begin_fade(id)
			var record: Dictionary = fading[id]
			if absf(float(record.get("alpha", -1.0)) - alpha) > 0.0001:
				record["alpha"] = alpha
				placement_view.set_instance_alpha(id, alpha)
				if bool(occlusion.tuning["follow_vegetation"]):
					_set_vegetation(id, alpha)
		elif is_fading:
			_end_fade(id)

func _begin_fade(id: String) -> void:
	var holder: Node3D = placement_view.holders[id]
	var record: Dictionary = {"displays": [], "copies": [], "swaps": []}
	var single_layer: bool = bool(occlusion.tuning["single_layer"])
	for child: Node in holder.find_children("*", "MeshInstance3D", true, false):
		var node: MeshInstance3D = child as MeshInstance3D
		if node.mesh == null:
			continue
		record["displays"].append({"node": node, "cast": node.cast_shadow})
		if single_layer:
			for surface: int in node.mesh.get_surface_count():
				var color_material: BaseMaterial3D = node.get_surface_override_material(surface) as BaseMaterial3D
				if color_material != null and int(color_material.get_meta(&"base_transparency", -1)) == BaseMaterial3D.TRANSPARENCY_DISABLED:
					node.set_surface_override_material(surface, _depth_writer(color_material))
					record["swaps"].append({"node": node, "surface": surface, "material": color_material})
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# Still SHADOWS_ONLY: layer 1 lets the player's receiver light see the same 3D shadow.
		record["copies"].append(_copy_of(node, SHADOW_LAYER | 1, GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY, "OccShadow"))
		record["copies"].append(_copy_of(node, REFLECT_LAYER, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "OccReflect"))
	fading[id] = record

## Depth-only pass (invisible: alpha 0) that precedes the faded colour material of the same surface.
func _depth_writer(color_material: BaseMaterial3D) -> StandardMaterial3D:
	var writer: StandardMaterial3D = StandardMaterial3D.new()
	writer.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	writer.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	writer.albedo_color = Color(0.0, 0.0, 0.0, 0.0)
	writer.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS
	writer.cull_mode = color_material.cull_mode
	writer.render_priority = DEPTH_PRIORITY
	writer.next_pass = color_material
	return writer

## Copy with the mesh's own (unfaded, shared GLB) materials: no surface override.
func _copy_of(node: MeshInstance3D, layers: int, cast: int, tag: String) -> MeshInstance3D:
	var copy: MeshInstance3D = MeshInstance3D.new()
	copy.name = "%s_%s" % [tag, node.name]
	copy.mesh = node.mesh
	copy.transform = node.transform
	copy.layers = layers
	copy.cast_shadow = cast
	node.get_parent().add_child(copy)
	return copy

func _end_fade(id: String) -> void:
	if placement_view.holders.has(id):
		placement_view.set_instance_alpha(id, 1.0)
	_free_fade(id)
	_set_vegetation(id, 1.0)

func _free_fade(id: String) -> void:
	var record: Dictionary = fading[id]
	for swap: Dictionary in record["swaps"]:
		if is_instance_valid(swap["node"]) and not (swap["node"] as Node).is_queued_for_deletion():
			(swap["node"] as MeshInstance3D).set_surface_override_material(int(swap["surface"]), swap["material"])
	for display: Dictionary in record["displays"]:
		if is_instance_valid(display["node"]) and not (display["node"] as Node).is_queued_for_deletion():
			(display["node"] as MeshInstance3D).cast_shadow = display["cast"]
	for copy: Variant in record["copies"]:
		if is_instance_valid(copy):
			var copy_node: Node = copy as Node
			if copy_node.get_parent() != null:
				copy_node.get_parent().remove_child(copy_node)
			copy_node.free()
	fading.erase(id)

func _restore_all() -> void:
	for id: String in fading.keys():
		if placement_view != null and is_instance_valid(placement_view) and placement_view.holders.has(id):
			placement_view.set_instance_alpha(id, 1.0)
		_free_fade(id)
	for id: String in vegetation_fading.keys():
		_set_vegetation(id, 1.0)
	vegetation_fading.clear()

func _set_vegetation(id: String, alpha: float) -> void:
	if wall_view == null:
		return
	var group: Node3D = wall_view.group_of(id)
	if group == null or not is_instance_valid(group):
		return
	var transparent: bool = alpha < 0.999
	if not transparent and not vegetation_fading.has(id):
		return
	for child: Node in group.find_children("*", "GeometryInstance3D", true, false):
		(child as GeometryInstance3D).transparency = 1.0 - alpha if transparent else 0.0
	if transparent:
		vegetation_fading[id] = true
	else:
		vegetation_fading.erase(id)

## Reflection includes scene objects and the player (64); add opaque building copies during draws.
func reflection_mask_during_draw() -> int:
	return 1 | 64 | (REFLECT_LAYER if not fading.is_empty() else 0)

func _on_pre_draw() -> void:
	if water_view != null and is_instance_valid(water_view) and water_view.reflection_camera != null:
		water_view.reflection_camera.cull_mask = reflection_mask_during_draw()

func _on_post_draw() -> void:
	if water_view != null and is_instance_valid(water_view) and water_view.reflection_camera != null:
		water_view.reflection_camera.cull_mask = 1 | 64

## Instance ids with a non-opaque display right now.
func faded_instances() -> PackedStringArray:
	var ids: PackedStringArray = PackedStringArray()
	for id: String in fading:
		ids.append(id)
	ids.sort()
	return ids
