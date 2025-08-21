shader_type canvas_item;
render_mode unshaded, blend_add;

uniform vec4	ray_color : source_color = vec4(1.0, 0.84, 0.0, 0.9);
uniform float	rays : hint_range(4.0, 64.0) = 10.0;
uniform float	ray_width : hint_range(0.0, 3.0) = 3;	// controls gap size
uniform float	ray_softness : hint_range(0.0, 0.5) = 0.3;

uniform float	inner = 0.18;			// circular inner radius
uniform float	feather = 0.06;			// feather for both inner/outer edges

uniform float	speed : hint_range(0.0, 0.5) = 0.05;
uniform float	brightness = 1.5;
uniform float	spin_offset = 0.0;

// --- Pill controls (new) ---
uniform bool	use_pill = true;					// toggle pill vs circle
uniform vec2	pill_size = vec2(0.35, 0.15);		// full width/height of pill in UV space (0..1)
uniform float	pill_radius : hint_range(0.0, 0.5) = 0.15;	// corner radius
uniform float	pill_rotation = 0.0;				// radians (0 = horizontal pill)
uniform float	inner_feather : hint_range(0.0, 0.2) = 0.02;	// feather for the *inner* cutout (pill or circle)

// ---------- helpers ----------
float sdRoundRect(vec2 p, vec2 b, float r) {
	// Signed distance to a rounded rectangle of half-extents b and radius r
	vec2 q = abs(p) - (b - vec2(r));
	return length(max(q, vec2(0.0))) - r + min(max(q.x, q.y), 0.0);
}

mat2 rot(float a) {
	float c = cos(a), s = sin(a);
	return mat2(vec2(c, -s), vec2(s, c));
}

void fragment() {
	vec2 p = UV - vec2(0.5);
	float r = length(p) / 0.5;
	float ang = atan(p.y, p.x) + spin_offset + TIME * speed * 6.2831853;

	// Angular mask with adjustable ray width
	float f = fract(ang / 6.2831853 * rays);
	float center_band = abs(f - 0.5) * 2.0; // normalized distance from center of a ray
	float tri = 1.0 - clamp(center_band / max(ray_width, 1e-4), 0.0, 1.0);

	// Feather between rays
	float ray_mask = smoothstep(0.5 - ray_softness, 0.5 + ray_softness, tri);

	// ---- Inner cutout: pill OR circle ----
	float inner_mask = 1.0; // 1 = visible, 0 = cut out
	if (use_pill) {
		// Rotate into pill space
		vec2 hp = rot(pill_rotation) * p;
		// Pill uses half-extents
		vec2 half_extents = 0.5 * pill_size;
		float d = sdRoundRect(hp, half_extents, pill_radius);
		// Smoothly cut out inside pill
		float ifeath = max(inner_feather, 1e-4);
		inner_mask = smoothstep(-ifeath, ifeath, d);
	} else {
		// circular inner hole
		inner_mask = smoothstep(inner, inner + inner_feather, r);
	}

	// Outer radial fade
	float ring_out = 1.0 - smoothstep(1.0 - feather, 1.0, r);

	float radial_fall = 1.0 - smoothstep(0.0, 1.0, r);

	// Combine
	float ring = inner_mask * ring_out;
	vec4 c = ray_color * ray_mask * ring * radial_fall * brightness;
	COLOR = c;
}