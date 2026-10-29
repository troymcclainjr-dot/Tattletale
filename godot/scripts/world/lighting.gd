class_name Lighting
## The look (engine.js renderer, lights and fog, rebuilt for clay): sky-colored background and
## depth fog, a warm sun from the JS direction with soft shadows, sky ambient, SSAO, a gentle
## glow for the emissives, AgX, and a touch of far depth of field so the block reads as a
## miniature set.

const SKY := Color("#b9d0e4")
## What to feed the sky's horizon (HORIZON_IN) and the fog (SKY_IN) so both show SKY on screen
## through AgX and the color grade, and far things fade into the horizon (measured with
## tools/game_shot.gd --views calib_sky; redo both if the grade changes).
const HORIZON_IN := Color(0.768, 0.9817, 1.2471)
const SKY_IN := Color(0.8888, 0.9908, 1.0986)
## Sky ambient energy, scaled so the (brighter, calibrated) sky lights the clay about as much as the
## art previews' sky does at 0.75 (godot/tools/shot.gd), so the models keep the colors they were made with.
const AMBIENT := 0.55
const BOUNCE := Color("#d8c9b0")
const TOP := Color("#8fb4dc")
const GROUND := Color("#7d7a70")
const SUN_FROM := Vector3(14, 26, 12)


static func setup(root: Node3D) -> Dictionary:
	var env := Environment.new()
	# a real sky (metal and gloss need something to reflect): deeper blue overhead, SKY at the
	# horizon, warm grey below; ambient light and reflections come from it too
	env.background_mode = Environment.BG_SKY
	env.sky = Sky.new()
	env.sky.sky_material = sky_material()
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	# half sky, half a warm bounce card: shadows stay a little warm, like a lit set, not blue
	env.ambient_light_color = BOUNCE
	env.ambient_light_sky_contribution = 0.55
	env.ambient_light_energy = AMBIENT
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.0
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = SKY_IN
	env.fog_light_energy = 1.0
	env.fog_density = 1.0
	env.fog_depth_begin = 45.0
	env.fog_depth_end = 120.0
	env.fog_depth_curve = 1.0
	env.fog_sky_affect = 0.0
	env.fog_sun_scatter = 0.0
	env.ssao_enabled = true
	env.ssao_radius = 1.1
	env.ssao_intensity = 2.4
	env.ssao_power = 1.6
	env.ssao_detail = 0.6
	env.ssao_horizon = 0.06
	env.ssao_sharpness = 0.98
	env.ssao_light_affect = 0.12
	env.ssao_ao_channel_affect = 0.0
	env.glow_enabled = true
	env.glow_normalized = false
	env.glow_intensity = 0.55
	env.glow_strength = 0.95
	env.glow_bloom = 0.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.glow_hdr_threshold = 1.1
	env.glow_hdr_scale = 2.0
	env.adjustment_enabled = true
	env.adjustment_brightness = 1.0
	env.adjustment_contrast = 1.03
	env.adjustment_saturation = 1.06
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	root.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = Color("#fff0d8")
	sun.light_energy = 1.7
	sun.light_angular_distance = 1.5
	sun.shadow_enabled = true
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	sun.shadow_blur = 1.2
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 75.0
	sun.directional_shadow_split_1 = 0.07
	sun.directional_shadow_split_2 = 0.18
	sun.directional_shadow_split_3 = 0.42
	sun.directional_shadow_blend_splits = true
	sun.directional_shadow_fade_start = 0.85
	root.add_child(sun)
	sun.look_at_from_position(SUN_FROM, Vector3.ZERO, Vector3.UP)

	# a cool bounce card from the other side, like a stop-motion set's fill; no shadows
	var fill := DirectionalLight3D.new()
	fill.name = "Fill"
	fill.light_color = Color("#c4d6ff")
	fill.light_energy = 0.22
	fill.light_specular = 0.0
	fill.shadow_enabled = false
	root.add_child(fill)
	fill.look_at_from_position(Vector3(-16, 9, 10), Vector3.ZERO, Vector3.UP)

	var cam := Camera3D.new()
	cam.name = "Camera"
	cam.near = 0.1
	cam.far = 300.0
	cam.fov = 55.0
	var attr := CameraAttributesPractical.new()
	attr.dof_blur_far_enabled = true
	attr.dof_blur_far_distance = 32.0
	attr.dof_blur_far_transition = 40.0
	attr.dof_blur_near_enabled = false
	attr.dof_blur_amount = 0.04
	cam.attributes = attr
	root.add_child(cam)
	cam.current = true
	return {"cam": cam, "env": env, "sun": sun, "attr": attr}


## The sky: a deeper blue overhead fading to the horizon color. Past the edge of the set (below the
## horizon) the screen shows the horizon color, like the JS's flat sky, while the radiance pass
## (reflections and ambient light) sees warm ground down there. Horizon fed HORIZON_IN, zenith
## scaled to keep the TOP/SKY ratio.
const SKY_SHADER := """
shader_type sky;
render_mode use_debanding;
uniform vec4 top_color : source_color;
uniform vec4 horizon_color : source_color;
uniform vec4 ground_color : source_color;
uniform float sky_curve = 0.15;
uniform float ground_curve = 0.04;

void sky() {
	float v = acos(clamp(EYEDIR.y, -1.0, 1.0));
	float c = 1.0 - v / (PI * 0.5);
	vec3 col = mix(horizon_color.rgb, top_color.rgb, clamp(1.0 - pow(1.0 - c, 1.0 / sky_curve), 0.0, 1.0));
	if (EYEDIR.y < 0.0) {
		col = horizon_color.rgb;
		if (AT_CUBEMAP_PASS) {
			float g = (v - PI * 0.5) / (PI * 0.5);
			col = mix(horizon_color.rgb, ground_color.rgb, clamp(1.0 - pow(1.0 - g, 1.0 / ground_curve), 0.0, 1.0));
		}
	}
	COLOR = col;
}
"""

static var _sky_shader: Shader


static func sky_material(horizon := HORIZON_IN) -> ShaderMaterial:
	if _sky_shader == null:
		_sky_shader = Shader.new()
		_sky_shader.code = SKY_SHADER
	var m := ShaderMaterial.new()
	m.shader = _sky_shader
	var k := horizon.srgb_to_linear()
	var t := TOP.srgb_to_linear()
	var s := SKY.srgb_to_linear()
	m.set_shader_parameter("top_color", Color(t.r / s.r * k.r, t.g / s.g * k.g, t.b / s.b * k.b).linear_to_srgb())
	m.set_shader_parameter("horizon_color", horizon)
	m.set_shader_parameter("ground_color", GROUND)
	return m
