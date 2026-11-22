extends RefCounted
## Local player accounts. Everything is stored on this computer in user://accounts.cfg:
## a random salt and a salted, repeatedly hashed password per account (the password itself is
## never saved), plus that player's scoreboard. This is an offline game, so accounts are not
## shared between computers.

const PATH := "user://accounts.cfg"
const GUEST := "guest"
const ROUNDS := 4000
const MAX_FAILS := 5
const LOCK_SECONDS := 30

# Failed attempts this session: {key: [count, locked_until_msec]}
static var _fails := {}


static func key_of(username: String) -> String:
	return username.strip_edges().to_lower()


static func validate_username(username: String) -> String:
	var u := username.strip_edges()
	if u.length() < 3 or u.length() > 16:
		return "Username must be 3 to 16 characters."
	var ok := RegEx.new()
	ok.compile("^[A-Za-z0-9_]+$")
	if ok.search(u) == null:
		return "Use letters, numbers and underscores only."
	if key_of(u) == GUEST:
		return "That name is reserved."
	return ""


static func validate_password(password: String) -> String:
	if password.length() < 6:
		return "Password must be at least 6 characters."
	if password.length() > 64:
		return "Password is too long (64 characters at most)."
	return ""


static func exists(username: String) -> bool:
	var cfg := _load()
	return cfg.has_section("user:" + key_of(username))


## Creates an account. Returns "" on success, otherwise a message for the player.
static func create(username: String, password: String) -> String:
	var err := validate_username(username)
	if err != "":
		return err
	err = validate_password(password)
	if err != "":
		return err
	var cfg := _load()
	var section := "user:" + key_of(username)
	if cfg.has_section(section):
		return "That username is already taken."
	var salt := Crypto.new().generate_random_bytes(16).hex_encode()
	cfg.set_value(section, "display", username.strip_edges())
	cfg.set_value(section, "salt", salt)
	cfg.set_value(section, "hash", _hash(password, salt))
	cfg.set_value(section, "created", Time.get_datetime_string_from_system())
	cfg.set_value(section, "scores", [])
	cfg.set_value(section, "best", 0)
	var save_error: int = cfg.save(PATH)
	if save_error != OK:
		return "Could not save the account. Check available storage and permissions."
	return ""


## Checks a login. Returns "" on success, otherwise a message for the player.
static func verify(username: String, password: String) -> String:
	var key := key_of(username)
	var state: Array = _fails.get(key, [0, 0])
	var now := Time.get_ticks_msec()
	if int(state[1]) > now:
		return "Too many attempts. Try again in %d seconds." % int(ceil((int(state[1]) - now) / 1000.0))
	var cfg := _load()
	var section := "user:" + key
	var good := false
	if cfg.has_section(section):
		var salt: String = cfg.get_value(section, "salt", "")
		good = _hash(password, salt) == str(cfg.get_value(section, "hash", ""))
	if good:
		_fails.erase(key)
		return ""
	state[0] = int(state[0]) + 1
	if int(state[0]) >= MAX_FAILS:
		state = [0, now + LOCK_SECONDS * 1000]
	_fails[key] = state
	return "Wrong username or password."


static func display_name(key: String) -> String:
	if key == GUEST:
		return "Guest"
	return str(_load().get_value("user:" + key, "display", key))


static func get_scores(key: String) -> Array:
	var raw = _load().get_value(_section(key), "scores", [])
	return raw if raw is Array else []


static func get_best(key: String) -> int:
	return int(_load().get_value(_section(key), "best", 0))


static func save_scores(key: String, scores: Array, best: int) -> void:
	var cfg := _load()
	cfg.set_value(_section(key), "scores", scores)
	cfg.set_value(_section(key), "best", best)
	cfg.save(PATH)


## "Keep me signed in": remembers which account to open next time (no password is stored).
static func set_remembered(key: String) -> void:
	var cfg := _load()
	cfg.set_value("meta", "remembered", key)
	cfg.save(PATH)


static func remembered() -> String:
	var key := str(_load().get_value("meta", "remembered", ""))
	if key == GUEST or key == "":
		return ""
	return key if _load().has_section("user:" + key) else ""


static func set_last_username(username: String) -> void:
	var cfg := _load()
	cfg.set_value("meta", "last", username)
	cfg.save(PATH)


static func last_username() -> String:
	return str(_load().get_value("meta", "last", ""))


static func _section(key: String) -> String:
	return "guest" if key == GUEST else "user:" + key


static func _load() -> ConfigFile:
	var cfg := ConfigFile.new()
	cfg.load(PATH)
	return cfg


static func _hash(password: String, salt: String) -> String:
	var h := (salt + ":" + password).sha256_text()
	for i in ROUNDS:
		h = (h + salt + password).sha256_text()
	return h
