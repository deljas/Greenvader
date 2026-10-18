extends SceneTree
## POC-05 independent capture (GPU, not headless). No OS input; window unfocusable. Own staging: default placement, ground
## around the base filled mature (harness op), 960 resolution, clock set to night / noon.
func _init() -> void:
	root.unfocusable = true
	_run.call_deferred()

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		print("NOT_RUN headless")
		quit(0)
		return
	var main: Node = (load("res://scenes/poc.tscn") as PackedScene).instantiate()
	main.set("auto_process", false)
	root.add_child(main)
	await process_frame
	main.set_resolution(1)
	var s: RefCounted = main.session
	s.state.debug_fill_stage(Rect2i(8, 5, 28, 28), WorldState.STAGE_MATURE)
	s.advance_game(60.0)
	for pair: Array in [["night", 23.0], ["noon", 12.0], ["evening", 16.5]]:
		var elapsed: float = fposmod(float(pair[1]) - float(s.env_tuning["start_hour"]), 24.0) / 24.0 * float(s.env_tuning["day_seconds"])
		s.clock.elapsed = elapsed
		main.tick(0.0, Vector2.ZERO)
		for i: int in 5:
			await process_frame
		await RenderingServer.frame_post_draw
		var img: Image = main.render_view.get_texture().get_image()
		print("size ", img.get_size(), " ", pair[0])
		img.save_png(ProjectSettings.globalize_path("res://evidence/poc/05/independent/own_%s_960.png" % pair[0]))
	quit(0)
