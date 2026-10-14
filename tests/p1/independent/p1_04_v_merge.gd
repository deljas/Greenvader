extends SceneTree
## Merges the per-run result files of the P1-04 independent verification into one checks.json.
func _initialize() -> void:
	var dir: String = "res://evidence/p1/p1-04/independent/"
	var out: Array = []
	var files: Array[String] = ["checks_logic.json", "checks_scene_pause.json", "checks_scene_rate_30.json", "checks_scene_rate_60.json", "checks_scene_rate_144.json", "checks_scene_water.json", "checks_gpu.json", "checks_gpu_offline.json"]
	for f: String in files:
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(dir + f))
		var arr: Array = data["results"] if data is Dictionary else data
		for r: Dictionary in arr:
			r["evidence"] = f
			out.append(r)
	var fails: int = 0
	for r: Dictionary in out:
		if r["status"] != "PASS":
			fails += 1
	var fh: FileAccess = FileAccess.open(dir + "checks.json", FileAccess.WRITE)
	fh.store_string(JSON.stringify({"total": out.size(), "fails": fails, "results": out}, "  "))
	fh.close()
	print("MERGED total=%d fails=%d" % [out.size(), fails])
	for r: Dictionary in out:
		if r["status"] != "PASS":
			print("NONPASS ", r["id"], " ", r["evidence"])
	quit()
