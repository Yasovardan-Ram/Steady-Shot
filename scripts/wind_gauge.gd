extends Control
## A small, quiet wind gauge: a thin scale with a marker showing which way, and how hard, the
## wind will push your bullet. Replaces the plain "WIND >>> 2.1" text.

const CREAM := Color(0.96, 0.92, 0.82)
const DIM := Color(0.7, 0.64, 0.55)
const AMBER := Color(0.93, 0.68, 0.25)
const MAX_WIND := 4.0

var wind := 0.0

var _shown := 0.0
var _time := 0.0
var _box: StyleBoxFlat


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box = StyleBoxFlat.new()
	_box.bg_color = Color(0.05, 0.045, 0.04, 0.55)
	_box.border_color = Color(1.0, 1.0, 1.0, 0.13)
	_box.set_border_width_all(1)
	_box.set_corner_radius_all(10)


func set_wind(accel_x: float) -> void:
	wind = accel_x


func _process(delta: float) -> void:
	_time += delta
	_shown = lerpf(_shown, wind, 1.0 - exp(-4.0 * delta))
	queue_redraw()


func _draw() -> void:
	draw_style_box(_box, Rect2(Vector2.ZERO, size))
	var font := ThemeDB.fallback_font
	var calm := absf(wind) < 0.15
	var strong := absf(_shown) > 2.5

	draw_string(font, Vector2(14.0, 20.0), "W I N D", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, DIM)

	var value := "calm" if calm else "%.1f" % absf(_shown)
	var value_color := DIM if calm else (AMBER if strong else CREAM)
	var unit := "" if calm else " m/s²"
	var vw := font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	var uw := font.get_string_size(unit, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
	draw_string(font, Vector2(size.x - 14.0 - uw - vw, 21.0), value, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, value_color)
	if not calm:
		draw_string(font, Vector2(size.x - 14.0 - uw, 21.0), unit, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, DIM)

	# Scale with ticks, centred. The marker moves left or right with the wind.
	var left := 20.0
	var right := size.x - 20.0
	var cx := (left + right) * 0.5
	var y := size.y - 14.0
	draw_line(Vector2(left, y), Vector2(right, y), Color(1, 1, 1, 0.16), 1.0)
	for i in 9:
		var x := lerpf(left, right, float(i) / 8.0)
		var tall := 5.0 if i == 4 else 3.0
		draw_line(Vector2(x, y - tall), Vector2(x, y + tall), Color(1, 1, 1, 0.3 if i == 4 else 0.18), 1.0)

	var offset := clampf(_shown / MAX_WIND, -1.0, 1.0) * (right - left) * 0.5
	var sway := sin(_time * 2.2) * 1.2 * clampf(absf(_shown) / MAX_WIND, 0.0, 1.0)
	var mx := cx + offset + sway
	var marker_color := AMBER if strong else CREAM
	if not calm:
		draw_line(Vector2(cx, y), Vector2(mx, y), Color(marker_color.r, marker_color.g, marker_color.b, 0.8), 2.0)
	draw_circle(Vector2(mx, y), 3.5, marker_color)

	# Small chevrons at each end; the one the wind blows toward lights up.
	var right_on := 1.0 if (not calm and _shown > 0.0) else 0.25
	var left_on := 1.0 if (not calm and _shown < 0.0) else 0.25
	draw_polyline(PackedVector2Array([Vector2(left - 7.0, y - 4.0), Vector2(left - 11.0, y), Vector2(left - 7.0, y + 4.0)]), Color(marker_color.r, marker_color.g, marker_color.b, left_on), 1.5, true)
	draw_polyline(PackedVector2Array([Vector2(right + 7.0, y - 4.0), Vector2(right + 11.0, y), Vector2(right + 7.0, y + 4.0)]), Color(marker_color.r, marker_color.g, marker_color.b, right_on), 1.5, true)
