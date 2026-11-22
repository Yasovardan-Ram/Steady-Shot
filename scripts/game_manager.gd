extends Node
## Rules of the game: waves of advancing enemies, score, lives, wind, pause / title / game-over
## menus, saved settings and scoreboard, and bullet impact effects. Always processes so it can
## handle pause.

const AudioBuses := preload("res://scripts/audio_buses.gd")
const LaneData := preload("res://scripts/lane_data.gd")
const TerrainSampler := preload("res://scripts/terrain_sampler.gd")
const Accounts := preload("res://scripts/accounts.gd")

enum State { TITLE, PLAYING, INTERMISSION, PAUSED, GAME_OVER }

const SAVE_PATH := "user://steadyshot.cfg"
const MAX_SCORES := 8

@export var enemy_scene: PackedScene
@export var impact_sound: AudioStream
@export var breach_z := -82.0
@export var start_lives := 5

var state := State.TITLE
var wave := 0
var level := 1
var score := 0
var lives := 5
var kills := 0
var headshots := 0
var shots_fired := 0
var _wave_started_msec: int = 0
var _wave_first_shot: bool = false
var _reaction_total_ms: float = 0.0
var _reaction_samples: int = 0
var _shot_consistency_total: float = 0.0
var _shot_consistency_samples: int = 0
var _steady_shots: int = 0
var _mixed_shots: int = 0
var _unstable_shots: int = 0
var _unrated_shots: int = 0
var _storm_wind_base_x: float = 0.0
var _storm_wind_clock: float = 0.0
var hits_landed := 0
var longest_kill := 0
var best_score := 0
var scores: Array = []
var current_user := ""
var _dev_mode := false
var volumes := {"master": 1.0, "sfx": 1.0, "ambient": 0.8}

var _auth_open := true
var _mission_briefing_open := false
var _legacy_scores: Array = []
var _legacy_best := 0
var _alive := 0
var _to_spawn := 0
var _spawn_timer := 0.0
var _intermission := 0.0
var _lock_timer := 0.0
var _enable_timer := 0.0
var _resume_state := State.PLAYING
var _sampler = null
var _last_lane := -1
var _last_record := -1
var _preview: AudioStreamPlayer
var _rock_sound: AudioStream
var _ricochet_sound: AudioStream

@onready var player = get_node("../Player")
@onready var weapon = get_node("../Player/Head/Camera3D/Weapon")
@onready var hud = get_node("../HUD")
@onready var sensor_bridge = get_node("../SensorBridge")
@onready var enemies: Node3D = get_node("../Enemies")
@onready var effects: Node3D = get_node("../Effects")
@onready var daynight = get_node("../DayNight")
@onready var nightvision = get_node("../NightVision")
@onready var hit_body_sound: AudioStreamPlayer = $HitBodySound
@onready var hit_head_sound: AudioStreamPlayer = $HitHeadSound
@onready var breach_sound: AudioStreamPlayer = $BreachSound
@onready var wave_sound: AudioStreamPlayer = $WaveSound


func _ready() -> void:
	add_to_group("game_manager")
	randomize()
	AudioBuses.ensure()
	_load_settings()
	for key in volumes.keys():
		AudioBuses.set_volume(key, volumes[key])
	for n in get_tree().root.find_children("*", "AudioStreamPlayer", true, false):
		if n.bus == &"Master":
			n.bus = AudioBuses.AMBIENT if n.name == "BriefingMusic" else AudioBuses.SFX
	_preview = AudioStreamPlayer.new()
	_preview.bus = AudioBuses.SFX
	add_child(_preview)
	if ResourceLoader.exists("res://audio/bullet_impact_rock.wav"):
		_rock_sound = load("res://audio/bullet_impact_rock.wav")
	if ResourceLoader.exists("res://audio/ricochet.wav"):
		_ricochet_sound = load("res://audio/ricochet.wav")
	var coll := get_node_or_null("../DesertCanyon/Terrain/TerrainCollision") as CollisionShape3D
	_sampler = TerrainSampler.new()
	_sampler.setup(coll)
	hud.bind(player, weapon, enemies)
	sensor_bridge.status_changed.connect(_on_sensor_status_changed)
	sensor_bridge.measurement_received.connect(_on_sensor_measurement)
	hud.sensor_setup.start_requested.connect(_on_sensor_key_submitted)
	hud.sensor_setup.skip_requested.connect(_on_sensor_skipped)
	hud.sensor_setup.quit_pressed.connect(_quit_game)
	hud.radar.breach_z = breach_z
	weapon.fired.connect(_on_weapon_fired)
	hud.menu.start_pressed.connect(_show_mission_briefing)
	hud.menu.deploy_pressed.connect(_start_game)
	hud.menu.briefing_back_pressed.connect(_return_to_title)
	hud.menu.restart_pressed.connect(_start_game)
	hud.menu.resume_pressed.connect(_resume)
	hud.menu.volume_changed.connect(_on_volume_changed)
	hud.menu.volume_released.connect(_on_volume_released)
	hud.menu.logout_pressed.connect(_on_logout)
	hud.menu.quit_pressed.connect(_quit_game)
	hud.auth.authenticated.connect(_on_authenticated)
	hud.auth.guest_chosen.connect(_on_guest)
	hud.auth.quit_pressed.connect(_quit_game)
	var remembered := Accounts.remembered()
	if remembered != "":
		_set_user(remembered)
		_show_sensor_setup()
	else:
		_enter_auth()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if is_instance_valid(sensor_bridge):
			sensor_bridge.stop()
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and (state == State.PLAYING or state == State.INTERMISSION):
		_pause()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if _dev_mode and (state == State.PLAYING or state == State.INTERMISSION):
			match event.keycode:
				KEY_F6:
					_dev_jump_wave(wave + 1)
					get_viewport().set_input_as_handled()
					return
				KEY_F5:
					_dev_jump_wave(maxi(1, wave - 1))
					get_viewport().set_input_as_handled()
					return
				KEY_K:
					_dev_kill_all_enemies()
					get_viewport().set_input_as_handled()
					return
		if event.keycode == KEY_ESCAPE:
			if state == State.TITLE and _mission_briefing_open:
				_return_to_title()
			elif state == State.PLAYING or state == State.INTERMISSION:
				_pause()
			elif state == State.PAUSED:
				_resume()
		elif event.keycode == KEY_N:
			if (state == State.PLAYING or state == State.INTERMISSION) and (daynight.is_night or daynight.is_storm):
				nightvision.set_storm_mode(daynight.is_storm)
				nightvision.set_active(not nightvision.active)
				hud.set_night_info(daynight.is_night, nightvision.active)
		elif (event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER or event.keycode == KEY_SPACE) and not _auth_open:
			if state == State.TITLE and _mission_briefing_open:
				_start_game()
				get_viewport().set_input_as_handled()
			elif state == State.TITLE:
				_show_mission_briefing()
				get_viewport().set_input_as_handled()
			elif state == State.GAME_OVER and _lock_timer <= 0.0:
				_start_game()
				get_viewport().set_input_as_handled()
			elif state == State.PAUSED:
				_resume()
				get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- settings and scores

func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	for key in volumes.keys():
		volumes[key] = clampf(float(cfg.get_value("audio", key, volumes[key])), 0.0, 1.0)
	# Scores saved by older versions (before accounts) are offered to the first guest.
	_legacy_best = int(cfg.get_value("stats", "best_score", 0))
	var raw = cfg.get_value("stats", "scores", [])
	if raw is Array:
		_legacy_scores = raw


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)
	for key in volumes.keys():
		cfg.set_value("audio", key, volumes[key])
	cfg.save(SAVE_PATH)


func _accuracy() -> int:
	if shots_fired <= 0:
		return 0
	return int(round(float(hits_landed) / float(shots_fired) * 100.0))


func _menu_data() -> Dictionary:
	return {
		"score": score, "wave": wave, "kills": kills, "headshots": headshots,
		"accuracy": _accuracy(), "longest": longest_kill, "lives": lives,
		"reaction_ms": int(round(_reaction_total_ms / float(maxi(_reaction_samples, 1)))) if _reaction_samples > 0 else 0,
		"consistency": int(round(_shot_consistency_total / float(maxi(_shot_consistency_samples, 1)))) if _shot_consistency_samples > 0 else 0,
		"steady_shots": _steady_shots, "mixed_shots": _mixed_shots, "unstable_shots": _unstable_shots, "unrated_shots": _unrated_shots, "shots_fired": shots_fired, "consistency_samples": _shot_consistency_samples,
		"best": best_score, "scores": scores, "highlight": _last_record,
		"volumes": volumes,
		"user": Accounts.display_name(current_user),
	}


func _record_score() -> void:
	_last_record = -1
	if score <= 0:
		return
	var entry := {"score": score, "wave": wave, "kills": kills, "accuracy": _accuracy(),
			"date": Time.get_date_string_from_system()}
	scores.append(entry)
	scores.sort_custom(func(a, b): return int(a["score"]) > int(b["score"]))
	while scores.size() > MAX_SCORES:
		scores.pop_back()
	_last_record = scores.find(entry)
	best_score = maxi(best_score, score)
	Accounts.save_scores(current_user, scores, best_score)


func _on_volume_changed(key: String, value: float) -> void:
	volumes[key] = value
	AudioBuses.set_volume(key, value)


## Called when a slider is let go: save, and play a short sample so the level can be judged.
func _on_volume_released(key: String) -> void:
	_save_settings()
	var path := "res://audio/ui_click.wav"
	if key == "sfx":
		path = "res://audio/sniper_shot_2.wav"
	elif key == "ambient":
		path = "res://audio/gust_swell.wav"
	elif key == "master":
		path = "res://audio/hit_head.wav"
	if ResourceLoader.exists(path):
		_preview.bus = AudioBuses.AMBIENT if key == "ambient" else AudioBuses.SFX
		_preview.stream = load(path)
		_preview.play()


# ---------------------------------------------------------------- accounts

func _set_user(key: String) -> void:
	current_user = key
	scores = Accounts.get_scores(key)
	best_score = Accounts.get_best(key)
	if key == Accounts.GUEST and scores.is_empty() and not _legacy_scores.is_empty():
		scores = _legacy_scores.duplicate()
		best_score = _legacy_best
		Accounts.save_scores(key, scores, best_score)


func _enter_auth() -> void:
	state = State.TITLE
	_auth_open = true
	player.set_active(false)
	weapon.enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	nightvision.set_active(false, true)
	daynight.set_night(false, 0.0)
	daynight.set_storm(false, 0.0)
	hud.set_night_info(false, false)
	hud.set_storm_info(false)
	hud.hide_menu()
	hud.auth.show_auth(Accounts.last_username())


func _on_authenticated(key: String, remember: bool) -> void:
	_dev_mode = key == "__DEV__"
	_set_user("dev" if _dev_mode else key)
	Accounts.set_remembered(key if remember else "")
	hud.auth.hide_auth()
	_show_sensor_setup()


func _on_guest() -> void:
	_set_user(Accounts.GUEST)
	Accounts.set_remembered("")
	hud.auth.hide_auth()
	_show_sensor_setup()


func _show_sensor_setup() -> void:
	state = State.TITLE
	_auth_open = true
	player.set_active(false)
	weapon.enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.hide_menu()
	hud.sensor_setup.show_setup()

func _on_sensor_key_submitted(api_key: String) -> void:
	var started: bool = sensor_bridge.start_with_key(api_key)
	api_key = ""
	if not started:
		player.set_sensor_status(sensor_bridge.current_status())
		hud.set_sensor_status(sensor_bridge.current_status())
	hud.sensor_setup.hide_setup()
	_enter_title()

func _on_sensor_skipped() -> void:
	sensor_bridge.stop()
	hud.set_sensor_status("FALLBACK · SENSOR DISABLED")
	player.set_sensor_status("FALLBACK · SENSOR DISABLED")
	hud.sensor_setup.hide_setup()
	_enter_title()

func _on_sensor_status_changed(value: String) -> void:
	player.set_sensor_status(value)
	hud.set_sensor_status(value)

func _on_sensor_measurement(packet: Dictionary) -> void:
	player.set_sensor_metrics(packet)
	hud.push_sensor_measurement(packet)


func _quit_game() -> void:
	# Stop the external sensor process before asking Godot to close.
	if is_instance_valid(sensor_bridge):
		sensor_bridge.stop()
	get_tree().paused = false
	get_tree().quit()


func _on_logout() -> void:
	if state != State.TITLE and state != State.GAME_OVER:
		return
	Accounts.set_remembered("")
	sensor_bridge.stop()
	_enter_auth()


# ---------------------------------------------------------------- flow

func _enter_title() -> void:
	get_tree().call_group("ambient_music_controller", "set_gameplay_music_active", false)
	state = State.TITLE
	hud.set_gameplay_overlays_visible(false)
	_auth_open = false
	player.set_active(false)
	weapon.enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.set_status(0, 0, start_lives, 0)
	hud.set_wind(0.0)
	hud.set_level(1, false)
	nightvision.set_active(false, true)
	daynight.set_night(false, 0.0)
	daynight.set_storm(false, 0.0)
	hud.set_night_info(false, false)
	hud.set_storm_info(false)
	hud.show_menu("title", _menu_data())


func _show_mission_briefing() -> void:
	if state != State.TITLE or _auth_open:
		return
	_mission_briefing_open = true
	hud.menu.show_mission_briefing(_menu_data())


func _return_to_title() -> void:
	_mission_briefing_open = false
	hud.menu.show_menu("title", _menu_data())


func _start_game() -> void:
	_mission_briefing_open = false
	get_tree().paused = false
	hud.set_gameplay_overlays_visible(true)
	for e in enemies.get_children():
		e.queue_free()
	for e in effects.get_children():
		e.queue_free()
	score = 0
	wave = 0
	level = 1
	hud.set_level(1, false)
	nightvision.set_active(false, true)
	daynight.set_night(false, 0.0)
	daynight.set_storm(false, 0.0)
	hud.set_night_info(false, false)
	hud.set_storm_info(false)
	lives = start_lives
	kills = 0
	headshots = 0
	shots_fired = 0
	hits_landed = 0
	_reaction_total_ms = 0.0
	_reaction_samples = 0
	_shot_consistency_total = 0.0
	_shot_consistency_samples = 0
	_steady_shots = 0
	_mixed_shots = 0
	_unstable_shots = 0
	_unrated_shots = 0
	_wave_first_shot = false
	longest_kill = 0
	_last_record = -1
	_alive = 0
	_to_spawn = 0
	player.reset()
	weapon.reset()
	hud.hide_menu()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_enable_timer = 0.3   # so the click that started the game does not fire a shot
	_start_wave()
	if _dev_mode:
		hud.show_popup("DEV CONTROLS  -  F5 PREVIOUS WAVE  |  F6 NEXT WAVE  |  K ELIMINATE ALL", Color(1.0, 0.35, 0.2))


func _start_wave() -> void:
	wave += 1
	get_tree().call_group("ambient_music_controller", "set_wave_number", wave)
	get_tree().call_group("ambient_music_controller", "set_gameplay_music_active", true)
	_wave_started_msec = Time.get_ticks_msec()
	_wave_first_shot = false
	state = State.PLAYING
	_to_spawn = mini(2 + wave, 10)
	_spawn_timer = 2.5
	var night := wave % 3 == 0
	var storm := wave % 5 == 0
	var max_wind := minf(0.22 + 0.16 * (wave - 1), 1.2)
	if storm:
		max_wind = minf(max_wind * 1.25, 1.5)
	var wind_x := randf_range(-max_wind, max_wind)
	if storm:
		wind_x = (1.0 if randf() < 0.5 else -1.0) * randf_range(0.6, 1.0) * max_wind
	_storm_wind_base_x = wind_x
	_storm_wind_clock = 0.0
	weapon.wind = Vector3(wind_x, 0.0, 0.0)
	hud.set_wind(wind_x)
	get_tree().call_group("wind_listeners", "set_wind", wind_x)
	weapon.refill()
	nightvision.set_storm_mode(storm)
	daynight.set_night(night, 4.0)
	daynight.set_storm(storm, 5.0)
	if not night:
		nightvision.set_active(false)
	var tags: Array[String] = []
	if night:
		tags.append("NIGHT")
	if storm:
		tags.append("SANDSTORM")
	if tags.is_empty():
		hud.show_banner("WAVE %d" % wave, 3.0)
	else:
		hud.show_banner("WAVE %d  -  %s" % [wave, "  +  ".join(tags)], 3.5)
	if night and storm:
		hud.show_popup("Night and a sandstorm  -  press N for high-contrast thermal enemy highlights in the scope", Color(0.86, 0.75, 0.55))
	elif night:
		hud.show_popup("Night falls  -  press N to switch the scope to night vision", Color(0.6, 0.95, 0.7))
	elif storm:
		hud.show_popup("Daytime sandstorm  -  press N while scoped for bright red/orange full-body enemy heat signatures", Color(0.95, 0.8, 0.55))
	hud.set_night_info(night, nightvision.active)
	hud.set_storm_info(storm)
	if wave == 1:
		hud.show_popup("Tip: W steps you to the cliff edge for a steeper view of the valley floor", Color(0.9, 0.9, 0.8))
	wave_sound.play()


## Developer-only wave navigation. Normal player progression is untouched.
func _dev_jump_wave(target_wave: int) -> void:
	if not _dev_mode:
		return
	target_wave = maxi(1, target_wave)
	for enemy in enemies.get_children():
		enemy.queue_free()
	_alive = 0
	_to_spawn = 0
	wave = target_wave - 1
	_start_wave()
	hud.show_popup("DEV MODE  -  WAVE %d" % wave, Color(1.0, 0.35, 0.2))


## Instantly kills every currently spawned enemy for rapid encounter testing.
func _dev_kill_all_enemies() -> void:
	if not _dev_mode:
		return
	for enemy in enemies.get_children():
		if is_instance_valid(enemy) and not enemy.dead:
			enemy.register_hit(enemy.global_position, true)
	hud.show_popup("DEV MODE  -  ALL ENEMIES ELIMINATED", Color(1.0, 0.35, 0.2))


func _wave_cleared() -> void:
	get_tree().call_group("ambient_music_controller", "set_gameplay_music_active", false)
	var bonus := 150 + wave * 50
	score += bonus
	state = State.INTERMISSION
	_intermission = 6.0
	level += 1
	hud.set_level(level, true)
	hud.show_banner("WAVE %d CLEARED   +%d" % [wave, bonus], 4.0)
	hud.show_popup("LEVEL UP   -   LEVEL %d" % level, Color(1.0, 0.85, 0.3))


func _pause() -> void:
	get_tree().call_group("ambient_music_controller", "set_gameplay_music_active", false)
	_resume_state = state
	hud.set_gameplay_overlays_visible(false)
	state = State.PAUSED
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.show_menu("paused", _menu_data())


func _resume() -> void:
	if state != State.PAUSED:
		return
	get_tree().paused = false
	state = _resume_state
	get_tree().call_group("ambient_music_controller", "set_gameplay_music_active", true)
	hud.set_gameplay_overlays_visible(true)
	hud.hide_menu()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_enable_timer = 0.25


func _game_over() -> void:
	get_tree().call_group("ambient_music_controller", "set_gameplay_music_active", false)
	state = State.GAME_OVER
	hud.set_gameplay_overlays_visible(false)
	_lock_timer = 1.5
	player.set_active(false)
	weapon.enabled = false
	nightvision.set_active(false)
	daynight.set_storm(false, 2.0)
	hud.set_storm_info(false)
	for e in enemies.get_children():
		e.queue_free()
	_alive = 0
	_to_spawn = 0
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_record_score()
	hud.show_menu("gameover", _menu_data())


func _process(delta: float) -> void:
	if state == State.PLAYING and daynight.is_storm:
		_storm_wind_clock += delta
		# Gusts vary the ballistic wind gradually without abruptly reversing it.
		var gust_factor: float = 0.78 + 0.22 * sin(_storm_wind_clock * 0.42 + 0.7 * sin(_storm_wind_clock * 0.17))
		var live_wind: float = _storm_wind_base_x * gust_factor
		weapon.wind = Vector3(live_wind, 0.0, 0.0)
		hud.set_wind(live_wind)
		get_tree().call_group("wind_listeners", "set_wind", live_wind)
	if _lock_timer > 0.0:
		_lock_timer -= delta
	if _enable_timer > 0.0:
		_enable_timer -= delta
		if _enable_timer <= 0.0 and (state == State.PLAYING or state == State.INTERMISSION):
			weapon.enabled = true
			player.set_active(true)

	if state == State.PLAYING:
		_update_playing(delta)
	elif state == State.INTERMISSION:
		_intermission -= delta
		if _intermission <= 0.0:
			_start_wave()
	if state != State.TITLE:
		hud.set_status(score, wave, lives, _to_spawn + _alive)


func _update_playing(delta: float) -> void:
	if _to_spawn > 0:
		_spawn_timer -= delta
		if _spawn_timer <= 0.0:
			_spawn_enemy()
			_to_spawn -= 1
			_spawn_timer = randf_range(3.0, 7.0)
	elif _alive <= 0:
		_wave_cleared()


# ---------------------------------------------------------------- enemies

func _spawn_enemy() -> void:
	if enemy_scene == null or LaneData.LANES.is_empty():
		return
	var count: int = LaneData.LANES.size()
	var idx := randi() % count
	if count > 1 and idx == _last_lane:
		idx = (idx + 1 + randi() % (count - 1)) % count
	_last_lane = idx
	var flat: Array = LaneData.LANES[idx]
	var lane := PackedVector2Array()
	for i in range(0, flat.size() - 1, 2):
		lane.append(Vector2(flat[i], flat[i + 1]))
	var enemy = enemy_scene.instantiate()
	enemies.add_child(enemy)
	var armored := wave >= 3 and randf() < minf(0.15 * (wave - 2), 0.5)
	var speed_mult := 1.0 + minf(0.07 * (wave - 1), 0.7)
	enemy.setup(lane, _sampler, speed_mult, armored, breach_z, level)
	enemy.set_conditions(daynight.is_night, daynight.is_storm)
	enemy.set_sandstorm_hitbox(daynight.is_storm)
	# Larger target volumes are strictly limited to the private developer test login.
	enemy.set_dev_hitbox_boost(_dev_mode)
	enemy.sniper_position = player.global_position
	enemy.died.connect(_on_enemy_died)
	enemy.wounded.connect(_on_enemy_wounded)
	enemy.reached_base.connect(_on_enemy_reached_base)
	_alive += 1


func _on_enemy_died(enemy: Node3D, headshot: bool, distance: float) -> void:
	_alive -= 1
	kills += 1
	hits_landed += 1
	longest_kill = maxi(longest_kill, int(distance))
	var points := 100 + int(distance * 0.5)
	var text := "KILL"
	var color := Color(1.0, 0.95, 0.8)
	if headshot:
		points += 100
		headshots += 1
		text = "HEADSHOT"
		color = Color(1.0, 0.85, 0.2)
		hit_head_sound.play()
	else:
		hit_body_sound.play()
	if enemy.get("armored") == true:
		points += 50
	score += points
	hud.show_hit_marker(headshot)
	hud.show_popup("%s   +%d   (%d m)" % [text, points, int(distance)], color)


func _on_enemy_wounded(_enemy: Node3D, headshot: bool) -> void:
	hits_landed += 1
	hit_body_sound.play()
	hud.show_hit_marker(headshot)
	hud.show_popup("ARMOR HIT - hit again or go for the head", Color(0.8, 0.8, 0.9))


func _on_enemy_reached_base(_enemy: Node3D) -> void:
	_alive -= 1
	lives -= 1
	breach_sound.play()
	hud.flash_damage()
	hud.show_popup("BREACH!   -1 LIFE", Color(1.0, 0.3, 0.25))
	if lives <= 0:
		_game_over()


func _on_weapon_fired() -> void:
	shots_fired += 1
	var consistency: float = player.shot_consistency_score()
	if is_finite(consistency):
		_shot_consistency_total += consistency
		_shot_consistency_samples += 1
		if consistency >= 75.0:
			_steady_shots += 1
		elif consistency >= 50.0:
			_mixed_shots += 1
		else:
			_unstable_shots += 1
	else:
		_unrated_shots += 1
	# A restrained nearby reaction: a few close enemies briefly flinch/hesitate.
	for enemy in enemies.get_children():
		if enemy.has_method("react_to_gunfire"):
			enemy.react_to_gunfire(player.global_position)
	if not _wave_first_shot and state == State.PLAYING:
		_wave_first_shot = true
		_reaction_total_ms += float(Time.get_ticks_msec() - _wave_started_msec)
		_reaction_samples += 1


# ---------------------------------------------------------------- effects

func spawn_impact(pos: Vector3, normal: Vector3, hit_enemy: bool, surface: String = "dirt") -> void:
	var dist: float = player.global_position.distance_to(pos)
	var puff := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	var mat := StandardMaterial3D.new()
	if not daynight.is_night:
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var tint := Color(0.85, 0.72, 0.52, 0.7)
	if surface == "rock":
		tint = Color(0.72, 0.66, 0.58, 0.7)
	if hit_enemy:
		tint = Color(0.6, 0.15, 0.1, 0.7)
	mat.albedo_color = tint
	puff.mesh = sphere
	puff.material_override = mat
	puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	effects.add_child(puff)
	puff.global_position = pos + normal * 0.1
	var base := clampf(dist * 0.012, 0.6, 3.5)
	puff.scale = Vector3.ONE * base * 0.4
	var tween := puff.create_tween()
	tween.set_parallel(true)
	tween.tween_property(puff, "scale", Vector3.ONE * base * 2.2, 0.9)
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.9)
	tween.chain().tween_callback(puff.queue_free)

	if hit_enemy:
		return
	var stream: AudioStream = impact_sound
	if surface == "rock" and _rock_sound != null:
		stream = _rock_sound
	_play_delayed(stream, dist, -4.0 - dist * 0.05, 1.0)
	if surface == "rock" and _ricochet_sound != null and randf() < 0.35:
		_play_delayed(_ricochet_sound, dist + 15.0, -9.0 - dist * 0.05, randf_range(0.9, 1.1))


## Sound travels at about 343 m/s, so impacts are heard after they are seen.
func _play_delayed(stream: AudioStream, dist: float, volume_db: float, pitch: float) -> void:
	if stream == null:
		return
	var snd := AudioStreamPlayer.new()
	snd.stream = stream
	snd.bus = AudioBuses.SFX
	snd.pitch_scale = pitch
	snd.volume_db = clampf(volume_db, -34.0, -2.0)
	effects.add_child(snd)
	snd.finished.connect(snd.queue_free)
	get_tree().create_timer(dist / 343.0, false).timeout.connect(snd.play)
