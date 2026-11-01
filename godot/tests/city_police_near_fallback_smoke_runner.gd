extends "res://tests/city_police_cruisers_smoke_runner.gd"
## Run with --police-section=boxed_dispatch to reuse normal arena/init/contracts.
## Only this virtual section differs: near foot response, then blocked exits.

func _boxed_dispatch_section(_prefer_mobile := false) -> void:
	await _near_fallback(false)
	await _near_fallback(true)

func _near_fallback(block_doors: bool) -> void:
	var a: Node3D = police[0]
	var lane := lane_by("Middle Avenue", Vector3(0, 0, 1))
	reset_car(a, lane, 20.0)
	reset_car(police[1], lane_by("West Avenue", Vector3(0, 0, 1)), 15.0)
	await advance(0.05)
	var front := make_car("near_fallback_front", lane, 20.0 + Cruisers.CAR_LENGTH + 1.86, false)
	var rear := make_car("near_fallback_rear", lane, 20.0 - Cruisers.CAR_LENGTH - 1.0, false)
	if not check(front != null and rear != null, "near fallback has real front and rear vehicle blockers"):
		return
	extras.append(front)
	extras.append(rear)
	var scene := a.global_position + Vector3(11.0, 0.0, 35.0)
	put_player(scene)
	spawn("civ_caller_near_fallback", "mama", scene + Vector3(3, 0, -3), Vector3(-3, 0, 3))
	await advance(0.1)
	var claims_before := int(cruisers().counters.claims)
	var contacts_before := int(cruisers().counters.contacts)
	var start := a.global_position
	var candidates := limit_dispatch_to(a)
	law.on_offense("assault", scene + Vector3(0, 0, 1), "")
	put_player(HIDEOUT)
	var claimed: bool = await advance_until(func(): return owned(a), 3.0)
	restore_dispatch_candidates(candidates)
	if not check(claimed, "near fallback starts with its explicitly sole available cruiser"):
		await dismiss()
		return
	var waiting_for_exit := func() -> bool:
		var unit := unit_of(a)
		return not unit.is_empty() and str(unit.get("response_fallback", "")) == "foot" and str(unit.mode) == "hold"
	var fallback: bool = await advance_until(waiting_for_exit, Cruisers.PASS_WAIT + Cruisers.REVERSE_SECONDS + 4.0)
	if not check(fallback, "boxed nearby dispatch reaches a bounded real foot-exit attempt"):
		note("near fallback diagnostic: %s" % str(cruisers().get_status()))
		await dismiss()
		return
	if block_doors:
		# Obstruct all doors only after the reverse ends, so the dispatch was
		# genuinely boxed by vehicles rather than sensing an artificial wall.
		for spec in [[Vector3(-2.2, 1, 0), Vector3(1, 2, 10)],
			[Vector3(2.2, 1, 0), Vector3(1, 2, 10)],
			[Vector3(0, 1, 3.2), Vector3(4, 2, .25)],
			[Vector3(0, 1, -2.95), Vector3(4, 2, .25)]]:
			extras.append(box(a.global_transform * Vector3(spec[0]), spec[1], 2, float(a.yaw)))
		await get_tree().physics_frame
		var progress := {"replacement": "", "metres": 0.0}
		var alternative := func() -> bool:
			for unit in cruisers().units.values():
				if unit.car != a and owned(unit.car) and float(unit.odometer) > 1.0:
					progress.replacement = str(unit.vehicle_id)
					progress.metres = float(unit.odometer)
			return not str(progress.replacement).is_empty() and not owned(a)
		var replaced: bool = await advance_until(alternative, 8.0)
		check(replaced and int(cruisers().counters.claims) >= claims_before + 2,
			"blocked real exit attempts preserve the report and dispatch a physically moving alternative")
		check(not cruisers()._eligible(a) and str(cruisers().last_blocked_dispatch.get("action", "")) == "replacement",
			"blocked-door car remains in cooldown instead of reclaiming the dispatch")
		if not replaced:
			note("blocked exits diagnostic: %s %s" % [str(progress), str(cruisers().get_status())])
	else:
		var walking := {"start": Vector3.INF, "metres": 0.0, "gain": 0.0}
		var foot_progress := func() -> bool:
			var unit := unit_of(a)
			if unit.is_empty() or str(unit.mode) != "dismounted":
				return false
			var entry: Dictionary = cruisers().crew[int(unit.crew)]
			var actor: Node3D = entry.actor
			if str(entry.state) != "foot" or not law._responders.has(str(entry.id)):
				return false
			if not Vector3(walking.start).is_finite():
				walking.start = actor.global_position
			walking.metres = actor.global_position.distance_to(walking.start)
			walking.gain = Cruisers.flat(walking.start, unit.goal) - Cruisers.flat(actor.global_position, unit.goal)
			return float(walking.metres) > 1.0 and float(walking.gain) > .5 and actor.enabled and not actor.dead
		var walked: bool = await advance_until(foot_progress, 14.0)
		check(walked, "nearby fallback exits through a real door and its enlisted living officer walks toward the report")
		check(int(cruisers().counters.claims) == claims_before + 1,
			"successful foot response keeps one dispatch without unnecessary replacement claims")
		if not walked:
			note("foot progress diagnostic: %s %s" % [str(walking), str(cruisers().get_status())])
	check(a.global_position.distance_to(start) < .1 and int(cruisers().counters.contacts) == contacts_before,
		"near fallback never drives the boxed cruiser into traffic")
	section_clean("near fallback blocked doors" if block_doors else "near fallback real walking")
	await dismiss()
