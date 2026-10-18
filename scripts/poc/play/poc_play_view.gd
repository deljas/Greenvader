extends Node3D
## POC-03 provisional 3D display of the play state. No game logic here: it only reads the session. Per-cell plant growth is
## shown by the POC-05 GroundCover (terrain-specific soil / pavement display, MultiMesh instances updated from the WorldState
## dirty list, never a whole-map rebuild per frame); pickups, sources, cultivated plants and shots use small pooled meshes
## (provisional flat unshaded colours), no outlines.
const Config: GDScript = preload("res://scripts/poc/poc_config.gd")
const Coords: GDScript = preload("res://scripts/poc/poc_coords.gd")
const GroundCoverScript: GDScript = preload("res://scripts/poc/environment/ground_cover.gd")

const HIDDEN_Y: float = -20.0

var session: RefCounted
## POC-05 terrain-specific greening display; cell_multimesh is its soil layer (one instance per cell).
var ground: Node3D
var cell_multimesh: MultiMesh
var cultivated_nodes: Dictionary = {}
var pickup_pool: Array[MeshInstance3D] = []
var shot_pool: Array[MeshInstance3D] = []
var source_nodes: Array[MeshInstance3D] = []
var materials: Dictionary = {}
var _sphere: SphereMesh
var _box: BoxMesh
## Instances of the cell MultiMesh rewritten since build (observability for the "no full rebuild" check).
var cell_updates: int:
	get:
		return ground.cell_updates if ground != null else 0
var last_sync_count: int = 0

func build(source: RefCounted) -> void:
	session = source
	_box = BoxMesh.new()
	_box.size = Vector3.ONE
	_sphere = SphereMesh.new()
	_sphere.radius = 0.5
	_sphere.height = 1.0
	_sphere.radial_segments = 8
	_sphere.rings = 4
	ground = GroundCoverScript.new()
	ground.name = "GroundCover"
	add_child(ground)
	ground.build(session, session.env_tuning)
	cell_multimesh = ground.soil_multimesh
	session.state.clear_dirty()
	for source_item: SeedSource in session.play.sources:
		var node: MeshInstance3D = _mesh_node(_box, Color("c58cff"), Vector3(0.5, 1.1, 0.5))
		node.name = "SeedSource%d" % source_item.id
		node.position = Coords.ground3(Coords.logic_to_ground(source_item.position), 0.55)
		source_nodes.append(node)

func _unshaded(color: Color) -> StandardMaterial3D:
	var key: String = color.to_html()
	if not materials.has(key):
		var material: StandardMaterial3D = StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = color
		materials[key] = material
	return materials[key]

func _mesh_node(mesh: Mesh, color: Color, size: Vector3) -> MeshInstance3D:
	var node: MeshInstance3D = MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = _unshaded(color)
	node.scale = size
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	return node

## Per frame: apply only the cells the WorldState marked dirty, then refresh the small pooled objects.
func sync() -> void:
	var dirty: PackedInt32Array = session.state.take_dirty()
	last_sync_count = dirty.size()
	ground.apply(dirty)
	_sync_cultivated()
	_sync_pickups()
	_sync_shots()

func _sync_cultivated() -> void:
	var seen: Dictionary = {}
	for plant: CultivatedPlant in session.play.cultivation.plants:
		seen[plant.uid] = true
		var node: MeshInstance3D = cultivated_nodes.get(plant.uid) as MeshInstance3D
		if node == null:
			var color: Color = Color("f08a24") if plant.key == &"carrot" else Color("9acd32")
			node = _mesh_node(_box, color, Vector3.ONE)
			cultivated_nodes[plant.uid] = node
		var height: float = 0.7 if plant.mature else 0.3
		var side: float = float(plant.size) * Config.CELL_M * 0.8
		node.scale = Vector3(side, height, side)
		var centre: Vector2 = Coords.logic_to_ground(plant.center_tiles() * float(Config.TILE_PX))
		node.position = Vector3(centre.x, height * 0.5, centre.y)
	for uid: Variant in cultivated_nodes.keys():
		if not seen.has(uid):
			(cultivated_nodes[uid] as Node).queue_free()
			cultivated_nodes.erase(uid)

func _pooled(pool: Array[MeshInstance3D], count: int) -> void:
	while pool.size() < count:
		var node: MeshInstance3D = _mesh_node(_sphere, Color.WHITE, Vector3.ONE * 0.25)
		pool.append(node)
	for i: int in pool.size():
		pool[i].visible = i < count

func _sync_pickups() -> void:
	var items: Array[Dictionary] = session.play.pickups.items
	_pooled(pickup_pool, items.size())
	var bob_time: float = session.clock.elapsed
	for i: int in items.size():
		var item: Dictionary = items[i]
		var node: MeshInstance3D = pickup_pool[i]
		var heal: bool = String(item["kind"]) == GroundPickups.KIND_HEAL_FRUIT
		node.material_override = _unshaded(Color("ff7aa8") if heal else Color("ffd34a"))
		var ground: Vector2 = Coords.logic_to_ground(Vector2(float(item["x"]), float(item["y"])))
		node.scale = Vector3.ONE * (0.3 if heal else 0.24)
		node.position = Vector3(ground.x, 0.22 + 0.04 * sin(bob_time * 4.0 + float(i)), ground.y)

func _sync_shots() -> void:
	var shots: Array[Dictionary] = session.projectiles.shots
	_pooled(shot_pool, shots.size())
	for i: int in shots.size():
		var shot: Dictionary = shots[i]
		var node: MeshInstance3D = shot_pool[i]
		var kind: String = String(shot["kind"])
		var color: Color = Color("63b8cf") if kind == "water" else (Color("fff1c2") if kind == "seed" else Color("f08a24"))
		node.material_override = _unshaded(color)
		node.scale = Vector3.ONE * 0.2
		var ground: Vector2 = Coords.logic_to_ground(shot["position"])
		node.position = Vector3(ground.x, 0.55, ground.y)

## Observability for tests / screenshots.
func snapshot() -> Dictionary:
	return {
		"cultivated": cultivated_nodes.size(),
		"pickups_visible": pickup_pool.filter(func(n: MeshInstance3D) -> bool: return n.visible).size(),
		"shots_visible": shot_pool.filter(func(n: MeshInstance3D) -> bool: return n.visible).size(),
		"sources": source_nodes.size(),
		"last_sync_count": last_sync_count,
		"cell_updates": ground.cell_updates,
	}
