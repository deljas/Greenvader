shader_type canvas_item;
render_mode unshaded;

// One 640px viewport-texture sample. No explicit gamma conversion, RGB
// posterization, neighbour samples, blur, outline, dithering or new noise.
void fragment() {
	vec4 source = texture(TEXTURE, UV);
	vec3 color = source.rgb;
	float luminance = dot(color, vec3(0.2126, 0.7152, 0.0722));
	float shadow_weight = 1.0 - smoothstep(0.18, 0.52, luminance);
	float light_weight = smoothstep(0.34, 0.74, luminance);
	color *= mix(vec3(1.0), vec3(0.94, 1.03, 1.07), shadow_weight * 0.55);
	color *= mix(vec3(1.0), vec3(1.06, 1.02, 0.94), light_weight * 0.60);
	float y = dot(color, vec3(0.2126, 0.7152, 0.0722));
	// Scalar luma only, 20 levels mixed at 20%. Preserve most of the continuous
	// material shading and hue; avoid strong banding of fine concrete grain.
	float target_y = mix(y, floor(y * 20.0 + 0.5) / 20.0, 0.20);
	color *= target_y / max(y, 0.0001);
	COLOR = vec4(clamp(color, vec3(0.0), vec3(1.0)), source.a);
}
