extends RefCounted
## Pure geometry shared by the actual world camera and current map detection.
const Config: GDScript = preload("res://scripts/poc/poc_config.gd")
const Coords: GDScript = preload("res://scripts/poc/poc_coords.gd")
const INTERNAL: Vector2i = Vector2i(640,360)
const NEAR_M: float = 0.05

static func transform_for(player_logic: Vector2) -> Transform3D:
	var foot: Vector3 = Coords.ground3(Coords.logic_to_ground(player_logic))
	var offset: Vector3 = Vector3(0.6123724,0.5,0.6123724) * Config.CAMERA_DISTANCE_M
	var target: Vector3 = foot + Vector3.UP * Config.CAMERA_TARGET_HEIGHT_M
	var right: Vector3 = Vector3(0.70710678,0,-0.70710678)
	var up: Vector3 = Vector3(-0.35355339,0.8660254,-0.35355339)
	var pixel: float = Config.CAMERA_SIZE_M / float(INTERNAL.y)
	target += right * (snappedf(target.dot(right),pixel)-target.dot(right))
	target += up * (snappedf(target.dot(up),pixel)-target.dot(up))
	return Transform3D(Basis.looking_at(-offset,Vector3.UP),target+offset)

static func screen_from_local(local: Vector3) -> Vector2:
	var pixels_per_metre: float = float(INTERNAL.y)/Config.CAMERA_SIZE_M
	return Vector2(INTERNAL)*0.5 + Vector2(local.x,-local.y)*pixels_per_metre

static func project_ground(logic: Vector2, camera_inverse: Transform3D) -> Vector2:
	return screen_from_local(camera_inverse * Coords.ground3(Coords.logic_to_ground(logic)))

static func contains_ground(logic: Vector2, camera_inverse: Transform3D) -> bool:
	var local: Vector3 = camera_inverse * Coords.ground3(Coords.logic_to_ground(logic))
	return local.z <= -NEAR_M and local.z >= -Config.CAMERA_FAR_M and Rect2(Vector2.ZERO,Vector2(INTERNAL)).has_point(screen_from_local(local))
