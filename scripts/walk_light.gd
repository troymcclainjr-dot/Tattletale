extends Node3D
## Lamps that are plain until someone walks through a patch of floor, then
## blink green three times: the lamps on a metal detector's posts.
##
##   var lamps: Node3D = WalkLight.new()     # const WalkLight := preload("res://scripts/walk_light.gd")
##   lamps.zone = Rect2(...)                 # the floor between the posts, x and z in the world
##   parent.add_child(lamps)
##   lamps.add_lamp(size, where)             # as many as it has
##   place.watchers.append(lamps)            # the scene tells it where he is each frame

const OFF := Color(0.6, 0.61, 0.6)
const ON := Color(0.3, 0.95, 0.4)
const BLINKS := 3
const BLINK_TIME := 0.3          # seconds for one blink, on then off

var zone := Rect2()

var _mat: StandardMaterial3D
var _inside := false
var _left := 0.0                 # seconds of blinking still to run


func _init() -> void:
	_mat = StandardMaterial3D.new()     # its own, so one detector blinking does not light them all
	_mat.roughness = 1.0
	_mat.metallic_specular = 0.0
	_mat.emission = ON
	_mat.emission_energy_multiplier = 1.4
	_light(false)


## A lamp, `size` big, at `where` in this node. They all share one material, so they blink together.
func add_lamp(size: Vector3, where: Vector3) -> MeshInstance3D:
	return Kit.box(self, size, where, _mat)


## Where he is now. Stepping into the zone starts the blinking.
func watch(at: Vector3, delta: float) -> void:
	var inside := zone.has_point(Vector2(at.x, at.z))
	if inside and not _inside:
		_left = BLINKS * BLINK_TIME
	_inside = inside
	if _left <= 0.0:
		return
	_left -= delta
	_light(_left > 0.0 and fmod(BLINKS * BLINK_TIME - _left, BLINK_TIME) < BLINK_TIME * 0.6)


func _light(on: bool) -> void:
	_mat.albedo_color = ON if on else OFF
	_mat.emission_enabled = on
