shader_type sky;
render_mode use_quarter_res_pass;

// Only explicit world-clock uniforms change this material. No camera/time/light
// built-ins: moving the player or physical sun cannot invalidate IBL every frame.
uniform vec3 sky_top : source_color = vec3(0.443, 0.608, 0.675);
uniform vec3 horizon : source_color = vec3(0.831, 0.847, 0.773);
uniform vec3 ground_bottom : source_color = vec3(0.412, 0.431, 0.392);
uniform vec3 sun_direction = vec3(0.0, 0.87, 0.49);
uniform vec3 sun_color : source_color = vec3(1.0, 0.88, 0.69);
uniform float sun_strength : hint_range(0.0, 1.0) = 1.0;
uniform vec3 cloud_lit : source_color = vec3(0.95, 0.95, 0.89);
uniform vec3 cloud_shade : source_color = vec3(0.52, 0.61, 0.64);
uniform vec2 cloud_drift = vec2(0.0);
uniform int cloud_quality : hint_range(0, 2) = 1;

float hash3(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

float noise3(vec3 p) {
	vec3 cell = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(cell), hash3(cell + vec3(1,0,0)), f.x),
		mix(hash3(cell + vec3(0,1,0)), hash3(cell + vec3(1,1,0)), f.x), f.y),
		mix(mix(hash3(cell + vec3(0,0,1)), hash3(cell + vec3(1,0,1)), f.x),
		mix(hash3(cell + vec3(0,1,1)), hash3(cell + vec3(1,1,1)), f.x), f.y), f.z);
}

float cloud_noise(vec3 p) {
	return noise3(p) * 0.72 + noise3(p * 2.13 + vec3(11.7, 3.1, 8.4)) * 0.28;
}

vec4 noise_gradient(vec3 p) {
	// Value and analytic gradient share the same eight hashes. This replaces
	// the coarse value lookup, rather than adding finite-difference samples.
	vec3 cell = floor(p);
	vec3 f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);
	vec3 du = 6.0 * f * (1.0 - f);
	float a = hash3(cell);
	float b = hash3(cell + vec3(1,0,0));
	float c = hash3(cell + vec3(0,1,0));
	float d = hash3(cell + vec3(1,1,0));
	float e = hash3(cell + vec3(0,0,1));
	float f1 = hash3(cell + vec3(1,0,1));
	float g = hash3(cell + vec3(0,1,1));
	float h = hash3(cell + vec3(1,1,1));
	float x0 = mix(a, b, u.x);
	float x1 = mix(c, d, u.x);
	float x2 = mix(e, f1, u.x);
	float x3 = mix(g, h, u.x);
	float y0 = mix(x0, x1, u.y);
	float y1 = mix(x2, x3, u.y);
	vec3 gradient = vec3(mix(mix(b-a, d-c, u.y), mix(f1-e, h-g, u.y), u.z),
		mix(x1-x0, x3-x2, u.z), y1-y0) * du;
	return vec4(mix(y0, y1, u.z), gradient);
}

float layer_distance(vec3 ray, float altitude) {
	// A curved distant layer keeps grazing rays finite. Flat slabs magnify
	// the spacing between eight samples into visible horizontal bands.
	float curvature = 0.035 * dot(ray.xz, ray.xz);
	return 2.0 * altitude / (ray.y + sqrt(ray.y * ray.y + 4.0 * curvature * altitude));
}

vec4 cloud_layer(vec3 ray) {
	vec4 result = vec4(0.0);
	if (cloud_quality > 0 && ray.y > 0.035) {
		float fade = smoothstep(0.035, 0.16, ray.y);
		float facing = pow(max(dot(ray, sun_direction), 0.0), 6.0) * sun_strength;
		if (cloud_quality == 1) {
			vec3 p = ray * layer_distance(ray, 2.3);
			p.xz += cloud_drift;
			float density = smoothstep(0.50, 0.68, cloud_noise(p * vec3(2.15, 1.7, 2.15)));
			result.a = density * 0.86 * fade;
			result.rgb = mix(cloud_shade, cloud_lit, 0.60 + facing * 0.25) * result.a;
		} else {
			// Eight samples only, at 1/16 screen pixels. No light raymarch,
			// texture lookup, shadow pass, history buffer or per-pixel jitter.
			float start = layer_distance(ray, 1.8);
			float step_length = (layer_distance(ray, 3.0) - start) / 8.0;
			for (int i = 0; i < 8; i++) {
				vec3 p = ray * (start + (float(i) + 0.5) * step_length);
				float height = (p.y + 0.035 * dot(p.xz, p.xz) - 1.8) / 1.2;
				vec3 altitude_gradient = vec3(0.07 * p.x, 1.0, 0.07 * p.z);
				p.xz += cloud_drift;
				vec3 frequency = vec3(2.15, 1.7, 2.15);
				vec3 q = p * frequency;
				vec4 coarse = noise_gradient(q);
				float detail = noise3(q * 2.13 + vec3(11.7, 3.1, 8.4));
				float cap = 2.0 * height - 1.0;
				float field = coarse.x * 0.72 + detail * 0.28 - cap * cap * 0.18;
				float density = smoothstep(0.49, 0.65, field);
				float opacity = clamp(density * step_length * 2.4, 0.0, 0.85);
				vec3 gradient = coarse.yzw * frequency * 0.72 - cap * 0.60 * altitude_gradient;
				vec3 normal = normalize(-gradient + vec3(0.0, 0.001, 0.0));
				float diffuse = max(dot(normal, sun_direction), 0.0);
				float rim = (1.0 - smoothstep(0.12, 0.55, density)) * facing * 0.18;
				float light = clamp(0.16 + diffuse * 0.68 + height * 0.16 + rim - result.a * 0.12, 0.0, 1.0);
				vec3 tint = mix(cloud_shade, cloud_lit, light);
				result.rgb += (1.0 - result.a) * opacity * tint;
				result.a += (1.0 - result.a) * opacity;
			}
			result *= fade;
		}
	}
	return result;
}

vec3 base_sky(vec3 ray) {
	return ray.y >= 0.0 ? mix(horizon, sky_top, pow(ray.y, 0.45))
		: mix(horizon, ground_bottom, pow(-ray.y, 0.35));
}

void sky() {
	if (AT_CUBEMAP_PASS) {
		// Stable palette only for reflection/ambient radiance. Clouds and the
		// visible disk do not alter the established 20%-dimmer lighting preset.
		COLOR = base_sky(EYEDIR);
	} else if (AT_QUARTER_RES_PASS) {
		vec4 clouds = cloud_layer(EYEDIR);
		COLOR = clouds.rgb;
		ALPHA = clouds.a;
	} else {
		vec3 color = base_sky(EYEDIR);
		float alignment = clamp(dot(EYEDIR, sun_direction), -1.0, 1.0);
		// A readable 0.9-degree stylized disk, aligned with the shadow caster.
		float disk = smoothstep(cos(0.0085), cos(0.0070), alignment);
		float halo = pow(max(alignment, 0.0), 180.0) * 0.18;
		float visible = sun_strength * smoothstep(-0.025, 0.015, EYEDIR.y);
		color += sun_color * (disk * 5.0 + halo) * visible;
		vec4 clouds = QUARTER_RES_COLOR;
		COLOR = color * (1.0 - clouds.a) + clouds.rgb;
	}
}
