extends RefCounted
## Terrain-aware routes. Rebuilt only at world creation/restore, never per frame.
const Coords: GDScript = preload("res://scripts/poc/poc_coords.gd")
var normal: AStarGrid2D = AStarGrid2D.new()
var hostile: AStarGrid2D = AStarGrid2D.new()
var state: WorldState
var components: PackedInt32Array = PackedInt32Array()
var water_banks: Array[Vector2i] = []

func setup(world: WorldState) -> void:
 state = world
 for grid: AStarGrid2D in [normal, hostile]:
  grid.region = Rect2i(0, 0, state.width, state.height)
  grid.cell_size = Vector2(4, 4)
  grid.offset = Vector2(2, 2)
  grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
  grid.update()
 water_banks.clear()
 for y: int in state.height:
  for x: int in state.width:
   var c: Vector2i = Vector2i(x, y)
   var walkable: bool = state.is_walkable(x, y)
   normal.set_point_solid(c, not walkable)
   hostile.set_point_solid(c, not walkable or state.zone_state[state.zone_at(state.index_of(x,y))] >= WorldState.ZONE_STABLE)
   if walkable:
    for delta: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
     var n: Vector2i = c + delta
     if state.in_bounds(n.x,n.y) and state.terrain[state.index_of(n.x,n.y)] == 3:
      water_banks.append(c)
      break

 components.resize(state.tile_count())
 components.fill(0)
 var next_component: int = 0
 for index: int in state.tile_count():
  var c: Vector2i = Vector2i(index%state.width,index/state.width)
  if components[index]!=0 or normal.is_point_solid(c): continue
  next_component+=1
  var queue: Array[Vector2i]=[c]
  components[index]=next_component
  var head: int=0
  while head<queue.size():
   var at: Vector2i=queue[head]
   head+=1
   for delta: Vector2i in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
    var adjacent: Vector2i=at+delta
    if not normal.is_in_boundsv(adjacent) or normal.is_point_solid(adjacent): continue
    var next_index: int=state.index_of(adjacent.x,adjacent.y)
    if components[next_index]==0:
     components[next_index]=next_component
     queue.append(adjacent)

func route(from: Vector2, to: Vector2, enemy: bool = false) -> Array[Vector2i]:
 var a: Vector2i = Coords.logic_to_cell(from)
 var b: Vector2i = Coords.logic_to_cell(to)
 var grid: AStarGrid2D = hostile if enemy else normal
 if not grid.is_in_boundsv(a) or not grid.is_in_boundsv(b) or grid.is_point_solid(a) or grid.is_point_solid(b):
  return []
 return grid.get_id_path(a,b)

func move(entity: Dictionary, goal: Vector2, speed: float, dt: float, now: float, enemy: bool = false) -> bool:
 var pos: Vector2 = entity.pos
 if pos.distance_to(goal) < 1.0:
  return true
 if now >= float(entity.get("route_at", -1.0)) or entity.get("goal", Vector2(-1,-1)).distance_to(goal) > 8.0:
  entity.route = route(pos, goal, enemy)
  entity.route_index = 1
  entity.route_at = now + 1.0
  entity.goal = goal
 var path: Array = entity.get("route", [])
 var idx: int = int(entity.get("route_index",1))
 var budget: float = speed * dt
 while idx < path.size() and budget > 0.0:
  var target: Vector2 = Coords.cell_center_logic(path[idx])
  var dist: float = pos.distance_to(target)
  if dist <= budget:
   pos = target
   budget -= dist
   idx += 1
  else:
   pos = pos.move_toward(target,budget)
   budget = 0.0
 entity.pos = pos
 entity.route_index = idx
 return pos.distance_to(goal) < 4.0

func bank(from: Vector2) -> Vector2:
 var cell: Vector2i=Coords.logic_to_cell(from)
 if not state.in_bounds(cell.x,cell.y): return Vector2(-1,-1)
 var component: int=components[state.index_of(cell.x,cell.y)]
 var nearest: Vector2=Vector2(-1,-1)
 var distance: float=INF
 for candidate: Vector2i in water_banks:
  if components[state.index_of(candidate.x,candidate.y)]!=component: continue
  var pos: Vector2=Coords.cell_center_logic(candidate)
  var d: float=pos.distance_squared_to(from)
  if d<distance:
   distance=d; nearest=pos
 return nearest

func closest_reachable(from: Vector2, goal: Vector2) -> Vector2:
 var c: Vector2i=Coords.logic_to_cell(from)
 if not state.in_bounds(c.x,c.y): return from
 var component: int=components[state.index_of(c.x,c.y)]
 var best: float=INF
 var answer: Vector2=from
 for index: int in state.tile_count():
  if components[index]!=component or component==0: continue
  var pos: Vector2=Coords.cell_center_logic(Vector2i(index%state.width,index/state.width))
  var distance: float=pos.distance_squared_to(goal)
  if distance<best:
   best=distance; answer=pos
 return answer
