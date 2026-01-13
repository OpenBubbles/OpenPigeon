/*
	煉瓦シェーダー by あるる（きのもと 結衣） @arlez80
	Brick Shader by Yui Kinomoto

	MIT License
*/
shader_type spatial;

const vec3 MONOCHROME_SCALE = vec3(0.298912, 0.586611, 0.114478);

uniform float noise_scale = 700.0;
uniform float brick_shift = 1.6;
uniform float brick_factor = 12.0;
uniform vec2 brick_scale = vec2(50.0, 100.0);

// Removed ": hint_color" so Godot 4 stops complaining
uniform vec4 brick_color  = vec4(0.7450980392, 0.3411764706, 0.2196078431, 1.0);
uniform vec4 brick_color2 = vec4(0.37, 0.12, 0.04, 1.0);
uniform vec4 mortar_joint_color = vec4(1.0, 0.98777, 0.9877777, 1.0);

vec2 random(vec2 pos)
{ 
	return fract(
		sin(
			vec2(
				dot(pos, vec2(12.9898, 78.233)),
				dot(pos, vec2(-148.998, -65.233))
			)
		) * 43758.5453
	);
}

vec2 value_noise(vec2 pos)
{
	vec2 p = floor(pos);
	vec2 f = fract(pos);

	vec2 v00 = random(p + vec2(0.0, 0.0));
	vec2 v10 = random(p + vec2(1.0, 0.0));
	vec2 v01 = random(p + vec2(0.0, 1.0));
	vec2 v11 = random(p + vec2(1.0, 1.0));

	vec2 u = f * f * (3.0 - 2.0 * f);

	return mix(mix(v00, v10, u.x), mix(v01, v11, u.x), u.y);
}

vec3 gen_brick_color(vec2 uv, float noise)
{
	uv.x += float(0.0 < sin(uv.y)) * brick_shift;
	float joint_weight = clamp(
		abs(sin(uv.y)) * abs(sin(uv.x)) * brick_factor + random(uv).x * noise,
		0.0,
		1.0
	);
	float color_select = random(floor(uv / 3.1415926535)).x;

	return mix(
		mortar_joint_color.rgb,
		mix(brick_color.rgb, brick_color2.rgb, color_select),
		joint_weight
	);
}

vec2 noise_tex(vec2 uv)
{
	return (
		value_noise(uv * 0.984864) * 0.5 +
		value_noise(uv * 2.543) * 0.25 +
		value_noise(uv * 9.543543) * 0.125 +
		value_noise(uv * 21.65436) * 0.0625 +
		value_noise(uv * 42.0) * 0.03125 +
		value_noise(uv * 87.135148) * 0.015625 +
		value_noise(uv * 340.66534654) * 0.0078125
	);
}

void fragment()
{
	vec2 uv = UV * brick_scale;

	float c[9];
	vec2 pixel_size = vec2(0.1, 0.1);

	for (int y = 0; y < 3; y++) {
		for (int x = 0; x < 3; x++) {
			vec2 v = uv + vec2(float(x - 1), float(y - 1)) * pixel_size;
			vec2 nv = UV * noise_scale + vec2(float(x - 1), float(y - 1)) * pixel_size;
			c[y * 3 + x] = length(noise_tex(nv)) + dot(gen_brick_color(v, 0.15), MONOCHROME_SCALE);
		}
	}

	vec2 sobel_filter = clamp(
		vec2(
			(
				c[0] * -1.0 +
				c[3] * -2.0 +
				c[6] * -1.0 +
				c[2] * 1.0 +
				c[5] * 2.0 +
				c[8] * 1.0
			),
			(
				c[0] * -1.0 +
				c[1] * -2.0 +
				c[2] * -1.0 +
				c[6] * 1.0 +
				c[7] * 2.0 +
				c[8] * 1.0
			)
		),
		vec2(-1.0, -1.0),
		vec2(1.0, 1.0)
	) * 0.5;

	// Godot 4: use NORMAL instead of NORMALMAP
	NORMAL = normalize(vec3(sobel_filter.x + 0.5, -sobel_filter.y + 0.5, 1.0));

	ALBEDO = gen_brick_color(uv, 0.3);
	ROUGHNESS = 0.95;
	METALLIC = 0.0;
}
