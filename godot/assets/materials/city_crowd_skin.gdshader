shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// RGB vertex/instance colors arrive in linear space. UV.x marks exposed skin;
// custom RGB is independent of clothing tint, including head and both arms.
varying vec3 skin_color;
void vertex() {
    skin_color = INSTANCE_CUSTOM.rgb;
}
void fragment() {
    ALBEDO = mix(COLOR.rgb, skin_color, UV.x);
    ROUGHNESS = 1.0;
}
