extends Control
## Log in / sign up screen, shown when the game starts. Built entirely in code, same look as the
## menu. It talks to accounts.gd and only emits signals; the game manager decides what happens next.

signal authenticated(key: String, remember: bool)
signal guest_chosen
signal quit_pressed

const Accounts := preload("res://scripts/accounts.gd")

const AMBER := Color(0.93, 0.68, 0.25)
const CREAM := Color(0.96, 0.92, 0.82)
const DIM := Color(0.66, 0.61, 0.54)
const RED := Color(1.0, 0.45, 0.36)

var _mode := "login"
var _tab_login: Button
var _tab_signup: Button
var _user_edit: LineEdit
var _pass_edit: LineEdit
var _confirm_edit: LineEdit
var _confirm_box: Control
var _remember: CheckBox
var _error: Label
var _primary: Button
var _click: AudioStreamPlayer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_build()
	_click = AudioStreamPlayer.new()
	if ResourceLoader.exists("res://audio/ui_click.wav"):
		_click.stream = load("res://audio/ui_click.wav")
	add_child(_click)


func show_auth(prefill_username: String = "") -> void:
	visible = true
	_set_shared_brand_visible(true)
	_set_mode("login")
	_user_edit.text = prefill_username
	_pass_edit.text = ""
	_confirm_edit.text = ""
	_error.text = ""
	if prefill_username != "":
		_pass_edit.grab_focus()
	else:
		_user_edit.grab_focus()


func hide_auth() -> void:
	visible = false
	_set_shared_brand_visible(false)
	_pass_edit.text = ""
	_confirm_edit.text = ""


func _set_shared_brand_visible(show_brand: bool) -> void:
	var hud := get_parent().get_parent()
	if hud != null and hud.has_method("set_auth_brand_visible"):
		hud.set_auth_brand_visible(show_brand)


# ---------------------------------------------------------------- building

func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.02, 0.015, 0.82)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(500, 0)
	panel.add_theme_stylebox_override("panel", _panel_style(Color(0.07, 0.062, 0.055, 0.97), AMBER, 2, 16))
	center.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 30)
	panel.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	margin.add_child(box)

	var title := _label("S T E A D Y S H O T", 38, AMBER)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var sub := _label("PLAYER ACCOUNT", 14, DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	box.add_child(tabs)
	_tab_login = _tab_button("LOG IN", "login")
	_tab_signup = _tab_button("SIGN UP", "signup")
	tabs.add_child(_tab_login)
	tabs.add_child(_tab_signup)

	box.add_child(_field_caption("USERNAME"))
	_user_edit = _line_edit("3 to 16 letters, numbers or _", false)
	box.add_child(_user_edit)
	box.add_child(_field_caption("PASSWORD"))
	_pass_edit = _line_edit("at least 6 characters", true)
	box.add_child(_pass_edit)

	var cbox := VBoxContainer.new()
	cbox.add_theme_constant_override("separation", 12)
	cbox.add_child(_field_caption("CONFIRM PASSWORD"))
	_confirm_edit = _line_edit("type it again", true)
	cbox.add_child(_confirm_edit)
	_confirm_box = cbox
	box.add_child(cbox)

	_remember = CheckBox.new()
	_remember.text = "Keep me signed in on this computer"
	_remember.add_theme_font_size_override("font_size", 14)
	_remember.add_theme_color_override("font_color", DIM)
	_remember.add_theme_color_override("font_hover_color", CREAM)
	_remember.add_theme_color_override("font_pressed_color", CREAM)
	box.add_child(_remember)

	_error = _label("", 14, RED)
	_error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_error.custom_minimum_size = Vector2(0, 20)
	box.add_child(_error)

	_primary = _action_button("LOG IN", true)
	_primary.pressed.connect(_on_primary)
	box.add_child(_primary)

	var or_row := HBoxContainer.new()
	or_row.add_theme_constant_override("separation", 12)
	or_row.add_child(_rule())
	or_row.add_child(_label("or", 13, DIM))
	or_row.add_child(_rule())
	box.add_child(or_row)

	var guest := _action_button("PLAY AS GUEST", false)
	guest.pressed.connect(_on_guest)
	box.add_child(guest)

	var quit_button := _action_button("EXIT GAME", false)
	quit_button.pressed.connect(func(): quit_pressed.emit())
	box.add_child(quit_button)

	var note := _label("Accounts are stored on this computer only. Guest scores are kept separately.", 12, DIM)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(note)

	_user_edit.text_submitted.connect(_on_user_submitted)
	_pass_edit.text_submitted.connect(_on_pass_submitted)
	_confirm_edit.text_submitted.connect(_on_confirm_submitted)
	_set_mode("login")


# ---------------------------------------------------------------- behaviour

func _set_mode(mode: String) -> void:
	_mode = mode
	var signup := mode == "signup"
	_confirm_box.visible = signup
	_primary.text = "CREATE ACCOUNT" if signup else "LOG IN"
	_style_tab(_tab_login, not signup)
	_style_tab(_tab_signup, signup)
	_error.text = ""
	_pass_edit.placeholder_text = "at least 6 characters" if signup else "your password"


func _on_tab(mode: String) -> void:
	_click.play()
	_set_mode(mode)


func _on_user_submitted(_t: String) -> void:
	_pass_edit.grab_focus()


func _on_pass_submitted(_t: String) -> void:
	if _mode == "signup":
		_confirm_edit.grab_focus()
	else:
		_submit()


func _on_confirm_submitted(_t: String) -> void:
	_submit()


func _on_primary() -> void:
	_click.play()
	_submit()


func _on_guest() -> void:
	_click.play()
	guest_chosen.emit()


func _submit() -> void:
	var username := _user_edit.text.strip_edges()
	var password := _pass_edit.text
	var err := ""
	# Private local developer login; never creates or stores a normal account.
	if _mode == "login" and username == "-dev" and password == "-mode":
		_error.text = "DEVELOPER MODE ENABLED"
		_error.add_theme_color_override("font_color", AMBER)
		_authenticated_dev()
		return
	if _mode == "signup":
		if password != _confirm_edit.text:
			err = "The two passwords do not match."
		else:
			err = Accounts.create(username, password)
	else:
		if username == "" or password == "":
			err = "Enter your username and password."
		else:
			err = Accounts.verify(username, password)
	if err != "":
		_error.text = err
		_error.add_theme_color_override("font_color", RED)
		return
	Accounts.set_last_username(username)
	authenticated.emit(Accounts.key_of(username), _remember.button_pressed)


func _authenticated_dev() -> void:
	authenticated.emit("__DEV__", false)


# ---------------------------------------------------------------- styling helpers

func _label(text: String, px: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	return l


func _field_caption(text: String) -> Label:
	return _label(text, 12, DIM)


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
	r.color = Color(0.93, 0.68, 0.25, 0.3)
	r.custom_minimum_size = Vector2(0, 1)
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


func _line_edit(placeholder: String, secret: bool) -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = placeholder
	e.secret = secret
	e.max_length = 64
	e.custom_minimum_size = Vector2(0, 42)
	e.add_theme_font_size_override("font_size", 17)
	e.add_theme_color_override("font_color", CREAM)
	e.add_theme_color_override("font_placeholder_color", Color(0.5, 0.46, 0.4))
	e.add_theme_color_override("caret_color", AMBER)
	e.add_theme_stylebox_override("normal", _edit_style(Color(0.12, 0.105, 0.09), Color(0.35, 0.28, 0.17)))
	e.add_theme_stylebox_override("focus", _edit_style(Color(0.14, 0.12, 0.1), AMBER))
	return e


func _edit_style(bg: Color, border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(1)
	s.set_corner_radius_all(8)
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s


func _tab_button(text: String, mode: String) -> Button:
	var b := Button.new()
	b.text = text
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(0, 38)
	b.add_theme_font_size_override("font_size", 15)
	b.pressed.connect(_on_tab.bind(mode))
	b.add_theme_stylebox_override("focus", _panel_style(Color(0, 0, 0, 0), Color(1, 1, 1, 0.3), 1, 8))
	return b


func _style_tab(b: Button, active: bool) -> void:
	var bg := Color(0.45, 0.3, 0.09) if active else Color(0.11, 0.095, 0.082)
	var border := AMBER if active else Color(0.3, 0.24, 0.15)
	b.add_theme_stylebox_override("normal", _panel_style(bg, border, 1, 8))
	b.add_theme_stylebox_override("hover", _panel_style(bg.lightened(0.1), border, 1, 8))
	b.add_theme_stylebox_override("pressed", _panel_style(bg, border, 1, 8))
	b.add_theme_color_override("font_color", CREAM if active else DIM)
	b.add_theme_color_override("font_hover_color", Color(1, 1, 1))


func _action_button(text: String, primary: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 48)
	b.add_theme_font_size_override("font_size", 18)
	b.add_theme_color_override("font_color", CREAM)
	b.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	var bg := Color(0.5, 0.33, 0.1) if primary else Color(0.13, 0.11, 0.09)
	var border := AMBER if primary else Color(0.4, 0.32, 0.2)
	b.add_theme_stylebox_override("normal", _panel_style(bg, border, 2, 10))
	b.add_theme_stylebox_override("hover", _panel_style(bg.lightened(0.15), Color(1.0, 0.82, 0.45), 2, 10))
	b.add_theme_stylebox_override("pressed", _panel_style(bg.darkened(0.15), border, 2, 10))
	b.add_theme_stylebox_override("focus", _panel_style(Color(0, 0, 0, 0), Color(1, 1, 1, 0.5), 2, 10))
	return b
