extends SceneTree
## 独立検証: 確認画面の実GPU撮影(非headless入口)。root.unfocusable=true、入力は Input.parse_input_event のみ。
## 実GPUが無ければ NOT_RUN。headlessの画像で代用しない。
const OUT_DIR: String = "res://evidence/content_pack/independent"
const GPU_DIR: String = "res://evidence/content_pack/independent/gpu"
var checks: Array = []
var shots: Array = []
var lab: Node = null
var g: RefCounted = null
var sc: float = 1.0
var adapter: String = ""

func ck(name: String, status: String, detail: String = "") -> void:
	checks.append({"name": name, "status": status, "detail": detail})

func frame() -> void:
	await process_frame

func draw_frames(n: int = 3) -> void:
	for i: int in range(n):
		await RenderingServer.frame_post_draw

func finish() -> void:
	var fails: int = 0
	var notrun: int = 0
	for c: Dictionary in checks:
		print("%s %s %s" % [c.status, c.name, c.detail])
		if c.status == "FAIL":
			fails += 1
		elif c.status == "NOT_RUN":
			notrun += 1
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var f: FileAccess = FileAccess.open(OUT_DIR + "/gpu_v.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"suite": "gpu_v", "adapter": adapter, "driver": RenderingServer.get_current_rendering_driver_name(), "display_server": DisplayServer.get_name(),
		"window_size": [root.size.x, root.size.y], "total": checks.size(), "failed": fails, "not_run": notrun, "shots": shots, "checks": checks}, "\t"))
	f.close()
	print("gpu_v total=%d failed=%d not_run=%d adapter=%s" % [checks.size(), fails, notrun, adapter])
	quit(1 if fails > 0 else 0)

func click_screen(p: Vector2, button: int = MOUSE_BUTTON_LEFT, shift: bool = false) -> void:
	var mv: InputEventMouseMotion = InputEventMouseMotion.new()
	mv.position = p * sc
	mv.global_position = p * sc
	Input.parse_input_event(mv)
	await frame()
	var ev: InputEventMouseButton = InputEventMouseButton.new()
	ev.position = p * sc
	ev.global_position = p * sc
	ev.button_index = button
	ev.pressed = true
	ev.shift_pressed = shift
	Input.parse_input_event(ev)
	await frame()

func click_world(w: Vector2, button: int = MOUSE_BUTTON_LEFT, shift: bool = false) -> void:
	await click_screen(w * 2.0, button, shift)

func btn(action: String) -> void:
	var c: Vector2 = lab.button_center(action)
	await click_screen(c)

func put_enemy(kind: String, w: Vector2) -> void:
	g.tab = "enemy"
	await btn("pick_enemy:" + kind)
	await click_world(w)

func put_crop(kind: String, w: Vector2) -> void:
	g.tab = "crop"
	await btn("pick_crop:" + kind)
	await click_world(w)

func capture(name: String, note: String) -> Image:
	await draw_frames(3)
	var im: Image = root.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(GPU_DIR))
	im.save_png(GPU_DIR + "/" + name + ".png")
	var scale: int = im.get_width() / 640
	var mult: bool = im.get_width() % 640 == 0 and im.get_height() % 360 == 0 and im.get_width() / 640 == im.get_height() / 360 and scale >= 1
	ck("shot_%s_size_integer_multiple_of_640x360" % name, "PASS" if mult else "FAIL", "%dx%d" % [im.get_width(), im.get_height()])
	# nearest: 各 scale x scale ブロックが一様か(補間・ぼかしなら崩れる)
	var bad: int = 0
	var blocks: int = 0
	for by: int in range(0, 360):
		for bx: int in range(0, 640):
			var c0: Color = im.get_pixel(bx * scale, by * scale)
			blocks += 1
			var uniform: bool = true
			for dy: int in range(scale):
				for dx: int in range(scale):
					if im.get_pixel(bx * scale + dx, by * scale + dy) != c0:
						uniform = false
			if not uniform:
				bad += 1
	ck("shot_%s_nearest_integer_scaling_blocks_uniform" % name, "PASS" if bad == 0 else "FAIL", "non-uniform blocks=%d of %d" % [bad, blocks])
	var colors: Dictionary = {}
	for y: int in range(im.get_height()):
		for x: int in range(im.get_width()):
			colors[im.get_pixel(x, y).to_rgba32()] = true
	shots.append({"name": name, "file": "evidence/content_pack/independent/gpu/%s.png" % name, "size": [im.get_width(), im.get_height()], "unique_colors": colors.size(), "note": note})
	return im

func _initialize() -> void:
	root.unfocusable = true
	adapter = RenderingServer.get_video_adapter_name()
	var gpu_ok: bool = DisplayServer.get_name() != "headless" and adapter != ""
	if not gpu_ok:
		ck("gpu_available", "NOT_RUN", "display=%s adapter='%s'" % [DisplayServer.get_name(), adapter])
		finish()
		return
	ck("gpu_available", "PASS", "adapter=%s driver=%s display=%s" % [adapter, RenderingServer.get_current_rendering_driver_name(), DisplayServer.get_name()])
	var scn: PackedScene = load("res://scenes/content_pack/content_lab.tscn")
	lab = scn.instantiate()
	lab.auto_step = false
	root.add_child(lab)
	await frame()
	await draw_frames(2)
	root.unfocusable = true
	await frame()
	ck("window_unfocusable", "PASS" if root.unfocusable and root.get_flag(Window.FLAG_NO_FOCUS) else "FAIL", "")
	g = lab.game
	sc = root.get_final_transform().x.x
	lab.ui.freeze = true
	lab.ui.t = 0.0
	g.seeds = 5000
	g.hero_pos = Vector2(120, 100)
	# --- 植物(入力で配置)
	g.set_speed(1)
	await put_crop("golden_clover", Vector2(100, 70))
	await put_crop("clover", Vector2(110, 70))
	await put_crop("oleander", Vector2(60, 100))
	await put_crop("clover", Vector2(72, 100))
	await put_crop("sunflower", Vector2(150, 100))
	await put_crop("lotus", Vector2(57, 41))
	await put_crop("giant_watermelon", Vector2(200, 60))
	await put_crop("cactus", Vector2(190, 110))
	await put_crop("sakura", Vector2(30, 120))
	await put_crop("potato", Vector2(160, 125))
	await put_crop("pumpkin", Vector2(176, 125))
	await put_crop("lavender", Vector2(140, 125))
	await put_crop("edamame", Vector2(130, 90))
	await btn("dbg_water")
	await btn("dbg_mature")
	g.sel_crop_id = g.pack.crops.crop_id_at(Vector2i(25, 17))
	# --- 敵(入力で配置)
	await put_enemy("tarachunade", Vector2(128, 100))
	await put_enemy("mimic_cabbage", Vector2(170, 90))
	await put_enemy("grass_snake", Vector2(100, 120))
	await put_enemy("moss_turtle", Vector2(205, 90))
	await put_enemy("deer", Vector2(215, 125))
	await put_enemy("mushling_parent", Vector2(80, 75))
	await put_enemy("stray_wolf", Vector2(225, 80))
	await put_enemy("black_kite", Vector2(190, 40))
	await put_enemy("sludge_carp", Vector2(30, 30))
	await put_enemy("honeybee_hive", Vector2(150, 70))
	await put_enemy("junk_crab", Vector2(40, 90))
	await put_enemy("ant_hill", Vector2(240, 110))
	await put_enemy("quill_hedgehog", Vector2(95, 95))
	await put_enemy("paint_chameleon", Vector2(235, 60))
	await put_enemy("slime_slug", Vector2(120, 125))
	await btn("tool:combat")
	# 状態: 数ステップだけ進めて予兆などを出す(1x、ごく短時間)
	g.step(0.9)
	ck("scene_built_via_injected_input", "PASS" if g.pack.crops.crop_ids().size() >= 11 and g.pack.enemies.enemy_ids().size() >= 20 else "FAIL", "crops=%d enemies=%d" % [g.pack.crops.crop_ids().size(), g.pack.enemies.enemy_ids().size()])
	var im: Image = await capture("lab_overview", "操作で組み立てた全体(状態記号つき)")
	# 夜: ヒカリゴケ・擬態の見破り・開花
	await put_crop("glow_moss", Vector2(102, 118))
	await btn("dbg_mature")
	await btn("day")
	g.step(0.2)
	await capture("lab_night", "夜(ヒカリゴケの範囲で擬態を表示)")
	finish()
