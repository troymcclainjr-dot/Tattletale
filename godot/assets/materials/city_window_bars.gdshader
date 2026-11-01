shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;
varying vec4 pane_style;
void vertex() { pane_style = INSTANCE_CUSTOM; }
float hash21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
void fragment() {
    vec2 size = max(pane_style.yz, vec2(0.1));
    vec2 p = UV * size;
    float count = clamp(floor(size.x / 0.18), 3.0, 16.0);
    float spacing = size.x / count;
    float vertical = abs(fract(p.x / spacing + 0.5) - 0.5) * spacing;
    float crossbar = min(abs(p.y - size.y * 0.24), abs(p.y - size.y * 0.76));
    // Hard-discard bars narrower than a pixel can disappear as a whole grille
    // when the repeated columns fall between samples. Keep a narrow coverage
    // floor at oblique street views, bounded by the spacing so distant windows
    // never turn into solid iron. This remains one opaque cutout draw.
    float width = max(mix(0.010, 0.014, pane_style.x), min(fwidth(p.x) * 0.65, spacing * 0.20));
    float rail_width = max(0.013, min(fwidth(p.y) * 0.65, size.y * 0.04));
    float edge_x = max(0.022, min(fwidth(p.x) * 0.65, spacing * 0.20));
    float edge_y = max(0.022, min(fwidth(p.y) * 0.65, size.y * 0.04));
    if (vertical > width && crossbar > rail_width && min(p.x, size.x - p.x) > edge_x && min(p.y, size.y - p.y) > edge_y) { discard; }
    float rust = smoothstep(0.68, 0.94, hash21(floor(p * vec2(23.0, 13.0)) + pane_style.x * 127.0));
    vec3 iron = mix(vec3(0.027, 0.031, 0.029), vec3(0.075, 0.067, 0.050), pane_style.x);
    ALBEDO = mix(iron, vec3(0.18, 0.075, 0.030), rust * 0.45);
    ROUGHNESS = 0.88;
    METALLIC = 0.12;
    SPECULAR = 0.22;
}
