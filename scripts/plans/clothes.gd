extends RefCounted
## A clothing store: racks he can change his clothes at.
## NOT BUILT YET: this is a stand-in (a pavement and one bare room) so that the
## travel list has somewhere to go. Numbers are metres on the plan (see
## place.gd): u from the left wall, v from the back wall.

const Props := preload("res://scripts/props.gd")


static func build(p: Node3D) -> void:
	p.setup("CLOTHING STORE", 10.0, 8.0)
	var st: int = p.street(-4.0, 14.0)
	var b1: int = p.band()
	p.arrive = p.pt(5.0, 9.2)
	p.room("ROOM", b1, 0, 0, 10, 8, Kit.tex("lino", 1.2, Color(0.7, 0.68, 0.6)), {"light": Color(1.0, 0.95, 0.85), "energy": 0.6})
	p.cross(b1, 8.0, 0, 10, Kit.tex("brick", 1.5, Color(0.5, 0.26, 0.2)), [{"a": 4.5, "b": 5.5}], {"h": 3.2})
	p.side(b1, 0.0, 0, 8, Color(0.8, 0.78, 0.7))
	p.side(b1, 10.0, 0, 8, Color(0.8, 0.78, 0.7))
	p.cross(b1, 0.0, 0, 10, Color(0.8, 0.78, 0.7), [], {"back": true})
