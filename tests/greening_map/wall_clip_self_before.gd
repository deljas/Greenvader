extends "res://tests/greening_map/wall_clip_self_base.gd"
func run() -> void:
	if not setup_lab():
		quit(2)
		return
	for item: Dictionary in [{"id":"A_right","start":Vector2(1.0,-2.0)},{"id":"B_right","start":Vector2(6.5,-3.8)}]:
		await press_wall(item["start"],[KEY_W,KEY_A])
		await capture("before_"+item["id"])
		var row: Dictionary = geometry_row(item["id"])
		row["visibility"] = await visible_pixels()
		rows.append(row)
	var f: FileAccess = FileAccess.open(OUT+"before-raw.json",FileAccess.WRITE)
	f.store_string(JSON.stringify(rows,"\t"))
	quit(0)
