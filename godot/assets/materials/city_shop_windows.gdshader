shader_type spatial;
render_mode cull_disabled;
varying float shop_kind;
float rect(vec2 uv, vec2 center, vec2 size) {
	vec2 d = abs(uv - center) - size * 0.5;
	return 1.0 - step(0.0, max(d.x, d.y));
}
void vertex() { shop_kind = INSTANCE_CUSTOM.r; }
void fragment() {
	vec2 uv = UV;
	vec3 color = vec3(0.085, 0.12, 0.13);
	if (shop_kind > 1.5 && shop_kind < 2.5) {
		// Two front-loading washers behind the laundry's display glass.
		float boxes = rect(uv, vec2(0.27, 0.61), vec2(0.41, 0.58)) + rect(uv, vec2(0.73, 0.61), vec2(0.41, 0.58));
		color = mix(color, vec3(0.72, 0.74, 0.69), clamp(boxes, 0.0, 1.0));
		float disc = min(length((uv - vec2(0.27, 0.64)) * vec2(1.0, 1.1)), length((uv - vec2(0.73, 0.64)) * vec2(1.0, 1.1)));
		if (disc < 0.145) { color = vec3(0.14, 0.21, 0.25); }
		if (disc < 0.10) { color = vec3(0.27, 0.37, 0.39); }
	} else if (shop_kind > 2.5 && shop_kind < 3.5) {
		// Red, white and blue barber pole, plus two chair silhouettes.
		float pole = rect(uv, vec2(0.12, 0.48), vec2(0.10, 0.76));
		float stripe = mod(floor((uv.y + uv.x) * 16.0), 3.0);
		vec3 pole_color = stripe < 1.0 ? vec3(0.72, 0.19, 0.15) : (stripe < 2.0 ? vec3(0.86, 0.85, 0.77) : vec3(0.18, 0.29, 0.49));
		color = mix(color, pole_color, pole);
		float chair = rect(uv, vec2(0.43, 0.59), vec2(0.23, 0.25)) + rect(uv, vec2(0.76, 0.59), vec2(0.23, 0.25));
		color = mix(color, vec3(0.38, 0.17, 0.13), clamp(chair, 0.0, 1.0));
	} else if (shop_kind > 0.5 && shop_kind < 1.5) {
		// Bottles on three display shelves.
		vec2 bottle = fract(uv * vec2(7.0, 3.0));
		float body = rect(bottle, vec2(0.5, 0.56), vec2(0.45, 0.55));
		float neck = rect(bottle, vec2(0.5, 0.20), vec2(0.20, 0.20));
		color = mix(color, vec3(0.28, 0.40, 0.20), clamp(body + neck, 0.0, 1.0));
		if (bottle.y > 0.90) { color = vec3(0.43, 0.32, 0.18); }
	} else if (shop_kind > 3.5 && shop_kind < 4.5) {
		float menu = rect(uv, vec2(0.69, 0.42), vec2(0.43, 0.65));
		color = mix(color, vec3(0.77, 0.68, 0.45), menu);
		if (menu > 0.5 && fract(uv.y * 15.0) < 0.20) { color *= 0.48; }
		color = mix(color, vec3(0.70, 0.35, 0.13), rect(uv, vec2(0.25, 0.72), vec2(0.35, 0.16)));
	} else {
		vec2 crate = fract(uv * vec2(4.0, 3.0));
		float fruit = 1.0 - step(0.24, length(crate - vec2(0.5)));
		color = mix(color, vec3(0.48, 0.40, 0.17), fruit * step(0.42, uv.y));
	}
	// Faint oblique reflection and dusty edges retain the impression of glass.
	float reflection = 1.0 - smoothstep(0.02, 0.09, abs(uv.x - uv.y * 0.45 - 0.18));
	color += vec3(0.10, 0.12, 0.12) * reflection;
	ALBEDO = color;
	ROUGHNESS = 0.35;
}
