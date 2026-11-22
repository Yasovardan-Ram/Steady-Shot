extends Control
## Draws the scope view (black mask, duplex reticle with mil-dots) and the hip crosshair
## plus hit markers. Display only.

var scope_alpha := 0.0
var fov_deg := 75.0
var mil_step := 1
var nv_on := false

var _hit_time := 0.0
var _hit_head := false


func flash_hit(headshot: bool) -> void:
	_hit_time = 0.3
	_hit_head = headshot


func _process(delta: float) -> void:
	if _hit_time > 0.0:
		_hit_time -= delta
	queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	if scope_alpha > 0.01:
		_draw_scope(c)
	if scope_alpha < 0.99:
		var a := 1.0 - scope_alpha
		var col := Color(1, 1, 1, 0.85 * a)
		for dir in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
			draw_line(c + dir * 6.0, c + dir * 14.0, col, 2.0)
		draw_circle(c, 1.5, col)
	if _hit_time > 0.0:
		var hc := Color(1.0, 0.85, 0.2, _hit_time / 0.3) if _hit_head else Color(1.0, 0.25, 0.2, _hit_time / 0.3)
		for s in [Vector2(1, 1), Vector2(1, -1), Vector2(-1, 1), Vector2(-1, -1)]:
			draw_line(c + s * 9.0, c + s * 18.0, hc, 3.0)


func _draw_scope(c: Vector2) -> void:
	var r := size.y * 0.46
	var black := Color(0, 0, 0, scope_alpha)
	var w := size.length()
	draw_arc(c, r + w * 0.5, 0.0, TAU, 256, black, w, false)
	draw_arc(c, r, 0.0, TAU, 128, Color(0.03, 0.03, 0.03, scope_alpha), 6.0, true)
	draw_arc(c, r - 3.0, -0.9, 0.15, 48, Color(0.72, 0.78, 0.72, 0.10 * scope_alpha), 1.2, true)
	# Very restrained lens dust and a faint glass reflection, kept away from the
	# central aiming point so the reticle remains readable.
	var dust_points: Array[Vector2] = [
		Vector2(-0.56, -0.38), Vector2(0.62, -0.22),
		Vector2(-0.68, 0.31), Vector2(0.48, 0.57),
		Vector2(0.18, -0.72), Vector2(-0.22, 0.68),
	]
	for dust_point in dust_points:
		var dust_pos: Vector2 = c + dust_point * r
		if dust_pos.distance_to(c) < r * 0.88:
			draw_circle(dust_pos, 1.0, Color(0.85, 0.82, 0.72, 0.13 * scope_alpha))
	draw_line(c + Vector2(-r * 0.68, -r * 0.70), c + Vector2(-r * 0.43, -r * 0.82), Color(0.9, 0.92, 0.86, 0.07 * scope_alpha), 2.0, true)

	var col := Color(0.0, 0.0, 0.0, 0.92 * scope_alpha)
	var inner := r * 0.2
	var gap := 6.0
	for dir in [Vector2.LEFT, Vector2.RIGHT, Vector2.DOWN]:
		draw_line(c + dir * r, c + dir * inner, col, 5.0)
	for dir in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		draw_line(c + dir * inner, c + dir * gap, col, 1.6)

	# Mil-dots: 1 mil = 1 m at 1000 m. Spacing adapts to the current zoom.
	var px_per_mil := 0.001 * (size.y * 0.5) / tan(deg_to_rad(fov_deg) * 0.5)
	mil_step = 1
	if px_per_mil < 4.5:
		mil_step = 5
	elif px_per_mil < 9.0:
		mil_step = 2
	var spacing := px_per_mil * mil_step
	var count := int((inner - gap) / spacing)
	for i in range(1, count + 1):
		var d := gap + spacing * i
		for dir in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
			draw_circle(c + dir * d, 2.2, col)
	draw_circle(c, 1.4, Color(0.9, 0.1, 0.1, scope_alpha))
	if nv_on:
		var font := ThemeDB.fallback_font
		draw_string(font, c + Vector2(-9.0, r * 0.84), "NV", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.45, 1.0, 0.55, 0.85 * scope_alpha))
