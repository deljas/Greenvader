shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;
// WTH-01 cloud shadows: dark drifting patches on the ground. Dynamic (world-space noise moved by the game clock), never baked
// into the terrain. A thin transparent quad just above the ground; depth-tested, so sprites and objects standing above it are
// not darkened. Drawn in stepped levels (no soft blur, no outline).
uniform float strength = 0.0;
uniform float coverage = 0.5;
uniform float darkness = 0.42;
uniform float scale_m = 11.0;
uniform vec2 wind = vec2(0.55, 0.3);
uniform float shadow_time = 0.0;
uniform float steps = 4.0;
varying vec3 world_position;
void vertex() { world_position=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; }
float hash21(vec2 p){ p=fract(p*vec2(123.34,456.21)); p+=dot(p,p+45.32); return fract(p.x*p.y); }
float vnoise(vec2 p){
	vec2 i=floor(p); vec2 f=fract(p); f=f*f*(3.0-2.0*f);
	return mix(mix(hash21(i),hash21(i+vec2(1,0)),f.x),mix(hash21(i+vec2(0,1)),hash21(i+vec2(1,1)),f.x),f.y);
}
void fragment() {
	vec2 p=(world_position.xz-wind*shadow_time)/scale_m;
	float n=0.6*vnoise(p)+0.3*vnoise(p*2.1+13.7)+0.1*vnoise(p*4.3+3.1);
	float patch_=smoothstep(1.0-coverage-0.08,1.0-coverage+0.12,n);
	float level=floor(patch_*steps+0.5)/steps;
	ALBEDO=vec3(0.02,0.04,0.07);
	ALPHA=level*darkness*strength;
}
