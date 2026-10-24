shader_type spatial;
render_mode cull_disabled;
uniform float coverage : hint_range(0,1) = 0.6;
void fragment() {
	vec2 p=UV*2.0-1.0;
	float broad=sin(UV2.x*3.7+sin(UV2.y*4.3))*sin(UV2.y*4.7+UV2.x*1.9);
	float n=sin(UV2.x*19.0+sin(UV2.y*12.0))*sin(UV2.y*21.0+UV2.x*7.0);
	float edge=length(p*vec2(1.0,0.87))+broad*0.30+n*0.13;
	if (coverage<=0.0 || edge>coverage*1.22 || fract(sin(dot(floor(UV2*20.0),vec2(13.3,71.7)))*43758.5)<0.08) discard;
	ALBEDO=mix(vec3(0.17,0.25,0.12),vec3(0.30,0.38,0.16),n*0.3+0.5);
	ROUGHNESS=1.0;
}
