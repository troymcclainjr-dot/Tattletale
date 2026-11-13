shader_type spatial;
render_mode unshaded, cull_disabled;
// A flat character drawing whose limbs can move without redrawing it.
//
// Legs: everything below the hip line belongs to one leg or the other; a mask
// says which, following the drawn inseam. Each leg is its own layer hung from
// the hip line. It can lift (the shin shortens and the boot rises) and it can
// swing: the foot slides forwards or back and the leg leans with it, the boot
// staying flat. The two legs swing separately, so one can pass in front of the
// other. The far leg can be darkened, and the edge where the legs were cut
// apart can be inked, so each reads as a whole leg.
// Arms: a mask says which pixels are arm. Each arm bends round its shoulder like
// a noodle: no turn at the shoulder, the full angle from `arm_reach` outwards.
//
// Positions are UV (0..1 across and down the drawing); lengths are fractions of
// the drawing's height.

uniform sampler2D art : source_color, filter_linear_mipmap, repeat_disable;
uniform float aspect = 0.58;           // drawing width / height
uniform vec3 ink : source_color = vec3(0.03, 0.0, 0.0);

uniform sampler2D limbs : filter_linear, repeat_disable;   // red: arm on the left of the picture, green: on the right
uniform sampler2D arm_art : source_color, filter_linear_mipmap, repeat_disable;   // the drawing the arms are taken from
uniform bool arms_drawn_here = true;   // false: this drawing has no arms of its own, they come from arm_art
uniform bool has_limbs = false;
uniform bool far_arm_hidden = false;   // the right-hand arm is not drawn (the body hides it side-on)
uniform vec2 arm_l_shift = vec2(0.0);  // the left-hand arm is drawn this far from where it is in arm_art
uniform float arm_l_top = 0.0;         // and nothing of it is drawn above this line (a sleeve covers it)
uniform vec2 arm_l_pivot = vec2(0.3, 0.55);
uniform vec2 arm_r_pivot = vec2(0.7, 0.55);
uniform float arm_l_angle = 0.0;       // radians, positive swings the hand to the right of the picture
uniform float arm_r_angle = 0.0;
uniform float arm_reach = 0.1;
uniform float arm_ink = 0.0;           // width of the line inked where an arm was cut from the body (0: none)

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
	vec4 c = textureGrad(art, src, dx, dy);
	if (leg_ink > 0.0 && c.a > 0.5) {
		// Close to the other leg's side of the cut: this is the cut edge.
		bool other = textureLod(legs, src - vec2(side * leg_ink / aspect, 0.0), 0.0).r > 0.5;
		if (other != (side > 0.0)) {
			c.rgb = ink;
		}
	}
	return c;
}

vec2 arm_source(vec2 uv, vec2 pivot, float angle) {
	vec2 d = (uv - pivot) * vec2(aspect, 1.0);
	float turn = angle * smoothstep(0.0, arm_reach, length(d));
	float c = cos(turn);
	float s = sin(turn);
	d = vec2(d.x * c - d.y * s, d.x * s + d.y * c);
	return pivot + d / vec2(aspect, 1.0);
}

// One arm's colour from where it sits in arm_art (alpha 0 where src is not arm).
// `body_side` is +1 if the body is to the right of this arm in the drawing.
vec4 arm(vec2 src, float body_side, bool left, vec2 dx, vec2 dy) {
	vec4 m = textureLod(limbs, src, 0.0);
	if ((left ? m.r : m.g) < 0.5) {
		return vec4(0.0);
	}
	vec4 c = textureGrad(arm_art, src, dx, dy);
	if (arm_ink > 0.0 && c.a > 0.5) {
		vec2 beside = src + vec2(body_side * arm_ink / aspect, 0.0);
		vec4 mb = textureLod(limbs, beside, 0.0);
		if ((left ? mb.r : mb.g) < 0.5 && textureLod(arm_art, beside, 0.0).a > 0.5) {
			c.rgb = ink;   // the arm was cut from the body here, not from the background
		}
	}
	return c;
}

void fragment() {
	vec2 dx = dFdx(UV);
	vec2 dy = dFdy(UV);
	vec4 col = vec4(0.0);
	if (UV.y <= hip_v) {
		col = textureGrad(art, UV, dx, dy);
	} else {
		vec4 l = leg(UV, -1.0, lift_l, swing_l, dx, dy);
		vec4 r = leg(UV, 1.0, lift_r, swing_r, dx, dy);
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
		vec4 rest = textureLod(limbs, UV, 0.0);
		if (arms_drawn_here && max(rest.r, rest.g) > 0.5) {
			col.a = 0.0;   // the arm has moved away from where it was drawn
		}
		if (!far_arm_hidden) {
			vec4 a = arm(arm_source(UV, arm_r_pivot, arm_r_angle), -1.0, false, dx, dy);
			if (a.a > 0.5) {
				col = a;
			}
		}
		if (UV.y >= arm_l_top) {
			vec4 a = arm(arm_source(UV - arm_l_shift, arm_l_pivot, arm_l_angle), 1.0, true, dx, dy);
			if (a.a > 0.5) {
				col = a;
			}
		}
	}
	ALBEDO = col.rgb;
	ALPHA = col.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}
