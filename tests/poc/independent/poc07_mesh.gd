extends SceneTree
## POC-07 independent: building mesh AABB (own GLB read) vs obstacle cells owned by the instance. Headless OK.
const Coords: GDScript = preload("res://scripts/poc/poc_coords.gd")
const Session: GDScript = preload("res://scripts/poc/poc_session.gd")
var fails: int = 0

func _init() -> void:
	_run.call_deferred()

func collect(n: Node, xf: Transform3D, acc: Array) -> void:
	var cur: Transform3D = xf
	if n is Node3D:
		cur = xf * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		acc.append((cur * (n as MeshInstance3D).mesh.get_aabb()))
	for c: Node in n.get_children():
		collect(c, cur, acc)

func _run() -> void:
	var sz: Vector2i = Session.town_size()
	var s: RefCounted = Session.new(sz.x, sz.y)
	s.load_combat(Session.TOWN_SETUP)
	var pl: RefCounted = s.placement
	for inst: Dictionary in pl.instances:
		if inst["kind"] != "building":
			continue
		var cat: Dictionary = pl.catalog[inst["asset"]]
		var scn: Node = (load(cat["glb"]) as PackedScene).instantiate()
		var boxes: Array = []
		collect(scn, Transform3D.IDENTITY, boxes)
		var lo: Vector2 = Vector2(INF, INF)
		var hi: Vector2 = Vector2(-INF, -INF)
		for b: AABB in boxes:
			lo.x = minf(lo.x, b.position.x)
			lo.y = minf(lo.y, b.position.z)
			hi.x = maxf(hi.x, b.end.x)
			hi.y = maxf(hi.y, b.end.z)
		var ctr: Vector2 = (lo + hi) * 0.5
		var pos: Vector2 = inst["pos"]
		var yaw: float = inst["yaw"]
		# yaw 0 for all buildings (checked); translate AABB centre to pos
		var mlo: Vector2 = lo - ctr + pos
		var mhi: Vector2 = hi - ctr + pos
		var cells: PackedInt32Array = pl.cells_of[inst["id"]]
		var clo: Vector2 = Vector2(INF, INF)
		var chi: Vector2 = Vector2(-INF, -INF)
		for i: int in cells:
			var g: Vector2 = Coords.cell_center_ground(Vector2i(i % s.state.width, i / s.state.width))
			clo = Vector2(minf(clo.x, g.x - 0.2), minf(clo.y, g.y - 0.2))
			chi = Vector2(maxf(chi.x, g.x + 0.2), maxf(chi.y, g.y + 0.2))
		var d: Array = [snappedf(clo.x - mlo.x, 0.01), snappedf(clo.y - mlo.y, 0.01), snappedf(chi.x - mhi.x, 0.01), snappedf(chi.y - mhi.y, 0.01)]
		var ok: bool = absf(yaw) < 0.001 and cells.size() > 0
		for v: float in d:
			if absf(v) > 0.8:
				ok = false
		if not ok:
			fails += 1
		print("PASS " if ok else "FAIL ", inst["id"], " mesh x[%.2f,%.2f] z[%.2f,%.2f] cells x[%.2f,%.2f] z[%.2f,%.2f] edge-diff(m, -x,-z,+x,+z)=%s ncells=%d" % [mlo.x, mhi.x, mlo.y, mhi.y, clo.x, chi.x, clo.y, chi.y, str(d), cells.size()])
		scn.free()
	print("RESULT fails=", fails)
	s.close()
	quit(1 if fails > 0 else 0)
