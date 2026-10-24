extends SceneTree
const Session: GDScript=preload("res://scripts/poc2/poc2_session.gd")
func _init() -> void:
 call_deferred("run")
func run() -> void:
 var s: RefCounted=Session.new()
 var home: Vector2=Session.Coords.cell_center_logic(Vector2i(177,188))
 for delta: Vector2 in [Vector2(-24,0),Vector2(24,0),Vector2(0,-24),Vector2(0,24)]:
  var target: Vector2=home+delta
  var cell: Vector2i=Session.Coords.logic_to_cell(target)
  print({"home":home,"target":target,"walkable":s.is_walkable_logic(target),"terrain":s.state.terrain[s.state.index_of(cell.x,cell.y)],"path":s.nav.route(home,target)})
 s.close(); quit()
