extends "res://tests/poc3/world_layout/self_logic.gd"
## Limited impact: actual cardinal routes, plus original diagonal-path failure locations.

func failure_point(session: RefCounted, route: Array[Vector2i]) -> Dictionary:
	if route.is_empty(): return {"empty":true}
	var position_: Vector2 = Coords.cell_center_logic(route[0])
	for index: int in range(1,route.size()):
		var from: Vector2 = position_
		var target: Vector2 = Coords.cell_center_logic(route[index])
		position_=Walker.move(session.state,4,position_,target-position_,Vector2(2,2))
		if position_.distance_to(target)>0.01:
			return {"step":index,"from_cell":route[index-1],"target_cell":route[index],"from_logic":from,"actual_logic":position_,"target_logic":target,"error_px":position_.distance_to(target)}
	return {}

func cardinal_parents(session: RefCounted, start: Vector2i) -> PackedInt32Array:
	var parents: PackedInt32Array = PackedInt32Array()
	parents.resize(session.state.tile_count())
	parents.fill(-1)
	var start_index: int = session.state.index_of(start.x,start.y)
	parents[start_index]=start_index
	var queue: Array[Vector2i] = [start]
	var head: int = 0
	while head<queue.size():
		var cell: Vector2i = queue[head]
		head+=1
		for delta: Vector2i in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
			var next: Vector2i = cell+delta
			if not session.state.in_bounds(next.x,next.y) or not session.state.is_walkable(next.x,next.y): continue
			var index: int = session.state.index_of(next.x,next.y)
			if parents[index]!=-1: continue
			if not Walker.is_clear(session.state,4,Coords.cell_center_logic(next),Vector2(2,2)): continue
			parents[index]=session.state.index_of(cell.x,cell.y)
			queue.append(next)
	return parents

func cardinal_route(session: RefCounted, parents: PackedInt32Array, destination: Vector2) -> Array[Vector2i]:
	var cell: Vector2i = Coords.logic_to_cell(destination)
	var index: int = session.state.index_of(cell.x,cell.y)
	var route: Array[Vector2i] = []
	if parents[index]<0: return route
	while true:
		route.append(Vector2i(index%224,index/224))
		if parents[index]==index: break
		index=parents[index]
	route.reverse()
	return route

func run() -> void:
	if not isolated() or Session.MAP_PATH!=EXPECTED_MAP:
		quit(1)
		return
	var session: RefCounted = Session.new()
	var parents: PackedInt32Array = cardinal_parents(session,Vector2i(112,112))
	for index: int in 4:
		var nest: Dictionary = session.nests[index]
		var diagonal: Array[Vector2i] = session.nav.route(session.position,nest.pos)
		var route: Array[Vector2i] = cardinal_route(session,parents,nest.pos)
		var error: Dictionary = failure_point(session,route)
		observations[str(index)]={"original_nav_first_error":failure_point(session,diagonal),"cardinal_cells":route.size(),"cardinal_length_m":route_m(route),"cardinal_first_error":error,"target_logic":nest.pos}
		check("cardinal_player_collision_route_"+str(index),not route.is_empty() and error.is_empty())
	session.close()
	finish("routes_followup.json")
