shader_type spatial;
render_mode blend_mix, depth_prepass_alpha, cull_disabled;
uniform vec4 base_color : source_color = vec4(1.0);
uniform sampler2D base_texture : source_color, filter_nearest;
uniform bool textured = false;
uniform bool vertex_color = false;
uniform float fade = 0.24;
uniform float cut_height = 1.8;
varying vec3 world_vertex;
void vertex() { world_vertex = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz; }
void fragment() {
 if (world_vertex.y > cut_height) { discard; }
 vec4 color = base_color;
 if (textured) { color *= texture(base_texture, UV); }
 if (vertex_color) { color *= COLOR; }
 ALBEDO = color.rgb; ALPHA = color.a * fade; ROUGHNESS = 1.0;
}
