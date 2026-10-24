extends RefCounted
## Meter units, origin at center of the ground-contact rectangle. No per-leaf placements.
const Definitions: GDScript = preload("res://scripts/vegetation_lab/building_defs.gd")

static func definition() -> Dictionary:
	var def: Dictionary = Definitions.all()[0].duplicate(true)
	def["model_asset"] = "res://assets/models/ruin_house/ruin_house.glb"
	def["restore_roof"] = false
	# UV rectangles include the actual door lintel/awning silhouette plus clearance.
	def["surfaces"][0]["awnings"] = [Rect2(3.33,2.18,1.72,0.30)]
	def["surfaces"][1]["awnings"] = []
	return def
