extends Node
## Day / night. Every third wave is a night wave: the sky, sun, ambient light and fog fade to
## moonlight, stars come out, and other scripts that join the "night_listeners" group
## (scenery, ambience) get set_night_factor(0..1).
## Every fifth wave also brings a sandstorm: fog thickens to a sandy haze (day or night), the
## sky and light dim, and the "storm_listeners" group gets set_storm_factor(0..1).

signal night_changed(is_night: bool)

## Exponential fog density at full sandstorm; roughly 150 m of clear sight.
const STORM_FOG_DENSITY := 0.0085

var is_night := false
var is_storm := false
var night_factor := 0.0
var storm_factor := 0.0

var _env: Environment
var _sky: ProceduralSkyMaterial
var _sun: DirectionalLight3D
var _tween: Tween
var _storm_tween: Tween
var _star_material: StandardMaterial3D
var _day := {}
var _night := {}
var _day_quat := Quaternion.IDENTITY
var _night_quat := Quaternion.IDENTITY


func _ready() -> void:
	var envs := get_tree().root.find_children("*", "WorldEnvironment", true, false)
	var suns := get_tree().root.find_children("*", "DirectionalLight3D", true, false)
	if envs.is_empty() or suns.is_empty():
		push_warning("DayNight: environment or sun not found")
		return
	_env = envs[0].environment
	_sun = suns[0]
	_sky = _env.sky.sky_material as ProceduralSkyMaterial
	if _sky == null:
		push_warning("DayNight: sky is not a ProceduralSkyMaterial")
		return
	_day = {
		"sky_top": _sky.sky_top_color, "sky_horizon": _sky.sky_horizon_color,
		"ground_bottom": _sky.ground_bottom_color, "ground_horizon": _sky.ground_horizon_color,
		"ambient": _env.ambient_light_energy, "fog": _env.fog_light_color,
		"saturation": _env.adjustment_saturation,
		"sun_color": _sun.light_color, "sun_energy": _sun.light_energy,
		"fog_density": _env.fog_density, "fog_sky": _env.fog_sky_affect, "fog_scatter": _env.fog_sun_scatter,
	}
	_night = {
		"sky_top": Color(0.009, 0.016, 0.045), "sky_horizon": Color(0.038, 0.050, 0.105),
		"ground_bottom": Color(0.014, 0.016, 0.024), "ground_horizon": Color(0.026, 0.034, 0.060),
		"ambient": 0.36, "fog": Color(0.018, 0.024, 0.046),
		"saturation": 0.68,
		"sun_color": Color(0.48, 0.57, 0.82), "sun_energy": 0.28,
	}
	_day_quat = _sun.global_transform.basis.get_rotation_quaternion()
	_night_quat = Basis.looking_at(Vector3(0.35, -0.8, -0.5).normalized(), Vector3.UP).get_rotation_quaternion()
	_build_stars()
	_apply(0.0)


## Fades to night (true) or day (false). duration 0 switches instantly.
func set_night(night: bool, duration: float = 4.0) -> void:
	is_night = night
	if _env == null:
		return
	if _tween != null and _tween.is_valid():
		_tween.kill()
	var target := 1.0 if night else 0.0
	if duration <= 0.0 or is_equal_approx(night_factor, target):
		_apply(target)
	else:
		_tween = create_tween()
		_tween.tween_method(_apply, night_factor, target, duration)
	night_changed.emit(night)


func _apply(t: float) -> void:
	night_factor = t
	_refresh()
	get_tree().call_group("night_listeners", "set_night_factor", t)


## Fades the sandstorm in (true) or out (false). duration 0 switches instantly.
func set_storm(storm: bool, duration: float = 5.0) -> void:
	is_storm = storm
	if _env == null:
		return
	if _storm_tween != null and _storm_tween.is_valid():
		_storm_tween.kill()
	var target := 1.0 if storm else 0.0
	if duration <= 0.0 or is_equal_approx(storm_factor, target):
		_apply_storm(target)
	else:
		_storm_tween = create_tween()
		_storm_tween.tween_method(_apply_storm, storm_factor, target, duration)


func _apply_storm(s: float) -> void:
	storm_factor = s
	_refresh()
	get_tree().call_group("storm_listeners", "set_storm_factor", s)


## Combines the day/night blend and the sandstorm blend into the actual sky, light and fog.
func _refresh() -> void:
	var t := night_factor
	var s := storm_factor
	var sky_top: Color = _day["sky_top"].lerp(_night["sky_top"], t)
	var sky_horizon: Color = _day["sky_horizon"].lerp(_night["sky_horizon"], t)
	var ground_bottom: Color = _day["ground_bottom"].lerp(_night["ground_bottom"], t)
	var ground_horizon: Color = _day["ground_horizon"].lerp(_night["ground_horizon"], t)
	var fog_color: Color = _day["fog"].lerp(_night["fog"], t)
	var sun_color: Color = _day["sun_color"].lerp(_night["sun_color"], t)
	var sun_energy: float = lerpf(_day["sun_energy"], _night["sun_energy"], t)
	var ambient: float = lerpf(_day["ambient"], _night["ambient"], t)
	var saturation: float = lerpf(_day["saturation"], _night["saturation"], t)
	var fog_density: float = _day["fog_density"]
	var fog_sky: float = _day["fog_sky"]
	var fog_scatter: float = _day["fog_scatter"]
	if s > 0.0:
		# Sand in the air: a warm brown haze by day, a murky dark brown at night.
		var haze := Color(0.76, 0.58, 0.36).lerp(Color(0.17, 0.13, 0.10), t)
		sky_top = sky_top.lerp(haze * 0.85, s * 0.92)
		sky_horizon = sky_horizon.lerp(haze, s * 0.95)
		ground_horizon = ground_horizon.lerp(haze, s * 0.95)
		ground_bottom = ground_bottom.lerp(haze * 0.7, s * 0.9)
		fog_color = fog_color.lerp(haze, s)
		fog_density = lerpf(fog_density, STORM_FOG_DENSITY, s)
		fog_sky = lerpf(fog_sky, 1.0, s)
		fog_scatter = lerpf(fog_scatter, 0.0, s)
		sun_energy *= 1.0 - 0.22 * s
		sun_color = sun_color.lerp(haze.lightened(0.25), s * 0.6)
		ambient *= 1.0 + 0.35 * s
		saturation = lerpf(saturation, 0.85, s)
		_env.fog_enabled = true
	_sky.sky_top_color = sky_top
	_sky.sky_horizon_color = sky_horizon
	_sky.ground_bottom_color = ground_bottom
	_sky.ground_horizon_color = ground_horizon
	_env.ambient_light_energy = ambient
	_env.fog_light_color = fog_color
	_env.fog_density = fog_density
	_env.fog_sky_affect = fog_sky
	_env.fog_sun_scatter = fog_scatter
	_env.adjustment_saturation = saturation
	_sun.light_color = sun_color
	_sun.light_energy = sun_energy
	_sun.basis = Basis(_day_quat.slerp(_night_quat, t))
	if _star_material != null:
		_star_material.albedo_color = Color(1.0, 1.0, 1.0, smoothstep(0.3, 1.0, t) * (1.0 - s))


## A few hundred small billboards far away on a dome: the stars. Fog is switched off for them.
func _build_stars() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 424242
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	_star_material = StandardMaterial3D.new()
	_star_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_star_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_star_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_star_material.billboard_keep_scale = true
	_star_material.vertex_color_use_as_albedo = true
	_star_material.disable_fog = true
	_star_material.albedo_color = Color(1, 1, 1, 0)
	quad.material = _star_material
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = quad
	var count := 1400
	mm.instance_count = count
	var placed := 0
	while placed < count:
		var dir := Vector3(rng.randfn(0.0, 1.0), rng.randfn(0.0, 1.0), rng.randfn(0.0, 1.0))
		if dir.length() < 0.001:
			continue
		dir = dir.normalized()
		if dir.y < 0.06:
			continue
		var size := rng.randf_range(5.0, 13.0) * (1.0 + 2.0 * pow(rng.randf(), 12.0))
		var xf := Transform3D(Basis.from_scale(Vector3(size, size, size)), dir * 3600.0)
		mm.set_instance_transform(placed, xf)
		var warm := rng.randf()
		var bright := rng.randf_range(0.45, 1.0)
		mm.set_instance_color(placed, Color(1.0, 0.92 + warm * 0.08, 0.85 + (1.0 - warm) * 0.15, bright))
		placed += 1
	var inst := MultiMeshInstance3D.new()
	inst.multimesh = mm
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(inst)
	inst.global_position = Vector3(0.0, 40.0, -100.0)
