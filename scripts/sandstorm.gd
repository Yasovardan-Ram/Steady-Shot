extends Node3D
## The look of a sandstorm: streaks of blown sand around the camera and a drifting, sand-coloured
## veil over the screen. The sky and fog are handled by DayNight; this node only adds the
## particles and the overlay. It listens for set_storm_factor (0..1), set_wind (direction of
## the sand) and set_night_factor (darker sand at night).

const OVERLAY_SHADER := """shader_type canvas_item;
uniform float strength = 0.0;
uniform float drift = 1.0;
uniform float dark = 0.0;
uniform vec3 sand : source_color = vec3(0.78, 0.6, 0.38);
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
void fragment() {
	vec2 uv = SCREEN_UV;
	float n = vnoise(uv * vec2(3.0, 5.0) + vec2(TIME * 0.9 * drift, TIME * 0.15)) * 0.6
			+ vnoise(uv * vec2(9.0, 14.0) + vec2(TIME * 2.4 * drift, 0.0)) * 0.4;
	float edge = smoothstep(0.2, 0.95, length(uv - vec2(0.5)) * 1.4);
	float a = strength * (0.10 + 0.28 * n + 0.22 * edge);
	vec3 col = sand * mix(1.0, 0.22, dark);
	COLOR = vec4(col, clamp(a, 0.0, 0.7));
}
"""

var _storm := 0.0
var _night := 0.0
var _wind_sign := 1.0
var _storm_time := 0.0
var _gust_phase := 0.0
var _particles: CPUParticles3D
var _particle_material: StandardMaterial3D
var _overlay_layer: CanvasLayer
var _overlay: ColorRect
var _overlay_material: ShaderMaterial


func _ready() -> void:
	add_to_group("storm_listeners")
	add_to_group("night_listeners")
	add_to_group("wind_listeners")
	_build_particles()
	_build_overlay()
	_update()


func set_storm_factor(s: float) -> void:
	_storm = s
	_update()


func set_night_factor(t: float) -> void:
	_night = t
	_update()


func set_wind(accel_x: float) -> void:
	if absf(accel_x) > 0.05:
		_wind_sign = signf(accel_x)
	_update_direction()


func _build_particles() -> void:
	_particles = CPUParticles3D.new()
	_particles.amount = 900
	_particles.lifetime = 1.8
	_particles.preprocess = 1.8
	_particles.local_coords = false
	_particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_particles.emission_box_extents = Vector3(45.0, 16.0, 55.0)
	_particles.gravity = Vector3.ZERO
	_particles.initial_velocity_min = 26.0
	_particles.initial_velocity_max = 46.0
	_particles.spread = 9.0
	_particles.scale_amount_min = 0.7
	_particles.scale_amount_max = 1.6
	_particles.set_particle_flag(CPUParticles3D.PARTICLE_FLAG_ALIGN_Y_TO_VELOCITY, true)
	var quad := QuadMesh.new()
	quad.size = Vector2(0.05, 0.9)
	_particle_material = StandardMaterial3D.new()
	_particle_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_particle_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_particle_material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	_particle_material.billboard_keep_scale = true
	_particle_material.vertex_color_use_as_albedo = true
	_particle_material.albedo_color = Color(0.85, 0.68, 0.45, 0.5)
	quad.material = _particle_material
	_particles.mesh = quad
	_particles.emitting = false
	add_child(_particles)
	_update_direction()


func _build_overlay() -> void:
	_overlay_layer = CanvasLayer.new()
	_overlay_layer.layer = -1    # above the 3D view, below the night-vision optic and the HUD
	add_child(_overlay_layer)
	var shader := Shader.new()
	shader.code = OVERLAY_SHADER
	_overlay_material = ShaderMaterial.new()
	_overlay_material.shader = shader
	_overlay = ColorRect.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.material = _overlay_material
	_overlay.visible = false
	_overlay_layer.add_child(_overlay)


func _update_direction() -> void:
	if _particles == null:
		return
	_particles.direction = Vector3(_wind_sign, 0.04, 0.3).normalized()
	if _overlay_material != null:
		_overlay_material.set_shader_parameter("drift", _wind_sign)


func _update() -> void:
	if _particles == null:
		return
	var dark := lerpf(1.0, 0.28, _night)
	_particles.color = Color(dark, dark, dark, clampf(_storm * 1.2, 0.0, 1.0))
	_particles.emitting = _storm > 0.02
	_overlay_material.set_shader_parameter("strength", _storm)
	_overlay_material.set_shader_parameter("dark", _night)
	_overlay.visible = _storm > 0.01


func _process(delta: float) -> void:
	_storm_time += delta
	_gust_phase = 0.5 + 0.5 * sin(_storm_time * 0.37 + sin(_storm_time * 0.13))
	if _overlay_material != null:
		# Gentle, irregular visibility variation: the storm breathes rather than
		# using a static brown screen tint.
		var pulse: float = _storm * (0.92 + 0.08 * _gust_phase)
		_overlay_material.set_shader_parameter("strength", pulse)
	if _particles != null and _storm > 0.01:
		var gust_scale: float = 0.88 + 0.12 * _gust_phase
		_particles.initial_velocity_min = 26.0 * gust_scale
		_particles.initial_velocity_max = 46.0 * gust_scale
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		# The sand streams past the player from upwind.
		global_position = cam.global_position + Vector3(-_wind_sign * 6.0, 0.0, -18.0)
