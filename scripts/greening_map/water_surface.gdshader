shader_type spatial;
render_mode cull_disabled, ambient_light_disabled;
uniform sampler2D reflection_texture : source_color, filter_nearest, repeat_disable;
uniform mat4 reflection_view_projection;
uniform float reflection_strength : hint_range(0,1) = 0.76;
uniform vec4 tint : source_color = vec4(0.25,0.43,0.47,1.0);
uniform bool receive_shadow = true;
uniform float shadow_floor : hint_range(0,1) = 0.42;
varying vec3 world_position;
void vertex() { world_position=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; }
void fragment() {
	vec4 projected=reflection_view_projection*vec4(world_position,1.0);
	vec2 uv=projected.xy/projected.w*vec2(0.5,-0.5)+0.5;
	vec3 reflection=texture(reflection_texture,uv).rgb;
	ALBEDO=mix(tint.rgb,reflection*vec3(0.88,0.97,1.0),reflection_strength);
	ROUGHNESS=1.0;
	SPECULAR=0.0;
}
void light() {
	// One directional sun: preserve the already-lit reflection's color, only
	// attenuate its brightness by the real shadow map. No second light/color gain.
	if (LIGHT_IS_DIRECTIONAL) {
		float factor=receive_shadow ? mix(shadow_floor,1.0,ATTENUATION) : 1.0;
		DIFFUSE_LIGHT+=vec3(factor);
	}
}
