extends Control
## Session-only API key prompt. The key is masked and never saved by the game.
signal start_requested(api_key: String)
signal skip_requested
signal quit_pressed

const AMBER := Color(0.93, 0.68, 0.25)
const CREAM := Color(0.96, 0.92, 0.82)
const DIM := Color(0.66, 0.61, 0.54)
var _key: LineEdit
var _error: Label

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_build()


func _set_shared_brand_visible(show_brand: bool) -> void:
	var hud := get_parent().get_parent()
	if hud != null and hud.has_method("set_auth_brand_visible"):
		hud.set_auth_brand_visible(show_brand)


func show_setup() -> void:
	visible = true
	_set_shared_brand_visible(true)
	_key.text = ""
	_error.text = ""
	_key.grab_focus()

func hide_setup() -> void:
	visible = false
	_set_shared_brand_visible(false)
	_key.text = ""

func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.025, 0.02, 0.015, 0.88)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(540, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.062, 0.055, 0.98)
	style.border_color = AMBER
	style.set_border_width_all(2)
	style.set_corner_radius_all(14)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 30)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 13)
	margin.add_child(box)
	var title := Label.new()
	title.text = "PRESAGE SENSOR SETUP"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 27)
	title.add_theme_color_override("font_color", AMBER)
	box.add_child(title)
	var desc := Label.new()
	desc.text = "Connect your webcam to let heart rate and breathing influence rifle stability. Keep one face and your upper chest visible, face the camera, sit still, and use bright even lighting."
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.add_theme_color_override("font_color", DIM)
	box.add_child(desc)
	var cap := Label.new()
	cap.text = "SMARTSPECTRA API KEY"
	cap.add_theme_color_override("font_color", CREAM)
	box.add_child(cap)
	_key = LineEdit.new()
	_key.placeholder_text = "Paste your Presage API key"
	_key.secret = true
	_key.max_length = 512
	_key.text_submitted.connect(func(_submitted: String): _submit())
	_key.custom_minimum_size.y = 44
	_key.add_theme_font_size_override("font_size", 17)
	box.add_child(_key)
	_error = Label.new()
	_error.text = ""
	_error.add_theme_color_override("font_color", Color(1, 0.48, 0.35))
	box.add_child(_error)
	var start := Button.new()
	start.text = "CONNECT SENSOR"
	start.custom_minimum_size.y = 48
	start.pressed.connect(_submit)
	box.add_child(start)
	var skip := Button.new()
	skip.text = "CONTINUE WITHOUT SENSOR"
	skip.custom_minimum_size.y = 42
	skip.pressed.connect(func(): skip_requested.emit())
	box.add_child(skip)
	var quit_button := Button.new()
	quit_button.text = "EXIT GAME"
	quit_button.custom_minimum_size.y = 38
	quit_button.pressed.connect(func(): quit_pressed.emit())
	box.add_child(quit_button)
	var note := Label.new()
	note.text = "The key is used only for this session and is not saved. First-time sensor setup automatically installs its components (internet required). You can still play without the sensor."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", 12)
	note.add_theme_color_override("font_color", DIM)
	box.add_child(note)

func _submit() -> void:
	var value := _key.text.strip_edges()
	if value.is_empty():
		_error.text = "Enter an API key, or continue without the sensor."
		return
	start_requested.emit(value)
	_key.text = ""

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_key.text = ""
