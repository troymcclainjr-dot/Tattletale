class_name Interact
## The E key (interact.js): what 2-Pack can do where he's standing.


static func nearest_interact():
	var P := G.P
	if G.S.lock != null:
		return null
	for c in G.C.values():
		if not c.active or c.dispatched or c.handling:
			continue
		var a = c.act()
		if a:
			var d := Vector2(P.x - a.x, P.z - a.z).length()
			if d < a.r and d >= a.get("rmin", 0.0):
				return {"kind": "crime", "label": a.label, "fn": a.fn}
	for ph in G.W_.phones:
		if Vector2(P.x - ph.x, P.z - (ph.z + 0.55)).length() < 1.25:
			return {"kind": "phone", "ph": ph, "label": "Use payphone"}
	if Vector2(P.x - 36.2, P.z + 1.7).length() < 2.3:
		if G.car.state != "parked":
			return {"kind": "copsaway", "label": "Precinct 9 (cops out on a call)"}
		var getdan: bool = G.C.ricky.active and G.cur(G.C.ricky).k == "getdan"
		return {"kind": "cops", "label": "Get Officer Dan" if getdan else "Tell the cops"}
	return null


static func next_hint() -> String:
	var open := G.C.values().filter(func(c): return c.active and c.id != "gary" and not c.dispatched and not c.handling)
	open.sort_custom(func(a, b): return a.left < b.left)
	var c: Crime = open[0] if open.size() else G.C.gary
	return "%s: %s" % [G.short_name(c), G.step_text(G.cur(c))]


static func interact() -> void:
	if G.S.bino_on or G.S.lock != null:
		return
	var it = nearest_interact()
	if it == null:
		return
	if it.kind == "crime":
		it.fn.call()
		return
	if it.kind == "copsaway":
		Hud.toast("The cops are out on a call. Come back when the car's back.")
		return
	if it.kind == "phone" and G.C.cops.active and G.cur(G.C.cops).k == "call911":
		Minigames.call911(it.ph)
		return
	var r: Crime = G.C.ricky
	if it.kind == "cops" and r.active and G.cur(r).k == "getdan" and not G.W.dan.escort:
		Stage1Crimes.start_escort()
		return
	var ev := Crimes.pending_evidence()
	if ev.is_empty():
		Hud.say("TWOPACK", "Hold up. I need evidence first.", 1.8)
		Hud.toast("Nothing to call in yet. " + next_hint())
		return
	if it.kind == "cops":
		Hud.say("DAN", "Sir... we're on our lunch break.", 2.0)
		G.later(2.1, func(): _cops_dispatch())
		return
	Puzzles.open_puzzle(it.ph, ev)


static func _cops_dispatch() -> void:
	Hud.say("TWOPACK", "It's TEN in the MORNIN'!", 1.8)
	Crimes.dispatch(Crimes.pending_evidence().map(func(c): return c.id))
