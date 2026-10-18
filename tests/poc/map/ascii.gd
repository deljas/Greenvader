extends SceneTree
## POC-07 helper: prints an ASCII picture of the town (one char per cell) and basic counts. Headless OK:
## godot --headless --path <repo> --script res://tests/poc/map/ascii.gd
## Legend: # placed obstacle, % outer ring, ~ water, s shore, = paved, S safe, : decorative puddle, N nest, @ start, i island, . wasteland.
const Session: GDScript = preload("res://scripts/poc/poc_session.gd")

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var size: Vector2i = Session.town_size()
	var s: RefCounted = Session.new(size.x, size.y)
	print("load_combat=", s.load_combat(Session.TOWN_SETUP))
	var st: WorldState = s.state
	var p: RefCounted = s.placement
	var lines: PackedStringArray = []
	for y: int in st.height:
		var line: String = ""
		for x: int in st.width:
			var i: int = y * st.width + x
			var ch: String = "."
			var t: int = st.terrain[i]
			if p.obstacle[i] == 1:
				ch = "#"
			elif t == Session.T_BUILDING:
				ch = "%"
			elif t == Session.T_WATER:
				ch = "~"
			elif t == Session.T_SHORE:
				ch = "s"
			elif p.puddle[i] == 1:
				ch = ":"
			elif t == Session.T_SAFE:
				ch = "S"
			elif t == Session.T_PAVED:
				ch = "="
			if st.occupant[i] != 0:
				ch = "N"
			if Vector2i(x, y) == p.player_start_cell:
				ch = "@"
			line += ch
		lines.append(line)
	print("\n".join(lines))
	print("targets=%d greened=%d sealed=%d nests=%d instances=%d" % [st.target_count, st.greened_count, p.sealed_count, s.enemies.nests.size(), p.instances.size()])
	for inst: Dictionary in p.instances:
		if inst["kind"] == "building" or inst["kind"] == "prop" or inst["kind"] == "tree":
			var cells: PackedInt32Array = p.cells_of[inst["id"]]
			if cells.is_empty():
				print("NO CELLS ", inst["id"])
	s.close()
	quit()
