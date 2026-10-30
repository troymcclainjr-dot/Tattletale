// Clean shared shading. Legacy filename preserves existing imported materials.
// No thumbprint normals, mottling, or plasticine rim effect.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec4 albedo : source_color = vec4(0.5, 0.5, 0.5, 1.0);
uniform float roughness : hint_range(0.0, 1.0) = 0.86;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;

void fragment() {
    ALBEDO = albedo.rgb;
    ROUGHNESS = roughness;
    METALLIC = metallic;
}
