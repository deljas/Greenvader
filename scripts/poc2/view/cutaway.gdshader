shader_type spatial;
render_mode blend_mix, depth_prepass_alpha, cull_disabled;
uniform vec4 base_color : source_color = vec4(1.0);
uniform sampler2D base_texture : source_color, filter_nearest;
uniform bool textured = false;
uniform bool vertex_color = false;
uniform float fade = 0.24;
uniform float cut_height = 1.8;
// 0 = upper part fully shown, 1 = fully gone. Driven by the same fade progress as the lower part (item 7).
uniform float upper_fade = 0.0;
varying vec3 world_vertex;
void vertex() { world_vertex = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz; }
void fragment() {
 float upper = world_vertex.y > cut_height ? 1.0 - upper_fade : 1.0;
 if (upper < 0.01) { discard; }
 vec4 color = base_color;
 if (textured) { color *= texture(base_texture, UV); }
 if (vertex_color) { color *= COLOR; }
 ALBEDO = color.rgb; ALPHA = color.a * (world_vertex.y > cut_height ? upper : fade); ROUGHNESS = 1.0;
}
