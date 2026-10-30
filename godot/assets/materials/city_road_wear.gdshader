shader_type spatial;
render_mode cull_disabled;
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
void vertex() {
	position_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	detail_kind = INSTANCE_CUSTOM.r;
	detail_seed = grit(MODEL_MATRIX[3].xz);
	road_across = normalize(MODEL_MATRIX[0].xz);
}
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float grain = soft_noise(position_world.xz * 31.0);
	if (detail_kind > 1.5) {
		float rim = length(p * vec2(1.0, 1.12));
		float edge = 0.71 + soft_noise(position_world.xz * 6.0) * 0.24;
		if (rim > edge) { discard; }
		// Dark aggregate and an uneven depression, never a pale painted disk.
		float bowl = mix(0.007, 0.043, smoothstep(0.32, edge, rim));
		float broken_aggregate = smoothstep(0.62, 0.80, rim) * step(0.72, grain) * 0.018;
		ALBEDO = vec3(bowl + broken_aggregate) * vec3(0.97, 0.98, 1.0) * (0.82 + grain * 0.24);
	} else {
		// Broad contiguous flaking, varied per stripe, with shared tire paths.
		// Fine grain changes tone only; it does not punch checkerboard pinholes.
		float peeling = soft_noise(position_world.xz * 2.65) * 0.80 + soft_noise(position_world.xz * 7.0) * 0.20;
		float lane = abs(fract(dot(position_world.xz, road_across) / 3.7) - 0.5) * 3.7;
		float tire = 1.0 - smoothstep(0.10, 0.28, abs(lane - 0.83));
		float wear_threshold = mix(0.20, 0.60, detail_seed) + tire * 0.15;
		float ragged_edge = 0.87 + soft_noise(position_world.xz * 11.0) * 0.12;
		if (peeling < wear_threshold || max(abs(p.x), abs(p.y)) > ragged_edge) { discard; }
		ALBEDO = pow(COLOR.rgb, vec3(2.2)) * (0.54 + grain * 0.12) * (1.0 - tire * 0.22);
	}
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
