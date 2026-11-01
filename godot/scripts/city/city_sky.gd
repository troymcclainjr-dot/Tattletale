extends RefCounted
## Visible sky only. World lighting presets and streetlight budgets stay owned
## by CityDayNight; this helper is called on its existing 0.5-second cadence.
const SHADER := preload("res://assets/materials/city_sky.gdshader")
const DEFAULT_CLOUD_QUALITY := 2 # Quarter-resolution volume validated in two full-city 1080p views.

static func create_material(quality: int = DEFAULT_CLOUD_QUALITY) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter("cloud_quality", clampi(quality, 0, 2))
	return material

static func apply(material: ShaderMaterial, state: Dictionary, minute: float, direction: Vector3) -> void:
	var day: float = state.day
	var twilight: float = state.twilight
	material.set_shader_parameter("sky_top", Color("192a3c").lerp(Color("719bac"), day))
	material.set_shader_parameter("horizon", Color("455265").lerp(Color("d4d8c5"), day).lerp(Color("b88d7b"), twilight * 0.65))
	material.set_shader_parameter("ground_bottom", Color("343d43").lerp(Color("696e64"), day))
	material.set_shader_parameter("sun_direction", direction.normalized())
	material.set_shader_parameter("sun_color", Color("ffe0af").lerp(Color("ffae79"), twilight))
	material.set_shader_parameter("sun_strength", float(state.sun_energy))
	material.set_shader_parameter("cloud_lit", Color("596777").lerp(Color("f0f0e2"), day).lerp(Color("d3aa92"), twilight * 0.52))
	material.set_shader_parameter("cloud_shade", Color("29394c").lerp(Color("859ba3"), day).lerp(Color("8a7881"), twilight * 0.35))
	# Closed daily orbit avoids a midnight seam; frozen world time freezes clouds.
	var phase := fposmod(minute, 1440.0) * TAU / 1440.0
	material.set_shader_parameter("cloud_drift", Vector2(sin(phase), cos(phase)) * 1.8)
