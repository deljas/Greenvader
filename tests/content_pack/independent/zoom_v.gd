extends SceneTree
## 目視用: GPU画像の一部を整数倍(nearest)に拡大して保存する。判定には使わない。
func _initialize() -> void:
	var dir: String = "res://evidence/content_pack/independent/gpu/"
	var jobs: Array = [
		["lab_overview", Rect2i(60, 60, 200, 110), "zoom_a"],
		["lab_overview", Rect2i(180, 60, 200, 110), "zoom_b"],
		["lab_overview", Rect2i(0, 0, 160, 100), "zoom_water"],
		["lab_overview", Rect2i(60, 150, 200, 110), "zoom_c"],
		["lab_overview", Rect2i(300, 130, 212, 150), "zoom_d"],
		["lab_night", Rect2i(60, 60, 200, 110), "zoom_night"],
	]
	for j: Array in jobs:
		var im: Image = Image.load_from_file(ProjectSettings.globalize_path(dir + str(j[0]) + ".png"))
		var r: Rect2i = j[1]
		var c: Image = im.get_region(r)
		c.resize(r.size.x * 6, r.size.y * 6, Image.INTERPOLATE_NEAREST)
		c.save_png(dir + str(j[2]) + ".png")
	quit(0)
