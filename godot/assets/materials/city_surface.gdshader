// Local architectural wear: masonry joints, peeling finishes, pavement repairs.
// World-scale features stay still and antialias with distance; no screen grain.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
// Calibrated specular response. `--legacy-city-finishes` renames this define in
// memory (city_weathering.gd): previous output, same resources and draw layout.
#define CITY_CALIBRATED_FINISHES
uniform vec4 albedo : source_color = vec4(0.5, 0.5, 0.5, 1.0);
uniform float roughness = 0.9;
uniform int surface_kind = 0; // 1 brick, 2 concrete, 3 asphalt, 4 painted facade, 5 earth/grass, 6 trim
// Render-optimizer palette contract: CUSTOM0 holds the sRGB albedo and roughness
// of each source finish, so finishes of one kind can share a single surface.
uniform bool use_vertex_palette = false;
varying vec3 world_position;
varying vec3 world_normal;
varying flat vec4 finish;
void vertex() {
    world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
    // Base color and roughness are chosen once per vertex; every finish below
    // reads `finish`, so trim minimums and calibration apply to palette surfaces.
    finish = vec4(albedo.rgb, roughness);
    if (use_vertex_palette) {
        finish = CUSTOM0;
        // Same output-color-space guard StandardMaterial uses for sRGB vertex color.
        if (!OUTPUT_IS_SRGB) {
            vec3 encoded = CUSTOM0.rgb;
            finish.rgb = mix(encoded / 12.92, pow((encoded + vec3(0.055)) / 1.055, vec3(2.4)), step(vec3(0.04045), encoded));
        }
    }
}
float hash21(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
float patch(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(i), hash21(i + vec2(1,0)), f.x), mix(hash21(i + vec2(0,1)), hash21(i + vec2(1,1)), f.x), f.y);
}
#ifdef CITY_CALIBRATED_FINISHES
// 1 while a feature of this world period spans about five pixels, 0 by two.
float resolved(float period, float footprint) {
    return 1.0 - smoothstep(period * 0.2, period * 0.45, footprint);
}
#endif
void fragment() {
    vec3 n = normalize(world_normal);
    vec2 wall = abs(n.x) > abs(n.z) ? world_position.zy : world_position.xy;
    vec2 p = abs(n.y) > 0.7 ? world_position.xz : wall;
    vec3 color = finish.rgb;
    float broad = patch(p * 0.55);
#ifdef CITY_CALIBRATED_FINISHES
    // One derivative in uniform control flow serves every finish below; the
    // normal-dependent brick branch no longer differentiates inside itself.
    vec2 pixel = fwidth(p);
    float footprint = max(pixel.x, pixel.y);
    float tread = step(0.7, n.y);
    float rough = finish.a;
    float spec = 0.5;
#endif
    if (surface_kind == 1 && abs(n.y) < 0.7) {
        // Sub-centimeter course drift and local edge loss break the ruler-straight
        // grid. All variation belongs to the masonry, never a screen-space layer.
        vec2 warped = p + vec2((patch(p * vec2(1.4, 5.0)) - 0.5) * 0.009,
                              (patch(p * vec2(2.8, 1.8) + vec2(8.0, 2.0)) - 0.5) * 0.006);
        vec2 brick = warped / vec2(0.285, 0.095);
        brick.x += mod(floor(brick.y), 2.0) * 0.5;
        vec2 id = floor(brick);
        vec2 edge = min(fract(brick), 1.0 - fract(brick));
#ifdef CITY_CALIBRATED_FINISHES
        // Same scale without the half-brick bond jump at every course line.
        vec2 aa = max(pixel / vec2(0.285, 0.095), vec2(0.005));
#else
        vec2 aa = max(fwidth(brick), vec2(0.005));
#endif
        float fired = hash21(id);
        float chip = smoothstep(0.62, 0.82, patch(p * 31.0));
        float joint_x = 0.019 + hash21(id + vec2(7.0, 3.0)) * 0.016 + chip * 0.019;
        float joint_y = 0.035 + hash21(id + vec2(2.0, 9.0)) * 0.022 + chip * 0.035;
        float mortar = 1.0 - smoothstep(joint_x, joint_x + aa.x, edge.x) * smoothstep(joint_y, joint_y + aa.y, edge.y);
        float detail = 1.0 - smoothstep(0.25, 1.2, max(aa.x, aa.y));
        color *= mix(1.0, mix(0.72, 1.13, fired), detail);
        vec3 fired_tint = mix(vec3(0.84, 0.89, 0.94), vec3(1.04, 0.93, 0.81), hash21(id + vec2(33.0, 4.0)));
        color *= mix(vec3(1.0), fired_tint, detail * 0.65);
        vec3 joint_color = mix(vec3(0.24, 0.225, 0.19), vec3(0.43, 0.40, 0.33), patch(p * 1.8));
        color = mix(color, joint_color, mortar * detail * 0.78);
        float lime = smoothstep(0.70, 0.86, patch(p * vec2(0.82, 1.55) + vec2(13.0, 6.0)));
        color = mix(color, vec3(0.56, 0.52, 0.43), lime * 0.17);
        float soot = smoothstep(0.45, 0.82, patch(vec2(p.x * 2.5, p.y * 0.18)));
        color *= 1.0 - soot * 0.22;
#ifdef CITY_CALIBRATED_FINISHES
        // Dense, darker-fired units hold a faint grazing sheen; porous recessed
        // mortar, lime bloom and soot stay matte. Unit variation follows `detail`,
        // so distant walls settle on the authored roughness instead of sparkling.
        rough += mix(mix(-0.08, 0.03, fired), 0.07, mortar) * detail + max(lime, soot) * 0.04;
        spec = mix(0.5, 0.36, mortar * detail);
#endif
    } else if (surface_kind == 2) {
        vec2 slabs = p / vec2(1.45, 1.45);
        vec2 edge = min(fract(slabs), 1.0 - fract(slabs));
#ifdef CITY_CALIBRATED_FINISHES
        vec2 aa = max(pixel / 1.45, vec2(0.002));
#else
        vec2 aa = max(fwidth(slabs), vec2(0.002));
#endif
        float seam = 1.0 - smoothstep(0.003, 0.003 + aa.x, edge.x) * smoothstep(0.003, 0.003 + aa.y, edge.y);
        // Soft elongated shoe/rubber scuffs and slab-scale stains, without
        // fine grit or normal-map relief. Reuse the existing two noise fields.
        float scuff = smoothstep(0.55, 0.82, patch(p * vec2(2.8, 0.85)));
        color *= mix(0.91, 1.03, broad);
        color = mix(color, vec3(0.26, 0.245, 0.21), scuff * 0.34);
        color = mix(color, vec3(0.22, 0.21, 0.18), seam * 0.55);
        color *= 1.0 - smoothstep(0.58, 0.83, broad) * 0.25;
#ifdef CITY_CALIBRATED_FINISHES
        // Feet burnish paving and stoop treads (marble most visibly); dirt-filled
        // joints stay matte. Walls keep their authored roughness.
        rough *= 1.0 - tread * (scuff * 0.08 + smoothstep(0.58, 0.83, broad) * 0.04);
        rough = mix(rough, max(rough, 0.96), seam);
#endif
    } else if (surface_kind == 3) {
        float repair = smoothstep(0.50, 0.55, patch(p * 0.34));
        color *= mix(0.72, 1.13, repair);
        float line = abs(fract(p.x * 0.42 + sin(p.y * 1.7) * 0.035) - 0.5);
#ifdef CITY_CALIBRATED_FINISHES
        float aa = max(pixel.x * 0.42, 0.001);
#else
        float aa = max(fwidth(p.x * 0.42), 0.001);
#endif
        float crack = (1.0 - smoothstep(0.0015, 0.0015 + aa, line)) * smoothstep(0.35, 0.65, patch(p * 0.4));
        color *= 1.0 - crack * 0.55;
        color *= mix(0.9, 1.02, broad);
#ifdef CITY_CALIBRATED_FINISHES
        // Darker binder-rich patches keep slightly more sheen than the oxidized
        // surface; sealed cracks are matte. Dry only: no puddle or wet response.
        rough += (repair - 1.0) * 0.06;
        rough = mix(rough, 1.0, crack);
#endif
    } else if (surface_kind == 4) {
#ifdef CITY_CALIBRATED_FINISHES
        // The flake edge widens to about one pixel of noise change, not a crawl.
        float soften = footprint * 2.4;
        float peeling = smoothstep(0.65 - soften, 0.74 + soften, patch(p * 3.2));
#else
        float peeling = smoothstep(0.65, 0.74, patch(p * 3.2));
#endif
        color = mix(color, vec3(0.43, 0.40, 0.34), peeling * 0.42);
        float streak = smoothstep(0.60, 0.85, patch(vec2(p.x * 4.0, p.y * 0.28)));
        color *= 1.0 - streak * 0.25;
#ifdef CITY_CALIBRATED_FINISHES
        // Exposed substrate and dirt runoff are chalkier than intact paint.
        rough += peeling * 0.08 + streak * 0.04;
#endif
    } else if (surface_kind == 5) {
        // Turf stays continuous. Strong brown thresholded patches used to read
        // as triangular holes across both source lawns and replacement lawns.
        // Preserve the stronger soil treatment on earth and vertical cut banks.
        float worn = patch(p * vec2(0.95, 0.48));
        bool turf = n.y > 0.7 && finish.g > finish.r * 1.04 && finish.g > finish.b * 1.15;
        if (turf) {
            color *= mix(0.96, 1.035, broad * 0.55 + worn * 0.45);
        } else {
            color = mix(color, vec3(0.34, 0.31, 0.16), smoothstep(0.42, 0.72, broad) * 0.36);
            color = mix(color, vec3(0.23, 0.18, 0.105), smoothstep(0.55, 0.78, worn) * 0.74);
        }
#ifdef CITY_CALIBRATED_FINISHES
        // Turf and loose soil self-shadow, so their grazing sky sheen stays
        // below paving's rather than reading as vinyl.
        rough = max(rough, 0.95) + smoothstep(0.55, 0.78, worn) * 0.03;
        spec = 0.35;
#endif
    } else if (surface_kind == 6) {
        // Weather follows painted wood: softened paint loss and vertical runoff.
        // Keep the modeled sash, frame and sill silhouettes intact.
#ifdef CITY_CALIBRATED_FINISHES
        // 5-7 cm flecks resolve only while they span pixels. Farther trim takes
        // their estimated average coverage and skips both noise lookups.
        float flecks = resolved(0.055, footprint);
        float paint_loss = 0.13;
        float runoff = 0.21;
        if (flecks > 0.0) {
            paint_loss = mix(0.13, smoothstep(0.65, 0.82, patch(p * vec2(18.0, 7.0))), flecks);
            runoff = mix(0.21, smoothstep(0.53, 0.81, patch(p * vec2(15.0, 0.75))), flecks);
        }
#else
        float paint_loss = smoothstep(0.65, 0.82, patch(p * vec2(18.0, 7.0)));
        float runoff = smoothstep(0.53, 0.81, patch(p * vec2(15.0, 0.75)));
#endif
        float wear_patch = smoothstep(0.38, 0.75, patch(p * 2.0 + vec2(2.0, 11.0)));
        color = mix(color, vec3(0.29, 0.255, 0.20), paint_loss * wear_patch * 0.62);
        color *= 1.0 - runoff * 0.18 - (1.0 - broad) * 0.07;
#ifdef CITY_CALIBRATED_FINISHES
        // Intact paint keeps the established matte floor; bare wood is rougher.
        rough = max(rough, 0.89) + paint_loss * wear_patch * 0.06;
#endif
    }
    ALBEDO = color;
#ifdef CITY_CALIBRATED_FINISHES
    // Weathered city finishes never turn glossy or wet-looking.
    ROUGHNESS = clamp(rough, 0.45, 1.0);
    SPECULAR = spec;
#else
    ROUGHNESS = surface_kind == 6 ? max(finish.a, 0.89) : finish.a;
#endif
}
