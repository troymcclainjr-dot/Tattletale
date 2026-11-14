shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
// A cut-out drawing that can glow round its outline and whose parts can move:
// the angel and the devil on the new-game screen.
//
// The figure is a body (`art`) and up to three parts cut out of it (a wing, a
// tail, a pitchfork: build_choice.py). `layer` is the parts in colour, in
// place; `parts` says, in red, green and blue, which part each pixel of the
// layer belongs to. A part moves as a stiff piece of card: it turns about a
// pivot and slides. Nothing else is touched, so a part moving beside a face
// cannot pull the face about. A part goes behind the body or in front of it.
//
// A part can also stretch instead of sliding as a whole (`ramp`): all of the
// slide at one end, none at the other. The devil's arm does, between his fist
// and his shoulder; the angel's hands do, from fingertips to heels.
//
// Glow: drawn in the clear margin round the whole figure, parts where they
// are now, so the picture needs a margin at least `reach` wide.
// Brows: two soft boxes on the body that slide up and down. Eyes: two ovals;
// in a blink they are painted over in the skin colour, leaving a line.
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

uniform sampler2D layer : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D parts : filter_linear_mipmap, repeat_disable;
uniform vec3 used = vec3(0.0);                                     // 1 for each of red, green, blue that is a part
uniform vec3 behind = vec3(1.0);                                   // 1: that part is behind the body; 0: in front
uniform vec2 pivot_r = vec2(0.5);                                  // where each part turns about
uniform vec2 pivot_g = vec2(0.5);
uniform vec2 pivot_b = vec2(0.5);
// How each has moved: slid by (x, y) of the picture's width and height, turned by z radians (clockwise on screen).
uniform vec3 move_r = vec3(0.0);
uniform vec3 move_g = vec3(0.0);
uniform vec3 move_b = vec3(0.0);
// A stretch: x = 0 none; 1 the part slides up and down by an amount that depends on how far across it is;
// 2 by how far down it is. y = where it slides in full, z = where it does not move at all.
uniform vec3 ramp_r = vec3(0.0);
uniform vec3 ramp_g = vec3(0.0);
uniform vec3 ramp_b = vec3(0.0);

uniform vec4 brow_l = vec4(0.0);                                   // centre x, y, half width, half height (of the picture's width, height)
uniform vec4 brow_r = vec4(0.0);
uniform vec2 brow_lift = vec2(0.0);                                // how far up each has gone, of the picture's height
uniform vec4 eye_l = vec4(0.0);                                    // the same four numbers, for an oval
uniform vec4 eye_r = vec4(0.0);
uniform vec2 eye_top = vec2(-1.0);                                 // how far up each oval a lid may paint: -1 all of it, 0 only the lower half
uniform float blink = 0.0;                                         // 0 open .. 1 shut
uniform vec3 skin : source_color = vec3(0.8, 0.4, 0.15);
uniform vec3 ink : source_color = vec3(0.01, 0.0, 0.0);

// Where on the layer the pixel at p shows, for a part that has moved.
vec2 back(vec2 p, vec3 move, vec2 pivot, vec3 ramp) {
	if (ramp.x > 1.5) {
		// Slides by move.y * w, where w falls from 1 at ramp.y to 0 at ramp.z down the picture: solve for where it came from.
		float len = ramp.z - ramp.y;
		float s = (p.y - move.y * ramp.z / len) / (1.0 - move.y / len);
		if (s < ramp.y) {
			s = p.y - move.y;
		} else if (s > ramp.z) {
			s = p.y;
		}
		p.y = s;
	} else if (ramp.x > 0.5) {
		p.y -= move.y * clamp((ramp.z - p.x) / (ramp.z - ramp.y), 0.0, 1.0);
	} else {
		p -= move.xy;
	}
	vec2 d = (p - pivot) * vec2(aspect, 1.0);
	float c = cos(-move.z);
	float s = sin(-move.z);
	d = vec2(d.x * c - d.y * s, d.x * s + d.y * c);
	return pivot + d / vec2(aspect, 1.0);
}

// How much of the figure covers uv, parts where they are now. `lod`: how blurred a copy of the pictures to read.
float cover(vec2 uv, float lod) {
	float a = textureLod(art, uv, lod).a;
	a = max(a, used.r * textureLod(parts, back(uv, move_r, pivot_r, ramp_r), lod).r);
	a = max(a, used.g * textureLod(parts, back(uv, move_g, pivot_g, ramp_g), lod).g);
	a = max(a, used.b * textureLod(parts, back(uv, move_b, pivot_b, ramp_b), lod).b);
	return a;
}

// One more piece of card laid over what is there (colours already multiplied by how solid they are).
vec4 over(vec4 under, vec3 colour, float solid) {
	return vec4(colour * solid + under.rgb * (1.0 - solid), solid + under.a * (1.0 - solid));
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
	// How many picture pixels one screen pixel covers, as a mip level. Worked out once from UV, which runs
	// smoothly: where a part's pixels come from jumps at its edges and cannot be used for this.
	vec2 size = vec2(textureSize(art, 0));
	float fine = max(0.0, log2(max(length(dFdx(UV) * size), length(dFdy(UV) * size))));
	float lod = max(0.0, fine - 0.5);

	// The body, with its brows where they are now and its eyes as open as they are now.
	vec2 on_body = UV + vec2(0.0, in_box(brow_l, UV) * brow_lift.x + in_box(brow_r, UV) * brow_lift.y);
	vec4 body = textureLod(art, on_body, lod);
	if (body.a > 0.5) {
		body.rgb = lid(lid(body.rgb, eye_l, eye_top.x, UV), eye_r, eye_top.y, UV);
	}

	// The parts, each read from where it is now.
	vec2 at_r = back(UV, move_r, pivot_r, ramp_r);
	vec2 at_g = back(UV, move_g, pivot_g, ramp_g);
	vec2 at_b = back(UV, move_b, pivot_b, ramp_b);
	float a_r = used.r * textureLod(parts, at_r, lod).r;
	float a_g = used.g * textureLod(parts, at_g, lod).g;
	float a_b = used.b * textureLod(parts, at_b, lod).b;
	vec3 c_r = textureLod(layer, at_r, lod).rgb;
	vec3 c_g = textureLod(layer, at_g, lod).rgb;
	vec3 c_b = textureLod(layer, at_b, lod).rgb;

	// Stacked: the parts behind, the body, the parts in front.
	vec4 c = vec4(0.0);
	c = over(c, c_r, a_r * behind.r);
	c = over(c, c_g, a_g * behind.g);
	c = over(c, c_b, a_b * behind.b);
	c = over(c, body.rgb, body.a);
	c = over(c, c_r, a_r * (1.0 - behind.r));
	c = over(c, c_g, a_g * (1.0 - behind.g));
	c = over(c, c_b, a_b * (1.0 - behind.b));
	c.rgb /= max(c.a, 0.001);

	// The glow, in the clear margin: a tight band against the outline and a wide soft one.
	float near = 0.0;
	float wide = 0.0;
	if ((glow > 0.001 || rim > 0.001) && c.a < 0.99) {
		for (int i = 0; i < 16; i++) {
			float a = float(i) * 0.3927;
			vec2 d = vec2(cos(a) / aspect, sin(a));
			near = max(near, cover(UV + d * reach * 0.22, fine + 1.6));
			wide += cover(UV + d * reach * 0.55, fine + 1.7) + cover(UV + d * reach, fine + 2.7);
		}
		wide /= 32.0;
	}
	float halo = max(clamp(max(near, wide * 1.7), 0.0, 1.0) * glow, near * rim * dim);
	ALBEDO = mix(mix(glow_colour, core_colour, near * smoothstep(0.0, 0.4, glow)), c.rgb * dim, c.a);
	ALPHA = c.a + (1.0 - c.a) * halo;
}
