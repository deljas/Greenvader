extends SceneTree
## One bounded 4s loop (72 samples), fixed-pose shadow proof, no OS input.
const Scene: PackedScene = preload("res://scenes/sprite_shadow_lab.tscn")
const OUT: String = "res://evidence/render-study-3d/sprite-shadow/self/"
var lab: Node
var sync_log: Array[Dictionary] = []
var results: Array[Dictionary] = []
var failures: int = 0

func _initialize() -> void:
	root.unfocusable = true
	run.call_deferred()

func check(ok: bool, id: String, detail: String = "") -> void:
	results.append({"id":id,"status":"PASS" if ok else "FAIL","detail":detail})
	if not ok:
		failures += 1
	print("%s %s %s" % ["PASS" if ok else "FAIL",id,detail])

func capture(label_: String, output3x: bool = false) -> Image:
	await lab.study.wait_render()
	var image: Image = lab.study.render_view.get_texture().get_image()
	image.save_png(OUT + label_ + "_640.png")
	var snapshot: Dictionary = lab.sync_snapshot()
	snapshot["sample"] = label_
	sync_log.append(snapshot)
	if output3x:
		var output: Image = lab.study.doubled_view.get_texture().get_image()
		output.save_png(OUT + label_ + "_1920.png")
		var expected: Image = image.duplicate()
		expected.resize(1920,1080,Image.INTERPOLATE_NEAREST)
		check(output.get_data() == expected.get_data(),"PNG.exact_nearest_3x")
	return image

func shadow_mask(on: Image, off: Image) -> Dictionary:
	var mask: Image = Image.create(640,360,false,Image.FORMAT_RGB8)
	mask.fill(Color.BLACK)
	var count: int = 0
	for y: int in 360:
		for x: int in 640:
			if on.get_pixel(x,y) != off.get_pixel(x,y):
				mask.set_pixel(x,y,Color.WHITE)
				count += 1
	return {"image":mask,"pixels":count}

func run() -> void:
	lab = Scene.instantiate()
	lab.automatic = false
	root.add_child(lab)
	var device: String = RenderingServer.get_video_adapter_name()
	if DisplayServer.get_name() == "headless" or device.is_empty():
		push_error("NOT_RUN: real GPU required")
		quit(2)
		return
	# First representative before any loop. Fixed foot and same light for all four.
	lab.apply_pose(0,false,lab.HOME)
	var pose0: Image = await capture("fixed_pose0_on",true)
	print("FIRST_IMAGE " + ProjectSettings.globalize_path(OUT+"fixed_pose0_on_1920.png"))
	lab.shadow_board.visible = false
	var off0: Image = await capture("fixed_pose0_off")
	lab.apply_pose(2,false,lab.HOME)
	lab.shadow_board.visible = true
	var pose2: Image = await capture("fixed_pose2_on")
	lab.shadow_board.visible = false
	var off2: Image = await capture("fixed_pose2_off")
	var mask0: Dictionary = shadow_mask(pose0,off0)
	var mask2: Dictionary = shadow_mask(pose2,off2)
	mask0["image"].save_png(OUT+"shadow_mask_pose0.png")
	mask2["image"].save_png(OUT+"shadow_mask_pose2.png")
	check(mask0["pixels"] > 20 and mask2["pixels"] > 20,"GPU.real_alpha_shadow","pose0=%d pose2=%d changed pixels vs own caster-OFF reference" % [mask0["pixels"],mask2["pixels"]])
	check(mask0["image"].get_data() != mask2["image"].get_data(),"GPU.pose_changes_shadow_outline")
	# Derived close-up is an integer crop/nearest enlargement of the GPU PNG.
	var crop: Image = pose0.get_region(Rect2i(272,222,192,112))
	crop.resize(1152,672,Image.INTERPOLATE_NEAREST)
	crop.save_png(OUT+"fixed_pose0_closeup_6x.png")
	lab.shadow_board.visible = true
	for i: int in 72:
		lab.pose_at_time(float(i)/18.0)
		await capture("frames/walk_%03d" % i)
	var all_sync: bool = true
	var flipped_samples: int = 0
	var frame_set: Dictionary = {}
	for snapshot: Dictionary in sync_log:
		all_sync = all_sync and snapshot["texture_match"] and snapshot["flip_match"] and snapshot["foot_match"]
		if snapshot["flip"]:
			flipped_samples += 1
		frame_set[snapshot["frame"]] = true
	check(all_sync and frame_set.size() == 4 and flipped_samples > 0,"sync.every_sample","%d captures, 4 poses, flip samples=%d" % [sync_log.size(),flipped_samples])
	# One optional building-occlusion example, same true depth test.
	lab.apply_pose(0,false,Vector3(-1.2,lab.GROUND_Y,-2.85))
	await capture("behind_building")
	for i: int in lab.textures.size():
		lab.textures[i].get_image().save_png("res://assets/render_study_3d/sprite_shadow/fixture_%d.png" % i)
	var file: FileAccess = FileAccess.open(OUT+"sync-frames.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(sync_log,"\t"))
	file.close()
	file = FileAccess.open(OUT+"checks.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":results,"failures":failures,"device":device,"frames":72,"sample_fps":18,"duration_seconds":4.0,"pixel_world":lab.pixel_world,"fixed_shadow0_pixels":mask0["pixels"],"fixed_shadow2_pixels":mask2["pixels"],"native":"NOT_RUN","physical_input":"NOT_RUN","video":"PNG series is lossless; external MP4 encode may change color/pixels"},"\t"))
	file.close()
	print("SPRITE_SHADOW_DONE failures=%d frames=72" % failures)
	quit(0 if failures == 0 else 1)
