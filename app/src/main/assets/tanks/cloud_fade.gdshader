shader_type canvas_item;

// Set this to 50.0 or 100.0 in the Inspector for extreme speed
uniform float uv_speed = 80.0;			
uniform float density : hint_range(0.0, 1.0) = 0.5;	
uniform float softness : hint_range(0.1, 1.0) = 0.6;	
uniform float spread = 0.2;             // Lower = more horizontally stretched
uniform float fade_max = 0.8;			

// High-speed jitter/turbulence
uniform float whip_strength = 0.08;		
uniform float whip_speed = 25.0;		
uniform float wind_abs = 1.0;			

void fragment() {
	vec2 uv = SCREEN_UV;
	
	// Apply horizontal stretching (spread)
	uv.x *= max(spread, 0.001);
	
	// INCREDIBLE SPEED: Moving the X-coordinate fast
	uv.x += TIME * uv_speed;

	// High-frequency vertical vibration (simulates extreme wind turbulence)
	float whip = sin(TIME * whip_speed) * whip_strength * wind_abs;
	uv.y += whip;

	// Sample the noise texture
	float n = texture(TEXTURE, uv).r;

	// Cloud logic: Keep it airy but distinct
	float low_bound = 1.0 - density; 
	float high_bound = low_bound + softness;
	float cloud = smoothstep(low_bound, high_bound, n);

	// Contrast boost for high-speed visibility
	cloud = pow(cloud, 0.8); 

	// Standard screen-space fade
	float ramp = smoothstep(0.0, 1.0, SCREEN_UV.x) * fade_max;
	
	COLOR = vec4(0.004, 0.015, 0.18, cloud * ramp);
}