extends SceneTree
const Scene: PackedScene = preload("res://scenes/town_lab.tscn")
func _initialize() -> void:
	root.unfocusable = true
	run.call_deferred()
func run() -> void:
	var lab: Node = Scene.instantiate()
	lab.automatic = false
	root.add_child(lab)
	lab.set_playing(false)
	lab.position = Vector2(-4.7,-10.7)
	lab.follow_size = 13.5
	lab._update_camera()
	lab.set_hour(12)
	await lab.wait_render()
	lab.water.reflection_view.get_texture().get_image().save_png("res://evidence/town-lab/self/reflection_viewport_day_320.png")
	var on: Image = lab.render_view.get_texture().get_image()
	on.save_png("res://evidence/town-lab/self/water_building_reflection_640.png")
	var ui: Image = root.get_texture().get_image()
	ui.resize(1920,1080,Image.INTERPOLATE_NEAREST)
	ui.save_png("res://evidence/town-lab/self/water_building_reflection_ui_1920.png")
	lab.water.set_reflection(false)
	await lab.wait_render()
	var off: Image = lab.render_view.get_texture().get_image()
	off.save_png("res://evidence/town-lab/self/water_reflection_OFF_640.png")
	ui = root.get_texture().get_image()
	ui.resize(1920,1080,Image.INTERPOLATE_NEAREST)
	ui.save_png("res://evidence/town-lab/self/water_reflection_OFF_ui_1920.png")
	var changed: int = 0
	for y: int in range(on.get_height()):
		for x: int in range(on.get_width()):
			if on.get_pixel(x,y)!=off.get_pixel(x,y): changed += 1
	print("Shifted P1 reflection changed pixels: ",changed)
	lab.water.set_reflection(true)
	lab.set_hour(22)
	await lab.wait_render()
	lab.water.reflection_view.get_texture().get_image().save_png("res://evidence/town-lab/self/reflection_viewport_night_320.png")
	var night: Image = lab.render_view.get_texture().get_image()
	night.save_png("res://evidence/town-lab/self/water_night_building_reflection_640.png")
	ui = root.get_texture().get_image()
	ui.resize(1920,1080,Image.INTERPOLATE_NEAREST)
	ui.save_png("res://evidence/town-lab/self/water_night_building_reflection_ui_1920.png")
	# Refresh overview evidence after the one moved puddle, no repeated logic run.
	lab.reset_position()
	lab.toggle_camera()
	for item: Array in [["morning",7.0],["noon",12.0],["evening",17.0],["night",22.0]]:
		lab.set_hour(item[1])
		await lab.wait_render()
		lab.render_view.get_texture().get_image().save_png("res://evidence/town-lab/self/"+item[0]+"_overview_640.png")
		ui = root.get_texture().get_image()
		ui.resize(1920,1080,Image.INTERPOLATE_NEAREST)
		ui.save_png("res://evidence/town-lab/self/"+item[0]+"_overview_ui_1920.png")
	lab.free()
	await process_frame
	quit()
