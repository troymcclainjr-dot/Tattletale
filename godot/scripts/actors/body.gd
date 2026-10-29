class_name Body
extends RefCounted
## Something people can't walk through (movement.js addBody): radius, where it is, whether it's there.

var r := 0.3
var pos: Callable      # -> Vector3 (x, 0, z)
var on: Callable       # -> bool


static func make(pr: float, ppos: Callable, pon: Callable) -> Body:
	var b := Body.new()
	b.r = pr
	b.pos = ppos
	b.on = pon
	return b
