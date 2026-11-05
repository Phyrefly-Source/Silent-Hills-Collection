extends Node
## Jukebox: plays soundtrack tracks. Ordinary files (OGG, MP3, WAV) play
## directly; CRI ADX / AIX music is decoded on the fly into an audio generator,
## so a track starts immediately and nothing is converted to disk.
##
## A track is a Dictionary from the music library:
##   {id, title, album, game, kind: "native"|"adx"|"aix"|"ffmpeg", file, offset, size, seconds}

signal track_changed(track: Dictionary)
signal state_changed

const BUFFER_SEC := 0.75

var queue: Array = []
var index := -1
var current := {}
var shuffle := false
var repeat := "all"      # "off" | "all" | "one"
var playing := false
var preparing := false   # converting the current track with FFmpeg

var _player: AudioStreamPlayer
var _gen: AudioStreamGeneratorPlayback = null
var _decoders: Array = []
var _rate := 44100
var _ended := false
var _order: Array = []   # shuffled order of queue indices
var _load_token := 0


func _ready() -> void:
	_player = AudioStreamPlayer.new()
	_player.bus = "Master"
	add_child(_player)
	_player.finished.connect(_on_native_finished)
	set_process(false)
	App.settings_changed.connect(_apply_volume)
	_apply_volume()


func _apply_volume() -> void:
	_player.volume_db = linear_to_db(clamp(float(App.settings.get("volume", 0.8)), 0.0001, 1.0))


# ------------------------------------------------------------------ queue
func play_list(tracks: Array, start: int = 0) -> void:
	queue = tracks.duplicate()
	_order = range(queue.size())
	if shuffle:
		_order.shuffle()
		# Start with the chosen track, then the shuffled rest.
		_order.erase(start)
		_order.push_front(start)
	index = _order.find(start)
	_play_current()


func set_shuffle(on: bool) -> void:
	shuffle = on
	var cur: int = _order[index] if index >= 0 and index < _order.size() else 0
	_order = range(queue.size())
	if on:
		_order.shuffle()
		_order.erase(cur)
		_order.push_front(cur)
	index = _order.find(cur)
	state_changed.emit()


func next() -> void:
	if queue.is_empty():
		return
	index += 1
	if index >= _order.size():
		if repeat == "off":
			stop()
			return
		index = 0
	_play_current()


func prev() -> void:
	if queue.is_empty():
		return
	if position() > 3.0:
		seek(0.0)
		return
	index = max(0, index - 1)
	_play_current()


func _play_current() -> void:
	if index < 0 or index >= _order.size():
		return
	play_track(queue[_order[index]])


# ------------------------------------------------------------------ playback
func play_track(t: Dictionary) -> void:
	_stop_stream()
	preparing = false
	var saved: Array = App.svc("music").data().layers.get(t.get("id", ""), [])
	if not saved.is_empty():
		t = t.duplicate()
		t.layers = saved
	current = t
	_ended = false
	_load_token += 1
	var token := _load_token
	track_changed.emit(t)
	match t.get("kind", ""):
		"native":
			var s := _load_native(t.file)
			if s:
				_player.stream = s
				_player.play()
				playing = true
		"adx", "aix":
			# Reading and splitting the file happens off the main thread.
			App.run(func(): return _open_cri(t), func(decs):
				if token != _load_token:
					return
				if decs.is_empty():
					App.notify("Couldn't decode %s." % t.title, "error")
					return
				_start_generator(decs))
		"ffmpeg":
			preparing = not App.svc("music").is_ready(t)
			App.svc("music").convert_with_ffmpeg(t, func(path: String):
				if token != _load_token:
					return
				preparing = false
				if path == "":
					App.notify("This track needs FFmpeg to play. Set it in Settings.", "error")
					return
				var s := _load_native(path)
				if s:
					_player.stream = s
					_player.play()
					playing = true
					state_changed.emit()
				_prefetch_next())
		_:
			_prefetch_next()
	state_changed.emit()


## Converts the next queued track ahead of time, so FLAC albums play gaplessly-ish.
func _prefetch_next() -> void:
	if _order.is_empty():
		return
	var n := index + 1
	if n >= _order.size():
		if repeat != "all":
			return
		n = 0
	var nt: Dictionary = queue[_order[n]]
	if nt.get("kind", "") == "ffmpeg" and not App.svc("music").is_ready(nt):
		App.svc("music").convert_with_ffmpeg(nt, func(_p): pass)


static func _load_native(path: String) -> AudioStream:
	match path.get_extension().to_lower():
		"ogg":
			return AudioStreamOggVorbis.load_from_file(path)
		"mp3":
			return AudioStreamMP3.load_from_file(path)
		"wav":
			return AudioStreamWAV.load_from_file(path)
	return null


static func _open_cri(t: Dictionary) -> Array:
	var b := SoundContainers.read_range(t.file, int(t.get("offset", 0)), int(t.get("size", 0)))
	var out := []
	if t.kind == "aix":
		for layer in SoundContainers.aix_layers(b):
			var d := AdxStream.from_bytes(layer)
			if d.ok:
				out.append(d)
	else:
		var d := AdxStream.from_bytes(b)
		if d.ok:
			out.append(d)
	return out


func _start_generator(decs: Array) -> void:
	_decoders = decs
	_rate = decs[0].rate
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = _rate
	gen.buffer_length = BUFFER_SEC
	_player.stream = gen
	_player.play()
	_gen = _player.get_stream_playback()
	playing = true
	_start_decoder()
	set_process(true)
	state_changed.emit()


# Decoding runs on its own thread and hands finished chunks to _process, which
# only copies them into the audio buffer. Seven-layer AIX tracks cost a fair bit
# of CPU in GDScript, and none of it lands on the UI thread.
var _thread: Thread = null
var _mutex := Mutex.new()
var _chunks: Array = []
var _queued := 0
var _stop_decoder := false
var _decoded_all := false


func _start_decoder() -> void:
	_stop_thread()
	_chunks.clear()
	_queued = 0
	_decoded_all = false
	_stop_decoder = false
	_ended = false
	_thread = Thread.new()
	_thread.start(_decode_loop.bind(_decoders, current.get("layers", []).duplicate()))


func _stop_thread() -> void:
	if _thread:
		_stop_decoder = true
		_thread.wait_to_finish()
		_thread = null


func _decode_loop(decs: Array, layers: Array) -> void:
	var active := []
	for i in decs.size():
		if layers.is_empty() or layers.has(i):
			active.append(decs[i])
	if active.is_empty():
		active = [decs[0]]
	var gain := 1.0 / sqrt(active.size())
	while not _stop_decoder:
		_mutex.lock()
		var q := _queued
		_mutex.unlock()
		if q >= _rate * 2:
			OS.delay_msec(15)
			continue
		var mix: PackedVector2Array = active[0].read(4096)
		if active.size() > 1:
			for d in active.slice(1):
				var more: PackedVector2Array = d.read(4096)
				for i in mini(mix.size(), more.size()):
					mix[i] += more[i]
			for i in mix.size():
				mix[i] = (mix[i] * gain).clamp(Vector2(-1, -1), Vector2(1, 1))
		_mutex.lock()
		if not mix.is_empty():
			_chunks.append(mix)
			_queued += mix.size()
		if mix.size() < 4096:
			_decoded_all = true
		_mutex.unlock()
		if mix.size() < 4096:
			return


func _process(_dt: float) -> void:
	if _gen == null:
		set_process(false)
		return
	if _player.stream_paused:
		return
	_fill()
	if _ended and _gen.get_frames_available() >= int(_rate * BUFFER_SEC) - 512:
		# Everything has been heard.
		_on_native_finished()


func _fill() -> void:
	var room := _gen.get_frames_available()
	_mutex.lock()
	while room > 0 and not _chunks.is_empty():
		var c: PackedVector2Array = _chunks[0]
		if c.size() <= room:
			_gen.push_buffer(c)
			room -= c.size()
			_queued -= c.size()
			_chunks.pop_front()
		else:
			_gen.push_buffer(c.slice(0, room))
			_chunks[0] = c.slice(room)
			_queued -= room
			room = 0
	if _decoded_all and _chunks.is_empty():
		_ended = true
	_mutex.unlock()


func _on_native_finished() -> void:
	if repeat == "one":
		seek(0.0)
		if current.get("kind", "") == "native":
			_player.play()
		return
	next()


func toggle() -> void:
	if current.is_empty():
		return
	_player.stream_paused = not _player.stream_paused
	playing = not _player.stream_paused
	state_changed.emit()


func pause() -> void:
	if playing:
		toggle()


func stop() -> void:
	_stop_stream()
	current = {}
	state_changed.emit()


func _stop_stream() -> void:
	_stop_thread()
	set_process(false)
	_player.stop()
	_player.stream_paused = false
	_player.stream = null
	_gen = null
	_decoders = []
	playing = false


func duration() -> float:
	if not _decoders.is_empty():
		return _decoders[0].seconds()
	if _player.stream:
		return _player.stream.get_length()
	return float(current.get("seconds", 0.0))


func position() -> float:
	if not _decoders.is_empty() and _gen:
		_mutex.lock()
		var queued := _queued
		_mutex.unlock()
		var buffered := BUFFER_SEC - _gen.get_frames_available() / float(_rate)
		return maxf(0.0, _decoders[0].position_seconds() - buffered - queued / float(_rate))
	if _player.playing:
		return _player.get_playback_position()
	return 0.0


func seek(sec: float) -> void:
	if not _decoders.is_empty():
		_stop_thread()
		for d in _decoders:
			d.seek(int(sec * _rate))
		if _gen:
			# A fresh playback starts with an empty buffer (clearing a live one isn't allowed).
			var paused := _player.stream_paused
			_player.stop()
			_player.play()
			_player.stream_paused = paused
			_gen = _player.get_stream_playback()
		_start_decoder()
	elif _player.stream:
		_player.seek(sec)


func _exit_tree() -> void:
	_stop_thread()


## Plays only some of an AIX track's layers (the game fades them in and out).
func set_layers(layers: Array) -> void:
	current["layers"] = layers
	if current.has("id"):
		App.svc("music").data().layers[current.id] = layers
		App.mark_dirty("library")
	if not _decoders.is_empty():
		seek(position())
