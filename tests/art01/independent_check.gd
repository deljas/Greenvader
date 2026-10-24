extends SceneTree
## ART-01 independent, one headless run. Never sends OS input or writes saves.

const OUT: String = "res://evidence/art01/independent/r2/"
var checks: Array[Dictionary] = []
var failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func record(id: String, passed: bool, detail: String) -> void:
	checks.append({"id": id, "result": "PASS" if passed else "FAIL", "detail": detail})
	if not passed:
		failures += 1
	print("%s %s: %s" % ["PASS" if passed else "FAIL", id, detail])

func opaque_matches(image: Image, sample: Image, at: Vector2i) -> bool:
	for y: int in sample.get_height():
		for x: int in sample.get_width():
			if sample.get_pixel(x, y).a == 1.0 and image.get_pixelv(at + Vector2i(x, y)) != sample.get_pixel(x, y):
				return false
	return true

func _run() -> void:
	var packed: PackedScene = load("res://scenes/art_study.tscn") as PackedScene
	var study: Node2D = packed.instantiate() as Node2D
	root.add_child(study)
	await process_frame
	var a: Image = study.images[0]
	var b: Image = study.images[1]
	var image_ids: Array[int] = [study.textures[0].get_instance_id(), study.textures[1].get_instance_id()]
	var node_count: int = study.find_children("*", "", true, false).size()
	var input_ok: bool = study.variant == 0
	for keycode: int in [KEY_B, KEY_A]:
		var key: InputEventKey = InputEventKey.new()
		key.keycode = keycode
		key.pressed = true
		Input.parse_input_event(key)
		await process_frame
		input_ok = input_ok and study.variant == (1 if keycode == KEY_B else 0)
		key = InputEventKey.new()
		key.keycode = keycode
		Input.parse_input_event(key)
	study.buttons[1].pressed.emit()
	input_ok = input_ok and study.variant == 1
	record("engine_scene_and_controls", input_ok, "Scene instantiated; A/B engine events and B button signal select expected variant. No physical input tested.")
	var provenance_ok: bool = a.get_size() == Vector2i(640, 360) and b.get_size() == Vector2i(640, 360)
	for i: int in 2:
		var name: String = "A_restrained" if i == 0 else "B_rich"
		var original: Image = Image.load_from_file("res://evidence/art01/self/r2/" + name + ".png")
		var doubled: Image = Image.load_from_file("res://evidence/art01/self/r2/" + name + "_2x.png")
		provenance_ok = provenance_ok and original.get_data() == study.images[i].get_data() and doubled.get_size() == Vector2i(1280, 720)
		for y: int in 720:
			for x: int in 1280:
				provenance_ok = provenance_ok and doubled.get_pixel(x, y) == original.get_pixel(x / 2, y / 2)
	record("png_provenance_and_integer_pixels", provenance_ok, "Inspected CPU PNGs match instantiated source images byte for byte; every 2x pixel equals its source pixel.")
	var changes: int = 0
	var outside_changes: int = 0
	for y: int in 360:
		for x: int in 640:
			if a.get_pixel(x, y) != b.get_pixel(x, y):
				changes += 1
				if y < 44 or y >= 322 or x >= 490:
					outside_changes += 1
	record("comparison_scope", changes > 0 and outside_changes == 0, "%d changed source pixels, %d outside grass comparison area; soil and header/footer stay identical." % [changes, outside_changes])
	var samples_ok: bool = true
	var flower: Image = PixelArt.flower().get_image()
	var seed: Image = PlayArt.fruit().get_image()
	var boar: Image = PixelArt.boar().get_image()
	samples_ok = flower.get_size() == Vector2i(16, 16) and seed.get_size() == Vector2i(4, 4) and boar.get_size() == Vector2i(32, 18)
	for image: Image in [a, b]:
		samples_ok = samples_ok and opaque_matches(image, flower, Vector2i(314, 210)) and opaque_matches(image, boar, Vector2i(388, 230))
		for at: Vector2i in [Vector2i(352, 220), Vector2i(372, 211), Vector2i(343, 240)]:
			samples_ok = samples_ok and opaque_matches(image, seed, at)
	record("existing_sample_pixels", samples_ok, "Both variants retain every opaque pixel of the existing 16px flower, three 4px pickup seeds and 32x18 enemy, at identical coordinates.")
	await process_frame
	var cache_ok: bool = study.raster_builds == 2 and node_count < 32 and study.find_children("*", "", true, false).size() == node_count
	cache_ok = cache_ok and study.textures[0].get_instance_id() == image_ids[0] and study.textures[1].get_instance_id() == image_ids[1]
	record("cache_and_node_budget", cache_ok, "%d scene descendants; exactly two original cached textures survive input and idle. No per-blade nodes." % node_count)
	var output: FileAccess = FileAccess.open(OUT + "runtime-checks.json", FileAccess.WRITE)
	output.store_string(JSON.stringify({"checks": checks, "failures": failures, "engine": Engine.get_version_info().string, "user_data": OS.get_user_data_dir()}, "\t"))
	output.close()
	study.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
