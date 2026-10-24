extends SceneTree
const Session: GDScript=preload("res://scripts/poc2/poc2_session.gd")
const Coords: GDScript=preload("res://scripts/poc/poc_coords.gd")
var checks: Array[Dictionary]=[]
func _init() -> void:
 call_deferred("run")
func check(name_: String,ok: bool,detail: Variant="") -> void:
 checks.append({"name":name_,"status":"PASS" if ok else "FAIL","detail":detail})
 print(checks.back())
func quiet() -> RefCounted:
 var s: RefCounted=Session.new()
 for c: Dictionary in s.clock.growth_ticked.get_connections(): s.clock.growth_ticked.disconnect(c.callable)
 for c: Dictionary in s.clock.spread_ticked.get_connections(): s.clock.spread_ticked.disconnect(c.callable)
 s.enemies.clear(); s.nests.clear(); s.known.fill(1); s.seeds=1000
 for kind: String in ["army","sprinkler"]: s.unlocked[kind]=true
 return s
func run() -> void:
 guard_and_unknown()
 water_trip()
 source_activation()
 var failures: int=0
 for row: Dictionary in checks:
  if row.status=="FAIL": failures+=1
 var f: FileAccess=FileAccess.open("res://evidence/poc2/independent/boundary-results.json",FileAccess.WRITE)
 f.store_string(JSON.stringify({"checks":checks,"failures":failures}," ")); f.close()
 quit(1 if failures else 0)
func guard_and_unknown() -> void:
 var s: RefCounted=quiet()
 var placed: Dictionary=s.place_helper("army",Vector2i(177,188))
 check("army_fixture",placed.ok,placed)
 if not placed.ok: s.close(); return
 var h: Dictionary=s.helpers[0]
 var home: Vector2=h.home
 # The original west-side fixture was inside a building; north has an unobstructed route.
 s.combat_system.spawn({"id":999,"kind":"spider","pos":home+Vector2(0,-24),"home":home+Vector2(0,-24)},false)
 var enemy: Dictionary=s.enemies[0]
 enemy.pos=home+Vector2(0,-24); enemy.home=enemy.pos
 s.advance_game(1.0)
 var moved: bool=h.pos.distance_to(home)>1.0
 s.advance_game(8.0)
 check("guard_intercepts_kills_returns",moved and s.enemies.is_empty() and h.pos.distance_to(home)<4.0,{"engaged":moved,"enemies":s.enemies.size(),"distance_home":h.pos.distance_to(home)})
 h.hp=60.0; h.last_combat=s.clock.elapsed
 s.advance_game(7.5)
 var held: bool=h.hp==60.0
 s.advance_game(1.5)
 check("recovery_wait_then_slow_heal",held and h.hp>60.0 and h.hp<62.0,{"held_before_eight_seconds":held,"hp_after_nine_seconds":h.hp})
 var safe: Vector2=Coords.cell_center_logic(Vector2i(191,188))
 check("enemy_cannot_route_to_stable",s.nav.route(home,safe,true).is_empty())
 var target: Vector2i=Vector2i(110,100)
 s.known[s.state.index_of(target.x,target.y)]=0
 var accepted: Dictionary=s.move_helper(h.id,Coords.cell_center_logic(target))
 var before: Vector2=h.pos
 s.advance_game(0.25)
 var hidden: bool=accepted.ok and h.moving and h.status=="exploring" and h.pos!=before
 s.known[s.state.index_of(target.x,target.y)]=1
 s.advance_game(0.25)
 check("unknown_blocked_order_disclosed_only_after_known",hidden and not h.moving and h.status=="unreachable",{"accepted":accepted,"hidden_while_moving":hidden,"final_status":h.status})
 s.close()
func water_trip() -> void:
 var s: RefCounted=quiet()
 var result: Dictionary=s.place_helper("sprinkler",Vector2i(194,188))
 check("water_fixture",result.ok,result)
 if not result.ok: s.close(); return
 var h: Dictionary=s.helpers[0]
 var home: Vector2=h.home
 h.water=0.0
 var left_home: bool=false
 var steps: int=0
 while steps<240 and h.status!="refilling":
  s.advance_game(0.25)
  left_home=left_home or h.pos.distance_to(home)>4.0
  steps+=1
 var arrived: bool=h.status=="refilling"
 s.advance_game(2.5)
 var halfway: float=h.water
 s.advance_game(2.5)
 check("water_trip_then_five_second_refill",left_home and arrived and absf(halfway-50.0)<0.01 and h.water==100.0 and h.status=="returning_water",{"left_home":left_home,"arrived":arrived,"half":halfway,"full":h.water,"status":h.status})
 steps=0
 while steps<240 and h.status=="returning_water":
  s.advance_game(0.25); steps+=1
 check("water_returns_original_post_without_move_consumption",h.pos.distance_to(home)<4.0 and h.water==100.0,{"distance":h.pos.distance_to(home),"water":h.water,"status":h.status})
 # Boundary fixture with no reachable water sources; does not alter map data or player saves.
 s.nav.water_banks.clear(); h.water=0.0; h.status="working"
 var old: Vector2=h.pos
 s.advance_game(0.25)
 check("no_water_route_waits",h.status=="no_water_route" and h.pos==old,{"status":h.status,"position_unchanged":h.pos==old})
 s.close()
func source_activation() -> void:
 var s: RefCounted=Session.new()
 for c: Dictionary in s.clock.growth_ticked.get_connections(): s.clock.growth_ticked.disconnect(c.callable)
 for c: Dictionary in s.clock.spread_ticked.get_connections(): s.clock.spread_ticked.disconnect(c.callable)
 var n: Dictionary=s.nests[1]
 s.nests.assign([n]); s.enemies.clear()
 var start: Vector2=s.position
 s.advance_game(30.0)
 var dormant: bool=not n.active and s.enemies.is_empty()
 s.position=n.pos
 s.advance_game(4.0)
 var woke: bool=n.active and not s.enemies.is_empty()
 s.position=start
 s.advance_game(10.0)
 check("source_dormant_approach_and_delayed_stop",dormant and woke and not n.active,{"far_dormant":dormant,"near_active":woke,"after_leaving_active":n.active})
 var c: Vector2i=Coords.logic_to_cell(n.pos)
 var green_index: int=s.state.index_of(c.x,c.y)
 s.state.set_stage(green_index,WorldState.STAGE_SPROUT1)
 s.advance_game(0.25)
 check("green_proximity_activates_source",n.active)
 # End-state boundary only: long complete sweep already has one implementation-side run.
 for source: Dictionary in s.nests.duplicate(): s.combat_system.damage_nest(source,10000.0)
 for enemy: Dictionary in s.enemies.duplicate(): s.combat_system.damage_enemy(enemy,10000.0)
 s.advance_game(1.25)
 check("no_sources_no_enemies_marks_stable",s.state.zone_state[1]>=WorldState.ZONE_STABLE,s.snapshot())
 s.close()
