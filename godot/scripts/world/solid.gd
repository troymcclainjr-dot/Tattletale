class_name Solid
extends RefCounted
## A collider in the 2D (x/z) collision world (world.js SOLIDS): a circle (c = 1) or a box (c = 0).

var c := 1
var x := 0.0
var z := 0.0
var r := 0.0
var x0 := 0.0
var x1 := 0.0
var z0 := 0.0
var z1 := 0.0


static func circle(px: float, pz: float, pr: float) -> Solid:
	var s := Solid.new()
	s.c = 1
	s.x = px
	s.z = pz
	s.r = pr
	return s


static func rect(px0: float, px1: float, pz0: float, pz1: float) -> Solid:
	var s := Solid.new()
	s.c = 0
	s.x0 = px0
	s.x1 = px1
	s.z0 = pz0
	s.z1 = pz1
	return s
