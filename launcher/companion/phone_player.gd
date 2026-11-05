extends Node
## The companion app's music player: plays soundtrack albums from the PC
## (each track fetched when it's needed, the next one ahead of time) or from
## albums kept on the phone.

signal changed          # track, playing state or queue
signal failed(message: String)

var queue: Array = []   # [{track, album}]
var index := -1
var playing := false
var shuffle := false
var repeat := "all"     # off | all | one
var loading := false

var _player: AudioStreamPlayer
var _order: Array = []
var _token := 0


func _ready() -> void:
	_player = AudioStreamPlayer.new()
	add_child(_player)
	_player.finished.connect(func():
		if repeat == "one":
			_player.play()
		else:
			next(true))


func current() -> Dictionary:
	return queue[index] if index >= 0 and index < queue.size() else {}


func position() -> float:
	return _player.get_playback_position() if _player.stream else 0.0


func length() -> float:
	return _player.stream.get_length() if _player.stream else float(current().get("track", {}).get("seconds", 0.0))


## Plays an album (from the PC's list) starting at track i.
func play_album(album: Dictionary, i: int) -> void:
	queue = []
	for t in album.tracks:
		queue.append({"track": t, "album": album})
	_order = range(queue.size())
	if shuffle:
		_order.shuffle()
		_order.erase(i)
		_order.push_front(i)
	index = i
	_start()


func set_shuffle(on: bool) -> void:
	shuffle = on
	_order = range(queue.size())
	if on:
		_order.shuffle()
		_order.erase(index)
		_order.push_front(index)
	changed.emit()


func toggle() -> void:
	if current().is_empty():
		return
	if _player.stream == null:
		_start()
		return
	playing = not playing
	_player.stream_paused = not playing
	if playing and not _player.playing:
		_player.play()
	changed.emit()


func stop() -> void:
	_player.stop()
	playing = false
	changed.emit()


func next(auto: bool = false) -> void:
	if queue.is_empty():
		return
	var k := _order.find(index)
	if k + 1 >= _order.size():
		if repeat == "off" and auto:
			stop()
			return
		k = -1
	index = _order[k + 1]
	_start()


func prev() -> void:
	if queue.is_empty():
		return
	if position() > 4.0:
		seek(0.0)
		return
	var k := _order.find(index)
	index = _order[maxi(0, k - 1)] if k > 0 else _order[_order.size() - 1]
	_start()


func seek(sec: float) -> void:
	if _player.stream:
		_player.seek(clampf(sec, 0.0, length()))


# ------------------------------------------------------------------ files
static func album_dir(album_key: String) -> String:
	return App.svc("pc").media_dir("music").path_join(album_key.md5_text().substr(0, 16))


## Where a track lives on the phone: kept with its album, or in the cache.
static func track_file(album_key: String, track_id: String) -> String:
	var kept := album_dir(album_key).path_join(track_id.md5_text().substr(0, 16) + ".audio")
	if FileAccess.file_exists(kept):
		return kept
	return App.svc("pc").cache_dir("music").path_join(track_id.md5_text().substr(0, 16) + ".audio")


static func track_path(track_id: String) -> String:
	return "/api/music/track?id=" + track_id.uri_encode()


func _start() -> void:
	var item := current()
	if item.is_empty():
		return
	_token += 1
	var tk := _token
	loading = true
	playing = true
	_player.stop()
	changed.emit()
	var dest := track_file(item.album.key, item.track.id)
	App.svc("pc").fetch(track_path(item.track.id), dest, func(ok: bool):
		if tk != _token:
			return
		loading = false
		var st: AudioStream = load_audio(dest) if ok else null
		if st == null:
			playing = false
			changed.emit()
			failed.emit("Couldn't get this track. Is the PC on, with the companion turned on?" if not ok else "This track couldn't be played.")
			return
		_player.stream = st
		_player.stream_paused = false
		_player.play()
		changed.emit()
		_prefetch())


func _prefetch() -> void:
	var k := _order.find(index)
	if k + 1 < _order.size():
		var nx: Dictionary = queue[_order[k + 1]]
		App.svc("pc").fetch(track_path(nx.track.id), track_file(nx.album.key, nx.track.id), func(_ok): pass)


## Reads an audio file by its contents (OGG, MP3 or WAV).
static func load_audio(path: String) -> AudioStream:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var head := f.get_buffer(4)
	f.close()
	if head.size() < 4:
		return null
	if head.get_string_from_ascii() == "OggS":
		return AudioStreamOggVorbis.load_from_file(path)
	if head.get_string_from_ascii() == "RIFF":
		return AudioStreamWAV.load_from_file(path)
	return AudioStreamMP3.load_from_file(path)


# ------------------------------------------------------------------ keeping albums
static func kept_index() -> Dictionary:
	return App.read_json(App.svc("pc").media_dir("music").path_join("albums.json"), {})


static func is_kept(album_key: String) -> bool:
	return kept_index().has(album_key)


## Downloads every track (and the cover) so the album plays away from home.
## progress(done, total); cb(ok).
static func keep_album(album: Dictionary, progress: Callable, cb: Callable) -> void:
	var pc = App.svc("pc")
	var dir := album_dir(album.key)
	DirAccess.make_dir_recursive_absolute(dir)
	var list: Array = album.tracks
	var step := [0, true]
	var one := func(self_ref: Callable):
		if step[0] >= list.size():
			if album.get("cover", false):
				pc.fetch("/api/music/cover?album=" + str(album.key).uri_encode(), dir.path_join("cover.img"), func(_ok): pass)
			var idx := kept_index()
			idx[album.key] = album
			App.write_json(pc.media_dir("music").path_join("albums.json"), idx)
			cb.call(step[1])
			return
		var t: Dictionary = list[step[0]]
		var dest := dir.path_join(str(t.id).md5_text().substr(0, 16) + ".audio")
		var cached: String = pc.cache_dir("music").path_join(str(t.id).md5_text().substr(0, 16) + ".audio")
		if FileAccess.file_exists(cached) and not FileAccess.file_exists(dest):
			DirAccess.rename_absolute(cached, dest)
		pc.fetch(track_path(t.id), dest, func(ok: bool):
			step[1] = step[1] and ok
			step[0] += 1
			progress.call(step[0], list.size())
			self_ref.call(self_ref))
	one.call(one)


static func forget_album(album_key: String) -> void:
	var dir := album_dir(album_key)
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)
	var idx := kept_index()
	idx.erase(album_key)
	App.write_json(App.svc("pc").media_dir("music").path_join("albums.json"), idx)
