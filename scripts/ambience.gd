extends Node
## Natural desert-canyon ambience: a wind bed that swells with the wave's wind, quiet crickets,
## and unpredictable one-shots (canyon wren, raven, hawk, a small rockfall, wind gusts) that
## arrive from random directions at random times, so the soundscape never settles into a rhythm.

const AudioBuses := preload("res://scripts/audio_buses.gd")

## [file, weight, volume_db, positional]
const EVENTS := [
	["res://audio/bird_wren.wav", 3.0, -8.0, true],
	["res://audio/bird_raven.wav", 2.0, -7.0, true],
	["res://audio/bird_hawk.wav", 1.5, -9.0, true],
	["res://audio/rockfall.wav", 1.5, -10.0, true],
	["res://audio/gust_swell.wav", 2.5, -9.0, false],
]

const NIGHT_EVENTS := [
	["res://audio/owl.wav", 3.0, -7.0, true],
	["res://audio/coyote.wav", 1.5, -9.0, true],
	["res://audio/rockfall.wav", 1.0, -10.0, true],
	["res://audio/gust_swell.wav", 2.5, -9.0, false],
]

var _night := 0.0
var _storm := 0.0
var _wind: AudioStreamPlayer
var _crickets: AudioStreamPlayer
var _strength := 0.4
var _time := 0.0
var _next_event := 6.0
var _streams := {}
var _mountain_player: AudioStreamPlayer
var _mountain_tween: Tween
var _mountain_countdown := -1.0
var _mountain_remaining := 0.0
var _mountain_eligible := false
var _gameplay_music_active := false


func _ready() -> void:
	add_to_group("wind_listeners")
	add_to_group("ambient_music_controller")
	add_to_group("night_listeners")
	add_to_group("storm_listeners")
	AudioBuses.ensure()
	for e in EVENTS + NIGHT_EVENTS:
		var path: String = e[0]
		if ResourceLoader.exists(path) and not _streams.has(path):
			_streams[path] = load(path)
	_wind = _loop_player("res://audio/wind_bed.wav", -18.0)
	_crickets = _loop_player("res://audio/crickets.wav", -32.0)
	_mountain_player = AudioStreamPlayer.new()
	_mountain_player.name = "RareMountainMusic"
	_mountain_player.process_mode = Node.PROCESS_MODE_ALWAYS
	_mountain_player.bus = AudioBuses.AMBIENT
	_mountain_player.volume_db = -42.0
	if ResourceLoader.exists("res://audio/the_mountain-nostalgic-610152.mp3"):
		_mountain_player.stream = load("res://audio/the_mountain-nostalgic-610152.mp3")
	add_child(_mountain_player)
	_next_event = randf_range(4.0, 9.0)


func set_wave_number(value: int) -> void:
	_mountain_eligible = value > 1 and value % 2 == 0
	_mountain_countdown = randf_range(18.0, 32.0) if _mountain_eligible else -1.0
	_mountain_remaining = 0.0
	_stop_mountain_music(0.35)


func set_gameplay_music_active(enabled: bool) -> void:
	_gameplay_music_active = enabled
	if not enabled:
		_mountain_eligible = false
		_mountain_countdown = -1.0
		_mountain_remaining = 0.0
		_stop_mountain_music(0.8)



## Called by the game manager at the start of every wave with the wind acceleration.
func set_wind(accel_x: float) -> void:
	_strength = clampf(absf(accel_x) / 3.0, 0.0, 1.0)


## 0 = day, 1 = night: crickets get louder and the night animals take over.
func set_night_factor(t: float) -> void:
	_night = t


## 0 = clear, 1 = full sandstorm: the wind roars and only gusts are heard.
func set_storm_factor(s: float) -> void:
	_storm = s


func _process(delta: float) -> void:
	_time += delta
	if _crickets != null:
		_crickets.volume_db = lerpf(_crickets.volume_db, lerpf(-32.0, -21.0, _night) - 14.0 * _storm, clampf(delta * 0.8, 0.0, 1.0))
	# Slow, uneven swelling on top of the wave's wind strength.
	var gust := 0.5 + 0.5 * sin(_time * 0.21) * sin(_time * 0.13 + 1.0)
	var target_db := lerpf(-26.0, -11.0, _strength) + gust * 3.5 + 9.0 * _storm
	_wind.volume_db = lerpf(_wind.volume_db, target_db, clampf(delta * 0.8, 0.0, 1.0))
	_next_event -= delta
	if _next_event <= 0.0:
		_play_event()
		_next_event = randf_range(7.0, 24.0)
	_update_rare_music(delta)


func _update_rare_music(delta: float) -> void:
	if not _gameplay_music_active or _mountain_player == null or _mountain_player.stream == null:
		return
	if _mountain_remaining > 0.0:
		_mountain_remaining = maxf(0.0, _mountain_remaining - delta)
		if _mountain_remaining <= 2.0 and _mountain_player.playing:
			if _mountain_tween == null or not _mountain_tween.is_running():
				_fade_mountain_out(2.0)
		return
	if not _mountain_eligible:
		return
	if _mountain_countdown > 0.0:
		_mountain_countdown -= delta
		return
	if not _mountain_player.playing:
		_mountain_eligible = false # at most one short cue per eligible wave
		_mountain_player.volume_db = -38.0
		_mountain_player.play()
		_mountain_remaining = 20.0
		if _mountain_tween != null and _mountain_tween.is_valid():
			_mountain_tween.kill()
		_mountain_tween = create_tween()
		_mountain_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		_mountain_tween.tween_property(_mountain_player, "volume_db", -29.0, 2.0)


func _fade_mountain_out(duration: float) -> void:
	if _mountain_player == null or not _mountain_player.playing:
		return
	if _mountain_tween != null and _mountain_tween.is_valid():
		_mountain_tween.kill()
	_mountain_tween = create_tween()
	_mountain_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_mountain_tween.tween_property(_mountain_player, "volume_db", -50.0, duration)
	_mountain_tween.tween_callback(_mountain_player.stop)


func _stop_mountain_music(duration: float) -> void:
	_fade_mountain_out(duration)


func _loop_player(path: String, volume_db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = AudioBuses.AMBIENT
	p.volume_db = volume_db
	if ResourceLoader.exists(path):
		var s = load(path)
		if s is AudioStreamWAV:
			s.loop_mode = AudioStreamWAV.LOOP_FORWARD
			s.loop_begin = 0
			s.loop_end = int(s.get_length() * s.mix_rate)
		p.stream = s
	add_child(p)
	p.finished.connect(p.play)
	p.play()
	return p


func _pick_event() -> Array:
	var list: Array = NIGHT_EVENTS if _night > 0.5 else EVENTS
	if _storm > 0.4:
		return ["res://audio/gust_swell.wav", 1.0, -6.0, false]
	var total := 0.0
	for e in list:
		total += float(e[1])
	var r := randf() * total
	for e in list:
		r -= float(e[1])
		if r <= 0.0:
			return e
	return list[0]


func _play_event() -> void:
	var e := _pick_event()
	var path: String = e[0]
	if not _streams.has(path):
		return
	var db := float(e[2]) + randf_range(-3.0, 2.0)
	if bool(e[3]):
		var cam := get_viewport().get_camera_3d()
		var origin := Vector3.ZERO
		if cam != null:
			origin = cam.global_position
		var angle := randf() * TAU
		var dist := randf_range(70.0, 230.0)
		var p3 := AudioStreamPlayer3D.new()
		p3.stream = _streams[path]
		p3.bus = AudioBuses.AMBIENT
		p3.volume_db = db + 8.0
		p3.unit_size = 30.0
		p3.max_distance = 600.0
		p3.pitch_scale = randf_range(0.93, 1.07)
		add_child(p3)
		p3.global_position = origin + Vector3(cos(angle) * dist, randf_range(-5.0, 45.0), sin(angle) * dist)
		p3.finished.connect(p3.queue_free)
		p3.play()
	else:
		var p := AudioStreamPlayer.new()
		p.stream = _streams[path]
		p.bus = AudioBuses.AMBIENT
		p.volume_db = db
		p.pitch_scale = randf_range(0.95, 1.05)
		add_child(p)
		p.finished.connect(p.queue_free)
		p.play()
