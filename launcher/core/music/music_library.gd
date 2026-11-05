extends RefCounted
## Music library: the player's own soundtrack albums (an OSTs folder beside the
## launcher, Music, or folders added in Settings), matched to the games, with
## favourites and playlists. Loose ADX / AIX rips in those folders play too.
## Indexing only reads headers, so it's quick; tracks are decoded when played.

signal indexed

const NATIVE := ["ogg", "mp3", "wav"]
const VIA_FFMPEG := ["flac", "m4a", "aac", "opus", "wma"]

var tracks: Array = []
var _by_id := {}
var busy := false


func _init() -> void:
	var cached: Dictionary = App.read_json(App.cache_dir.path_join("music-index.json"), {})
	# Older indexes also listed music from inside the games; that's gone now.
	_set_tracks(cached.get("tracks", []).filter(func(t): return str(t.get("album_key", "")).begins_with("ost:")))
	_folders_sig = str(cached.get("folders", ""))


var _folders_sig := ""


## A cheap fingerprint of the soundtrack folders: their album folders, file
## counts and change times. Reading it touches no audio files.
## Bumped when indexing changes, so existing indexes are rebuilt once.
const INDEX_VERSION := 3


static func folders_signature() -> String:
	var parts := ["v%d" % INDEX_VERSION]
	for r in soundtrack_roots():
		parts.append(r)
		var dirs := [r]
		for sub in DirAccess.get_directories_at(r):
			dirs.append(r.path_join(sub))
		for d in dirs:
			var files := DirAccess.get_files_at(d)
			var newest := 0
			for f in files:
				newest = maxi(newest, FileAccess.get_modified_time(d.path_join(f)))
			parts.append("%s|%d|%d" % [d.get_file(), files.size(), newest])
	return "\n".join(parts).md5_text()


## Re-reads the music when soundtrack folders were added or changed since the
## last index (an OSTs folder dropped beside the launcher is picked up on start).
func refresh_if_changed() -> void:
	App.run(func(): return folders_signature(), func(sig):
		if sig != _folders_sig:
			index())


func _set_tracks(list: Array) -> void:
	tracks = list
	_by_id.clear()
	for t in tracks:
		_by_id[t.id] = t


func track(id: String) -> Dictionary:
	return _by_id.get(id, {})


func data() -> Dictionary:
	var m: Dictionary = App.library.music
	for k in ["favorites", "playlists", "names", "layers"]:
		if not m.has(k):
			m[k] = [] if k == "favorites" else {}
	return m


func title_of(t: Dictionary) -> String:
	return str(data().names.get(t.id, t.title))


# ------------------------------------------------------------------ albums
## [{key, title, game, kind, cover, tracks}]. kind: "ost" (an official soundtrack
## matched to a game), "game" (music pulled from an installed game), "folder".
## Soundtracks first, then game music, each in release order, then folders.
func albums() -> Array:
	var by := {}
	var order := []
	for t in tracks:
		var k: String = t.album_key
		if not by.has(k):
			var gid := str(t.get("game", ""))
			var kind := ("film" if gid.begins_with("film-") else "ost") if gid != "" else "folder"
			by[k] = {"key": k, "title": t.album, "game": t.get("game", ""), "kind": kind, "cover": t.get("cover", ""), "tracks": []}
			order.append(k)
		by[k].tracks.append(t)
	var game_order := {}
	for i in App.games.size():
		game_order[App.games[i].id] = i
	for i in App.films.size():
		game_order[App.films[i].id] = 100 + i
	var rank := {"ost": 0, "film": 1, "folder": 2}
	var list: Array = order.map(func(k): return by[k])
	list.sort_custom(func(a, b):
		if a.kind != b.kind:
			return rank[a.kind] < rank[b.kind]
		var ga: int = game_order.get(a.game, 999)
		var gb: int = game_order.get(b.game, 999)
		if ga != gb:
			return ga < gb
		return str(a.title).naturalnocasecmp_to(str(b.title)) < 0)
	return list


func favorites() -> Array:
	return data().favorites.map(func(id): return track(id)).filter(func(t): return not t.is_empty())


func is_favorite(id: String) -> bool:
	return data().favorites.has(id)


func toggle_favorite(id: String) -> void:
	var f: Array = data().favorites
	if f.has(id):
		f.erase(id)
	else:
		f.append(id)
	App.mark_dirty("library")


func playlists() -> Dictionary:
	return data().playlists


func playlist_tracks(name: String) -> Array:
	return data().playlists.get(name, []).map(func(id): return track(id)).filter(func(t): return not t.is_empty())


func add_to_playlist(name: String, id: String) -> void:
	var p: Dictionary = data().playlists
	if not p.has(name):
		p[name] = []
	if not p[name].has(id):
		p[name].append(id)
	App.mark_dirty("library")


func remove_from_playlist(name: String, id: String) -> void:
	data().playlists.get(name, []).erase(id)
	App.mark_dirty("library")


func delete_playlist(name: String) -> void:
	data().playlists.erase(name)
	App.mark_dirty("library")


func rename_track(id: String, title: String) -> void:
	if title.strip_edges() == "":
		data().names.erase(id)
	else:
		data().names[id] = title.strip_edges()
	App.mark_dirty("library")


# ------------------------------------------------------------------ indexing
## Reads the soundtrack folders (see soundtrack_roots). Music inside the game
## files isn't listed: the official albums replace it.
func index(done: Callable = Callable()) -> void:
	if busy:
		return
	busy = true
	var folders: Array = soundtrack_roots()
	App.run(func():
		var out := []
		for f in folders:
			out.append_array(_index_folder(str(f)))
		return [out, folders_signature()],
	func(res):
		var out: Array = res[0]
		var sig: String = res[1]
		_set_tracks(out)
		App.write_json(App.cache_dir.path_join("music-index.json"), {"built": int(Time.get_unix_time_from_system()), "folders": sig, "tracks": out})
		_folders_sig = sig
		busy = false
		indexed.emit()
		if done.is_valid():
			done.call())


static func _id(file: String, offset: int) -> String:
	return (file.to_lower() + "#" + str(offset)).md5_text().substr(0, 12)


static func _aix_seconds(head: PackedByteArray, size: int) -> float:
	var pos := 8 + SoundContainers._be32(head, 4)
	if pos + 16 > head.size():
		return 0.0
	var layers: int = max(1, head[pos + 9])
	var info := AdxStream.header_info(head.slice(pos + 16, pos + 48))
	if info.is_empty():
		return 0.0
	return (size - pos) / (18.0 / 32.0 * info.channels * layers) / max(info.rate, 1)


static func _describe_file(f: String) -> Dictionary:
	var ext := f.get_extension().to_lower()
	var t := {"id": _id(f, 0), "title": f.get_file().get_basename().replace("_", " ").capitalize() if f.get_file().begins_with("bgm") else f.get_file().get_basename(), "file": f, "offset": 0, "size": 0, "seconds": 0.0}
	if ext == "adx":
		var info := AdxStream.header_info(SoundContainers.read_range(f, 0, 0x20))
		if info.is_empty():
			return {}
		t.kind = "adx"
		t.seconds = info.seconds
	elif ext == "aix":
		var fa := FileAccess.open(f, FileAccess.READ)
		var size := fa.get_length()
		fa.close()
		t.kind = "aix"
		t.seconds = _aix_seconds(SoundContainers.read_range(f, 0, 0x4000), size)
	elif NATIVE.has(ext):
		t.kind = "native"
	elif VIA_FFMPEG.has(ext):
		t.kind = "ffmpeg"
	else:
		return {}
	return t


## Words that say nothing about which game an album belongs to.
const NOISE := ["original", "soundtrack", "soundtracks", "ost", "game", "video", "music", "official", "the", "of", "complete", "edition", "konami"]


static func norm_album(s: String) -> String:
	var t := s.to_lower()
	t = RegEx.create_from_string("([a-z])(\\d)").sub(t, "$1 $2", true)   # "hill2" -> "hill 2"
	t = RegEx.create_from_string("[^a-z0-9]+").sub(t, " ", true).strip_edges()
	var words := Array(t.split(" ", false)).filter(func(w): return not NOISE.has(w))
	return " ".join(words)


## Which game an album belongs to, from its name; "" if none. The most specific
## (longest) match wins, so "Silent Hill 2 2024" is the remake, not the original.
static func album_game(name: String) -> String:
	var n := norm_album(name)
	var best := ""
	var best_len := -1
	for g in App.games + App.films:
		var p: String = g.get("ost_match", "")
		if p == "":
			continue
		var m := RegEx.create_from_string(p).search(n)
		if m and m.get_string().length() > best_len:
			best = g.id
			best_len = m.get_string().length()
	return best


## Folders that hold soundtracks: the ones added in Settings, plus an "OSTs" or
## "Soundtracks" folder beside the launcher, and Silent Hill folders in Music.
static func soundtrack_roots() -> Array:
	var out := []
	for f in App.settings.get("music_folders", []):
		out.append(str(f))
	for base in [App.root_dir, App.root_dir.get_base_dir()]:
		for name in ["OSTs", "OST", "Soundtracks", "Soundtrack", "Music"]:
			var p: String = base.path_join(name)
			if DirAccess.dir_exists_absolute(p) and not out.has(p):
				out.append(p)
	var music := OS.get_system_dir(OS.SYSTEM_DIR_MUSIC)
	if music != "" and DirAccess.dir_exists_absolute(music):
		for sub in DirAccess.get_directories_at(music):
			if sub.to_lower().contains("silent hill") and not out.has(music.path_join(sub)):
				out.append(music.path_join(sub))
	return out


static func _index_folder(root: String) -> Array:
	var out := []
	var by_dir := {}
	for f in walk_files(root, 6):
		var ext: String = str(f).get_extension().to_lower()
		if not (NATIVE.has(ext) or VIA_FFMPEG.has(ext) or ext == "adx" or ext == "aix"):
			continue
		var d: String = str(f).get_base_dir()
		if not by_dir.has(d):
			by_dir[d] = []
		by_dir[d].append(f)
	for d in by_dir:
		var files: Array = by_dir[d]
		var tracks := []
		var albums := {}
		var discs := {}
		for f in files:
			var t := _describe_file(f)
			if t.is_empty():
				continue
			var tags := AudioTags.read(f)
			t.title = tags.title if tags.title != "" else _title_from_name(str(f))
			t.artist = tags.artist
			t.track = int(tags.track)
			t.disc = max(1, int(tags.disc))
			t.year = tags.year
			if tags.seconds > 0:
				t.seconds = tags.seconds
			if tags.album != "":
				albums[tags.album] = int(albums.get(tags.album, 0)) + 1
			discs[t.disc] = true
			tracks.append(t)
		if tracks.is_empty():
			continue
		# Badly tagged albums give every track the same "title" (often the album
		# name, with the real title in the artist field and the uploader as the
		# artist): use the file names, and credit the game's composer below.
		var broken := false
		if tracks.size() > 2:
			var same := {}
			for t in tracks:
				same[t.title] = int(same.get(t.title, 0)) + 1
			for t in tracks:
				if same[t.title] * 2 > tracks.size():
					t.title = _title_from_name(t.file)
					t.artist = ""
					broken = true
		# Titles with a dash ("Breeze - in Monochrome Night") are sometimes split
		# into artist "Breeze", title "in Monochrome Night": put them back together.
		var main_artist := _main_artist(tracks)
		if main_artist != "":
			for t in tracks:
				var ar := str(t.artist)
				if ar != "" and ar.to_lower() != main_artist.to_lower() and str(t.file).get_file().begins_with(ar + " - " + str(t.title)):
					t.title = ar + " - " + str(t.title)
					t.artist = main_artist
		# Album name: what most of the tags say, else the folder's name.
		var album: String = d.get_file()
		var most := 0
		for a in albums:
			if albums[a] > most:
				most = albums[a]
				album = a
		var game := album_game(album)
		if game == "":
			game = album_game(d.get_file())
		# Tracks with no usable artist are credited to the game's composer.
		var composer: String = App.game(game).get("composer", "") if game != "" else ""
		if composer != "":
			for t in tracks:
				if broken or str(t.artist) == "":
					t.artist = composer
		var cover := _cover_for(d, tracks)
		tracks.sort_custom(func(a, b):
			if a.disc != b.disc:
				return a.disc < b.disc
			if a.track != b.track:
				return (a.track if a.track > 0 else 9999) < (b.track if b.track > 0 else 9999)
			return str(a.file).naturalnocasecmp_to(str(b.file)) < 0)
		var pretty := _pretty_album(album)
		for t in tracks:
			t.album = pretty
			t.album_key = "ost:" + d.to_lower()
			t.game = game
			t.official = game != ""
			t.cover = cover
			t.group = ("Disc %d" % t.disc) if discs.size() > 1 else ""
			out.append(t)
	return out


## The artist on most of an album's tracks (case-insensitive), or "".
static func _main_artist(tracks: Array) -> String:
	var count := {}
	var best := ""
	var best_n := 0
	for t in tracks:
		var ar := str(t.get("artist", ""))
		if ar == "":
			continue
		var k := ar.to_lower()
		count[k] = int(count.get(k, 0)) + 1
		if count[k] > best_n:
			best_n = count[k]
			best = ar
	return best if best_n * 2 > tracks.size() else ""


## A title from a file name: "01 - Artist - Title" -> "Title", while parts that
## name the album ("Apology - Silent Hill Townfall OST") are dropped.
static func _title_from_name(file: String) -> String:
	var base: String = file.get_file().get_basename()
	base = RegEx.create_from_string("^\\d+([.]\\d+)?\\s*[-.]?\\s+").sub(base, "")
	var parts := Array(base.split(" - ", false)).map(func(x): return str(x).strip_edges())
	var keep := parts.filter(func(x):
		var low: String = str(x).to_lower()
		return not (low.contains("silent hill") or low.contains("soundtrack") or low.ends_with(" ost") or low == "ost"))
	if keep.is_empty():
		return base
	return keep[-1] if keep.size() > 1 else keep[0]


## Tidies a tag like "SILENT HILL2 （Original Soundtrack）" for display.
static func _pretty_album(a: String) -> String:
	var s := a.replace("（", " (").replace("）", ")").replace("  ", " ").strip_edges()
	if s == s.to_upper():
		s = s.capitalize().replace("Ost", "OST")
	s = RegEx.create_from_string("(?i)silent hill(\\d)").sub(s, "Silent Hill $1", true)
	s = RegEx.create_from_string("^SILENT HILL\\b").sub(s, "Silent Hill")
	return s


## Album art: a front cover image in the folder (or its Covers folder), else the
## picture embedded in the first track, saved once to the cache.
static func _cover_for(dir: String, tracks: Array) -> String:
	var cands := []
	for sub in [dir, dir.path_join("Covers"), dir.path_join("Scans"), dir.path_join("Artwork")]:
		if not DirAccess.dir_exists_absolute(sub):
			continue
		for f in DirAccess.get_files_at(sub):
			var low: String = f.to_lower()
			if low.get_extension() in ["jpg", "jpeg", "png", "webp"]:
				var score := 0
				for w in ["front", "cover", "folder"]:
					if low.contains(w):
						score += 2
				if low.contains("back") or low.contains("cd") or low.contains("disc"):
					score -= 3
				cands.append([score, sub.path_join(f)])
	if not cands.is_empty():
		cands.sort_custom(func(a, b): return a[0] > b[0])
		return cands[0][1]
	var cache := App.cache_dir.path_join("covers").path_join(dir.to_lower().md5_text().substr(0, 12) + ".img")
	for ext in [".jpg", ".png"]:
		if FileAccess.file_exists(cache.get_basename() + ext):
			return cache.get_basename() + ext
	for t in tracks.slice(0, 3):
		var pic := AudioTags.picture(t.file)
		if pic.size() > 64:
			DirAccess.make_dir_recursive_absolute(cache.get_base_dir())
			var ext := ".png" if pic[0] == 0x89 else ".jpg"
			cache = cache.get_basename() + ext
			var fa := FileAccess.open(cache, FileAccess.WRITE)
			fa.store_buffer(pic)
			fa.close()
			return cache
	return ""


static func walk_files(dir: String, depth: int) -> Array:
	var out := []
	if depth < 0 or not DirAccess.dir_exists_absolute(dir):
		return out
	var files := DirAccess.get_files_at(dir)
	var sorted: Array = Array(files)
	sorted.sort_custom(func(a, b): return a.naturalnocasecmp_to(b) < 0)
	for f in sorted:
		out.append(dir.path_join(f))
	for sub in DirAccess.get_directories_at(dir):
		out.append_array(walk_files(dir.path_join(sub), depth - 1))
	return out


## Expands * in any path segment.
static func glob(pattern: String) -> Array:
	var parts := pattern.split("/")
	var cur: Array = [parts[0] if parts[0] != "" else "/"]
	for i in range(1, parts.size()):
		var seg := parts[i]
		var nxt := []
		var last := i == parts.size() - 1
		for base in cur:
			if not seg.contains("*"):
				var p: String = base.path_join(seg)
				if (last and FileAccess.file_exists(p)) or (not last and DirAccess.dir_exists_absolute(p)):
					nxt.append(p)
				continue
			if not DirAccess.dir_exists_absolute(base):
				continue
			var names: Array = Array(DirAccess.get_files_at(base) if last else DirAccess.get_directories_at(base))
			names.sort_custom(func(a, b): return a.naturalnocasecmp_to(b) < 0)
			for n in names:
				if n.matchn(seg):
					nxt.append(base.path_join(n))
		cur = nxt
	return cur


# ------------------------------------------------------------------ FFmpeg
func ffmpeg_path() -> String:
	var s: String = App.settings.get("ffmpeg", "")
	if s != "" and FileAccess.file_exists(s):
		return s
	for p in [App.root_dir.path_join("tools/ffmpeg.exe"), App.root_dir.path_join("ffmpeg.exe"), App.root_dir.path_join("tools/ffmpeg")]:
		if FileAccess.file_exists(p):
			return p
	return ""


var _converting := {}   # track id -> [callbacks waiting for it]


## True when the track is already converted (or doesn't need converting).
func is_ready(t: Dictionary) -> bool:
	if t.get("kind", "") != "ffmpeg":
		return true
	var out := App.cache_dir.path_join("music").path_join(t.id + ".ogg")
	return FileAccess.file_exists(out) or FileAccess.file_exists(out.get_basename() + ".wav")


## Converts a track FFmpeg can read into a cached OGG, once. cb(path or "").
## A conversion already running (a prefetch) is joined rather than repeated.
func convert_with_ffmpeg(t: Dictionary, cb: Callable) -> void:
	var out := App.cache_dir.path_join("music").path_join(t.id + ".ogg")
	for done in [out, out.get_basename() + ".wav"]:
		if FileAccess.file_exists(done):
			cb.call(done)
			return
	if _converting.has(t.id):
		# Already being converted (a prefetch): wait for that one.
		_converting[t.id].append(cb)
		return
	var ff := ffmpeg_path()
	if ff == "":
		cb.call("")
		return
	_converting[t.id] = [cb]
	var id: String = t.id
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	App.run(func():
		var src: String = t.file
		var tmp := ""
		if t.has("iso_lba"):
			var iso := Iso9660.open(t.file)
			tmp = App.cache_dir.path_join("music").path_join(t.id + "." + str(t.iso_name).get_extension().to_lower())
			var fa := FileAccess.open(tmp, FileAccess.WRITE)
			fa.store_buffer(iso.read_extent(int(t.iso_lba), int(t.iso_size)))
			fa.close()
			iso.close()
			src = tmp
		# Written under a temporary name, so a half-converted file is never played.
		var part := out.get_basename() + ".part.ogg"
		var code := OS.execute(ff, ["-y", "-v", "error", "-i", src, "-vn", "-map_metadata", "-1", "-c:a", "libvorbis", "-q:a", "6", part], [], false, false)
		if code == 0 and FileAccess.file_exists(part):
			DirAccess.rename_absolute(part, out)
		else:
			# Minimal FFmpeg builds may lack libvorbis: fall back to plain WAV.
			DirAccess.remove_absolute(part)
			out = out.get_basename() + ".wav"
			part = out.get_basename() + ".part.wav"
			code = OS.execute(ff, ["-y", "-v", "error", "-i", src, "-vn", "-c:a", "pcm_s16le", part], [], false, false)
			if code == 0 and FileAccess.file_exists(part):
				DirAccess.rename_absolute(part, out)
		if tmp != "":
			DirAccess.remove_absolute(tmp)
		return out if code == 0 and FileAccess.file_exists(out) else "",
	func(path):
		var waiting: Array = _converting.get(id, [])
		_converting.erase(id)
		for c in waiting:
			if c.is_valid():
				c.call(path))
