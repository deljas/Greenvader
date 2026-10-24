extends SceneTree
const Session: GDScript=preload("res://scripts/poc2/poc2_session.gd")
var checks: Array[Dictionary]=[]
func check(name: String,condition: bool,detail: Variant = "") -> void:
 checks.append({"name":name,"pass":condition,"detail":detail})
 print("PASS " if condition else "FAIL ",name," ",detail)
func ready() -> RefCounted:
 var s: RefCounted=Session.new()
 s.enemies.clear(); s.nests.clear()
 s.unlocked={"clover":true,"carrot":true,"wheat":true,"rafflesia":true,"watermelon":true,"army":true,"gatlinger":true,"sprinkler":true}
 s.seeds=1000
 return s
func _initialize() -> void:
 var s: RefCounted=Session.new()
 check("world224_and_initial250",s.state.width==224 and s.state.height==224 and s.state.greened_count==250,s.snapshot())
 check("initial_stock_income_skills",s.seeds==60 and is_equal_approx(s.land_rate(),5.0) and s.skills==["tackle","bazooka"])
 var dormant: Dictionary=s.nests.back()
 s.advance_game(1.0)
 check("far_nest_dormant",not dormant.active)
 var initial: Dictionary=s.enemies[0]
 var before: int=s.seeds
 s.combat_system.damage_enemy(initial,1000)
 check("initial_enemy_reward",s.seeds-before==6)
 var n: Dictionary=s.nests[0]
 s.combat_system.spawn(n,false)
 var spawned: Dictionary=s.enemies.back()
 before=s.seeds
 s.combat_system.damage_enemy(spawned,1000)
 check("spawned_enemy_zero_reward",s.seeds==before)
 before=s.seeds
 s.combat_system.damage_nest(n,1000)
 check("small_nest_reward_unlock",s.seeds-before==30 and s.unlocked.get("army",false))
 var elapsed: float=s.clock.elapsed
 s.paused=true; s.advance_game(20.0)
 check("pause_time_and_movement",s.clock.elapsed==elapsed and s.walk(Vector2.RIGHT,1.0)==Vector2.ZERO)
 s.close()
 s=ready()
 var cell: Vector2i=Vector2i(184,186)
 var green_before: int=s.state.greened_count
 var out: Dictionary=s.place_plant("clover",cell)
 check("crop_cost_and_land_preserved",out.ok and s.seeds==990 and s.state.greened_count==green_before)
 s.advance_game(19.75)
 check("crop_not_premature",not s.plants[0].mature)
 s.advance_game(0.25)
 check("crop_matures20_rate2",s.plants[0].mature and is_equal_approx(s.crop_rate(),2.0))
 before=s.seeds
 var refund: Dictionary=s.remove_plant(int(s.plants[0].id))
 check("remove20percent",refund.ok and s.seeds==before+2)
 check("crop_requires_green",not s.place_plant("clover",Vector2i(180,180)).ok)
 out=s.place_helper("gatlinger",Vector2i(180,180),5)
 check("helper_wasteland_and_budget",out.ok and s.helpers[0].ammo==5)
 var h: Dictionary=s.helpers[0]
 before=s.seeds
 s.advance_game(16.0)
 check("finite_ammo_no_auto_debit",h.ammo==0 and s.seeds>=before,h.ammo)
 before=s.seeds
 check("remote_supply",s.supply_helper(int(h.id),7).ok and h.ammo==7 and s.seeds==before-7)
 before=s.seeds
 s.remove_helper(int(h.id))
 check("remove_unused_ammo_full",s.seeds-before==13)
 out=s.place_helper("army",Vector2i(185,186))
 h=s.helpers.back(); h.hp=60.0; h.last_combat=s.clock.elapsed
 s.advance_game(7.75)
 check("helper_heal_delay",h.hp==60.0)
 s.advance_game(1.25)
 check("helper_heals_noncombat",h.hp>60.0 and h.hp<=61.5,h.hp)
 var unknown: Vector2i=Vector2i(110,100)
 s.known[s.state.index_of(unknown.x,unknown.y)]=0
 check("unknown_order_accepted",s.move_helper(int(h.id),Session.Coords.cell_center_logic(unknown)).ok)
 s.advance_game(0.25)
 check("unknown_order_does_not_leak_obstacle",h.status=="exploring" and h.moving)
 # Save includes crop maturation, fractional income, finite stores, orders, shots, RNG and exploration.
 s.place_plant("carrot",Vector2i(186,188))
 s.position=Session.Coords.cell_center_logic(Vector2i(191,188))
 s.set_aim(s.position+Vector2(20,0)); s.fire()
 var data: Dictionary=JSON.parse_string(JSON.stringify(s.to_dict()))
 var restored: Dictionary=s.restore(data)
 check("json_roundtrip",restored.ok,restored)
 check("save_roundtrip_exact",JSON.parse_string(JSON.stringify(s.to_dict()))==data)
 var before_data: String=JSON.stringify(s.to_dict())
 var bad: Dictionary=data.duplicate(true); bad.values.seeds=-1
 check("bad_save_atomic",not s.restore(bad).ok and JSON.stringify(s.to_dict())==before_data)
 bad=data.duplicate(true); bad.world.occupancy_owners={"oops":[]}
 check("bad_ownership_rejected",not s.restore(bad).ok)
 s.close()
 s=ready()
 var bank: Vector2=s.nav.bank(s.position)
 check("reachable_water_bank",bank.x>=0 and not s.nav.route(s.position,bank).is_empty(),bank)
 s.position=bank; s.known.fill(1)
 out=s.place_helper("sprinkler",Session.Coords.logic_to_cell(bank))
 h=s.helpers.back(); h.water=0.0
 s.advance_game(5.25)
 check("sprinkler_refills5seconds",h.water==100.0,h.water)
 s.close()
 s=ready()
 # Stable completion includes a genuine water-isolated island and land underneath helpers.
 s.known.fill(1)
 s.place_helper("army",Vector2i(152,148))
 s._check_zone()
 check("sweep_stable_only",s.state.zone_state[1]>=2)
 s.advance_game(3500.0)
 check("stable_island_100percent",s.state.greened_count==s.state.target_count and s.state.cleared,s.snapshot())
 s.close()
 var fail_count: int=0
 for entry: Dictionary in checks:
  if not entry.pass: fail_count+=1
 var output: Dictionary={"checks":checks,"pass":checks.size()-fail_count,"fail":fail_count,"not_run":["GPU rendering","physical OS input","art/fun acceptance"],"long_time_policy":"one 3500 game-second condition; advance_game fixed internal 0.25s deterministic steps"}
 var file: FileAccess=FileAccess.open("res://evidence/poc2/self/simulation_results.json",FileAccess.WRITE)
 file.store_string(JSON.stringify(output," ")); file.close()
 print("RESULT ",checks.size()-fail_count," PASS / ",fail_count," FAIL")
 quit(1 if fail_count else 0)
