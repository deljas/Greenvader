extends SceneTree
## Independent specification-derived checks. Execute only after the parent freezes the target.
## No user saves, OS input, or game implementation files are modified.
const Session: GDScript = preload("res://scripts/poc2/poc2_session.gd")
const OUT: String = "res://evidence/poc2/independent/logic-results.json"
var checks: Array[Dictionary] = []

func _init() -> void:
 call_deferred("run")

func check(name_: String, ok: bool, expected: Variant, actual: Variant) -> void:
 checks.append({"name":name_,"status":"PASS" if ok else "FAIL","expected":expected,"actual":actual})
 print("%s %s" % [checks.back().status,name_])

func isolated() -> RefCounted:
 var s: RefCounted = Session.new()
 # Isolate income and planted-object behaviour from terrain spread and enemy pressure.
 # These disconnected systems are exercised separately in the integration plan.
 for connection: Dictionary in s.clock.growth_ticked.get_connections():
  s.clock.growth_ticked.disconnect(connection.callable)
 for connection: Dictionary in s.clock.spread_ticked.get_connections():
  s.clock.spread_ticked.disconnect(connection.callable)
 s.enemies.clear()
 s.nests.clear()
 s.known.fill(1)
 return s

func run() -> void:
 economy()
 crops()
 ammunition()
 rewards()
 persistence()
 var failures: int = 0
 for item: Dictionary in checks:
  if item.status=="FAIL": failures+=1
 var output: Dictionary = {"scope":"independent isolated logic; see plan.md for integration and NOT_RUN boundaries","checks":checks,"failures":failures}
 var file: FileAccess = FileAccess.open(OUT,FileAccess.WRITE)
 if file!=null:
  file.store_string(JSON.stringify(output," "))
  file.close()
 quit(1 if failures>0 else 0)

func economy() -> void:
 var s: RefCounted = isolated()
 check("world_size_and_start",s.state.width==224 and s.state.height==224 and s.state.greened_count==250 and s.seeds==60,[224,224,250,60],[s.state.width,s.state.height,s.state.greened_count,s.seeds])
 var old_map: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/poc/maps/town_01.json"))
 check("map_each_axis_doubled",old_map["size"][0]*2==s.state.width and old_map["size"][1]*2==s.state.height,[112,112],old_map["size"])
 s.advance_game(60.0)
 check("start_income_one_minute",s.seeds==65 and is_equal_approx(s.land_rate(),5.0),[65,5], [s.seeds,s.land_rate()])
 var before: float = s.clock.elapsed
 s.paused=true
 s.advance_game(60.0)
 check("paused_clock_and_income",s.seeds==65 and s.clock.elapsed==before,[65,before],[s.seeds,s.clock.elapsed])
 s.close()

func crops() -> void:
 var s: RefCounted = isolated()
 s.seeds=1000
 var locked: Dictionary = s.place_plant("watermelon",Vector2i(190,188))
 check("fossil_locked_crop",not locked.ok and s.seeds==1000,"reject; unchanged seeds",[locked,s.seeds])
 var bare: Dictionary = s.place_plant("clover",Vector2i(190,180))
 check("crop_requires_green",not bare.ok,"reject on bare soil",bare)
 # Constants below come from POC2_SPEC table, never copied from CATALOG.
 var rows: Array = [["clover",10,2.0,20.0,Vector2i(180,183)], ["carrot",15,1.0,15.0,Vector2i(182,183)], ["wheat",40,12.0,45.0,Vector2i(184,183)], ["rafflesia",40,2.0,30.0,Vector2i(187,183)], ["watermelon",120,30.0,90.0,Vector2i(191,183)]]
 for row: Array in rows:
  s.unlocked[row[0]]=true
  var before: int=s.seeds
  var result: Dictionary=s.place_plant(row[0],row[4])
  check("place_"+row[0],result.ok and before-s.seeds==row[1],row[1],{"result":result,"spent":before-s.seeds})
 var overlap: Dictionary=s.place_plant("clover",Vector2i(192,185))
 check("whole_crop_footprint_occupied",not overlap.ok,"reject overlapping watermelon",overlap)
 var mixed: Dictionary=s.place_plant("watermelon",Vector2i(203,188))
 check("whole_footprint_requires_green",not mixed.ok,"reject partially green footprint",mixed)
 s.advance_game(14.5)
 check("no_production_before_maturity",is_zero_approx(s.crop_rate()),0,s.crop_rate())
 # One monotonic timeline checks boundaries, without repeated runs per plant.
 var boundaries: Array = [[15.0,1.0],[20.0,3.0],[30.0,5.0],[45.0,17.0],[90.0,47.0]]
 for boundary: Array in boundaries:
  s.advance_game(boundary[0]-s.clock.elapsed)
  check("production_at_"+str(boundary[0]),is_equal_approx(s.crop_rate(),boundary[1]),boundary[1],s.crop_rate())
 check("under_plant_land_income_kept",is_equal_approx(s.land_rate(),5.0),5,s.land_rate())
 var count_before: int=s.seeds
 s.advance_game(60.0)
 check("mature_combined_income",s.seeds-count_before==52,52,s.seeds-count_before)
 if not s.plants.is_empty():
  # A saved/discounted actual cost may be non-multiple-of-five: exercise rounding explicitly.
  var plant: Dictionary=s.plants[0]
  plant.cost=13
  var old_seeds: int=s.seeds
  var removed: Dictionary=s.remove_plant(int(plant.id))
  check("refund_actual_paid_floor",removed.ok and s.seeds-old_seeds==2,2,s.seeds-old_seeds)
 s.close()

func ammunition() -> void:
 var s: RefCounted=isolated()
 s.seeds=200
 s.unlocked.gatlinger=true
 var result: Dictionary=s.place_helper("gatlinger",Vector2i(190,180),30)
 check("helper_on_bare_ground",result.ok,"allowed",result)
 if result.ok:
  var h: Dictionary=s.helpers[0]
  check("initial_ammo_transfer",s.seeds==140 and h.ammo==30,[140,30],[s.seeds,h.ammo])
  var supplied: Dictionary=s.supply_helper(h.id,20)
  check("remote_ammo_conserved",supplied.ok and s.seeds==120 and h.ammo==50,[120,50],[s.seeds,h.ammo])
  var overflow: Dictionary=s.supply_helper(h.id,51)
  check("overflow_transfer_atomic",not overflow.ok and s.seeds==120 and h.ammo==50,[120,50],[s.seeds,h.ammo,overflow])
  var before: int=s.seeds
  s.paused=true
  var removal: Dictionary=s.remove_helper(h.id)
  check("paused_remove_refunds_ammo_and_twenty_percent",removal.ok and s.seeds-before==56,56,s.seeds-before)
 s.paused=false
 var death: Dictionary=s.place_helper("gatlinger",Vector2i(190,180),10)
 if death.ok:
  var before_death: int=s.seeds
  s.helpers[0].hp=0.0
  s.advance_game(0.25)
  check("death_no_ammo_or_cost_refund",s.helpers.is_empty() and s.seeds==before_death,before_death,[s.seeds,s.helpers.size()])
 s.close()

func rewards() -> void:
 var s: RefCounted=Session.new()
 var small: Dictionary={}
 var strong: Dictionary={}
 for enemy: Dictionary in s.enemies:
  if enemy.strong: strong=enemy
  else: small=enemy
 if not small.is_empty():
  var before: int=s.seeds
  s.combat_system.damage_enemy(small,1000.0)
  check("initial_small_reward",s.seeds-before==6,6,s.seeds-before)
 if not strong.is_empty():
  var before: int=s.seeds
  s.combat_system.damage_enemy(strong,1000.0)
  check("initial_strong_reward",s.seeds-before==15,15,s.seeds-before)
 var source: Dictionary=s.nests[0]
 s.combat_system.spawn(source,false)
 var born: Dictionary=s.enemies.back()
 var before: int=s.seeds
 s.combat_system.damage_enemy(born,1000.0)
 check("produced_enemy_zero_reward",s.seeds==before,before,s.seeds)
 for scale_: String in ["small","medium","large"]:
  for nest: Dictionary in s.nests.duplicate():
   if nest.scale!=scale_: continue
   var reward: int={"small":30,"medium":80,"large":200}[scale_]
   before=s.seeds
   s.combat_system.damage_nest(nest,1000.0)
   check("nest_reward_"+scale_,s.seeds-before==reward,reward,s.seeds-before)
   break
 s.close()

func persistence() -> void:
 var s: RefCounted=isolated()
 s.unlocked.gatlinger=true
 s.seeds=200
 var result: Dictionary=s.place_helper("gatlinger",Vector2i(190,180),17)
 if not result.ok:
  check("save_fixture_place",false,true,result)
  s.close()
  return
 s.move_helper(result.id,Vector2(750,730))
 s.income_fraction=0.375
 s.paused=true
 var saved: Dictionary=s.to_dict()
 var other: RefCounted=Session.new()
 var restored: Dictionary=other.restore(saved)
 check("restore_economy_unlock_command",restored.ok and other.seeds==s.seeds and is_equal_approx(other.income_fraction,0.375) and other.unlocked.get("gatlinger",false) and other.helpers.size()==1 and other.helpers[0].ammo==17 and other.helpers[0].home==s.helpers[0].home,"same seeds/fraction/unlock/ammo/home",{"result":restored,"seeds":other.seeds,"fraction":other.income_fraction,"helpers":other.helpers.size()})
 var before: String=JSON.stringify(other.to_dict())
 var corrupt: Dictionary=saved.duplicate(true)
 corrupt.values["seeds"]=-1
 var rejected: Dictionary=other.restore(corrupt)
 check("invalid_restore_atomic",not rejected.ok and before==JSON.stringify(other.to_dict()),"reject; entire current snapshot unchanged",rejected)
 s.close()
 other.close()
