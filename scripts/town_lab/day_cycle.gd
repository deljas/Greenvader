extends RefCounted
## Stylized equinox-like lab cycle. Compass is aligned to screen, not world -Z.
const NORTH: Vector3 = Vector3(-0.70710678,0,-0.70710678)
const EAST: Vector3 = Vector3(0.70710678,0,-0.70710678)
const SOUTH: Vector3 = Vector3(0.70710678,0,0.70710678)
const WEST: Vector3 = Vector3(-0.70710678,0,0.70710678)

static func state(hour: float) -> Dictionary:
	var h: float = fposmod(hour,24)
	var phase: float = (h-6)/12*PI
	var altitude: float = sin(phase)
	var elevation: float = deg_to_rad(55)*altitude
	var horizontal: Vector3 = EAST*cos(phase)+SOUTH*sin(phase)
	var source: Vector3 = horizontal*cos(elevation)+Vector3.UP*sin(elevation)
	var daylight: float = smoothstep(-0.18,0.25,altitude)
	var sun_power: float = smoothstep(0,0.25,altitude)
	var night: float = 1-smoothstep(-0.1,0.3,altitude)
	return {"hour":h,"source":source,"sun_elevation":rad_to_deg(elevation),"sun_power":sun_power,
		"daylight":daylight,"night":night,"sun_color":Color("f0a169").lerp(Color("fff8e7"),smoothstep(0.02,0.6,altitude)),
		"ambient_color":Color("6b85b5").lerp(Color("b4c4cc"),daylight),
		"ambient_energy":lerpf(0.20,0.46,daylight),"moon_source":-source}
