extends SceneTree
func _init() -> void:
	var light: DirectionalLight3D = DirectionalLight3D.new()
	for item: Dictionary in light.get_property_list():
		if "mask" in String(item.name) or "shadow" in String(item.name):
			print(item.name, " = ", light.get(item.name))
	var material: StandardMaterial3D = StandardMaterial3D.new()
	for item: Dictionary in material.get_property_list():
		if "shadow" in String(item.name):
			print(item.name, " = ", material.get(item.name))
	light.free()
	quit()
