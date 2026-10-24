shader_type spatial;
render_mode cull_disabled, ambient_light_disabled;
uniform sampler2D reflection_texture : source_color, filter_nearest, repeat_disable;
uniform mat4 reflection_view_projection;
uniform float daylight = 1.0;
uniform float reflection_strength : hint_range(0,1) = 0.78;
uniform bool receive_shadow = true;
uniform bool sun_enabled = true;
varying vec3 world_position;
void vertex() { world_position=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; }
void fragment() {
	vec4 projected=reflection_view_projection*vec4(world_position,1.0);
	vec2 uv=projected.xy/projected.w*vec2(0.5,-0.5)+0.5;
	vec3 reflected=texture(reflection_texture,uv).rgb;
	vec3 wet_tint=vec3(0.16,0.24,0.25)*mix(0.045,0.55,daylight);
	ALBEDO=mix(wet_tint,reflected*vec3(0.88,0.96,1.0),reflection_strength);
	// Reflection already contains sun/ambient/lamp radiance. Only a bounded
	// shadow visibility factor is applied; no second light-energy/color gain.
	float floor_factor=mix(0.78,0.42,daylight);
	EMISSION=ALBEDO*floor_factor;
	ROUGHNESS=1.0;
	SPECULAR=0.0;
}
void light() {
	float floor_factor=mix(0.78,0.42,daylight);
	float visibility=receive_shadow ? ATTENUATION : 1.0;
	// MAX, not +=: multiple lamps/directional fill can never multiply the
	// already-lit reflected image. Night local shadow contrast is gentle.
	// Day: only the above-horizon sun. Night: local lamps only; the approximate
	// moon must not erase a nearby lamp's shadow with unoccluded visibility1.
	if (LIGHT_IS_DIRECTIONAL == sun_enabled) {
		DIFFUSE_LIGHT=max(DIFFUSE_LIGHT,vec3((1.0-floor_factor)*visibility));
	}
}
