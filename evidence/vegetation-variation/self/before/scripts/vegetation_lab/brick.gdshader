shader_type spatial;
varying vec3 local_position;
void vertex() { local_position = VERTEX; }
void fragment() {
	float u = atan(local_position.x,local_position.z)*1.75;
	vec2 p = vec2(u/0.48,local_position.y/0.24);
	p.x += mod(floor(p.y),2.0)*0.5;
	vec2 f = fract(p);
	float edge = min(min(f.x,1.0-f.x),min(f.y,1.0-f.y));
	float tone = fract(sin(dot(floor(p),vec2(17.13,31.67)))*4178.0);
	vec3 brick = vec3(0.43,0.22,0.13)*(0.85+tone*0.25);
	ALBEDO = mix(vec3(0.32,0.30,0.24),brick,step(0.035,edge));
	ROUGHNESS = 0.95;
}
