extends RefCounted
## The camera of a HARD music video (video.json's "style"): instead of one wide
## shot on Large Fry's shoulder, it cuts between set-ups on the bar lines.
## video_take.gd asks `setup_for(bar)` which one each bar gets and `place` puts
## the camera there each frame.
##
##   master    the crew master: from Large Fry's lens at chest height, wide
##             enough for the people behind him
##   low       a low wide close-up of him from waist height, looking up
##   face      a tighter shot of his face, from eye height
##   shoulder  past the shoulder of whoever stands nearest the camera, off to
##             one side (only if somebody does)
##   high      a brief high view of the whole gathering (one bar at most)
##
## Flat people: no orbits. Inside a set-up the camera only slides a little
## sideways over the bar. The cards turn to face whichever camera is on (as
## they always do), so no set-up looks at anyone from behind.
##
## Which set-up a bar gets: the first two bars of the song are the master;
## a bar with a hold prompt in it is the face (stillness rewarded); a bar near
## a mishap is the master (so the trouble is seen); otherwise the section's own
## order (VERSE, HOOK), never the same set-up three bars running, never the high
## view two bars running.

const Crew := preload("res://scripts/video_crew.gd")
const ORDER := {
	"VERSE": ["low", "low", "master", "face", "shoulder", "master", "face", "high", "low", "master", "shoulder", "face"],
	"HOOK": ["low", "shoulder", "face", "master", "low", "high", "face", "master"],
	"": ["master"],
}
const SLIDE := {"master": 0.3, "low": 0.22, "face": 0.12, "shoulder": 0.18, "high": 0.6}     # metres sideways over a bar
const FOV := {"master": 44.0, "low": 66.0, "face": 32.0, "shoulder": 42.0, "high": 46.0}

var force := ""                  # a --do step's set-up, held whatever the bar (video:cut)
var _plan := {}                  # bar: the set-up it gets
var _shoulder: Node3D            # who the shoulder set-up looks past
var _dodged := {}                # "bar:set-up": how far sideways its eye goes to see round a post (worked out once a bar)


## Work out every bar's set-up. `sections`: [{"name", "pattern"}], `count_in`
## beats before the song; `holds`: the beats of the hold prompts; `mishaps`: the
## take's ({"start", "close"}); `crew`: the stage's people (paper actors);
## `stage`: video_stage.gd.
func plan(stage: Node3D, sections: Array, count_in: float, holds: Array, mishaps: Array, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 17 + 3
	_shoulder = _shoulder_for(stage)
	var at := count_in
	var bar := 0
	var last := ""
	var run := 0
	for s: Dictionary in sections:
		var name := String(s["name"])
		var order: Array = ORDER.get(name, ORDER[""])
		var k := rng.randi() % order.size()
		var bars := int(ceil(String(s["pattern"]).length() / 4.0))
		for j in bars:
			var from := at + j * 4.0
			var want := String(order[k % order.size()])
			k += 1
			if bar < 2:
				want = "master"
			elif _has_hold(holds, from):
				want = "face"
			elif _near_mishap(mishaps, from):
				want = "master"
			if want == "shoulder" and _shoulder == null:
				want = "low"
			if stage.crew.is_empty() and want in ["shoulder", "high"]:
				want = "face" if last != "face" else "low"
			if want == "high" and last == "high":
				want = "master"
			if want == last:
				run += 1
				if run >= 2:
					want = "master" if last != "master" else "low"
					run = 0
			else:
				run = 0
			_plan[bar] = want
			last = want
			bar += 1
		at += String(s["pattern"]).length()


## The set-up for bar `n` (bars counted from ACTION; the outro and anything past the plan: master).
func setup_for(n: int) -> String:
	if force != "":
		return force
	return String(_plan.get(n, "master"))


func _has_hold(holds: Array, from: float) -> bool:
	for b: float in holds:
		if b >= from - 0.2 and b < from + 3.8:
			return true
	return false


## Is a mishap asking for E during this bar (from its coming on, so what it is
## can be seen)? Only the bars it is on, so the cuts carry on round it.
func _near_mishap(mishaps: Array, from: float) -> bool:
	for m: Dictionary in mishaps:
		if from + 4.0 > float(m["open"]) - 0.5 and from < float(m["close"]):
			return true
	return false


## Whose shoulder the shoulder set-up looks past: of the crew standing nearer
## the lens than he is and off to one side, the nearest the lens whose set-up
## sees his mark with no thin prop, car or other person in the way; or null
## (then there is no shoulder set-up).
static func _shoulder_for(stage: Node3D) -> Node3D:
	var lens := Vector2(stage.lens.x, stage.lens.z)
	var him := Vector2(stage.mark.x, stage.mark.z)
	var deep := (him - lens).normalized()
	var front: Array = []
	for npc: Node3D in stage.crew:
		var p := Vector2(npc.position.x, npc.position.z)
		if (p - him).dot(deep) < -0.5 and absf((p - him).dot(Vector2(-deep.y, deep.x))) > 0.9:
			front.append(npc)
	front.sort_custom(func(a: Node3D, b: Node3D) -> bool:
		return (Vector2(a.position.x, a.position.z) - him).dot(deep) < (Vector2(b.position.x, b.position.z) - him).dot(deep))
	for npc: Node3D in front:
		var eye: Vector3 = shoulder_eye(npc, stage.mark)[0]
		var from := Vector2(eye.x, eye.z)
		var through := "" if Crew.clear_sight(stage, from, him) else "a post or a car"
		for other: Node3D in stage.crew:
			var q := Vector2(other.position.x, other.position.z)
			if other != npc and through == "" and Geometry2D.get_closest_point_to_segment(q, from, him).distance_to(q) < 0.5:
				through = String(other.name)
		if through == "":
			return npc
		print("[shot] video: the shoulder set-up past %s would look through %s" % [npc.name, through])
	return null


## Put `cam` where set-up `name` has it, `u` (0 .. 1) of the way through its bar.
## `aim` is where Large Fry is pointing now and `goal` where he is panning to
## (x along his line; he walks to keep in it); `lead` is him.
func place(cam: Camera3D, name: String, u: float, stage: Node3D, lead: Node3D, aim: Vector3, bar := -1, goal := Vector3.INF) -> void:
	var lens := Vector3(stage.lens.x, 0.0, stage.lens.z)
	var deep := Vector3(stage.mark.x, 0.0, stage.mark.z) - lens
	deep = deep.normalized()
	var right := Vector3(-deep.z, 0.0, deep.x)
	var slide := right * float(SLIDE.get(name, 0.2)) * (u - 0.5)
	# The close set-ups keep him in the picture: they look half way between where Large Fry wants him and where he is.
	var him := Vector3(lead.position.x, 0.0, lead.position.z)
	var near := him.lerp(Vector3(aim.x, 0.0, aim.z), 0.5)
	var going := Vector3(goal.x, 0.0, goal.z) if goal != Vector3.INF else Vector3(aim.x, 0.0, aim.z)
	var eye := Vector3.ZERO
	var look := Vector3.ZERO
	match name:
		"low":
			var off := -deep * 1.95 + right * 0.3
			eye = near + off + right * _dodge(stage, bar, name, [[near + off, him], [going + off, going]], right) + Vector3(0.0, 0.55, 0.0)
			look = near + Vector3(0.0, 1.22, 0.0)
		"face":              # head and chest, his face above the middle (clear of the lane of prompts)
			var off := -deep * 2.4 + right * 0.12
			eye = near + off + right * _dodge(stage, bar, name, [[near + off, him], [going + off, going]], right) + Vector3(0.0, float(lead.height) * 0.74, 0.0)
			look = near + Vector3(0.0, float(lead.height) * 0.62, 0.0)
		"shoulder":
			if _shoulder and is_instance_valid(_shoulder):
				var eye_look := shoulder_eye(_shoulder, near)
				eye = eye_look[0]
				look = eye_look[1]
			else:
				eye = lens + Vector3(0.0, 1.25, 0.0)
				look = Vector3(aim.x, 1.0, aim.z)
		"high":
			eye = Vector3(aim.x, 0.0, aim.z) - deep * 4.6 + right * 1.1 + Vector3(0.0, 4.4, 0.0)
			look = Vector3(aim.x, 0.2, aim.z) + deep * 1.0
		_:      # master: from where Large Fry stands, at chest height
			eye = lens + Vector3(0.0, 1.25, 0.0)
			look = Vector3(aim.x, 1.0, aim.z) + deep * 0.7
	cam.fov = float(FOV.get(name, 44.0))
	cam.look_at_from_position(eye + slide, look + slide * 0.5)


## The shoulder set-up's eye and where it looks: a metre and a half behind `by`
## (the crew member nearest the camera) and well out to his far side from him,
## looking a little to that side of him, so `by` fills one edge of the picture
## (cut by it) and he (at `near`) is in the middle, clear of `by`.
static func shoulder_eye(by_npc: Node3D, near: Vector3) -> Array:
	var by := Vector3(by_npc.position.x, 0.0, by_npc.position.z)
	var to := (near - by).normalized()
	var out := Vector3(-to.z, 0.0, to.x)
	if out.dot(by - near) < 0.0:
		out = -out
	return [by - to * 1.5 + out * 1.15 + Vector3(0.0, 1.3, 0.0), near + out * 0.25 + Vector3(0.0, 1.05, 0.0)]


## How far sideways (metres, along `right`) a close set-up's eye moves so that
## no post, pole or car stands between it and him, both where he is and where
## Large Fry is panning to (`pairs`: [eye, him] for each, on the floor): worked
## out at the start of each bar it is on, then kept for the bar (no jumps inside
## a bar).
func _dodge(stage: Node3D, bar: int, name: String, pairs: Array, right: Vector3) -> float:
	var key := "%d:%s" % [bar, name]
	if bar >= 0 and _dodged.has(key):
		return float(_dodged[key])
	var best := 0.0
	for d: float in [0.0, 0.45, -0.45, 0.9, -0.9, 1.35, -1.35]:
		var clear := true
		for pair: Array in pairs:
			var at: Vector3 = pair[0] + right * d
			var from := Vector2(at.x, at.z)
			for side: float in [0.0, -0.32, 0.32]:          # his middle and both sides: a post near the eye hides more of him than a line would
				var to: Vector3 = pair[1] + right * side
				clear = clear and Crew.clear_sight(stage, from, Vector2(to.x, to.z), 0.15)
			for npc: Node3D in stage.crew:                   # and not inside one of the crew
				clear = clear and from.distance_to(Vector2(npc.position.x, npc.position.z)) > 0.6
		if clear:
			best = d
			break
	if bar >= 0:
		_dodged[key] = best
	return best
