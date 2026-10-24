shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;

uniform vec4 base_color : source_color = vec4(0.58, 0.60, 0.55, 1.0);
uniform float surface_kind = 0.0; // 0 concrete, 1 pavement, 2 rusted steel, 3 soil
varying vec3 world_position;
varying vec3 world_normal;

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
float noise21(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
		mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0)), f.x), f.y);
}
void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}
void fragment() {
	vec3 n = abs(normalize(world_normal));
	vec2 p = n.y > 0.65 ? world_position.xz : (n.x > n.z ? world_position.zy : world_position.xy);
	float grain = noise21(p * 20.0);
	float flecks = step(0.83, hash21(floor(p * 47.0)));
	vec3 color = base_color.rgb;
	if (surface_kind < 0.5) {
		// Intrinsic aggregate, construction seams and runoff stains. No light/shadow
		// direction is sampled or baked into the material; all illumination is 3D.
		vec2 cell = fract(p / vec2(1.1, 0.66));
		float seam = 1.0 - step(0.012, min(min(cell.x, 1.0-cell.x), min(cell.y, 1.0-cell.y)));
		float dirt = smoothstep(0.52, 0.83, noise21(vec2(p.x * 5.0, p.y * 0.9)));
		float crack_path = abs(fract(p.x * 0.48 + noise21(vec2(floor(p.y * 2.0), 8.0)) * 0.24) - 0.49);
		float crack = (1.0 - step(0.005, crack_path)) * step(0.61, noise21(p * 2.0));
		color *= 0.93 + grain * 0.12;
		color = mix(color, vec3(0.34, 0.35, 0.28), dirt * 0.23);
		color *= 1.0 - seam * 0.10 - crack * 0.30;
		color += flecks * 0.035;
	} else if (surface_kind < 1.5) {
		vec2 tile = p / 0.86;
		vec2 f = fract(tile);
		float edge = min(min(f.x, 1.0-f.x), min(f.y, 1.0-f.y));
		float tile_tone = hash21(floor(tile));
		color *= 0.96 + tile_tone * 0.07 + (grain-0.5) * 0.12;
		float crack = 1.0 - step(0.008, abs(f.x - f.y * 0.63 - 0.17));
		color = mix(color, vec3(0.25, 0.27, 0.23), (1.0-step(0.016, edge)) * 0.8);
		color *= 1.0 - crack * step(0.73, tile_tone) * 0.36;
		color += (step(0.016, edge) - step(0.026, edge)) * 0.06;
	} else if (surface_kind < 2.5) {
		float rust = smoothstep(0.43, 0.57, noise21(p * 9.0) + noise21(p * 3.1) * 0.25);
		color = mix(color, vec3(0.39, 0.19, 0.075), rust * 0.87);
		color *= 0.86 + grain * 0.2;
	} else {
		// Fine material granules only; no large-scale positional lighting pattern.
		color *= 0.95 + grain * 0.09;
	}
	ALBEDO = color;
	ROUGHNESS = 0.94;
	METALLIC = surface_kind > 1.5 && surface_kind < 2.5 ? 0.12 : 0.0;
	SPECULAR = 0.18;
}
