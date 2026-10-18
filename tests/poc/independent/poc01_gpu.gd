extends SceneTree
const Coords: GDScript = preload("res://scripts/poc/poc_coords.gd")
const OUT: String = "res://evidence/poc/01/independent/"
var main: Node
var fails: int = 0
func chk(n: String, ok: bool, d: String = "") -> void:
	if not ok: fails += 1
	print("PASS " if ok else "FAIL ", n, " ", d)
func _init() -> void:
	root.unfocusable = true
	_run.call_deferred()
func grab() -> Image:
	for i in 4: await process_frame
	await RenderingServer.frame_post_draw
	return main.render_view.get_texture().get_image()
func _run() -> void:
	print("renderer: ", RenderingServer.get_video_adapter_name(), " ", DisplayServer.get_name())
	main = (load("res://scenes/poc.tscn") as PackedScene).instantiate()
	root.add_child(main)
	main.auto_process = false
	main.window_size_override = Vector2i(1920, 1080)
	await process_frame
	for idx: int in [0, 1]:
		main.set_resolution(idx)
		main.session.position = Coords.cell_center_logic(Vector2i(24, 20))
		main.tick(0.0, Vector2.ZERO)
		var full: Image = await grab()
		full.save_png(ProjectSettings.globalize_path(OUT + "render_%d.png" % main.render_view.size.x))
		# shadow/sprite sync
		var snap: Dictionary = main.actor.snapshot()
		chk("res%d sync" % idx, snap["matching_texture"] and snap["matching_feet"] and snap["matching_flip"], str(snap))
		var mask: Image = main.actor.display_sprite.texture.get_image()
		var foot: Vector2 = snap["foot_screen"]
		var org: Vector2i = Vector2i(roundi(foot.x) - mask.get_width() / 2, roundi(foot.y) - mask.get_height())
		# background without sprite & shadow
		main.actor.display_sprite.visible = false
		main.actor.shadow_board.visible = false
		var bg: Image = await grab()
		main.actor.shadow_board.visible = false
		main.actor.display_sprite.visible = true
		var spr: Image = await grab()
		main.actor.shadow_board.visible = true
		var bad: int = 0
		var inside: int = 0
		var changed_in: int = 0
		var cols: Dictionary = {}
		for y in range(org.y - 6, org.y + mask.get_height() + 6):
			for x in range(org.x - 6, org.x + mask.get_width() + 6):
				var mx: int = x - org.x
				var my: int = y - org.y
				var m: bool = mx >= 0 and my >= 0 and mx < mask.get_width() and my < mask.get_height() and mask.get_pixel(mx, my).a > 0.5
				var same: bool = spr.get_pixel(x, y) == bg.get_pixel(x, y)
				if m:
					inside += 1
					if not same: changed_in += 1
					cols[spr.get_pixel(x, y).to_html()] = true
				elif not same:
					bad += 1
		chk("res%d no outside-mask change/outline" % idx, bad == 0, "outside diffs=%d inside=%d changed=%d colors=%d" % [bad, inside, changed_in, cols.size()])
		# follow: subpixel player offsets, colour count must not grow
		var maxcols: int = 0
		var counts: Array = []
		for step in 12:
			main.session.position += Vector2(-0.37, -0.21) * step * 0.3
			main.tick(0.0, Vector2.ZERO)
			var im: Image = await grab()
			var sn: Dictionary = main.actor.snapshot()
			var f: Vector2 = sn["foot_screen"]
			var o: Vector2i = Vector2i(roundi(f.x) - mask.get_width() / 2, roundi(f.y) - mask.get_height())
			var c2: Dictionary = {}
			for y in mask.get_height():
				for x in mask.get_width():
					if mask.get_pixel(x, y).a > 0.5:
						c2[im.get_pixel(o.x + x, o.y + y).to_html()] = true
			counts.append(c2.size())
			main.actor.display_sprite.visible = false
			main.actor.shadow_board.visible = false
			var bg2: Image = await grab()
			main.actor.display_sprite.visible = true
			main.actor.shadow_board.visible = true
			var same_in: int = 0
			for y in mask.get_height():
				for x in mask.get_width():
					if mask.get_pixel(x, y).a > 0.5 and im.get_pixel(o.x + x, o.y + y) == bg2.get_pixel(o.x + x, o.y + y):
						same_in += 1
			if same_in > 0:
				print("  step ", step, " mask px identical to bare ground (sprite not drawn there): ", same_in, " foot ", f)
			maxcols = maxi(maxcols, c2.size())
			if step == 6:
				im.save_png(ProjectSettings.globalize_path(OUT + "follow_%d.png" % main.render_view.size.x))
			chk("res%d follow foot integer" % idx, absf(f.x - roundf(f.x)) < 0.01 and absf(f.y - roundf(f.y)) < 0.01, str(f)) if step % 4 == 0 else null
		chk("res%d follow colours stable" % idx, maxcols <= cols.size() + 4, "static=%d follow=%s" % [cols.size(), str(counts)])
	print("RESULT fails=", fails)
	quit(fails)
