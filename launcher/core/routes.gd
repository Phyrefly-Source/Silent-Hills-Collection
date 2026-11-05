extends RefCounted
## Routes: how each game gets onto PC, and what the main button should do.
##
## kind "steam"    the PC release from Steam; played through Steam.
## kind "enhanced" an installed PC release plus a packaged Enhanced patch.
## kind "rebuild"  a native PC build made from the player's own console dump by a
##                 packaged decompile-to-recompile tool.
##
## Packages live in <launcher>/rebuilds/<game>/manifest.json, so each tool can
## be updated or added without a new launcher build:
##   {"name", "version", "kind": "rebuild"|"enhanced",
##    "steps": [{"label", "exe", "args": [...]}],      # build steps (rebuild)
##    "output": "{launcher}/builds/<game>",             # where the build goes
##    "run": {"exe": "{output}/Game.exe", "args": ["{dump}"]},
##    "files": "files",                                 # folder copied into {game} (enhanced)
##    "installed_when": ["SH3EE.ini"],
##    "description": "…",                               # shown on the Mods tab (enhanced)
##    "settings": "Enhanced/settings.json",             # settings schema, relative to files (enhanced)
##    "on_remove": {"restore_ini": "Enhanced/engine-originals.ini",
##                  "targets": {"vars_pc.cfg": "Engine/vars_pc.cfg"}}}
##
## An Enhanced patch is turned on and off from the Mods tab. Off means the game is exactly as it
## was: the mod manager puts every replaced file back, and "on_remove" puts back the game's own
## config values the patch had changed (the patch records them; one INI section per target file,
## key=value lines restored verbatim). The patch's own settings file stays, so turning it on again
## brings every feature and setting back.

signal build_log(game_id: String, line: String)
signal build_done(game_id: String, ok: bool)

var _jobs := {}   # game id -> {pid, stdio}


func package(id: String) -> Dictionary:
	var p := App.root_dir.path_join("rebuilds").path_join(id).path_join("manifest.json")
	var m: Dictionary = App.read_json(p, {})
	if not m.is_empty():
		m["_dir"] = p.get_base_dir()
	return m


func _exists(p: String) -> bool:
	return p != "" and (FileAccess.file_exists(p) or DirAccess.dir_exists_absolute(p))


## What the page should show for this game right now.
func status(id: String) -> Dictionary:
	var g := App.game(id)
	var gs := App.state(id)
	var route: Dictionary = g.get("route", {})
	var pkg := package(id)
	var s := {
		"kind": route.get("kind", ""),
		"label": route.get("label", ""),
		"connected": false,
		"playable": false,
		"primary": {"label": "Find game", "action": "find"},
		"note": "",
		"package": pkg,
		"busy": _jobs.has(id),
	}
	match s.kind:
		"steam":
			var appid := str(gs.get("steam_appid", g.install.get("steam_appid", "")))
			s.connected = appid != "" and _exists(gs.path)
			s.playable = s.connected
			if s.connected:
				s.primary = {"label": "Play", "action": "play"}
			elif appid != "":
				s.primary = {"label": "Install on Steam", "action": "steam_install"}
				s.note = "Not installed in any Steam library on this PC."
			else:
				s.note = "Not found in your Steam libraries."
		"enhanced":
			var exe := _game_exe(id)
			s.connected = _exists(exe)
			if not s.connected:
				s.note = "Connect your PC copy. Silent Hills looks in the usual places, or you can browse to it."
			else:
				var installed := _patch_installed(id, pkg)
				s.playable = true
				s.patch_installed = installed
				if installed:
					s.primary = {"label": "Play", "action": "play"}
					s.note = "%s is on." % route.get("label", "The Enhanced patch")
				elif bool(gs.get("enhanced_off", false)):
					s.primary = {"label": "Play", "action": "play"}
					s.note = "%s is off. Turn it on in Mods." % route.get("label", "The Enhanced patch")
				elif not pkg.is_empty():
					s.primary = {"label": "Install %s" % pkg.get("name", "Enhanced patch"), "action": "install_patch"}
					s.note = "Your PC copy is connected. Install the patch to play the enhanced version."
				else:
					s.primary = {"label": "Play", "action": "play"}
					s.note = "%s isn't packaged with the launcher yet. Play starts the PC release as it is." % route.get("label", "The Enhanced patch")
		"rebuild":
			var exe := _game_exe(id)
			var dump: String = gs.get("dump", "")
			if _exists(exe):
				s.connected = true
				s.playable = true
				s.primary = {"label": "Play", "action": "play"}
				s.note = "Native PC build" + ((" · " + pkg.get("version", "")) if pkg.has("version") else "") + "."
			elif not _exists(dump):
				s.primary = {"label": "Choose your %s" % route.get("source", "dump"), "action": "choose_dump"}
				s.note = "The rebuild starts from your own %s. Silent Hills never downloads game data." % route.get("source", "dump")
			elif pkg.is_empty():
				s.connected = true
				s.primary = {"label": "Rebuild in development", "action": "none"}
				s.note = "Your dump is ready. The rebuild tool for this game isn't packaged yet."
			else:
				s.connected = true
				s.primary = {"label": "Build for PC", "action": "rebuild"}
				s.note = "Your dump is ready. Building makes a native Windows version on this PC."
	if s.busy:
		s.primary = {"label": "Building…", "action": "none"}
	return s


## The program Play should start (absolute), or "".
func _game_exe(id: String) -> String:
	var g := App.game(id)
	var gs := App.state(id)
	if str(gs.get("exe", "")) != "" and FileAccess.file_exists(gs.exe):
		return gs.exe
	var pkg := package(id)
	if pkg.has("run"):
		var out := output_dir(id, pkg)
		var e := App.expand(str(pkg.run.get("exe", "")).replace("{output}", out), gs.path, gs.get("dump", ""))
		if FileAccess.file_exists(e):
			return e
	var rel: String = g.get("install", {}).get("exe", "")
	if rel != "" and gs.path != "":
		return gs.path.path_join(rel)
	return ""


func play_target(id: String) -> Dictionary:
	var g := App.game(id)
	var gs := App.state(id)
	if g.route.kind == "steam":
		return {"url": "steam://rungameid/%s" % gs.get("steam_appid", g.install.get("steam_appid", ""))}
	var exe := _game_exe(id)
	var args: Array = []
	var pkg := package(id)
	if pkg.has("run") and exe.begins_with(output_dir(id, pkg)):
		for a in pkg.run.get("args", []):
			args.append(App.expand(str(a), gs.path, gs.get("dump", "")))
	var dump_arg: String = g.install.get("dump_arg", "")
	if dump_arg != "" and str(gs.get("dump", "")) != "" and DirAccess.dir_exists_absolute(gs.dump):
		args.append_array([dump_arg, gs.dump])
	return {"exe": exe, "args": args, "cwd": exe.get_base_dir()}


func output_dir(id: String, pkg: Dictionary) -> String:
	return App.expand(str(pkg.get("output", "{launcher}/builds/" + id)))


func _runtime_toggle_available(id: String, pkg: Dictionary) -> bool:
	var spec: Dictionary = pkg.get("runtime_toggle", {})
	if spec.is_empty():
		return false
	var path: String = App.state(id).path.path_join(str(spec.get("dll", "")))
	return FileAccess.file_exists(path) and FileAccess.get_sha256(path) == str(spec.get("sha256", ""))


func _repair_runtime_assets(id: String, pkg: Dictionary) -> String:
	var game: String = App.state(id).path
	var source: String = str(pkg._dir).path_join(str(pkg.get("files", "files")))
	var assets: Dictionary = pkg.get("runtime_assets", {})
	# Preflight every missing asset before copying anything. Existing custom assets stay intact.
	for rel in assets:
		if not FileAccess.file_exists(game.path_join(rel)):
			if FileAccess.get_sha256(source.path_join(rel)) != str(assets[rel]):
				return "Patch asset is missing or damaged: " + str(rel)
	for rel in assets:
		var target := game.path_join(rel)
		if FileAccess.file_exists(target):
			continue
		DirAccess.make_dir_recursive_absolute(target.get_base_dir())
		if DirAccess.copy_absolute(source.path_join(rel), target) != OK or FileAccess.get_sha256(target) != str(assets[rel]):
			return "Couldn't restore patch asset: " + str(rel)
	return ""


func _set_runtime_toggle(id: String, pkg: Dictionary, enabled: bool) -> String:
	if enabled:
		var repair := _repair_runtime_assets(id, pkg)
		if repair != "":
			return repair
	var spec: Dictionary = pkg.runtime_toggle
	var path: String = App.state(id).path.path_join(str(spec.ini))
	var before := FileAccess.get_file_as_string(path)
	if FileAccess.get_open_error() != OK:
		return "Couldn't read the patch settings."
	var after := before
	if not enabled:
		# Capture final engine values before disabling, even if the game's exit callback was skipped.
		var originals: Dictionary = preload("res://core/patch_settings.gd").read(App.state(id).path.path_join("Enhanced/engine-originals.ini"))
		for name in ["vars_pc.cfg", "default_pc.cfg"]:
			var cfg_path: String = App.state(id).path.path_join("Engine/" + name)
			if not originals.has(name):
				continue # first launch has not captured a baseline yet
			if not FileAccess.file_exists(cfg_path):
				return "Engine settings are missing; patch switch unchanged."
			for line in FileAccess.get_file_as_string(cfg_path).split("\n"):
				var eq := line.find("=")
				if eq <= 0:
					continue
				var key := line.substr(0, eq).strip_edges()
				if originals[name].has(key.to_lower()):
					after = preload("res://core/patch_settings.gd").set_key(after, "EngineValues", name + ":" + key, line.substr(eq + 1).strip_edges())
	after = preload("res://core/patch_settings.gd").set_key(after, "Enhanced", "Enabled", "1" if enabled else "0")
	var tmp := path + ".toggle-tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return "Couldn't save the patch switch."
	f.store_string(after)
	f.flush()
	var err := f.get_error()
	f.close()
	if err != OK or FileAccess.get_file_as_string(tmp) != after:
		return "Patch switch write failed; existing settings kept."
	err = DirAccess.rename_absolute(tmp, path)
	if err != OK:
		return "Couldn't replace patch settings: " + error_string(err)
	App.set_state(id, {"enhanced_off": not enabled})
	return ""


func _patch_installed(id: String, pkg: Dictionary) -> bool:
	if _runtime_toggle_available(id, pkg):
		var path: String = App.state(id).path.path_join(str(pkg.runtime_toggle.ini))
		var values: Dictionary = preload("res://core/patch_settings.gd").read(path)
		return str(values.get("enhanced", {}).get("enabled", "1")) != "0"
	var g := App.game(id)
	var gs := App.state(id)
	if App.svc("mods").is_enabled(id, "_enhanced"):
		return true
	var marks: Array = pkg.get("installed_when", g.route.get("installed_when", []))
	if marks.is_empty():
		return false
	for m in marks:
		if not _exists(gs.path.path_join(str(m))):
			return false
	return true


# ------------------------------------------------------------------ actions
func install_patch(id: String) -> String:
	var pkg := package(id)
	var gs := App.state(id)
	if pkg.is_empty():
		return "There's no patch package for this game yet."
	if App.svc("runner").is_running(id):
		return "Close %s first." % App.game(id).title
	if _runtime_toggle_available(id, pkg):
		return _set_runtime_toggle(id, pkg, true)
	var src: String = pkg._dir.path_join(str(pkg.get("files", "files")))
	if not DirAccess.dir_exists_absolute(src):
		return "The patch package is missing its files folder."
	# The patch goes through the mod manager so it can be removed cleanly.
	var err: String = App.svc("mods").install_folder(id, "_enhanced", src, gs.path, pkg.get("name", "Enhanced patch"))
	if err == "":
		App.set_state(id, {"enhanced_off": false})
	return err


## Turns an Enhanced patch off: the game's config values first (while the patch's record of them
## is still there), then every file the patch installed. "" = success.
func remove_patch(id: String) -> String:
	var pkg := package(id)
	var gs := App.state(id)
	if App.svc("runner").is_running(id):
		return "Close %s first." % App.game(id).title
	if _runtime_toggle_available(id, pkg):
		return _set_runtime_toggle(id, pkg, false)
	if not App.svc("mods").is_enabled(id, "_enhanced"):
		return "This manually installed patch cannot be rolled back by this launcher version."
	var game_path: String = gs.path
	var on_remove: Dictionary = pkg.get("on_remove", {})
	if game_path != "" and not on_remove.is_empty():
		restore_ini_values(game_path, str(on_remove.get("restore_ini", "")), on_remove.get("targets", {}))
	var err: String = App.svc("mods").disable(id, "_enhanced")
	if err == "":
		App.set_state(id, {"enhanced_off": true})
	return err


## Writes key=value lines from an INI's sections back into the files they belong to (only keys
## that already exist in the target; line endings and everything else untouched). Returns the count.
static func restore_ini_values(game_path: String, ini_rel: String, targets: Dictionary) -> int:
	var ini := game_path.path_join(ini_rel)
	if ini_rel == "" or not FileAccess.file_exists(ini):
		return 0
	var sections := {}
	var cur := ""
	for raw in FileAccess.get_file_as_string(ini).split("\n"):
		var line := raw.strip_edges()
		if line.begins_with("[") and line.ends_with("]"):
			cur = line.substr(1, line.length() - 2)
			sections[cur] = {}
		elif cur != "" and line.contains("="):
			var eq := line.find("=")
			sections[cur][line.substr(0, eq)] = line.substr(eq + 1)
	var n := 0
	for sec in sections:
		if not targets.has(sec):
			continue
		var path := game_path.path_join(str(targets[sec]))
		if not FileAccess.file_exists(path):
			continue
		var text := FileAccess.get_file_as_string(path)
		var lines := text.split("\n")
		var changed := false
		for i in lines.size():
			var l: String = lines[i]
			var eol := "\r" if l.ends_with("\r") else ""
			var body := l.trim_suffix("\r")
			var eq := body.find("=")
			if eq <= 0:
				continue
			var key := body.substr(0, eq)
			if sections[sec].has(key):
				var v: String = sections[sec][key]
				if body.substr(eq + 1) != v:
					lines[i] = key + "=" + v + eol
					changed = true
					n += 1
		if changed:
			var f := FileAccess.open(path, FileAccess.WRITE)
			if f:
				f.store_string("\n".join(lines))
				f.close()
	return n


func rebuild(id: String) -> void:
	var pkg := package(id)
	var gs := App.state(id)
	var out := output_dir(id, pkg)
	DirAccess.make_dir_recursive_absolute(out)
	var steps: Array = pkg.get("steps", [])
	_jobs[id] = true
	App.run(func():
		for st in steps:
			var exe := App.expand(str(st.exe).replace("{output}", out), gs.path, gs.dump)
			if exe.is_relative_path():
				exe = pkg._dir.path_join(exe)
			var args := PackedStringArray()
			for a in st.get("args", []):
				args.append(App.expand(str(a).replace("{output}", out), gs.path, gs.dump))
			build_log.emit.call_deferred(id, "▸ " + str(st.get("label", exe.get_file())))
			var p := OS.execute_with_pipe(exe, args, false)
			if p.is_empty():
				build_log.emit.call_deferred(id, "Couldn't start " + exe)
				return false
			var io: FileAccess = p.stdio
			while true:
				var line := io.get_line()
				if line != "":
					build_log.emit.call_deferred(id, line)
				elif io.get_error() != OK and not OS.is_process_running(p.pid):
					break
				else:
					OS.delay_msec(20)
			if OS.get_process_exit_code(p.pid) != 0:
				build_log.emit.call_deferred(id, "Step failed with code %d." % OS.get_process_exit_code(p.pid))
				return false
		return true,
	func(ok):
		_jobs.erase(id)
		build_done.emit(id, ok)
		App.library_changed.emit(id))
