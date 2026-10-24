extends "res://tests/greening_map/wall_clip_self_base.gd"
func run() -> void:
	if not setup_lab():
		quit(2)
		return
	var state_before: PackedByteArray = var_to_bytes(lab.session.state.to_dict())
	var cases: Array[Dictionary] = [
		{"id":"A_front","start":Vector2(-3.2,1.8),"keys":[KEY_W,KEY_D]},
		{"id":"A_right","start":Vector2(1.0,-2.0),"keys":[KEY_W,KEY_A]},
		{"id":"A_corner","start":Vector2(1.0,1.8),"keys":[KEY_W]},
		{"id":"B_right","start":Vector2(6.5,-3.8),"keys":[KEY_W,KEY_A]},
		{"id":"B_front","start":Vector2(4.0,-0.8),"keys":[KEY_W,KEY_D]}
	]
	for item: Dictionary in cases:
		var codes: Array[int] = []
		for code: int in item["keys"]:
			codes.append(code)
		if item["id"]=="A_corner":
			# Axis sliding can leave the corner during a long diagonal push.
			lab.session.position = Session.to_logic(Vector2(Session.HALF.x/10.0,0.8+Session.HALF.y/10.0))
			lab.update_actor(Vector2.ZERO)
		else:
			await press_wall(item["start"],codes)
		var row: Dictionary = geometry_row(item["id"])
		row["visibility"] = await visible_pixels()
		rows.append(row)
		check(row["visibility"]["visible"]==row["visibility"]["opaque_fixture_pixels"],"visible_all_"+item["id"],str(row["visibility"]))
		check(Walker.is_clear(lab.session.state,4,lab.session.position,Session.HALF),"collision_clear_"+item["id"])
		await capture("after_"+item["id"],item["id"]=="A_right")
	# Whole rectangular card bounds cover all opaque texels and flips. Verify the
	# camera projection and shared physical board state for each frame/flip once.
	var ground: Vector2 = Session.to_ground(lab.session.position)
	var sync_rows: Array[Dictionary] = []
	var all_sync: bool = true
	var dimensions: bool = true
	for flip: bool in [false,true]:
		for frame: int in 4:
			lab.actor.pose(Vector3(ground.x,0.016,ground.y),frame,flip)
			var row: Dictionary = geometry_row("frame_%d_flip_%s" % [frame,str(flip)])
			var s: Dictionary = row["sync"]
			all_sync = all_sync and s["texture_match"] and s["flip_match"] and s["foot_match"]
			var bottom_left: Vector3 = Vector3(row["corners"][0][0],row["corners"][0][1],row["corners"][0][2])
			var bottom_right: Vector3 = Vector3(row["corners"][1][0],row["corners"][1][1],row["corners"][1][2])
			var top_left: Vector3 = Vector3(row["corners"][3][0],row["corners"][3][1],row["corners"][3][2])
			var width: float = lab.camera.unproject_position(bottom_right).x-lab.camera.unproject_position(bottom_left).x
			var height: float = lab.camera.unproject_position(bottom_left).y-lab.camera.unproject_position(top_left).y
			row["projected_size"] = [width,height]
			dimensions = dimensions and absf(width-16)<0.0001 and absf(height-24)<0.0001 and absf(top_left.x-bottom_left.x)<0.00001 and absf(top_left.z-bottom_left.z)<0.00001
			sync_rows.append(row)
	check(all_sync,"all_frames_flips_shared_physical_foot")
	check(dimensions,"upright_16x24_projection")
	var screen_foot: Vector2 = lab.camera.unproject_position(lab.actor.render_foot)
	check(screen_foot.distance_to(screen_foot.round())<0.0001,"presentation_foot_pixel_snap")
	lab.session.position = Session.to_logic(Vector2(-3.2,-5.5))
	lab.update_actor(Vector2.ZERO)
	var behind: Dictionary = geometry_row("behind_A")
	behind["visibility"] = await visible_pixels()
	rows.append(behind)
	check(behind["visibility"]["visible"]==0,"behind_occlusion_preserved",str(behind["visibility"]))
	await capture("after_behind_A")
	check(lab.actor.display_sprite.no_depth_test==false,"depth_test_remains_enabled")
	check(state_before==var_to_bytes(lab.session.state.to_dict()),"paused_wall_checks_state_unchanged")
	# Upright display stays in the same scene/layer and therefore enters the existing
	# reflection pass. Place it on the ray into the pond solely for this image pair.
	lab.session.position = Session.to_logic(Vector2(-7.9,3.0))
	lab.update_actor(Vector2.ZERO)
	await capture("after_reflection_actor")
	var reflection_on: Image = lab.water_surface.reflection_view.get_texture().get_image()
	reflection_on.save_png(OUT+"actor_reflection_ON_320.png")
	lab.actor.display_sprite.hide()
	await lab.wait_render()
	var reflection_off: Image = lab.water_surface.reflection_view.get_texture().get_image()
	reflection_off.save_png(OUT+"actor_reflection_OFF_320.png")
	check(reflection_on.get_data()!=reflection_off.get_data(),"upright_sprite_enters_reflection")
	lab.actor.display_sprite.show()
	var f: FileAccess = FileAccess.open(OUT+"after-raw.json",FileAccess.WRITE)
	f.store_string(JSON.stringify({"cases":rows,"frames_flips":sync_rows},"\t"))
	f = FileAccess.open(OUT+"gpu-results.json",FileAccess.WRITE)
	f.store_string(JSON.stringify({"results":checks,"failures":failures,"pixel_world":lab.actor.pixel_world,"min_foundation_wall_gap_m":0.09,"full_card_axis_half_m":8.0*lab.actor.pixel_world/sqrt(2.0),"snap_max_axis_m":1.5*lab.actor.pixel_world/sqrt(2.0),"chosen_half_m":Session.HALF.x/10.0},"\t"))
	quit(0 if failures==0 else 1)
