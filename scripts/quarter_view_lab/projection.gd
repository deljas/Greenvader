extends RefCounted
## Display adapter only. WorldState coordinates and its 4-unit cells stay unchanged.
static func project(logical: Vector2) -> Vector2:
	return Vector2(logical.x - logical.y, (logical.x + logical.y) * 0.5)

static func unproject(screen: Vector2) -> Vector2:
	return Vector2(screen.x * 0.5 + screen.y, screen.y - screen.x * 0.5)
