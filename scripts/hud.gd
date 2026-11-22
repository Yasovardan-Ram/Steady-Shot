extends CanvasLayer
## Pure display. The game manager tells it what to show; it reads ammo/scope state
## from the player and weapon every frame.

@onready var reticle = $Root/Reticle
@onready var radar = $Root/Radar
@onready var zoom_label: Label = $Root/ZoomLabel
@onready var ammo_box: HBoxContainer = $Root/AmmoBox
@onready var bolt_label: Label = $Root/BoltLabel
@onready var reload_bar: ProgressBar = $Root/ReloadBar
@onready var banner_label: Label = $Root/BannerLabel
@onready var popup_label: Label = $Root/PopupLabel
@onready var menu = $Root/Menu
@onready var damage_flash: ColorRect = $Root/DamageFlash

var player
var weapon
var _pips: Array[ColorRect] = []
var _banner_tween: Tween
var _popup_tween: Tween
var _flash_tween: Tween
var _score_value: Label
var _enemies_value: Label
var _life_pips: Array[ColorRect] = []
var _level_panel: PanelContainer
var _level_value: Label
var _level_tween: Tween
var _last_score := 0
var _score_tween: Tween
var _level_style: StyleBoxFlat
var auth
var _wind_gauge: Control
var _hint_panel: PanelContainer
var _hint_after_label: Label
var _storm_chip: PanelContainer
var _night := false
var _nv_on := false
var _storm := false
var _hint_timer := 0.0
var _hint_alpha := 0.0
var _font_caps: FontVariation
var _font_wide: FontVariation
var _heart_history: Control
var _breathing_history: Control
var _sensor_status_label: Label
var _sensor_status_log_seen: Array[String] = []
var _sensor_received_any_real_data: bool = false
var sensor_setup
var _brand_saved_radar_visible: bool = true
var _brand_saved_wind_visible: bool = false
var _brand_saved_level_visible: bool = true
var _brand_visibility_saved: bool = false
var _auth_brand_visible: bool = false

const AMBER := Color(0.93, 0.68, 0.25)
const CREAM := Color(0.96, 0.92, 0.82)
const DIM := Color(0.7, 0.64, 0.55)
const WindGauge := preload("res://scripts/wind_gauge.gd")
const AuthPanel := preload("res://scripts/auth_panel.gd")
const SensorSetup := preload("res://scripts/sensor_setup.gd")
const SensorHistory: Script = preload("res://scripts/sensor_history.gd")


func _ready() -> void:
	banner_label.modulate.a = 0.0
	popup_label.modulate.a = 0.0
	damage_flash.modulate.a = 0.0
	add_to_group("storm_listeners")
	_font_caps = FontVariation.new()
	_font_caps.base_font = ThemeDB.fallback_font
	_font_caps.spacing_glyph = 2
	_font_wide = FontVariation.new()
	_font_wide.base_font = ThemeDB.fallback_font
	_font_wide.spacing_glyph = 7
	_build_ammo_panel()
	_build_status_panel()
	_build_level_badge()
	_build_wind_gauge()
	_build_hint()
	_build_storm_chip()
	_build_auth()
	_build_sensor_setup()
	_build_shared_brand_title()
	_build_sensor_hud()
	_refine(zoom_label, 15, Color(0.86, 0.82, 0.72, 0.9), true)
	_refine(bolt_label, 14, Color(0.86, 0.82, 0.72, 0.9), true)
	_refine(banner_label, 40, CREAM, false, _font_wide)
	_refine(popup_label, 21, CREAM, false)
	zoom_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


## A compact dark plate with a warm outline keeps the ammo/reload HUD legible over any terrain.
func _build_ammo_panel() -> void:
	var panel := PanelContainer.new()
	panel.name = "AmmoReadabilityPanel"
	panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	panel.offset_left = 10.0
	panel.offset_top = -122.0
	panel.offset_right = 310.0
	panel.offset_bottom = -5.0
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.028, 0.022, 0.78)
	style.border_color = Color(0.78, 0.57, 0.29, 0.88)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.content_margin_left = 7.0
	style.content_margin_right = 7.0
	style.content_margin_top = 5.0
	style.content_margin_bottom = 5.0
	panel.add_theme_stylebox_override("panel", style)
	$Root.add_child(panel)
	# Keep it above the full-screen reticle canvas but behind all HUD controls.
	$Root.move_child(panel, 1)


func bind(p_player, p_weapon, enemies_root: Node3D) -> void:
	player = p_player
	weapon = p_weapon
	radar.player = p_player
	radar.enemies_root = enemies_root
	for child in ammo_box.get_children():
		child.queue_free()
	_pips.clear()
	for i in weapon.capacity:
		var pip := ColorRect.new()
		pip.custom_minimum_size = Vector2(12, 34)
		ammo_box.add_child(pip)
		_pips.append(pip)


func _process(delta: float) -> void:
	if player == null or weapon == null:
		return
	reticle.scope_alpha = smoothstep(0.7, 0.97, player.scope_progress)
	reticle.fov_deg = player.current_fov

	reticle.nv_on = _nv_on
	if player.is_scoped:
		zoom_label.text = "%d×      1 dot = %d mil" % [int(player.zoom_value()), reticle.mil_step]
	else:
		zoom_label.text = "RMB  scope        R  reload"

	for i in _pips.size():
		_pips[i].color = Color(0.95, 0.75, 0.25) if i < weapon.ammo else Color(0.25, 0.25, 0.25, 0.7)
	reload_bar.visible = weapon.is_reloading
	reload_bar.value = weapon.reload_progress()
	if weapon.is_reloading:
		bolt_label.text = "RELOADING"
		bolt_label.add_theme_color_override("font_color", Color(1.0, 0.55, 0.4, 0.95))
	elif weapon.is_bolt_cycling():
		bolt_label.text = "CYCLING BOLT"
		bolt_label.add_theme_color_override("font_color", Color(0.93, 0.68, 0.25, 0.95))
	else:
		bolt_label.text = "READY"
		bolt_label.add_theme_color_override("font_color", Color(0.86, 0.82, 0.72, 0.9))

	if _sensor_status_label != null:
		_sensor_status_label.text = player.sensor_status

	# "Press N for night vision": shown for a while when night falls, and whenever you look
	# through the scope at night with the optic still off.
	if _hint_timer > 0.0:
		_hint_timer -= delta
	var want_hint: bool = (_night or _storm) and not _nv_on and (_hint_timer > 0.0 or bool(player.is_scoped))
	_hint_alpha = move_toward(_hint_alpha, 1.0 if want_hint else 0.0, delta * 3.0)
	_hint_panel.modulate.a = _hint_alpha
	_hint_panel.visible = _hint_alpha > 0.01


func set_status(score: int, _wave: int, lives: int, enemies_left: int) -> void:
	if _score_value == null:
		return
	_score_value.text = _format_number(score)
	if score > _last_score:
		_score_value.modulate = Color(1.0, 0.82, 0.35)
		if _score_tween != null and _score_tween.is_valid():
			_score_tween.kill()
		_score_tween = create_tween()
		_score_tween.tween_property(_score_value, "modulate", Color(1, 1, 1), 0.45)
	_last_score = score
	_enemies_value.text = str(enemies_left)
	while _life_pips.size() < lives:
		_add_life_pip()
	for i in _life_pips.size():
		_life_pips[i].color = Color(0.9, 0.3, 0.24) if i < lives else Color(0.22, 0.2, 0.18, 0.9)


## Level goes up after every cleared wave; the badge sits under the minimap.
func set_level(level: int, animate: bool) -> void:
	if _level_value == null:
		return
	_level_value.text = str(level)
	if not animate:
		return
	_level_panel.pivot_offset = _level_panel.size * 0.5
	_level_panel.scale = Vector2(1.4, 1.4)
	_level_panel.modulate = Color(1.6, 1.4, 0.9)
	if _level_tween != null and _level_tween.is_valid():
		_level_tween.kill()
	_level_tween = create_tween()
	_level_tween.set_parallel(true)
	_level_tween.tween_property(_level_panel, "scale", Vector2.ONE, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_level_tween.tween_property(_level_panel, "modulate", Color(1, 1, 1), 0.9)


## The goggles are no longer announced under the wind: just a small hint (see _process).
func set_night_info(night: bool, nv_on: bool) -> void:
	if night and not _night:
		_hint_timer = 12.0
	_night = night
	_nv_on = nv_on
	_update_badge_color()


func set_storm_info(storm: bool) -> void:
	if storm and not _storm:
		_hint_timer = 12.0
	_storm = storm
	_storm_chip.visible = storm
	if _hint_after_label != null:
		_hint_after_label.text = "for thermal hint" if storm and not _night else "for night vision"
	_update_badge_color()


## Blown sand jams the minimap a little (see radar.gd).
func set_storm_factor(s: float) -> void:
	if radar != null:
		radar.interference = s


func _update_badge_color() -> void:
	if _level_style == null:
		return
	if _storm:
		_level_style.border_color = Color(0.86, 0.66, 0.38)
	elif _night:
		_level_style.border_color = Color(0.45, 0.75, 1.0)
	else:
		_level_style.border_color = AMBER


func _format_number(n: int) -> String:
	var digits := str(absi(n))
	var out := ""
	for i in digits.length():
		if i > 0 and (digits.length() - i) % 3 == 0:
			out += " "
		out += digits[i]
	return out


func _text(text: String, px: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", maxi(int(px / 8.0), 2))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _box_style(bg: Color, border: Color, radius: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(2)
	s.border_width_left = 5
	s.set_corner_radius_all(radius)
	s.shadow_color = Color(0, 0, 0, 0.5)
	s.shadow_size = 10
	return s


func _build_status_panel() -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(20, 16)
	panel.custom_minimum_size = Vector2(270, 0)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _box_style(Color(0.05, 0.045, 0.04, 0.8), AMBER, 12))
	$Root.add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 12)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(box)
	box.add_child(_text("SCORE", 13, DIM))
	_score_value = _text("0", 42, CREAM)
	box.add_child(_score_value)
	var rule := ColorRect.new()
	rule.color = Color(0.93, 0.68, 0.25, 0.4)
	rule.custom_minimum_size = Vector2(0, 2)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(rule)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 34)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(row)
	var enemies_col := VBoxContainer.new()
	enemies_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	enemies_col.add_child(_text("ENEMIES", 13, DIM))
	_enemies_value = _text("0", 28, CREAM)
	enemies_col.add_child(_enemies_value)
	row.add_child(enemies_col)
	var lives_col := VBoxContainer.new()
	lives_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lives_col.add_child(_text("LIVES", 13, DIM))
	var pips := HBoxContainer.new()
	pips.name = "Pips"
	pips.add_theme_constant_override("separation", 5)
	pips.custom_minimum_size = Vector2(0, 34)
	pips.alignment = BoxContainer.ALIGNMENT_CENTER
	pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lives_col.add_child(pips)
	row.add_child(lives_col)
	for i in 5:
		_add_life_pip()


func _add_life_pip() -> void:
	var pips := $Root.find_child("Pips", true, false)
	if pips == null:
		return
	var pip := ColorRect.new()
	pip.custom_minimum_size = Vector2(16, 16)
	pip.color = Color(0.9, 0.3, 0.24)
	pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pips.add_child(pip)
	_life_pips.append(pip)


func _build_level_badge() -> void:
	_level_panel = PanelContainer.new()
	_level_panel.anchor_left = 1.0
	_level_panel.anchor_right = 1.0
	_level_panel.anchor_top = 0.0
	_level_panel.anchor_bottom = 0.0
	_level_panel.offset_left = -190.0
	_level_panel.offset_right = -20.0
	_level_panel.offset_top = 198.0
	_level_panel.offset_bottom = 246.0
	_level_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_level_style = _box_style(Color(0.05, 0.045, 0.04, 0.82), AMBER, 12)
	_level_panel.add_theme_stylebox_override("panel", _level_style)
	$Root.add_child(_level_panel)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_level_panel.add_child(row)
	var cap := _text("LEVEL", 18, DIM)
	cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(cap)
	_level_value = _text("1", 34, AMBER)
	row.add_child(_level_value)


func set_wind(accel_x: float) -> void:
	if _wind_gauge != null:
		_wind_gauge.set_wind(accel_x)


func set_auth_brand_visible(show_brand: bool) -> void:
	_auth_brand_visible = show_brand
	var brand := $Root.get_node_or_null("AuthBrandTitle")
	if show_brand:
		if not _brand_visibility_saved:
			_brand_saved_radar_visible = radar.visible
			_brand_saved_wind_visible = _wind_gauge.visible if _wind_gauge != null else false
			_brand_saved_level_visible = _level_panel.visible if _level_panel != null else false
			_brand_visibility_saved = true
		if brand != null:
			brand.visible = true
		radar.visible = false
		if _wind_gauge != null:
			_wind_gauge.visible = false
		if _level_panel != null:
			_level_panel.visible = false
	else:
		if brand != null:
			brand.visible = false
		if _brand_visibility_saved:
			radar.visible = _brand_saved_radar_visible
			if _wind_gauge != null:
				_wind_gauge.visible = _brand_saved_wind_visible
			if _level_panel != null:
				_level_panel.visible = _brand_saved_level_visible
			_brand_visibility_saved = false


func set_gameplay_overlays_visible(is_visible: bool) -> void:
	# Never let gameplay HUD refreshes reveal overlays over the auth/API brand.
	if _wind_gauge != null:
		_wind_gauge.visible = is_visible and not _auth_brand_visible
	if _heart_history != null:
		_heart_history.visible = is_visible
	if _breathing_history != null:
		_breathing_history.visible = is_visible


func _build_auth() -> void:
	auth = Control.new()
	auth.set_script(AuthPanel)
	$Root.add_child(auth)

func _build_sensor_setup() -> void:
	sensor_setup = Control.new()
	sensor_setup.set_script(SensorSetup)
	$Root.add_child(sensor_setup)

func _build_shared_brand_title() -> void:
	var brand := Label.new()
	brand.name = "AuthBrandTitle"
	brand.text = "STEADY\nSHOT"
	brand.set_anchors_preset(Control.PRESET_FULL_RECT)
	brand.anchor_left = 0.64
	brand.anchor_right = 0.95
	brand.anchor_top = 0.035
	brand.anchor_bottom = 0.34
	brand.offset_left = 0.0
	brand.offset_right = -28.0
	brand.offset_top = 0.0
	brand.offset_bottom = 0.0
	brand.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	brand.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	brand.add_theme_font_size_override("font_size", 136)
	var display_font := SystemFont.new()
	display_font.font_names = PackedStringArray(["Arial Black", "Impact", "DejaVu Sans"])
	display_font.font_weight = 900
	brand.add_theme_font_override("font", display_font)
	brand.add_theme_color_override("font_color", Color(1.0, 0.79, 0.39, 0.96))
	brand.add_theme_color_override("font_outline_color", Color(0.025, 0.02, 0.015, 0.94))
	brand.add_theme_constant_override("outline_size", 8)
	brand.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	brand.add_theme_constant_override("shadow_offset_x", 5)
	brand.add_theme_constant_override("shadow_offset_y", 6)
	brand.mouse_filter = Control.MOUSE_FILTER_IGNORE
	brand.visible = false
	$Root.add_child(brand)


func _build_sensor_hud() -> void:
	_heart_history = Control.new()
	_heart_history.set_script(SensorHistory)
	_heart_history.title_text = "HEART RATE"
	_heart_history.unit_text = "BPM"
	_heart_history.accent = Color(0.95, 0.55, 0.38)
	_heart_history.anchor_left = 1.0
	_heart_history.anchor_right = 1.0
	_heart_history.anchor_top = 1.0
	_heart_history.anchor_bottom = 1.0
	_heart_history.offset_left = -230.0
	_heart_history.offset_right = -20.0
	_heart_history.offset_top = -166.0
	_heart_history.offset_bottom = -92.0
	_heart_history.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$Root.add_child(_heart_history)
	_heart_history.set_startup_reference(72.0)
	_heart_history.visible = false

	_breathing_history = Control.new()
	_breathing_history.set_script(SensorHistory)
	_breathing_history.title_text = "BREATHING RATE"
	_breathing_history.unit_text = "BREATHS/MIN"
	_breathing_history.accent = Color(0.42, 0.78, 0.92)
	_breathing_history.anchor_left = 1.0
	_breathing_history.anchor_right = 1.0
	_breathing_history.anchor_top = 1.0
	_breathing_history.anchor_bottom = 1.0
	_breathing_history.offset_left = -230.0
	_breathing_history.offset_right = -20.0
	_breathing_history.offset_top = -86.0
	_breathing_history.offset_bottom = -12.0
	_breathing_history.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$Root.add_child(_breathing_history)
	_breathing_history.set_startup_reference(14.0)
	_breathing_history.visible = false
	_sensor_status_label = null

func set_sensor_status(value: String) -> void:
	# Keep diagnostics in the editor/terminal, not on the player's gameplay HUD.
	if not _sensor_status_log_seen.has(value):
		print("[SteadyShot sensor] ", value)
		_sensor_status_log_seen.append(value)

func push_sensor_measurement(packet: Dictionary) -> void:
	var hr: Variant = packet.get("heart_rate", null)
	var br: Variant = packet.get("breathing_rate", null)
	var has_valid_heart: bool = hr is Dictionary and hr.has("value") and _valid_hud_sample(hr) and float(hr.value) >= 35.0 and float(hr.value) <= 210.0
	var has_valid_breathing: bool = br is Dictionary and br.has("value") and _valid_hud_sample(br) and float(br.value) >= 2.0 and float(br.value) <= 45.0
	if (has_valid_heart or has_valid_breathing) and not _sensor_received_any_real_data:
		_sensor_received_any_real_data = true
		# End both reference animations together once the first real metric arrives.
		_heart_history.stop_startup_reference()
		_breathing_history.stop_startup_reference()
	if has_valid_heart:
		_heart_history.add_value(float(hr.value))
	if has_valid_breathing:
		_breathing_history.add_value(float(br.value))

func _valid_hud_sample(sample: Dictionary) -> bool:
	var value: float = float(sample.get("value", NAN))
	var confidence: float = float(sample.get("confidence", 100.0))
	return is_finite(value) and confidence >= 25.0


func _build_wind_gauge() -> void:
	_wind_gauge = Control.new()
	_wind_gauge.set_script(WindGauge)
	_wind_gauge.anchor_left = 1.0
	_wind_gauge.anchor_right = 1.0
	_wind_gauge.offset_left = -190.0
	_wind_gauge.offset_right = -20.0
	_wind_gauge.offset_top = 258.0
	_wind_gauge.offset_bottom = 310.0
	$Root.add_child(_wind_gauge)
	_wind_gauge.visible = false


func _build_hint() -> void:
	_hint_panel = PanelContainer.new()
	_hint_panel.anchor_left = 0.5
	_hint_panel.anchor_right = 0.5
	_hint_panel.anchor_top = 1.0
	_hint_panel.anchor_bottom = 1.0
	_hint_panel.offset_left = -170.0
	_hint_panel.offset_right = 170.0
	_hint_panel.offset_top = -112.0
	_hint_panel.offset_bottom = -76.0
	_hint_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_panel.visible = false
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.05, 0.04, 0.7)
	style.border_color = Color(0.45, 1.0, 0.55, 0.4)
	style.set_border_width_all(1)
	style.set_corner_radius_all(16)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	_hint_panel.add_theme_stylebox_override("panel", style)
	$Root.add_child(_hint_panel)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_panel.add_child(row)
	var soft := Color(0.78, 0.95, 0.82, 0.95)
	var before := Label.new()
	before.text = "Press"
	_refine(before, 15, soft, false)
	row.add_child(before)
	var cap := PanelContainer.new()
	var cap_style := StyleBoxFlat.new()
	cap_style.bg_color = Color(0.45, 1.0, 0.55, 0.16)
	cap_style.border_color = Color(0.45, 1.0, 0.55, 0.7)
	cap_style.set_border_width_all(1)
	cap_style.set_corner_radius_all(5)
	cap_style.content_margin_left = 9
	cap_style.content_margin_right = 9
	cap_style.content_margin_top = 1
	cap_style.content_margin_bottom = 1
	cap.add_theme_stylebox_override("panel", cap_style)
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var key := Label.new()
	key.text = "N"
	_refine(key, 15, Color(0.7, 1.0, 0.75), false)
	cap.add_child(key)
	row.add_child(cap)
	_hint_after_label = Label.new()
	_hint_after_label.text = "for night vision"
	_refine(_hint_after_label, 15, soft, false)
	row.add_child(_hint_after_label)


func _build_storm_chip() -> void:
	_storm_chip = PanelContainer.new()
	_storm_chip.anchor_left = 1.0
	_storm_chip.anchor_right = 1.0
	_storm_chip.offset_left = -190.0
	_storm_chip.offset_right = -20.0
	_storm_chip.offset_top = 314.0
	_storm_chip.offset_bottom = 340.0
	_storm_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_storm_chip.visible = false
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.2, 0.14, 0.07, 0.65)
	style.border_color = Color(0.86, 0.66, 0.38, 0.6)
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.content_margin_top = 3
	style.content_margin_bottom = 3
	_storm_chip.add_theme_stylebox_override("panel", style)
	$Root.add_child(_storm_chip)
	var l := Label.new()
	l.text = "SANDSTORM"
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_refine(l, 12, Color(0.95, 0.8, 0.55), true)
	_storm_chip.add_child(l)


## Quiet, regular-weight text: no heavy outline, a faint shadow, optional letter spacing.
func _refine(l: Label, px: int, color: Color, caps: bool = false, font: Font = null) -> void:
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_color_override("font_color", color)
	l.add_theme_constant_override("outline_size", 0)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	if font != null:
		l.add_theme_font_override("font", font)
	elif caps:
		l.add_theme_font_override("font", _font_caps)


func show_hit_marker(headshot: bool) -> void:
	reticle.flash_hit(headshot)


func show_banner(text: String, seconds: float = 2.5) -> void:
	banner_label.text = text
	banner_label.modulate.a = 1.0
	if _banner_tween != null and _banner_tween.is_valid():
		_banner_tween.kill()
	_banner_tween = create_tween()
	_banner_tween.tween_interval(seconds)
	_banner_tween.tween_property(banner_label, "modulate:a", 0.0, 0.6)


func show_popup(text: String, color: Color) -> void:
	popup_label.text = text
	popup_label.add_theme_color_override("font_color", color)
	popup_label.modulate.a = 1.0
	if _popup_tween != null and _popup_tween.is_valid():
		_popup_tween.kill()
	_popup_tween = create_tween()
	_popup_tween.tween_interval(1.2)
	_popup_tween.tween_property(popup_label, "modulate:a", 0.0, 0.5)


func flash_damage() -> void:
	damage_flash.modulate.a = 0.5
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash_tween = create_tween()
	_flash_tween.tween_property(damage_flash, "modulate:a", 0.0, 0.6)


func show_menu(mode: String, data: Dictionary) -> void:
	menu.show_menu(mode, data)


func hide_menu() -> void:
	menu.hide_menu()
