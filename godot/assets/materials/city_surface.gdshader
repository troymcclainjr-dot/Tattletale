// Local architectural wear: masonry joints, peeling finishes, pavement repairs.
// World-scale features stay still and antialias with distance; no screen grain.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform vec4 albedo : source_color = vec4(0.5, 0.5, 0.5, 1.0);
uniform float roughness = 0.9;
uniform int surface_kind = 0; // 1 brick, 2 concrete, 3 asphalt, 4 painted facade, 5 earth/grass, 6 trim
varying vec3 world_position;
varying vec3 world_normal;
void vertex() {
    world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}
float hash21(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
float patch(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(i), hash21(i + vec2(1,0)), f.x), mix(hash21(i + vec2(0,1)), hash21(i + vec2(1,1)), f.x), f.y);
}
void fragment() {
    vec3 n = normalize(world_normal);
    vec2 wall = abs(n.x) > abs(n.z) ? world_position.zy : world_position.xy;
    vec2 p = abs(n.y) > 0.7 ? world_position.xz : wall;
    vec3 color = albedo.rgb;
    float broad = patch(p * 0.55);
    if (surface_kind == 1 && abs(n.y) < 0.7) {
        // Sub-centimeter course drift and local edge loss break the ruler-straight
        // grid. All variation belongs to the masonry, never a screen-space layer.
        vec2 warped = p + vec2((patch(p * vec2(1.4, 5.0)) - 0.5) * 0.009,
                              (patch(p * vec2(2.8, 1.8) + vec2(8.0, 2.0)) - 0.5) * 0.006);
        vec2 brick = warped / vec2(0.285, 0.095);
        brick.x += mod(floor(brick.y), 2.0) * 0.5;
        vec2 id = floor(brick);
        vec2 edge = min(fract(brick), 1.0 - fract(brick));
        vec2 aa = max(fwidth(brick), vec2(0.005));
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
    } else if (surface_kind == 2) {
        vec2 slabs = p / vec2(1.45, 1.45);
        vec2 edge = min(fract(slabs), 1.0 - fract(slabs));
        vec2 aa = max(fwidth(slabs), vec2(0.002));
        float seam = 1.0 - smoothstep(0.003, 0.003 + aa.x, edge.x) * smoothstep(0.003, 0.003 + aa.y, edge.y);
        color *= mix(0.82, 1.05, patch(p * 1.3));
        color = mix(color, vec3(0.22, 0.21, 0.18), seam * 0.55);
        color *= 1.0 - smoothstep(0.58, 0.83, broad) * 0.25;
    } else if (surface_kind == 3) {
        float repair = smoothstep(0.50, 0.55, patch(p * 0.34));
        color *= mix(0.72, 1.13, repair);
        float line = abs(fract(p.x * 0.42 + sin(p.y * 1.7) * 0.035) - 0.5);
        float aa = max(fwidth(p.x * 0.42), 0.001);
        float crack = (1.0 - smoothstep(0.0015, 0.0015 + aa, line)) * smoothstep(0.35, 0.65, patch(p * 0.4));
        color *= 1.0 - crack * 0.55;
        color *= mix(0.9, 1.02, broad);
    } else if (surface_kind == 4) {
        float peeling = smoothstep(0.65, 0.74, patch(p * 3.2));
        color = mix(color, vec3(0.43, 0.40, 0.34), peeling * 0.42);
        float streak = smoothstep(0.60, 0.85, patch(vec2(p.x * 4.0, p.y * 0.28)));
        color *= 1.0 - streak * 0.25;
    } else if (surface_kind == 5) {
        color = mix(color, vec3(0.25, 0.23, 0.13), smoothstep(0.55, 0.78, patch(p * 0.65)) * 0.55);
    } else if (surface_kind == 6) {
        // Weather follows painted wood: softened paint loss and vertical runoff.
        // Keep the modeled sash, frame and sill silhouettes intact.
        float paint_loss = smoothstep(0.65, 0.82, patch(p * vec2(18.0, 7.0)));
        float wear_patch = smoothstep(0.38, 0.75, patch(p * 2.0 + vec2(2.0, 11.0)));
        float runoff = smoothstep(0.53, 0.81, patch(p * vec2(15.0, 0.75)));
        color = mix(color, vec3(0.29, 0.255, 0.20), paint_loss * wear_patch * 0.62);
        color *= 1.0 - runoff * 0.18 - (1.0 - broad) * 0.07;
    }
    ALBEDO = color;
    ROUGHNESS = surface_kind == 6 ? max(roughness, 0.89) : roughness;
}
