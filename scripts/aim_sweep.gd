extends RefCounted
## --do=aimsweep:seconds (screenshot mode, main.gd): does he flicker between side-on and his back as the
## cross goes over the edge between them? The red cross is held level beside him until he is side-on,
## then goes round him to nearly straight above him and back down, then wavers to and fro over the edge he
## turns his back at, many times. It prints each time he changed the way he points it and his drawing:
## once going up, once coming down and once in the wavering is right (3 and 3); more is a flicker.
## main.gd's _aim_at keeps the edge a little sticky: he turns his back past AIM_SIDE + 0.1 and turns
## side-on again only under AIM_SIDE - 0.1.

const RADIUS := 300.0        # pixels from his chest, on the screen
const TOP := 1.45            # radians above level the cross goes to
const WAVER := 0.08          # radians: it wavers this far each way over the edge he turns his back at
const WAVERS := 8            # ...this many times
const SETTLE := 0.6          # seconds the cross is held level first, for him to turn side-on


static func run(main: Node, actor: Node3D, camera: Camera3D, side: float, seconds: float) -> void:
	var frames := maxi(int(seconds * 60.0), 4)
	var settle := int(SETTLE * 60.0)
	var way := ""
	var view := ""
	var ways := PackedStringArray()
	var views := PackedStringArray()
	for i in settle + frames * 3:
		var t := float(i - settle) / float(frames)
		var rise := 0.0
		if t >= 0.0:
			rise = lerpf(0.0, TOP, t) if t < 1.0 else (lerpf(TOP, 0.0, t - 1.0) if t < 2.0 else side + 0.1 + WAVER * sin((t - 2.0) * TAU * WAVERS))
		var from := camera.unproject_position(actor.global_position + Vector3(0.0, actor.height * 0.55, 0.0))
		main._aim_at(from + Vector2(cos(rise), -sin(rise)) * RADIUS)
		await main.get_tree().process_frame
		if i < settle:
			way = String(actor.aim_way)
			view = String(actor.view)
			continue
		if String(actor.aim_way) != way:
			way = String(actor.aim_way)
			ways.append("%s at %.2f" % ["side-on" if way == "" else way, rise])
		if String(actor.view) != view:
			view = String(actor.view)
			views.append("%s at %.2f" % [view, rise])
	print("[shot] aimsweep: he changed the way he points %d times (%s) and his drawing %d times (%s); 3 and 3 is right" % [ways.size(), ", ".join(ways), views.size(), ", ".join(views)])
