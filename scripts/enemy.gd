extends CharacterBody3D
## Enemy infantry advancing on the sniper's cliff. They follow a baked lane across the valley
## floor (every lane is in view of the nest), wandering a little from side to side, walking,
## sprinting and stopping. Reaching the breach line costs the player a life.

signal died(enemy: Node3D, headshot: bool, distance: float)
signal wounded(enemy: Node3D, headshot: bool)
signal reached_base(enemy: Node3D)

enum State { WALK, RUN, PAUSE }

@export var walk_speed := 2.4
@export var run_speed := 5.0
@export var max_health := 100.0
@export var body_damage := 100.0
@export var head_damage := 200.0
## How far (m) the enemy may drift sideways from the middle of its lane.
@export var wander_width := 1.4

var speed_mult := 1.0
var armored := false
var breach_z := -82.0
var sniper_position := Vector3.ZERO
var health := 100.0
var dead := false

var _lane := PackedVector2Array()
var _cum := PackedFloat32Array()
var _length := 0.0
var _s := 0.0
var _seg := 0
var _dir := Vector2(0.0, 1.0)
var _sampler = null
var _state := State.WALK
var _state_timer := 2.0
var _time := 0.0
var _stride := 0.0
var _lane_offset := 0.0
var _wander_phase := randf() * TAU
var _wander_freq := randf_range(0.12, 0.26)
var _flash_material: StandardMaterial3D
var _meshes: Array[MeshInstance3D] = []
var _dust: CPUParticles3D
var _dust_material: StandardMaterial3D
var _heat_meshes: Array[MeshInstance3D] = []
var _storm_hitbox_boosted := false
var _dev_hitbox_boosted := false
var _base_hitbox_adjusted := false
var _base_body_radius := 0.0
var _base_body_height := 0.0
var _base_head_radius := 0.0
var _difficulty_hitbox_scale := 1.0

@onready var _body_collision: CollisionShape3D = $BodyCollision
@onready var _head_collision: CollisionShape3D = $HeadCollision

@onready var visual: Node3D = $Visual
@onready var leg_left: Node3D = $Visual/LegLeft
@onready var leg_right: Node3D = $Visual/LegRight
@onready var arm_left: Node3D = $Visual/ArmLeft
@onready var arm_right: Node3D = $Visual/ArmRight
@onready var armor_plate: Node3D = $Visual/ArmorPlate


func _ready() -> void:
	_flash_material = StandardMaterial3D.new()
	_flash_material.albedo_color = Color(1.0, 0.35, 0.25)
	_flash_material.emission_enabled = true
	_flash_material.emission = Color(1.0, 0.2, 0.1)
	for node in visual.find_children("*", "MeshInstance3D", true, false):
		_meshes.append(node)
	armor_plate.visible = false
	_apply_base_hitbox_bonus()
	_state_timer = randf_range(1.0, 3.0)
	_make_dust()


## A small, permanent forgiveness adjustment on every level. Collision shapes are
## duplicated so enemies never mutate shared PackedScene resources.
func _apply_base_hitbox_bonus() -> void:
	if _base_hitbox_adjusted:
		return
	_base_hitbox_adjusted = true
	if _body_collision.shape is CapsuleShape3D:
		var body_shape: CapsuleShape3D = _body_collision.shape.duplicate() as CapsuleShape3D
		_base_body_radius = body_shape.radius * 1.08
		_base_body_height = body_shape.height * 1.04
		_body_collision.shape = body_shape
	if _head_collision.shape is SphereShape3D:
		var head_shape: SphereShape3D = _head_collision.shape.duplicate() as SphereShape3D
		_base_head_radius = head_shape.radius * 1.07
		_head_collision.shape = head_shape
	_apply_hitbox_dimensions()


## Call after adding to the tree. lane = x,z points from the spawn end to the breach end.
func setup(lane: PackedVector2Array, sampler, p_speed_mult: float, p_armored: bool, p_breach_z: float, p_level: int = 1) -> void:
	_lane = lane
	_sampler = sampler
	speed_mult = p_speed_mult
	armored = p_armored
	breach_z = p_breach_z
	_difficulty_hitbox_scale = 1.0
	if p_level > 6:
		_difficulty_hitbox_scale *= 0.98
	if p_level > 15:
		_difficulty_hitbox_scale *= 0.99
	_apply_hitbox_dimensions()
	if armored:
		max_health = 200.0
		armor_plate.visible = true
	health = max_health
	_cum = PackedFloat32Array()
	_cum.append(0.0)
	for i in range(1, _lane.size()):
		_cum.append(_cum[i - 1] + _lane[i].distance_to(_lane[i - 1]))
	if _cum.size() > 0:
		_length = _cum[_cum.size() - 1]
	_lane_offset = randf_range(-0.9, 0.9)
	_place(0.0)


func _physics_process(delta: float) -> void:
	if dead or _lane.size() < 2:
		return
	_time += delta
	_state_timer -= delta
	if _state_timer <= 0.0:
		_next_state()

	var moving := _state != State.PAUSE
	if moving:
		var speed := (run_speed if _state == State.RUN else walk_speed) * speed_mult
		_s += speed * delta
		_stride += delta * speed * 2.2
	_place(delta)
	_animate(moving)

	if _s >= _length or global_position.z >= breach_z:
		dead = true
		reached_base.emit(self)
		queue_free()


func react_to_gunfire(sniper_pos: Vector3) -> void:
	if dead or global_position.distance_to(sniper_pos) > 105.0:
		return
	if randf() < 0.10:
		_state = State.PAUSE
		_state_timer = randf_range(0.16, 0.28)
		if _dust != null and randf() < 0.35:
			_dust.emitting = true


func _next_state() -> void:
	var r := randf()
	if _state == State.PAUSE:
		_state = State.WALK
		_state_timer = randf_range(2.5, 5.0)
	elif r < 0.22:
		_state = State.PAUSE
		_state_timer = randf_range(0.8, 1.8)
	elif r < 0.52:
		_state = State.RUN
		_state_timer = randf_range(1.2, 2.4)
	else:
		_state = State.WALK
		_state_timer = randf_range(2.0, 4.0)
	if _dust != null:
		_dust.emitting = _state == State.RUN


func _lane_point(s: float) -> Vector2:
	var last := _lane.size() - 2
	while _seg < last and _cum[_seg + 1] < s:
		_seg += 1
	var a := _lane[_seg]
	var b := _lane[_seg + 1]
	var seg_len := _cum[_seg + 1] - _cum[_seg]
	var t := 0.0
	if seg_len > 0.0:
		t = clampf((s - _cum[_seg]) / seg_len, 0.0, 1.0)
	_dir = (b - a).normalized()
	return a.lerp(b, t)


func _place(delta: float) -> void:
	var p := _lane_point(minf(_s, _length))
	var side := Vector2(-_dir.y, _dir.x)
	var wander := sin(_time * _wander_freq * TAU + _wander_phase) * wander_width
	var pos2 := p + side * (_lane_offset + wander)
	var y := global_position.y
	if _sampler != null and _sampler.ok:
		y = _sampler.height_at(pos2.x, pos2.y)
	global_position = Vector3(pos2.x, y, pos2.y)
	var target_yaw := atan2(-_dir.x, -_dir.y)
	if delta <= 0.0:
		rotation.y = target_yaw
	else:
		rotation.y = lerp_angle(rotation.y, target_yaw, clampf(6.0 * delta, 0.0, 1.0))


func _animate(moving: bool) -> void:
	if moving:
		var swing := sin(_stride)
		leg_left.rotation.x = swing * 0.7
		leg_right.rotation.x = -swing * 0.7
		arm_left.rotation.x = -swing * 0.5
		arm_right.rotation.x = swing * 0.2
		visual.position.y = absf(swing) * 0.04
	else:
		leg_left.rotation.x = lerpf(leg_left.rotation.x, 0.0, 0.2)
		leg_right.rotation.x = lerpf(leg_right.rotation.x, 0.0, 0.2)
		arm_left.rotation.x = lerpf(arm_left.rotation.x, 0.0, 0.2)
		arm_right.rotation.x = lerpf(arm_right.rotation.x, 0.0, 0.2)
		visual.position.y = 0.0


## A faint trail of dust while running: a natural, very small hint of where they are.
func _make_dust() -> void:
	_dust = CPUParticles3D.new()
	_dust.amount = 10
	_dust.lifetime = 1.2
	_dust.emitting = false
	_dust.local_coords = false
	_dust.direction = Vector3.UP
	_dust.spread = 35.0
	_dust.initial_velocity_min = 0.3
	_dust.initial_velocity_max = 1.0
	_dust.gravity = Vector3(0.0, 0.1, 0.0)
	_dust.scale_amount_min = 0.6
	_dust.scale_amount_max = 1.1
	var puff := SphereMesh.new()
	puff.radius = 0.28
	puff.height = 0.56
	puff.radial_segments = 8
	puff.rings = 4
	_dust_material = StandardMaterial3D.new()
	_dust_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_dust_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_dust_material.vertex_color_use_as_albedo = true
	_dust_material.albedo_color = Color(0.8, 0.68, 0.5, 0.55)
	puff.material = _dust_material
	_dust.mesh = puff
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 1.0, 1.0, 0.7))
	ramp.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	_dust.color_ramp = ramp
	_dust.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_dust)
	_dust.position = Vector3(0.0, 0.1, 0.0)


## Night vision and the sandstorm thermal hint both use a separate render layer.
## The heat silhouette is only visible through the scoped optic when the player enables N.
func set_night(night: bool) -> void:
	set_conditions(night, false)


func set_conditions(night: bool, storm: bool) -> void:
	if _dust_material != null:
		_dust_material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL if night else BaseMaterial3D.SHADING_MODE_UNSHADED
	# A sandstorm always uses the full bright thermal silhouette, whether it is
	# daytime or nighttime. Night-only vision without a storm keeps the subtle
	# green night-vision enemy overlay.
	if storm and _heat_meshes.is_empty():
		_build_heat(true)
	elif night and _heat_meshes.is_empty():
		_build_heat(false)


## On sandstorm waves, enlarge the enemy collision volumes slightly (not the visible model).
## Duplicate each resource first so the shared PackedScene shapes remain untouched.
func set_sandstorm_hitbox(enabled: bool) -> void:
	_storm_hitbox_boosted = enabled
	_apply_hitbox_dimensions()


## Developer-only test aid; expands hitbox dimensions by 180% total without changing visuals.
func set_dev_hitbox_boost(enabled: bool) -> void:
	_dev_hitbox_boosted = enabled
	_apply_hitbox_dimensions()


## Rebuild from the unmodified scene dimensions every time; never compound toggles.
func _apply_hitbox_dimensions() -> void:
	if _base_body_radius <= 0.0 or _base_head_radius <= 0.0:
		return
	var storm_body := 1.16 if _storm_hitbox_boosted else 1.0
	var storm_height := 1.06 if _storm_hitbox_boosted else 1.0
	var storm_head := 1.12 if _storm_hitbox_boosted else 1.0
	var dev_scale := 2.8 if _dev_hitbox_boosted else 1.0
	if _body_collision.shape is CapsuleShape3D:
		var body_shape := (_body_collision.shape as CapsuleShape3D).duplicate() as CapsuleShape3D
		body_shape.radius = _base_body_radius * storm_body * _difficulty_hitbox_scale * dev_scale
		body_shape.height = _base_body_height * storm_height * _difficulty_hitbox_scale * dev_scale
		_body_collision.shape = body_shape
	if _head_collision.shape is SphereShape3D:
		var head_shape := (_head_collision.shape as SphereShape3D).duplicate() as SphereShape3D
		head_shape.radius = _base_head_radius * storm_head * _difficulty_hitbox_scale * dev_scale
		_head_collision.shape = head_shape


func _build_heat(storm_mode: bool) -> void:
	var heat_shader := Shader.new()
	heat_shader.code = """shader_type spatial;
render_mode unshaded, fog_disabled;
void fragment() {
	// A hot-core palette: dark red/orange edges transition into a very
	// bright yellow-white centre. Values above 1.0 are intentional HDR.
	float vertical_heat = smoothstep(0.02, 0.98, UV.y);
	float core = 0.35 + vertical_heat * 0.65;
	vec3 edge_heat = vec3(24.0, 0.42, 0.008);
	vec3 core_heat = vec3(48.0, 32.0, 18.0);
	float rim = pow(1.0 - max(dot(normalize(NORMAL), normalize(VIEW)), 0.0), 1.8);
	vec3 heat = mix(edge_heat, core_heat, clamp(core * 0.72 + rim * 0.48, 0.0, 1.0));
	ALBEDO = vec3(1.0, 0.48, 0.08);
	EMISSION = heat * 55.0;
}
"""
	var heat_material := ShaderMaterial.new()
	heat_material.shader = heat_shader
	if not storm_mode:
		var night_material := StandardMaterial3D.new()
		night_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		night_material.albedo_color = Color(0.09, 0.15, 0.1, 1.0)
		for m in _meshes:
			if not m.is_visible_in_tree():
				continue
			var h := MeshInstance3D.new()
			h.name = "Thermal" + m.name
			h.mesh = m.mesh
			h.material_override = night_material
			h.layers = 2
			h.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			h.transform = m.transform.scaled_local(Vector3.ONE * 1.015)
			m.get_parent().add_child(h)
			_heat_meshes.append(h)
		return

	# Thermal vision paints the complete visible enemy silhouette, including
	# torso, pelvis, head, arms, legs, armour and carried equipment. The thermal
	# layer stays depth-tested so walls and terrain still occlude the target.
	for m in _meshes:
		if not m.is_visible_in_tree():
			continue
		var h := MeshInstance3D.new()
		h.name = "Thermal" + m.name
		h.mesh = m.mesh
		h.material_override = heat_material
		h.layers = 2
		h.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		h.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		# Slightly expand the thermal mesh to keep it visible over the source
		# surface while preserving the original silhouette and depth occlusion.
		h.transform = m.transform.scaled_local(Vector3.ONE * 1.14)
		m.get_parent().add_child(h)
		_heat_meshes.append(h)


## Called by bullets.
func register_hit(_hit_position: Vector3, is_head: bool) -> void:
	if dead:
		return
	health -= head_damage if is_head else body_damage
	_flash()
	if health <= 0.0:
		_die(is_head)
	else:
		_state = State.RUN
		_state_timer = randf_range(1.5, 2.5)
		if _dust != null:
			_dust.emitting = true
		wounded.emit(self, is_head)


func _flash() -> void:
	for m in _meshes:
		m.material_override = _flash_material
	get_tree().create_timer(0.12, false).timeout.connect(_clear_flash)


func _clear_flash() -> void:
	for m in _meshes:
		if is_instance_valid(m):
			m.material_override = null


func _die(is_head: bool) -> void:
	dead = true
	collision_layer = 0
	if _dust != null:
		_dust.emitting = false
	died.emit(self, is_head, global_position.distance_to(sniper_position))
	var t := create_tween()
	t.tween_property(visual, "rotation_degrees:x", 90.0, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_interval(2.0)
	t.tween_property(self, "global_position:y", global_position.y - 1.0, 1.0)
	t.tween_callback(queue_free)
