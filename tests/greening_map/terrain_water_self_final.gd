extends "res://tests/greening_map/terrain_water_self_capture.gd"
## One requested final presentation frame; no regression/test rerun.
func run() -> void:
	lab = Scene.instantiate()
	lab.automatic = false
	root.add_child(lab)
	if DisplayServer.get_name()=="headless":
		quit(2)
		return
	set_fixture(WorldState.STAGE_MATURE,120000)
	await capture("final_comparison")
	var f: FileAccess = FileAccess.open(OUT+"final-raw.json",FileAccess.WRITE)
	f.store_string(JSON.stringify(raw,"\t"))
	quit(0)
