shader_type canvas_item;
render_mode unshaded;

uniform sampler2D noise_tex;
uniform float alpha : hint_range(0.0, 1.0) = 1.0;
uniform vec3 deep_color    = vec3(0.02, 0.25, 0.55);
uniform vec3 shallow_color = vec3(0.12, 0.65, 0.95);

uniform float base_scale   = 3.0;   // big waves
uniform float detail_scale = 10.0;  // small ripples
uniform float time_scale   = 0.25;  // overall speed
uniform float warp_amount  = 0.3;   // how swirly the water is

// NEW: extra scroll applied from GDScript when boards swipe
uniform float swipe_offset = 0.0;

void fragment() {
	// 0..1 across the whole viewport, so it fills the screen
	vec2 uv = FRAGCOORD.xy * SCREEN_PIXEL_SIZE;

	// Apply extra X offset driven by the board swipe
	uv.x += swipe_offset;

	// First noise used to warp the UVs (breaks straight lines)
	vec2 warp_uv      = uv * base_scale;
	vec2 warp_sample  = texture(noise_tex, fract(warp_uv)).rg;
	vec2 warp         = (warp_sample - 0.5) * warp_amount;

	// Two scrolling samples for layered motion
	vec2 scroll1 = vec2(TIME * time_scale, 0.0);
	vec2 scroll2 = vec2(-TIME * time_scale * 0.6, TIME * time_scale * 0.2);

	vec2 detail_uv1 = uv * detail_scale       + warp + scroll1;
	vec2 detail_uv2 = uv * (detail_scale*0.8) + warp + scroll2;

	// Wrap UVs so we always stay in 0..1 and avoid clamping artifacts
	float n1 = texture(noise_tex, fract(detail_uv1)).r;
	float n2 = texture(noise_tex, fract(detail_uv2)).r;

	float wave  = (n1 + n2) * 0.5;
	float shade = 0.5 + wave * 0.5;

	vec3 col = mix(deep_color, shallow_color, shade);
	COLOR = vec4(col, alpha);
}
