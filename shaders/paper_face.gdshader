shader_type spatial;
render_mode unshaded, cull_disabled;
// One loose face part (an eye, a brow, the mouth, a tear) lying on a character's card.
//
// The part sits exactly on the card, so it cannot slide against the drawing
// when the camera is off to one side. To be drawn over the card it is pulled
// towards the eye along its own line of sight: that changes how deep it is and
// nothing about where it lands on screen.
//
// With `clip` on, the part is drawn only where the body drawing under it is
// bare skin: the colour of the drawing at `skin_at`. Hair, a hat, a bandana,
// a drawn mustache and the head outline all cut it off, so a raised brow goes
// under the bandana and a profile mouth stops at the edge of the face.
// paper_face.gd says where the part lies on the drawing: the drawing's UV at
// the part's top-left corner, and how far it moves across the part's width
// and down its height.

uniform sampler2D art : source_color, filter_linear_mipmap, repeat_disable;
uniform float toward = 0.012;          // metres nearer the eye than the card
uniform bool clip = false;
uniform sampler2D body : filter_linear, repeat_disable;   // the drawing this part lies on
uniform vec2 body_o = vec2(0.0);       // the drawing's UV under the part's top-left corner
uniform vec2 body_u = vec2(1.0, 0.0);  // how far the drawing's UV moves across the part
uniform vec2 body_v = vec2(0.0, 1.0);  // and down it
uniform vec2 skin_at = vec2(0.5);      // a point of the drawing that is bare skin, in its UV
uniform float skin_near = 0.16;        // how far from that colour still counts as skin

void vertex() {
	vec4 v = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	v.xyz -= normalize(v.xyz) * toward;
	POSITION = PROJECTION_MATRIX * v;
}

void fragment() {
	vec4 c = texture(art, UV);
	if (clip) {
		vec4 under = textureLod(body, body_o + UV.x * body_u + UV.y * body_v, 0.0);
		vec3 skin = textureLod(body, skin_at, 0.0).rgb;
		if (under.a < 0.5 || distance(under.rgb, skin) > skin_near) {
			discard;
		}
	}
	ALBEDO = c.rgb;
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}
