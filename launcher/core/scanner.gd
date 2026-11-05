extends RefCounted
## Scanner: finds installed games, existing PC builds and disc dumps in the
## places they usually live, without crawling whole drives.
##
## Roots: each drive's top level and common game folders (Games, GOG Games,
## Program Files, SteamLibrary...), every Steam library from libraryfolders.vdf,
## the user's Documents / Downloads / Desktop, and any folders added in Settings.
## Folders whose names look like Silent Hill get a deeper look.

const DUMP_EXT := ["iso", "bin", "cue", "chd", "cso", "rvz", "wbfs", "wia", "gcz", "vpk", "pbp"]
const SKIP_DIRS := ["windows", "$recycle.bin", "system volume information", "programdata", "appdata",
	"node_modules", ".git", "msocache", "perflogs", "recovery", "intel", "amd", "nvidia",
	"microsoft", "windowsapps", "drivers", "common files", "shadercache", "_build", "_dumps", "cache"]
const HINTS := ["silent", "hill", "downpour", "homecoming", "townfall", "p.t", "shattered", "origins",
	"book of memories", "short message", "cusa01127", "ppsa101", "konami", "rom", "iso", "dump", "games"]
const MAX_ENTRIES := 250000

var _visited := 0
var _cancel := false
static var _steam_root_cache = null


# ------------------------------------------------------------------ Steam
func steam_root() -> String:
	var s: String = App.settings.get("steam_root", "")
	if s != "" and DirAccess.dir_exists_absolute(s):
		return s
	if _steam_root_cache != null:
		return _steam_root_cache
	_steam_root_cache = _find_steam_root()
	return _steam_root_cache


func _find_steam_root() -> String:
	if OS.get_name() == "Windows":
		var out := []
		if OS.execute("reg", ["query", "HKCU\\Software\\Valve\\Steam", "/v", "SteamPath"], out, false, false) == 0:
			for line in str(out[0]).split("\n"):
				if line.contains("SteamPath"):
					var p := line.split("REG_SZ")[-1].strip_edges().replace("\\", "/")
					if DirAccess.dir_exists_absolute(p):
						return p
	var home := OS.get_environment("HOME")
	for p in ["C:/Program Files (x86)/Steam", "C:/Program Files/Steam",
			home.path_join(".local/share/Steam"), home.path_join(".steam/steam"), home.path_join(".steam/root"),
			home.path_join(".var/app/com.valvesoftware.Steam/.local/share/Steam")]:
		if DirAccess.dir_exists_absolute(p):
			return p
	return ""


func steam_libraries(root: String = "") -> Array:
	if root == "":
		root = steam_root()
	var libs := []
	if root == "":
		return libs
	libs.append(root)
	var vdf := root.path_join("steamapps/libraryfolders.vdf")
	if FileAccess.file_exists(vdf):
		var re := RegEx.create_from_string("\"path\"\\s+\"([^\"]+)\"")
		for m in re.search_all(FileAccess.get_file_as_string(vdf)):
			var p := m.get_string(1).replace("\\\\", "/").replace("\\", "/")
			if not libs.has(p):
				libs.append(p)
	return libs


## {appid: {"dir": install path, "name": installdir}}
func steam_apps(root: String = "") -> Dictionary:
	var out := {}
	var re_id := RegEx.create_from_string("\"appid\"\\s+\"(\\d+)\"")
	var re_dir := RegEx.create_from_string("\"installdir\"\\s+\"([^\"]+)\"")
	for lib in steam_libraries(root):
		var apps: String = lib.path_join("steamapps")
		if not DirAccess.dir_exists_absolute(apps):
			continue
		for f in DirAccess.get_files_at(apps):
			if not (f.begins_with("appmanifest_") and f.ends_with(".acf")):
				continue
			var txt := FileAccess.get_file_as_string(apps.path_join(f))
			var mi := re_id.search(txt)
			var md := re_dir.search(txt)
			if mi and md:
				out[mi.get_string(1)] = {"dir": apps.path_join("common").path_join(md.get_string(1)), "name": md.get_string(1)}
	return out


# ------------------------------------------------------------------ roots
## [[path, depth]]: how deep to look depends on how likely games are there.
## Folders that look like Silent Hill always get a deeper look while walking.
func roots() -> Array:
	var r := []
	var seen := {}
	var add := func(p: String, depth: int):
		p = p.replace("\\", "/").trim_suffix("/")
		if p.length() == 2:
			p += "/"
		if p != "" and DirAccess.dir_exists_absolute(p) and not seen.has(p.to_lower()):
			seen[p.to_lower()] = true
			r.append([p, depth])
	for extra in App.settings.get("extra_scan_roots", []):
		add.call(str(extra), 4)
	add.call(App.root_dir.get_base_dir(), 2)
	for lib in steam_libraries():
		add.call(lib.path_join("steamapps/common"), 1)
	if OS.get_name() == "Windows":
		for i in DirAccess.get_drive_count():
			var d := DirAccess.get_drive_name(i) + "/"
			for sub in ["Games", "GOG Games", "SteamLibrary/steamapps/common", "Program Files (x86)/GOG Galaxy/Games",
					"Emulation", "Emulators", "ROMs", "Roms", "ISOs", "Dumps", "Konami"]:
				add.call(d + sub, 3)
			add.call(d + "Program Files (x86)", 1)
			add.call(d + "Program Files", 1)
			add.call(d, 1)
	else:
		var home := OS.get_environment("HOME")
		for sub in ["Games", "Emulation", "Emulation/roms", "ROMs", "Dumps"]:
			add.call(home.path_join(sub), 3)
		# SteamOS mounts SD cards and USB drives under /run/media/<user>/<label>.
		for media in ["/run/media", "/media", "/mnt"]:
			if DirAccess.dir_exists_absolute(media):
				for d in DirAccess.get_directories_at(media):
					var m := media.path_join(d)
					add.call(m, 2)
					for sub in ["Games", "Emulation", "Emulation/roms", "SteamLibrary/steamapps/common"]:
						add.call(m.path_join(sub), 3)
					for d2 in DirAccess.get_directories_at(m):
						add.call(m.path_join(d2), 2)
	for sd in [OS.SYSTEM_DIR_DOWNLOADS, OS.SYSTEM_DIR_DOCUMENTS, OS.SYSTEM_DIR_DESKTOP]:
		add.call(OS.get_system_dir(sd), 2)
	return r


# ------------------------------------------------------------------ scan
## Returns {installs: {id: [{path, exe}]}, dumps: {id: [{path, serial}]}, steam: {id: {appid, dir}}}.
## progress.call(text) is invoked from the worker thread (use call_deferred inside).
func scan(only_game: String = "", progress: Callable = Callable()) -> Dictionary:
	_visited = 0
	_cancel = false
	var res := {"installs": {}, "dumps": {}, "steam": {}}
	var targets: Array = App.games if only_game == "" else [App.game(only_game)]

	# Steam games resolve straight from the app manifests.
	var apps := steam_apps()
	for g in targets:
		var inst: Dictionary = g.get("install", {})
		for appid in apps:
			var a: Dictionary = apps[appid]
			if appid == str(inst.get("steam_appid", "")) or (inst.get("steam_dir", "") != "" and a.name.to_lower() == str(inst.steam_dir).to_lower() and g.route.kind == "steam"):
				res.steam[g.id] = {"appid": appid, "dir": a.dir}

	for entry in roots():
		if _cancel:
			break
		if progress.is_valid():
			progress.call("Looking in %s" % entry[0])
		_walk(entry[0], 0, entry[1], targets, res)
	return res


func cancel() -> void:
	_cancel = true


func _walk(dir: String, depth: int, max_depth: int, targets: Array, res: Dictionary) -> void:
	if _cancel or _visited > MAX_ENTRIES:
		return
	var da := DirAccess.open(dir)
	if da == null:
		return
	da.include_hidden = false
	var name := dir.get_file().to_lower()
	if _interesting(name):
		_check_install(dir, targets, res)
		# Builds often sit one level down (e.g. "Silent Hill Origins/PC").
		for sub in da.get_directories():
			_check_install(dir.path_join(sub), targets, res)
		_check_dump_folder(dir, targets, res)
	for f in da.get_files():
		_visited += 1
		var ext := f.get_extension().to_lower()
		if DUMP_EXT.has(ext):
			_check_dump_file(dir.path_join(f), targets, res)
	if depth >= max_depth:
		return
	for sub in da.get_directories():
		_visited += 1
		var low: String = sub.to_lower()
		if SKIP_DIRS.has(low) or low.begins_with("."):
			continue
		# Past the top levels, only follow folders that look relevant.
		var deeper := max_depth
		if _interesting(low):
			deeper = max(max_depth, depth + 3)
		_walk(dir.path_join(sub), depth + 1, deeper, targets, res)


func _interesting(low: String) -> bool:
	for h in HINTS:
		if low.contains(h):
			return true
	for g in App.games:
		for f in g.get("install", {}).get("folders", []):
			if low == str(f).to_lower().get_file():
				return true
	return false


func _check_install(dir: String, targets: Array, res: Dictionary) -> void:
	for g in targets:
		for rel in g.get("install", {}).get("detect", []):
			if FileAccess.file_exists(dir.path_join(rel)):
				var base := dir
				# A detect path with a folder ("PC/x.exe") means the game root is here.
				var list: Array = res.installs.get(g.id, [])
				var exe := dir.path_join(rel)
				if not list.any(func(e): return e.exe == exe):
					list.append({"path": base, "exe": exe})
				res.installs[g.id] = list
				break


func _check_dump_folder(dir: String, targets: Array, res: Dictionary) -> void:
	# PS4 / PS5 / Vita dumps are folders with sce_sys/param.sfo or param.json.
	for meta in ["sce_sys/param.sfo", "sce_sys/param.json"]:
		var p := dir.path_join(meta)
		if not FileAccess.file_exists(p):
			continue
		var txt := FileAccess.get_file_as_bytes(p).get_string_from_ascii()
		for g in targets:
			for serial in g.get("dump", {}).get("serials", []):
				if txt.contains(serial):
					_add_dump(res, g.id, dir, serial)


func _check_dump_file(path: String, targets: Array, res: Dictionary) -> void:
	var low := path.get_file().to_lower()
	if low.ends_with(".bin") and FileAccess.file_exists(path.get_basename() + ".cue"):
		return   # the .cue stands for the whole disc
	var id := identify(path)
	for g in targets:
		var d: Dictionary = g.get("dump", {})
		if d.is_empty():
			continue
		var hit := ""
		for serial in d.get("serials", []):
			if id.serial != "" and id.serial.replace("_", "-").replace(".", "").to_upper().begins_with(str(serial).replace("_", "-").to_upper()):
				hit = serial
		if hit == "" and id.serial == "":
			for n in d.get("names", []):
				if low.contains(str(n)):
					hit = "by name"
		if hit != "" and d.get("kinds", []).has(low.get_extension()):
			_add_dump(res, g.id, path, hit)


func _add_dump(res: Dictionary, id: String, path: String, serial: String) -> void:
	var list: Array = res.dumps.get(id, [])
	if not list.any(func(e): return e.path == path):
		list.append({"path": path, "serial": serial})
	res.dumps[id] = list


# ------------------------------------------------------------------ identify
## Reads just enough of a dump to say what it is: {platform, serial, title}.
static func identify(path: String) -> Dictionary:
	var out := {"platform": "", "serial": "", "title": ""}
	var ext := path.get_extension().to_lower()
	if ext == "cue":
		var txt := FileAccess.get_file_as_string(path)
		var m := RegEx.create_from_string("FILE\\s+\"([^\"]+)\"").search(txt)
		if m == null:
			return out
		path = path.get_base_dir().path_join(m.get_string(1))
		ext = "bin"
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return out
	var head := f.get_buffer(0x400)
	f.close()
	if head.size() < 0x80:
		return out
	var magic := head.slice(0, 4).get_string_from_ascii()
	if (head[0] == 0x52 and head[1] == 0x56 and head[2] == 0x5A and head[3] == 1) or (head[0] == 0x57 and head[1] == 0x49 and head[2] == 0x41 and head[3] == 1):
		out.platform = "Wii"
		out.serial = head.slice(0x58, 0x5E).get_string_from_ascii()
		return out
	if magic == "WBFS":
		out.platform = "Wii"
		out.serial = head.slice(0x200, 0x206).get_string_from_ascii()
		return out
	if head[0x18] == 0x5D and head[0x19] == 0x1C and head[0x1A] == 0x9E and head[0x1B] == 0xA3:
		out.platform = "Wii"
		out.serial = head.slice(0, 6).get_string_from_ascii()
		return out
	if ext in ["iso", "bin", "img"]:
		var iso := Iso9660.open(path)
		if iso.ok:
			out.title = iso.volume_id
			var umd := iso.read_file("UMD_DATA.BIN", 64)
			if umd.size() > 0:
				out.platform = "PSP"
				out.serial = umd.get_string_from_ascii().split("|")[0]
			else:
				var cnf := iso.read_file("SYSTEM.CNF", 512).get_string_from_ascii()
				var m := RegEx.create_from_string("BOOT2?\\s*=\\s*cdrom0?:\\\\?([A-Z]{4}[_-]\\d{3}\\.\\d{2})").search(cnf)
				if m:
					out.platform = "PlayStation 2" if cnf.contains("BOOT2") else "PlayStation"
					out.serial = m.get_string(1).replace("_", "-").replace(".", "")
			iso.close()
	return out
