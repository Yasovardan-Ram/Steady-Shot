extends CharacterBody3D
## Sniper in the nest: slight movement inside barriers, mouse look, scope zoom,
## weapon sway, sensor-driven physiology influence and recoil. Knows nothing about enemies or score.

signal scope_toggled(active: bool)

## Start looking slightly down into the valley.
const START_PITCH_DEG := -7.0

@export var move_speed := 2.2
@export var acceleration := 20.0
@export var gravity := 20.0
@export var look_sensitivity := 0.0022
@export var base_fov := 75.0
@export var zoom_levels: Array[float] = [4.0, 8.0, 12.0]
@export var start_zoom_index := 1
## Allowed movement around the spawn point (metres): x range and z range.
@export var bounds_x := Vector2(-9.0, 9.0)
@export var bounds_z := Vector2(-1.7, 13.0)
## Rifle sway in degrees (angular, so it looks bigger the more you zoom).
@export var sway_degrees := 0.14
@export_group("Presage aim influence")
@export_range(0.0, 2.5, 0.05) var heart_rate_influence := 1.35
@export_range(0.0, 2.5, 0.05) var breathing_influence := 0.95
@export_range(0.1, 2.0, 0.05) var maximum_sensor_sway_multiplier := 1.8
@export_range(0.0, 100.0, 1.0) var confidence_threshold := 25.0
@export_range(40.0, 90.0, 1.0) var heart_rate_calm_bpm := 62.0
@export_range(80.0, 180.0, 1.0) var heart_rate_high_bpm := 115.0
@export_range(4.0, 18.0, 0.5) var breathing_rate_calm_bpm := 10.0
@export_range(14.0, 35.0, 0.5) var breathing_rate_high_bpm := 25.0
@export_range(1.0, 30.0, 1.0) var sensor_timeout_seconds := 8.0
@export_range(0.1, 10.0, 0.1) var sensor_smoothing := 2.8
@export_range(0.1, 5.0, 0.1) var sensor_recovery_speed := 1.25
## Upward view kick per shot, in degrees (a little less when scoped).
@export var recoil_kick_degrees := 1.7

var active := false
var is_scoped := false
var zoom_index := 1
var current_fov := 75.0
var scope_progress := 0.0
var heart_rate_bpm := NAN
var breathing_rate_bpm := NAN
var heart_confidence := 0.0
var breathing_confidence := 0.0
var heart_stable := false
var breathing_stable := false
var sensor_status := "FALLBACK · SENSOR NOT CONNECTED"
var _heart_target := NAN
var _breathing_target := NAN
var _heart_smoothed := NAN
var _breathing_smoothed := NAN
var _heart_age := 999.0
var _breathing_age := 999.0
var _previous_heart := NAN
var _previous_breathing := NAN
var _heart_rise := 0.0
var _breathing_change := 0.0
var _sensor_effect := 0.0
var _breath_phase := 0.0

var _origin := Vector3.ZERO
var _time := 0.0
var _recoil := 0.0
var _recoil_yaw := 0.0
var _recoil_target := 0.0
var _recoil_yaw_target := 0.0
var _shake := 0.0
var _fov_punch := 0.0
var _snd_in: AudioStream
var _snd_out: AudioStream
var _snd_step: AudioStream
var _move_factor := 0.0

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var weapon = $Head/Camera3D/Weapon
@onready var zoom_sound: AudioStreamPlayer = $ZoomSound


func _ready() -> void:
	_origin = global_position
	zoom_index = start_zoom_index
	current_fov = base_fov
	camera.fov = base_fov
	head.rotation.x = deg_to_rad(START_PITCH_DEG)
	weapon.fired.connect(_on_weapon_fired)
	weapon.reload_started.connect(_on_reload_started)
	_snd_step = zoom_sound.stream
	if ResourceLoader.exists("res://audio/scope_in.wav"):
		_snd_in = load("res://audio/scope_in.wav")
	if ResourceLoader.exists("res://audio/scope_out.wav"):
		_snd_out = load("res://audio/scope_out.wav")


func set_active(value: bool) -> void:
	active = value
	if not value and is_scoped:
		is_scoped = false


func reset() -> void:
	global_position = _origin
	velocity = Vector3.ZERO
	rotation = Vector3.ZERO
	head.rotation = Vector3(deg_to_rad(START_PITCH_DEG), 0.0, 0.0)
	is_scoped = false
	zoom_index = start_zoom_index
	heart_rate_bpm = NAN
	breathing_rate_bpm = NAN
	heart_confidence = 0.0
	breathing_confidence = 0.0
	_heart_age = 999.0
	_breathing_age = 999.0
	_heart_target = NAN
	_breathing_target = NAN
	_heart_smoothed = NAN
	_breathing_smoothed = NAN
	_previous_heart = NAN
	_previous_breathing = NAN
	_heart_rise = 0.0
	_breathing_change = 0.0
	_sensor_effect = 0.0
	_recoil = 0.0
	_recoil_yaw = 0.0
	_recoil_target = 0.0
	_recoil_yaw_target = 0.0
	_shake = 0.0
	_fov_punch = 0.0


func zoom_value() -> float:
	return zoom_levels[zoom_index]


func _zoom_to_fov(zoom: float) -> float:
	return rad_to_deg(2.0 * atan(tan(deg_to_rad(base_fov) * 0.5) / zoom))


func _unhandled_input(event: InputEvent) -> void:
	if not active or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventMouseMotion:
		# Mouse speed follows the visible field of view so aiming stays consistent when zoomed.
		var sens_scale := tan(deg_to_rad(current_fov) * 0.5) / tan(deg_to_rad(base_fov) * 0.5)
		rotate_y(-event.relative.x * look_sensitivity * sens_scale)
		head.rotation.x = clampf(head.rotation.x - event.relative.y * look_sensitivity * sens_scale,
				deg_to_rad(-80.0), deg_to_rad(60.0))
	elif event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_RIGHT:
				_toggle_scope()
			MOUSE_BUTTON_WHEEL_UP:
				_change_zoom(1)
			MOUSE_BUTTON_WHEEL_DOWN:
				_change_zoom(-1)


func _play_zoom_sound(stream: AudioStream) -> void:
	if stream == null:
		return
	zoom_sound.stream = stream
	zoom_sound.play()


func _toggle_scope() -> void:
	is_scoped = not is_scoped
	_play_zoom_sound(_snd_in if is_scoped else _snd_out)
	scope_toggled.emit(is_scoped)


## Reloading takes you off the scope, like in most shooters.
func _on_reload_started() -> void:
	if is_scoped:
		is_scoped = false
		_play_zoom_sound(_snd_out)
		scope_toggled.emit(false)


func _change_zoom(step: int) -> void:
	if not is_scoped:
		return
	var new_index := clampi(zoom_index + step, 0, zoom_levels.size() - 1)
	if new_index != zoom_index:
		zoom_index = new_index
		_play_zoom_sound(_snd_step)


func _on_weapon_fired() -> void:
	# The view snaps up and to a random side, then settles back over about a second.
	var kick_scale := lerpf(1.0, 0.55, scope_progress)
	_recoil_target += recoil_kick_degrees * kick_scale * randf_range(0.9, 1.15)
	_recoil_yaw_target += randf_range(-0.55, 0.55) * kick_scale
	_shake = 1.0
	_fov_punch = 1.0


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0

	var input_dir := Vector2.ZERO
	if active and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		input_dir.x = float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A))
		input_dir.y = float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W))
		input_dir = input_dir.normalized()

	var speed := move_speed * (0.4 if is_scoped else 1.0)
	var direction := global_transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)
	velocity.x = move_toward(velocity.x, direction.x * speed, acceleration * delta)
	velocity.z = move_toward(velocity.z, direction.z * speed, acceleration * delta)
	move_and_slide()

	# Hard limit: the player can only shuffle around the nest.
	global_position.x = clampf(global_position.x, _origin.x + bounds_x.x, _origin.x + bounds_x.y)
	global_position.z = clampf(global_position.z, _origin.z + bounds_z.x, _origin.z + bounds_z.y)

	_move_factor = clampf(Vector2(velocity.x, velocity.z).length() / move_speed, 0.0, 1.0)
	_update_sensor_state(delta)


func set_sensor_status(value: String) -> void:
	sensor_status = value

func set_sensor_metrics(packet: Dictionary) -> void:
	var hr = packet.get("heart_rate", null)
	var br = packet.get("breathing_rate", null)
	if hr is Dictionary and _valid_sensor_sample(hr):
		var pulse_value := float(hr.value)
		if pulse_value >= 35.0 and pulse_value <= 210.0:
			_heart_age = 0.0
			_heart_target = pulse_value
			heart_confidence = float(hr.get("confidence", 100.0))
			heart_stable = bool(hr.get("stable", false))
			if is_finite(_previous_heart):
				_heart_rise = clampf((pulse_value - _previous_heart) / 12.0, -1.0, 1.0)
			_previous_heart = pulse_value
	if br is Dictionary and _valid_sensor_sample(br):
		var breath_value := float(br.value)
		if breath_value >= 2.0 and breath_value <= 45.0:
			_breathing_age = 0.0
			_breathing_target = breath_value
			if is_finite(_previous_breathing):
				_breathing_change = clampf((breath_value - _previous_breathing) / 8.0, -1.0, 1.0)
			_previous_breathing = breath_value
			breathing_confidence = float(br.get("confidence", 100.0))
			breathing_stable = bool(br.get("stable", false))

func _valid_sensor_sample(sample: Dictionary) -> bool:
	if not sample.has("value") or not (sample.value is int or sample.value is float):
		return false
	var confidence := float(sample.get("confidence", 100.0))
	return is_finite(float(sample.value)) and confidence >= confidence_threshold

func _update_sensor_state(delta: float) -> void:
	_heart_age += delta
	_breathing_age += delta
	var heart_fresh := _heart_age <= sensor_timeout_seconds
	var breathing_fresh := _breathing_age <= sensor_timeout_seconds
	var target_effect := 0.0
	if heart_fresh and is_finite(_heart_target):
		if not is_finite(_heart_smoothed): _heart_smoothed = _heart_target
		_heart_smoothed = lerpf(_heart_smoothed, _heart_target, 1.0 - exp(-sensor_smoothing * delta))
		heart_rate_bpm = _heart_smoothed
		var hr_load := clampf(inverse_lerp(heart_rate_calm_bpm, maxf(heart_rate_high_bpm, heart_rate_calm_bpm + 1.0), _heart_smoothed), 0.0, 1.0)
		var hr_quality := clampf(heart_confidence / 75.0, 0.0, 1.0) * (1.0 if heart_stable else 0.72)
		target_effect += hr_load * hr_quality * heart_rate_influence
		if _heart_rise > 0.0:
			target_effect += _heart_rise * 0.28 * heart_rate_influence
		_heart_rise = move_toward(_heart_rise, 0.0, delta * 0.5)
	else:
		_heart_rise = move_toward(_heart_rise, 0.0, delta * 0.35)
	if breathing_fresh and is_finite(_breathing_target):
		if not is_finite(_breathing_smoothed): _breathing_smoothed = _breathing_target
		_breathing_smoothed = lerpf(_breathing_smoothed, _breathing_target, 1.0 - exp(-sensor_smoothing * delta))
		breathing_rate_bpm = _breathing_smoothed
		var br_load := clampf(inverse_lerp(breathing_rate_calm_bpm, maxf(breathing_rate_high_bpm, breathing_rate_calm_bpm + 1.0), _breathing_smoothed), 0.0, 1.0)
		var br_quality := clampf(breathing_confidence / 70.0, 0.0, 1.0) * (1.0 if breathing_stable else 0.75)
		target_effect += br_load * br_quality * breathing_influence
		target_effect += absf(_breathing_change) * 0.18 * br_quality * breathing_influence
		_breathing_change = move_toward(_breathing_change, 0.0, delta * 0.3)
	else:
		_breathing_change = move_toward(_breathing_change, 0.0, delta * 0.3)
	var rate := sensor_smoothing if target_effect > _sensor_effect else sensor_recovery_speed
	_sensor_effect = lerpf(_sensor_effect, target_effect, 1.0 - exp(-rate * delta))
	# After the timeout, fade the physiological difficulty back toward neutral (above),
	# but retain the last real rates for the subtle breathing/heart rhythm animation.
	# Never replace a once-measured value with the startup reference or an invented rate.
	if _heart_age > sensor_timeout_seconds * 2.0:
		_heart_smoothed = NAN
		_heart_target = NAN
		_previous_heart = NAN
	if _breathing_age > sensor_timeout_seconds * 2.0:
		_breathing_smoothed = NAN
		_breathing_target = NAN
		_previous_breathing = NAN
		_breathing_change = 0.0

func shot_consistency_score() -> float:
	# Without any real sensor sample, this shot is unrated rather than falsely
	# receiving a perfect score. The startup reference waveform is never used.
	var heart_fresh: bool = is_finite(heart_rate_bpm) and _heart_age <= sensor_timeout_seconds
	var breathing_fresh: bool = is_finite(breathing_rate_bpm) and _breathing_age <= sensor_timeout_seconds
	if not heart_fresh and not breathing_fresh:
		return NAN
	# A retrospective gameplay indicator, not a health score. It deliberately
	# measures physiology and player movement only; wind is not included.
	var maximum_load: float = maxf(heart_rate_influence + breathing_influence, 0.1)
	var physiology_load: float = clampf(_sensor_effect / maximum_load, 0.0, 1.0)
	var phase_penalty: float = 0.0
	if breathing_fresh:
		phase_penalty = 1.0 - absf(cos(_breath_phase))
	var movement_penalty: float = clampf(_move_factor, 0.0, 1.0)
	return clampf(100.0 - physiology_load * 52.0 - phase_penalty * 28.0 - movement_penalty * 12.0, 0.0, 100.0)


func shot_discipline_spread() -> float:
	# Firing remains possible at any time; unstable physiology and the active
	# breathing phase simply make the shot less predictable. There is no focus
	# button, hold-breath action, or temporary accuracy boost.
	var maximum_load: float = maxf(heart_rate_influence + breathing_influence, 0.1)
	var physiology_load: float = clampf(_sensor_effect / maximum_load, 0.0, 1.0)
	var phase_penalty: float = 0.0
	if is_finite(breathing_rate_bpm):
		var breath_pause_quality: float = absf(cos(_breath_phase))
		phase_penalty = 1.0 - breath_pause_quality
	return 0.06 + physiology_load * 0.48 + phase_penalty * 0.24


func _process(delta: float) -> void:
	_time += delta

	var target_fov := base_fov
	if is_scoped:
		target_fov = _zoom_to_fov(zoom_levels[zoom_index])
	current_fov = lerpf(current_fov, target_fov, 1.0 - exp(-14.0 * delta))
	_fov_punch = lerpf(_fov_punch, 0.0, 1.0 - exp(-10.0 * delta))
	camera.fov = current_fov * (1.0 + 0.04 * _fov_punch)

	var zoom_fov := _zoom_to_fov(zoom_levels[zoom_index])
	scope_progress = clampf(inverse_lerp(base_fov, zoom_fov, current_fov), 0.0, 1.0)
	weapon.set_model_visible(scope_progress < 0.5)
	weapon.spread_deg = (0.12 if is_scoped else 1.5) + shot_discipline_spread()

	# Sensor-driven sway is layered onto the original rifle movement and recoil.
	var amp := sway_degrees * (1.0 if is_scoped else 0.4)
	amp *= 1.0 + _move_factor * 2.5
	var sensor_multiplier := 1.0 + clampf(_sensor_effect, 0.0, heart_rate_influence + breathing_influence) * 0.72
	sensor_multiplier = minf(sensor_multiplier, maximum_sensor_sway_multiplier)
	amp *= sensor_multiplier
	var breathing_hz := maxf(breathing_rate_bpm if is_finite(breathing_rate_bpm) else 12.0, 2.0) / 60.0
	var has_breath_rate := is_finite(breathing_rate_bpm)
	var has_heart_rate := is_finite(heart_rate_bpm)
	var breath_phase := _time * TAU * breathing_hz
	_breath_phase = breath_phase
	var breath_wave := (sin(breath_phase) * 0.55 + sin(breath_phase * 2.0 + 0.4) * 0.16) if has_breath_rate else sin(_time * 1.25)
	var heart_tremor_hz := maxf(heart_rate_bpm if has_heart_rate else 72.0, 35.0) / 60.0
	var heart_tremor := sin(_time * TAU * heart_tremor_hz * 2.0) * 0.10 if has_heart_rate else 0.0
	var sway_pitch := sin(_time * 0.71) * 0.5 + sin(_time * 1.63 + 1.1) * 0.35 + sin(_time * 4.3 + 0.4) * 0.15 + breath_wave * 0.8 + heart_tremor
	var breathing_yaw := sin(breath_phase + 1.2) * 0.24 if has_breath_rate else 0.0
	var sway_yaw := sin(_time * 0.83 + 0.5) * 0.55 + sin(_time * 1.91 + 2.1) * 0.3 + sin(_time * 3.7) * 0.15 + breathing_yaw + heart_tremor * 0.6

	# Recoil: the target jumps on each shot and eases back slowly; the view follows it fast.
	_recoil_target = lerpf(_recoil_target, 0.0, 1.0 - exp(-2.4 * delta))
	_recoil_yaw_target = lerpf(_recoil_yaw_target, 0.0, 1.0 - exp(-2.4 * delta))
	_recoil = lerpf(_recoil, _recoil_target, 1.0 - exp(-28.0 * delta))
	_recoil_yaw = lerpf(_recoil_yaw, _recoil_yaw_target, 1.0 - exp(-28.0 * delta))
	_shake = lerpf(_shake, 0.0, 1.0 - exp(-12.0 * delta))
	camera.position = Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), 0.0) * 0.007 * _shake
	camera.rotation_degrees = Vector3(sway_pitch * amp + _recoil, sway_yaw * amp + _recoil_yaw, 0.0)
