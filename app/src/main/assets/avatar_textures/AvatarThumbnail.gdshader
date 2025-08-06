// pill_shape.gdshader
shader_type canvas_item;

uniform float corner_radius : hint_range(0.0, 1024.0) = 32.0;

float round_box(vec2 position, vec2 box_size, float radius) {
	return length(max(abs(position) - box_size + radius, 0.0)) - radius;
}

void fragment() {
	// Start with the base color of the node (the mask's color)
	COLOR = texture(TEXTURE, UV);
	
	vec2 size = 1.0 / SCREEN_PIXEL_SIZE;
	float distance = round_box(UV * size - size * 0.5, size * 0.5, corner_radius);

	// If the pixel is INSIDE the pill shape...
	if (distance > 0.0) {
		// ...cut a hole by making it fully transparent.
		COLOR.a = 0.0;
	}
}