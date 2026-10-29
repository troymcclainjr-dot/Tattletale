// The clay look. Every clay_/gloss_/metal_ material in the game is this shader with its
// own color and roughness, so tuning the defaults here restyles the whole game at once.
// Surface detail is triplanar in OBJECT space, so thumbprints stick to moving puppets.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec4 albedo : source_color = vec4(0.5, 0.5, 0.5, 1.0);
uniform float roughness : hint_range(0.0, 1.0) = 0.86;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform float print_amount : hint_range(0.0, 2.0) = 1.0;  // thumbprint depth: clay 1, gloss ~0.3
uniform float mottle_amount : hint_range(0.0, 2.0) = 1.0; // color unevenness
uniform float print_scale = 2.2;                          // texture repeats per meter
uniform float normal_depth = 0.5;
uniform float sheen : hint_range(0.0, 1.0) = 0.22;        // soft rim light, reads as plasticine
uniform float sss : hint_range(0.0, 1.0) = 0.0;           // subsurface glow (skin)
uniform sampler2D clay_normal : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D clay_mottle : hint_default_white, filter_linear_mipmap, repeat_enable;

varying vec3 v_obj_pos;
varying vec3 v_obj_nrm;
varying vec3 v_nx;
varying vec3 v_ny;
varying vec3 v_nz;

void vertex() {
	v_obj_pos = VERTEX;
	v_obj_nrm = NORMAL;
	// object-space axes as view-space normal directions (handles non-uniform scale)
	v_nx = MODELVIEW_NORMAL_MATRIX * vec3(1.0, 0.0, 0.0);
	v_ny = MODELVIEW_NORMAL_MATRIX * vec3(0.0, 1.0, 0.0);
	v_nz = MODELVIEW_NORMAL_MATRIX * vec3(0.0, 0.0, 1.0);
}

vec3 tri_weights(vec3 n) {
	vec3 w = pow(abs(n), vec3(4.0));
	return w / (w.x + w.y + w.z + 1e-5);
}

vec3 unpack_nrm(vec4 t) {
	vec2 xy = t.xy * 2.0 - 1.0;
	return vec3(xy, sqrt(max(0.0, 1.0 - dot(xy, xy))));
}

void fragment() {
	vec3 p = v_obj_pos * print_scale;
	vec3 n = normalize(v_obj_nrm);
	vec3 w = tri_weights(n);

	float mott = texture(clay_mottle, p.zy).r * w.x + texture(clay_mottle, p.xz).r * w.y + texture(clay_mottle, p.xy).r * w.z;
	ALBEDO = albedo.rgb * mix(1.0, mott, mottle_amount);
	ROUGHNESS = roughness;
	METALLIC = metallic;

	// triplanar normal, whiteout blend (Golus)
	float k = normal_depth * print_amount;
	vec3 tx = unpack_nrm(texture(clay_normal, p.zy)); tx.xy *= k;
	vec3 ty = unpack_nrm(texture(clay_normal, p.xz)); ty.xy *= k;
	vec3 tz = unpack_nrm(texture(clay_normal, p.xy)); tz.xy *= k;
	tx = vec3(tx.xy + n.zy, abs(tx.z) * n.x);
	ty = vec3(ty.xy + n.xz, abs(ty.z) * n.y);
	tz = vec3(tz.xy + n.xy, abs(tz.z) * n.z);
	vec3 nobj = normalize(tx.zyx * w.x + ty.xzy * w.y + tz.xyz * w.z);
	NORMAL = normalize(nobj.x * v_nx + nobj.y * v_ny + nobj.z * v_nz);

	RIM = sheen;
	RIM_TINT = 0.6;
	SSS_STRENGTH = sss;
}
