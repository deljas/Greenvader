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
varying vec3 world_position;
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
