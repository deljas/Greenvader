extends RefCounted
## Only building-scale data: shape, surface charts, holes and entrance corridor.
static func all() -> Array[Dictionary]:
	return [
		{"id":"A", "label":"A 横長コンクリート", "shape":"box", "size":Vector3(6.4,2.6,4.0), "color":Color("a1a393"), "seed":501,
		"surfaces":[plane(Vector3(-3.2,0,2),Vector3.RIGHT,Vector3.BACK,6.4,2.6,[Rect2(0.8,0.9,1.4,1.1),Rect2(3.8,0,1.2,2.1)]),plane(Vector3(3.2,0,2),Vector3.FORWARD,Vector3.RIGHT,4,2.6,[Rect2(1.1,0.9,1.2,1.1)])],
		"walkway":{"from":Vector2(1.2,2),"to":Vector2(1.2,4.3),"half_width":0.65},"extent":Vector2(4.5,4.4)},
		{"id":"B", "label":"B 縦長角形", "shape":"box", "size":Vector3(2.8,5.1,3.0), "color":Color("909b9f"), "seed":502,
		"surfaces":[plane(Vector3(-1.4,0,1.5),Vector3.RIGHT,Vector3.BACK,2.8,5.1,[Rect2(0.9,0,1.0,2.0),Rect2(0.95,3.0,0.9,1.1)]),plane(Vector3(1.4,0,1.5),Vector3.FORWARD,Vector3.RIGHT,3,5.1,[Rect2(1.0,1.0,0.85,1.0),Rect2(1.0,3.2,0.85,1.0)])],
		"walkway":{"from":Vector2(0,1.5),"to":Vector2(0,4.1),"half_width":0.60},"extent":Vector2(3.6,4.3)},
		{"id":"C", "label":"C レンガ円塔", "shape":"cylinder", "size":Vector3(3.5,4.6,3.5), "radius":1.75,"roof_height":1.65,"roof_radius":2.02,"color":Color("995d47"),"seed":503,
		"surfaces":[{"kind":"cylinder","radius":1.75,"width":TAU*1.75,"height":4.6,"holes":[Rect2(0.95,0,1.0,2.0),Rect2(0.1,2.65,0.65,1.05),Rect2(2.35,2.65,0.65,1.05)]}],
		"walkway":{"from":Vector2(1.28,1.20),"to":Vector2(3.5,3.4),"half_width":0.60},"extent":Vector2(3.9,4.1)}
	]

static func plane(origin: Vector3, tangent: Vector3, normal: Vector3, width: float, height: float, holes: Array[Rect2]) -> Dictionary:
	return {"kind":"plane","origin":origin,"tangent":tangent,"normal":normal,"width":width,"height":height,"holes":holes}
