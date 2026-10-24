extends RefCounted
## View-only definitions. Existing provisional raster art is reused at its native texel size.
const Art: GDScript = preload("res://scripts/pixel_art.gd")
const Crops: GDScript = preload("res://scripts/play/play_art.gd")
var definitions: Dictionary = {}

func _init() -> void:
	var boar: Texture2D = Art.boar()
	var sprout: Texture2D = Art.sprout()
	var mature: Texture2D = Art.mature()
	register("enemies","boar",{"source":"PixelArt.boar","clips":{"idle":clip(boar,Vector2i(16,16))},"mirror_left":true})
	register("plants","clover",{"source":"PixelArt.sprout/mature","clips":{"idle":clip(sprout,Vector2i(4,7)),"planted":clip(sprout,Vector2i(4,7)),"growing":clip(sprout,Vector2i(4,7)),"mature":clip(mature,Vector2i(8,15))}})
	register("plants","carrot",{"source":"PlayArt.cultivated","clips":{"idle":clip(Crops.cultivated(&"carrot",false),Vector2i(4,8)),"planted":clip(Crops.cultivated(&"carrot",false),Vector2i(4,8)),"growing":clip(Crops.cultivated(&"carrot",false),Vector2i(4,8)),"mature":clip(Crops.cultivated(&"carrot",true),Vector2i(4,8))}})

static func clip(texture: Texture2D, anchor: Vector2i) -> Dictionary:
	return {"frames":[texture],"anchor":anchor,"frame_pixels":Vector2i(texture.get_size()),"fps":0.0}

func register(category: String, kind: String, definition: Dictionary) -> void:
	# The same entry point supports helpers, moving mothers and fixed nests when art is supplied.
	definitions[category+":"+kind] = definition.duplicate(true)

func definition_for(category: String, kind: String) -> Dictionary:
	return definitions.get(category+":"+kind,{})

static func sample(definition: Dictionary, state: String, direction: StringName, elapsed: float) -> Dictionary:
	var clips: Dictionary = definition.get("clips",{})
	var resolved: String = state if clips.has(state) else "idle"
	if not clips.has(resolved): return {}
	var selected: Dictionary = clips[resolved]
	var directions: Dictionary = selected.get("directions",{})
	# Four direction sheets can supply per-direction frames/anchor; temporary art may supply one.
	if not directions.is_empty(): selected = directions.get(String(direction),directions.get("down",selected))
	var frames: Array = selected.get("frames",[])
	if frames.is_empty(): return {}
	var index: int = posmod(floori(elapsed * float(selected.get("fps",0.0))),frames.size())
	var texture: Texture2D = frames[index] as Texture2D
	if texture == null: return {}
	return {"texture":texture,"anchor":Vector2(selected.get("anchor",Vector2i(texture.get_width()/2,texture.get_height()))),"frame_pixels":Vector2i(selected.get("frame_pixels",texture.get_size())),"frame":index,"clip_state":resolved,"flip":bool(definition.get("mirror_left",false)) and direction==&"left"}
