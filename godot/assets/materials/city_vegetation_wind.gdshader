// CUSTOM0 = cell-local tree anchor XZ, squared height/radius ratio, sway weight.
// One material and one clock uniform serve every resident vegetation cell.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform float wind_time = 0.0;
uniform float wind_strength : hint_range(0.0, 1.0) = 1.0;

void vertex() {
    // SurfaceTool's native merge applies the forward plant basis to normals.
    // Equal X/Z scale and yaw-only rotation let this recover inverse-transpose
    // direction without a scripted transform+normalize for every merged vertex.
    NORMAL = normalize(NORMAL * vec3(CUSTOM0.z, 1.0, CUSTOM0.z));
    // Match StandardMaterial3D: decode before interpolation, only in renderers
    // with linear output. Avoid repeating three pow operations per fragment.
    if (!OUTPUT_IS_SRGB) {
        vec3 encoded = COLOR.rgb;
        vec3 low = encoded / 12.92;
        vec3 high = pow((encoded + vec3(0.055)) / 1.055, vec3(2.4));
        COLOR.rgb = mix(low, high, step(vec3(0.04045), encoded));
    }
    float weight = CUSTOM0.w * wind_strength;
    if (weight > 0.0) {
        // The anchor is converted through the cell transform so a tree keeps its
        // phase even when nearby cells stream in and out.
        vec2 anchor = (MODEL_MATRIX * vec4(CUSTOM0.x, 0.0, CUSTOM0.y, 1.0)).xz;
        float phase = dot(anchor, vec2(0.173, 0.127));
        float slow = sin(wind_time * 0.58 + phase);
        float cross = sin(wind_time * 0.83 + phase * 1.37);
        VERTEX.xz += vec2(slow * 0.055, cross * 0.035) * weight;
    }
}

void fragment() {
    ALBEDO = COLOR.rgb;
    ROUGHNESS = 0.88;
    SPECULAR = 0.21;
}
