extends RefCounted
## Part of `--check-faces` (main.gd): nobody may stand about with eyes that cannot blink.
##
## Counts the people of a place whose face, as they were placed, shows an eye that cannot blink
## (paper_face.gd's BLINKING_EYES: a laugh's arcs, eyes shut in bliss, hearts, spirals). Eyes the
## drawing hides (shades) do not count. Then proves the rule behind it on each of them: every
## expression whose eyes cannot blink, left on someone who is not talking, settles into an open-eyed
## face by itself (paper_face.gd's "rest" and SETTLE). Everyone is put back as they were.

const PaperFace := preload("res://scripts/paper_face.gd")


static func report(people: Array) -> void:
	var shut := 0
	var faces := 0
	var tried := 0
	var stuck := 0
	for member: Dictionary in people:
		var who: Node3D = member["actor"]
		var face: Node3D = who.face
		if face == null:
			continue
		faces += 1
		if not face.can_blink():
			shut += 1
			print("[shot] faces: %s rests on \"%s\": its eyes cannot blink" % [who.name, face.expression])
		var was: String = face.expression
		var talked: bool = face.talking
		var held: bool = face.hold
		face.talking = false
		face.hold = false
		for name: String in PaperFace.EXPRESSIONS:
			if PaperFace.blinks(name):
				continue
			tried += 1
			face.set_expression(name, true)
			face._process(PaperFace.SETTLE + 0.05)
			face._process(0.2)          # the eyes open as from a blink
			if not PaperFace.blinks(face.expression) or face.expression != PaperFace.rest_of(name):
				stuck += 1
				print("[shot] faces: %s on \"%s\" did not settle (now \"%s\")" % [who.name, name, face.expression])
		face.talking = talked
		face.hold = held
		face.set_expression(was, true)
	print("[shot] faces: %d people here with faces, %d resting on a face that cannot blink" % [faces, shut])
	print("[shot] faces: a moment left on someone not talking settles: %d of %d tries did not" % [stuck, tried])
