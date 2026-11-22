extends Control
## Compact history of actual Presage rate estimates. Startup references are display-only
## animation and are never sent to gameplay or added to the measured history.

var title_text: String = "HEART RATE"
var unit_text: String = "BPM"
var accent: Color = Color(0.95, 0.68, 0.25)
var values: Array[float] = []
var sample_times: Array[float] = []
var latest: float = NAN
var preview_value: float = NAN
var has_real_measurement: bool = false
var _preview_time: float = 0.0
var _elapsed: float = 0.0
const STARTUP_REFERENCE_SECONDS: float = 180.0
const HISTORY_LIMIT: int = 60
const MAX_VISIBLE_SAMPLE_GAP: float = 20.0

func set_startup_reference(value: float) -> void:
	if has_real_measurement or _preview_time >= STARTUP_REFERENCE_SECONDS:
		return
	preview_value = value
	latest = NAN
	queue_redraw()

func stop_startup_reference() -> void:
	# Called as soon as either Presage metric becomes real, so the HUD never
	# mixes a synthetic startup reference with a live sensor session.
	if not has_real_measurement:
		preview_value = NAN
		latest = NAN
		queue_redraw()

func add_value(value: float) -> void:
	if not is_finite(value):
		return
	# The first real sample permanently replaces the startup reference for this session.
	if not has_real_measurement:
		values.clear()
		sample_times.clear()
		has_real_measurement = true
		preview_value = NAN
	values.append(value)
	sample_times.append(_elapsed)
	while values.size() > HISTORY_LIMIT:
		values.pop_front()
		sample_times.pop_front()
	latest = value
	queue_redraw()

func _process(delta: float) -> void:
	_elapsed += delta
	if visible and not has_real_measurement and is_finite(preview_value):
		_preview_time += delta
		if _preview_time >= STARTUP_REFERENCE_SECONDS:
			preview_value = NAN
			latest = NAN
		queue_redraw()

func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.035, 0.032, 0.028, 0.82), true)
	draw_rect(Rect2(Vector2.ZERO, size), Color(accent.r, accent.g, accent.b, 0.32), false, 1.0)
	var font: Font = ThemeDB.fallback_font
	draw_string(font, Vector2(9.0, 15.0), title_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 9, accent)
	var value_text: String = "—" if not is_finite(latest) else "%.0f" % latest
	var value_width: float = font.get_string_size(value_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 15).x
	var unit_width: float = font.get_string_size(unit_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 8).x
	draw_string(font, Vector2(w - value_width - unit_width - 15.0, 17.0), value_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 15, Color(0.96, 0.92, 0.82))
	draw_string(font, Vector2(w - unit_width - 7.0, 15.0), unit_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 8, Color(0.72, 0.68, 0.6))
	var graph: Rect2 = Rect2(9.0, 23.0, w - 18.0, h - 28.0)
	draw_line(Vector2(graph.position.x, graph.end.y), graph.end, Color(1.0, 1.0, 1.0, 0.09), 1.0)
	if has_real_measurement and not values.is_empty():
		var min_v: float = float(values.min())
		var max_v: float = float(values.max())
		var span: float = maxf(max_v - min_v, 2.0)
		var points: PackedVector2Array = PackedVector2Array()
		for i in range(values.size()):
			var x: float = graph.position.x + graph.size.x * float(i) / float(maxi(values.size() - 1, 1))
			var y: float = graph.end.y - ((values[i] - min_v) / span) * graph.size.y
			points.append(Vector2(x, y))
		for i in range(points.size()):
			if i > 0 and sample_times[i] - sample_times[i - 1] <= MAX_VISIBLE_SAMPLE_GAP:
				draw_line(points[i - 1], points[i], accent, 1.7, true)
			draw_circle(points[i], 1.6, accent)
	elif is_finite(preview_value):
		# Gentle reference-only motion during initial sensor acquisition. It is never a reading.
		var points: PackedVector2Array = PackedVector2Array()
		for i in range(25):
			var t: float = float(i) / 24.0
			var x: float = graph.position.x + graph.size.x * t
			var y: float = graph.position.y + graph.size.y * (0.52 + sin(t * TAU * 1.35 + _preview_time * 1.1) * 0.055)
			points.append(Vector2(x, y))
		draw_polyline(points, Color(accent.r, accent.g, accent.b, 0.48), 1.4, true)
