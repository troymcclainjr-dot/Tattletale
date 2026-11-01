// Opaque dark interior backing with restrained, uneven dusty reflections.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
// Calibrated response; `--legacy-city-finishes` renames this define in memory.
#define CITY_CALIBRATED_FINISHES
varying vec3 world_position;
varying vec3 world_normal;
void vertex() {
    world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}
float hash21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float patch(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(i), hash21(i + vec2(1, 0)), f.x), mix(hash21(i + vec2(0, 1)), hash21(i + vec2(1, 1)), f.x), f.y);
}
void fragment() {
    vec3 n = normalize(world_normal);
    vec2 p = abs(n.x) > abs(n.z) ? world_position.zy : world_position.xy;
    float tone = patch(p * vec2(0.72, 0.40));
    float dust = smoothstep(0.28, 0.80, patch(p * vec2(3.1, 0.55) + vec2(4.2, 7.4)));
#ifdef CITY_CALIBRATED_FINISHES
    // 6 cm rain streaks resolve only while they span pixels; distant panes take
    // their estimated average instead of sparkling, and skip the lookup.
    vec2 pixel = fwidth(p);
    float streak_detail = 1.0 - smoothstep(0.011, 0.025, max(pixel.x, pixel.y));
    float streak = 0.17;
    if (streak_detail > 0.0) {
        streak = mix(0.17, smoothstep(0.56, 0.84, patch(p * vec2(17.0, 1.3))), streak_detail);
    }
#else
    float streak = smoothstep(0.56, 0.84, patch(p * vec2(17.0, 1.3)));
#endif
    vec3 glass = mix(vec3(0.034, 0.045, 0.052), vec3(0.095, 0.103, 0.094), tone);
    ALBEDO = mix(glass, vec3(0.155, 0.145, 0.113), dust * 0.28 + streak * 0.08);
#ifdef CITY_CALIBRATED_FINISHES
    // Clean float glass is a smooth F0 0.04 dielectric: a tighter sun glint and
    // a Fresnel rise toward grazing, broken up by dust and streaks. Without SSR
    // or probes only the sky fills reflections, yet at eye level the street
    // canyon (facades, cars) would; near-horizontal reflections are held down.
    vec3 reflected = (INV_VIEW_MATRIX * vec4(reflect(-VIEW, NORMAL), 0.0)).xyz;
    float open_sky = smoothstep(-0.05, 0.55, reflected.y);
    ROUGHNESS = clamp(0.30 + dust * 0.30 + streak * 0.10, 0.30, 0.75);
    SPECULAR = mix(0.24, 0.5, open_sky) * (1.0 - dust * 0.3);
#else
    ROUGHNESS = clamp(0.64 + dust * 0.20 + streak * 0.07, 0.64, 0.92);
    SPECULAR = 0.20;
#endif
    METALLIC = 0.0;
}
