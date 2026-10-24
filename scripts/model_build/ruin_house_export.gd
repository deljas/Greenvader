extends SceneTree
## Rebuild: Godot --headless --path <repo> --script res://scripts/model_build/ruin_house_export.gd
const G: GDScript = preload("res://scripts/render_study_3d/ruin_geometry.gd")
const Walls: GDScript = preload("res://scripts/vegetation_lab/building_geometry.gd")
const Attachments: GDScript = preload("res://assets/models/ruin_house/attachments.gd")
const OUTPUT: String = "res://assets/models/ruin_house/ruin_house.glb"

func _initialize() -> void:
	build.call_deferred()

func material_(hex: String, label_: String) -> StandardMaterial3D:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.resource_name = label_
	mat.albedo_color = Color(hex)
	mat.roughness = 0.96
	return mat

func build() -> void:
	var house: Node3D = Node3D.new()
	house.name = "RuinHouse"
	root.add_child(house)
	var def: Dictionary = Attachments.definition()
	var concrete: Material = material_("9c9f90","WeatheredConcrete")
	var edge: Material = material_("afb09d","ConcreteFrames")
	var roof: Material = material_("858d7d","RoofConcrete")
	var rust: Material = material_("80654b","RustSteel")
	var recess: Material = material_("243730","DarkRecess")
	G.box(house,"BackWall",Vector3(0,1.4,-2.4),Vector3(6,2.8,0.22),concrete)
	G.box(house,"LeftWall",Vector3(-3,1.4,0),Vector3(0.22,2.8,4.8),concrete)
	for surface: Dictionary in def["surfaces"]:
		Walls._plane_wall(house,surface,concrete)
		for hole: Rect2 in surface["holes"]:
			var door: bool = hole.position.y<0.05
			var center: Vector2 = hole.get_center()
			var hit: Dictionary = Walls.sample(surface,center.x,center.y)
			var panel: MeshInstance3D = G.box(house,"ClosedRustDoor" if door else "RecessedWindow",hit["position"]-hit["normal"]*0.12,Vector3(hole.size.x-0.05,hole.size.y-0.04,0.07),rust if door else recess)
			panel.basis = Walls.facing(hit["normal"])
			for x: float in [hole.position.x,hole.end.x]:
				part(house,surface,Vector2(x,center.y),Vector3(0.09,hole.size.y+0.12,0.18),edge,"WindowOrDoorJamb")
			for y: float in [hole.position.y,hole.end.y]:
				part(house,surface,Vector2(center.x,y),Vector3(hole.size.x+0.12,0.09,0.18),edge,"SillOrLintel")
			if not door:
				part(house,surface,center,Vector3(0.035,hole.size.y-0.08,0.12),rust,"WindowMullion")
			else:
				part(house,surface,Vector2(center.x+0.39,1.05),Vector3(0.13,0.04,0.20),recess,"DoorHandle")
				var awning: MeshInstance3D = part(house,surface,Vector2(center.x,2.34),Vector3(1.70,0.13,0.53),roof,"ConcreteDoorAwning")
				awning.position += hit["normal"]*0.05
	# Missing corner is real geometry; the slab and broken parapet stay inside the foundation.
	var outline: PackedVector2Array = PackedVector2Array([Vector2(-3.16,-2.56),Vector2(3.16,-2.56),Vector2(3.16,1.55),Vector2(2.92,1.58),Vector2(2.84,1.96),Vector2(2.43,2.08),Vector2(2.31,2.56),Vector2(-0.8,2.56),Vector2(-1.0,2.42),Vector2(-1.3,2.56),Vector2(-3.16,2.56)])
	G._prism(house,"BrokenRoofSlab",outline,2.75,0.22,roof)
	for i: int in 9:
		var x: float = -2.85+i*0.69
		G.box(house,"RearParapet",Vector3(x,3.08,-2.43),Vector3(0.65,0.24,0.18),concrete)
		if i not in [3,7,8]:
			G.box(house,"ChippedFrontParapet",Vector3(x,3.04+(i%3)*0.025,2.43),Vector3(0.60,0.15+(i%3)*0.05,0.18),edge)
	for i: int in 5:
		G.box(house,"LeftRoofRim",Vector3(-3.05,3.08,-1.95+i*0.87),Vector3(0.17,0.25,0.80),concrete)
	for i: int in 3:
		G.box(house,"RightRoofRim",Vector3(3.05,3.07,-1.95+i*0.87),Vector3(0.17,0.22,0.79),concrete)
	for x: float in [-2.5,-2.29]:
		var rod: MeshInstance3D = G.box(house,"ExposedRebar",Vector3(x,3.22,2.39),Vector3(0.035,0.46,0.035),rust)
		rod.rotation.z = 0.17
	for child: Node in house.get_children():
		child.owner = house
	var document: GLTFDocument = GLTFDocument.new()
	var state: GLTFState = GLTFState.new()
	var append_error: Error = document.append_from_scene(house,state)
	var write_error: Error = document.write_to_filesystem(state,OUTPUT) if append_error==OK else append_error
	print("GLB_EXPORT append=",append_error," write=",write_error," children=",house.get_child_count())
	house.free()
	quit(0 if write_error==OK else 1)

func part(parent: Node3D, surface: Dictionary, uv: Vector2, size_: Vector3, mat: Material, label_: String) -> MeshInstance3D:
	var hit: Dictionary = Walls.sample(surface,uv.x,uv.y)
	var node: MeshInstance3D = G.box(parent,label_,hit["position"]+hit["normal"]*0.08,size_,mat)
	node.basis = Walls.facing(hit["normal"])
	return node
