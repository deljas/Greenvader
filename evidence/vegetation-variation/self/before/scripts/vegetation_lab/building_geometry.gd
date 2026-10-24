extends RefCounted
const OldGeometry: GDScript = preload("res://scripts/render_study_3d/ruin_geometry.gd")
const Brick: Shader = preload("res://scripts/vegetation_lab/brick.gdshader")

static func sample(surface: Dictionary, u: float, v: float) -> Dictionary:
	if surface["kind"] == "cylinder":
		var angle: float = u / float(surface["radius"])
		var normal: Vector3 = Vector3(sin(angle),0,cos(angle))
		return {"position":normal*float(surface["radius"])+Vector3.UP*v,"normal":normal}
	return {"position":surface["origin"]+surface["tangent"]*u+Vector3.UP*v,"normal":surface["normal"]}

static func path_sample(def: Dictionary, surface: Dictionary, u: float, distance: float) -> Dictionary:
	var height: float = surface["height"]
	if distance <= height:
		return sample(surface,u,distance)
	var end: Dictionary = sample(surface,u,height)
	var inset: float = distance-height
	if def["shape"] == "cylinder":
		var n: Vector3 = end["normal"]
		var roof_r: float = def["roof_radius"]
		var overhang: float = roof_r-float(def["radius"])
		if inset < overhang:
			return {"position":n*(float(def["radius"])+inset)+Vector3.UP*(height+0.04),"normal":Vector3.UP}
		var radius: float = maxf(0.18,roof_r-(inset-overhang))
		var roof_h: float = def["roof_height"]
		return {"position":n*radius+Vector3.UP*(height+roof_h*(1.0-radius/roof_r)),"normal":(n*(roof_h/roof_r)+Vector3.UP).normalized()}
	if def.get("restore_roof",false):
		if inset < 0.58:
			return {"position":end["position"]+Vector3.UP*inset,"normal":end["normal"]}
		var p: Vector3 = end["position"]-end["normal"]*(inset-0.58)
		var top: float = roof_top(def,p.x,p.z)
		if top < 0:
			return {}
		return {"position":Vector3(p.x,top,p.z),"normal":Vector3.UP}
	return {"position":end["position"]-end["normal"]*inset+Vector3.UP*0.20,"normal":Vector3.UP}

static func blocked_surface(surface: Dictionary, u: float, v: float, margin: float) -> bool:
	for hole: Rect2 in surface["holes"]:
		if hole.grow(margin).has_point(Vector2(u,v)):
			return true
	return false

static func ground_allowed(def: Dictionary, p: Vector2, margin: float = 0.34) -> bool:
	var size_: Vector3 = def["size"]
	if def["shape"] == "cylinder":
		if p.length() < float(def["radius"])+margin:
			return false
	elif Rect2(Vector2(-size_.x,-size_.z)*0.5,Vector2(size_.x,size_.z)).grow(margin).has_point(p):
		return false
	var corridor: Dictionary = def["walkway"]
	var nearest: Vector2 = Geometry2D.get_closest_point_to_segment(p,corridor["from"],corridor["to"])
	return p.distance_to(nearest) > float(corridor["half_width"])+margin

static func build(parent: Node3D, def: Dictionary) -> void:
	var size_: Vector3 = def["size"]
	var concrete: Material = OldGeometry.material(def["color"])
	var dark: Material = OldGeometry.material(Color("263a35"))
	var door: Material = OldGeometry.material(Color("74634e"),2.0)
	var extent: Vector2 = def["extent"]
	OldGeometry.box(parent,"Paving",Vector3(0,-0.035,0),Vector3(extent.x*2,0.10,extent.y*2),OldGeometry.material(Color("727b71"),1.0))
	if def["shape"] == "box":
		OldGeometry.box(parent,"Back",Vector3(0,size_.y/2,-size_.z/2),Vector3(size_.x,size_.y,0.22),concrete)
		OldGeometry.box(parent,"Left",Vector3(-size_.x/2,size_.y/2,0),Vector3(0.22,size_.y,size_.z),concrete)
		if def.get("restore_roof",false):
			var temporary: Node3D = Node3D.new()
			var old_parts: Dictionary = OldGeometry.build(temporary)
			var roof: Node3D = old_parts["roof"]
			temporary.remove_child(roof)
			parent.add_child(roof)
			var triangles: PackedVector3Array = PackedVector3Array()
			for part: MeshInstance3D in roof.get_children():
				if String(part.name).begins_with("ExposedRebar"):
					continue
				for vertex: Vector3 in part.mesh.get_faces():
					triangles.append(part.transform*vertex)
			def["roof_triangles"] = triangles
			temporary.free()
		else:
			OldGeometry.box(parent,"FlatRoof",Vector3(0,size_.y+0.08,0),Vector3(size_.x+0.36,0.20,size_.z+0.36),concrete)
		for surface: Dictionary in def["surfaces"]:
			_plane_wall(parent,surface,concrete)
	else:
		var brick: ShaderMaterial = ShaderMaterial.new()
		brick.shader = Brick
		_cylinder_wall(parent,def["surfaces"][0],brick)
		var cone: CylinderMesh = CylinderMesh.new()
		cone.bottom_radius = def["roof_radius"]
		cone.top_radius = 0.0
		cone.height = def["roof_height"]
		cone.radial_segments = 48
		var mesh: MeshInstance3D = MeshInstance3D.new()
		mesh.mesh = cone
		mesh.position.y = size_.y+float(def["roof_height"])*0.5
		var metal: StandardMaterial3D = StandardMaterial3D.new()
		metal.albedo_color = Color("343e43")
		metal.metallic = 0.35
		metal.roughness = 0.72
		mesh.material_override = metal
		parent.add_child(mesh)
	for surface: Dictionary in def["surfaces"]:
		for hole: Rect2 in surface["holes"]:
			var hit: Dictionary = sample(surface,hole.get_center().x,hole.get_center().y)
			var recess: MeshInstance3D = OldGeometry.box(parent,"Door" if hole.position.y==0 else "WindowRecess",hit["position"]-hit["normal"]*0.12,Vector3(hole.size.x, hole.size.y,0.06),door if hole.position.y==0 else dark)
			recess.basis = facing(hit["normal"])

static func facing(normal: Vector3) -> Basis:
	var right: Vector3 = Vector3.UP.cross(normal)
	if right.length_squared() < 0.001:
		right = Vector3.RIGHT
	right = right.normalized()
	return Basis(right,normal.cross(right).normalized(),normal)

static func _plane_wall(parent: Node3D, surface: Dictionary, mat: Material) -> void:
	var xs: Array[float] = [0.0,float(surface["width"])]
	var ys: Array[float] = [0.0,float(surface["height"])]
	for hole: Rect2 in surface["holes"]:
		xs.append(hole.position.x)
		xs.append(hole.end.x)
		ys.append(hole.position.y)
		ys.append(hole.end.y)
	xs.sort()
	ys.sort()
	for i: int in range(xs.size()-1):
		for j: int in range(ys.size()-1):
			var u: float = (xs[i]+xs[i+1])*0.5
			var v: float = (ys[j]+ys[j+1])*0.5
			if xs[i+1]-xs[i] < 0.001 or ys[j+1]-ys[j] < 0.001 or blocked_surface(surface,u,v,0):
				continue
			var hit: Dictionary = sample(surface,u,v)
			var mesh: MeshInstance3D = OldGeometry.box(parent,"WallBands",hit["position"],Vector3(xs[i+1]-xs[i],ys[j+1]-ys[j],0.22),mat)
			mesh.basis = facing(hit["normal"])

static func _cylinder_wall(parent: Node3D, surface: Dictionary, mat: Material) -> void:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for row: int in 40:
		for col: int in 96:
			var u: float = float(col)/96.0*float(surface["width"])
			var v: float = float(row)/40.0*float(surface["height"])
			var du: float = float(surface["width"])/96.0
			var dv: float = float(surface["height"])/40.0
			if blocked_surface(surface,u+du/2,v+dv/2,0):
				continue
			for corner: Vector2 in [Vector2(u,v),Vector2(u+du,v+dv),Vector2(u+du,v),Vector2(u,v),Vector2(u,v+dv),Vector2(u+du,v+dv)]:
				var hit: Dictionary = sample(surface,corner.x,corner.y)
				st.set_normal(hit["normal"])
				st.add_vertex(hit["position"])
	var node: MeshInstance3D = MeshInstance3D.new()
	node.mesh = st.commit()
	node.material_override = mat
	parent.add_child(node)

static func roof_top(def: Dictionary, x: float, z: float) -> float:
	var triangles: PackedVector3Array = def.get("roof_triangles",PackedVector3Array())
	var top: float = -1.0
	for i: int in range(0,triangles.size(),3):
		var hit: Variant = Geometry3D.segment_intersects_triangle(Vector3(x,5,z),Vector3(x,2.6,z),triangles[i],triangles[i+1],triangles[i+2])
		if hit != null:
			top = maxf(top,hit.y)
	return top
