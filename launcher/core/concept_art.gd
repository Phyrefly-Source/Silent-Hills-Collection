extends RefCounted
## Concept Art: the officially released concept art for each game, gathered in
## one place. Pictures come from Silent Hill Memories at run time, plus any
## folders of art the player adds (art book scans, press kits) under
## data/concept-art/<game>. Nothing is downloaded in bulk from the site.

signal changed(game_id: String)   # pictures were added
signal loaded(game_id: String)    # the site's list for a game arrived

const IMG := ["jpg", "jpeg", "png", "webp"]

var _site := {}      # game id -> [picture] (null while loading)
var _waiting := {}   # game id -> [callbacks]


func offline_dir(id: String = "") -> String:
	var d := App.data_dir.path_join("concept-art")
	return d.path_join(id) if id != "" else d


## Everything for a game or film:
## cb([{name, section, thumb, full, ext, artist, page, source, local, url}]).
## "full" is a local path when a copy is kept, otherwise the site's URL.
func pictures(id: String, cb: Callable) -> void:
	var local := _local(id)
	_site_list(id, func(list: Array):
		var out := []
		var seen := {}
		for img in list:
			var keep := _offline_path(id, img)
			var has := FileAccess.file_exists(keep)
			out.append({"name": img.caption, "section": img.section, "thumb": keep if has else img.thumb,
				"full": keep if has else img.full, "ext": "." + str(img.full).get_extension().to_lower(),
				"artist": "", "page": img.page, "source": "Silent Hill Memories", "local": has, "url": img.full})
			seen[keep.get_file().to_lower()] = true
		for p in local:
			if seen.has(str(p).get_file().to_lower()):
				continue   # a kept copy of a site picture, already listed
			out.append({"name": str(p).get_file().get_basename().replace("_", " "), "section": "Your files", "thumb": p, "full": p,
				"ext": "." + str(p).get_extension(), "artist": "", "page": "", "source": "Your files", "local": true, "url": ""})
		cb.call(out))


## Cached count, or -1 while unknown.
func count(id: String) -> int:
	var w = _site.get(id, null)
	var kept := {}
	for img in (w if w != null else []):
		kept[_offline_path(id, img).get_file().to_lower()] = true
	var n := _local(id).filter(func(p): return not kept.has(str(p).get_file().to_lower())).size()
	if w == null:
		return -1 if n == 0 else n
	return (w as Array).size() + n


func _site_list(id: String, cb: Callable) -> void:
	if _site.has(id) and _site[id] != null:
		cb.call(_site[id])
		return
	if _waiting.has(id):
		_waiting[id].append(cb)
		return
	_waiting[id] = [cb]
	_site[id] = null
	var shm = App.svc("shm")
	shm.gallery(shm.folder_of(App.entry(id)), "art", func(list: Array):
		_site[id] = list
		var cbs: Array = _waiting.get(id, [])
		_waiting.erase(id)
		for c in cbs:
			if c.is_valid():
				c.call(list)
		loaded.emit(id))


## Pictures in the player's own folders that belong to this game: kept copies
## in data/concept-art/<game>, and added folders whose name matches the game.
func _local(id: String) -> Array:
	var out := []
	_images(offline_dir(id), 3, out)
	for root in App.settings.get("concept_folders", []):
		var r := str(root)
		if not DirAccess.dir_exists_absolute(r):
			continue
		if game_for_folder(r.get_file()) == id:
			_images(r, 4, out)
			continue
		for sub in DirAccess.get_directories_at(r):
			if game_for_folder(sub) == id:
				_images(r.path_join(sub), 4, out)
	return out


## Pictures in added folders that don't match any game.
func other_pictures() -> Array:
	var out := []
	for root in App.settings.get("concept_folders", []):
		var r := str(root)
		if not DirAccess.dir_exists_absolute(r) or game_for_folder(r.get_file()) != "":
			continue
		for f in DirAccess.get_files_at(r):
			if IMG.has(f.get_extension().to_lower()):
				out.append(r.path_join(f))
		for sub in DirAccess.get_directories_at(r):
			if game_for_folder(sub) == "":
				_images(r.path_join(sub), 4, out)
	return out


static func game_for_folder(name: String) -> String:
	var MusicLibrary = load("res://core/music/music_library.gd")
	var g: String = MusicLibrary.album_game(name)
	if g != "":
		return g
	# "Silent Hill" alone (or "SH1") is the first game.
	var n := name.to_lower().replace("_", " ").strip_edges()
	if n in ["silent hill", "silent hill 1", "sh1", "sh"]:
		return "sh1"
	var m := RegEx.create_from_string("^sh ?([234])\\b").search(n)
	if m:
		return "sh" + m.get_string(1)
	return ""


static func _images(dir: String, depth: int, out: Array) -> void:
	if depth < 0 or not DirAccess.dir_exists_absolute(dir):
		return
	var files := Array(DirAccess.get_files_at(dir))
	files.sort_custom(func(a, b): return a.naturalnocasecmp_to(b) < 0)
	for f in files:
		if IMG.has(f.get_extension().to_lower()):
			out.append(dir.path_join(f))
	for sub in DirAccess.get_directories_at(dir):
		_images(dir.path_join(sub), depth - 1, out)


func add_folder(path: String) -> void:
	var list: Array = App.settings.get("concept_folders", [])
	if not list.has(path):
		list.append(path)
		App.set_setting("concept_folders", list)
	for g in App.games:
		changed.emit(g.id)


# ------------------------------------------------------------------ local copies
static func _safe(name: String) -> String:
	return RegEx.create_from_string("[\\\\/:*?\"<>|]+").sub(name, "_", true).strip_edges()


func _offline_path(id: String, img: Dictionary) -> String:
	# The site's own file name ("sh3_art_char_heather_01.jpg"), kept as is.
	return offline_dir(id).path_join(_safe(str(img.full).get_file().split("?")[0]))
