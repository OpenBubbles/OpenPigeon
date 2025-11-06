shader_type canvas_item;

uniform float alpha_fade : hint_range(0.0, 1.0) = 0.0; // Controls overall visibility
uniform vec4 highlight_color : source_color = vec4(0.0, 1.0, 1.0, 1.0); // Cyan by default

void fragment() {
	// Center UV coordinates to -0.5 to 0.5 range
	vec2 uv = UV - 0.5;

	// Calculate distance from the center
	float d = length(uv);

	// Define the inner and outer radii for the highlight band
	// These values are relative to the UV space (0.0 to 0.5 from center to edge)
	float inner_radius = 0.45; // Start of the highlight band
	float outer_radius = 0.5;  // End of the highlight band (should be 0.5 for a circle touching ColorRect edges)

	// Use smoothstep to create a soft, anti-aliased edge for the circle.
	// `smoothstep(edge0, edge1, x)` returns 0.0 if x <= edge0, 1.0 if x >= edge1,
	// and smoothly interpolates otherwise.
	// Here, we want alpha to be 1.0 in the center and fade to 0.0 towards the outer_radius.
	// So, we use outer_radius as edge0 and inner_radius as edge1, then invert.
	float circle_alpha = smoothstep(outer_radius, inner_radius, d);

	// Combine the circle's alpha with the animated alpha_fade uniform
	// The final color is the highlight_color with its alpha modulated
	COLOR = vec4(highlight_color.rgb, highlight_color.a * circle_alpha * alpha_fade);
}