extends SceneTree
## Evidence helper: crops the area around the player (screen centre) of a capture and upscales it (nearest) for inspection.
func _init() -> void:
	for name: String in ["occlusion_640", "occlusion_960", "full_day_640", "combat_640", "stable_960"]:
		var image: Image = Image.load_from_file(ProjectSettings.globalize_path("res://evidence/poc/09/%s.png" % name))
		var w: int = image.get_width()
		var h: int = image.get_height()
		var cw: int = w / 5
		var ch: int = h / 4
		var crop: Image = image.get_region(Rect2i(w / 2 - cw / 2, h * 45 / 100 - ch / 2, cw, ch))
		crop.resize(cw * 4, ch * 4, Image.INTERPOLATE_NEAREST)
		crop.save_png(ProjectSettings.globalize_path("res://evidence/poc/09/zoom_%s.png" % name))
	quit(0)
