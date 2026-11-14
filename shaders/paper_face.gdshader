shader_type spatial;
render_mode unshaded, cull_disabled;
// One loose face part (an eye, a brow, the mouth) lying on a character's card.
//
// The part sits exactly on the card, so it cannot slide against the drawing
// when the camera is off to one side. To be drawn over the card it is pulled
// towards the eye along its own line of sight: that changes how deep it is and
// nothing about where it lands on screen.

//
// A part made for the edge of the face (a profile mouth) runs under the head
// outline. With `clip` on it is drawn only where the body drawing under it is
// not ink and not empty, so the outline cuts it off and nothing pokes out.

uniform sampler2D art : source_color, filter_linear_mipmap, repeat_disable;
uniform float toward = 0.012;          // metres nearer the eye than the card
uniform bool clip = false;
uniform sampler2D body : filter_linear_mipmap, repeat_disable;   // the drawing this part lies on
uniform vec4 body_rect = vec4(0.0, 0.0, 1.0, 1.0);               // where the part is on it: x, y, w, h in the drawing's UV
uniform float ink_level = 0.14;        // darker than this in every channel is the outline

void vertex() {
	vec4 v = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	v.xyz -= normalize(v.xyz) * toward;
	POSITION = PROJECTION_MATRIX * v;
}

void fragment() {
	vec4 c = texture(art, UV);
	if (clip) {
		vec4 under = texture(body, body_rect.xy + UV * body_rect.zw);
		if (under.a < 0.5 || max(under.r, max(under.g, under.b)) < ink_level) {
			discard;
		}
	}
	ALBEDO = c.rgb;
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}
