extends Node
## Owns the local Node.js Presage process and a non-blocking WebSocketPeer connection.
signal status_changed(status: String)
signal measurement_received(sample: Dictionary)

const PORT := 8765
const URL := "ws://127.0.0.1:8765"
const CONNECT_TIMEOUT := 8.0
const RECONNECT_DELAY := 2.0
const INSTALL_TIMEOUT := 180.0
const INSTALL_POLL_INTERVAL := 0.5

var _peer := WebSocketPeer.new()
var _process_id := -1
var _status := "SENSOR OFF"
var _connect_elapsed := 0.0
var _reconnect_elapsed := 0.0
var _want_sensor := false
var _last_sample_ms := 0
var _no_data_timeout_sent := false
var _data_elapsed := 0.0
var _session_token := ""
var _auth_sent := false
var _bootstrap_pid := -1
var _bootstrap_elapsed := 0.0
var _bootstrap_poll_elapsed := 0.0
var _bootstrapping := false
var _pending_api_key := ""
var _bridge_directory := ""

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func start_with_key(api_key: String) -> bool:
	if api_key.strip_edges().is_empty():
		_set_status("FALLBACK · NO API KEY")
		return false
	stop()
	_want_sensor = true
	_pending_api_key = api_key.strip_edges()
	var bridge_path := ProjectSettings.globalize_path("res://presage_bridge/sensor.js")
	var package_path := ProjectSettings.globalize_path("res://presage_bridge/package.json")
	_bridge_directory = ProjectSettings.globalize_path("res://presage_bridge")
	if not FileAccess.file_exists(bridge_path) or not FileAccess.file_exists(package_path):
		_fail_startup("FALLBACK · BRIDGE FILES MISSING")
		return false

	if not _dependencies_ready():
		if not _begin_dependency_install():
			_fail_startup("FALLBACK · COULD NOT START AUTOMATIC SETUP")
			return false
		_bootstrapping = true
		_bootstrap_elapsed = 0.0
		_bootstrap_poll_elapsed = 0.0
		_set_status("SETTING UP SENSOR · INSTALLING COMPONENTS…")
		return true

	return _launch_sensor_process()

func _dependencies_ready() -> bool:
	return FileAccess.file_exists(_bridge_directory.path_join("node_modules/@smartspectra/node-sdk/package.json")) and FileAccess.file_exists(_bridge_directory.path_join("node_modules/ws/package.json")) and FileAccess.file_exists(_bridge_directory.path_join("node_modules/.package-lock.json"))

func _begin_dependency_install() -> bool:
	var pid := -1
	if OS.get_name() == "Windows":
		var shell := OS.get_environment("COMSPEC")
		if shell.is_empty():
			shell = "cmd.exe"
		var command := "npm install --prefix \"" + _bridge_directory + "\" --no-audit --no-fund"
		pid = OS.create_process(shell, ["/c", command], false)
	else:
		pid = OS.create_process("npm", ["install", "--prefix", _bridge_directory, "--no-audit", "--no-fund"], false)
	_bootstrap_pid = pid
	return pid > 0

func _launch_sensor_process() -> bool:
	if _pending_api_key.is_empty():
		_fail_startup("FALLBACK · API KEY UNAVAILABLE")
		return false
	var crypto := Crypto.new()
	_session_token = crypto.generate_random_bytes(32).hex_encode()
	OS.set_environment("PRESAGE_API_KEY", _pending_api_key)
	OS.set_environment("PRESAGE_SESSION_TOKEN", _session_token)
	var bridge_path := ProjectSettings.globalize_path("res://presage_bridge/sensor.js")
	_process_id = OS.create_process("node", [bridge_path], false)
	OS.unset_environment("PRESAGE_API_KEY")
	OS.unset_environment("PRESAGE_SESSION_TOKEN")
	_pending_api_key = ""
	_bootstrapping = false
	_bootstrap_pid = -1
	if _process_id <= 0:
		_session_token = ""
		_want_sensor = false
		_set_status("FALLBACK · NODE.JS NOT FOUND")
		return false
	_peer = WebSocketPeer.new()
	_auth_sent = false
	_peer.connect_to_url(URL)
	_connect_elapsed = 0.0
	_reconnect_elapsed = 0.0
	_data_elapsed = 0.0
	_last_sample_ms = 0
	_set_status("STARTING SENSOR…")
	return true

func _fail_startup(message: String) -> void:
	if _bootstrap_pid > 0:
		OS.kill(_bootstrap_pid)
	_bootstrap_pid = -1
	_bootstrapping = false
	_pending_api_key = ""
	_want_sensor = false
	OS.unset_environment("PRESAGE_API_KEY")
	OS.unset_environment("PRESAGE_SESSION_TOKEN")
	_set_status(message)

func stop() -> void:
	_want_sensor = false
	if _bootstrap_pid > 0:
		OS.kill(_bootstrap_pid)
	_bootstrap_pid = -1
	_bootstrapping = false
	_pending_api_key = ""
	OS.unset_environment("PRESAGE_API_KEY")
	OS.unset_environment("PRESAGE_SESSION_TOKEN")
	if _peer.get_ready_state() != WebSocketPeer.STATE_CLOSED:
		_peer.close(1000, "Game stopping sensor")
	if _process_id > 0:
		OS.kill(_process_id)
	_process_id = -1
	_session_token = ""
	_auth_sent = false
	_last_sample_ms = 0
	_data_elapsed = 0.0
	_set_status("SENSOR OFF")

func _process(delta: float) -> void:
	if _bootstrapping:
		_bootstrap_elapsed += delta
		_bootstrap_poll_elapsed += delta
		if _bootstrap_poll_elapsed >= INSTALL_POLL_INTERVAL:
			_bootstrap_poll_elapsed = 0.0
			if _dependencies_ready():
				_bootstrap_pid = -1
				_launch_sensor_process()
				return
		if _bootstrap_elapsed >= INSTALL_TIMEOUT:
			_fail_startup("FALLBACK · AUTOMATIC SETUP TIMED OUT")
		return
	if not _want_sensor:
		return
	_peer.poll()
	var state := _peer.get_ready_state()
	if state == WebSocketPeer.STATE_CLOSED:
		_connect_elapsed += delta
		if _connect_elapsed > CONNECT_TIMEOUT:
			_set_status("FALLBACK · BRIDGE UNAVAILABLE")
		_reconnect_elapsed += delta
		if _reconnect_elapsed >= RECONNECT_DELAY:
			_reconnect_elapsed = 0.0
			_peer = WebSocketPeer.new()
			_auth_sent = false
			var err := _peer.connect_to_url(URL)
			if err != OK:
				_set_status("RECONNECTING…")
	elif state == WebSocketPeer.STATE_CONNECTING:
		_connect_elapsed += delta
		if _connect_elapsed > CONNECT_TIMEOUT:
			_set_status("FALLBACK · BRIDGE CONNECTION TIMEOUT")
	else:
		_connect_elapsed = 0.0
		_reconnect_elapsed = 0.0
		if not _auth_sent and not _session_token.is_empty():
			var auth_message := JSON.stringify({"type": "auth", "token": _session_token})
			_auth_sent = _peer.send_text(auth_message) == OK
		_data_elapsed += delta
		while _peer.get_available_packet_count() > 0:
			var packet := _peer.get_packet()
			if _peer.was_string_packet():
				var parsed = JSON.parse_string(packet.get_string_from_utf8())
				if parsed is Dictionary:
					if parsed.get("type", "") == "status":
						_set_status(str(parsed.get("status", "SENSOR READY")))
					elif parsed.get("type", "") == "metrics":
						measurement_received.emit(parsed)
						_last_sample_ms = Time.get_ticks_msec()
						_data_elapsed = 0.0
						_no_data_timeout_sent = false
		if _data_elapsed > 8.0 and not _no_data_timeout_sent:
			_set_status("NO VALID SENSOR READINGS · CHECK LIGHT / FACE POSITION")
			_no_data_timeout_sent = true
		elif _last_sample_ms > 0 and Time.get_ticks_msec() - _last_sample_ms > 8000:
			_set_status("SENSOR DATA STALE · HOLDING LAST VALUE")

func _set_status(value: String) -> void:
	if _status == value:
		return
	_status = value
	status_changed.emit(value)

func current_status() -> String:
	return _status
