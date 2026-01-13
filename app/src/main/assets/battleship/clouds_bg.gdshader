shader_type canvas_item;
render_mode unshaded;

uniform sampler2D noise_tex;

// Base settings
uniform float noise_scale = 2.0;
uniform float scroll_speed = 0.04;
uniform float swipe_offset = 0.0;

// Noise mixing
uniform float low_freq_scale   = 0.6;
uniform float mid_freq_scale   = 1.0;
uniform float high_freq_scale  = 2.5;

uniform float low_freq_weight  = 1.5;
uniform float mid_freq_weight  = 1.0;
uniform float high_freq_weight = 0.4;

// Appearance
uniform float cloud_coverage = 0.55;
uniform float puffiness      = 1.2;
uniform float alpha_max = 0.9;

// EDGE FADING: Controls how soft the box edges are (0.0 to 0.5)
uniform float edge_softness = 0.2;

void fragment() {
	vec2 uv = FRAGCOORD.xy * SCREEN_PIXEL_SIZE;

	// 1. Noise Generation
	vec2 base_uv = uv * noise_scale;
	base_uv.x -= TIME * scroll_speed;
	base_uv.x += swipe_offset;

	float n_low  = texture(noise_tex, fract(base_uv * low_freq_scale)).r;
	float n_mid  = texture(noise_tex, fract(base_uv * mid_freq_scale)).r;
	float n_high = texture(noise_tex, fract(base_uv * high_freq_scale)).r;

	float total_w = low_freq_weight + mid_freq_weight + high_freq_weight;
	float n = (n_low * low_freq_weight + n_mid * mid_freq_weight + n_high * high_freq_weight) / total_w;

	n = n - (1.0 - cloud_coverage);
	n = clamp(n, 0.0, 1.0);
	n = pow(n, puffiness);

	// 2. EDGE VIGNETTE (The Fix)
	// We calculate distance to the nearest edge (Left, Right, Top, or Bottom)
	// uv.x and uv.y are 0..1 inside the rect.
	float dist_x = min(UV.x, 1.0 - UV.x);
	float dist_y = min(UV.y, 1.0 - UV.y);

	// Combine them to find how close we are to ANY border
	float min_dist = min(dist_x, dist_y);

	// Smoothly fade alpha to 0.0 as we approach the edge
	float border_alpha = smoothstep(0.0, edge_softness, min_dist);

	// Final Alpha
	float final_alpha = alpha_max * n * border_alpha;

	vec3 cloud_color = vec3(1.0);
	COLOR = vec4(cloud_color, final_alpha);
}