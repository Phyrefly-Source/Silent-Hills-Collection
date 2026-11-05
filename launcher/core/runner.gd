extends Node
## Runner: starts games and times how long they run.
##
## A session lasts while any process runs from the game's folder (or has one of
## the game's process names). That copes with launcher stubs (PlayDownpour.exe
## hands over to downpour.exe), self-restarting exes and Steam, which starts the
## game itself. Processes are listed every few seconds on a worker thread.

signal session_started(game_id: String)
signal session_ended(game_id: String, seconds: int)

const POLL := 4.0
const END_AFTER := 9.0

var sessions := {}   # id -> {start, last_seen, seen, grace, roots, names}
var _timer: Timer
var _polling := false


func _ready() -> void:
	_timer = Timer.new()
	_timer.wait_time = POLL
	_timer.timeout.connect(_poll)
	add_child(_timer)


func is_running(id: String) -> bool:
	return sessions.has(id)


func play(id: String) -> String:
	if sessions.has(id):
		return "%s is already running." % App.game(id).title
	var g := App.game(id)
	var gs := App.state(id)
	var routes = App.svc("routes")
	var t: Dictionary = routes.play_target(id)

	# Back up saves first; quick and it has saved people more than once.
	if gs.get("auto_backup", true) and not g.get("saves", []).is_empty():
		App.svc("saves").backup(id, "", "auto")

	# Mods, scripts and recompiled games can report achievements through these.
	OS.set_environment("SILENTHILLS_GAME_ID", id)
	OS.set_environment("SILENTHILLS_ACHIEVEMENTS_INBOX", App.data_dir.path_join("achievements/inbox"))
	DirAccess.make_dir_recursive_absolute(App.data_dir.path_join("achievements/inbox"))
	# Native builds that run RetroAchievements sets read what's left to unlock here.
	OS.set_environment("SILENTHILLS_RA_DEFS", App.svc("ra").write_runtime(id))

	var roots: Array = []
	if t.has("url"):
		if OS.shell_open(t.url) != OK:
			return "Couldn't hand the game to Steam."
		if gs.path != "":
			roots.append(gs.path)
		_begin(id, roots, g.install.get("process", []), 150.0)
		return ""
	var exe: String = t.get("exe", "")
	if exe == "" or not FileAccess.file_exists(exe):
		return "Can't find the game's program. Check the folder under Manage."
	if OS.get_name() == "Windows":
		# `start /D` sets the working folder, which many of these games need.
		var args := PackedStringArray(["/c", "start", "Silent Hills", "/D", exe.get_base_dir().replace("/", "\\"), exe.replace("/", "\\")])
		args.append_array(PackedStringArray(t.args))
		var pid := OS.create_process("cmd.exe", args, false)
		if pid <= 0:
			return "Windows refused to start the game."
	else:
		var argv := PackedStringArray(t.args)
		var program := exe
		if exe.to_lower().ends_with(".exe"):
			# A Windows game on Linux: umu-run (Proton, the SteamOS way) first, then Wine.
			var via := ""
			for w in ["umu-run", "wine"]:
				var o := []
				if OS.execute("sh", ["-c", "command -v " + str(w)], o) == 0 and o.size() > 0 and str(o[0]).strip_edges() != "":
					via = str(o[0]).strip_edges()
					break
			if via == "":
				return "Install umu-launcher (or Wine) to run Windows games here."
			argv.insert(0, exe)
			program = via
		# Launch from the game's folder: many of these games need it as the working dir.
		var cmd: Array = ["-c", 'cd "$1" && shift && exec "$@"', "sh", exe.get_base_dir(), program]
		cmd.append_array(Array(argv))
		var pid := OS.create_process("sh", PackedStringArray(cmd), false)
		if pid <= 0:
			return "Couldn't start the game."
	roots.append(exe.get_base_dir())
	if gs.path != "" and not roots.has(gs.path):
		roots.append(gs.path)
	# Also by name: Windows hides the path of games that run as administrator.
	var names: Array = g.install.get("process", []).duplicate()
	if not names.has(exe.get_file()):
		names.append(exe.get_file())
	_begin(id, roots, names, 60.0)
	return ""


func _begin(id: String, roots: Array, names: Array, grace: float) -> void:
	var now := Time.get_unix_time_from_system()
	var low_roots := []
	for r in roots:
		var p := str(r).replace("\\", "/").to_lower().trim_suffix("/") + "/"
		# Never treat a drive root or the launcher's own folder as the game.
		if p.length() > 4 and not App.root_dir.to_lower().begins_with(p):
			low_roots.append(p)
	sessions[id] = {"start": now, "last_seen": now, "seen": false, "grace": grace, "roots": low_roots,
		"names": names.map(func(n): return str(n).to_lower())}
	var gs := App.state(id)
	gs.last_played = int(now)
	App.mark_dirty("library")
	session_started.emit(id)
	App.library_changed.emit(id)
	if _timer.is_stopped():
		_timer.start()


func stop_all() -> void:
	for id in sessions.keys():
		_end(id, true)


func shutdown() -> void:
	stop_all()


func _poll() -> void:
	if _polling or sessions.is_empty():
		if sessions.is_empty():
			_timer.stop()
		return
	_polling = true
	App.run(_list_processes, _on_processes)


## Every running program: its full path when Windows gives it, and always
## "name:<file name>" (programs running as administrator have no visible path).
static func _list_processes() -> Array:
	var out := []
	var paths := []
	if OS.get_name() == "Windows":
		var cmd := "Get-Process | ForEach-Object { $_.ProcessName + '|' + $_.Path }"
		if OS.execute("powershell.exe", ["-NoProfile", "-NonInteractive", "-Command", cmd], out, false, false) == 0:
			for line in str(out[0]).split("\n"):
				var l := line.strip_edges()
				if l == "":
					continue
				var bits := l.split("|", true, 1)
				paths.append("name:" + bits[0].to_lower() + ".exe")
				if bits.size() > 1 and bits[1].strip_edges() != "":
					paths.append(bits[1].strip_edges().replace("\\", "/").to_lower())
	else:
		for d in DirAccess.get_directories_at("/proc"):
			if d.is_valid_int():
				var cmdline := FileAccess.get_file_as_string("/proc/%s/cmdline" % d)
				for a in cmdline.split(char(0)):
					if a.begins_with("/"):
						paths.append(a.to_lower())
	return paths


func _on_processes(paths: Array) -> void:
	_polling = false
	var now := Time.get_unix_time_from_system()
	for id in sessions.keys():
		var s: Dictionary = sessions[id]
		var found := false
		for p in paths:
			if p.begins_with("name:"):
				if s.names.has(p.substr(5)):
					found = true
					break
				continue
			for r in s.roots:
				if p.begins_with(r):
					found = true
					break
			if not found and s.names.has(p.get_file()):
				found = true
			if found:
				break
		if found:
			if not s.seen:
				s.seen = true
				s.start = now   # the clock starts when the game is actually up
			s.last_seen = now
			continue
		var limit: float = END_AFTER if s.seen else s.grace
		if now - s.last_seen >= limit:
			_end(id, false)


func _end(id: String, forced: bool) -> void:
	var s: Dictionary = sessions.get(id, {})
	if s.is_empty():
		return
	sessions.erase(id)
	var end: float = Time.get_unix_time_from_system() if forced else s.last_seen + POLL / 2.0
	var seconds := int(max(0.0, end - s.start)) if s.seen else 0
	var gs := App.state(id)
	if s.seen:
		gs.playtime = int(gs.playtime) + seconds
		gs.sessions = int(gs.sessions) + 1
		gs.last_session = seconds
		App.mark_dirty("library")
	session_ended.emit(id, seconds)
	App.library_changed.emit(id)
	App.svc("achievements").refresh(id)
