shader_type canvas_item;

// Distance from top/bottom to the main body of the paper (in pixels)
uniform float edge_height = 4.0;

// Per-segment amplitude range (how tall the tear teeth can be, in px)
uniform float min_amplitude = 4.0;
uniform float max_amplitude = 8.0;

// Per-segment period range (horizontal size of waves / teeth, in px)
uniform float min_period = 40.0;
uniform float max_period = 120.0;

// How wide each "random segment" is (in px) – smaller = more variety
uniform float segment_width = 80.0;

// 0 = always sine, 1 = can be fully sawtooth
uniform float max_saw_mix = 0.8;

// Per-instance random seed (set from GDScript so panels don’t match)
uniform float global_seed = 0.0;

// Base paper color (usually pure white)
uniform vec4 paper_color : source_color = vec4(1.0);

// Simple hash
float hash1(float n) {
	return fract(sin(n * 43758.5453123) * 43758.5453123);
}

float rand_range(float seed, float a, float b) {
	return a + (b - a) * hash1(seed);
}

// Generates one tear profile (wave/saw mix) for a given pixel y-edge
float tear_profile(float x_px, float tex_h, bool top_edge, float seed_offset) {
	// Segment index along X
	float seg = floor(x_px / segment_width);
	float local_x = x_px - seg * segment_width;

	// Include global_seed so each material instance is different
	float base_seed = seg + seed_offset + global_seed * 1000.0;

	// Random amplitude & period for this segment
	float amp = rand_range(base_seed + 1.0, min_amplitude, max_amplitude);
	float period = rand_range(base_seed + 2.0, min_period, max_period);

	// Convert period into angular frequency
	float w = 6.28318 / period;

	// Random phase
	float phase = rand_range(base_seed + 3.0, 0.0, 6.28318);

	// Random saw / sine mix
	float saw_mix = rand_range(base_seed + 4.0, 0.0, max_saw_mix);

	// Optional decay to avoid very linear saws everywhere
	float decay = rand_range(base_seed + 5.0, 0.4, 1.0);

	// Smooth sine
	float sine_wave = sin(local_x * w + phase);

	// Sawtooth in [-1, 1]
	float saw = fract(local_x / period + phase) * 2.0 - 1.0;
	saw *= decay;

	// Blend between sine and saw for this segment
	float wave = mix(sine_wave, saw, saw_mix);

	// We want teeth pointing IN towards the body:
	//  - Top edge: move the line DOWN by a positive amount
	//  - Bottom edge: move the line UP by a positive amount
	float offset = abs(wave) * amp;

	float line;
	if (top_edge) {
		// Top starts a bit below 0 and moves further DOWN
		line = edge_height + offset;
	} else {
		// Bottom starts a bit above tex_h and moves further UP
		line = tex_h - edge_height - offset;
	}

	// Keep line inside the texture bounds
	line = clamp(line, 0.0, tex_h);
	return line;
}

void fragment() {
	// Convert UV (0..1) into pixel coordinates
	vec2 px = UV / TEXTURE_PIXEL_SIZE;
	float tex_h = 1.0 / TEXTURE_PIXEL_SIZE.y;

	// Use x in pixels for segmenting
	float x_px = px.x;

	// Get top & bottom tear lines
	float top_line = tear_profile(x_px, tex_h, true, 10.0);
	float bottom_line = tear_profile(x_px, tex_h, false, 100.0);

	// Outside the torn band? Transparent.
	if (px.y < top_line || px.y > bottom_line) {
		discard;
	}

	// Inside: solid paper
	COLOR = paper_color;
}
