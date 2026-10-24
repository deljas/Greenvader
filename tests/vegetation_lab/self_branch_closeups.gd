extends "res://tests/vegetation_lab/self_branch_capture.gd"
## Only the framing affected by the second UI row is recaptured.
func run() -> void:
	lab = Scene.instantiate()
	root.add_child(lab)
	if DisplayServer.get_name()=="headless":
		quit(2)
		return
	lab.presets[2].pressed.emit()
	for index: int in [1,3]:
		lab.view_select.select(index)
		lab.view_select.item_selected.emit(index)
		await capture("A_roof_branches_closeup" if index==1 else "C_branches_closeup")
	quit(0)
