shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, shadows_disabled;
// Speed lines and dust for a sprint (scripts/speed_lines.gd): flat ink on a card that faces the camera.
//
// mode 0: up to five tapered ink strokes. Each runs from `a` (thick, the end nearest him) to `b`
//         (drawn to a point), like a brush stroke flicked away from him.
// mode 1: a puff of dust: a small cloud of a few round lobes with a flat foot, pale, with an inked rim.
//         As `age` goes from 0 to 1 its fill fades, its rim thins and breaks up, and it is gone.
//
// Positions are metres from the middle of the quad, y up. Nothing here is solid: it is drawn after
// everything opaque, never hides anything behind it from the depth test, and fades in and out.

uniform int mode = 0;
uniform vec2 size = vec2(1.0);            // the quad, metres
uniform vec2 seg_a[5];                    // mode 0: where each stroke starts (its thick end)
uniform vec2 seg_b[5];                    // ...and where it runs out
uniform float seg_w[5];                   // ...and its half-width at the start, metres (0: not drawn)
uniform float strength = 1.0;             // 0 nothing .. 1 all there
uniform float halo = 0.0;                 // mode 0: a pale edge this wide round each stroke (metres), half see-through
uniform vec3 ink : source_color = vec3(0.03, 0.0, 0.0);
uniform vec3 dust : source_color = vec3(0.92, 0.89, 0.82);
uniform float age = 0.0;                  // mode 1
uniform float rim = 0.15;                 // mode 1: the ink round the puff, as a fraction of its half-size
uniform float flip = 1.0;                 // mode 1: -1 mirrors the cloud, so no two in a row look the same

float stroke(vec2 p, vec2 a, vec2 b, float w) {
	vec2 ab = b - a;
	float t = clamp(dot(p - a, ab) / max(dot(ab, ab), 1e-6), 0.0, 1.0);
	float d = length(p - (a + ab * t));
	float half_w = w * pow(1.0 - t, 0.85) * (0.55 + 0.45 * smoothstep(0.0, 0.12, t));
	return d - half_w;
}

float lobe(vec2 q, vec2 c, float r) {
	return length(q - c) - r;
}

// The cloud, in units of the quad's half-size: below zero inside.
float cloud(vec2 q) {
	q.x *= flip;
	float d = lobe(q, vec2(0.0, -0.08), 0.42);
	d = min(d, lobe(q, vec2(-0.42, -0.26), 0.3));
	d = min(d, lobe(q, vec2(0.44, -0.24), 0.32));
	d = min(d, lobe(q, vec2(-0.18, 0.26), 0.3));
	d = min(d, lobe(q, vec2(0.22, 0.2), 0.27));
	return max(d, -0.58 - q.y);            // a flat foot: it sits on the ground
}

void fragment() {
	vec2 p = (UV - 0.5) * size * vec2(1.0, -1.0);
	if (mode == 0) {
		float d = 1e3;
		for (int i = 0; i < 5; i++) {
			if (seg_w[i] > 0.0) {
				d = min(d, stroke(p, seg_a[i], seg_b[i], seg_w[i]));
			}
		}
		float aa = max(fwidth(d), 1e-5);
		float core = 1.0 - smoothstep(-aa, aa, d);
		float edge = (1.0 - smoothstep(-aa, aa, d - halo)) * 0.5;
		ALBEDO = mix(dust, ink, core / max(max(core, edge), 1e-4));
		ALPHA = max(core, edge) * strength;
	} else {
		vec2 q = p / (size * 0.5);
		float d = cloud(q);
		float aa = max(fwidth(d), 1e-5);
		float inside = 1.0 - smoothstep(-aa, aa, d);
		float band = rim * (1.0 - 0.6 * age);
		float in_fill = 1.0 - smoothstep(-band - aa, -band + aa, d);
		// The rim breaks up as it goes: gaps open round it.
		float round_it = atan(q.y, q.x * flip);
		float gaps = smoothstep(0.15, 0.35, sin(round_it * 7.0 + 2.3) * 0.5 + 0.5 - age * 0.9 + 0.25);
		float rim_a = (inside - in_fill) * (1.0 - smoothstep(0.55, 1.0, age)) * gaps;
		float fill_a = in_fill * 0.9 * pow(1.0 - age, 1.4);
		vec3 col = mix(dust, ink, rim_a / max(rim_a + fill_a, 1e-4));
		ALBEDO = col;
		ALPHA = clamp(rim_a + fill_a, 0.0, 1.0) * strength;
	}
}
