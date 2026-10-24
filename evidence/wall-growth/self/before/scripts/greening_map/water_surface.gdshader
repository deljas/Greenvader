shader_type spatial;
render_mode unshaded, cull_disabled;
uniform sampler2D reflection_texture : source_color, filter_nearest, repeat_disable;
uniform mat4 reflection_view_projection;
uniform float reflection_strength : hint_range(0,1) = 0.76;
uniform vec4 tint : source_color = vec4(0.25,0.43,0.47,1.0);
varying vec3 world_position;
void vertex() { world_position=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; }
void fragment() {
	vec4 projected=reflection_view_projection*vec4(world_position,1.0);
	vec2 uv=projected.xy/projected.w*vec2(0.5,-0.5)+0.5;
	vec3 reflection=texture(reflection_texture,uv).rgb;
	ALBEDO=mix(tint.rgb,reflection*vec3(0.88,0.97,1.0),reflection_strength);
}
