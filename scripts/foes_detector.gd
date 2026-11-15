extends Node3D
## The lamps and alarm of a metal detector (props.gd's detector()). Walking through between its posts
## blinks the lamps green; with a firearm on him (`armed` says so) they blink red, the light on top flashes
## and throws a red glow round it, and `tripped` is emitted. combat_foes.gd sets `armed`, the numbers
## (foes.json "detector") and listens; with nobody listening it only ever blinks green.
##
##   var lamps: Node3D = preload("res://scripts/foes_detector.gd").new()
##   lamps.zone = Rect2(...)                 # the floor between the posts, x and z in the world
##   parent.add_child(lamps)
##   lamps.add_lamp(size, where)             # as many as it has
##   lamps.add_beacon(radius, height, where) # the light on top
##   place.watchers.append(lamps)            # the scene tells it where he is each frame

signal tripped(red: bool)

const OFF := Color(0.6, 0.61, 0.6)
const GREEN := Color(0.3, 0.95, 0.4)
const RED := Color(1.0, 0.13, 0.1)
const BEACON_OFF := Color(0.3, 0.29, 0.3)       # unlit: smoked grey, so only an alarm looks red
const GLOW := 2.6               # the red glow's brightness at its height (the green one, as he walks through clean: GREEN_GLOW of it)
const GREEN_GLOW := 0.5
const GLOW_REACH := 3.4         # metres

var zone := Rect2()
var armed := Callable()         # () -> bool: he has a firearm on him. Not set: never
var numbers := {"blinks": 3, "blink": 0.3, "red_blinks": 16, "red_blink": 0.2}
var shown := ""                 # what it showed the last time he walked through: "green" or "red"
var times := 0                  # how many times he has walked through

var _mat: StandardMaterial3D
var _beacon_mat: StandardMaterial3D
var _glow: OmniLight3D
var _inside := false
var _left := 0.0                # seconds of blinking still to run
var _red := false


func _init() -> void:
	add_to_group("foes_detector")
	_mat = _lamp_material(GREEN)        # its own, so one detector blinking does not light them all
	_beacon_mat = _lamp_material(RED)
	_light(false)


func _lamp_material(on: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.roughness = 1.0
	m.metallic_specular = 0.0
	m.emission = on
	m.emission_energy_multiplier = 1.4
	return m


## A lamp, `size` big, at `where` in this node. They all share one material, so they blink together.
func add_lamp(size: Vector3, where: Vector3) -> MeshInstance3D:
	return Kit.box(self, size, where, _mat)


## The light on top, a short drum `radius` round and `height` high centred on `where`: dark until it goes
## off, then it flashes red with a glow round it.
func add_beacon(radius: float, height: float, where: Vector3) -> MeshInstance3D:
	_glow = Kit.omni(self, where + Vector3(0.0, 0.25, 0.35), RED, 0.0, GLOW_REACH)
	_glow.visible = false
	return Kit.cyl(self, radius, height, where, _beacon_mat, Vector3.ZERO, 12)


## Where he is now. Stepping into the zone starts the blinking.
func watch(at: Vector3, delta: float) -> void:
	var inside := zone.has_point(Vector2(at.x, at.z))
	if inside and not _inside:
		_red = armed.is_valid() and bool(armed.call())
		shown = "red" if _red else "green"
		times += 1
		_left = _total()
		tripped.emit(_red)
	_inside = inside
	if _left <= 0.0:
		return
	_left -= delta
	var each := float(numbers["red_blink"] if _red else numbers["blink"])
	_light(_left > 0.0 and fmod(_total() - _left, each) < each * 0.6, _left > 0.0)


func _total() -> float:
	return float(numbers["red_blinks"]) * float(numbers["red_blink"]) if _red else float(numbers["blinks"]) * float(numbers["blink"])


## The lamps on or off; while the alarm runs the light on top stays lit, brighter as the lamps blink on. A
## glow of the lamps' colour round the arch while they blink (red all through the alarm).
func _light(on: bool, running := false) -> void:
	var colour := RED if _red else GREEN
	_mat.albedo_color = colour if on else OFF
	_mat.emission = colour
	_mat.emission_enabled = on
	var alarm := running and _red
	_beacon_mat.albedo_color = RED if alarm else BEACON_OFF
	_beacon_mat.emission_enabled = alarm
	_beacon_mat.emission_energy_multiplier = 2.4 if on else 1.2
	if _glow:
		_glow.light_color = colour
		_glow.visible = alarm or (running and on)
		_glow.light_energy = GLOW * (1.0 if on else 0.45) if alarm else (GLOW * GREEN_GLOW if running and on else 0.0)
