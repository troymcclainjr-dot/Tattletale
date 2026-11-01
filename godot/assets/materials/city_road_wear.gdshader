shader_type spatial;
render_mode cull_disabled;
// Calibrated response; `--legacy-city-finishes` renames this define in memory.
#define CITY_CALIBRATED_FINISHES
varying vec3 position_world;
varying float detail_kind;
varying float detail_seed;
varying vec2 road_across;
float grit(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float soft_noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(grit(cell), grit(cell + vec2(1.0, 0.0)), f.x),
		mix(grit(cell + vec2(0.0, 1.0)), grit(cell + vec2(1.0)), f.x), f.y);
}
#ifdef CITY_CALIBRATED_FINISHES
// Noise of this world period, eased to its 0.5 mean once it nears two pixels.
float resolved_noise(vec2 at, float period, float footprint) {
	float keep = 1.0 - smoothstep(period * 0.2, period * 0.45, footprint);
	return keep > 0.0 ? mix(0.5, soft_noise(at / period), keep) : 0.5;
}
#endif
void vertex() {
	position_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	detail_kind = INSTANCE_CUSTOM.r;
	detail_seed = grit(MODEL_MATRIX[3].xz);
	road_across = normalize(MODEL_MATRIX[0].xz);
}
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
#ifdef CITY_CALIBRATED_FINISHES
	// Pixel size is taken before branching. Looking down a street it spans many
	// centimetres, so sub-pixel edge, flake and tone noise would crawl through
	// the discards; the coarse 38 cm flaking still sets every mark's shape.
	vec2 pixel = fwidth(position_world.xz);
	float footprint = max(pixel.x, pixel.y);
	float grain = resolved_noise(position_world.xz, 0.2, footprint);
#else
	float grain = soft_noise(position_world.xz * 5.0);
#endif
	if (detail_kind > 1.5) {
		float rim = length(p * vec2(1.0, 1.12));
#ifdef CITY_CALIBRATED_FINISHES
		float edge = 0.71 + resolved_noise(position_world.xz, 1.0 / 6.0, footprint) * 0.24;
#else
		float edge = 0.71 + soft_noise(position_world.xz * 6.0) * 0.24;
#endif
		if (rim > edge) { discard; }
		// Dark aggregate and an uneven depression, never a pale painted disk.
		float bowl = mix(0.007, 0.043, smoothstep(0.32, edge, rim));
		float broken_aggregate = smoothstep(0.62, 0.80, rim) * step(0.72, grain) * 0.018;
		ALBEDO = vec3(bowl + broken_aggregate) * vec3(0.97, 0.98, 1.0) * (0.82 + grain * 0.24);
#ifdef CITY_CALIBRATED_FINISHES
		// No sky sheen in the depression: that is what read as a pale disk.
		ROUGHNESS = 1.0;
		SPECULAR = 0.0;
#endif
	} else {
		// Broad contiguous flaking, varied per stripe, with shared tire paths.
		// Fine grain changes tone only; it does not punch checkerboard pinholes.
#ifdef CITY_CALIBRATED_FINISHES
		float peeling = soft_noise(position_world.xz * 2.65) * 0.80 + resolved_noise(position_world.xz, 1.0 / 7.0, footprint) * 0.20;
#else
		float peeling = soft_noise(position_world.xz * 2.65) * 0.80 + soft_noise(position_world.xz * 7.0) * 0.20;
#endif
		float lane = abs(fract(dot(position_world.xz, road_across) / 3.7) - 0.5) * 3.7;
		float tire = 1.0 - smoothstep(0.10, 0.28, abs(lane - 0.83));
		bool yellow_line = detail_kind > 0.5;
		float wear_threshold = yellow_line ? mix(0.12, 0.32, detail_seed) + tire * 0.10 : mix(0.20, 0.60, detail_seed) + tire * 0.15;
#ifdef CITY_CALIBRATED_FINISHES
		float ragged_edge = 0.87 + resolved_noise(position_world.xz, 1.0 / 11.0, footprint) * 0.12;
#else
		float ragged_edge = 0.87 + soft_noise(position_world.xz * 11.0) * 0.12;
#endif
		if (peeling < wear_threshold || max(abs(p.x), abs(p.y)) > ragged_edge) { discard; }
		float paint_tone = yellow_line ? 0.88 + grain * 0.06 : 0.54 + grain * 0.12;
		ALBEDO = pow(COLOR.rgb, vec3(2.2)) * paint_tone * (1.0 - tire * 0.22);
#ifdef CITY_CALIBRATED_FINISHES
		// Dry traffic paint is a dielectric with a soft sheen like the asphalt
		// beside it; rubber-filmed tire paths are flatter. Never wet-looking.
		ROUGHNESS = mix(0.78, 0.88, tire);
		SPECULAR = mix(0.40, 0.30, tire);
#endif
	}
#ifndef CITY_CALIBRATED_FINISHES
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
#endif
}
