extends "res://tests/city_residents_smoke_runner.gd"
## Reuses the full real-city resident/1200-ambient validation, with destination
## assertions at the same already-prepared route checkpoint.

func _capture_deployment(level: Node, provider: Node, safe_routes: bool) -> void:
	super._capture_deployment(level, provider, safe_routes)
	var destinations: Array[Dictionary] = []
	var valid := true
	var original_minute: float = level.world_time.minute_of_day
	for id in provider.routes:
		var route: Dictionary = provider.routes[id]
		if not route.has("destination"):
			continue
		var site: Dictionary = route.destination
		var point: Vector3 = route.points[route.anchors.leisure]
		valid = valid and point.distance_to(route.points[route.anchors.home]) >= 5.0
		var ray := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 1.3, site.focus + Vector3.UP * 1.3, 2 | 16)
		valid = valid and level.get_world_3d().direct_space_state.intersect_ray(ray).is_empty()
		if site.kind == "shop":
			var offset: Vector3 = point - site.focus
			valid = valid and Vector2(offset.x, offset.z).length() <= Residents.SHOP_FRONTAGE_RADIUS
			var open := false
			for entry in level.shops.definitions:
				if str(entry.id) == str(site.id):
					open = level.shops.is_entry_open(entry)
					valid = valid and site.focus.is_equal_approx(level.vector(entry.get("approach_start", entry.entry_world)))
			valid = valid and open and "outside" in str(site.label)
		else:
			var flat := Vector2(point.x, point.z)
			var polygon: PackedVector2Array = site.polygon
			var edge_distance := INF
			for edge in polygon.size():
				edge_distance = minf(edge_distance, flat.distance_to(Geometry2D.get_closest_point_to_segment(flat, polygon[edge], polygon[(edge + 1) % polygon.size()])))
			valid = valid and edge_distance <= Residents.COURT_VIEW_RADIUS
		destinations.append({"resident": id, "site": site.id, "kind": site.kind, "position": [point.x, point.y, point.z], "label": site.label})
	check(not destinations.is_empty(), "real-world leisure routes reach existing shop/court frontage")
	check(valid, "real destinations remain near actual open sites with clear sightlines and checked corridor access")
	check(provider.get_status().destination_build_queries <= 80, "destination selection adds at most two setup-only rays per resident")
	check(level.world_time.minute_of_day == original_minute, "destination selection does not change the world clock")
	print("[resident_destinations] ", JSON.stringify(destinations))
	deployment.real_destinations = destinations
