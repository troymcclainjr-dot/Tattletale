extends RefCounted
## People who are shot, and the people round them (combat.gd hands shots on to this).
##
## A person hit flinches and pulls a hurt face; with no health left he drops where he stands: his card goes
## over and lies flat on the floor, face up, his eyes crossed out and his tongue out (paper_face.gd's HELD "dead"),
## and a pool of blood spreads from under him and stays. Nothing about the dead moves: they do not walk, dance,
## blink, talk or stand in anyone's way, and nothing is left in their hands to twitch (_still).
##
## Everyone near a shot is frightened: they turn to the shooter with a scared face, then each runs for a hiding
## place out of his sight (people_cover.gd finds one from the place itself; people_flee.gd runs him there, facing
## the way he goes, round props and round each other, opening a shut door on the way) and crouches there. If the shooter comes round to where he
## can see someone hiding (for SEEN_FOR), that one runs for another place; a hiding place is never shared. Stopped
## on his way by people in it, he gets down where he is if the shooter cannot see him there, or goes round them. With
## nowhere to hide he runs as far from the shooter as he can get and cowers there (looking again every RETRY
## seconds); with nowhere to run either, he cowers where he is. With no shot for CALM seconds and no gun pointed, they walk back to
## where they were and go on with what they were doing; when he leaves a place, those who ran are back in their
## places at once.
##
## Held at gunpoint: while he points a gun at someone close (HOLD_RANGE), in clear sight, who has not run yet,
## with the red cross on him or near him (HOLD_NEAR pixels; pointing with Ctrl, which has no cross, the barrel
## within HOLD_CONE of him), that one freezes with his hands up (someone with no arms drawn shrinks instead). When
## the cross has been off him for RELEASE seconds, or a shot goes off, he runs for a hiding place.
##
## Someone `foe` (armed and shooting back: combat_foes.gd drives him) is not frightened, held or hidden here;
## dead, he is dead like anyone.
##
## Placeholder rule: the dead stay dead (in the save, in the player state's flags) until he next sleeps.

const PaperActor := preload("res://scripts/paper_actor.gd")
const PaperFace := preload("res://scripts/paper_face.gd")
const Cover := preload("res://scripts/people_cover.gd")
const FleeBrain := preload("res://scripts/people_flee.gd")
const PeopleBack := preload("res://scripts/people_back.gd")
const HEALTH := 100              # a person's, placeholder
const REACT := 18.0              # metres: people this near a shot are frightened by it
const CALM := 12.0               # seconds with no shot (and no gun pointed) before the frightened go back to what they were doing
const FALL := 0.55               # seconds to go down
const POOL_SECONDS := 4.0        # for the pool to spread
const POOL_RADIUS := 0.95        # metres, about (the ring is 0.8 of it, wobbling): it shows round someone the size of the lead
const HURT_FACE := 0.6           # seconds of the hurt face before the scared one
const CROUCH_TIME := 0.25        # seconds to crouch down, or stand up
const LOOK_EVERY := 0.25         # seconds between looks from a hiding place: can the shooter see him there?
const SEEN_FOR := 0.9            # seconds in the shooter's sight before someone hiding runs for another place
const RETRY := 2.0               # seconds between tries to find a hiding place, cowering in the shooter's sight
const TRIES := 3                 # ways that come to nothing (someone in the way) before he cowers where he is
const CROWD := 1.0               # metres: held up on his way, his next way goes round whoever is this near him
const HOLD_RANGE := 6.5          # metres: he holds up people this near at gunpoint
const HOLD_NEAR := 60.0          # pixels: the red cross this near someone's drawing is on him
const HOLD_CONE := 0.2           # radians: pointing with no cross (Ctrl), the barrel this near the line to someone
const RELEASE := 0.4             # seconds of the cross off him before someone held up runs
const HANDS_TIME := 0.2          # seconds to get his hands up, or down


class Person:
	var actor: Node3D
	var member: Dictionary
	var place := ""
	var index := 0
	var health := HEALTH
	var state := "calm"          # "calm", "alarmed", "held", "fleeing", "hiding", "cowering", "returning", "dead"
	var wait := 0.0
	var quiet := 0.0
	var taken := false
	var brain_was: Variant = null
	var areas_was: Array = []
	var others_was: Array = []
	var obstacles_was: Array = []
	var face_was := "neutral"
	var reach_was := 1.6
	var performing_was := false
	var parent_was: Node         # the node he stood in (a band of the place): back into it when he is calm
	var home := Vector3.ZERO
	var hurt_t := 0.0
	var fall_t := -1.0
	var pool: MeshInstance3D
	var flee                     # his people_flee.gd while he is frightened
	var foe := false             # armed and shooting back (combat_foes.gd drives him): a shot does not frighten him
	var crouch := 0.0            # 0 standing .. 1 crouched as low as he goes (people_flee.gd draws it)
	var hands := 0.0             # 0 .. 1 his hands up
	var search: RefCounted       # people_cover.gd's Search while he looks for somewhere to go
	var spot := Vector2.INF      # the hiding place he has taken: nobody else hides this near it
	var running_off := false     # nowhere hides him: he runs as far from the lead as he can, and cowers there
	var avoid: Array = []        # hiding places he has been found in, this fright
	var in_sight := false        # hiding: the shooter could see him, the last time he looked
	var seen_t := 0.0
	var look_t := 0.0
	var retry_t := 0.0
	var off_t := 0.0             # held up: seconds the cross has been off him
	var tries := 0
	var spent := 0               # microseconds his searches have taken, this fright (for hidecheck)
	var looked := 0              # spots he has looked at from the shooter's eyes, this fright


var main: Node
var fx: Node3D
var world_of: Callable           # place node -> combat_world.gd for it
var _people := {}                # "place:index": Person
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	_rng.seed = 23


## The person for main.gd's cast entry `index` at `place`.
func _person(place: String, index: int) -> Person:
	var key := "%s:%d" % [place, index]
	if not _people.has(key):
		var p := Person.new()
		var member: Dictionary = main._cast[place][index]
		p.member = member
		p.actor = member["actor"]
		p.place = place
		p.index = index
		p.home = p.actor.position
		p.reach_was = p.actor.use_reach
		_people[key] = p
	return _people[key]


## Everyone at the place he is at, alive or not.
func here() -> Array:
	var out: Array = []
	var cast: Array = main._cast.get(main._place, [])
	for i in cast.size():
		out.append(_person(main._place, i))
	return out


func living_here() -> Array:
	var out: Array = []
	for p: Person in here():
		if p.state != "dead" and p.actor.is_visible_in_tree():
			out.append(p)
	return out


## How tall someone is now: crouched, less.
func _tall(p: Person) -> float:
	return float(p.actor.height) * lerpf(1.0, FleeBrain.crouched(p.actor), p.crouch)


## Whoever's drawing is under a ray from the camera (the cross): {"person", "dist", "point"}, or {}.
func pick(from: Vector3, dir: Vector3) -> Dictionary:
	var best := {}
	var near := INF
	for p: Person in living_here():
		var a := p.actor
		var n: Vector3 = a.global_transform.basis.z
		var across: Vector3 = a.global_transform.basis.x
		var facing := dir.dot(n)
		if absf(facing) < 1e-4:
			continue
		var t := (a.global_position - from).dot(n) / facing
		if t <= 0.0 or t > near:
			continue
		var on := from + dir * t
		var u := (on - a.global_position).dot(across)
		var v := on.y - a.global_position.y
		var h := _tall(p)
		var wide: float = a.reach / 0.4
		var half := (0.13 if v > h * 0.82 else (0.25 if v > h * 0.45 else 0.17)) * wide
		if v < 0.0 or v > h * 1.02 or absf(u) > half:
			continue
		near = t
		best = {"person": p, "dist": t, "point": on}
	return best


## The first person a shot from `from` to `to` goes into: {"person", "t" (0..1 along it), "point"}, or {}.
func along(from: Vector3, to: Vector3) -> Dictionary:
	var best := {}
	var first := INF
	var d := to - from
	var flat := Vector2(d.x, d.z)
	var len2 := flat.length_squared()
	if len2 < 1e-8:
		return best
	var f := Vector2(from.x, from.z)
	for p: Person in living_here():
		var a := p.actor
		var c := Vector2(a.global_position.x, a.global_position.z)
		var r: float = 0.24 * a.reach / 0.4
		var t := clampf((c - f).dot(flat) / len2, 0.0, 1.0)
		var gap := (f + flat * t).distance_squared_to(c)
		if gap > r * r:
			continue
		var t0 := maxf(t - sqrt(r * r - gap) / sqrt(len2), 0.0)
		var y := from.y + d.y * t0
		var y1 := from.y + d.y * t
		var foot: float = a.global_position.y
		var top := foot + _tall(p)
		if (y < foot or y > top) and (y1 < foot or y1 > top):
			continue
		if t0 < first:
			first = t0
			best = {"person": p, "t": t0, "point": from + d * t0}
	return best


# ------------------------------------------------------------ shot, frightened

## Someone is hit by a shot going `dir` at `point`, for `damage`. Returns "down" if that was the end of him.
func hit(p: Person, point: Vector3, dir: Vector3, damage: int) -> String:
	if p.state == "dead":
		return "dead"
	p.health -= damage
	var a := p.actor
	var eye: Basis = main._camera.global_transform.basis
	var plane := point - a.global_transform.basis.z * (point - a.global_position).dot(a.global_transform.basis.z)
	fx.blood(plane + (main._camera.global_position - plane).normalized() * 0.06, dir, a.global_position.y, _node_for(a.global_position))
	if p.health <= 0:
		_die(p, dir)
		return "down"
	a.flinch = -0.2 * signf(dir.dot(eye.x))      # he jerks away from the shot, across the screen
	p.hurt_t = HURT_FACE
	if a.face:
		a.face.set_expression("hurt", true)
	if p.state in ["hiding", "cowering"] and not p.foe:
		p.quiet = 0.0
		_run(p, true)                            # found: he runs for somewhere else
	else:
		_frighten(p, main._actor.global_position)
	return "hit"


## A shot was fired from `at`: everyone near it is frightened (those out of sight in a part of the place the camera
## has cut away too: they hear it).
func alarm(at: Vector3) -> void:
	for p: Person in here():
		if p.state != "dead" and p.actor.global_position.distance_to(at) <= REACT:
			_frighten(p, at)


func _frighten(p: Person, at: Vector3) -> void:
	p.quiet = 0.0
	if p.foe:
		return
	match p.state:
		"calm":
			_take_over(p)
			p.state = "alarmed"
			p.wait = _rng.randf_range(0.15, 0.45)
			_look_at(p, at)
			if p.actor.face and p.hurt_t <= 0.0:
				p.actor.face.set_expression("scared", true)
		"held", "returning":
			_run(p)


## He turns to look at `at` (as far as he can turn) and his eyes go that way.
func _look_at(p: Person, at: Vector3) -> void:
	var a := p.actor
	var way := Vector2(at.x - a.global_position.x, at.z - a.global_position.z)
	var across: float = main._screen_dir(way).x
	if PeopleBack.turns(a):
		p.flee.look_way = way
	else:
		a.face_side(across)
	if a.face:
		a.face.look(signf(across) * (1.0 if not a._views.has("side") else 0.0))


## From now on this person is moved by people_flee.gd, not by what moved him before (put back by _let_go).
func _take_over(p: Person) -> void:
	if p.taken:
		return
	p.taken = true
	var a := p.actor
	a.use_reach = -1.0                    # frightened: nobody to talk to till he calms down
	p.brain_was = p.member["brain"]
	p.areas_was = a.areas.duplicate()
	p.others_was = a.others.duplicate()
	p.obstacles_was = a.obstacles
	p.face_was = a.face.expression if a.face else "neutral"
	p.performing_was = a.performing
	p.parent_was = a.get_parent()
	a.performing = false                  # the dancing stops
	p.avoid = []
	p.tries = 0
	p.spent = 0
	p.looked = 0
	var brain := FleeBrain.new()
	brain.person = p
	brain.main = main
	brain.hidden_at = _hidden_there
	p.flee = brain
	p.member["brain"] = brain


## Back to what he was doing.
func _let_go(p: Person) -> void:
	if not p.taken:
		return
	p.taken = false
	var a := p.actor
	p.member["brain"] = p.brain_was
	p.search = null
	p.spot = Vector2.INF
	p.running_off = false
	p.crouch = 0.0
	p.hands = 0.0
	a.use_reach = p.reach_was
	a.areas = p.areas_was
	a.others = p.others_was
	a.obstacles = p.obstacles_was
	a.sprinting = false
	a.cower = 0.0
	a.flinch = 0.0
	if not a._pivot.top_level:
		a._pivot.scale = Vector3.ONE          # people_flee.gd's crouch
	a.performing = p.performing_was
	PeopleBack.front_again(a)
	a._yaw = wrapf(a._yaw, -PI, PI)
	a._want_yaw = 0.0
	if p.parent_was and is_instance_valid(p.parent_was) and a.get_parent() != p.parent_was:
		a.reparent(p.parent_was, true)
	if a.face:
		a.face.set_expression(p.face_was if p.face_was != "" else "neutral")
		a.face.look(0.0)
	p.state = "calm"


## He runs for a hiding place (`found`: he has been found where he was, and keeps away from there now; `crowded`:
## people in his way stopped him, and he goes round them).
func _run(p: Person, found := false, crowded := false) -> void:
	if found:
		p.tries = 0                           # seen where he is: a new run, with its own TRIES
	if found and p.spot != Vector2.INF:
		p.avoid.append(p.spot)
	elif found:
		p.avoid.append(Vector2(p.actor.position.x, p.actor.position.z))
	p.spot = Vector2.INF
	p.running_off = false
	p.state = "fleeing"
	p.seen_t = 0.0
	p.in_sight = false
	p.flee.go(PackedVector2Array(), [])        # he stands while he looks about for somewhere
	p.flee.face_front = false
	if p.actor.face and p.hurt_t <= 0.0:
		p.actor.face.set_expression("scared", true)
		p.actor.face.look(0.0)
	p.search = _new_search(p, Vector2.INF, crowded)
	if p.search == null:
		_cower(p)


## A search for somewhere to hide from the lead (goal INF), or for the way to `goal` (`crowded`: not through
## anyone within CROWD of him).
func _new_search(p: Person, goal: Vector2, crowded := false) -> RefCounted:
	var a := p.actor
	var b := _site_of(p)
	a.areas = b.walk_areas()
	a.obstacles = p.obstacles_was
	a.others = [main._actor]
	for q: Person in here():
		if q != p and q.state != "dead":
			a.others.append(q.actor)
	var g: RefCounted = Cover.grid(b, a.reach)
	var at := Vector2(a.position.x, a.position.z)
	var start := _way_in(p, g, at)
	if start < 0:
		return null
	var s: RefCounted = Cover.Search.new()
	s.g = g
	s.start = start
	s.from_spot = at
	var lead: Node3D = main._actor
	s.shooter = Vector2(lead.global_position.x, lead.global_position.z)
	s.eye = Cover.eye_of(lead)
	s.keep_off = p.avoid.duplicate()
	for q: Person in here():
		if q != p and q.spot != Vector2.INF:
			s.keep_off.append(q.spot)
		if q == p or q.state == "dead" or goal != Vector2.INF:
			continue
		var there := Vector2(q.actor.position.x, q.actor.position.z)
		if q.state in ["hiding", "cowering", "held"] or (crowded and there.distance_to(at) < CROWD):
			s.blocked.append(there)          # no way through someone crouched in a doorway, or who stopped him
	s.tall = float(a.height) * FleeBrain.crouched(a)
	s.floor_y = a.global_position.y
	s.world = world_of.call(b)
	for door: Node3D in (b.get("doors") if b.get("doors") is Array else []):
		s.doors[door] = true
		if door.get("mate"):
			s.doors[door.mate] = true
	s.shown = func(ri: int) -> bool: return Cover.node_of_room(b, ri).is_visible_in_tree()
	if goal != Vector2.INF:
		s.goal = g.nearest(goal)
		if s.goal < 0:
			return null
	return s


## The square his way starts from. Someone standing where nobody may walk (behind a counter, too near it) first
## goes straight to the nearest square he can get to without going through what is there: props do not stop
## him till he is out (people_flee.gd's escape). -1 if there is none.
func _way_in(p: Person, g: RefCounted, at: Vector2) -> int:
	var a := p.actor
	p.flee.escape = false
	if a.can_stand(at):
		return g.nearest(at)
	var b := _site_of(p)
	var near: Array = []
	for dz in range(-6, 7):
		for dx in range(-6, 7):
			var i: int = g.at(at + Vector2(dx, dz) * Cover.CELL)
			if g.is_open(i):
				near.append(Vector2((g.middle(i) as Vector2).distance_to(at), i))
	near.sort()
	var best := -1
	for each: Vector2 in near.slice(0, 12):
		if _no_prop_between(b, at, g.middle(int(each.y))):
			best = int(each.y)
			break
	if best >= 0:
		a.areas.append(Rect2(at, Vector2.ZERO).expand(g.middle(best)).grow(0.12))
		a.obstacles = []
		p.flee.escape = true
	return best


static func _no_prop_between(b: Node3D, from: Vector2, to: Vector2) -> bool:
	var n := maxi(int(ceil(from.distance_to(to) / 0.05)), 1)
	var box := Rect2(from, Vector2.ZERO).expand(to)
	for prop: Rect2 in b.obstacles:
		if not prop.intersects(box, true):
			continue
		for k in n + 1:
			if prop.has_point(from.lerp(to, float(k) / float(n))):
				return false
	return true


## His search is done: off he goes (or he cowers where he is; or, going home, he is let go where he is).
func _search_done(p: Person) -> void:
	var s: RefCounted = p.search
	p.search = null
	p.spent += int(s.usec)
	p.looked += int(s.tried)
	var exact: Array = []
	var doors: Array = []                # the door each point is in the doorway of (he opens it if it is shut)
	for point: Vector2 in s.path:
		exact.append(s.g.snap.has(s.g.at(point)))
		doors.append(s.g.door_at.get(s.g.at(point)))
	if p.state == "fleeing":
		if s.found < 0:
			_cower(p)
			return
		if _claimed(p, s.g.middle(s.found)):
			p.search = _new_search(p, Vector2.INF)       # someone else took it while he looked: he looks again
			if p.search == null:
				_cower(p)
			return
		p.spot = s.g.middle(s.found)
		p.running_off = s.fled
		if s.path.is_empty():
			_settle(p)
			return
		p.flee.go(s.path, exact, doors)
	elif p.state == "returning":
		if s.found < 0:
			_let_go(p)                   # no way back: he stays where he is
			return
		var way: PackedVector2Array = s.path
		way.append(Vector2(p.home.x, p.home.z))
		exact.append(true)
		doors.append(null)
		p.flee.go(way, exact, doors)


## Has someone else here taken a hiding place this near `spot`?
func _claimed(p: Person, spot: Vector2) -> bool:
	for q: Person in here():
		if q != p and q.spot != Vector2.INF and q.spot.distance_to(spot) < Cover.CLAIM:
			return true
	return false


## Held up on his way: may he stop where he is and hide there (out of the shooter's sight already, standing as
## he is, in a room, not a doorway, and not close to the shooter)?
func _may_stop_here(p: Person) -> bool:
	var a := p.actor
	var here := Vector2(a.position.x, a.position.z)
	if Cover.room_of(_site_of(p), here) < 0 or a.global_position.distance_to(main._actor.global_position) < Cover.NEAR_SHOOTER:
		return false
	return not _seen_now(p)


## There: down in his hiding place, or (nowhere hid him) cowering as far from the lead as he could get.
func _settle(p: Person) -> void:
	if p.running_off:
		_cower(p)
	else:
		_hide(p)


func _hide(p: Person) -> void:
	p.state = "hiding"
	p.flee.go(PackedVector2Array(), [])
	p.flee.face_front = true
	p.look_t = LOOK_EVERY
	p.seen_t = 0.0
	p.in_sight = false


## Nowhere to go: down where he is.
func _cower(p: Person) -> void:
	p.state = "cowering"
	p.flee.go(PackedVector2Array(), [])
	p.flee.face_front = true
	p.retry_t = RETRY
	p.look_t = 0.0
	p.seen_t = 0.0


## Calm again: he walks back to where he was.
func _go_home(p: Person) -> void:
	p.state = "returning"
	p.spot = Vector2.INF
	p.running_off = false
	p.tries = 0
	p.flee.go(PackedVector2Array(), [])
	p.flee.face_front = false
	if p.actor.face:
		p.actor.face.set_expression(p.face_was if p.face_was != "" else "neutral")
		p.actor.face.look(0.0)
	p.search = _new_search(p, Vector2(p.home.x, p.home.z))
	if p.search == null:
		_let_go(p)


## Running for his hiding place: crouched at `at`, would he be out of the lead's sight? (people_flee.gd asks, near
## the end of his way: someone drawn from the front only may stop a little short of the spot that was tried.)
func _hidden_there(p: Person, at: Vector2) -> bool:
	var a := p.actor
	if p.state != "fleeing" or not a.is_visible_in_tree():
		return true
	return not Cover.seen(world_of.call(_site_of(p)), Cover.eye_of(main._actor), at, a.global_position.y,
			float(a.height) * FleeBrain.crouched(a))


## Can the lead see him where he is (crouched as he is)?
func _seen_now(p: Person) -> bool:
	var a := p.actor
	if not a.is_visible_in_tree():
		return false             # in a part of the place the camera has cut away: there are walls between (people_cover.gd)
	return Cover.seen(world_of.call(_site_of(p)), Cover.eye_of(main._actor), Vector2(a.global_position.x, a.global_position.z),
			a.global_position.y, _tall(p))


# ------------------------------------------------------------ held up

## Is the lead holding him up: pointing a gun at him (the cross on him or near), close, in clear sight?
func _held_up(p: Person) -> bool:
	var lead: Node3D = main._actor
	if p.foe or lead.weapon == "" or not lead.aiming or lead.lowered:
		return false
	var a := p.actor
	if not a.is_visible_in_tree() or a.global_position.distance_to(lead.global_position) > HOLD_RANGE:
		return false
	if not _aimed_at(p):
		return false
	var chest := a.global_position + Vector3(0.0, a.height * 0.6, 0.0)
	var w = world_of.call(_site_of(p))
	return w == null or not w.trace(Cover.eye_of(lead), chest)["hit"]


## Is the red cross on his drawing or near it (or, with no cross, the barrel pointed at him)?
func _aimed_at(p: Person) -> bool:
	var a := p.actor
	if main._cross.visible:
		var cam: Camera3D = main._camera
		var foot: Vector3 = a.global_position
		var head := foot + Vector3(0.0, _tall(p) * 0.95, 0.0)
		if cam.is_position_behind(foot) or cam.is_position_behind(head):
			return false
		var s0 := cam.unproject_position(foot)
		var s1 := cam.unproject_position(head)
		var at: Vector2 = main._cross.at
		var gap := at.distance_to(Geometry2D.get_closest_point_to_segment(at, s0, s1))
		return gap <= s0.distance_to(s1) * 0.15 * a.reach / 0.4 + HOLD_NEAR
	var gp: Dictionary = main._actor.gun_points()
	if gp.is_empty():
		return false
	var to: Vector3 = a.global_position + Vector3(0.0, a.height * 0.6, 0.0) - (gp["muzzle"] as Vector3)
	return (gp["dir"] as Vector3).angle_to(to) < HOLD_CONE


func _hold_up(p: Person) -> void:
	_take_over(p)
	p.state = "held"
	p.off_t = 0.0
	p.flee.go(PackedVector2Array(), [])
	p.flee.face_front = false
	_look_at(p, main._actor.global_position)
	if p.actor.face:
		p.actor.face.set_expression("scared", true)


# ------------------------------------------------------------ down

func _die(p: Person, dir: Vector3, lay := Vector3.ZERO, write := true) -> void:
	_take_over(p)
	p.state = "dead"
	p.health = 0
	p.member["brain"] = null              # nothing walks him now; main.gd only keeps his drawing posed
	p.search = null
	p.spot = Vector2.INF
	p.crouch = 0.0
	p.hands = 0.0
	var a := p.actor
	_still(a)
	a.use_reach = -1.0                    # nobody to talk to
	if a.face:
		a.face.talking = false
		a.face.hold = true                # for good: nothing on his face moves now (paper_face.gd's HELD)
		a.face.set_expression("dead", true)
		a.face.hold_mouth(String(PaperFace.HELD["dead"]["mouth"]))
		a.face.look(0.0)
	a.fall_to = lay if lay != Vector3.ZERO else _fall_way(p, dir)
	a.fall_lift = _floor_under(p) - a.global_position.y
	p.fall_t = 0.0
	_out_of_the_way(p)
	_settle_in_room(p)
	if write:
		_remember(p)


## Nothing about him moves from now on: no dance, no step, no bob, no turn, nothing in his hands. He goes down
## from his front drawing, square to the camera, so that it is his face that ends up looking up.
static func _still(a: Node3D) -> void:
	a.weapon = ""
	a.aiming = false
	a.lowered = false
	a.recoil = 0.0
	a.sprinting = false
	a.performing = false
	a.cower = 0.0
	a.flinch = 0.0
	a._groove = 0.0
	a._beat = 0.0
	a._gait = 0.0
	a._phase = 0.0
	a._run = 0.0
	a._armed = 0.0
	a._aim = 0.0
	PeopleBack.front_again(a)
	if a.view != "front" and a._views.has("front"):
		a._show("front")
	a._want_view = a.view
	a._want_yaw = 0.0
	a._yaw = 0.0
	if not a._pivot.top_level:
		a._pivot.rotation = Vector3.ZERO
		a._pivot.scale = Vector3.ONE
	a._card.position.y = 0.0
	a._card.rotation.z = 0.0
	a.walk(Vector2.ZERO, Vector2.ZERO, 0.0)          # posed so at once


## The way his head goes as he falls: across the screen, away from the shot, where there is floor for him.
func _fall_way(p: Person, dir: Vector3) -> Vector3:
	var eye: Basis = main._camera.global_transform.basis
	var right := Vector3(eye.x.x, 0.0, eye.x.z).normalized()
	var away := -Vector3(eye.z.x, 0.0, eye.z.z).normalized()
	var push := right if Vector3(dir.x, 0.0, dir.z).dot(right) >= 0.0 else -right
	for way: Vector3 in [push, push.rotated(Vector3.UP, 0.4 * signf(push.dot(right))), -push, away, (push + away).normalized(), (-push + away).normalized(), -away]:
		if _room_to_lie(p, way):
			return way
	return push


func _room_to_lie(p: Person, way: Vector3) -> bool:
	var a := p.actor
	var b := _site_of(p)
	var room: Dictionary = b.rooms[b.room_at_pos(a.global_position, 0)]
	var floor_rect: Rect2 = room.get("rect", room.get("area", Rect2()))
	floor_rect = floor_rect.grow(-0.12)
	for k: float in [0.3, 0.6, 0.85, 1.0]:
		var spot: Vector3 = a.global_position + way * a.height * k
		var flat := Vector2(spot.x, spot.z)
		if not floor_rect.has_point(flat):
			return false
		for prop: Rect2 in b.obstacles:
			if prop.grow(0.05).has_point(flat):
				return false
	return true


## The dead stand in nobody's way.
func _out_of_the_way(p: Person) -> void:
	main._actor.others.erase(p.actor)
	for q: Person in here():
		q.actor.others.erase(p.actor)
		if q.taken:
			q.others_was.erase(p.actor)


## In the player state's flags: who is down where, today.
func _remember(p: Person) -> void:
	var state: RefCounted = main._state
	var dead: Dictionary = state.flags.get("dead", {})
	if int(dead.get("day", -1)) != int(main._day):
		dead = {"day": main._day, "who": {}}
	var who: Dictionary = dead["who"].get(p.place, {})
	var a := p.actor
	who[str(p.index)] = [snappedf(a.position.x, 0.01), snappedf(a.position.z, 0.01), snappedf(a.fall_to.x, 0.001), snappedf(a.fall_to.z, 0.001)]
	dead["who"][p.place] = who
	state.flags["dead"] = dead
	state.touch()


## Make what the flags say true at `place`: the dead are down (with their pools, at once), the rest are up.
func reconcile(place: String) -> void:
	if not main._cast.has(place):
		return
	var dead: Dictionary = main._state.flags.get("dead", {})
	var who: Dictionary = {}
	if int(dead.get("day", -1)) == int(main._day):
		who = dead.get("who", {}).get(place, {})
	var cast: Array = main._cast[place]
	for i in cast.size():
		var p := _person(place, i)
		var key := str(i)
		if who.has(key) and p.state != "dead":
			var at: Array = who[key]
			_take_over(p)
			p.actor.position = Vector3(float(at[0]), p.actor.position.y, float(at[1]))
			_die(p, Vector3.ZERO, Vector3(float(at[2]), 0.0, float(at[3])), false)
			p.fall_t = FALL
			p.actor.fallen = 1.0
		elif not who.has(key) and p.state == "dead":
			_revive(p)
	if place == main._place and main._building.is_visible_in_tree():
		for p: Person in here():
			if p.state == "dead":
				_out_of_the_way(p)
				if p.pool == null and p.fall_t >= FALL:           # down when he came: his floor and his pool, now it can be seen
					p.actor.fall_lift = _floor_under(p) - p.actor.global_position.y
					_pool_for(p, 0.0)


func _revive(p: Person) -> void:
	var a := p.actor
	if p.pool:
		fx.lift_pool(p.pool)
		p.pool = null
	a.fallen = 0.0
	a.use_reach = p.reach_was
	p.fall_t = -1.0
	p.health = HEALTH
	if a.face:
		a.face.hold = false
		a.face.hold_mouth("")
	a.position = p.home
	a.face_way("front")
	_let_go(p)
	if p.place == main._place and not main._actor.others.has(a):
		main._actor.others.append(a)


## He has left `place`: those there who ran are back where they were, unfrightened.
func left(place: String) -> void:
	for key: String in _people:
		var p: Person = _people[key]
		if p.place == place and p.state != "dead" and p.taken:
			var a := p.actor
			a.position = p.home
			PeopleBack.front_again(a)
			if a.view != "front" and a._views.has("front"):
				a._show("front")
			a._want_view = a.view
			a._yaw = 0.0
			a._want_yaw = 0.0
			p.hurt_t = 0.0
			p.health = HEALTH
			_let_go(p)


## Someone who has run into another room goes into its node, so that he is shown and hidden with it.
func _settle_in_room(p: Person) -> void:
	var a := p.actor
	var b := _site_of(p)
	var ri := Cover.room_of(b, Vector2(a.position.x, a.position.z))
	if ri < 0:
		return
	var node := Cover.node_of_room(b, ri)
	if node and a.get_parent() != node and a.get_parent() != main:
		a.reparent(node, true)


func _pool_for(p: Person, seconds: float) -> void:
	if p.pool:
		return
	var a := p.actor
	var feet: Vector3 = a.global_position
	var at: Vector3 = feet + a.fall_to * a.height * 0.42
	p.pool = fx.pool(Vector3(at.x, _floor_under(p) + 0.004, at.z), POOL_RADIUS * a.reach / 0.4, seconds, _node_for(feet, _site_of(p)))


## The place someone belongs to (its node).
func _site_of(p: Person) -> Node3D:
	return main._sites.get(p.place, main._building)


## The top of the floor he lies on: the highest under his feet, middle and head that is no more than a step
## above his feet (a court, a rug; not a bench his head is under).
func _floor_under(p: Person) -> float:
	var a := p.actor
	var feet: Vector3 = a.global_position
	var w = world_of.call(_site_of(p))
	if w == null:
		return feet.y
	var top := feet.y
	for k: float in [0.0, 0.45, 0.85]:
		var at: Vector3 = feet + a.fall_to * a.height * k
		top = maxf(top, w.floor_at(Vector3(at.x, feet.y - 0.38, at.z), feet.y))      # it looks down from 0.12 above his feet
	return top


## The node things on the floor at `at` go in, so that they are hidden with the room (a band of a place,
## a room of the studio).
func _node_for(at: Vector3, site: Node3D = null) -> Node3D:
	var b: Node3D = site if site else main._building
	var room: Dictionary = b.rooms[b.room_at_pos(at, maxi(main._room, 0) if b == main._building else 0)]
	if room.has("node"):
		return room["node"]
	return b.node_of(room["band"])


# ------------------------------------------------------------ each frame

func tick(delta: float) -> void:
	var until := Time.get_ticks_usec() + Cover.BUDGET
	var lead: Node3D = main._actor
	var pointing: bool = lead.weapon != "" and lead.aiming and not lead.lowered
	for p: Person in here():
		var a := p.actor
		if p.state == "dead":
			if p.fall_t >= 0.0 and p.fall_t < FALL:
				p.fall_t += delta
				a.fallen = clampf(p.fall_t / FALL, 0.0, 1.0)
				if p.fall_t >= FALL:
					_pool_for(p, POOL_SECONDS)
			continue
		if a.flinch != 0.0:
			a.flinch = move_toward(a.flinch, 0.0, delta * 1.4)
		if p.hurt_t > 0.0:
			p.hurt_t -= delta
			if p.hurt_t <= 0.0 and a.face and p.state != "calm" and p.state != "returning":
				a.face.set_expression("scared", true)
		if p.search != null and Time.get_ticks_usec() < until:
			while not p.search.step(until) and Time.get_ticks_usec() < until:
				pass
			if p.search.done:
				_search_done(p)
		match p.state:
			"calm":
				if pointing and _held_up(p):
					_hold_up(p)
			"alarmed":
				if pointing and _held_up(p):
					_hold_up(p)
				else:
					p.wait -= delta
					if p.wait <= 0.0:
						_run(p)
			"held":
				p.off_t = 0.0 if pointing and _held_up(p) else p.off_t + delta
				if p.off_t >= RELEASE:
					_run(p)
			"fleeing":
				if p.search == null and p.flee.stuck:
					if _may_stop_here(p):
						p.spot = Vector2(a.position.x, a.position.z)
						_hide(p)                         # out of his sight already: down where he is
					else:
						p.tries += 1
						if p.tries < TRIES:
							_run(p, false, true)         # round whoever stopped him
						else:
							_cower(p)
				elif p.search == null and p.flee.arrived:
					_settle(p)
			"hiding", "cowering":
				p.look_t -= delta
				if p.look_t <= 0.0:
					p.look_t = LOOK_EVERY
					p.in_sight = _seen_now(p)
				p.seen_t = p.seen_t + delta if p.in_sight else 0.0
				p.quiet = 0.0 if pointing else p.quiet + delta
				if p.quiet > CALM:
					_go_home(p)
				elif p.state == "hiding" and p.seen_t >= SEEN_FOR:
					_run(p, true)
				elif p.state == "cowering":
					p.retry_t -= delta
					if p.retry_t <= 0.0 and p.in_sight:
						p.retry_t = RETRY
						_run(p, true)
			"returning":
				if p.search == null and p.flee.stuck:
					p.tries += 1
					if p.tries < TRIES:
						_go_home(p)
					else:
						_let_go(p)
				elif p.search == null and p.flee.arrived:
					p.flee.face_front = true
					if absf(wrapf(a._yaw, -PI, PI)) < 0.05 and a.view == "front":
						_let_go(p)
		if p.taken:
			p.crouch = move_toward(p.crouch, 1.0 if p.state in ["hiding", "cowering"] else 0.0, delta / CROUCH_TIME)
			p.hands = move_toward(p.hands, 1.0 if p.state == "held" else 0.0, delta / HANDS_TIME)
			if p.state in ["fleeing", "returning"]:
				_settle_in_room(p)


## For the check: is this person down, and is there a pool under him?
func is_down(p: Person) -> bool:
	return p.state == "dead"


func has_pool(p: Person) -> bool:
	return p.pool != null and is_instance_valid(p.pool) and p.pool.is_visible_in_tree()
