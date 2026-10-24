extends SceneTree
## Narrow follow-up: initial combined test had saved its deliberately inconsistent night fixture.
const OUT: String="res://evidence/spr01/independent/walk-compare-gpu/"
const SAVE_DIR: String="res://evidence/spr01/independent/walk-compare-save-valid/"
const Save: GDScript=preload("res://scripts/poc/save/poc_save.gd")
var main: Node
func _init() -> void:
	root.unfocusable=true
	_run.call_deferred()
func _run() -> void:
	main=load("res://scenes/poc.tscn").instantiate()
	main.auto_process=false
	main.save_dir=SAVE_DIR
	main.set_meta(&"poc_town",true)
	root.add_child(main)
	main.audio.muted=true
	for i: int in 4:
		await process_frame
	var rejected: Dictionary=Save.load_slot("res://evidence/spr01/independent/walk-compare-save/",false,Callable(main,"make_session"),"town_01")
	var before: Dictionary=Save.capture(main.session)
	before.erase("saved_at")
	var write: Dictionary=Save.save(main.session,SAVE_DIR,{"resolution_index":1})
	var loaded: Dictionary=main.load_game(false)
	var after: Dictionary=Save.capture(main.session)
	after.erase("saved_at")
	var ok: bool=bool(write.ok) and bool(loaded.ok) and main.current_resolution()==Vector2i(640,360) and main.render_view.size==Vector2i(640,360) and before==after
	var report: Dictionary={"name":"legacy_index1_save_load_640_valid_fixture","status":"PASS" if ok else "FAIL","save_ok":write.ok,"load_ok":loaded.ok,"load_reason":loaded.get("reason",""),"state_equal":before==after,"resolution":main.current_resolution(),"initial_fixture_rejection":rejected.get("reason","")}
	var f: FileAccess=FileAccess.open(OUT+"save_followup.json",FileAccess.WRITE)
	f.store_string(JSON.stringify(report,"\t"))
	f.close()
	print(JSON.stringify(report))
	main.session.close()
	main.queue_free()
	await process_frame
	quit(0 if ok else 1)
