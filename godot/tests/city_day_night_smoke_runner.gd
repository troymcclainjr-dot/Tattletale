extends Node
## Clock palette, surveyed lamp heads, and fixed nearby light budget.
const DayNight := preload("res://scripts/city/city_day_night.gd")
const WorldTime := preload("res://scripts/city/city_world_time.gd")
const Optimizer := preload("res://scripts/city/city_render_optimizer.gd")

class TestLevel:
	extends Node3D
	var world_time: Node
	var dressing_report: Dictionary = {}
	var traffic: Node = null
	var player: Node3D
	var streaming: Node = null

var passes := 0
var fails := 0

func _ready() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	if ok:
		passes += 1
	else:
		fails += 1
	print("[day_night] %s %s" % ["PASS" if ok else "FAIL", label])

func _run() -> void:
	var morning: Dictionary = DayNight.sample(9.0 * 60.0)
	var night: Dictionary = DayNight.sample(23.0 * 60.0)
	var dusk: Dictionary = DayNight.sample(18.5 * 60.0)
	check(is_equal_approx(float(morning.sun_energy), 1.0) and is_equal_approx(float(morning.ambient_energy), 0.52)
		and is_equal_approx(float(morning.fill_energy), 0.192) and is_zero_approx(float(morning.lamps)),
		"9am preserves existing daylight and keeps streetlights off")
	check(is_zero_approx(float(night.sun_energy)) and is_equal_approx(float(night.lamps), 1.0)
		and float(night.ambient_energy) >= 0.25, "night is lamp-lit but remains navigable")
	check(float(dusk.sun_energy) > 0.0 and float(dusk.sun_energy) < 1.0
		and float(dusk.lamps) > 0.5, "dusk crossfades sun and lamp sources")
	var before: Dictionary = DayNight.sample(19.0 * 60.0 - 0.01)
	var after: Dictionary = DayNight.sample(19.0 * 60.0 + 0.01)
	check(absf(float(before.sun_energy) - float(after.sun_energy)) < 0.001,
		"time-of-day curve is continuous across minute boundaries")

	var level := TestLevel.new()
	add_child(level)
	level.world_time = WorldTime.new()
	level.add_child(level.world_time)
	level.world_time.set_time(23.0 * 60.0)
	level.player = Node3D.new()
	level.player.position = Vector3(50, 0, 0)
	level.add_child(level.player)
	var world := WorldEnvironment.new()
	world.name = "WorldEnvironment"
	world.environment = Environment.new()
	world.environment.sky = Sky.new()
	world.environment.sky.sky_material = ProceduralSkyMaterial.new()
	level.add_child(world)
	var sun := DirectionalLight3D.new()
	sun.name = "LateAfternoonSun"
	level.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.name = "SkyFill"
	level.add_child(fill)
	var records: Array[Dictionary] = []
	for i in 12:
		var base := Vector3(float(i) * 10.0, 0, 0)
		records.append({"position": base, "head_position": base + Vector3(0, 4.758, 0.519),
			"yaw": 0.0, "source": "authored"})
	level.dressing_report = {"lamp_anchors": records}
	var controller := DayNight.new()
	level.add_child(controller)
	var status: Dictionary = controller.setup(level)
	var optimizer := Optimizer.new()
	level.add_child(optimizer)
	optimizer.level = level
	optimizer.city = level
	optimizer.set_quality("high")
	check(not sun.shadow_enabled and is_equal_approx(sun.directional_shadow_max_distance, 120.0)
		and sun.directional_shadow_mode == DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS,
		"quality selected at night configures the disabled sun without turning shadows on")
	check(bool(status.enabled) and int(status.lamp_anchors) == 12, "controller reads actual reported lamp heads")
	check(sun.sky_mode == DirectionalLight3D.SKY_MODE_LIGHT_ONLY
		and fill.sky_mode == DirectionalLight3D.SKY_MODE_LIGHT_ONLY
		and controller.sky_sun.sky_mode == DirectionalLight3D.SKY_MODE_SKY_ONLY
		and not fill.shadow_enabled and not controller.sky_sun.shadow_enabled,
		"only the physical sun and fill light the scene; one shadowless sun drives the sky")
	check(int(status.active_lights) == 8 and controller._pool.size() == 8, "night pool is capped at eight lights")
	var all_at_heads := true
	for lamp in controller._pool:
		if lamp.visible:
			var found := false
			for anchor in records:
				found = found or lamp.global_position.distance_to(anchor.head_position) < 0.001
			all_at_heads = all_at_heads and found and not lamp.shadow_enabled
	check(all_at_heads, "every active shadowless light is centered on an existing lens")
	var writes_before: int = controller.get_status().lighting_writes
	var sky_before: int = controller.get_status().sky_updates
	controller.tick(1.0)
	status = controller.get_status()
	check(int(status.lighting_writes) == writes_before and int(status.sky_updates) == sky_before,
		"a frozen clock does not rewrite lamp, sun, or sky resources")
	level.world_time.set_time(9.0 * 60.0)
	controller.tick(0.5)
	status = controller.get_status()
	check(is_equal_approx(sun.light_energy, 1.0) and sun.shadow_enabled,
		"daylight establishes direct sun and shadows before the night jump")
	check(is_equal_approx(sun.directional_shadow_max_distance, 120.0)
		and sun.directional_shadow_mode == DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS,
		"sunrise retains the quality selected during night")
	sky_before = int(status.sky_updates)
	level.world_time.set_time(22.0 * 60.0)
	controller.tick(0.05)
	for i in 9:
		controller.tick(0.05)
	status = controller.get_status()
	var pending_ok := is_zero_approx(sun.light_energy) and not sun.shadow_enabled and int(status.sky_updates) > sky_before
	if not pending_ok:
		print("[day_night] pending diagnostic: sun=%f shadow=%s sky=%d before=%d accumulated=%f last_sky_minute=%f" % [sun.light_energy, sun.shadow_enabled, status.sky_updates, sky_before, controller._sky_accum, controller._last_sky_minute])
	check(pending_ok,
		"a clock jump first sampled at 20 Hz still applies its pending night sky at 2 Hz")
	optimizer.set_quality("low")
	writes_before = int(status.lighting_writes)
	sky_before = int(status.sky_updates)
	controller.tick(0.5)
	status = controller.get_status()
	check(int(status.lighting_writes) == writes_before and int(status.sky_updates) == sky_before,
		"settled frozen night makes no new sky or light writes")
	level.world_time.set_time(9.0 * 60.0)
	controller.tick(0.3)
	status = controller.get_status()
	check(is_zero_approx(float(status.night_factor)) and int(status.active_lights) == 0,
		"streetlight pool shuts down by day without adding fixtures")
	controller.tick(0.2)
	check(sun.shadow_enabled and is_equal_approx(sun.directional_shadow_max_distance, 55.0)
		and sun.directional_shadow_mode == DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS,
		"a second night quality change takes effect at the following sunrise")
	level.world_time.set_time(17.0 * 60.0)
	controller.tick(0.5)
	var sky_angle: Vector3 = controller.sky_sun.rotation_degrees
	var sky_updates_before: int = controller.get_status().sky_updates
	var last_angle: Vector3 = sun.rotation_degrees
	var max_step := 0.0
	var physical_steps := 0
	for i in 200:
		level.world_time.tick(0.05)
		controller.tick(0.05)
		var current_angle: Vector3 = sun.rotation_degrees
		var step_size := current_angle.distance_to(last_angle)
		max_step = maxf(max_step, step_size)
		physical_steps += int(step_size > 0.0)
		last_angle = current_angle
		if i == 4:
			check(current_angle.distance_to(sky_angle) > 0.02
				and controller.sky_sun.rotation_degrees == sky_angle,
				"physical sun moves during a 0.25 s interval while sky sun stays fixed")
	check(physical_steps > 0 and max_step <= 0.05,
		"17:00 sun motion advances smoothly with at most 0.05 degree steps")
	check(int(controller.get_status().sky_updates) - sky_updates_before <= 20,
		"ten seconds of live time produces at most 20 sky updates")
	print("[day_night] %d passed, %d failed" % [passes, fails])
	get_tree().quit(0 if fails == 0 else 1)
