shader_type spatial;
render_mode unshaded, cull_disabled;
// A flat character drawing whose limbs can move without redrawing it, and
// whose clothes can change colour.
//
// Legs: everything below the hip line belongs to one leg or the other; a mask
// says which, following the drawn inseam. Each leg is its own layer hung from
// the hip line. It can lift (the shin shortens and the boot rises) and it can
// swing: the foot slides forwards or back and the leg leans with it, the boot
// staying flat. The two legs swing separately, so one can pass in front of the
// other. The far leg can be darkened, and the edge where the legs were cut
// apart can be inked, so each reads as a whole leg.
//
// Arms: a mask says which pixels are arm. Each arm is a rubber hose hung from
// its shoulder. It turns (`angle`: nothing at the shoulder itself, all of it
// from `arm_reach` outwards), it bows (`curl`: more turn the further along the
// arm, so it arcs like a bent elbow), and it gets longer or shorter along its
// own length (`stretch`), never thicker. It can be cut off at the wrist
// (`cut`), for when a fist drawn with the thing he holds takes the hand's
// place (paper_actor.gd, paper_prop.gdshader).
//
// Side-on only one arm is drawn. With both hands on something the far arm is
// drawn too (`far_arm_copy`): a second copy of the near one, hung from a point
// behind his chest and drawn UNDER his body, so it comes out from behind him.
//
// Clothes: `regions` says which piece of clothing each pixel belongs to (its
// red channel: 1 hat, 2 jacket, 3 shirt, 4 trousers, 5 shoes, 6 the bare arm
// a long sleeve would cover). A piece is repainted by scaling its new colour
// by how light the drawing is there against the colour it was drawn in, so the
// ink lines and soft edges stay.
//
// `layer` draws part of him: 1 everything but the near arm, 2 the near arm
// alone. paper_actor.gd lays a second card over what he holds, with the near
// arm on it, so that arm passes in front of a rifle.
//
// Positions are UV (0..1 across and down the drawing); lengths are fractions of
// the drawing's height.

uniform sampler2D art : source_color, filter_linear_mipmap, repeat_disable;
uniform float aspect = 0.58;           // drawing width / height
uniform float pad = 0.0;               // the card is this much wider than the drawing at each side (a fraction of the
                                       // drawing's width): room for an arm raised out past the drawing's edge
uniform vec3 ink : source_color = vec3(0.03, 0.0, 0.0);
uniform float toward = 0.0;            // metres nearer the eye than the card really is (the copy that carries the near arm)
uniform int layer = 0;                 // 0 all of him, 1 all but the near arm, 2 the near arm only

uniform sampler2D limbs : filter_linear, repeat_disable;   // red: arm on the left of the picture, green: on the right
uniform sampler2D arm_art : source_color, filter_linear_mipmap, repeat_disable;   // the drawing the arms are taken from
uniform bool arms_drawn_here = true;   // false: this drawing has no arms of its own, they come from arm_art
uniform bool has_limbs = false;
uniform bool far_arm_hidden = false;   // the right-hand arm is not drawn (the body hides it side-on)
uniform bool far_arm_copy = false;     // side-on, both hands on something: the far arm is a copy of the near one, under the body
uniform vec2 far_arm_shift = vec2(0.0);   // where that copy hangs from, measured from the near arm's shoulder
uniform bool arms_under = false;       // the arms go behind the body (seen from the back, hands in front of him)
uniform vec2 arm_l_shift = vec2(0.0);  // the left-hand arm is drawn this far from where it is in arm_art
uniform float arm_l_top = 0.0;         // and nothing of it is drawn above this line (a sleeve covers it)...
uniform vec2 arm_l_top_x = vec2(-9.0, 9.0);   // ...between these two x (the sleeve's sides): raised, the arm comes out past them
uniform vec2 arm_l_pivot = vec2(0.3, 0.55);
uniform vec2 arm_r_pivot = vec2(0.7, 0.55);
uniform float arm_l_angle = 0.0;       // radians, positive swings the hand to the right of the picture
uniform float arm_r_angle = 0.0;
uniform float arm_l_curl = 0.0;        // radians more by the fingertips: the arm bows
uniform float arm_r_curl = 0.0;
uniform float arm_l_stretch = 1.0;     // length, against how it was drawn
uniform float arm_r_stretch = 1.0;
uniform vec2 arm_from = vec2(0.0);     // nothing of an arm is drawn nearer its shoulder than this (x the left-hand arm, y the right): its root, when it goes behind him
uniform float arm_l_cut = 9.0;         // nothing drawn further than this along the arm (the wrist, when a fist takes over)
uniform float arm_r_cut = 9.0;
uniform vec2 arm_l_axis = vec2(0.0, 1.0);   // the way each arm runs as drawn, shoulder to hand (a unit vector, y down)
uniform vec2 arm_r_axis = vec2(0.0, 1.0);
uniform float arm_len = 0.21;          // shoulder to fingertips, for the bow
uniform float arm_reach = 0.1;
uniform float arm_joint = 0.034;       // what was drawn this close to a shoulder stays put under the moving arm, so the join never opens
uniform float arm_ink = 0.0;           // width of the line inked where an arm was cut from the body (0: none)
uniform bool joint_half = false;       // keep less of that disc on the far side of the arm from the body (the armpit side matters; the other is a flap)
uniform float arm_stub = 0.02;         // an arm that bends at its elbow keeps this much below the elbow as drawn, for the forearm to come out of
uniform vec2 arm_elbow = vec2(0.0);    // x the left-hand arm, y the right: above 0.5 its pivot is its elbow, and what is above that stays as drawn
uniform float rim_ink = 0.0;           // width of the line inked across an arm's cut end and round the shoulder disc (0: none)

uniform sampler2D legs : filter_linear, repeat_disable;    // white: the leg on the right of the picture
uniform float hip_v = 2.0;             // above 1: no legs to move
uniform float knee_v = 3.0;
uniform float lift_l = 0.0;
uniform float lift_r = 0.0;
uniform float swing_l = 0.0;           // how far the foot has slid to the right of the picture
uniform float swing_r = 0.0;
uniform bool near_leg_right = true;    // which leg is in front when they cross
uniform float far_leg_shade = 1.0;     // the far leg's colour is multiplied by this
uniform float leg_ink = 0.0;           // width of the line inked where the legs were cut apart (0: none)

uniform sampler2D under : source_color, filter_linear_mipmap, repeat_disable;   // the drawing without its arms: what is behind an arm (a wardrobe character)
uniform sampler2D under_regions : filter_nearest, repeat_disable;               // ...and that picture's clothes
uniform bool has_under = false;
uniform sampler2D regions : filter_nearest, repeat_disable;       // this drawing's clothes (see the top)
uniform sampler2D arm_regions : filter_nearest, repeat_disable;   // and those of the drawing the arms come from
uniform bool has_regions = false;
uniform vec3 dress_from[7] : source_color;    // the colour each piece was drawn in (index: the region's number)
uniform vec3 dress_to[7] : source_color;      // the colour it is to be; the same as dress_from leaves it alone
uniform bool cuffs = false;            // long sleeves: ink the line at the wrist where the sleeve ends

const vec3 LUMA = vec3(0.2126, 0.7152, 0.0722);

void vertex() {
	vec4 v = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	v.xyz -= normalize(v.xyz) * toward;
	POSITION = PROJECTION_MATRIX * v;
}

// The colour c, drawn at src of a drawing whose clothes are `map`, in the clothes he has on now.
vec3 dress(vec3 c, vec2 src, sampler2D map) {
	if (!has_regions) {
		return c;
	}
	vec4 m = textureLod(map, src, 0.0);
	int id = int(m.r * 255.0 / 40.0 + 0.5);
	if (id < 1 || id > 6) {
		return c;
	}
	if (id == 6 && cuffs && m.g > 0.5) {
		return ink;
	}
	if (dress_from[id] == dress_to[id]) {
		return c;
	}
	float was = dot(c, LUMA);
	float cloth = dot(dress_from[id], LUMA);
	if (was <= cloth) {         // the cloth, its shading and its ink: the new colour, as dark as it was drawn
		return dress_to[id] * (was / max(cloth, 0.02));
	}
	// Lighter than the cloth: a detail on it (a stripe, a number, a sparkle, a sole) or the soft edge of one,
	// which is part cloth, part detail. Only the cloth part changes colour, so the detail keeps its own
	// colour and no fringe of the old cloth is left round it.
	float detail = clamp((was - cloth) / max(1.0 - cloth, 0.05), 0.0, 1.0);
	return clamp(c + (dress_to[id] - dress_from[id]) * (1.0 - detail), 0.0, 1.0);
}

// Where in the drawing the pixel at uv comes from if it shows this leg; x < -1 if it does not.
vec2 leg_source(vec2 uv, float side, float lift, float swing) {
	float v = uv.y + lift;
	if (uv.y <= knee_v - lift) {
		v = hip_v + (uv.y - hip_v) * (knee_v - hip_v) / (knee_v - lift - hip_v);
	}
	float u = uv.x - swing * (v - hip_v) / (1.0 - hip_v) / aspect;
	if (v > 1.0 || u < 0.0 || u > 1.0) {
		return vec2(-9.0);
	}
	bool right = textureLod(legs, vec2(u, v), 0.0).r > 0.5;
	if (right != (side > 0.0)) {
		return vec2(-9.0);
	}
	return vec2(u, v);
}

// One leg's colour at uv (alpha 0 where it does not cover the pixel).
vec4 leg(vec2 uv, float side, float lift, float swing, vec2 dx, vec2 dy) {
	vec2 src = leg_source(uv, side, lift, swing);
	if (src.x < -1.0) {
		return vec4(0.0);
	}
	vec4 c;
	if (has_under && arms_drawn_here) {      // his legs come from the picture without his arms: a hand that hung over one stays out of it
		c = textureGrad(under, src, dx, dy);
		c.rgb = dress(c.rgb, src, under_regions);
	} else {
		c = textureGrad(art, src, dx, dy);
		c.rgb = dress(c.rgb, src, regions);
	}
	if (leg_ink > 0.0 && c.a > 0.5) {
		// Close to the other leg's side of the cut: this is the cut edge.
		bool other = textureLod(legs, src - vec2(side * leg_ink / aspect, 0.0), 0.0).r > 0.5;
		if (other != (side > 0.0)) {
			c.rgb = ink;
		}
	}
	return c;
}

// What shows at uv where an arm was drawn and has moved away: nothing, or, for a drawing that has the
// picture of itself without arms (`under`), the body that was behind the arm.
vec4 behind_arm(vec2 uv, vec2 dx, vec2 dy) {
	if (!has_under) {
		return vec4(0.0);
	}
	vec4 c = textureGrad(under, uv, dx, dy);
	c.rgb = dress(c.rgb, uv, under_regions);
	return c;
}

// Where in arm_art the pixel at uv comes from, for an arm that has turned, bowed and stretched.
vec2 arm_source(vec2 uv, vec2 pivot, float angle, float curl, float stretch, vec2 axis) {
	vec2 d = (uv - pivot) * vec2(aspect, 1.0);
	float r = length(d) / stretch;               // how far along the arm this was drawn (near enough: the arm is thin)
	float turn = angle * smoothstep(0.0, arm_reach, r) + curl * clamp((r - arm_reach) / max(arm_len - arm_reach, 0.01), 0.0, 1.2);
	float c = cos(turn);
	float s = sin(turn);
	d = vec2(d.x * c - d.y * s, d.x * s + d.y * c);
	d -= axis * dot(d, axis) * (1.0 - 1.0 / stretch);      // take the stretch back out, along the arm only
	return pivot + d / vec2(aspect, 1.0);
}

// One arm's colour from where it sits in arm_art (alpha 0 where src is not arm).
// `body_side` is +1 if the body is to the right of this arm in the drawing.
vec4 arm(vec2 src, vec2 pivot, float cut, float body_side, bool left, vec2 dx, vec2 dy) {
	if (src.x < 0.0 || src.x > 1.0 || src.y < 0.0 || src.y > 1.0) {
		return vec4(0.0);
	}
	float along_arm = length((src - pivot) * vec2(aspect, 1.0));
	if (along_arm > cut || along_arm < (left ? arm_from.x : arm_from.y)) {
		return vec4(0.0);
	}
	vec4 m = textureLod(limbs, src, 0.0);
	if ((left ? m.r : m.g) < 0.5) {
		return vec4(0.0);
	}
	vec4 c = textureGrad(arm_art, src, dx, dy);
	c.rgb = dress(c.rgb, src, arm_regions);
	if (rim_ink > 0.0 && cut < 8.0 && c.a > 0.5 && along_arm > cut - rim_ink) {
		c.rgb = ink;       // the cut end: whatever of it a fist does not cover is closed with a line
	}
	float root = left ? arm_from.x : arm_from.y;
	if (rim_ink > 0.0 && root > 0.0 && c.a > 0.5 && along_arm < root + rim_ink) {
		c.rgb = ink;       // and the end it starts from, when its root is not drawn
	}
	if (arm_ink > 0.0 && c.a > 0.5) {
		vec2 beside = src + vec2(body_side * arm_ink / aspect, 0.0);
		vec4 mb = textureLod(limbs, beside, 0.0);
		if ((left ? mb.r : mb.g) < 0.5 && textureLod(arm_art, beside, 0.0).a > 0.5) {
			c.rgb = ink;   // the arm was cut from the body here, not from the background
		}
	}
	return c;
}

// The forearm of an arm that bends at its elbow (arm_elbow): `a` is the arm's colour at uv, taken from src.
// Nothing from above the elbow turns; and where the forearm's cut end shows, past the sleeve it comes out of, it is inked.
vec4 forearm(vec4 a, vec2 uv, vec2 src, vec2 pivot, vec2 axis, float bends, bool left) {
	if (bends < 0.5) {
		return a;
	}
	float along = dot((src - pivot) * vec2(aspect, 1.0), axis);
	if (along < 0.0) {
		return vec4(0.0);
	}
	if (a.a > 0.5 && rim_ink > 0.0 && along < rim_ink) {
		vec4 m = textureLod(limbs, uv, 0.0);
		bool kept = (left ? m.r : m.g) > 0.5 && dot((uv - pivot) * vec2(aspect, 1.0), axis) < arm_stub;
		if (!kept) {
			a.rgb = ink;
		}
	}
	return a;
}

// The left-hand arm (the near one, side-on) at uv, where it is now.
vec4 near_arm(vec2 uv, vec2 dx, vec2 dy) {
	if (uv.y < arm_l_top && uv.x > arm_l_top_x.x && uv.x < arm_l_top_x.y) {
		return vec4(0.0);
	}
	vec2 src = arm_source(uv - arm_l_shift, arm_l_pivot, arm_l_angle, arm_l_curl, arm_l_stretch, arm_l_axis);
	return forearm(arm(src, arm_l_pivot, arm_l_cut, 1.0, true, dx, dy), uv, src, arm_l_pivot, arm_l_axis, arm_elbow.x, true);
}

void fragment() {
	vec2 uv = vec2(UV.x * (1.0 + 2.0 * pad) - pad, UV.y);     // where this is in the drawing; x runs outside 0..1 in the spare card
	bool inside = uv.x >= 0.0 && uv.x <= 1.0;
	vec2 dx = dFdx(uv);
	vec2 dy = dFdy(uv);
	vec4 col = vec4(0.0);
	if (layer == 2) {
		if (has_limbs) {
			col = near_arm(uv, dx, dy);
		}
		ALBEDO = col.rgb;
		ALPHA = col.a;
		ALPHA_SCISSOR_THRESHOLD = 0.5;
	} else {
		if (!inside) {
			col = vec4(0.0);
		} else if (uv.y <= hip_v) {
			col = textureGrad(art, uv, dx, dy);
			col.rgb = dress(col.rgb, uv, regions);
		} else {
			vec4 l = leg(uv, -1.0, lift_l, swing_l, dx, dy);
			vec4 r = leg(uv, 1.0, lift_r, swing_r, dx, dy);
			vec4 far = near_leg_right ? l : r;
			vec4 near = near_leg_right ? r : l;
			if (far.a > 0.5) {
				col = vec4(far.rgb * far_leg_shade, far.a);
			}
			if (near.a > 0.5) {
				col = near;
			}
		}
		if (has_limbs) {
			vec4 rest = inside ? textureLod(limbs, uv, 0.0) : vec4(0.0);
			if (has_under && arms_drawn_here && inside && uv.y <= hip_v && max(rest.r, rest.g) <= 0.5) {
				// Off the arms, the picture without them: seen small, a hair of an arm's outline lies outside
				// `limbs`, and it would be left as dots where the arm hung.
				col = behind_arm(uv, dx, dy);
			}
			if (arms_drawn_here && max(rest.r, rest.g) > 0.5) {
				// The arm has moved away from where it was drawn. Right at the shoulder
				// the drawing is kept, like the disc at a paper puppet's joint: a bent
				// arm pulls its armpit corner away from the stub it hangs from, and
				// without this the background shows through the crack.
				vec2 pv = rest.r > 0.5 ? arm_l_pivot : arm_r_pivot;
				vec2 ax = rest.r > 0.5 ? arm_l_axis : arm_r_axis;
				vec2 off = (uv - pv) * vec2(aspect, 1.0);
				float from_pivot = length(off);
				float inward = dot(off, rest.r > 0.5 ? vec2(ax.y, -ax.x) : vec2(-ax.y, ax.x));     // towards the body, across the arm
				if ((rest.r > 0.5 ? arm_elbow.x : arm_elbow.y) > 0.5) {
					// An arm that bends at the elbow: above it, and a short stub below, it is as drawn.
					float along = dot(off, ax);
					if (along > arm_stub) {
						col = behind_arm(uv, dx, dy);
					} else if (rim_ink > 0.0 && along > arm_stub - rim_ink) {
						col.rgb = ink;     // the stub's end, where the forearm does not cover it
					}
				} else {
					// On the far side of the arm from the body, a held arm keeps less of the disc: more is a flap.
					float keep = joint_half && inward < 0.0 ? arm_joint * 0.6 : arm_joint;
					if (from_pivot > keep) {
						col = behind_arm(uv, dx, dy);
					} else if (rim_ink > 0.0 && from_pivot > keep - rim_ink) {
						col.rgb = ink;     // the disc's own edge, where the moved arm does not cover it
					}
				}
			}
			bool body_here = col.a > 0.5;
			if (far_arm_copy) {
				// Behind him: it shows only where his body does not.
				if (!body_here) {
					vec2 from = arm_l_shift + far_arm_shift;
					vec4 a = arm(arm_source(uv - from, arm_l_pivot, arm_r_angle, arm_r_curl, arm_r_stretch, arm_l_axis), arm_l_pivot, arm_r_cut, 1.0, true, dx, dy);
					if (a.a > 0.5) {
						col = a;
					}
				}
			} else if (!far_arm_hidden && !(arms_under && body_here)) {
				vec2 src = arm_source(uv, arm_r_pivot, arm_r_angle, arm_r_curl, arm_r_stretch, arm_r_axis);
				vec4 a = forearm(arm(src, arm_r_pivot, arm_r_cut, -1.0, false, dx, dy), uv, src, arm_r_pivot, arm_r_axis, arm_elbow.y, false);
				if (a.a > 0.5) {
					col = a;
				}
			}
			if (layer == 0 && !(arms_under && body_here)) {
				vec4 a = near_arm(uv, dx, dy);
				if (a.a > 0.5) {
					col = a;
				}
			}
		}
		ALBEDO = col.rgb;
		ALPHA = col.a;
		ALPHA_SCISSOR_THRESHOLD = 0.5;
	}
}
