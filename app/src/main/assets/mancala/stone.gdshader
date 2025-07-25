shader_type canvas_item;

uniform vec4 stone_color : source_color; // Color from GDScript
uniform sampler2D texture : hint_default_white; // Stone texture
uniform vec2 light_direction = vec2(0.5, -0.5); // Direction of the light (top-left)
uniform float glare_intensity = 0.5; // How strong the glare is
uniform float glare_size = 0.2; // How large the glare area is

void fragment() {
    vec4 tex_color = texture(texture, UV);

    // Calculate a 'normal' for basic lighting simulation based on texture alpha
    // This is a simplified approach for a circular/organic shape.
    vec2 center = vec2(0.5, 0.5);
    float dist = distance(UV, center);
    vec2 normal_vec = normalize(UV - center);

    // Simple dot product for diffuse lighting
    float light_factor = dot(normal_vec, normalize(light_direction));
    light_factor = max(0.0, light_factor * 0.5 + 0.5); // Remap to 0-1 and adjust contrast

    // Calculate glare (specular highlight)
    vec2 reflection_vec = reflect(normalize(light_direction), normal_vec);
    float glare = max(0.0, dot(vec2(0.0, -1.0), reflection_vec)); // Glare brightest when facing up
    glare = pow(glare, 1.0 / glare_size) * glare_intensity; // Sharpen and intensify

    // Combine base color, texture, diffuse light, and glare
    vec4 final_color = tex_color * stone_color * light_factor;
    final_color.rgb += glare; // Add glare to RGB channels

    COLOR = final_color;
    COLOR.a *= tex_color.a; // Preserve original texture alpha
}