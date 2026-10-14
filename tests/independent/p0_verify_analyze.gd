extends SceneTree
## Offline pixel analysis of window captures (P0-VERIFY V2/V3). Usage:
## godot --headless --path <proj> --script res://tests/independent/p0_verify_analyze.gd -- --dir=<abs> --exp=<abs oracle json> --out=<abs json>
## Expected margins/scale come from tests/independent/p0_layout_oracle.ps1 (spec-derived), not from game code.

func _init() -> void:
	var args: Dictionary = {}
	for a: String in OS.get_cmdline_user_args():
		var parts: PackedStringArray = a.substr(2).split("=", true, 1)
		args[parts[0]] = parts[1]
	var dir: String = args["dir"]
	var exp_all: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args["exp"]))
	var results: Array = []
	results.append(self_test())
	for f: String in DirAccess.get_files_at(dir):
		if not f.ends_with("-captures.json") or not (f.begins_with("v2-")):
			continue
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join(f)))
		for rec: Dictionary in data["captures"]:
			results.append(analyze(dir, rec, exp_all, data["tag"]))
	var fa: FileAccess = FileAccess.open(args["out"], FileAccess.WRITE)
	fa.store_string(JSON.stringify(results, "  ", true, true))
	fa.close()
	quit()

func block_uniform(crop: Image, k: int) -> bool:
	var down: Image = crop.duplicate()
	down.resize(crop.get_width() / k, crop.get_height() / k, Image.INTERPOLATE_NEAREST)
	var up: Image = down.duplicate()
	up.resize(crop.get_width(), crop.get_height(), Image.INTERPOLATE_NEAREST)
	return up.get_data() == crop.get_data()

func count_nonuniform(crop: Image, k: int) -> int:
	var bad: int = 0
	var bw: int = crop.get_width() / k
	var bh: int = crop.get_height() / k
	for by: int in bh:
		for bx: int in bw:
			var c0: Color = crop.get_pixel(bx * k, by * k)
			var ok: bool = true
			for y: int in k:
				for x: int in k:
					if crop.get_pixel(bx * k + x, by * k + y) != c0:
						ok = false
						break
				if not ok:
					break
			if not ok:
				bad += 1
	return bad

func list_nonuniform(crop: Image, k: int) -> Array:
	var bad: Array = []
	var bw: int = crop.get_width() / k
	var bh: int = crop.get_height() / k
	for by: int in bh:
		for bx: int in bw:
			var c0: Color = crop.get_pixel(bx * k, by * k)
			var ok: bool = true
			for y: int in k:
				for x: int in k:
					if crop.get_pixel(bx * k + x, by * k + y) != c0:
						ok = false
				if not ok:
					break
			if not ok:
				bad.append(Vector2i(bx, by))
	return bad

func self_test() -> Dictionary:
	var small: Image = Image.create(64, 36, false, Image.FORMAT_RGBA8)
	for y: int in 36:
		for x: int in 64:
			small.set_pixel(x, y, Color8((x * 37) % 256, (y * 91) % 256, (x * y) % 256))
	var big: Image = small.duplicate()
	big.resize(64 * 3, 36 * 3, Image.INTERPOLATE_NEAREST)
	var uniform_detected: bool = block_uniform(big, 3)
	var broken: Image = big.duplicate()
	broken.set_pixel(100, 50, Color(1, 0, 1))
	var broken_detected: bool = not block_uniform(broken, 3)
	var shifted: Image = Image.create(192, 108, false, Image.FORMAT_RGBA8)
	shifted.blit_rect(big, Rect2i(1, 0, 191, 108), Vector2i(0, 0))
	var shift_detected: bool = not block_uniform(shifted, 3)
	var slow: int = count_nonuniform(broken, 3)
	return {"self_test": true, "uniform_image_passes": uniform_detected, "single_bad_pixel_detected": broken_detected, "one_pixel_shift_detected": shift_detected, "slow_count_for_single_bad_pixel": slow,
		"ok": uniform_detected and broken_detected and shift_detected and slow == 1}

func analyze(dir: String, rec: Dictionary, exp_all: Dictionary, tag: String) -> Dictionary:
	var r: Dictionary = {"tag": tag, "label": rec["label"], "file": rec["file"]}
	var img: Image = Image.load_from_file(dir.path_join(rec["file"]))
	if img == null:
		r["error"] = "cannot load"
		return r
	img.convert(Image.FORMAT_RGBA8)
	var w: int = img.get_width()
	var h: int = img.get_height()
	r["image_size"] = "%dx%d" % [w, h]
	var key: String = "%dx%d" % [w, h]
	if not exp_all.has(key):
		r["error"] = "no oracle for " + key
		return r
	var e: Dictionary = exp_all[key]
	var k: int = int(e["IntegerScale"])
	var L: int = int(e["LeftMargin"])
	var R: int = int(e["RightMargin"])
	var T: int = int(e["TopMargin"])
	var B: int = int(e["BottomMargin"])
	r["expected"] = {"k": k, "L": L, "R": R, "T": T, "B": B, "content": "%dx%d" % [e["ContentWidth"], e["ContentHeight"]]}
	var stride: int = w * 4
	var data: PackedByteArray = img.get_data()
	var mask_corners: bool = (rec.get("method", "screen_get_image_rect") != "PrintWindow") and key != "1920x1080"
	r["capture_method"] = rec.get("method", "screen_get_image_rect")
	r["bottom_corner_mask_12px_applied"] = mask_corners
	var c0: Color = Color(0, 0, 0, 1)
	if L > 0:
		c0 = img.get_pixel(L / 2, h / 2)
	elif T > 0:
		c0 = img.get_pixel(w / 2, T / 2)
	var raw: Image = img.duplicate()
	if mask_corners:
		# DWM rounds the bottom corners of decorated windows; those client pixels are desktop/black, not game output.
		img.fill_rect(Rect2i(0, h - 12, 12, 12), c0 if (L > 0 or T > 0) else Color(0, 0, 0, 1))
		img.fill_rect(Rect2i(w - 12, h - 12, 12, 12), c0 if (L > 0 or T > 0) else Color(0, 0, 0, 1))
	data = img.get_data()
	var margin_ok: bool = true
	if L + R + T + B > 0:
		var tmpl: Image = Image.create(w, h, false, Image.FORMAT_RGBA8)
		tmpl.fill(c0)
		var td: PackedByteArray = tmpl.get_data()
		if T > 0 and data.slice(0, T * stride) != td.slice(0, T * stride):
			margin_ok = false
		if B > 0 and data.slice((h - B) * stride, h * stride) != td.slice((h - B) * stride, h * stride):
			margin_ok = false
		if L > 0 or R > 0:
			for y: int in range(T, h - B):
				if L > 0 and data.slice(y * stride, y * stride + L * 4) != td.slice(0, L * 4):
					margin_ok = false
					break
				if R > 0 and data.slice(y * stride + (w - R) * 4, (y + 1) * stride) != td.slice(0, R * 4):
					margin_ok = false
					break
		r["margin_color"] = c0.to_html(false)
	r["margins_exact_uniform"] = margin_ok
	var cw: int = 640 * k
	var ch: int = 360 * k
	var crop: Image = raw.get_region(Rect2i(L, T, cw, ch))
	# edge ring must contain non-margin-colour pixels (content really starts exactly at the expected rect)
	var ring_ok: bool = true
	if L + R + T + B > 0:
		var sides: Array = [Rect2i(0, 0, cw, 1), Rect2i(0, ch - 1, cw, 1), Rect2i(0, 0, 1, ch), Rect2i(cw - 1, 0, 1, ch)]
		for sr: Rect2i in sides:
			var strip: Image = crop.get_region(sr)
			var different: bool = false
			for y: int in strip.get_height():
				for x: int in strip.get_width():
					if strip.get_pixel(x, y) != c0:
						different = true
						break
				if different:
					break
			if not different:
				ring_ok = false
	r["content_edge_ring_not_margin_colour"] = ring_ok
	var uni: bool = block_uniform(crop, k)
	r["blocks_all_uniform_incl_corner_pixels"] = uni
	var bad_list: Array = []
	if not uni:
		bad_list = list_nonuniform(crop, k)
	var outside: int = 0
	var inside_corner: int = 0
	for b: Vector2i in bad_list:
		var bottom: bool = (b.y + 1) * k > ch - 12 and (L + R + T + B == 0 or true) and h == ch
		var side: bool = b.x * k < 12 or (b.x + 1) * k > cw - 12
		if mask_corners and w == cw and bottom and side:
			inside_corner += 1
		else:
			outside += 1
	r["nonuniform_blocks_outside_corner_zones"] = outside
	r["nonuniform_blocks_in_window_corner_zones"] = inside_corner
	r["nonuniform_block_coords_sample"] = bad_list.slice(0, 20)
	r["blocks_all_uniform"] = outside == 0
	r["total_blocks"] = 640 * 360
	var down: Image = crop.duplicate()
	down.resize(640, 360, Image.INTERPOLATE_NEAREST)
	var colors: Dictionary = {}
	var lum: float = 0.0
	for y: int in range(0, 360, 2):
		for x: int in range(0, 640, 2):
			var c: Color = down.get_pixel(x, y)
			colors[c.to_html(false)] = true
			lum += c.get_luminance()
	r["distinct_colors_sampled"] = colors.size()
	r["mean_luminance_sampled"] = snappedf(lum / (180.0 * 320.0), 0.0001)
	var vpi: Image = Image.load_from_file(dir.path_join(rec["vp_file"]))
	if vpi != null:
		vpi.convert(Image.FORMAT_RGBA8)
		var diff: int = 0
		if vpi.get_size() == Vector2i(640, 360):
			for y: int in 360:
				for x: int in 640:
					if mask_corners and w == cw and y >= 360 - 6 and (x < 6 or x >= 640 - 6):
						continue
					if vpi.get_pixel(x, y) != down.get_pixel(x, y):
						diff += 1
			r["pixels_differing_from_viewport_texture"] = diff
		else:
			r["viewport_texture_size"] = str(vpi.get_size())
	return r
