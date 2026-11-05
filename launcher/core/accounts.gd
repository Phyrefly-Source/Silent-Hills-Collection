extends Node
## Local profiles: a username and password per person using this PC, each
## with their own picture, favourites (up to three games), play time and
## achievements.
##
## Everything stays on this PC, in the launcher's data folder:
##   data/accounts.json              the profiles (passwords as salted hashes)
##   data/profiles/<key>/            each profile's picture and achievements
## Passwords are never stored: only a PBKDF2-HMAC-SHA256 hash of each, with a
## random salt per profile and many rounds, worked out on a background thread.
## (Later, signing in online can build on the same profiles.)
##
## Without a profile the launcher still works ("Guest"): play time and
## achievements then go to the shared, pre-profile records. The first profile
## made on a PC takes those records over.

signal changed            # signed in, out, or the profile was edited

const ROUNDS := 150000
const MAX_FAVOURITES := 3
const NAME_RE := "^[A-Za-z0-9 _.\\-]{3,24}$"

var current := ""         # key of the signed-in profile, "" = guest
var _data := {}


func _ready() -> void:
	_data = App.read_json(_path(), {"users": {}, "remember": ""})
	if not _data.has("users"):
		_data.users = {}
	var r := str(_data.get("remember", ""))
	if r != "" and _data.users.has(r):
		current = r
	App.svc("runner").session_ended.connect(_on_session_ended)


func _path() -> String:
	return App.data_dir.path_join("accounts.json")


func _save() -> void:
	App.write_json(_path(), _data)


static func key_of(name: String) -> String:
	return name.strip_edges().to_lower()


func has_profiles() -> bool:
	return not _data.users.is_empty()


func signed_in() -> bool:
	return current != ""


## Every profile: [{key, name, created}] by name.
func profiles() -> Array:
	var out := []
	for k in _data.users:
		out.append({"key": k, "name": _data.users[k].name, "created": _data.users[k].get("created", 0)})
	out.sort_custom(func(a, b): return str(a.name).naturalnocasecmp_to(str(b.name)) < 0)
	return out


func user() -> Dictionary:
	return _data.users.get(current, {})


func display_name() -> String:
	return str(user().get("name", "Guest"))


## The signed-in profile's folder ("" for Guest).
func profile_dir(key: String = "") -> String:
	var k := key if key != "" else current
	return "" if k == "" else App.data_dir.path_join("profiles").path_join(k.validate_filename())


# ------------------------------------------------------------------ passwords
static func _hash(password: String, salt: PackedByteArray, rounds: int) -> PackedByteArray:
	# PBKDF2-HMAC-SHA256, one 32-byte block.
	var c := Crypto.new()
	var pw := password.to_utf8_buffer()
	var block := salt.duplicate()
	block.append_array(PackedByteArray([0, 0, 0, 1]))
	var u := c.hmac_digest(HashingContext.HASH_SHA256, pw, block)
	var out := u.duplicate()
	for i in rounds - 1:
		u = c.hmac_digest(HashingContext.HASH_SHA256, pw, u)
		for j in out.size():
			out[j] = out[j] ^ u[j]
	return out


static func _equal(a: PackedByteArray, b: PackedByteArray) -> bool:
	if a.size() != b.size():
		return false
	var d := 0
	for i in a.size():
		d |= a[i] ^ b[i]
	return d == 0


## Why a name or password can't be used ("" when they're fine).
func check_new(name: String, password: String, confirm: String) -> String:
	var n := name.strip_edges()
	if not RegEx.create_from_string(NAME_RE).search(n):
		return "Use 3 to 24 letters, numbers, spaces, dots, dashes or underscores for the username."
	if _data.users.has(key_of(n)):
		return "There's already a profile called %s on this PC." % n
	if password.length() < 6:
		return "Use at least 6 characters for the password."
	if password != confirm:
		return "The two passwords don't match."
	return ""


## Makes a profile and signs in. cb(error: String), "" on success.
func create(name: String, password: String, remember: bool, cb: Callable) -> void:
	var n := name.strip_edges()
	var salt := Crypto.new().generate_random_bytes(16)
	App.run(func(): return _hash(password, salt, ROUNDS), func(h: PackedByteArray):
		var k := key_of(n)
		var first: bool = _data.users.is_empty()
		_data.users[k] = {"name": n, "salt": salt.hex_encode(), "hash": h.hex_encode(), "rounds": ROUNDS,
			"created": int(Time.get_unix_time_from_system()), "favourites": [], "playtime": {}, "sessions": {}}
		DirAccess.make_dir_recursive_absolute(profile_dir(k))
		if first:
			_adopt_shared_records(k)
		_sign_in(k, remember)
		cb.call(""))


## Checks the password and signs in. cb(error: String).
func sign_in(name: String, password: String, remember: bool, cb: Callable) -> void:
	var k := key_of(name)
	var u: Dictionary = _data.users.get(k, {})
	if u.is_empty():
		cb.call("There's no profile called %s on this PC." % name.strip_edges())
		return
	var salt := str(u.salt).hex_decode()
	var rounds := int(u.get("rounds", ROUNDS))
	App.run(func(): return _hash(password, salt, rounds), func(h: PackedByteArray):
		if not _equal(h, str(u.hash).hex_decode()):
			cb.call("That password isn't right.")
			return
		_sign_in(k, remember)
		cb.call(""))


func _sign_in(k: String, remember: bool) -> void:
	current = k
	_data.remember = k if remember else ""
	_save()
	App.svc("achievements").reload()
	changed.emit()


func sign_out() -> void:
	current = ""
	_data.remember = ""
	_save()
	App.svc("achievements").reload()
	changed.emit()


## cb(error).
func change_password(old: String, new_pw: String, confirm: String, cb: Callable) -> void:
	if new_pw.length() < 6:
		cb.call("Use at least 6 characters for the new password.")
		return
	if new_pw != confirm:
		cb.call("The two new passwords don't match.")
		return
	var u := user()
	var k := current
	App.run(func(): return _hash(old, str(u.salt).hex_decode(), int(u.get("rounds", ROUNDS))), func(h: PackedByteArray):
		if not _equal(h, str(u.hash).hex_decode()):
			cb.call("The current password isn't right.")
			return
		var salt := Crypto.new().generate_random_bytes(16)
		App.run(func(): return _hash(new_pw, salt, ROUNDS), func(h2: PackedByteArray):
			_data.users[k].salt = salt.hex_encode()
			_data.users[k].hash = h2.hex_encode()
			_data.users[k].rounds = ROUNDS
			_save()
			cb.call("")))


# ------------------------------------------------------------------ picture
func avatar_path(key: String = "") -> String:
	var d := profile_dir(key)
	if d == "":
		return ""
	var p := d.path_join("avatar.png")
	return p if FileAccess.file_exists(p) else ""


## Uses a picture from disk as the profile picture (cropped square, 256 px).
func set_avatar(path: String) -> bool:
	var img := Pictures.read(path)
	if img == null or current == "":
		return false
	var side := mini(img.get_width(), img.get_height())
	img = img.get_region(Rect2i((img.get_width() - side) / 2, (img.get_height() - side) / 2, side, side))
	img.resize(256, 256, Image.INTERPOLATE_LANCZOS)
	DirAccess.make_dir_recursive_absolute(profile_dir())
	img.save_png(profile_dir().path_join("avatar.png"))
	changed.emit()
	return true


## A round picture for the profile (its photo, or its initial on a colour).
func avatar_texture(px: int, key: String = "") -> ImageTexture:
	var k := key if key != "" else current
	var img: Image = null
	var ap := avatar_path(k)
	if ap != "":
		img = Image.load_from_file(ap)
	if img == null:
		img = Image.create(px, px, false, Image.FORMAT_RGBA8)
		img.fill(Style.HOVER if k == "" else Style.accent_fill(Color.from_hsv(float(k.hash() % 360) / 360.0, 0.45, 0.55)))
	img.convert(Image.FORMAT_RGBA8)
	img.resize(px, px, Image.INTERPOLATE_LANCZOS)
	if ap == "":
		# No photo: a person glyph on the colour.
		var g := Style.icon("user", int(px * 0.55), Color(1, 1, 1, 0.9)).get_image()
		g.convert(Image.FORMAT_RGBA8)
		var o := (px - g.get_width()) / 2
		img.blend_rect(g, Rect2i(Vector2i.ZERO, g.get_size()), Vector2i(o, o))
	var r := px / 2.0
	for y in px:
		for x in px:
			var d := Vector2(x + 0.5 - r, y + 0.5 - r).length()
			var c := img.get_pixel(x, y)
			c.a *= clampf(r - d, 0.0, 1.0)
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)


# ------------------------------------------------------------------ favourites
func favourites() -> Array:
	return user().get("favourites", []).filter(func(id): return not App.game(id).is_empty())


func is_favourite(id: String) -> bool:
	return favourites().has(id)


## Toggles a favourite. Returns "" or why it couldn't (three already).
func toggle_favourite(id: String) -> String:
	if current == "":
		return "Make a profile to keep favourites."
	var f: Array = favourites()
	if f.has(id):
		f.erase(id)
	elif f.size() >= MAX_FAVOURITES:
		return "You already have three favourites. Take one off first."
	else:
		f.append(id)
	_data.users[current].favourites = f
	_save()
	changed.emit()
	return ""


# ------------------------------------------------------------------ play time
func _on_session_ended(id: String, seconds: int) -> void:
	if current == "" or seconds <= 0:
		return
	var u: Dictionary = _data.users[current]
	u.playtime[id] = int(u.playtime.get(id, 0)) + seconds
	u.sessions[id] = int(u.sessions.get(id, 0)) + 1
	u.last_played = u.get("last_played", {})
	u.last_played[id] = int(Time.get_unix_time_from_system())
	_save()
	changed.emit()


## Seconds played: the profile's own, or the shared record for Guest.
func playtime(id: String) -> int:
	if current == "":
		return int(App.state(id).get("playtime", 0))
	return int(user().get("playtime", {}).get(id, 0))


func sessions(id: String) -> int:
	if current == "":
		return int(App.state(id).get("sessions", 0))
	return int(user().get("sessions", {}).get(id, 0))


func total_playtime() -> int:
	var t := 0
	for g in App.games:
		t += playtime(g.id)
	return t


## The first profile on a PC takes over what was recorded before profiles
## existed: play time per game and the achievements progress.
func _adopt_shared_records(k: String) -> void:
	var u: Dictionary = _data.users[k]
	for g in App.games:
		var gs := App.state(g.id)
		if int(gs.get("playtime", 0)) > 0:
			u.playtime[g.id] = int(gs.playtime)
			u.sessions[g.id] = int(gs.get("sessions", 0))
	var shared := App.data_dir.path_join("achievements/progress.json")
	if FileAccess.file_exists(shared):
		DirAccess.copy_absolute(shared, profile_dir(k).path_join("achievements.json"))
