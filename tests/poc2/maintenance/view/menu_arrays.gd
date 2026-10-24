extends "res://tests/poc2/maintenance/view/menu_boundaries.gd"
## Only the affected title/pause construction and help-return paths after typed-array repair.
func run() -> void:
	var entry_error: Error=change_scene_to_packed(Main)
	await frames()
	main=current_scene
	main.auto_process=false
	main.save_dir=TEST_SAVE
	var title_buttons: Array[String]=[]
	for button: Node in main.ui.menu.find_children("*","Button",true,false): title_buttons.append(button.text)
	check("real_entry_title_buttons",entry_error==OK and main==current_scene and main.menu=="title" and title_buttons==["新しく始める","続きから","操作説明"])
	check("title_menu_constructed",main.ui.menu.visible and main.ui.menu.find_children("*","Button",true,false).size()==3)
	await frames()
	for button: Node in main.ui.menu.find_children("*","Button",true,false):
		if button.text=="操作説明": mouse(button.get_global_rect().get_center()); break
	await frames()
	key(KEY_ESCAPE)
	await frames()
	check("help_returns_to_title_only",main.menu=="title" and main.ui.menu.visible and not main.ui.help.visible and not main.ui.supply.visible and main.session.paused)
	await capture("03_title_restored")
	for button: Node in main.ui.menu.find_children("*","Button",true,false):
		if button.text=="新しく始める": mouse(button.get_global_rect().get_center()); break
	await frames()
	key(KEY_ESCAPE)
	await frames()
	check("pause_menu_constructed",main.menu=="pause" and main.ui.menu.visible and main.ui.menu.find_children("*","Button",true,false).size()==5)
	for button: Node in main.ui.menu.find_children("*","Button",true,false):
		if button.text=="操作説明": mouse(button.get_global_rect().get_center()); break
	await frames()
	for button: Node in main.ui.help.find_children("*","Button",true,false):
		if button.text=="閉じる": mouse(button.get_global_rect().get_center()); break
	await frames()
	check("help_returns_to_pause_only",main.menu=="pause" and main.ui.menu.visible and not main.ui.help.visible and not main.ui.supply.visible and main.session.paused)
	await capture("04_pause_restored")
	var failures: int=0
	for row: Dictionary in checks:
		if row.status=="FAIL": failures+=1
	var file: FileAccess=FileAccess.open(OUT+"menu-array-checks.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"input":"Input.parse_input_event only; root.unfocusable=true"},"  "))
	file.close()
	main.session.close()
	main.queue_free()
	quit(0 if failures==0 else 1)

