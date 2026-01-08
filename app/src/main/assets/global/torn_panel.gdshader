shader_type canvas_item;

uniform vec4 paper_color : source_color = vec4(1.0, 0.98, 0.95, 1.0);
uniform sampler2D paper_texture;
uniform sampler2D noise_tex : repeat_enable;
uniform float tear_amplitude = 0.06;
uniform float tear_scale = 0.5;
uniform vec2 noise_offset = vec2(0.0, 0.0);
uniform float burn_size = 0;
uniform vec4 burn_color : source_color = vec4(0, 0, 0, 0);

void fragment() {
	vec2 pixel_pos = UV / TEXTURE_PIXEL_SIZE;
	vec2 uv_a = (pixel_pos * tear_scale) + noise_offset;
	float noise_a = texture(noise_tex, uv_a).r;
	vec2 uv_b = (pixel_pos * (tear_scale * 0.73)) + noise_offset + vec2(15.3, 42.1);
	float noise_b = texture(noise_tex, uv_b).r;
	float noise_combined = (noise_a + noise_b) * 0.5;
	float wave = (noise_combined * 2.0 - 1.0) * tear_amplitude;
	float top_cut_line = tear_amplitude + wave;
	float bottom_cut_line = 1.0 - (tear_amplitude + wave);
	float dist_to_top = UV.y - top_cut_line;
	float dist_to_bottom = bottom_cut_line - UV.y;
	float dist_to_edge = min(dist_to_top, dist_to_bottom);
	float pixel_height = TEXTURE_PIXEL_SIZE.y;
	float alpha = smoothstep(0.0, pixel_height, dist_to_edge);
	vec4 base_col = paper_color;
	vec4 tex_col = texture(paper_texture, UV);
	base_col = mix(base_col, tex_col * base_col, 0.5);

	if (dist_to_edge < burn_size) {
		float t = dist_to_edge / burn_size;
		COLOR = mix(burn_color, base_col, smoothstep(0.0, 1.0, t));
	} else {
		COLOR = base_col;
	}
}