shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
// A cut-out drawing that can glow round its outline: the angel and the devil
// on the new-game screen. The glow is drawn in the clear margin round the
// figure, so the picture needs one at least `reach` wide.

uniform sampler2D art : source_color, filter_linear_mipmap, repeat_disable;
uniform float aspect = 1.0;                                        // picture width / height
uniform vec3 glow_colour : source_color = vec3(1.0, 0.86, 0.35);   // the body of the glow
uniform vec3 core_colour : source_color = vec3(1.0, 1.0, 0.9);     // right against the outline
uniform float glow = 0.0;                                          // 0 none .. 1 full
uniform float reach = 0.1;                                         // how far it spreads, as a fraction of the picture's height
uniform float dim = 1.0;                                           // brightness of the drawing itself

void fragment() {
	vec4 c = texture(art, UV);
	float near = 0.0;
	float wide = 0.0;
	if (glow > 0.001 && c.a < 0.99) {
		for (int i = 0; i < 16; i++) {
			float a = float(i) * 0.3927;
			vec2 d = vec2(cos(a) / aspect, sin(a));
			near = max(near, textureLod(art, UV + d * reach * 0.22, 1.0).a);
			wide += textureLod(art, UV + d * reach * 0.55, 2.0).a + textureLod(art, UV + d * reach, 3.0).a;
		}
		wide /= 32.0;
	}
	float halo = clamp(max(near, wide * 1.7), 0.0, 1.0) * glow;
	ALBEDO = mix(mix(glow_colour, core_colour, near), c.rgb * dim, c.a);
	ALPHA = c.a + (1.0 - c.a) * halo;
}
