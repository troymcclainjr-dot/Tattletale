extends Node
## Time-of-day lighting for Pen Lucy. The level owns the clock and calls tick().
## Street fixtures stay where CityDressing placed them; only eight nearby,
## shadowless lights are resident, while all real lamp lenses share one material.

const Dressing := preload("res://scripts/city/city_dressing.gd")
const SkyVisual := preload("res://scripts/city/city_sky.gd")
const MAX_STREET_LIGHTS := 8
const LAMP_REACH := 65.0
const LIGHT_INTERVAL := 0.05
const SKY_INTERVAL := 0.5
const POOL_INTERVAL := 0.25
const INTERVAL_EPSILON := 0.000001
const DAY_TOP := Color("719bac")
const DAY_HORIZON := Color("d4d8c5")
const NIGHT_TOP := Color("192a3c")
const NIGHT_HORIZON := Color("455265")
const DUSK_HORIZON := Color("b88d7b")
const DAY_FOG := Color("c7d2c7")
const NIGHT_FOG := Color("687581")
const DAY_SUN := Color("ffe0af")
const DUSK_SUN := Color("ffae79")
const DAY_FILL := Color("b7d8e8")
const NIGHT_FILL := Color("9db9d3")

var level: Node3D
var clock: Node
var environment: Environment
var sky: Sky
var atmosphere: ProceduralSkyMaterial
var sky_visual: ShaderMaterial
var cloud_quality := SkyVisual.DEFAULT_CLOUD_QUALITY
var sun: DirectionalLight3D
var fill: DirectionalLight3D
var sky_sun: DirectionalLight3D
var _lens_material: StandardMaterial3D
var _anchors: Array[Dictionary] = []
var _pool: Array[OmniLight3D] = []
var _selected: Dictionary = {}
var _lighting_accum := 0.0
var _sky_accum := 0.0
var _pool_accum := 0.0
var _night_factor := 0.0
var _sky_updates := 0
var _pool_updates := 0
var _lighting_writes := 0
var _last_sample_minute := -1.0
var _last_sky_minute := -1.0

func setup(owner_level: Node3D) -> Dictionary:
	level = owner_level
	clock = level.get("world_time") as Node
	for candidate in level.find_children("*", "WorldEnvironment", true, false):
		var world := candidate as WorldEnvironment
		if world != null:
			environment = world.environment
			break
	sun = level.get_node_or_null("LateAfternoonSun") as DirectionalLight3D
	fill = level.get_node_or_null("SkyFill") as DirectionalLight3D
	if environment == null or sun == null or fill == null or clock == null:
		return {"enabled": false, "reason": "world clock or existing environment lights unavailable"}
	# The moving shadow caster and fill affect the scene only. A separate,
	# shadowless light drives the procedural sky on its slower cadence.
	sun.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	fill.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	fill.shadow_enabled = false
	if sky_sun == null:
		sky_sun = DirectionalLight3D.new()
		sky_sun.name = "SkySun"
		sky_sun.sky_mode = DirectionalLight3D.SKY_MODE_SKY_ONLY
		sky_sun.shadow_enabled = false
		add_child(sky_sun)
	sky_sun.rotation_degrees = sun.rotation_degrees
	sky_sun.light_color = sun.light_color
	sky_sun.light_energy = sun.light_energy
	sky = environment.sky
	if sky != null:
		atmosphere = sky.sky_material as ProceduralSkyMaterial
		# Sky radiance regeneration is more expensive than interpolating light
		# uniforms. Spread updates over frames and keep a modest cubemap.
		sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
		sky.radiance_size = Sky.RADIANCE_SIZE_128
		sky_visual = SkyVisual.create_material(cloud_quality)
		sky.sky_material = sky_visual
		atmosphere = null
	_collect_anchors()
	_setup_lens_material()
	for i in MAX_STREET_LIGHTS:
		var lamp := OmniLight3D.new()
		lamp.name = "NearbyStreetLight_%d" % i
		lamp.light_color = Color("ffe0a6")
		lamp.light_energy = 0.0
		lamp.light_specular = 0.25
		lamp.omni_range = 11.5
		lamp.omni_attenuation = 1.25
		lamp.shadow_enabled = false
		lamp.visible = false
		add_child(lamp)
		_pool.append(lamp)
	_apply_lighting(true)
	_update_pool()
	return get_status()

func tick(delta: float) -> void:
	if clock == null or environment == null or delta <= 0.0:
		return
	_lighting_accum += delta
	_sky_accum += delta
	_pool_accum += delta
	var lighting_due := _lighting_accum + INTERVAL_EPSILON >= LIGHT_INTERVAL
	var sky_due := _sky_accum + INTERVAL_EPSILON >= SKY_INTERVAL
	if lighting_due or sky_due:
		if lighting_due:
			_lighting_accum = _remaining_interval(_lighting_accum, LIGHT_INTERVAL)
		if sky_due:
			_sky_accum = _remaining_interval(_sky_accum, SKY_INTERVAL)
		_apply_lighting(sky_due)
	if _pool_accum + INTERVAL_EPSILON >= POOL_INTERVAL:
		_pool_accum = _remaining_interval(_pool_accum, POOL_INTERVAL)
		_update_pool()

static func _remaining_interval(accumulated: float, interval: float) -> float:
	# Consume all complete intervals, including a nearly exact floating-point
	# boundary. One latest-state update is sufficient after a long frame.
	var periods := floori((accumulated + INTERVAL_EPSILON) / interval)
	return maxf(0.0, accumulated - float(periods) * interval)

static func _smooth(a: float, b: float, value: float) -> float:
	var t: float = clampf((value - a) / (b - a), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)

static func sample(minute_of_day: float) -> Dictionary:
	var hour: float = fposmod(minute_of_day, 1440.0) / 60.0
	var day: float = _smooth(6.0, 8.5, hour) * (1.0 - _smooth(17.3, 19.6, hour))
	var morning: float = _smooth(5.8, 6.8, hour) * (1.0 - _smooth(7.3, 8.5, hour))
	var evening: float = _smooth(17.0, 18.2, hour) * (1.0 - _smooth(19.3, 20.3, hour))
	var twilight: float = maxf(morning, evening)
	var lamps: float = maxf(1.0 - _smooth(5.5, 7.0, hour), _smooth(17.6, 19.0, hour))
	var elevation: float = 60.811 * sin(PI * clampf((hour - 6.0) / 12.0, 0.0, 1.0))
	var yaw: float = -74.0 + clampf(hour - 6.0, 0.0, 12.0) * 14.0
	return {"hour": hour, "day": day, "twilight": twilight, "lamps": lamps,
		"sun_energy": day * (1.0 - 0.26 * twilight), "sun_elevation": elevation,
		"sun_yaw": yaw, "ambient_energy": lerpf(0.27, 0.52, day),
		"fill_energy": lerpf(0.11, 0.192, day),
		"fog_density": lerpf(0.0008, 0.00055, day)}

func _apply_lighting(update_sky: bool) -> void:
	var minute: float = float(clock.get("minute_of_day"))
	var sample_changed := _last_sample_minute < 0.0 or not is_equal_approx(minute, _last_sample_minute)
	var sky_pending := update_sky and (_last_sky_minute < 0.0 or not is_equal_approx(minute, _last_sky_minute))
	if not sample_changed and not sky_pending:
		return
	var state := sample(minute)
	if sample_changed:
		_last_sample_minute = minute
	var day: float = state.day
	var twilight: float = state.twilight
	_night_factor = float(state.lamps)
	if absf(environment.ambient_light_energy - float(state.ambient_energy)) > 0.0001:
		environment.ambient_light_energy = float(state.ambient_energy)
		_lighting_writes += 1
	var fog_color := NIGHT_FOG.lerp(DAY_FOG, day).lerp(DUSK_HORIZON, twilight * 0.22)
	if not environment.fog_light_color.is_equal_approx(fog_color):
		environment.fog_light_color = fog_color
		_lighting_writes += 1
	if absf(environment.fog_density - float(state.fog_density)) > 0.0000002:
		environment.fog_density = float(state.fog_density)
		_lighting_writes += 1
	if _lens_material != null:
		var emission := lerpf(1.0, 3.0, _night_factor)
		if absf(_lens_material.emission_energy_multiplier - emission) > 0.0001:
			_lens_material.emission_energy_multiplier = emission
			_lighting_writes += 1
	for lamp in _pool:
		var energy := 1.3 * _night_factor
		if absf(lamp.light_energy - energy) > 0.0001:
			lamp.light_energy = energy
			_lighting_writes += 1
	var sun_energy: float = state.sun_energy
	if absf(sun.light_energy - sun_energy) > 0.0001:
		sun.light_energy = sun_energy
		_lighting_writes += 1
	var sun_color := DAY_SUN.lerp(DUSK_SUN, twilight)
	if not sun.light_color.is_equal_approx(sun_color):
		sun.light_color = sun_color
		_lighting_writes += 1
	var shadows: bool = sun_energy > 0.08
	if sun.shadow_enabled != shadows:
		sun.shadow_enabled = shadows
		_lighting_writes += 1
	var fill_energy: float = state.fill_energy
	if absf(fill.light_energy - fill_energy) > 0.0001:
		fill.light_energy = fill_energy
		_lighting_writes += 1
	var fill_color := NIGHT_FILL.lerp(DAY_FILL, day)
	if not fill.light_color.is_equal_approx(fill_color):
		fill.light_color = fill_color
		_lighting_writes += 1
	var sun_angle := Vector3(-float(state.sun_elevation), float(state.sun_yaw), 0.0)
	if sun.rotation_degrees.distance_to(sun_angle) > 0.02:
		sun.rotation_degrees = sun_angle
		_lighting_writes += 1
	if sky_pending:
		_last_sky_minute = minute
		var sky_changed := false
		if absf(sky_sun.light_energy - sun_energy) > 0.0001:
			sky_sun.light_energy = sun_energy
			sky_changed = true
		if not sky_sun.light_color.is_equal_approx(sun_color):
			sky_sun.light_color = sun_color
			sky_changed = true
		if sky_sun.rotation_degrees.distance_to(sun_angle) > 0.2:
			sky_sun.rotation_degrees = sun_angle
			sky_changed = true
		if atmosphere != null:
			var top := NIGHT_TOP.lerp(DAY_TOP, day)
			var horizon := NIGHT_HORIZON.lerp(DAY_HORIZON, day).lerp(DUSK_HORIZON, twilight * 0.65)
			var bottom := Color("343d43").lerp(Color("696e64"), day)
			if not atmosphere.sky_top_color.is_equal_approx(top):
				atmosphere.sky_top_color = top
				sky_changed = true
			if not atmosphere.sky_horizon_color.is_equal_approx(horizon):
				atmosphere.sky_horizon_color = horizon
				sky_changed = true
			if not atmosphere.ground_horizon_color.is_equal_approx(horizon):
				atmosphere.ground_horizon_color = horizon
				sky_changed = true
			if not atmosphere.ground_bottom_color.is_equal_approx(bottom):
				atmosphere.ground_bottom_color = bottom
				sky_changed = true
		if sky_visual != null:
			# Lights emit along local -Z: +Z points toward the visible sun.
			SkyVisual.apply(sky_visual, state, minute, sun.global_basis.z)
			sky_changed = true
		if sky_changed:
			_sky_updates += 1

func set_cloud_quality(value: int) -> void:
	var quality := clampi(value, 0, 2)
	if quality == cloud_quality:
		return
	cloud_quality = quality
	if sky_visual != null:
		sky_visual.set_shader_parameter("cloud_quality", cloud_quality)


func _collect_anchors() -> void:
	_anchors.clear()
	var authored: Dictionary = level.get("dressing_report")
	var lists: Array = [authored.get("lamp_anchors", [])]
	var traffic = level.get("traffic")
	if is_instance_valid(traffic):
		lists.append(traffic.street_details.get("lamp_anchors", []))
	for source in lists:
		for record in source:
			if not record is Dictionary:
				continue
			var base = record.get("position")
			if not base is Vector3 or not base.is_finite():
				continue
			var head = record.get("head_position")
			if not head is Vector3:
				head = base + Basis(Vector3.UP, float(record.get("yaw", 0.0))) * Dressing.LAMP_LENS_LOCAL
			if not head.is_finite():
				continue
			var duplicate := false
			for prior in _anchors:
				if (prior.position as Vector3).distance_squared_to(base) < 1.0:
					duplicate = true
					break
			if not duplicate:
				_anchors.append({"position": base, "head_position": head, "source": str(record.get("source", "unknown"))})

func _setup_lens_material() -> void:
	var mesh := Dressing.source_lamp_mesh()
	if mesh == null:
		return
	for surface in mesh.get_surface_count():
		var existing: Material = mesh.surface_get_material(surface)
		if existing == null or not existing.resource_name.begins_with("glow_ffe6b0"):
			continue
		if existing is StandardMaterial3D:
			_lens_material = existing.duplicate() as StandardMaterial3D
		else:
			_lens_material = StandardMaterial3D.new()
			_lens_material.albedo_color = Color("ffe6b0")
			_lens_material.roughness = 0.4
		_lens_material.emission_enabled = true
		_lens_material.emission = Color("ffe6b0")
		mesh.surface_set_material(surface, _lens_material)
		break

func _select_nearest(center: Vector3) -> Array[int]:
	var candidates: Array[Dictionary] = []
	for i in _anchors.size():
		var anchor: Vector3 = _anchors[i].position
		var distance_sq := Vector2(center.x - anchor.x, center.z - anchor.z).length_squared()
		if distance_sq <= LAMP_REACH * LAMP_REACH:
			# A small stable preference prevents selection chatter at rank eight.
			candidates.append({"index": i, "score": distance_sq - (25.0 if _selected.has(i) else 0.0)})
	candidates.sort_custom(_candidate_less)
	var result: Array[int] = []
	for i in mini(MAX_STREET_LIGHTS, candidates.size()):
		result.append(int(candidates[i].index))
	return result

func _candidate_less(a: Dictionary, b: Dictionary) -> bool:
	if is_equal_approx(float(a.score), float(b.score)):
		return int(a.index) < int(b.index)
	return float(a.score) < float(b.score)

func _update_pool() -> void:
	_pool_updates += 1
	if _night_factor < 0.02 or _anchors.is_empty():
		for lamp in _pool:
			lamp.visible = false
		_selected.clear()
		return
	var player = level.get("player")
	if not is_instance_valid(player):
		return
	var center: Vector3 = player.global_position
	var inspector = level.get("inspector")
	if inspector != null and inspector.active:
		center = inspector.streaming_focus()
	var nearest := _select_nearest(center)
	_selected.clear()
	for i in _pool.size():
		var lamp := _pool[i]
		lamp.visible = i < nearest.size()
		if i < nearest.size():
			var index: int = nearest[i]
			_selected[index] = true
			lamp.global_position = _anchors[index].head_position

func get_status() -> Dictionary:
	return {"enabled": clock != null and environment != null and sun != null and fill != null and sky_sun != null,
		"minute_of_day": float(clock.get("minute_of_day")) if clock != null else 0.0,
		"night_factor": _night_factor, "lamp_anchors": _anchors.size(),
		"active_lights": _selected.size(), "max_lights": MAX_STREET_LIGHTS,
		"shared_lens_material": _lens_material != null, "sky_updates": _sky_updates,
		"cloud_quality": cloud_quality, "cloud_samples": 8 if cloud_quality == 2 else cloud_quality,
		"pool_updates": _pool_updates, "lighting_writes": _lighting_writes}
