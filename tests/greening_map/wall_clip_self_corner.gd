extends "res://tests/greening_map/wall_clip_self_base.gd"
## One corrected corner fixture; other successful cases are not repeated.
func run() -> void:
	if not setup_lab():
		quit(2)
		return
	lab.session.position = Session.to_logic(Vector2(Session.HALF.x/10.0,0.8+Session.HALF.y/10.0))
	lab.update_actor(Vector2.ZERO)
	var row: Dictionary = geometry_row("A_corner")
	row["visibility"] = await visible_pixels()
	check(row["visibility"]["visible"]==row["visibility"]["opaque_fixture_pixels"],"visible_all_A_corner",str(row["visibility"]))
	check(Walker.is_clear(lab.session.state,4,lab.session.position,Session.HALF),"collision_clear_A_corner")
	await capture("after_A_corner")
	var f: FileAccess = FileAccess.open(OUT+"corner-raw.json",FileAccess.WRITE)
	f.store_string(JSON.stringify(row,"\t"))
	f = FileAccess.open(OUT+"corner-results.json",FileAccess.WRITE)
	f.store_string(JSON.stringify({"results":checks,"failures":failures},"\t"))
	quit(0 if failures==0 else 1)
