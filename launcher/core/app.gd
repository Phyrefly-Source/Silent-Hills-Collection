extends Node
## App: paths, settings, the catalogue and the per-game library state.
##
## Everything the launcher keeps lives next to the exe in ./data, so the whole
## folder can be moved. When run from the editor it uses user://.
## Other services (scanner, launcher, art, achievements...) are plain objects
## created here on demand, so start-up only pays for what the first screen uses.

signal library_changed(game_id: String)
signal settings_changed
signal toast(text: String, kind: String)
signal job_progress(job: String, text: String, fraction: float)

const VERSION := "0.1.0"
const SAVE_DELAY := 0.6

var root_dir := ""        # folder holding the exe (or user:// in the editor)
## The phone companion app (Android build, or SILENTHILLS_COMPANION=1 to try it on a PC).
var companion := false
var data_dir := ""
var cache_dir := ""

var settings := {}
var library := {}         # {games: {id: {...}}, comics: {...}, music: {...}}
var games: Array = []     # catalogue entries, release order
var comics_catalogue: Array = []
var films: Array = []     # the Silent Hill films, release order (data/films.json)

var _by_id := {}
var _dirty := {}
var _save_timer: SceneTreeTimer = null
var _services := {}

const DEFAULT_SETTINGS := {
	"sgdb_key": "",
	"steam_root": "",
	"ffmpeg": "",
	"reduce_motion": false,
	"ambience": true,
	"minimize_on_play": true,
	"volume": 0.8,
	"extra_scan_roots": [],
	"comic_folders": [],
	"music_folders": [],
	"order": "release",
}


func _ready() -> void:
	_init_paths()
	settings = DEFAULT_SETTINGS.duplicate(true)
	settings.merge(_read_json(data_dir.path_join("settings.json"), {}), true)
	for gone in ["ra_user", "ra_key"]:   # RetroAchievements accounts are no longer used
		settings.erase(gone)
	library = _read_json(data_dir.path_join("library.json"), {})
	for k in ["games", "comics", "music"]:
		if not library.has(k) or typeof(library[k]) != TYPE_DICTIONARY:
			library[k] = {}
	_load_catalogue()
	if not companion:
		_migrate_electron_state()
	get_tree().auto_accept_quit = false


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		for s in _services.values():
			if s.has_method("shutdown"):
				s.shutdown()
		flush()
		get_tree().quit()


# ------------------------------------------------------------------ paths
func _init_paths() -> void:
	companion = OS.has_feature("mobile") or OS.get_environment("SILENTHILLS_COMPANION") == "1"
	if OS.has_feature("mobile"):
		root_dir = ProjectSettings.globalize_path("user://")
	elif OS.has_feature("template"):
		# Portable zip ships a `portable` marker, and older builds already keep
		# data\ beside the exe: both stay there. Installed copies (Program Files,
		# AppImage) use the per-user folder instead.
		var exe_dir := OS.get_executable_path().get_base_dir()
		if FileAccess.file_exists(exe_dir.path_join("portable")) or DirAccess.dir_exists_absolute(exe_dir.path_join("data")):
			root_dir = exe_dir
		else:
			root_dir = ProjectSettings.globalize_path("user://")
	else:
		root_dir = ProjectSettings.globalize_path("user://")
	var override := OS.get_environment("SILENTHILLS_ROOT")
	if override != "":
		root_dir = override
	data_dir = root_dir.path_join("data")
	cache_dir = data_dir.path_join("cache")
	for d in [data_dir, cache_dir, data_dir.path_join("art"), data_dir.path_join("achievements/inbox"),
			data_dir.path_join("save-backups"), data_dir.path_join("mod-backups"), root_dir.path_join("mods"),
			root_dir.path_join("rebuilds")]:
		DirAccess.make_dir_recursive_absolute(d)


func tokens(game_path: String = "", dump_path: String = "") -> Dictionary:
	var home := OS.get_environment("USERPROFILE")
	if home == "":
		home = OS.get_environment("HOME")
	var appdata := OS.get_environment("APPDATA")
	var local := OS.get_environment("LOCALAPPDATA")
	return {
		"game": game_path,
		"dump": dump_path,
		"launcher": root_dir,
		"home": home,
		"userprofile": home,
		"documents": OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS),
		"appdata": appdata if appdata != "" else home.path_join("AppData/Roaming"),
		"localappdata": local if local != "" else home.path_join("AppData/Local"),
		"savedgames": home.path_join("Saved Games"),
		"programfiles": _env_or("ProgramFiles", "C:/Program Files"),
		"programfilesx86": _env_or("ProgramFiles(x86)", "C:/Program Files (x86)"),
	}


func expand(p: String, game_path: String = "", dump_path: String = "") -> String:
	if p == "":
		return p
	var t := tokens(game_path, dump_path)
	for k in t:
		p = p.replace("{%s}" % k, str(t[k]))
	return p.replace("\\", "/").simplify_path() if not p.contains("*") else p.replace("\\", "/")


func _env_or(name: String, fallback: String) -> String:
	var v := OS.get_environment(name)
	return v if v != "" else fallback


# ------------------------------------------------------------------ catalogue
func _load_catalogue() -> void:
	var base: Array = _read_json("res://data/games.json", {}).get("games", [])
	# Entries in data/catalogue/*.json are added or laid over the built-ins by id,
	# so new games or corrected paths don't need a new launcher build.
	var extra_dir := data_dir.path_join("catalogue")
	if DirAccess.dir_exists_absolute(extra_dir):
		for f in DirAccess.get_files_at(extra_dir):
			if f.get_extension().to_lower() != "json":
				continue
			var extra = _read_json(extra_dir.path_join(f), {})
			for g in (extra.get("games", []) if extra is Dictionary else []):
				var found := false
				for i in base.size():
					if base[i].id == g.get("id"):
						base[i].merge(g, true)
						found = true
				if not found and g.has("id") and g.has("title"):
					base.append(g)
	base.sort_custom(func(a, b): return [a.get("year", 9999), a.get("order", 0)] < [b.get("year", 9999), b.get("order", 0)])
	games = base
	_by_id.clear()
	for g in games:
		_by_id[g.id] = g
	comics_catalogue = _read_json("res://data/comics.json", {}).get("comics", [])
	films = _read_json("res://data/films.json", {}).get("films", [])
	for f in films:
		_by_id[f.id] = f


## Loads a picture whatever its file name says (see Pictures.load).
static func load_image(path: String) -> Image:
	return Pictures.read(path)


## True when shelves should leave out comics, films and soundtracks you don't have.
func hide_missing() -> bool:
	return bool(settings.get("hide_missing", false))


## A small toggle for a page header that flips "hide what's missing".
func missing_toggle() -> Button:
	var b := CheckBox.new()
	b.text = "Hide missing"
	b.button_pressed = hide_missing()
	b.tooltip_text = "Hide comics, films and soundtracks you don't have (also in Settings)"
	b.focus_mode = Control.FOCUS_NONE
	b.toggled.connect(func(on): set_setting("hide_missing", on))
	settings_changed.connect(func():
		if is_instance_valid(b):
			b.set_pressed_no_signal(hide_missing()))
	return b


## A game or a film by id.
func entry(id: String) -> Dictionary:
	return _by_id.get(id, {})


func game(id: String) -> Dictionary:
	return _by_id.get(id, {})


## Per-game state, created on first use.
func state(id: String) -> Dictionary:
	var gs: Dictionary = library.games.get(id, {})
	if gs.is_empty():
		gs = {"path": "", "exe": "", "dump": "", "playtime": 0, "sessions": 0, "last_played": 0, "last_session": 0}
		library.games[id] = gs
	return gs


func set_state(id: String, patch: Dictionary) -> void:
	state(id).merge(patch, true)
	mark_dirty("library")
	library_changed.emit(id)


# ------------------------------------------------------------------ settings
func set_setting(key: String, value) -> void:
	settings[key] = value
	mark_dirty("settings")
	settings_changed.emit()


func mark_dirty(what: String) -> void:
	_dirty[what] = true
	if _save_timer == null:
		_save_timer = get_tree().create_timer(SAVE_DELAY)
		_save_timer.timeout.connect(flush)


func flush() -> void:
	_save_timer = null
	if _dirty.has("settings"):
		write_json(data_dir.path_join("settings.json"), settings)
	if _dirty.has("library"):
		write_json(data_dir.path_join("library.json"), library)
	_dirty.clear()


# ------------------------------------------------------------------ services
## Services are created lazily: App.svc("scanner") etc.
func svc(name: String) -> Object:
	if _services.has(name):
		return _services[name]
	var paths := {
		"scanner": "res://core/scanner.gd",
		"runner": "res://core/runner.gd",
		"art": "res://core/art.gd",
		"saves": "res://core/saves.gd",
		"mods": "res://core/mods.gd",
		"routes": "res://core/routes.gd",
		"achievements": "res://core/achievements/achievements.gd",
		"music": "res://core/music/music_library.gd",
		"comics": "res://core/comics/comics_library.gd",
		"shm": "res://core/shm.gd",
		"movies": "res://core/movies.gd",
		"image_search": "res://core/image_search.gd",
		"ra": "res://core/achievements/ra.gd",
		"concept": "res://core/concept_art.gd",
		"companion": "res://core/companion/server.gd",
		"pc": "res://core/companion/client.gd",
		"news": "res://core/news.gd",
		"accounts": "res://core/accounts.gd",
		"updater": "res://core/updater.gd",
	}
	var s = load(paths[name]).new()
	if s is Node:
		add_child(s)
	_services[name] = s
	return s


## Run work on a worker thread; `done` is called on the main thread with the result.
func run(work: Callable, done: Callable = Callable()) -> int:
	return WorkerThreadPool.add_task(func():
		var r = work.call()
		# Back on the main thread, and only if whoever asked still exists
		# (a page or picture may have been closed while the work ran).
		(func():
			if done.is_valid():
				done.call(r)).call_deferred())


func notify(text: String, kind: String = "ok") -> void:
	toast.emit(text, kind)


# ------------------------------------------------------------------ json
func _read_json(path: String, fallback):
	if not FileAccess.file_exists(path):
		return fallback
	var txt := FileAccess.get_file_as_string(path)
	var v = JSON.parse_string(txt)
	return v if v != null and typeof(v) == typeof(fallback) else fallback


func read_json(path: String, fallback):
	return _read_json(path, fallback)


func write_json(path: String, data) -> bool:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	return DirAccess.rename_absolute(tmp, path) == OK


# ------------------------------------------------------------------ migration
## Bring over game folders and play time from the Electron launcher when this
## build sits next to it (one folder up, or the same folder).
func _migrate_electron_state() -> void:
	if library.get("migrated", false):
		return
	for p in [root_dir.path_join("../data/state.json").simplify_path(), data_dir.path_join("state.json")]:
		if not FileAccess.file_exists(p):
			continue
		var old = _read_json(p, {})
		var og: Dictionary = old.get("games", {})
		for id in og:
			if not _by_id.has(id):
				continue
			var o: Dictionary = og[id]
			var gs := state(id)
			if gs.path == "" and str(o.get("path", "")) != "":
				gs.path = str(o.path).replace("\\", "/")
			gs.playtime = max(int(gs.playtime), int(o.get("playtime", 0)))
			gs.sessions = max(int(gs.sessions), int(o.get("sessions", 0)))
			gs.last_played = max(int(gs.last_played), int(o.get("lastPlayed", 0) / 1000))
			if str(o.get("steamAppId", "")) != "":
				gs.steam_appid = str(o.steamAppId)
		var old_prog: String = str(p).get_base_dir().path_join("achievements/progress.json")
		var new_prog: String = data_dir.path_join("achievements/progress.json")
		if FileAccess.file_exists(old_prog) and not FileAccess.file_exists(new_prog):
			DirAccess.copy_absolute(old_prog, new_prog)
		break
	library.migrated = true
	mark_dirty("library")


# ------------------------------------------------------------------ format
static func fmt_duration(sec: int) -> String:
	if sec <= 0:
		return "Not played"
	if sec < 60:
		return "%d sec" % sec
	var m := int(round(sec / 60.0))
	if m < 60:
		return "%d min" % m
	return ("%d h %d min" % [m / 60, m % 60]) if m % 60 else ("%d h" % (m / 60))


static func fmt_ago(unix: int) -> String:
	if unix <= 0:
		return "Never"
	var now := int(Time.get_unix_time_from_system())
	var days := int((now - unix) / 86400)
	if days <= 0:
		return "Today"
	if days == 1:
		return "Yesterday"
	if days < 7:
		return "%d days ago" % days
	var d := Time.get_datetime_dict_from_unix_time(unix)
	return "%d %s %d" % [d.day, ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"][d.month - 1], d.year]
