// The end of an arm cut short (paper_card.gdshader's arm_l_cut and arm_r_cut), included there.
// Cut straight across it is where a fist takes over. With cut_round set, the end is rounded off as it
// shows on screen, like an elbow: pointed away from us, his upper arms go forward, seen end-on, and
// end there (paper_actor.gd _elbows_out).

uniform vec2 cut_round = vec2(0.0, 1.0);   // x: the round end's radius as it shows (0: cut straight across); y: how short the arm is drawn (its stretch)

// How far past the end a point of the arm is, as it shows (below zero: on the arm).
// `o` is the point from the shoulder as drawn, `axis` the way the arm runs as drawn.
float past_cut(vec2 o, vec2 axis, float cut) {
	if (cut_round.x <= 0.0) {
		return length(o) - cut;
	}
	float along = (dot(o, axis) - cut) * cut_round.y + cut_round.x;      // from the middle of the round end, as it shows
	float across = dot(o, vec2(axis.y, -axis.x));
	return along > 0.0 ? length(vec2(along, across)) - cut_round.x : along - cut_round.x;
}
