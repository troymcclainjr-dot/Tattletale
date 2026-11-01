shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

void vertex() {
    // Colors stay encoded in the mesh's 8-bit attribute, preserving dark tones.
    // Match the source_color conversion used by the original actor materials.
    if (!OUTPUT_IS_SRGB) {
        COLOR.rgb = mix(pow((COLOR.rgb + vec3(0.055)) / 1.055, vec3(2.4)),
                        COLOR.rgb / 12.92, lessThanEqual(COLOR.rgb, vec3(0.04045)));
    }
}

void fragment() {
    ALBEDO = COLOR.rgb;
    ROUGHNESS = UV.x;
    METALLIC = UV.y;
}
