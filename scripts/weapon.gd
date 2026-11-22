extends Node3D
## Bolt-action sniper rifle: 6-round magazine, bolt cycle between shots,
## automatic reload when empty, ballistic bullets zeroed at a set range.
## It does not know about enemies, score or UI.

signal fired
signal dry_fired
signal ammo_changed(ammo: int, capacity: int)
signal reload_started
signal reload_finished

@export var bullet_scene: PackedScene
@export var capacity := 6
@export var bolt_time := 1.15
@export var reload_time := 3.2
@export var muzzle_velocity := 420.0
@export var zero_range := 150.0
@export var gravity := 9.81
@export var recoil_kick := 0.07

var enabled := false
var ammo := 6
var is_reloading := false
var spread_deg := 0.0
var wind := Vector3.ZERO

var _bolt_timer := 0.0
var _reload_timer := 0.0
var _anim: Tween
var _flash_token := 0
var _bolt_rest := Vector3.ZERO
var _mag_rest := Vector3.ZERO
var _mag_tween: Tween
var _shot_variants: Array[AudioStream] = []
var _bolt_tween: Tween
var _bolt_token := 0
var _reload_delay := 0.0
var _rest_pos := Vector3.ZERO
var _look_sway := Vector2.ZERO
var _kick := 0.0
var _raise := 1.0
var _time := 0.0
var _walk_phase := 0.0
var _player = null
var _brass_material: StandardMaterial3D
var _casing_mesh: CylinderMesh

@onready var model: Node3D = $Model
@onready var bolt_handle: Node3D = $Model/BoltHandle
@onready var muzzle_flash: Node3D = $Model/MuzzleFlash
@onready var shot_sound: AudioStreamPlayer = $ShotSound
@onready var bolt_sound: AudioStreamPlayer = $BoltSound
@onready var reload_sound: AudioStreamPlayer = $ReloadSound
@onready var dry_sound: AudioStreamPlayer = $DrySound


func _ready() -> void:
	ammo = capacity
	_rest_pos = position
	_player = get_node_or_null("../../..")
	_brass_material = StandardMaterial3D.new()
	_brass_material.albedo_color = Color(0.8, 0.58, 0.2)
	_brass_material.metallic = 1.0
	_brass_material.roughness = 0.3
	_casing_mesh = CylinderMesh.new()
	_casing_mesh.top_radius = 0.0055
	_casing_mesh.bottom_radius = 0.0065
	_casing_mesh.height = 0.052
	_casing_mesh.radial_segments = 8
	_casing_mesh.rings = 1
	_casing_mesh.material = _brass_material
	_bolt_rest = bolt_handle.position
	muzzle_flash.visible = false
	var mag := model.get_node_or_null("Magazine") as Node3D
	if mag != null:
		_mag_rest = mag.position
	shot_sound.max_polyphony = 2
	for i in range(1, 4):
		var path := "res://audio/sniper_shot_%d.wav" % i
		if ResourceLoader.exists(path):
			var s = load(path)
			if s is AudioStream:
				_shot_variants.append(s)


func set_model_visible(value: bool) -> void:
	model.visible = value


func reset() -> void:
	_kill_anim()
	ammo = capacity
	is_reloading = false
	_bolt_timer = 0.0
	_reload_timer = 0.0
	_reload_delay = 0.0
	_raise = 1.0   # the rifle is raised into view
	ammo_changed.emit(ammo, capacity)


func refill() -> void:
	if not is_reloading:
		ammo = capacity
		ammo_changed.emit(ammo, capacity)


func is_bolt_cycling() -> bool:
	return _bolt_timer > 0.0 and not is_reloading


func reload_progress() -> float:
	if not is_reloading:
		return 0.0
	return 1.0 - clampf(_reload_timer / reload_time, 0.0, 1.0)


func _process(delta: float) -> void:
	_animate_weapon(delta)
	if _bolt_timer > 0.0:
		_bolt_timer -= delta
	if _reload_delay > 0.0:
		_reload_delay -= delta
		if _reload_delay <= 0.0 and not is_reloading:
			_start_reload()
	if is_reloading:
		_reload_timer -= delta
		if _reload_timer <= 0.0:
			_finish_reload()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT \
			and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		try_fire()
	elif event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == KEY_R:
		request_reload()
	elif event is InputEventMouseMotion and enabled:
		_look_sway = (_look_sway + event.relative * 0.5).limit_length(40.0)


## R key: swap the magazine now instead of waiting for it to run dry.
func request_reload() -> bool:
	if not enabled or is_reloading or ammo >= capacity:
		return false
	_reload_delay = 0.0
	_start_reload()
	return true


func try_fire() -> bool:
	if not enabled:
		return false
	if is_reloading:
		dry_sound.play()
		dry_fired.emit()
		return false
	if _bolt_timer > 0.0 or ammo <= 0:
		return false

	ammo -= 1
	_bolt_timer = bolt_time
	_spawn_bullet()
	if not _shot_variants.is_empty():
		shot_sound.stream = _shot_variants[randi() % _shot_variants.size()]
	shot_sound.pitch_scale = randf_range(0.97, 1.03)
	shot_sound.play()
	_flash_muzzle()
	_kick = 1.0
	_play_shot_anim()
	fired.emit()
	ammo_changed.emit(ammo, capacity)

	if ammo <= 0:
		_reload_delay = 0.45
	else:
		_bolt_token += 1
		get_tree().create_timer(0.27, false).timeout.connect(_play_bolt_sound.bind(_bolt_token))
	return true


func _play_bolt_sound(token: int) -> void:
	if token == _bolt_token and not is_reloading:
		bolt_sound.play()


func _spawn_bullet() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or bullet_scene == null:
		return
	var b: Basis = cam.global_transform.basis
	var dir: Vector3 = -b.z
	# Zeroing: aim slightly high so the bullet crosses the line of sight at zero_range.
	var t0 := zero_range / muzzle_velocity
	var lift := atan(0.5 * gravity * t0 / muzzle_velocity)
	dir = dir.rotated(b.x, lift)
	if spread_deg > 0.0:
		var ang := deg_to_rad(spread_deg) * sqrt(randf())
		var around := randf() * TAU
		dir = dir.rotated(b.x, cos(around) * ang).rotated(b.y, sin(around) * ang)

	var bullet = bullet_scene.instantiate()
	var root := get_tree().get_first_node_in_group("bullet_root")
	if root == null:
		root = get_tree().current_scene
	root.add_child(bullet)
	bullet.global_position = cam.global_position + dir * 0.3
	bullet.launch(dir * muzzle_velocity, gravity, wind)


func _flash_muzzle() -> void:
	_flash_token += 1
	muzzle_flash.visible = true
	get_tree().create_timer(0.05, false).timeout.connect(_hide_flash.bind(_flash_token))


func _hide_flash(token: int) -> void:
	if token == _flash_token:
		muzzle_flash.visible = false


func _start_reload() -> void:
	is_reloading = true
	_reload_timer = reload_time
	_bolt_token += 1
	bolt_sound.stop()
	reload_sound.play()
	reload_started.emit()
	_play_reload_anim()


func _finish_reload() -> void:
	is_reloading = false
	ammo = capacity
	_bolt_timer = 0.3
	ammo_changed.emit(ammo, capacity)
	reload_finished.emit()


func _kill_anim() -> void:
	if _anim != null and _anim.is_valid():
		_anim.kill()
	if _mag_tween != null and _mag_tween.is_valid():
		_mag_tween.kill()
	if _bolt_tween != null and _bolt_tween.is_valid():
		_bolt_tween.kill()
	var mag := model.get_node_or_null("Magazine") as Node3D
	if mag != null:
		mag.position = _mag_rest
		mag.visible = true
	model.position = Vector3.ZERO
	model.rotation_degrees = Vector3.ZERO
	bolt_handle.position = _bolt_rest
	bolt_handle.rotation_degrees = Vector3.ZERO


func _play_shot_anim() -> void:
	_kill_anim()
	model.position = Vector3(0.0, 0.012, recoil_kick)
	model.rotation_degrees = Vector3(7.0, randf_range(-1.2, 1.2), randf_range(-1.5, 1.5))
	_anim = create_tween()
	_anim.tween_property(model, "position", Vector3.ZERO, 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_anim.parallel().tween_property(model, "rotation_degrees", Vector3.ZERO, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if ammo > 0:
		_anim.tween_property(bolt_handle, "rotation_degrees:z", 80.0, 0.15)
		_anim.tween_property(bolt_handle, "position", _bolt_rest + Vector3(0.0, 0.0, 0.07), 0.17)
		_anim.tween_callback(_eject_casing)
		_anim.tween_interval(0.08)
		_anim.tween_property(bolt_handle, "position", _bolt_rest, 0.15)
		_anim.tween_property(bolt_handle, "rotation_degrees:z", 0.0, 0.15)


## The spent case flips out of the ejection port and clinks to the ground.
func _eject_casing() -> void:
	var cam := get_viewport().get_camera_3d()
	var scene := get_tree().current_scene
	if cam == null or scene == null:
		return
	var cb: Basis = cam.global_transform.basis
	var casing := MeshInstance3D.new()
	casing.mesh = _casing_mesh
	casing.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	scene.add_child(casing)
	var start := bolt_handle.global_position
	casing.global_position = start
	var vel := cb.x * randf_range(1.5, 2.3) + cb.y * randf_range(1.1, 1.7) + cb.z * randf_range(0.2, 0.7)
	var ground_y := cam.global_position.y - 1.6
	var spin := Vector3(randf_range(-14.0, 14.0), randf_range(-6.0, 6.0), randf_range(-14.0, 14.0))
	var tw := casing.create_tween()
	tw.tween_method(_move_casing.bind(casing, start, vel, ground_y, spin), 0.0, 1.8, 1.8)
	tw.tween_interval(2.5)
	tw.tween_callback(casing.queue_free)


func _move_casing(t: float, casing: Node3D, start: Vector3, vel: Vector3, ground_y: float, spin: Vector3) -> void:
	if not is_instance_valid(casing):
		return
	var pos := start + vel * t + Vector3(0.0, -4.9 * t * t, 0.0)
	if pos.y < ground_y:
		pos.y = ground_y
	casing.global_position = pos
	casing.rotation = spin * minf(t, 0.6)


## Whole-rifle motion on top of the model animations: draw, scope raise, breathing, walking
## bob, lag behind mouse movement and the kick of each shot.
func _animate_weapon(delta: float) -> void:
	_time += delta
	var scope_t := 0.0
	var speed := 0.0
	if _player != null:
		scope_t = _player.scope_progress
		speed = Vector2(_player.velocity.x, _player.velocity.z).length()
	_look_sway = _look_sway.lerp(Vector2.ZERO, 1.0 - exp(-7.0 * delta))
	_kick = lerpf(_kick, 0.0, 1.0 - exp(-8.0 * delta))
	_raise = move_toward(_raise, 0.0, delta * 2.0)
	_walk_phase += speed * delta * 2.6
	var walk := clampf(speed / 2.0, 0.0, 1.0)
	var bob := Vector3(sin(_walk_phase) * 0.012, absf(sin(_walk_phase * 2.0)) * 0.009, 0.0) * walk
	var breathe := Vector3(0.0, sin(_time * 1.7) * 0.0016, 0.0)
	var ads := Vector3(-0.15, 0.115, 0.19) * scope_t
	var drawn := Vector3(0.04, -0.4, 0.06) * (_raise * _raise)
	var lag := Vector3(-_look_sway.x * 0.0007, _look_sway.y * 0.0005, 0.0)
	var kick_pos := Vector3(0.0, 0.0, _kick * 0.045)
	position = _rest_pos + ads + bob + breathe + drawn + lag + kick_pos
	rotation_degrees = Vector3(
			_kick * 4.5 - _look_sway.y * 0.05 - _raise * 25.0,
			-_look_sway.x * 0.06,
			-bob.x * 90.0 + _raise * 8.0)


func _play_reload_anim() -> void:
	_kill_anim()
	_anim = create_tween()
	_anim.tween_property(model, "position", Vector3(0.055, -0.23, 0.13), 0.30)
	_anim.parallel().tween_property(model, "rotation_degrees", Vector3(-22.0, 2.0, 16.0), 0.30)
	_anim.tween_interval(maxf(reload_time - 1.05, 0.1))
	_anim.tween_property(model, "position", Vector3(-0.008, 0.012, -0.012), 0.22)
	_anim.parallel().tween_property(model, "rotation_degrees", Vector3(2.0, 0.0, -1.5), 0.22)
	_anim.tween_property(model, "position", Vector3.ZERO, 0.12)
	_anim.parallel().tween_property(model, "rotation_degrees", Vector3.ZERO, 0.12)
	_play_mag_swap()
	_play_reload_bolt()


## Chambering at the end of the reload, lined up with the bolt sounds in reload.wav.
func _play_reload_bolt() -> void:
	_bolt_tween = create_tween()
	_bolt_tween.tween_interval(1.82)
	_bolt_tween.tween_property(bolt_handle, "rotation_degrees:z", 80.0, 0.14)
	_bolt_tween.tween_property(bolt_handle, "position", _bolt_rest + Vector3(0.0, 0.0, 0.07), 0.18)
	_bolt_tween.tween_interval(0.22)
	_bolt_tween.tween_property(bolt_handle, "position", _bolt_rest, 0.17)
	_bolt_tween.tween_interval(0.03)
	_bolt_tween.tween_property(bolt_handle, "rotation_degrees:z", 0.0, 0.14)


## The magazine drops out, then a fresh one slides in, timed to the reload sound.
func _play_mag_swap() -> void:
	var mag := model.get_node_or_null("Magazine") as Node3D
	if mag == null:
		return
	_mag_tween = create_tween()
	_mag_tween.tween_interval(0.34)
	_mag_tween.tween_property(mag, "position", _mag_rest + Vector3(0.0, -0.16, 0.0), 0.16)
	_mag_tween.tween_callback(mag.hide)
	_mag_tween.tween_interval(0.6)
	_mag_tween.tween_callback(_show_fresh_mag)
	_mag_tween.tween_property(mag, "position", _mag_rest, 0.22)


func _show_fresh_mag() -> void:
	var mag := model.get_node_or_null("Magazine") as Node3D
	if mag != null:
		mag.position = _mag_rest + Vector3(0.0, -0.16, 0.0)
		mag.show()
