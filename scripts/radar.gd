extends Control
## Small spotter radar: shows where enemies are relative to the way you are facing.
## It only helps you find them; it does not help you hit them.

@export var range_m := 330.0
## World z of the breach line (set by the game manager).
@export var breach_z := -82.0

var player: Node3D
var enemies_root: Node3D
## 0..1, raised by a sandstorm: blown sand scatters the signal, so blips flicker and fuzz appears.
var interference := 0.0


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5 - 4.0
	draw_circle(c, r, Color(0.0, 0.05, 0.0, 0.45))
	draw_arc(c, r, 0.0, TAU, 64, Color(0.5, 1.0, 0.5, 0.7), 2.0, true)
	draw_line(c + Vector2(0, -r), c + Vector2(0, r), Color(0.5, 1.0, 0.5, 0.18), 1.0)
	draw_line(c + Vector2(-r, 0), c + Vector2(r, 0), Color(0.5, 1.0, 0.5, 0.18), 1.0)
	if interference > 0.02:
		for i in int(26.0 * interference):
			var ang := randf() * TAU
			var rad := sqrt(randf()) * (r - 4.0)
			draw_circle(c + Vector2(cos(ang), sin(ang)) * rad, 1.1, Color(0.55, 0.8, 0.5, 0.35 * interference))
	if player == null or enemies_root == null:
		return
	var yaw := player.rotation.y
	_draw_breach_line(c, r, yaw)
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.014)
	for e in enemies_root.get_children():
		if e.get("dead") == true:
			continue
		var rel: Vector3 = e.global_position - player.global_position
		var local := Vector3(rel.x, 0.0, rel.z).rotated(Vector3.UP, -yaw)
		var p := Vector2(local.x, local.z) / range_m * r
		if p.length() > r - 3.0:
			p = p.normalized() * (r - 3.0)
		if interference > 0.02 and randf() < 0.35 * interference:
			continue    # the blip drops out for a frame
		var to_line: float = breach_z - e.global_position.z
		if to_line < 35.0:
			# about to cross the breach line: pulsing warning ring
			draw_circle(c + p, 5.5 + pulse * 2.5, Color(1.0, 0.85, 0.2, 0.35 + 0.4 * pulse))
			draw_circle(c + p, 3.5, Color(1.0, 0.95, 0.5))
		else:
			draw_circle(c + p, 3.0, Color(1.0, 0.25, 0.2))
	draw_circle(c, 3.0, Color(0.6, 1.0, 0.6))


## The red dashed line is where enemies cost you a life. Anything past it has got through.
func _draw_breach_line(c: Vector2, r: float, yaw: float) -> void:
	var rel_z: float = breach_z - player.global_position.z
	var a3 := Vector3(-1500.0, 0.0, rel_z).rotated(Vector3.UP, -yaw)
	var b3 := Vector3(1500.0, 0.0, rel_z).rotated(Vector3.UP, -yaw)
	var a := Vector2(a3.x, a3.z) / range_m * r
	var b := Vector2(b3.x, b3.z) / range_m * r
	var d := b - a
	var qa := d.dot(d)
	var qb := 2.0 * a.dot(d)
	var rr := r - 2.0
	var qc := a.dot(a) - rr * rr
	var disc := qb * qb - 4.0 * qa * qc
	if qa <= 0.0 or disc <= 0.0:
		return
	var sq := sqrt(disc)
	var p1 := c + a + d * ((-qb - sq) / (2.0 * qa))
	var p2 := c + a + d * ((-qb + sq) / (2.0 * qa))
	draw_line(p1, p2, Color(1.0, 0.15, 0.1, 0.18), 7.0, true)
	var seg := p2 - p1
	var length := seg.length()
	if length < 1.0:
		return
	var dir := seg / length
	var pos := 0.0
	while pos < length:
		var end := minf(pos + 7.0, length)
		draw_line(p1 + dir * pos, p1 + dir * end, Color(1.0, 0.25, 0.18, 0.95), 2.0, true)
		pos += 11.0
	var font := ThemeDB.fallback_font
	draw_string(font, p1 + Vector2(8.0, -5.0), "BREACH", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1.0, 0.45, 0.35))
