extends SceneTree
## usage: --script ... -- --in=<png> --out=<png> --rect=x,y,w,h --scale=n   (nearest-neighbour crop for visual review)
func _init() -> void:
	var a: Dictionary = {}
	for s: String in OS.get_cmdline_user_args():
		var p: PackedStringArray = s.substr(2).split("=", true, 1)
		a[p[0]] = p[1]
	var img: Image = Image.load_from_file(a["in"])
	var r: PackedStringArray = a["rect"].split(",")
	var c: Image = img.get_region(Rect2i(int(r[0]), int(r[1]), int(r[2]), int(r[3])))
	c.resize(c.get_width() * int(a["scale"]), c.get_height() * int(a["scale"]), Image.INTERPOLATE_NEAREST)
	c.save_png(a["out"])
	quit()
