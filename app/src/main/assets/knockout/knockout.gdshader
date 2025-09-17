shader_type canvas_item;

// Godot 4 screen sample
uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;

// --- Tunables (already subtle) ---
uniform float speed       : hint_range(0.0, 2.0) = 0.16;
uniform float scale       : hint_range(2.0, 60.0) = 14.0;
uniform int   octaves                          = 3;
uniform float lacunarity  : hint_range(1.5, 3.0) = 1.9;
uniform float gain        : hint_range(0.3, 0.8) = 0.58;
uniform float warp        : hint_range(0.0, 2.0) = 0.38;

uniform float refract_px  : hint_range(0.0, 8.0) = 0.9;
uniform float alpha_mix   : hint_range(0.0, 1.0) = 0.65;
uniform float shade_strength : hint_range(0.0, 1.0) = 0.06;

// -------- Simplex noise (smooth) --------
vec3 mod289(vec3 x){ return x - floor(x * (1.0 / 289.0)) * 289.0; }
vec2 mod289(vec2 x){ return x - floor(x * (1.0 / 289.0)) * 289.0; }
vec3 permute(vec3 x){ return mod289((x*34.0 + 1.0) * x); }

float snoise(vec2 v){
    const vec4 C = vec4(0.211324865405187,  // (3.0-sqrt(3.0))/6.0
                        0.366025403784439,  // 0.5*(sqrt(3.0)-1.0)
                        -0.577350269189626, // -1.0/sqrt(3.0)
                        0.024390243902439); // 1.0/41.0
    vec2 i  = floor(v + dot(v, C.yy));
    vec2 x0 = v - i + dot(i, C.xx);

    vec2 i1 = (x0.x > x0.y) ? vec2(1.0, 0.0) : vec2(0.0, 1.0);
    vec4 x12 = x0.xyxy + C.xxzz;
    x12.xy -= i1;

    i = mod289(i);
    vec3 p = permute(permute(i.y + vec3(0.0, i1.y, 1.0))
                   + i.x + vec3(0.0, i1.x, 1.0));

    vec3 m = max(0.5 - vec3(dot(x0,x0), dot(x12.xy,x12.xy), dot(x12.zw,x12.zw)), 0.0);
    m = m*m; m = m*m;

    vec3 x = 2.0*fract(p * C.www) - 1.0;
    vec3 h = abs(x) - 0.5;
    vec3 ox = floor(x + 0.5);
    vec3 a0 = x - ox;

    m *= 1.79284291400159 - 0.85373472095314 * (a0*a0 + h*h);

    vec3 g;
    g.x  = a0.x * x0.x  + h.x * x0.y;
    g.y  = a0.y * x12.x + h.y * x12.y;
    g.z  = a0.z * x12.z + h.z * x12.w;

    return 130.0 * dot(m, g); // ~[-1,1]
}

float fbm_simplex(vec2 p){
    float v = 0.0;
    float a = 0.5;
    float f = 1.0;
    for(int i=0;i<8;i++){
        if(i>=octaves) break;
        v += snoise(p * f) * a;
        f *= lacunarity;
        a *= gain;
    }
    return v * 0.5 + 0.5; // remap to ~[0,1]
}
// ---------------------------------------

void fragment(){
    float t  = TIME;
    vec2 uv  = UV;
    vec2 suv = SCREEN_UV;

    // base coords + gentle LEFT->RIGHT drift
    vec2 p = uv * scale;
    p.x += t * speed * scale * 0.10;
    p.y += t * speed * 0.03;

    // soft domain warp (simplex-based)
    vec2 w = vec2(fbm_simplex(p + vec2(5.2, 1.3)), fbm_simplex(p + vec2(1.7, 9.2))) * warp;
    float n = fbm_simplex(p + w);

    // wider epsilon -> smoother gradient, fewer “blocky” edges
    float eps = 3.0 / max(scale, 0.001);
    float n_x1 = fbm_simplex(p + w + vec2(eps, 0.0));
    float n_x2 = fbm_simplex(p + w - vec2(eps, 0.0));
    float n_y1 = fbm_simplex(p + w + vec2(0.0, eps));
    float n_y2 = fbm_simplex(p + w - vec2(0.0, eps));
    vec2 grad = vec2(n_x1 - n_x2, n_y1 - n_y2) * (0.5 / eps); // approx ∇n

    // convert to UV-sized refraction
    vec2 ref_ofs = grad * refract_px * vec2(SCREEN_PIXEL_SIZE.x, SCREEN_PIXEL_SIZE.y);

    vec4 base_bg   = texture(SCREEN_TEXTURE, suv);
    vec4 refracted = texture(SCREEN_TEXTURE, suv + ref_ofs);
    vec4 mixed     = mix(base_bg, refracted, alpha_mix);

    // very subtle brightness ripple so it shows over flat color
    float shade = (n - 0.5) * 0.6;
    mixed.rgb *= (1.0 + shade * shade_strength);

    COLOR = mixed;
}
