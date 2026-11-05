extends RefCounted
## Comics: the series' comics (data/comics.json) matched with the player's own
## files. Reads CBZ/ZIP archives and folders of page images directly. CBR and
## CB7 are unpacked once with 7-Zip when it's installed. Reading position is
## remembered per comic.

signal scanned

const IMG := ["jpg", "jpeg", "png", "webp", "bmp", "gif"]
const ARCHIVES := ["cbz", "zip", "cbr", "rar", "cb7", "7z", "pdf"]

var items: Array = []    # {id, path, kind, title, catalogue}
var busy := false
var _pages := {}         # id -> [page names]


func _init() -> void:
	items = App.read_json(App.cache_dir.path_join("comics-index.json"), {}).get("items", [])


func data() -> Dictionary:
	var c: Dictionary = App.library.comics
	if not c.has("progress"):
		c.progress = {}
	if not c.has("files"):
		c.files = []
	return c


## Catalogue entries with the player's copies attached, in issue order.
func shelf() -> Array:
	var out := []
	for c in App.comics_catalogue:
		var own := items.filter(func(i): return i.catalogue == c.id)
		own.sort_custom(_by_issue)
		out.append({"entry": c, "copies": own})
	var unmatched := items.filter(func(i): return i.catalogue == "")
	for i in unmatched:
		out.append({"entry": {"id": i.id, "title": i.title, "year": 0, "publisher": "", "issues": 0}, "copies": [i]})
	return out


static func _by_issue(a: Dictionary, b: Dictionary) -> bool:
	var ia := int(a.get("issue", 0))
	var ib := int(b.get("issue", 0))
	if ia != ib:
		return ia < ib
	return str(a.title).naturalnocasecmp_to(str(b.title)) < 0


## The shelf entry a copy belongs to.
func series_of(it: Dictionary) -> Dictionary:
	for s in shelf():
		for c in s.copies:
			if c.id == it.id:
				return s
	return {}


## The copy after this one in its series, or {}.
func next_issue(it: Dictionary) -> Dictionary:
	var s := series_of(it)
	if s.is_empty():
		return {}
	var list: Array = s.copies
	for i in list.size() - 1:
		if list[i].id == it.id:
			return list[i + 1]
	return {}


## Issue number from a file name: "Issue #3", "#3", "No. 3"; 0 when there is none.
static func issue_of(name: String) -> int:
	var m := RegEx.create_from_string("(?i)(?:#|issue[\\s_]*#?|\\bno\\.?[\\s_]*)(\\d{1,3})").search(name)
	return m.get_string(1).to_int() if m else 0


func scan(done: Callable = Callable()) -> void:
	if busy:
		return
	busy = true
	var roots: Array = App.settings.get("comic_folders", []).duplicate()
	var files: Array = data().files.duplicate()
	App.run(func():
		var found := []
		for r in roots:
			_walk(str(r), 4, found)
		for f in files:
			if FileAccess.file_exists(f) or DirAccess.dir_exists_absolute(f):
				var it := _item(f, DirAccess.dir_exists_absolute(f))
				if not it.is_empty():
					found.append(it)
		var seen := {}
		return found.filter(func(i):
			if seen.has(i.id):
				return false
			seen[i.id] = true
			return true),
	func(found):
		items = found
		App.write_json(App.cache_dir.path_join("comics-index.json"), {"items": items})
		busy = false
		scanned.emit()
		if done.is_valid():
			done.call())


func add_path(p: String) -> void:
	if DirAccess.dir_exists_absolute(p) and _images_in(p).is_empty():
		var folders: Array = App.settings.get("comic_folders", [])
		if not folders.has(p):
			folders.append(p)
			App.set_setting("comic_folders", folders)
	else:
		var f: Array = data().files
		if not f.has(p):
			f.append(p)
			App.mark_dirty("library")
	scan()


func _walk(dir: String, depth: int, out: Array) -> void:
	if depth < 0 or not DirAccess.dir_exists_absolute(dir):
		return
	if dir.begins_with(App.data_dir) or dir.get_file().begins_with("."):
		return   # the launcher's own art and caches aren't comics
	if _images_in(dir).size() >= 3:
		var it := _item(dir, true)
		if not it.is_empty():
			out.append(it)
		return
	for f in DirAccess.get_files_at(dir):
		if ARCHIVES.has(f.get_extension().to_lower()):
			out.append(_item(dir.path_join(f), false))
	for sub in DirAccess.get_directories_at(dir):
		_walk(dir.path_join(sub), depth - 1, out)


func _images_in(dir: String) -> Array:
	var out := []
	for f in DirAccess.get_files_at(dir):
		if IMG.has(f.get_extension().to_lower()):
			out.append(f)
	out.sort_custom(func(a, b): return a.naturalnocasecmp_to(b) < 0)
	return out


func _item(p: String, is_dir: bool) -> Dictionary:
	var name := p.get_file() if is_dir else p.get_file().get_basename()
	var kind := "folder" if is_dir else p.get_extension().to_lower()
	if kind == "zip":
		kind = "cbz"
	if kind in ["rar"]:
		kind = "cbr"
	if kind in ["7z"]:
		kind = "cb7"
	return {"id": p.to_lower().md5_text().substr(0, 12), "path": p, "kind": kind, "title": _pretty(name), "catalogue": _match(name), "issue": issue_of(name)}


static func _norm(s: String) -> String:
	return RegEx.create_from_string("[^a-z0-9]+").sub(s.to_lower(), " ", true).strip_edges()


func _match(name: String) -> String:
	var n := _norm(name)
	var best := ""
	var best_len := 0
	for c in App.comics_catalogue:
		for m in c.get("match", []):
			var mm := _norm(str(m))
			if n.contains(mm) and mm.length() > best_len:
				best = c.id
				best_len = mm.length()
	return best


static func _pretty(name: String) -> String:
	return name.replace("_", " ").replace(".", " ").strip_edges()


# ------------------------------------------------------------------ pages
## Page list for a comic (names inside the archive or folder). Empty if unreadable.
func pages(it: Dictionary) -> Array:
	if _pages.has(it.id):
		return _pages[it.id]
	var out := []
	match it.kind:
		"cbz":
			var z := ZIPReader.new()
			if z.open(it.path) == OK:
				for f in z.get_files():
					if IMG.has(f.get_extension().to_lower()) and not f.get_file().begins_with("."):
						out.append(f)
				z.close()
		"folder":
			out = _images_in(it.path)
		"cbr", "cb7":
			var dir := _unpacked_dir(it)
			if dir != "":
				out = _walk_images(dir, "")
	out.sort_custom(func(a, b): return a.naturalnocasecmp_to(b) < 0)
	_pages[it.id] = out
	return out


func _walk_images(root: String, rel: String) -> Array:
	var out := []
	var d := root.path_join(rel) if rel != "" else root
	for f in DirAccess.get_files_at(d):
		if IMG.has(f.get_extension().to_lower()):
			out.append(rel.path_join(f) if rel != "" else f)
	for sub in DirAccess.get_directories_at(d):
		out.append_array(_walk_images(root, rel.path_join(sub) if rel != "" else sub))
	return out


func readable(it: Dictionary) -> String:
	match it.kind:
		"cbz", "folder":
			return ""
		"cbr", "cb7":
			return "" if _seven_zip() != "" else "Install 7-Zip to read %s files." % it.kind.to_upper()
		"pdf":
			return "PDF comics can't be read in the launcher yet. A CBZ or a folder of pages works."
	return "Unknown format."


func _seven_zip() -> String:
	for p in ["C:/Program Files/7-Zip/7z.exe", "C:/Program Files (x86)/7-Zip/7z.exe", App.root_dir.path_join("tools/7z.exe")]:
		if FileAccess.file_exists(p):
			return p
	return ""


func _unpacked_dir(it: Dictionary) -> String:
	var dir := App.cache_dir.path_join("comics").path_join(it.id)
	if DirAccess.dir_exists_absolute(dir) and not _walk_images(dir, "").is_empty():
		return dir
	var sz := _seven_zip()
	if sz == "":
		return ""
	DirAccess.make_dir_recursive_absolute(dir)
	OS.execute(sz, ["x", "-y", "-o" + dir, it.path], [], false, false)
	return dir


## Loads page i as an Image (call from a worker thread).
func page_image(it: Dictionary, i: int) -> Image:
	var list := pages(it)
	if i < 0 or i >= list.size():
		return null
	var name: String = list[i]
	var img := Image.new()
	var bytes := PackedByteArray()
	match it.kind:
		"cbz":
			var z := ZIPReader.new()
			if z.open(it.path) == OK:
				bytes = z.read_file(name)
				z.close()
		"folder":
			bytes = FileAccess.get_file_as_bytes(it.path.path_join(name))
		_:
			bytes = FileAccess.get_file_as_bytes(_unpacked_dir(it).path_join(name))
	var ext := name.get_extension().to_lower()
	var err := ERR_FILE_UNRECOGNIZED
	match ext:
		"jpg", "jpeg":
			err = img.load_jpg_from_buffer(bytes)
		"png":
			err = img.load_png_from_buffer(bytes)
		"webp":
			err = img.load_webp_from_buffer(bytes)
		"bmp":
			err = img.load_bmp_from_buffer(bytes)
	return img if err == OK else null


func cover_path(it: Dictionary) -> String:
	return App.cache_dir.path_join("comics-covers").path_join(it.id + ".webp")


## cb(Texture2D or null)
func cover(it: Dictionary, cb: Callable) -> void:
	var p := cover_path(it)
	App.run(func():
		var img := Image.new()
		if FileAccess.file_exists(p) and img.load(p) == OK:
			return img
		if readable(it) != "":
			return null
		var page := page_image(it, 0)
		if page == null:
			return null
		var w := 360
		page.resize(w, int(page.get_height() * float(w) / page.get_width()), Image.INTERPOLATE_LANCZOS)
		DirAccess.make_dir_recursive_absolute(p.get_base_dir())
		page.save_webp(p, false, 0.85)
		return page,
	func(img):
		cb.call(ImageTexture.create_from_image(img) if img != null else null))


func progress(it: Dictionary) -> int:
	return int(data().progress.get(it.id, 0))


## Pages in a copy, once it has been opened (0 before that).
func page_count(it: Dictionary) -> int:
	return int(data().get("pages", {}).get(it.id, 0))


## 0..1 through the comic; 1 when the last page was reached.
func fraction(it: Dictionary) -> float:
	var n := page_count(it)
	if n <= 1:
		return 0.0
	return clampf(float(progress(it)) / float(n - 1), 0.0, 1.0)


func started(it: Dictionary) -> bool:
	return data().progress.has(it.id)


func finished(it: Dictionary) -> bool:
	return bool(data().get("finished", {}).get(it.id, false))


func set_progress(it: Dictionary, page: int, total: int = 0) -> void:
	var d := data()
	d.progress[it.id] = page
	if not d.has("progress_at"):
		d.progress_at = {}
	d.progress_at[it.id] = int(Time.get_unix_time_from_system())
	if total > 0:
		if not d.has("pages"):
			d.pages = {}
		d.pages[it.id] = total
		if page >= total - 1:
			if not d.has("finished"):
				d.finished = {}
			d.finished[it.id] = true
	d.last = it.id
	App.mark_dirty("library")


## The copy read most recently, if it isn't finished; otherwise {}.
func continue_item() -> Dictionary:
	var id: String = data().get("last", "")
	for i in items:
		if i.id == id:
			if finished(i):
				var nx := next_issue(i)
				return nx if not nx.is_empty() and not finished(nx) else {}
			return i
	return {}
