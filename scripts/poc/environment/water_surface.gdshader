shader_type spatial;
render_mode cull_disabled, ambient_light_disabled;
// POC-05 water surface (ported from the town lab / greening map): planar reflection + shadow receiving.
uniform sampler2D reflection_texture : source_color, filter_nearest, repeat_disable;
uniform mat4 reflection_view_projection;
uniform float daylight = 1.0;
uniform float reflection_strength : hint_range(0,1) = 0.78;
uniform bool receive_shadow = true;
// POL-01: reflected image gain, reflection background (where no object was drawn: alpha 0) and the shadow floor, from data/poc/environment.json "water".
uniform float reflection_gain = 1.0;
uniform vec3 sky_day : source_color = vec3(0.6,0.72,0.8);
uniform vec3 sky_night : source_color = vec3(0.05,0.08,0.14);
uniform float floor_day = 0.42;
uniform float floor_night = 0.78;
// WTH-01 rain ripples: one ring per world-space cell, expanding and fading; none without rain. Game-time driven.
uniform float rain_level = 0.0;
uniform float ripple_time = 0.0;
uniform float ripple_cell_m = 0.8;
uniform float ripple_period = 0.9;
uniform float ripple_radius_m = 0.32;
uniform float ripple_strength = 0.5;
varying vec3 world_position;
float hash21(vec2 p){ p=fract(p*vec2(123.34,456.21)); p+=dot(p,p+45.32); return fract(p.x*p.y); }
float ripple_ring(vec2 xz){
	float ring=0.0;
	vec2 base=floor(xz/ripple_cell_m);
	for (int j=-1;j<=1;j++){
		for (int i=-1;i<=1;i++){
			vec2 cell=base+vec2(float(i),float(j));
			float h=hash21(cell);
			vec2 centre=(cell+vec2(hash21(cell+7.3),hash21(cell+19.1)))*ripple_cell_m;
			float phase=fract(ripple_time/ripple_period+h);
			float life=floor(ripple_time/ripple_period+h);
			// only some cells ring in a given cycle, more of them as the rain gets heavier
			if (hash21(cell+life*0.37)>rain_level*0.85) { continue; }
			float d=length(xz-centre);
			float front=phase*ripple_radius_m;
			ring=max(ring,(1.0-smoothstep(0.0,0.035,abs(d-front)))*(1.0-phase));
		}
	}
	return ring;
}
void vertex() { world_position=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; }
void fragment() {
	vec4 projected=reflection_view_projection*vec4(world_position,1.0);
	vec2 uv=projected.xy/projected.w*vec2(0.5,-0.5)+0.5;
	vec4 sample_=texture(reflection_texture,uv);
	vec3 reflected=mix(mix(sky_night,sky_day,daylight),min(sample_.rgb*reflection_gain,vec3(1.0)),sample_.a);
	vec3 wet_tint=vec3(0.16,0.24,0.25)*mix(0.045,0.55,daylight);
	ALBEDO=mix(wet_tint,reflected*vec3(0.88,0.96,1.0),reflection_strength);
	// The reflection already contains the sun/ambient radiance; only a bounded shadow visibility factor is applied.
	float floor_factor=mix(floor_night,floor_day,daylight);
	EMISSION=ALBEDO*floor_factor;
	if (rain_level>0.001) {
		float ring=ripple_ring(world_position.xz)*ripple_strength*rain_level;
		EMISSION+=vec3(0.55,0.68,0.78)*ring*mix(0.45,1.0,daylight);
	}
	ROUGHNESS=1.0;
	SPECULAR=0.0;
}
void light() {
	float floor_factor=mix(floor_night,floor_day,daylight);
	float visibility=receive_shadow ? ATTENUATION : 1.0;
	// One key light (sun by day, moon at night). MAX, not +=: never multiplies the already lit reflected image.
	if (LIGHT_IS_DIRECTIONAL) {
		DIFFUSE_LIGHT=max(DIFFUSE_LIGHT,vec3((1.0-floor_factor)*visibility));
	}
}
