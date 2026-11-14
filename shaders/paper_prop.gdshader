shader_type spatial;
render_mode unshaded, cull_disabled;
// Something a paper character holds (a pistol, a rifle), or the fist that
// holds it: a flat drawing laid on his card. Like a face part it lies exactly
// on the card and is pulled towards the eye along its own line of sight, so it
// is drawn over him without sliding against him when the camera is off to one
// side. `toward` below zero pushes it behind him instead (seen from the back,
// what he holds is in front of his body).
//
// The fists are drawn white with black lines; `tint` paints them the skin of
// whoever holds them.

uniform sampler2D art : source_color, filter_linear_mipmap, repeat_disable;
uniform vec3 tint : source_color = vec3(1.0);
uniform float toward = 0.03;           // metres nearer the eye than the card

void vertex() {
	vec4 v = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	v.xyz -= normalize(v.xyz) * toward;
	POSITION = PROJECTION_MATRIX * v;
}

void fragment() {
	vec4 c = texture(art, UV);
	ALBEDO = c.rgb * tint;
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}
