shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
// A cut-out drawing that can glow round its outline and move a little: the
// angel and the devil on the new-game screen.
//
// Glow: drawn in the clear margin round the figure, so the picture needs one at
// least `reach` wide.
//
// Moving parts: `parts` says, in red, green and blue, how much of each of
// three parts is at each pixel (a wing, a tail, a hand: build_choice.py).
// Each part can slide and can turn about a pivot. Where a part is, the picture
// is read from where that pixel was before the part moved; the map's soft
// edges make the part bend away from the body rather than tear off it.
// Brows: two soft boxes that slide up and down. Eyes: two ovals; in a blink
// they are painted over in the skin colour from top and bottom, leaving a line.
//
// Positions are UV (0..1 across and down the picture); lengths are fractions
// of the picture's height unless they say otherwise.

uniform sampler2D art : source_color, filter_linear_mipmap, repeat_disable;
uniform float aspect = 1.0;                                        // picture width / height
uniform vec3 glow_colour : source_color = vec3(1.0, 0.86, 0.35);   // the body of the glow
uniform vec3 core_colour : source_color = vec3(1.0, 1.0, 0.9);     // right against the outline
uniform float glow = 0.0;                                          // 0 none .. 1 full
uniform float reach = 0.1;                                         // how far it spreads
uniform float dim = 1.0;                                           // brightness of the drawing itself
uniform float rim = 0.0;                                           // a thin line of the glow colour round the outline even when not glowing: black ink (the pitchfork) shows on a black screen

uniform sampler2D parts : filter_linear, repeat_disable;
uniform bool has_parts = false;
// For each part: where it turns about (x, y) and how far from there it is turning fully ...
uniform vec3 pivot_r = vec3(0.5, 0.5, 0.1);
uniform vec3 pivot_g = vec3(0.5, 0.5, 0.1);
uniform vec3 pivot_b = vec3(0.5, 0.5, 0.1);
// ... and how it has moved: slid by (x, y) of the picture's width and height, turned by z radians (clockwise on screen).
uniform vec3 move_r = vec3(0.0);
uniform vec3 move_g = vec3(0.0);
uniform vec3 move_b = vec3(0.0);

uniform vec4 brow_l = vec4(0.0);                                   // centre x, y, half width, half height (of the picture's width, height)
uniform vec4 brow_r = vec4(0.0);
uniform vec2 brow_lift = vec2(0.0);                                // how far up each has gone, of the picture's height
uniform vec4 eye_l = vec4(0.0);                                    // the same four numbers, for an oval
uniform vec4 eye_r = vec4(0.0);
uniform vec2 eye_top = vec2(-1.0);                                 // how far up each oval a lid may paint: -1 all of it, 0 only the lower half
uniform float blink = 0.0;                                         // 0 open .. 1 shut
uniform vec3 skin : source_color = vec3(0.8, 0.4, 0.15);
uniform vec3 ink : source_color = vec3(0.01, 0.0, 0.0);

// Where the pixel at p came from, before one part moved.
vec2 unmove(vec2 p, float w, vec3 move, vec3 pivot) {
	if (w < 0.002) {
		return p;
	}
	p -= move.xy * w;
	vec2 d = (p - pivot.xy) * vec2(aspect, 1.0);
	float turn = -move.z * w * smoothstep(0.0, pivot.z, length(d));
	float c = cos(turn);
	float s = sin(turn);
	d = vec2(d.x * c - d.y * s, d.x * s + d.y * c);
	return pivot.xy + d / vec2(aspect, 1.0);
}

// How much of a soft box is at uv: 1 in the middle, 0 from its edge outwards.
float in_box(vec4 box, vec2 uv) {
	if (box.z <= 0.0) {
		return 0.0;
	}
	vec2 q = abs(uv - box.xy) / box.zw;
	return 1.0 - smoothstep(0.55, 1.0, max(q.x, q.y));
}

// A shut or shutting eye: skin from the top and bottom, a line left across the middle.
vec3 lid(vec3 c, vec4 eye, float top, vec2 uv) {
	if (eye.z <= 0.0 || blink <= 0.0) {
		return c;
	}
	vec2 e = (uv - eye.xy) / eye.zw;
	if (dot(e, e) >= 1.0 || e.y < top) {
		return c;
	}
	float open = 1.0 - blink;
	float from_line = abs(e.y - 0.12 * (1.0 - e.x * e.x));            // the lash line sags a little in the middle
	if (from_line < max(open, 0.2)) {
		return open > 0.2 ? c : (abs(e.x) < 0.9 ? ink : skin);
	}
	return skin;
}

void fragment() {
	vec2 src = UV;
	if (has_parts) {
		vec3 w = textureLod(parts, UV, 0.0).rgb;
		src = unmove(src, w.r, move_r, pivot_r);
		src = unmove(src, w.g, move_g, pivot_g);
		src = unmove(src, w.b, move_b, pivot_b);
	}
	src.y += in_box(brow_l, UV) * brow_lift.x + in_box(brow_r, UV) * brow_lift.y;
	vec2 off = src - UV;
	vec4 c = texture(art, src);
	if (c.a > 0.5) {
		c.rgb = lid(lid(c.rgb, eye_l, eye_top.x, UV), eye_r, eye_top.y, UV);
	}
	float near = 0.0;
	float wide = 0.0;
	if ((glow > 0.001 || rim > 0.001) && c.a < 0.99) {
		for (int i = 0; i < 16; i++) {
			float a = float(i) * 0.3927;
			vec2 d = vec2(cos(a) / aspect, sin(a));
			near = max(near, textureLod(art, src + d * reach * 0.22, 1.0).a);
			wide += textureLod(art, UV + off + d * reach * 0.55, 2.0).a + textureLod(art, UV + off + d * reach, 3.0).a;
		}
		wide /= 32.0;
	}
	float halo = max(clamp(max(near, wide * 1.7), 0.0, 1.0) * glow, near * rim * dim);
	ALBEDO = mix(mix(glow_colour, core_colour, near * smoothstep(0.0, 0.4, glow)), c.rgb * dim, c.a);
	ALPHA = c.a + (1.0 - c.a) * halo;
}
