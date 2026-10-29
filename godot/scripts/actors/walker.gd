class_name Walker
extends RefCounted
## An NPC that walks (movement.js makeWalker): turns in place to face where it's going, then
## walks forward. Never sideways, never backwards.

var rig: Puppet
var r := 0.3
var x := 0.0           # [HUD] (W.dan)
var z := 0.0           # [HUD] (W.dan)
var yaw := 0.0
var speed := 1.0
var target = null      # [x, z] or null
var detour = null      # [x, z] or null
var moving := false
var waiting := 0.0
var visible := false
var body: Body
# Officer Dan's escort and Ricky's route
var escort = null      # [HUD] null | "follow" | "bust" | "home"
var lost := false      # [HUD]
var path: Array = []
var route: Array = []
var ri := 0


static func make(prig: Puppet, pr: float, pspeed: float) -> Walker:
	var w := Walker.new()
	w.rig = prig
	w.r = pr
	w.speed = pspeed
	return w
