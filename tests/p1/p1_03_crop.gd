extends SceneTree
## Re-cuts the x8 crop from the saved 640x360 GPU capture (headless, no GPU needed).
func _initialize() -> void:
	var image: Image = Image.load_from_file(ProjectSettings.globalize_path("res://evidence/p1/p1-03/gpu_viewport_640x360.png"))
	var crop: Image = image.get_region(Rect2i(135, 125, 130, 45))
	crop.resize(crop.get_width() * 8, crop.get_height() * 8, Image.INTERPOLATE_NEAREST)
	crop.save_png(ProjectSettings.globalize_path("res://evidence/p1/p1-03/gpu_scene_crop_x8.png"))
	print("CROP_DONE %s" % crop.get_size())
	quit()
