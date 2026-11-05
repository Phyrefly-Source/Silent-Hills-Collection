extends RefCounted
## Films: finds your copies of the Silent Hill films and matches them to the
## catalogue (data/films.json). Looks in a "Movies" or "Films" folder beside
## the launcher (or one folder up), Silent Hill folders in Videos, and folders
## added in Settings. A file can also be chosen by hand.

signal scanned

const VIDEO := ["mkv", "mp4", "m4v", "avi", "mov", "webm", "ts", "m2ts", "wmv", "mpg", "mpeg"]

var extra: Array = []   # video files that don't match a catalogue film


static func roots() -> Array:
	var out := []
	for f in App.settings.get("movie_folders", []):
		out.append(str(f))
	for base in [App.root_dir, App.root_dir.get_base_dir()]:
		for name in ["Movies", "Films", "Movie", "Film"]:
			var p: String = base.path_join(name)
			if DirAccess.dir_exists_absolute(p) and not out.has(p):
				out.append(p)
	var vids := OS.get_system_dir(OS.SYSTEM_DIR_MOVIES)
	if vids != "" and DirAccess.dir_exists_absolute(vids):
		for sub in DirAccess.get_directories_at(vids):
			if sub.to_lower().contains("silent hill"):
				out.append(vids.path_join(sub))
		for f in DirAccess.get_files_at(vids):
			if f.to_lower().contains("silent hill") and VIDEO.has(f.get_extension().to_lower()):
				out.append(vids.path_join(f))
	return out


## "Silent.Hill.Revelation.2012.1080p.BluRay.x264" -> "silent hill revelation"
static func clean_name(file: String) -> String:
	var n := file.get_file().get_basename().to_lower()
	n = RegEx.create_from_string("[\\[(].*?[\\])]").sub(n, " ", true)
	n = RegEx.create_from_string("[._]+").sub(n, " ", true)
	var cut := RegEx.create_from_string("\\b(19|20)\\d\\d\\b|\\b(2160p|1080p|720p|480p|4k|uhd|bluray|blu ray|bdrip|brrip|web ?dl|webrip|hdr|x264|x265|h264|h265|hevc|remux|dvdrip|3d)\\b").search(n)
	if cut:
		n = n.substr(0, cut.get_start())
	n = RegEx.create_from_string("[^a-z0-9]+").sub(n, " ", true)
	return n.strip_edges()


## The catalogue film a file is, or "".
static func film_for(file: String) -> String:
	var n := clean_name(file)
	var best := ""
	var best_len := -1
	for f in App.films:
		var m := RegEx.create_from_string(str(f.get("match", "^$"))).search(n)
		if m and m.get_string().length() > best_len:
			best = f.id
			best_len = m.get_string().length()
	return best


## Looks for films off the main thread, then connects the ones not yet connected.
func scan(done: Callable = Callable()) -> void:
	var rs := roots()
	App.run(func():
		var files := []
		for r in rs:
			if FileAccess.file_exists(r):
				files.append(r)
			else:
				_walk(r, 3, files)
		return files,
	func(files: Array):
		extra = []
		var taken := {}
		for f in App.films:
			var p := str(App.state(f.id).get("path", ""))
			if p != "" and FileAccess.file_exists(p):
				taken[f.id] = true
		for file in files:
			var id := film_for(file)
			if id == "":
				extra.append(file)
			elif not taken.has(id):
				App.set_state(id, {"path": file})
				taken[id] = true
		scanned.emit()
		if done.is_valid():
			done.call())


static func _walk(dir: String, depth: int, out: Array) -> void:
	if depth < 0 or not DirAccess.dir_exists_absolute(dir):
		return
	for f in DirAccess.get_files_at(dir):
		if VIDEO.has(f.get_extension().to_lower()) and not f.to_lower().contains("sample"):
			out.append(dir.path_join(f))
	for sub in DirAccess.get_directories_at(dir):
		_walk(dir.path_join(sub), depth - 1, out)


func path_of(id: String) -> String:
	var p := str(App.state(id).get("path", ""))
	return p if p != "" and FileAccess.file_exists(p) else ""


func set_path(id: String, file: String) -> void:
	App.set_state(id, {"path": file})
	scanned.emit()


func set_place(id: String, sec: float) -> void:
	if not App.library.has("films"):
		App.library.films = {}
	if not App.library.films.has("progress"):
		App.library.films.progress = {}
	App.library.films.progress[id] = sec
	if not App.library.films.has("progress_at"):
		App.library.films.progress_at = {}
	App.library.films.progress_at[id] = int(Time.get_unix_time_from_system())
	App.mark_dirty("library")


## Seconds into the film where you stopped (0 when not started or finished).
func place(id: String) -> float:
	return float(App.library.get("films", {}).get("progress", {}).get(id, 0.0))


## When the place was last saved (unix time; 0 if never).
func place_at(id: String) -> int:
	return int(App.library.get("films", {}).get("progress_at", {}).get(id, 0))
