class_name AVStream
extends RefCounted
## Plays a film through the bundled FFmpeg: one FFmpeg process decodes the
## picture (scaled, raw YUV 4:2:0 on a pipe) and another the sound (stereo
## 48 kHz float on a pipe). Two reader threads keep a few frames and a couple
## of seconds of sound ready; the player shows each frame when the sound clock
## reaches it. Seeking starts both processes again at the new time.
## Works with whatever FFmpeg can decode (H.264, HEVC 10-bit, AV1, …), using the
## GPU decoder when one is available.

const RATE := 48000
const MAX_FRAMES := 6
const MAX_AUDIO_SEC := 2.0

var path := ""
var info := {}             # from probe()
var width := 0             # decoded picture size (even numbers)
var height := 0
var start_time := 0.0      # where this run of the processes began
var ended_video := false
var ended_audio := false

var _ff := ""
var _vproc := {}
var _aproc := {}
var _vthread: Thread
var _athread: Thread
var _mutex := Mutex.new()
var _frames: Array = []    # [[pts, PackedByteArray]]
var _audio: Array = []     # PackedByteArray chunks of f32 stereo
var _audio_bytes := 0
var _stop := false


# ------------------------------------------------------------------ probing
## Reads a film's streams from FFmpeg's description of the file:
## {duration, width, height, fps, audio: [{n, lang, title, channels}], subs: [{n, lang, title, codec}]}
static func probe(ff: String, file: String) -> Dictionary:
	var out := []
	OS.execute(ff, ["-hide_banner", "-nostdin", "-i", file], out, true)
	return parse_probe(out[0] if not out.is_empty() else "")


static func parse_probe(text: String) -> Dictionary:
	var res := {"duration": 0.0, "width": 0, "height": 0, "fps": 24.0, "audio": [], "subs": []}
	var d := RegEx.create_from_string("Duration: (\\d+):(\\d+):(\\d+(?:\\.\\d+)?)").search(text)
	if d:
		res.duration = d.get_string(1).to_int() * 3600 + d.get_string(2).to_int() * 60 + d.get_string(3).to_float()
	var lines := text.split("\n")
	var cur := {}
	var re_stream := RegEx.create_from_string("Stream #\\d+:\\d+(?:\\[[^\\]]*\\])?(?:\\(([a-z]{2,3})\\))?.*?: (Video|Audio|Subtitle): ([a-z0-9_]+)(.*)")
	var re_title := RegEx.create_from_string("^\\s+title\\s*:\\s*(.+)$")
	for line in lines:
		var m := re_stream.search(line)
		if m:
			var kind := m.get_string(2)
			var lang := m.get_string(1)
			var rest := m.get_string(4)
			cur = {}
			match kind:
				"Video":
					if res.width == 0 and not rest.contains("attached pic"):
						var s := RegEx.create_from_string(", (\\d{2,5})x(\\d{2,5})").search(rest)
						if s:
							res.width = s.get_string(1).to_int()
							res.height = s.get_string(2).to_int()
						var f := RegEx.create_from_string("([\\d.]+) fps").search(rest)
						if f:
							res.fps = f.get_string(1).to_float()
				"Audio":
					var ch := 2
					if rest.contains("5.1"):
						ch = 6
					elif rest.contains("7.1"):
						ch = 8
					elif rest.contains("mono"):
						ch = 1
					cur = {"n": res.audio.size(), "lang": lang, "title": "", "channels": ch, "codec": m.get_string(3)}
					res.audio.append(cur)
				"Subtitle":
					cur = {"n": res.subs.size(), "lang": lang, "title": "", "codec": m.get_string(3)}
					res.subs.append(cur)
			continue
		var t := re_title.search(line)
		if t and not cur.is_empty():
			cur.title = t.get_string(1).strip_edges()
	return res


## Text subtitles can be shown; picture-based ones (Blu-ray PGS, DVD) can't.
static func is_text_sub(codec: String) -> bool:
	return codec in ["subrip", "srt", "ass", "ssa", "mov_text", "webvtt", "text"]


# ------------------------------------------------------------------ running
func _init(ffmpeg: String, file: String, probed: Dictionary, max_width: int = 1920) -> void:
	_ff = ffmpeg
	path = file
	info = probed
	var sw: int = maxi(2, int(info.get("width", 1920)))
	var sh: int = maxi(2, int(info.get("height", 1080)))
	width = mini(sw, max_width)
	height = int(round(float(sh) * width / sw))
	width -= width % 2
	height -= height % 2


func frame_bytes() -> int:
	return width * height * 3 / 2


func fps() -> float:
	return maxf(1.0, float(info.get("fps", 24.0)))


## Starts decoding at `t` seconds with the given audio track (-1: none).
func start(t: float, audio_track: int) -> void:
	stop()
	_stop = false
	start_time = maxf(0.0, t)
	ended_video = false
	ended_audio = audio_track < 0 or (info.get("audio", []) as Array).is_empty()
	_frames.clear()
	_audio.clear()
	_audio_bytes = 0
	var ss := "%.3f" % start_time
	var vargs := ["-nostdin", "-v", "error", "-hwaccel", "auto", "-ss", ss, "-i", path, "-map", "0:v:0", "-an", "-sn",
		"-vf", "scale=%d:%d:flags=bicubic,format=yuv420p" % [width, height],
		"-r", "%.6f" % fps(), "-f", "rawvideo", "-pix_fmt", "yuv420p", "-"]
	_vproc = OS.execute_with_pipe(_ff, vargs)
	if not _vproc.is_empty():
		_vthread = Thread.new()
		_vthread.start(_read_video.bind(_vproc.stdio))
	else:
		ended_video = true
	if not ended_audio:
		var aargs := ["-nostdin", "-v", "error", "-ss", ss, "-i", path, "-map", "0:a:%d" % audio_track, "-vn", "-sn",
			"-ac", "2", "-ar", str(RATE), "-f", "f32le", "-"]
		_aproc = OS.execute_with_pipe(_ff, aargs)
		if not _aproc.is_empty():
			_athread = Thread.new()
			_athread.start(_read_audio.bind(_aproc.stdio))
		else:
			ended_audio = true


func stop() -> void:
	_stop = true
	for p in [_vproc, _aproc]:
		if not p.is_empty():
			OS.kill(int(p.pid))
	for t in [_vthread, _athread]:
		if t and t.is_started():
			t.wait_to_finish()
	_vthread = null
	_athread = null
	_vproc = {}
	_aproc = {}


func _read_video(pipe: FileAccess) -> void:
	var size := frame_bytes()
	var n := 0
	while not _stop:
		_mutex.lock()
		var full := _frames.size() >= MAX_FRAMES
		_mutex.unlock()
		if full:
			OS.delay_msec(4)
			continue
		var buf := pipe.get_buffer(size)
		while buf.size() < size and not _stop:
			var more := pipe.get_buffer(size - buf.size())
			if more.is_empty():
				break
			buf.append_array(more)
		if buf.size() < size:
			break
		_mutex.lock()
		_frames.append([start_time + n / fps(), buf])
		_mutex.unlock()
		n += 1
	ended_video = true


func _read_audio(pipe: FileAccess) -> void:
	var chunk := 4096 * 8   # 4096 stereo frames of 32-bit floats
	var cap := int(MAX_AUDIO_SEC * RATE * 8)
	while not _stop:
		_mutex.lock()
		var full := _audio_bytes >= cap
		_mutex.unlock()
		if full:
			OS.delay_msec(10)
			continue
		var buf := pipe.get_buffer(chunk)
		if buf.is_empty():
			break
		_mutex.lock()
		_audio.append(buf)
		_audio_bytes += buf.size()
		_mutex.unlock()
	ended_audio = true


## Takes up to `max_frames` stereo frames of sound, as [l, r, l, r, …] floats.
func take_audio(max_frames: int) -> PackedFloat32Array:
	var want := max_frames * 8
	var got := PackedByteArray()
	_mutex.lock()
	while not _audio.is_empty() and got.size() < want:
		var c: PackedByteArray = _audio[0]
		var need := want - got.size()
		if c.size() <= need:
			got.append_array(c)
			_audio.pop_front()
		else:
			got.append_array(c.slice(0, need))
			_audio[0] = c.slice(need)
	_audio_bytes -= got.size()
	_mutex.unlock()
	got.resize(got.size() - got.size() % 8)
	return got.to_float32_array()


func audio_ready_frames() -> int:
	_mutex.lock()
	var n := _audio_bytes / 8
	_mutex.unlock()
	return n


## The newest decoded frame due at `clock`, dropping older ones; [] if none due.
func take_frame(clock: float) -> Array:
	var due := []
	_mutex.lock()
	while not _frames.is_empty() and float(_frames[0][0]) <= clock:
		due = _frames.pop_front()
	_mutex.unlock()
	return due


func frames_ready() -> int:
	_mutex.lock()
	var n := _frames.size()
	_mutex.unlock()
	return n
