extends RefCounted
## Moves someone frightened: combat_people.gd puts one in main.gd's cast in place of his own brain while he is
## frightened, and main.gd calls tick() each frame. It walks him along `path` (to a hiding place, or home again),
## opening any shut door on it as he gets there, and stands him still, crouched or with his hands up, as
## combat_people.gd says (the Person's `crouch` and `hands`, 0 .. 1).
##
## He faces the way he goes (the house rule). Before he goes a new way he turns to face it, standing; going on he
## turns little by little as his way bends. Someone with a drawing for each way (front, side, back) turns as he
## always has, a paper flip to the drawing for that way. Someone drawn only from the front turns his card about its
## upright (people_back.gd): towards the camera or away from it he faces the way he goes; straight across the
## screen his card cannot face (it would be edge on), so he goes across at people_back.gd's TURN_MOST, first one
## side of it and then the other, as someone dodging does, keeping to each side at least TACK seconds (held up by
## a corner on one side, he tries the other for DODGE seconds). Anyone held up against a prop (sliding along it
## slower than he walks) makes for a point just round its nearer corner first, turning to face it.

const PeopleBack := preload("res://scripts/people_back.gd")
const Cover := preload("res://scripts/people_cover.gd")
const ARRIVE := 0.14             # metres: a point of his way is reached this near
const ARRIVE_LOOSE := 0.3        # ...or this near, for a point in the middle of his way that is not in a doorway
const PASSED := 0.4              # ...or, not in a doorway, this near once he has gone past it
const TURN_EPS := 0.14           # radians: turned further than this from the way he means to go, he stops to turn
const TACK := 0.35               # seconds: drawn only from the front, he keeps to the side he faces at least this long
const TURN := 0.22               # seconds: someone with a drawing for each way stands turning this long (a paper flip)
const LIFT := 0.14               # crouched, his feet come up his drawing this much of its height, at most (and he comes down)
const SQUASH := 0.22             # ...and he is squashed down by this much of his height, as a cartoon cowers
const HANDS_UP := 1.25           # radians: hands up, each upper arm turned this far out from hanging (a little above level)
const HANDS_CURL := 0.95         # ...and the arm bowed this much further up by the hand, so the hand is over the elbow
const STUCK := 0.6               # seconds of getting nowhere before he gives up on his way
const DODGE := 0.15              # seconds: drawn from the front only, crossing the screen, held up this long by something on his way,
                                 # he goes round it by the other side of the way across, for this long
const OPEN_REACH := 1.2          # metres: a shut door on his way, he opens it from this near its doorway
const ROUND := 0.2               # metres: held up DODGE seconds against a prop, he makes for a point this far out from
                                 # its corner each way

var frozen := false
var main: Node
var person:                      # the Person it moves (held weakly: the Person holds this)
	get:
		return _person.get_ref() if _person else null
	set(value):
		_person = weakref(value)
var path := PackedVector2Array()
var tight: Array = []            # for each point of path: true where it must be reached exactly (a doorway)
var doors: Array = []            # for each point of path: the door whose doorway it is in, or null (shut: he opens it)
var at := 0
var arrived := false
var stuck := false
var face_front := false          # standing: turn to face the camera
var look_way := Vector2.ZERO     # standing: turn to face this way on the floor (if face_front is not set)
var escape := false              # he starts where he may not stand (behind a counter): props do not stop him till he is out
var hidden_at: Callable          # (Person, floor spot) -> bool: crouched there, is he out of the shooter's sight? (combat_people.gd)
var _person: WeakRef
var _turning := 0.0
var _tack := TACK
var _slow := 0.0
var _dodged := false             # held up, he has tried the other side of the way across
var _rounded := false            # held up by a prop, he has made for a point round its corner (once for each point)
var _start := Vector2.INF        # where he set off along this way


## A new way to go.
func go(way: PackedVector2Array, exact: Array, through: Array = []) -> void:
	path = way
	tight = exact
	doors = through
	at = 0
	arrived = way.is_empty()
	stuck = false
	_slow = 0.0
	_dodged = false
	_rounded = false
	_turning = 0.0
	_tack = TACK
	_start = Vector2.INF


func tick(delta: float) -> void:
	var p = person
	if p == null:
		return
	var a: Node3D = p.actor
	var dt := 1.0 / 60.0 if main._scripted else delta
	a.cower = p.crouch
	if frozen or arrived or at >= path.size():
		_stand(a, dt)
	else:
		_go(a, dt, p)
	_after(a, p)


## Standing: turned the way he is asked to face, if any.
func _stand(a: Node3D, dt: float) -> void:
	a.sprinting = false
	if PeopleBack.turns(a):
		if face_front:
			a._want_yaw = PeopleBack.toward(a._yaw, 0.0)
		elif look_way != Vector2.ZERO:
			a._want_yaw = PeopleBack.yaw_for(a, look_way, a._yaw)
	elif face_front and (a.view != "front" or not is_equal_approx(a._want_yaw, 0.0)):
		a.face_way("front")
	a.walk(Vector2.ZERO, Vector2.ZERO, dt)


func _go(a: Node3D, dt: float, p: RefCounted) -> void:
	var here := Vector2(a.position.x, a.position.z)
	if _start == Vector2.INF:
		_start = here
	var turner := PeopleBack.turns(a)
	while at < path.size():
		var exact := bool(tight[at])
		var last := at >= path.size() - 1
		# Someone drawn from the front only goes straight across the screen dodging from side to side, so he may
		# pass a point a little to one side of it: near enough, and gone past it, it is reached (his hiding
		# place, only where it hides him).
		var near := ARRIVE if exact or (last and not turner) else ARRIVE_LOOSE
		var gap := here.distance_to(path[at])
		if gap >= near:
			var before: Vector2 = path[at - 1] if at > 0 else _start
			if exact or gap >= PASSED or (path[at] - before).dot(here - path[at]) <= 0.0:
				break
		if last and gap >= ARRIVE and hidden_at.is_valid() and not hidden_at.call(p, here):
			break
		at += 1
		_rounded = false
	if at >= path.size():
		arrived = true
		_stand(a, dt)
		return
	var door: Node3D = doors[at] if at < doors.size() else null
	if door and not door.is_open and here.distance_to(path[at]) < OPEN_REACH:
		door.set_open(true)                          # a shut door on his way: he opens it as he gets to it
	if door and door.is_open:
		for d: Node3D in [door, door.mate]:
			if d and d.passage.has_area() and not a.areas.has(d.passage):
				a.areas.append(d.passage)
	if escape and _out(a, here, p.obstacles_was):
		escape = false
		a.obstacles = p.obstacles_was
	if _slow > DODGE and not _rounded:
		var round_to := _round(a, here, path[at])
		if round_to != Vector2.INF:
			path.insert(at, round_to)                  # round the corner first, then on as he was going
			tight.insert(at, true)
			if at <= doors.size():
				doors.insert(at, null)
			_rounded = true
			_slow = 0.0
	var want := (path[at] - here).normalized()
	a.sprinting = p.state == "fleeing"
	var dir := want
	if PeopleBack.turns(a):
		var away_now := cos(a._want_yaw) < 0.0
		var yaw := PeopleBack.yaw_for(a, want, a._want_yaw)
		var across := absf(wrapf(atan2(want.x, want.y) - a.global_rotation.y, -PI, PI))
		_tack += dt
		if _slow > DODGE and not _dodged and across > PeopleBack.TURN_MOST and across < PI - PeopleBack.TURN_MOST:
			yaw = PeopleBack.yaw_on_side(a, want, a._want_yaw, not away_now)     # held up (a corner): round it the other way
			_tack = TACK - DODGE
			_dodged = true
		elif (cos(yaw) < 0.0) != away_now:
			if _tack < TACK:
				yaw = PeopleBack.yaw_on_side(a, want, a._want_yaw, away_now)      # not yet: on along the side he is on
			else:
				_tack = 0.0
		a._want_yaw = yaw
		if absf(wrapf(yaw - a._yaw, -PI, PI)) > TURN_EPS:
			a.walk(Vector2.ZERO, Vector2.ZERO, dt)          # turning where he stands
			return
		dir = PeopleBack.facing(a, a._yaw)
		a.walk(dir, Vector2(0.0, 1.0 if cos(a._yaw) >= 0.0 else -1.0), dt)
	else:
		if _turning > 0.0:
			_turning -= dt
			a.walk(Vector2.ZERO, Vector2.ZERO, dt)
			return
		if _turn_for(a, want):
			a.walk(Vector2.ZERO, Vector2.ZERO, dt)
			return
		a.walk(want, main._screen_dir(want), dt)
	var moved := Vector2(a.position.x, a.position.z).distance_to(here)
	if moved < a.WALK_SPEED * float(a.speed) * dt * 0.3:
		_slow += dt
	else:
		_slow = 0.0
		_dodged = false
	if _slow > STUCK:
		stuck = true


## Escaping from where nobody may stand: is he out, on the place's floor and clear of its props?
func _out(a: Node3D, here: Vector2, props: Array) -> bool:
	for prop: Rect2 in props:
		if prop.grow_individual(a.reach, a.RADIUS, a.reach, a.RADIUS).has_point(here):
			return false
	for area: Rect2 in main._building.walk_areas():
		if area.has_point(here):
			return true
	return false


## Held up against a prop: a point ROUND out from one of its corners, that he may stand on and walk to straight
## from where he is, the one that makes his way on to `ahead` shortest (INF if no prop is holding him up).
func _round(a: Node3D, here: Vector2, ahead: Vector2) -> Vector2:
	var best := Vector2.INF
	var best_cost := INF
	for prop: Rect2 in a.obstacles:
		var r: Rect2 = prop.grow_individual(a.reach, a.RADIUS, a.reach, a.RADIUS)
		if r.has_point(here) or not r.grow(0.06).has_point(here):
			continue                                   # not the one he is up against
		var mid := r.get_center()
		for c: Vector2 in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
			var out: Vector2 = c + Vector2(signf(c.x - mid.x), signf(c.y - mid.y)) * ROUND
			if not a.can_stand(out) or Cover.cuts(r, here, out):
				continue
			var cost := here.distance_to(out) + out.distance_to(ahead)
			if cost < best_cost:
				best_cost = cost
				best = out
	return best


## Someone with a drawing for each way: before he goes a new way he turns to its drawing, standing. True while he does.
func _turn_for(a: Node3D, way: Vector2) -> bool:
	var screen: Vector2 = main._screen_dir(way)
	var view := "front"
	var mirrored := false
	if a._views.has("side") and absf(screen.x) >= absf(screen.y) * 0.7:
		view = "side"
		mirrored = screen.x < 0.0
	elif a._views.has("back") and screen.y < 0.0:
		view = "back"
	elif a._views.size() == 1:
		return false
	if a.view == view and is_equal_approx(a._want_yaw, PI if mirrored else 0.0):
		return false
	a.face_way(view, mirrored)
	_turning = TURN
	return true


## After he has walked this frame: his back if he is seen from behind, crouched, hands up.
func _after(a: Node3D, p: RefCounted) -> void:
	if PeopleBack.turns(a):
		PeopleBack.show_side(a)
	var legs: bool = a._views[a.view]["limbs"] != null
	if p.crouch > 0.0 and legs:
		var hip := float(a._mat.get_shader_parameter("hip_v"))
		var knee := float(a._mat.get_shader_parameter("knee_v"))
		var lift := minf(LIFT, 0.8 * maxf(knee - hip, 0.0)) * float(p.crouch)
		a._put("lift_l", lift)
		a._put("lift_r", lift)
		a._card.position.y = -lift * a.height
	if not a._pivot.top_level:
		if p.crouch > 0.0:
			var c := float(p.crouch)
			a._pivot.scale = Vector3(1.0 + 0.5 * SQUASH * c, 1.0 - SQUASH * c, 1.0)     # deeper than paper_actor.gd's cower
		elif a._pivot.scale != Vector3.ONE:
			a._pivot.scale = Vector3.ONE
	if p.hands > 0.0 and legs and a._arms.has("l") and a._arms.has("r") and a.weapon == "":
		raise_hands(a, float(p.hands))


## His hands up, `h` of the way (0 .. 1), seen square on: the upper arm goes out from the shoulder and the arm
## bows on up from there, so the elbow is the widest point and the open hand ends up above it, beside his head.
## (It was the other way about: the arm went up steeply and bowed outwards, so the elbows were tucked in and the
## hands splayed, which read as arms bent the wrong way.)
static func raise_hands(a: Node3D, h: float) -> void:
	a._put("arm_l_angle", -HANDS_UP * h)
	a._put("arm_r_angle", HANDS_UP * h)
	a._put("arm_l_curl", -HANDS_CURL * h)
	a._put("arm_r_curl", HANDS_CURL * h)


## How tall someone is crouched as far as he goes, of his standing height.
static func crouched(a: Node3D) -> float:
	if a._views[a.view]["limbs"] == null:
		return 1.0 - SQUASH              # no legs drawn: he only shrinks
	var hip := float(a._mat.get_shader_parameter("hip_v"))
	var knee := float(a._mat.get_shader_parameter("knee_v"))
	return (1.0 - minf(LIFT, 0.8 * maxf(knee - hip, 0.0))) * (1.0 - SQUASH)
