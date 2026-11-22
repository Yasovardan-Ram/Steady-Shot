extends CanvasLayer
## Night-vision optic. It only works through the scope: the screen is untouched until you zoom
## in, and then a shader turns the circle you are looking through into amplified green with
## grain and scan-lines. Enemies carry an extra "body heat" mesh on visual layer 2 that is only
## drawn while you are looking through the optic with night vision on.
## Toggle with N (the game manager only allows it at night).

signal toggled(on: bool)

const HEAT_LAYER_MASK := 2

var active := false

var _rect: ColorRect
var _material: ShaderMaterial
var _tween: Tween
var _on_sound: AudioStreamPlayer
var _off_sound: AudioStreamPlayer
var _player = null
var _scope_alpha := 0.0
var _heat_shown := false
var _storm_mode := false
var _camera_ref: Camera3D
var _camera_base_mask := 1

const SHADER_CODE := """shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float amount : hint_range(0.0, 1.0) = 0.0;
uniform float scope_alpha : hint_range(0.0, 1.0) = 0.0;
uniform float radius = 0.46;
uniform float gain = 9.0;
uniform float flash = 0.0;
uniform vec3 tint = vec3(0.32, 1.0, 0.42);\nuniform bool thermal_mode = false;
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}
void fragment() {
	vec3 col = texture(screen_tex, SCREEN_UV).rgb;
	vec2 res = vec2(1.0) / SCREEN_PIXEL_SIZE;
	vec2 p = (SCREEN_UV - vec2(0.5)) * res;
	float r_px = radius * res.y;
	float d = length(p);
	// Only the circle you are looking through is affected.
	float inside = 1.0 - smoothstep(r_px - 4.0, r_px, d);
	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	float v = 1.0 - exp(-lum * gain);
	float n = hash(SCREEN_UV * vec2(1920.0, 1080.0) + vec2(TIME * 37.0, TIME * 91.0));
	v += (n - 0.5) * 0.14;
	v *= 0.96 + 0.04 * sin(SCREEN_UV.y * 900.0 + TIME * 6.0);
	v *= mix(0.55, 1.0, smoothstep(r_px, r_px * 0.45, d));
	v += flash;
	vec3 nv = tint * clamp(v, 0.0, 1.0);
	float optic_amount = amount * scope_alpha * inside;
	// Thermal mode does not paint the optic orange: only the separate, faint
	// head/torso heat meshes on render layer 2 provide a limited thermal cue.
	vec3 result = col;
	if (thermal_mode) {
		// In sandstorms, leave the scene in its normal colours and show
		// only the enemy heat-layer as unmistakable bright red/orange targets.
		float hot_signal = col.r - max(col.g * 1.15, col.b * 1.5);
		float hot_mask = smoothstep(0.015, 0.22, hot_signal);
		float heat_level = clamp(col.g / max(col.r, 0.001) * 1.8, 0.0, 1.0);
		vec3 hot_red = mix(vec3(1.8, 0.015, 0.001), vec3(2.8, 0.48, 0.008), heat_level);
		vec3 red_only_thermal = mix(col, hot_red, hot_mask);
		result = mix(col, red_only_thermal, optic_amount);
	} else {
		result = mix(col, nv, optic_amount);
	}
	COLOR = vec4(result, 1.0);
}
"""


func _ready() -> void:
	layer = 0    # under the HUD (layer 1), so the reticle and menus are never tinted
	process_mode = Node.PROCESS_MODE_ALWAYS
	var shader := Shader.new()
	shader.code = SHADER_CODE
	_material = ShaderMaterial.new()
	_material.shader = shader
	_material.set_shader_parameter("amount", 0.0)
	_material.set_shader_parameter("tint", Vector3(0.32, 1.0, 0.42))
	_material.set_shader_parameter("gain", 9.0)
	_rect = ColorRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.material = _material
	_rect.visible = false
	add_child(_rect)
	_on_sound = _make_sound("res://audio/nv_on.wav", -6.0)
	_off_sound = _make_sound("res://audio/nv_off.wav", -8.0)
	call_deferred("_init_camera")


func _make_sound(path: String, volume_db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.volume_db = volume_db
	if ResourceLoader.exists(path):
		p.stream = load(path)
	add_child(p)
	return p


func _init_camera() -> void:
	_player = get_node_or_null("../Player")
	_set_camera_mask(false)


func _process(_delta: float) -> void:
	if _player == null:
		return
	_scope_alpha = smoothstep(0.7, 0.97, float(_player.scope_progress))
	_material.set_shader_parameter("scope_alpha", _scope_alpha)
	_rect.visible = (active or float(_material.get_shader_parameter("amount")) > 0.01) and _scope_alpha > 0.01
	# Body heat is only drawn while you are actually looking through the optic.
	var want_heat := active and _scope_alpha > 0.5
	if want_heat != _heat_shown:
		_heat_shown = want_heat
		_set_camera_mask(want_heat)


func _set_camera_mask(show_heat: bool) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	if cam != _camera_ref:
		_camera_ref = cam
		# Preserve the scene's original visible layers while adding the temporary
		# thermal layer. This avoids accidentally hiding other game objects.
		_camera_base_mask = cam.cull_mask & ~HEAT_LAYER_MASK
	cam.cull_mask = _camera_base_mask | (HEAT_LAYER_MASK if show_heat else 0)


## Sandstorm mode keeps the normal scene colours and highlights enemy heat meshes
## in bright red/orange, including when night and sandstorm overlap.
func set_storm_mode(enabled: bool) -> void:
	_storm_mode = enabled
	if _material != null:
		_material.set_shader_parameter("thermal_mode", enabled)
		_material.set_shader_parameter("tint", Vector3(0.32, 1.0, 0.42))
		_material.set_shader_parameter("gain", 9.0)


func set_active(on: bool, instant: bool = false) -> void:
	if on == active:
		return
	active = on
	if not on:
		_heat_shown = false
		_set_camera_mask(false)
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if instant:
		_material.set_shader_parameter("amount", 1.0 if on else 0.0)
		_rect.visible = on
	else:
		if on:
			_rect.visible = true
			_material.set_shader_parameter("flash", 0.5)
		_tween = create_tween()
		_tween.set_parallel(true)
		_tween.tween_method(_set_amount, 1.0 - float(on), float(on), 0.35)
		if on:
			_tween.tween_method(_set_flash, 0.5, 0.0, 0.45)
		else:
			_tween.chain().tween_callback(_hide_rect)
		if on:
			_on_sound.play()
		else:
			_off_sound.play()
	toggled.emit(on)


func _set_amount(v: float) -> void:
	_material.set_shader_parameter("amount", v)


func _set_flash(v: float) -> void:
	_material.set_shader_parameter("flash", v)


func _hide_rect() -> void:
	if not active:
		_rect.visible = false
