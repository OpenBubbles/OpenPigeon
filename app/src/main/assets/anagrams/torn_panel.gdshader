shader_type canvas_item;

// Distance from top/bottom to the main body of the paper (in pixels)
uniform float edge_height    = 10.0;

// How tall the waves of the tear are (in pixels)
uniform float wave_amplitude = 2.0;

// Horizontal scale of the waves (bigger = longer, smoother waves)
uniform float wave_length    = 80.0;

uniform vec4 paper_color : source_color = vec4(1.0); // usually pure white

void fragment() {
	// Convert UV (0..1) into pixel coordinates
	vec2 px = UV / TEXTURE_PIXEL_SIZE;
	float tex_h = 1.0 / TEXTURE_PIXEL_SIZE.y;

	// x along the width, normalized by wave_length so we control how often it wiggles
	float x = px.x / wave_length;

	// A smooth wave — combination of two sines for a more organic tear
	float wave_top    = sin(x * 6.28318) * 0.6 + sin(x * 12.56636 + 1.3) * 0.4;
	float wave_bottom = sin(x * 6.28318 + 3.14159) * 0.6 + sin(x * 12.56636 + 0.7) * 0.4;

	// Top & bottom tear lines
	float top_line = edge_height + wave_top * wave_amplitude;
	float bottom_line = tex_h - edge_height + wave_bottom * wave_amplitude;

	// Outside the torn band? Transparent.
	if (px.y < top_line || px.y > bottom_line) {
		discard;
	}

	// Inside: solid paper
	COLOR = paper_color;
}
