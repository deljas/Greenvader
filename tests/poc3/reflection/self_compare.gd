extends SceneTree
## Fixed native-card water-bank comparison. No OS input or simulation advance.
const OUT: String = "res://evidence/poc3/reflection/self/"
const Water: GDScript = preload("res://scripts/poc/environment/water_view.gd")
const Actor: GDScript = preload("res://scripts/poc/poc_actor.gd")
const Card: GDScript = preload("res://scripts/poc2/view/entity_sprite.gd")
const Catalog: GDScript = preload("res://scripts/poc2/view/entity_sprite_catalog.gd")
const CameraGeometry: GDScript = preload("res://scripts/poc2/view/camera_geometry.gd")
const Coords: GDScript = preload("res://scripts/poc/poc_coords.gd")
const Day: GDScript = preload("res://scripts/poc/environment/poc_day.gd")
const Session: GDScript = preload("res://scripts/poc2/poc2_session.gd")
const World: GDScript = preload("res://scripts/poc2/view/world_view.gd")

class ReflectionSource extends RefCounted:
	var state: WorldState
	var weather: RefCounted = null

var checks: Array[Dictionary] = []
var observations: Dictionary = {}
var viewport: SubViewport
var scene: Node3D
var camera: Camera3D
var sun: DirectionalLight3D
var water: Node3D
var actor: Node3D
var cards: Array[Node3D] = []
var catalog: RefCounted = Catalog.new()
var bank: Vector3
var forward: Vector3

func _init() -> void:
	call_deferred("run")

func check(label: String, passed: bool, detail: Variant = "") -> void:
	checks.append({"name":label,"status":"PASS" if passed else "FAIL","detail":detail})
	print(JSON.stringify(checks.back()))

func frames(count: int = 3) -> void:
	for index: int in count: await process_frame

func safe_window() -> bool:
	return root.unfocusable and root.mode==Window.MODE_MINIMIZED and ProjectSettings.get_setting("display/window/size/no_focus",false) and ProjectSettings.get_setting("display/window/size/mode",-1)==1

func finish() -> void:
	var failures: int = 0
	for row: Dictionary in checks:
		if row.status=="FAIL": failures+=1
	var file_name: String = "normal_results.json" if OS.get_cmdline_user_args().has("--normal-only") else "compare_results.json"
	var file: FileAccess = FileAccess.open(OUT+file_name,FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"observations":observations,"not_run":["physical input","all lighting/weather/geometry","full-map GPU timing","final art approval"]},"  "))
	file.close()
	quit(1 if failures else 0)

func make_view() -> void:
	viewport=SubViewport.new()
	viewport.size=Vector2i(640,360)
	viewport.own_world_3d=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	viewport.transparent_bg=false
	viewport.msaa_3d=Viewport.MSAA_DISABLED
	viewport.screen_space_aa=Viewport.SCREEN_SPACE_AA_DISABLED
	viewport.use_taa=false
	root.add_child(viewport)
	scene=Node3D.new()
	viewport.add_child(scene)

func build_fixture() -> void:
	make_view()
	bank=Coords.ground3(Coords.cell_center_ground(Vector2i(32,32)))
	camera=Camera3D.new()
	scene.add_child(camera)
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect=Camera3D.KEEP_HEIGHT
	camera.size=18.5
	camera.near=0.05
	camera.far=150.0
	camera.transform=CameraGeometry.transform_for(Coords.cell_center_logic(Vector2i(32,32)))
	camera.current=true
	forward=Vector3(camera.global_basis.z.x,0,camera.global_basis.z.z).normalized()
	var env_node: WorldEnvironment = WorldEnvironment.new()
	var environment: Environment = Environment.new()
	environment.background_mode=Environment.BG_COLOR
	environment.background_color=Color("29332f")
	environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color=Color("9fadb8")
	environment.ambient_light_energy=0.55
	env_node.environment=environment
	scene.add_child(env_node)
	sun=DirectionalLight3D.new()
	sun.light_energy=0.8
	sun.shadow_enabled=true
	sun.shadow_caster_mask=1|8
	sun.transform=Transform3D(Basis.looking_at(Vector3(-0.4,-0.8,-0.5),Vector3.UP),Vector3(0,10,0))
	scene.add_child(sun)
	# Same water/Actor/card implementations as the game; synthetic bank removes building occlusion.
	var source: ReflectionSource = ReflectionSource.new()
	var defs: Array[TerrainDef] = []
	source.state=WorldState.new(64,64,defs,31)
	for y: int in 64:
		for x: int in 64:
			var point: Vector3 = Coords.ground3(Coords.cell_center_ground(Vector2i(x,y)))
			source.state.terrain[source.state.index_of(x,y)]=3 if (point-bank).dot(forward)>0.12 else 0
	var floor_node: MeshInstance3D = MeshInstance3D.new()
	var floor_mesh: PlaneMesh = PlaneMesh.new()
	floor_mesh.size=Vector2(26,26)
	floor_node.mesh=floor_mesh
	floor_node.position=bank-Vector3.UP*0.02
	floor_node.layers=2
	var floor_material: StandardMaterial3D = StandardMaterial3D.new()
	floor_material.albedo_color=Color("7b816c")
	floor_node.material_override=floor_material
	scene.add_child(floor_node)
	water=Water.new()
	scene.add_child(water)
	water.setup(viewport,camera,source,Day.load_tuning(),null)
	water.set_daylight(1.0)
	actor=Actor.new()
	scene.add_child(actor)
	actor.setup(camera)
	for index: int in 3:
		var card: Node3D = Card.new()
		scene.add_child(card)
		cards.append(card)
	pose_fixture(0)

func pose_fixture(step: int) -> void:
	var moving: bool = step>0 and step<5
	var direction: StringName = &"left" if step==5 else (&"right" if step==6 else &"down")
	var shift: float = float(mini(step,4))*0.12 if moving else 0.0
	var right: Vector3 = camera.global_basis.x
	actor.pose(bank+right*(-2.8+shift),posmod(step-1,4),direction,sun,0,moving)
	var boar_direction: StringName = &"left" if step==5 else &"right"
	cards[0].pose(catalog.definition_for("enemies","boar"),{"state":"move" if moving else "idle","direction":boar_direction},bank+right*(2.8+shift),camera,sun,float(step)/8.0)
	cards[1].pose(catalog.definition_for("plants","clover"),{"state":"mature","direction":&"down"},bank+right*(-0.8),camera,sun,0.0)
	cards[2].pose(catalog.definition_for("plants","carrot"),{"state":"mature","direction":&"down"},bank+right*0.8,camera,sun,0.0)
	water.sync_camera()

func capture(label: String) -> bool:
	await frames()
	RenderingServer.force_draw(false)
	var full: Image = viewport.get_texture().get_image()
	var reflected: Image = water.reflection_view.get_texture().get_image()
	return full.save_png(OUT+label+".png")==OK and reflected.save_png(OUT+label+"_reflection.png")==OK

func measure_interval() -> Dictionary:
	# One short sample block per divisor. This is CPU time waiting for force_draw, NOT isolated GPU time.
	var samples: Array[float] = []
	for sample: int in 12:
		await process_frame
		var start: int = Time.get_ticks_usec()
		RenderingServer.force_draw(false)
		samples.append(float(Time.get_ticks_usec()-start)/1000.0)
	samples.sort()
	return {"label":"synchronous_force_draw_CPU_wait_ms_not_GPU_timer","sample_count":samples.size(),"median_ms":samples[samples.size()/2],"minimum_ms":samples.front(),"maximum_ms":samples.back(),"global_draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"global_primitives":Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)}

func normal_connection() -> void:
	if is_instance_valid(viewport): viewport.free()
	make_view()
	var session: RefCounted = Session.new()
	var chosen: Vector2i = Vector2i(-1,-1)
	# Find a real water-bank tile with legal walkable, unoccupied footing. No fixed map ID assumption.
	for y: int in range(2,session.state.height-2):
		for x: int in range(3,session.state.width-3):
			var i: int = session.state.index_of(x,y)
			if session.state.terrain[i]!=3: continue
			var candidate: Vector2i = Vector2i(x,y-1)
			if session.state.is_walkable(candidate.x,candidate.y) and session.state.occupant[session.state.index_of(candidate.x,candidate.y)]==0:
				if session.state.terrain[session.state.index_of(x-2,y)]==3 and session.state.terrain[session.state.index_of(x+2,y)]==3:
					chosen=candidate
					break
		if chosen.x>=0: break
	check("normal_real_bank_found",chosen.x>=0,str(chosen))
	if chosen.x<0:
		session.close()
		return
	session.position=Coords.cell_center_logic(chosen)
	var world: Node3D = World.new()
	scene.add_child(world)
	var before_tuning: String = JSON.stringify(session.env_tuning,"",false,true)
	world.build(session,viewport)
	check("source_environment_tuning_unchanged",before_tuning==JSON.stringify(session.env_tuning,"",false,true) and int(Day.load_tuning().get("water",{}).get("reflection_divisor",-1))==2)
	await frames()
	RenderingServer.force_draw(false)
	check("normal_world_capture",viewport.get_texture().get_image().save_png(OUT+"normal_world_connection.png")==OK)
	observations.normal_connection={"water_divisor":world.water.divisor,"reflection_size":str(world.water.reflection_view.size),"main_size":str(viewport.size),"player_cell":str(chosen)}
	# Set the expected new connection only after the parent authorizes the game change.
	if OS.get_cmdline_user_args().has("--expect-divisor=1"):
		check("normal_world_full_resolution_connected",world.water.divisor==1 and world.water.reflection_view.size==Vector2i(640,360))
	session.close()

func run() -> void:
	# A script/runtime failure must not leave a minimized test process running indefinitely.
	create_timer(90.0).timeout.connect(func() -> void:
		check("watchdog_completed_before_90s",false)
		finish())
	var isolated: bool = OS.get_user_data_dir().replace("\\","/").contains("evidence/poc3/reflection/self/profile/")
	check("startup_minimized_unfocusable_isolated",safe_window() and isolated)
	if not safe_window() or not isolated:
		finish()
		return
	if OS.get_cmdline_user_args().has("--normal-only"):
		await normal_connection()
		check("finished_minimized_unfocusable",safe_window())
		finish()
		return
	build_fixture()
	check("fixture_native_nearest_no_aa",viewport.size==Vector2i(640,360) and viewport.msaa_3d==Viewport.MSAA_DISABLED and actor.display_sprite.texture_filter==BaseMaterial3D.TEXTURE_FILTER_NEAREST and cards[0].body.texture_filter==BaseMaterial3D.TEXTURE_FILTER_NEAREST)
	for divisor: int in [2,1]:
		water.divisor=divisor
		water.set_render_size(Vector2i(640,360))
		var labels: Array[String] = ["still","walk0","walk1","walk2","walk3","turn_left","turn_right"]
		for step: int in labels.size():
			pose_fixture(step)
			check("capture_d%d_%s"%[divisor,labels[step]],await capture("d%d_%s"%[divisor,labels[step]]))
			observations["d%d_%s"%[divisor,labels[step]]]={"actor":actor.snapshot(),"actor_reflection_foot":str(water.reflection_camera.unproject_position(actor.render_foot)),"boar":cards[0].snapshot(),"clover":cards[1].snapshot(),"carrot":cards[2].snapshot()}
		check("reflection_size_d%d"%divisor,water.reflection_view.size==Vector2i(640/divisor,360/divisor))
		observations["d"+str(divisor)]=await measure_interval()
	check("finished_minimized_unfocusable",safe_window())
	finish()
