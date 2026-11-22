extends Control
## Title, pause and game-over screen in one: a stat strip across the top, audio sliders on the
## left, the saved scoreboard on the right and the action buttons underneath.
## Built entirely in code. It only emits signals; the game manager decides what they do.

signal start_pressed
signal deploy_pressed
signal briefing_back_pressed
signal resume_pressed
signal restart_pressed
signal logout_pressed
signal quit_pressed
signal volume_changed(key: String, value: float)
signal volume_released(key: String)

const AMBER := Color(0.93, 0.68, 0.25)
const CREAM := Color(0.96, 0.92, 0.82)
const DIM := Color(0.66, 0.61, 0.54)
const RED := Color(1.0, 0.38, 0.3)
const AudioBuses := preload("res://scripts/audio_buses.gd")

const STAT_NAMES := {
	"score": "SCORE", "wave": "WAVE", "kills": "KILLS",
	"headshots": "HEADSHOTS", "accuracy": "ACCURACY", "longest": "LONGEST SHOT",
	"reaction": "FIRST SHOT", "consistency": "SHOT CONSISTENCY",
}
const SLIDERS := [
	["master", "MASTER"], ["sfx", "WEAPON & EFFECTS"], ["ambient", "WIND & AMBIENCE"],
]
const BRIEFING := "Hold the cliff. Enemy infantry are crossing the valley toward your position.\nStop them before they reach the breach line (red flags) - each one that gets through costs a life.\n\nMouse  aim        Left click  fire (6 rounds)        R  reload (automatic when empty)        Right click  scope\nMouse wheel  4x / 8x / 12x        Sensor-driven sway        WASD  move along the ledge        Esc  pause\nBreathing rhythm affects shot consistency: firing during an unstable phase is less predictable.\nEvery 3rd wave is night: press N and the scope switches to night vision (it only works through the scope).\nEvery 5th wave brings a sandstorm that cuts your view - day or night.\n\nBullets take time to arrive, drop, and drift in the wind. Use the mil-dots and lead your target."

var _mode_label: Label
var _user_label: Label
var _score_title: Label
var _briefing: Label
var _commander_line: Label
var _commander_voice: AudioStreamPlayer
var _briefing_music: AudioStreamPlayer
var _briefing_music_tween: Tween
var _ambient_volume_before_briefing := 0.0
var _ambient_duck_active := false
var _ambient_restore_tween: Tween
var _consistency_summary: Label
var _stats_grid: GridContainer
var _stat_values := {}
var _sliders := {}
var _slider_pct := {}
var _score_grid: GridContainer
var _buttons: HBoxContainer
var _root_box: VBoxContainer
var _body: HBoxContainer
var _hint: Label
var _click: AudioStreamPlayer
var _knob: ImageTexture
var _knob_hi: ImageTexture
var _filling := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	AudioBuses.ensure()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_knob = _make_knob(AMBER)
	_knob_hi = _make_knob(Color(1.0, 0.85, 0.5))
	_build()
	_click = AudioStreamPlayer.new()
	if ResourceLoader.exists("res://audio/ui_click.wav"):
		_click.stream = load("res://audio/ui_click.wav")
	add_child(_click)
	_commander_voice = AudioStreamPlayer.new()
	_commander_voice.volume_db = -3.0
	if ResourceLoader.exists("res://audio/commander_briefing.mp3"):
		_commander_voice.stream = load("res://audio/commander_briefing.mp3")
	elif ResourceLoader.exists("res://audio/commander_briefing.wav"):
		_commander_voice.stream = load("res://audio/commander_briefing.wav")
	add_child(_commander_voice)
	_commander_voice.finished.connect(_stop_briefing_music_only)
	_briefing_music = AudioStreamPlayer.new()
	_briefing_music.name = "BriefingMusic"
	_briefing_music.bus = AudioBuses.BRIEFING
	_briefing_music.volume_db = -21.5
	if ResourceLoader.exists("res://audio/nastelbom-dark-trailer-638572.mp3"):
		_briefing_music.stream = load("res://audio/nastelbom-dark-trailer-638572.mp3")
	elif ResourceLoader.exists("res://audio/briefing_music.wav"):
		_briefing_music.stream = load("res://audio/briefing_music.wav")
	_briefing_music.stream_paused = false
	_briefing_music.finished.connect(_on_briefing_music_finished)
	add_child(_briefing_music)


# ---------------------------------------------------------------- public

func show_menu(mode: String, data: Dictionary) -> void:
	visible = true
	# Restore the standard button-before-hint order for title, pause and results.
	if _root_box != null and _buttons != null and _hint != null and _buttons.get_index() > _hint.get_index():
		_root_box.move_child(_buttons, _hint.get_index() - 1)
	var is_title := mode == "title"
	_briefing.visible = is_title
	_commander_line.visible = false
	_stop_briefing_audio()
	_stats_grid.visible = not is_title
	_consistency_summary.visible = not is_title
	_body.visible = true
	var best := int(data.get("best", 0))
	if mode == "title":
		_briefing.text = BRIEFING
		_mode_label.text = "BRIEFING        BEST SCORE  %d" % best
		_mode_label.add_theme_color_override("font_color", CREAM)
	elif mode == "paused":
		_mode_label.text = "PAUSED"
		_mode_label.add_theme_color_override("font_color", CREAM)
	else:
		_mode_label.text = "MISSION FAILED"
		_mode_label.add_theme_color_override("font_color", RED)
	var who := str(data.get("user", "Guest"))
	_user_label.text = "PLAYER   %s" % who.to_upper()
	_score_title.text = "SCOREBOARD   -   %s" % who.to_upper()
	_fill_stats(data)
	_fill_volumes(data)
	_fill_scores(data)
	_fill_buttons(mode)
	if mode == "paused":
		_hint.text = "ESC / ENTER  resume"
	elif mode == "title":
		_hint.text = "ENTER  start"
	else:
		_hint.text = "ENTER  play again"


func show_mission_briefing(data: Dictionary) -> void:
	visible = true
	# The briefing-only Skip control sits at the bottom edge of the panel.
	if _root_box != null and _hint != null and _buttons != null and _hint.get_index() > _buttons.get_index():
		_root_box.move_child(_hint, _buttons.get_index())
	_mode_label.text = "FIELD ORDERS  /  DEPLOYMENT"
	_mode_label.add_theme_color_override("font_color", AMBER)
	_briefing.visible = true
	_briefing.text = "The fort is the last line of defence. Enemy infantry are advancing through the valley. Hold your position, watch your breathing, and make every round count."
	_commander_line.visible = true
	_stats_grid.visible = false
	_consistency_summary.visible = false
	_body.visible = false
	_user_label.text = "PLAYER   %s" % str(data.get("user", "Guest")).to_upper()
	_score_title.text = "SCOREBOARD   -   %s" % str(data.get("user", "Guest")).to_upper()
	_fill_volumes(data)
	_fill_scores(data)
	_fill_buttons("mission_briefing")
	_hint.text = "THE COMMANDER IS ON THE RADIO  /  DEPLOY WHEN READY"
	_start_briefing_audio()


func hide_menu() -> void:
	visible = false
	_stop_briefing_audio()


func _start_briefing_audio() -> void:
	_duck_ambient_for_speech()
	if _briefing_music_tween != null and _briefing_music_tween.is_valid():
		_briefing_music_tween.kill()
	if _briefing_music != null:
		_briefing_music.stop()
	if _commander_voice != null:
		_commander_voice.play()
	if _briefing_music != null and _briefing_music.stream != null:
		_briefing_music.volume_db = -27.0
		_briefing_music.play()
		_briefing_music_tween = create_tween()
		_briefing_music_tween.tween_property(_briefing_music, "volume_db", -21.5, 1.8)


func _duck_ambient_for_speech() -> void:
	var idx := AudioServer.get_bus_index(AudioBuses.AMBIENT)
	if idx < 0:
		return
	if _ambient_restore_tween != null and _ambient_restore_tween.is_valid():
		_ambient_restore_tween.kill()
	_ambient_volume_before_briefing = AudioServer.get_bus_volume_db(idx)
	_ambient_duck_active = true
	AudioServer.set_bus_volume_db(idx, -42.0)


func _restore_ambient_after_speech(duration: float = 1.0) -> void:
	if not _ambient_duck_active:
		return
	var idx := AudioServer.get_bus_index(AudioBuses.AMBIENT)
	_ambient_duck_active = false
	if idx < 0:
		return
	if _ambient_restore_tween != null and _ambient_restore_tween.is_valid():
		_ambient_restore_tween.kill()
	_ambient_restore_tween = create_tween()
	_ambient_restore_tween.tween_method(
		_set_ambient_bus_volume,
		-42.0, _ambient_volume_before_briefing, duration
	)


func _set_ambient_bus_volume(value: float) -> void:
	var idx := AudioServer.get_bus_index(AudioBuses.AMBIENT)
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, value)


func _stop_briefing_audio() -> void:
	_restore_ambient_after_speech(0.7)
	if _briefing_music_tween != null and _briefing_music_tween.is_valid():
		_briefing_music_tween.kill()
	if _briefing_music != null and _briefing_music.playing:
		_briefing_music_tween = create_tween()
		_briefing_music_tween.tween_property(_briefing_music, "volume_db", -50.0, 0.65)
		_briefing_music_tween.tween_callback(_briefing_music.stop)
	if _commander_voice != null:
		_commander_voice.stop()


func _on_briefing_music_finished() -> void:
	if visible and _commander_line.visible and _commander_voice != null and _commander_voice.playing:
		_briefing_music.play()


func _stop_briefing_music_only() -> void:
	_restore_ambient_after_speech(1.8)
	if _briefing_music != null and _briefing_music.playing:
		if _briefing_music_tween != null and _briefing_music_tween.is_valid():
			_briefing_music_tween.kill()
		_briefing_music_tween = create_tween()
		_briefing_music_tween.tween_property(_briefing_music, "volume_db", -50.0, 1.8)
		_briefing_music_tween.tween_callback(_briefing_music.stop)


# ---------------------------------------------------------------- building

func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.02, 0.015, 0.74)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(1060, 0)
	panel.add_theme_stylebox_override("panel", _panel_style(Color(0.07, 0.062, 0.055, 0.96), AMBER, 2, 16))
	center.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	panel.add_child(margin)

	var root := VBoxContainer.new()
	_root_box = root
	root.add_theme_constant_override("separation", 14)
	margin.add_child(root)

	var title := _label("S T E A D Y S H O T", 46, AMBER)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(title)
	_mode_label = _label("PAUSED", 24, CREAM)
	_mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_mode_label)
	_user_label = _label("", 14, DIM)
	_user_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_user_label)
	root.add_child(_rule())

	_briefing = _label(BRIEFING, 17, CREAM)
	_briefing.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_briefing.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_briefing.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(_briefing)
	_commander_line = _label("\"Soldier... if you're hearing this, then I've fallen. There will be no reinforcements. No one coming to save you. Only the endless tide of hell marching towards those walls. So take your position, steady your aim, and let them come. If death finds you today, meet it with your rifle in hand and fire in your heart. Let the gates of Valhalla open wide, for you shall not enter them quietly. Make them remember you, soldier. Make them fear the very ground you stand upon. Hold the fortress... until your final breath.\"", 16, AMBER)
	_commander_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_commander_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_commander_line.visible = false
	root.add_child(_commander_line)

	_stats_grid = GridContainer.new()
	_stats_grid.columns = 4
	_stats_grid.add_theme_constant_override("h_separation", 10)
	root.add_child(_stats_grid)
	for key in STAT_NAMES.keys():
		var tile := PanelContainer.new()
		tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tile.add_theme_stylebox_override("panel", _panel_style(Color(0.15, 0.125, 0.1, 0.95), Color(0.35, 0.27, 0.15), 1, 8))
		var box := VBoxContainer.new()
		var cap := _label(STAT_NAMES[key], 13, DIM)
		cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var val := _label("0", 32, CREAM)
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(cap)
		box.add_child(val)
		tile.add_child(box)
		_stats_grid.add_child(tile)
		_stat_values[key] = val
	_consistency_summary = _label("SHOT CONDITIONS  ·  STEADY: 0    MODERATE: 0    UNSTABLE: 0", 12, DIM)
	_consistency_summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_consistency_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_consistency_summary.add_theme_font_size_override("font_size", 14)
	root.add_child(_consistency_summary)

	root.add_child(_rule())

	_body = HBoxContainer.new()
	_body.add_theme_constant_override("separation", 18)
	root.add_child(_body)
	_body.add_child(_build_audio_card())
	_body.add_child(_build_score_card())

	root.add_child(_rule())
	_buttons = HBoxContainer.new()
	_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	_buttons.add_theme_constant_override("separation", 18)
	root.add_child(_buttons)
	_hint = _label("", 14, DIM)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_hint)


func _build_audio_card() -> Control:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", _panel_style(Color(0.11, 0.095, 0.082, 0.95), Color(0.3, 0.24, 0.15), 1, 10))
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	card.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	margin.add_child(box)
	box.add_child(_label("AUDIO", 20, AMBER))
	for entry in SLIDERS:
		var key: String = entry[0]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var name_label := _label(entry[1], 15, CREAM)
		name_label.custom_minimum_size = Vector2(170, 0)
		row.add_child(name_label)
		var slider := HSlider.new()
		slider.min_value = 0.0
		slider.max_value = 1.0
		slider.step = 0.01
		slider.value = 1.0
		slider.custom_minimum_size = Vector2(180, 26)
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_style_slider(slider)
		var pct := _label("100%", 15, AMBER)
		pct.custom_minimum_size = Vector2(50, 0)
		pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		slider.value_changed.connect(_on_slider_changed.bind(key))
		slider.drag_ended.connect(_on_slider_released.bind(key))
		row.add_child(slider)
		row.add_child(pct)
		box.add_child(row)
		_sliders[key] = slider
		_slider_pct[key] = pct
	var note := _label("Let go of a slider to hear a sample.", 13, DIM)
	box.add_child(note)
	return card


func _build_score_card() -> Control:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", _panel_style(Color(0.11, 0.095, 0.082, 0.95), Color(0.3, 0.24, 0.15), 1, 10))
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	card.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)
	_score_title = _label("SCOREBOARD", 20, AMBER)
	box.add_child(_score_title)
	_score_grid = GridContainer.new()
	_score_grid.columns = 5
	_score_grid.add_theme_constant_override("h_separation", 14)
	_score_grid.add_theme_constant_override("v_separation", 4)
	box.add_child(_score_grid)
	return card


# ---------------------------------------------------------------- filling

func _fill_stats(data: Dictionary) -> void:
	_stat_values["score"].text = str(int(data.get("score", 0)))
	_stat_values["wave"].text = str(int(data.get("wave", 0)))
	_stat_values["kills"].text = str(int(data.get("kills", 0)))
	_stat_values["headshots"].text = str(int(data.get("headshots", 0)))
	_stat_values["accuracy"].text = "%d%%" % int(data.get("accuracy", 0))
	_stat_values["longest"].text = "%d m" % int(data.get("longest", 0))
	var reaction_ms: int = int(data.get("reaction_ms", 0))
	_stat_values["reaction"].text = "%.1f s" % (float(reaction_ms) / 1000.0) if reaction_ms > 0 else "—"
	_stat_values["consistency"].text = "%d%%" % int(data.get("consistency", 0)) if int(data.get("consistency_samples", 0)) > 0 else "—"
	var rated := int(data.get("consistency_samples", 0))
	var fired := int(data.get("shots_fired", 0))
	_consistency_summary.text = "RATED SHOTS: %d / %d     STEADY: %d     MODERATE: %d     UNSTABLE: %d     UNRATED: %d" % [rated, fired, int(data.get("steady_shots", 0)), int(data.get("mixed_shots", 0)), int(data.get("unstable_shots", 0)), int(data.get("unrated_shots", 0))]


func _fill_volumes(data: Dictionary) -> void:
	var vols: Dictionary = data.get("volumes", {})
	_filling = true
	for key in _sliders.keys():
		var v := clampf(float(vols.get(key, 1.0)), 0.0, 1.0)
		_sliders[key].value = v
		_slider_pct[key].text = "%d%%" % int(round(v * 100.0))
	_filling = false


func _fill_scores(data: Dictionary) -> void:
	for c in _score_grid.get_children():
		_score_grid.remove_child(c)
		c.queue_free()
	for h in ["#", "SCORE", "WAVE", "KILLS", "DATE"]:
		var hl := _label(h, 13, DIM)
		_score_grid.add_child(hl)
	var scores: Array = data.get("scores", [])
	var highlight := int(data.get("highlight", -1))
	if scores.is_empty():
		for i in 5:
			_score_grid.add_child(_label("-" if i < 2 else "", 15, DIM))
		return
	for i in mini(scores.size(), 6):
		var e: Dictionary = scores[i]
		var col := AMBER if i == highlight else CREAM
		_score_grid.add_child(_label("%d" % (i + 1), 16, col))
		_score_grid.add_child(_label(str(int(e.get("score", 0))), 16, col))
		_score_grid.add_child(_label(str(int(e.get("wave", 0))), 16, col))
		_score_grid.add_child(_label(str(int(e.get("kills", 0))), 16, col))
		_score_grid.add_child(_label(str(e.get("date", "")), 14, col if i == highlight else DIM))


func _fill_buttons(mode: String) -> void:
	for c in _buttons.get_children():
		_buttons.remove_child(c)
		c.queue_free()
	if mode == "title":
		_buttons.add_child(_button("START MISSION", start_pressed))
		_buttons.add_child(_button("SWITCH ACCOUNT", logout_pressed))
		_buttons.add_child(_button("EXIT GAME", quit_pressed))
	elif mode == "paused":
		_buttons.add_child(_button("RESUME", resume_pressed))
		_buttons.add_child(_button("RESTART", restart_pressed))
		_buttons.add_child(_button("EXIT GAME", quit_pressed))
	elif mode == "mission_briefing":
		var skip_button := _button("SKIP", deploy_pressed)
		skip_button.custom_minimum_size = Vector2(180, 48)
		_buttons.add_child(skip_button)
	else:
		_buttons.add_child(_button("PLAY AGAIN", restart_pressed))
		_buttons.add_child(_button("SWITCH ACCOUNT", logout_pressed))
		_buttons.add_child(_button("EXIT GAME", quit_pressed))


# ---------------------------------------------------------------- callbacks

func _on_slider_changed(value: float, key: String) -> void:
	_slider_pct[key].text = "%d%%" % int(round(value * 100.0))
	if not _filling:
		volume_changed.emit(key, value)


func _on_slider_released(_value_changed: bool, key: String) -> void:
	volume_released.emit(key)


func _on_button(sig: Signal) -> void:
	_click.play()
	sig.emit()


# ---------------------------------------------------------------- styling helpers

func _label(text: String, font_px: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_px)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", maxi(int(font_px / 8.0), 2))
	return l


func _panel_style(bg: Color, border: Color, border_width: int, radius: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_width)
	s.set_corner_radius_all(radius)
	s.shadow_color = Color(0, 0, 0, 0.55)
	s.shadow_size = 18
	return s


func _rule() -> Control:
	var r := ColorRect.new()
	r.color = Color(0.93, 0.68, 0.25, 0.35)
	r.custom_minimum_size = Vector2(0, 2)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


func _button(text: String, sig: Signal) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(250, 54)
	b.add_theme_font_size_override("font_size", 22)
	b.add_theme_color_override("font_color", CREAM)
	b.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	b.add_theme_stylebox_override("normal", _panel_style(Color(0.5, 0.33, 0.1), AMBER, 2, 10))
	b.add_theme_stylebox_override("hover", _panel_style(Color(0.75, 0.5, 0.14), Color(1.0, 0.82, 0.45), 2, 10))
	b.add_theme_stylebox_override("pressed", _panel_style(Color(0.38, 0.25, 0.08), AMBER, 2, 10))
	b.add_theme_stylebox_override("focus", _panel_style(Color(0, 0, 0, 0), Color(1, 1, 1, 0.5), 2, 10))
	b.pressed.connect(_on_button.bind(sig))
	return b


func _style_slider(s: HSlider) -> void:
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.22, 0.19, 0.15)
	track.set_corner_radius_all(4)
	track.content_margin_top = 4
	track.content_margin_bottom = 4
	var fill := StyleBoxFlat.new()
	fill.bg_color = AMBER
	fill.set_corner_radius_all(4)
	fill.content_margin_top = 4
	fill.content_margin_bottom = 4
	var fill_hi := StyleBoxFlat.new()
	fill_hi.bg_color = Color(1.0, 0.8, 0.4)
	fill_hi.set_corner_radius_all(4)
	fill_hi.content_margin_top = 4
	fill_hi.content_margin_bottom = 4
	s.add_theme_stylebox_override("slider", track)
	s.add_theme_stylebox_override("grabber_area", fill)
	s.add_theme_stylebox_override("grabber_area_highlight", fill_hi)
	s.add_theme_icon_override("grabber", _knob)
	s.add_theme_icon_override("grabber_highlight", _knob_hi)
	s.add_theme_icon_override("grabber_disabled", _knob)


func _make_knob(color: Color) -> ImageTexture:
	var px := 22
	var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
	var c := (px - 1) * 0.5
	for y in px:
		for x in px:
			var d := Vector2(x - c, y - c).length()
			var a := clampf((c - d) + 0.5, 0.0, 1.0)
			var edge := clampf((c - 3.0 - d) + 0.5, 0.0, 1.0)
			var col := Color(0.12, 0.09, 0.05).lerp(color, edge)
			img.set_pixel(x, y, Color(col.r, col.g, col.b, a))
	return ImageTexture.create_from_image(img)
