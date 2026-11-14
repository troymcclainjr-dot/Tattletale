extends RefCounted
## Things that grow, for the places out of doors. The trees and shrubs are the
## old Pen Lucy game's own models (assets/models/tree_a .. tree_d, shrub_a ..
## shrub_d: see the README); where a model is missing a plain stand-in of
## cylinders and balls is built instead, so a place still loads.
##
##   const Outdoor := preload("res://scripts/outdoor.gd")
##   Outdoor.tree(p, band, u, v, "a")            # a tree; its trunk is walked round
##   Outdoor.shrub(p, band, u, v, "b", 1.2)      # a shrub, 1.2 times its size

const MODELS := "res://assets/models/"
const LEAF := Color(0.3, 0.52, 0.27)
const BARK := Color(0.36, 0.26, 0.18)


## A tree standing at (u, v). kind: "a" to "d". `size` scales it; `turn` (degrees)
## turns it so that two of a kind do not look the same. The trunk takes up floor.
static func tree(p: Node3D, b: int, u: float, v: float, kind := "a", size := 1.0, turn := 0.0) -> Node3D:
	var g: Node3D = p.prop(b, u, v, 0.0, 0.5, 0.5)
	var model := _model("tree_" + kind)
	if model:
		model.scale = Vector3.ONE * size
		model.rotation_degrees.y = turn
		g.add_child(model)
		return g
	var h := 4.6 * size
	Kit.cyl(g, 0.16 * size, h * 0.5, Vector3(0, h * 0.25, 0), BARK, Vector3.ZERO, 7, 0.11 * size)
	Kit.ball(g, 1.5 * size, Vector3(0, h * 0.68, 0), LEAF, 8)
	Kit.ball(g, 1.05 * size, Vector3(0.75 * size, h * 0.84, 0.2 * size), LEAF.lightened(0.08), 7)
	Kit.ball(g, 0.95 * size, Vector3(-0.7 * size, h * 0.8, -0.2 * size), LEAF.darkened(0.08), 7)
	return g


## A shrub at (u, v). kind: "a" to "d". It takes up floor unless `solid` is false.
static func shrub(p: Node3D, b: int, u: float, v: float, kind := "a", size := 1.0, turn := 0.0, solid := true) -> Node3D:
	var g: Node3D = p.prop(b, u, v, 0.0, 0.8 * size, 0.8 * size, solid)
	var model := _model("shrub_" + kind)
	if model:
		model.scale = Vector3.ONE * size
		model.rotation_degrees.y = turn
		g.add_child(model)
		return g
	Kit.ball(g, 0.5 * size, Vector3(0, 0.4 * size, 0), LEAF.darkened(0.1), 7)
	Kit.ball(g, 0.36 * size, Vector3(0.3 * size, 0.5 * size, 0.1 * size), LEAF, 6)
	return g


static func _model(name: String) -> Node3D:
	var path := MODELS + name + ".glb"
	if not ResourceLoader.exists(path):
		return null
	var scene: PackedScene = load(path)
	return scene.instantiate() if scene else null
