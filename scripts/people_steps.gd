extends RefCounted
## --do steps for the people (combat_people.gd: the dead, the frightened who hide, the held up). main.gd's
## _take_shot hands these here:
##
##   hidecheck            a shot into the air in the room here with the most people in sight (hidecheck:here: where
##                        he stands); when they have all hidden (or 10 seconds have gone by) it prints where each one
##                        ended up and whether the shooter can see him there, and what hides him (anyone still going:
##                        where he is each half second for 3 seconds more, and what holds him up)
##   runcover[:name]      a shot (unless people are frightened already); the moment someone in sight is part-way to
##                        his hiding place everything stops and a picture is taken, from the camera's side of him
##   hidden[:name]        a shot (unless people are hiding already) and, once they have hidden, a picture of the
##                        one in sight nearest the shooter, the two of them in it
##   gunpoint[:name]      he goes up to the nearest person in sight and points his gun at him: a picture once his
##                        hands are up; then the cross goes off him and it prints what he does
##   deadrow[:name]       every character with the dead face, standing on three shelves (name.png) and lying as
##                        the dead lie, seen as the game sees them (name_lying.png), on a plain backdrop far above
##   deadcheck[:name]     everyone here put down at once (the dancers too); once they lie still a picture (if
##                        named) and two seconds of frames: does anything about any of them move?
##
## Pictures are saved beside the --shot file, as shot_steps.gd's snap does.

const PaperActor := preload("res://scripts/paper_actor.gd")
const PaperFace := preload("res://scripts/paper_face.gd")
const Cover := preload("res://scripts/people_cover.gd")
const SETTLE := 10.0             # seconds hidecheck waits for everyone to hide
const PARAMS := ["arm_l_angle", "arm_r_angle", "arm_l_curl", "arm_r_curl", "lift_l", "lift_r", "swing_l", "swing_r"]


static func step(main: Node, bits: PackedStringArray) -> void:
	var name := bits[1] if bits.size() > 1 and bits[1] != "" else bits[0]
	match bits[0]:
		"hidecheck":
			await _hidecheck(main, bits.size() > 1 and bits[1] == "here")
		"runcover":
			await _runcover(main, name)
		"hidden":
			await _hidden(main, name)
		"gunpoint":
			await _gunpoint(main, name)
		"deadrow":
			await _deadrow(main, name)
		"deadcheck":
			await _deadcheck(main, bits[1] if bits.size() > 1 else "")


static func _frames(main: Node, n: int) -> void:
	for i in n:
		await main.get_tree().process_frame


static func _called(p: RefCounted) -> String:
	var a: Node3D = p.actor
	return "%s (%s)" % [a.display_name if a.display_name != "" else String(a.name), a._who]


# ------------------------------------------------------------ a shot, and hiding

## Stand him in the middle of the room with the most people in sight.
static func _to_the_crowd(main: Node) -> void:
	var b: Node3D = main._building
	var count := {}
	for p: RefCounted in main._combat.people.living_here():
		var ri := Cover.room_of(b, Vector2(p.actor.position.x, p.actor.position.z))
		if ri >= 0:
			count[ri] = int(count.get(ri, 0)) + 1
	var best := -1
	for ri: int in count:
		if best < 0 or int(count[ri]) > int(count[best]):
			best = ri
	if best < 0:
		return
	var at: Vector3 = main._spot_in_room(String(b.rooms[best]["name"]))
	main._actor.position = at
	main._actor.areas = b.walk_areas()
	main._change_room(b.room_at_pos(at, main._room), true)
	await _frames(main, 6)


## A shot into the air beside him (as a warning shot); if the gun only clicks, the people are frightened all the same.
static func _shot(main: Node) -> void:
	var lead: Node3D = main._actor
	if lead.weapon == "":
		lead.weapon = "pistol"
	lead.aiming = true
	var cam: Camera3D = main._camera
	var right := Vector3(cam.global_transform.basis.x.x, 0.0, cam.global_transform.basis.x.z).normalized()
	var up_there: Vector3 = lead.global_position + right * 2.0 + Vector3(0.0, lead.height + 1.2, 0.0)
	for i in 24:
		main._aim_at(cam.unproject_position(up_there))
		await main.get_tree().process_frame
	var went: bool = main._combat.fire()
	main._aim_off()
	lead.aiming = false
	if not went:
		main._combat.people.alarm(lead.global_position)
	print("[shot] people: a shot %s at %.2f, %.2f in the %s" % ["fired" if went else "(the gun clicked: an alarm instead)",
			lead.position.x, lead.position.z, main._building.rooms[main._room]["name"]])


## Everyone frightened is hiding, cowering, held or down, and nobody is still looking for somewhere.
static func _settled(people: RefCounted) -> bool:
	for p: RefCounted in people.here():
		if p.taken and (p.state in ["alarmed", "fleeing", "returning"] or p.search != null):
			return false
	return true


static func _hidecheck(main: Node, here_only: bool) -> void:
	var people: RefCounted = main._combat.people
	if not here_only:
		await _to_the_crowd(main)
	var was := {}
	for p: RefCounted in people.here():
		was[p] = [Vector2(p.actor.position.x, p.actor.position.z), p.state, _room_name(main, p)]
	await _shot(main)
	var t := 0.0
	while t < SETTLE:
		await main.get_tree().process_frame
		t += 1.0 / 60.0
		if t > 1.5 and _settled(people):         # time enough for anyone hiding in his sight to see that he is
			break
	for i in 30:                                 # and down as low as they go
		var low := true
		for p: RefCounted in people.here():
			low = low and (p.state not in ["hiding", "cowering"] or p.crouch >= 1.0)
		if low:
			break
		await main.get_tree().process_frame
		t += 1.0 / 60.0
	var lead: Node3D = main._actor
	var b: Node3D = main._building
	var w: RefCounted = main._combat.world_for(b)
	var eye := Cover.eye_of(lead)
	var counts := {"hidden": 0, "cut": 0, "cower": 0, "cower_seen": 0, "running": 0, "seen": 0, "calm": 0, "dead": 0, "held": 0}
	for p: RefCounted in people.here():
		var a: Node3D = p.actor
		var now := Vector2(a.position.x, a.position.z)
		var then: Vector2 = was[p][0]
		var line := "[shot] hidecheck:   %s: %s, from %.2f, %.2f (%s) to %.2f, %.2f (%s), %.1f m" % [_called(p), p.state,
				then.x, then.y, was[p][2], now.x, now.y, _room_name(main, p), then.distance_to(now)]
		match p.state:
			"hiding", "cowering":
				var cut: bool = not a.is_visible_in_tree()
				var seen: bool = people._seen_now(p)
				var why := ""
				if cut:
					why = "out of his sight: in a part cut away from the camera"
				elif not seen:
					var hit: Dictionary = w.trace(eye, a.global_position + Vector3(0.0, people._tall(p) * 0.96, 0.0))
					var mi: Node = hit["mi"]
					why = "out of his sight, behind %s" % (("%s/%s" % [mi.get_parent().name, mi.name]) if mi else "?")
				else:
					why = "IN HIS SIGHT"
				line += ": " + why
				if p.state == "hiding" and p.spot != Vector2.INF:
					line += " (%.2f m from the spot tried)" % p.spot.distance_to(now)
					if seen and not cut:
						var spot: Vector2 = p.spot
						var to: Vector2 = (Vector2(lead.global_position.x, lead.global_position.z) - spot).normalized()
						var off: Vector2 = now - spot
						var tall: float = people._tall(p)
						line += " (%+.2f m towards him, %+.2f m across; the spot itself %s now)" % [off.dot(to), off.dot(Vector2(-to.y, to.x)),
								"in his sight" if Cover.seen(w, eye, spot, a.global_position.y, tall) else "hidden"]
				if p.running_off:
					line += " (nowhere hid him: he ran as far from him as he could)"
				if p.state == "hiding":
					counts["cut" if cut else ("seen" if seen else "hidden")] += 1
				else:
					counts["cower_seen" if seen else "cower"] += 1
			"alarmed", "fleeing", "returning":
				counts["running"] += 1
				var next := "-"
				if p.flee.at < p.flee.path.size():
					var point: Vector2 = p.flee.path[p.flee.at]
					next = "%.2f, %.2f, %.2f m on" % [point.x, point.y, point.distance_to(now)]
				line += ": STILL GOING (point %d of %d of his way to %s (next %s), %s, %d ways given up%s, card at %.0f, wanting %.0f degrees)" % [
						p.flee.at, p.flee.path.size(), "-" if p.spot == Vector2.INF else "%.2f, %.2f" % [p.spot.x, p.spot.y], next,
						"searching" if p.search != null else "not searching", p.tries, ", stuck" if p.flee.stuck else "",
						rad_to_deg(wrapf(a._yaw, -PI, PI)), rad_to_deg(wrapf(a._want_yaw, -PI, PI))]
			"calm":
				counts["calm"] += 1
				line += ": not frightened (%s)" % ("a foe" if p.foe else "too far from the shot" if a.global_position.distance_to(lead.global_position) > people.REACT else "?")
			"dead":
				counts["dead"] += 1
			"held":
				counts["held"] += 1
		if p.flee and p.state != "calm":
			line += "; searched %.1f ms, %d spots tried" % [float(p.spent) / 1000.0, int(p.looked)]
		print(line)
	var problems: int = counts["seen"] + counts["running"]
	print("[shot] hidecheck: %s: %d hidden out of his sight (%d of them in a part cut away), %d cowering out of his sight, %d cowering in his sight (nowhere to go), %d HIDING IN HIS SIGHT, %d STILL GOING, %d not frightened, %d held up, %d down, after %.1f s: %d problems" % [
			main._place, counts["hidden"] + counts["cut"], counts["cut"], counts["cower"], counts["cower_seen"], counts["seen"], counts["running"],
			counts["calm"], counts["held"], counts["dead"], t, problems])
	if counts["running"] > 0:
		await _follow(main, people)


## Anyone still going after SETTLE: where he is each half second for three seconds more, and what holds him up.
static func _follow(main: Node, people: RefCounted) -> void:
	for k in 6:
		for i in 30:
			await main.get_tree().process_frame
		for p: RefCounted in people.here():
			if not p.taken or p.state not in ["alarmed", "fleeing", "returning"]:
				continue
			var a: Node3D = p.actor
			var here := Vector2(a.position.x, a.position.z)
			var held := "-"
			if p.flee.at < p.flee.path.size():
				var point: Vector2 = p.flee.path[p.flee.at]
				held = _held_by(p, here + (point - here).normalized() * 0.06)
			print("[shot] hidecheck:     +%.1f s %s: %s at %.2f, %.2f, point %d of %d, card %.0f wanting %.0f, slow %.2f s; a step on: %s" % [
					0.5 * (k + 1), _called(p), p.state, here.x, here.y, p.flee.at, p.flee.path.size(), rad_to_deg(wrapf(a._yaw, -PI, PI)),
					rad_to_deg(wrapf(a._want_yaw, -PI, PI)), p.flee._slow, held])


## What stops him standing at `ahead`: the floor's end, a prop, someone, or nothing.
static func _held_by(p: RefCounted, ahead: Vector2) -> String:
	var a: Node3D = p.actor
	if not a._on_floor(ahead):
		return "off the floor"
	for prop: Rect2 in a.obstacles:
		var r: Rect2 = prop.grow_individual(a.reach, a.RADIUS, a.reach, a.RADIUS)
		if r.has_point(ahead):
			return "a prop grown to %.2f, %.2f .. %.2f, %.2f" % [r.position.x, r.position.y, r.end.x, r.end.y]
	for other: Node3D in a.others:
		var there := Vector2(other.position.x, other.position.z)
		if there.distance_to(ahead) < a.RADIUS * 2.0 and there.distance_to(ahead) < there.distance_to(Vector2(a.position.x, a.position.z)):
			return "someone at %.2f, %.2f" % [there.x, there.y]
	return "nothing"


static func _room_name(main: Node, p: RefCounted) -> String:
	var b: Node3D = main._building
	var ri := Cover.room_of(b, Vector2(p.actor.position.x, p.actor.position.z))
	return String(b.rooms[ri]["name"]) if ri >= 0 else "a doorway"


static func _runcover(main: Node, name: String) -> void:
	var people: RefCounted = main._combat.people
	var from := {}
	for p: RefCounted in people.here():
		from[p] = Vector2(p.actor.position.x, p.actor.position.z)
	var any := false
	for p: RefCounted in people.here():
		any = any or p.state in ["alarmed", "fleeing"]
	if not any:
		await _shot(main)
	var runner: RefCounted = null
	for i in 360:
		await main.get_tree().process_frame
		for p: RefCounted in people.living_here():
			if p.state != "fleeing" or p.flee == null or p.flee.path.is_empty() or p.flee.arrived:
				continue
			var a: Node3D = p.actor
			var gone: float = (from[p] as Vector2).distance_to(Vector2(a.position.x, a.position.z))
			var left: float = Vector2(a.position.x, a.position.z).distance_to(p.flee.path[p.flee.path.size() - 1])
			if gone > 0.8 and gone / (gone + left) > 0.35 and a._gait > 0.9:
				runner = p
				break
		if runner:
			break
	if runner == null:
		print("[shot] runcover: nobody in sight ran for cover")
		for p: RefCounted in people.here():
			print("[shot] runcover:   %s: %s, %d points of way, at %d, %s, %.1f m from where he was" % [_called(p), p.state,
					p.flee.path.size() if p.flee else 0, p.flee.at if p.flee else 0, "arrived" if p.flee and p.flee.arrived else "-",
					(from[p] as Vector2).distance_to(Vector2(p.actor.position.x, p.actor.position.z))])
		return
	var a: Node3D = runner.actor
	print("[shot] runcover: %s, running for %.2f, %.2f, at %.2f, %.2f, his card turned %.0f degrees%s" % [_called(runner),
			runner.spot.x, runner.spot.y, a.position.x, a.position.z, rad_to_deg(wrapf(a._yaw, -PI, PI)),
			" (his back)" if cos(a._yaw) < 0.0 else ""])
	await _picture_of(main, a.global_position, name)


static func _hidden(main: Node, name: String) -> void:
	var people: RefCounted = main._combat.people
	var any := false
	for p: RefCounted in people.here():
		any = any or p.state in ["hiding", "fleeing", "alarmed"]
	if not any:
		await _shot(main)
	var t := 0.0
	while t < SETTLE and not _settled(people):
		await main.get_tree().process_frame
		t += 1.0 / 60.0
	for i in 30:                        # everyone down as low as he goes (half crouched, he shows over what hides him)
		var low := true
		for p: RefCounted in people.here():
			low = low and (p.state not in ["hiding", "cowering"] or p.crouch >= 1.0)
		if low:
			break
		await main.get_tree().process_frame
	var lead: Node3D = main._actor
	var cam: Camera3D = main._camera
	var best: RefCounted = null
	var best_score := INF
	for p: RefCounted in people.living_here():
		if p.state == "hiding" and not people._seen_now(p):
			# The nearest one the camera has on screen first (someone through a wall in another room shows nothing).
			var on: bool = cam.is_position_in_frustum(p.actor.global_position + Vector3(0.0, 0.5, 0.0)) and Cover.room_of(main._building,
					Vector2(p.actor.position.x, p.actor.position.z)) == main._room
			var score: float = p.actor.global_position.distance_to(lead.global_position) + (0.0 if on else 100.0)
			if score < best_score:
				best_score = score
				best = p
	if best == null:
		print("[shot] hidden: nobody in sight of the camera is hiding")
		return
	var a: Node3D = best.actor
	for i in 30:                        # down as low as he goes
		if best.crouch >= 1.0:
			break
		await main.get_tree().process_frame
	print("[shot] hidden: %s at %.2f, %.2f, crouched %.2f, %.1f m from him" % [_called(best), a.position.x, a.position.z, best.crouch,
			a.global_position.distance_to(lead.global_position)])
	await _picture_of(main, (a.global_position + lead.global_position) * 0.5, name, a.global_position.distance_to(lead.global_position))


static func _gunpoint(main: Node, name: String) -> void:
	var people: RefCounted = main._combat.people
	var lead: Node3D = main._actor
	if lead.weapon == "":
		lead.weapon = "pistol"
	var near: RefCounted = null
	for p: RefCounted in people.living_here():
		if p.state == "calm" and not p.foe:
			if near == null or p.actor.global_position.distance_to(lead.global_position) < near.actor.global_position.distance_to(lead.global_position):
				near = p
	if near == null:
		print("[shot] gunpoint: nobody here to hold up")
		return
	if not await _beside(main, near):
		var held: RefCounted = await main._combat._stand_near(near, true)
		if held == null:
			print("[shot] gunpoint: %s cannot be pointed at from anywhere near" % _called(near))
			return
	lead.aiming = true
	var a: Node3D = near.actor
	for i in 40:
		main._aim_at(main._camera.unproject_position(a.global_position + Vector3(0.0, a.height * 0.6, 0.0)))
		await main.get_tree().process_frame
	print("[shot] gunpoint: %s, %.1f m from him: %s, hands up %.2f" % [_called(near), a.global_position.distance_to(lead.global_position), near.state, near.hands])
	await _picture(main, name, Vector3.ZERO, Vector3.ZERO)
	var off: Vector3 = a.global_position + Vector3(0.0, a.height + 2.5, 0.0)
	var t := 0.0
	while t < 2.0 and near.state == "held":
		main._aim_at(main._camera.unproject_position(off))
		await main.get_tree().process_frame
		t += 1.0 / 60.0
	print("[shot] gunpoint: the cross off him, %.2f s later he is %s" % [t, near.state])


## Stand him 2 to 4 m to one side of `p` across the screen (not between him and the camera, where the two flat
## figures would be one), in his room, with nothing between his eyes and p's chest. False if there is no such spot.
static func _beside(main: Node, p: RefCounted) -> bool:
	var lead: Node3D = main._actor
	var b: Node3D = main._building
	var at: Vector3 = p.actor.global_position
	var room: int = b.room_at_pos(at, 0)
	var right: Vector3 = main._camera.global_transform.basis.x
	var across := Vector2(right.x, right.z).normalized()
	var w: RefCounted = main._combat.world_for(b)
	var chest := at + Vector3(0.0, float(p.actor.height) * 0.6, 0.0)
	lead.areas = b.walk_areas()
	for r: float in [2.6, 3.2, 2.0, 3.8]:
		for side: float in [-1.0, 1.0]:
			for tilt: float in [0.0, 0.35, -0.35]:
				var s := Vector2(at.x, at.z) + across.rotated(tilt) * side * r
				if not lead.can_stand(s) or b.room_at_pos(Vector3(s.x, at.y, s.y), 0) != room:
					continue
				var eye := Vector3(s.x, at.y + float(lead.height) * Cover.EYE, s.y)
				if w and w.trace(eye, chest)["hit"]:
					continue
				main._teleport(Vector3(s.x, at.y, s.y), true)
				await _frames(main, 6)
				return true
	return false


# ------------------------------------------------------------ the dead

static func _deadrow(main: Node, name: String) -> void:
	var origin := Vector3(0, 700, 0)
	var grey := StandardMaterial3D.new()
	grey.albedo_color = Color(0.56, 0.6, 0.66)
	grey.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var floor_look := StandardMaterial3D.new()
	floor_look.albedo_color = Color(0.44, 0.47, 0.52)
	floor_look.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var made: Array = []
	Kit.box(main, Vector3(60, 30, 0.1), origin + Vector3(0, 0, -1.2), grey)
	for row in 3:
		Kit.box(main, Vector3(60, 0.1, 2.0), origin + Vector3(0, row * 2.1 - 0.05, 0), floor_look)
	var rigs := _rigs(main)
	for i in rigs.size():
		var who: Node3D = PaperActor.new()
		main.add_child(who)
		if not who.set_rig(main._rig_dir(rigs[i])) or who.face == null:
			who.queue_free()
			continue
		var row := 2 - i / 6
		who.position = origin + Vector3((float(i % 6) - 2.5) * 1.2, row * 2.1, 0.0)
		who.areas = [Rect2(-999, -999, 1998, 1998)]
		who.face.hold = true
		who.face.set_expression("dead", true)
		who.face.hold_mouth(String(PaperFace.HELD["dead"]["mouth"]))
		who.walk(Vector2.ZERO, Vector2.ZERO, 1.0 / 60.0)
		made.append(who)
	main._tag.visible = false
	main._hint.visible = false
	var mid := origin + Vector3(0.0, 3.1, 0.0)
	await _picture(main, name, mid + Vector3(0.0, 0.0, 17.0), mid, 30.0)
	# Lying as the dead lie, head to the right of the picture, seen as the follow camera sees the floor.
	for i in made.size():
		var who: Node3D = made[i]
		who.position = origin + Vector3((float(i % 4) - 1.5) * 2.3, 0.0, float(i / 4) * 1.0 - 2.0)
		who.fall_to = Vector3.RIGHT
		who.fallen = 1.0
		who.walk(Vector2.ZERO, Vector2.ZERO, 1.0 / 60.0)
	var look := origin + Vector3(0.75, 0.0, 0.0)          # the middle of them all (they lie head to the right)
	var away: Vector3 = main.FOLLOW_OFFSET.normalized()
	await _picture(main, name + "_lying", look + away * 8.0 + Vector3(0.0, 2.9, 0.0), look, 40.0)
	for who: Node3D in made:
		who.queue_free()
	print("[shot] deadrow: %d characters" % made.size())


## Every character folder with a rig and loose face parts.
static func _rigs(main: Node) -> Array:
	var out: Array = []
	var dir := DirAccess.open("res://assets/characters")
	if dir == null:
		return out
	for folder: String in dir.get_directories():
		if FileAccess.file_exists("res://assets/characters/%s/rig.json" % folder):
			out.append(folder)
	out.sort()
	return out


static func _deadcheck(main: Node, name: String) -> void:
	var people: RefCounted = main._combat.people
	var down: Array = []
	var danced := {}
	for p: RefCounted in people.here():
		if p.state != "dead":
			danced[p] = p.actor.performing
			people._die(p, Vector3(main._camera.global_transform.basis.x))
			down.append(p)
	await _frames(main, int((people.FALL + 0.3) * 60.0))
	if name != "":
		await _picture(main, name, Vector3.ZERO, Vector3.ZERO)
	var before := {}
	for p: RefCounted in down:
		before[p] = _pose_of(p.actor)
	var moved := {}
	for i in 120:
		await main.get_tree().process_frame
		for p: RefCounted in down:
			var now: Dictionary = _pose_of(p.actor)
			for key: String in now:
				if not moved.has(p) and str(now[key]) != str(before[p][key]):
					moved[p] = "%s: %s, then %s" % [key, str(before[p][key]), str(now[key])]
	var still := 0
	for p: RefCounted in down:
		var a: Node3D = p.actor
		var eyes := "-"
		if a.face:
			eyes = "%s/%s, mouth %s" % [a.face._nodes["eye_l"].get_meta("part", ""), a.face._nodes["eye_r"].get_meta("part", ""), a.face.shown_mouth()]
		if moved.has(p):
			print("[shot] deadcheck:   %s%s: MOVED (%s)" % [_called(p), " (was dancing)" if danced[p] else "", moved[p]])
		else:
			still += 1
			print("[shot] deadcheck:   %s%s: still; eyes %s" % [_called(p), " (was dancing)" if danced[p] else "", eyes])
	print("[shot] deadcheck: %s: %d down, %d still, %d MOVED" % [main._place, down.size(), still, down.size() - still])


## Everything about someone that could move, as it is now.
static func _pose_of(a: Node3D) -> Dictionary:
	var out := {
		"pivot": a._pivot.global_transform, "card": a._card.transform, "over": a._over.visible, "held": a._held.visible,
		"view": a.view, "yaw": snappedf(a._yaw, 0.0001), "groove": a._groove, "gait": a._gait,
	}
	for param: String in PARAMS:
		out[param] = a._mat.get_shader_parameter(param)
	if a.face:
		out["face"] = a.face.visible
		out["expression"] = a.face.expression
		for slot: String in a.face._nodes:
			var node: MeshInstance3D = a.face._nodes[slot]
			out["face " + slot] = [node.get_meta("part", ""), node.visible, node.transform]
	return out


# ------------------------------------------------------------ pictures

## A picture of `at` from the camera's side of it, as the follow camera would frame someone standing there (or
## further back, to take in `wide` metres).
static func _picture_of(main: Node, at: Vector3, name: String, wide := 0.0) -> void:
	var room: Dictionary = main._building.rooms[maxi(main._building.room_at_pos(at, main._room), 0)]
	var back: Vector3 = main.FOLLOW_OFFSET * float(room["cam_near"]) * (1.0 + wide * 0.12)
	var look := at + Vector3(0.0, float(room["look_y"]), 0.0)
	await _picture(main, name, Vector3(at.x + back.x, at.y + float(room["cam_y"]) + wide * 0.2, at.z + back.z), look, 40.0)


## Everything stops; a picture from `eye` looking at `look` (or from the camera following him, with both ZERO);
## then everything goes on.
static func _picture(main: Node, name: String, eye: Vector3, look: Vector3, fov := 40.0) -> void:
	main.set_process(false)
	main._fade.color.a = 0.0
	main._change_room(main._building.room_at_pos(main._actor.position, main._room), true)
	if eye == Vector3.ZERO and look == Vector3.ZERO:
		main._follow(0.0, true)
	else:
		main._camera.fov = fov
		main._camera.look_at_from_position(eye, look)
		main._face_cards()
	main._show_doors()
	for i in 12:
		await main.get_tree().process_frame
	await RenderingServer.frame_post_draw
	main._save_frame(String(main._shot_path).get_base_dir().path_join(name + ".png"))
	main.set_process(true)
