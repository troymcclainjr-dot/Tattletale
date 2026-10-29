extends "res://scripts/crimes/crime.gd"
## A crime with a fixed target, for the HUD harness.

var tpos := Vector3.ZERO


func target() -> Vector3:
	return tpos
