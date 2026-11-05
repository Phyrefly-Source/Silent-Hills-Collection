extends Node
## The companion app's soundtracks, comics and films, served by the PC
## (part of the companion server, server.gd). Everything here needs a paired
## phone except /s/<ticket>/…, a short-lived link for opening a film in the
## phone's own video app.
##
##   GET  /api/music                       albums and their tracks
##   GET  /api/music/cover?album=<key>     an album's cover
##   GET  /api/music/track?id=<track>      a track as OGG/MP3 (converted once with FFmpeg when needed)
##   GET  /api/comics                      your comics, with your place in each
##   GET  /api/comics/cover?id=<comic>
##   GET  /api/comics/page?id=<comic>&n=<page>   a page, sized for a phone (WebP)
##   POST /api/comics/progress {id, page, total}
##   GET  /api/films                       the films, your place, and whether each is ready for the phone
##   POST /api/films/prepare {id}          converts a film for the phone (once; Theora/Vorbis in Ogg)
##   GET  /api/films/file?id=<film>        the converted film (Range)
##   GET  /api/films/subs?id=<film>        its subtitles (SRT), when there are any
##   POST /api/films/place {id, seconds}
##   GET  /api/films/ticket?id=<film>      -> {path} for /s/<ticket>/play (valid 8 hours)

var server   # server.gd

const PAGE_WIDTH := 1440
const FILM_WIDTH := 1280

var _tickets := {}   # ticket -> {id, until}
var _job := {}       # the film being converted: {id, procs:[pid], parts:[], progress_files, seconds, started}
var _queue: Array = []
var _status := {}    # film id -> {state, progress, error}
var _timer: Timer


func _ready() -> void:
	_timer = Timer.new()
	_timer.wait_time = 1.0
	_timer.autostart = true
	_timer.timeout.connect(_tick)
	add_child(_timer)


func route(c: Dictionary, req: Dictionary) -> bool:
	var path: String = req.path
	var q: Dictionary = req.query
	match path:
		"/api/music":
			server._send(c, 200, _music())
		"/api/music/cover":
			var cover := ""
			for a in App.svc("music").albums():
				if a.key == str(q.get("album", "")):
					cover = str(a.cover)
			if cover != "" and FileAccess.file_exists(cover):
				server._send_file(c, cover)
			else:
				server._send(c, 404, {"error": "no cover"})
		"/api/music/track":
			_track(c, req, str(q.get("id", "")))
		"/api/comics":
			server._send(c, 200, _comics())
		"/api/comics/cover":
			var it := _comic(str(q.get("id", "")))
			if it.is_empty():
				server._send(c, 404, {"error": "unknown comic"})
			else:
				App.svc("comics").cover(it, func(_tex):
					var p: String = App.svc("comics").cover_path(it)
					if FileAccess.file_exists(p):
						server._send_file(c, p)
					else:
						server._send(c, 404, {"error": "no cover"}))
		"/api/comics/page":
			_page(c, str(q.get("id", "")), int(q.get("n", "0")))
		"/api/comics/progress":
			var body = JSON.parse_string(req.body)
			var it := _comic(str(body.get("id", ""))) if body is Dictionary else {}
			if it.is_empty():
				server._send(c, 404, {"error": "unknown comic"})
			else:
				App.svc("comics").set_progress(it, int(body.get("page", 0)), int(body.get("total", 0)))
				server._send(c, 200, {"ok": true})
		"/api/films":
			server._send(c, 200, _films())
		"/api/films/prepare":
			var body = JSON.parse_string(req.body)
			var id := str(body.get("id", "")) if body is Dictionary else ""
			if App.svc("movies").path_of(id) == "":
				server._send(c, 404, {"error": "That film isn't on this PC."})
			elif App.svc("music").ffmpeg_path() == "":
				server._send(c, 503, {"error": "FFmpeg is missing from the launcher's tools folder."})
			else:
				prepare(id)
				server._send(c, 202, film_status(id))
		"/api/films/file":
			var id := str(q.get("id", ""))
			if film_status(id).state == "ready":
				server._stream_file(c, film_out(id), "video/ogg", req)
			else:
				server._send(c, 404, {"error": "not ready"})
		"/api/films/subs":
			var p := film_out(str(q.get("id", ""))).get_basename() + ".srt"
			if FileAccess.file_exists(p):
				server._write(c, 200, "text/plain; charset=utf-8", FileAccess.get_file_as_bytes(p))
			else:
				server._send(c, 404, {"error": "no subtitles"})
		"/api/films/place":
			var body = JSON.parse_string(req.body)
			if body is Dictionary and not App.entry(str(body.get("id", ""))).is_empty():
				App.svc("movies").set_place(str(body.id), float(body.get("seconds", 0)))
				server._send(c, 200, {"ok": true})
			else:
				server._send(c, 400, {"error": "bad film"})
		"/api/films/ticket":
			var id := str(q.get("id", ""))
			if App.svc("movies").path_of(id) == "":
				server._send(c, 404, {"error": "That film isn't on this PC."})
			else:
				var t := Crypto.new().generate_random_bytes(16).hex_encode()
				_tickets[t] = {"id": id, "until": Time.get_unix_time_from_system() + 8 * 3600}
				server._send(c, 200, {"path": "/s/%s/play" % t})
		_:
			return false
	return true


# ------------------------------------------------------------------ music
func _music() -> Dictionary:
	var out := []
	for a in App.svc("music").albums():
		var tracks := []
		for t in a.tracks:
			tracks.append({"id": t.id, "title": App.svc("music").title_of(t), "artist": str(t.get("artist", "")),
				"seconds": float(t.get("seconds", 0.0)), "group": str(t.get("group", ""))})
		var artist := ""
		for t in a.tracks:
			if str(t.get("artist", "")) != "":
				artist = str(t.artist)
				break
		out.append({"key": a.key, "title": a.title, "artist": artist, "kind": a.kind, "game": a.game,
			"cover": str(a.cover) != "", "tracks": tracks})
	return {"albums": out}


func _track(c: Dictionary, req: Dictionary, id: String) -> void:
	var lib = App.svc("music")
	var t: Dictionary = lib.track(id)
	if t.is_empty():
		server._send(c, 404, {"error": "unknown track"})
		return
	var ext := str(t.file).get_extension().to_lower()
	if t.get("kind", "") == "native" and ext in ["ogg", "mp3"] and int(t.get("offset", 0)) == 0:
		server._stream_file(c, t.file, "audio/ogg" if ext == "ogg" else "audio/mpeg", req)
		return
	var job := t.duplicate()
	job.kind = "ffmpeg"
	lib.convert_with_ffmpeg(job, func(p: String):
		if p == "":
			server._send(c, 503, {"error": "This track needs FFmpeg to play on the phone."})
		else:
			server._stream_file(c, p, "audio/ogg" if p.ends_with(".ogg") else "audio/wav", req))


# ------------------------------------------------------------------ comics
func _comic(id: String) -> Dictionary:
	for it in App.svc("comics").items:
		if it.id == id:
			return it
	return {}


func _comics() -> Dictionary:
	var lib = App.svc("comics")
	var out := []
	for s in lib.shelf():
		for it in s.copies:
			if lib.readable(it) != "":
				continue
			out.append({"id": it.id, "title": it.title, "series": s.entry.id, "series_title": s.entry.title,
				"year": int(s.entry.get("year", 0)), "issue": int(it.get("issue", 0)),
				"pages": lib.pages(it).size() if it.kind in ["cbz", "folder"] else lib.page_count(it),
				"page": lib.progress(it), "page_at": int(lib.data().get("progress_at", {}).get(it.id, 0)),
				"finished": lib.finished(it)})
	return {"comics": out}


## A page scaled to a phone's width, kept in the cache.
func _page(c: Dictionary, id: String, n: int) -> void:
	var it := _comic(id)
	if it.is_empty():
		server._send(c, 404, {"error": "unknown comic"})
		return
	var lib = App.svc("comics")
	var total: int = lib.pages(it).size()
	if n < 0 or n >= total:
		server._send(c, 404, {"error": "no such page"})
		return
	if lib.page_count(it) != total:
		var d: Dictionary = lib.data()
		if not d.has("pages"):
			d.pages = {}
		d.pages[it.id] = total
		App.mark_dirty("library")
	var out := App.cache_dir.path_join("companion-pages").path_join(id).path_join("%04d.webp" % n)
	if FileAccess.file_exists(out):
		server._send_file(c, out)
		return
	App.run(func():
		var img: Image = lib.page_image(it, n)
		if img == null:
			return ""
		if img.get_width() > PAGE_WIDTH:
			img.resize(PAGE_WIDTH, int(img.get_height() * float(PAGE_WIDTH) / img.get_width()), Image.INTERPOLATE_LANCZOS)
		DirAccess.make_dir_recursive_absolute(out.get_base_dir())
		return out if img.save_webp(out, false, 0.86) == OK else "",
	func(p: String):
		if p == "":
			server._send(c, 404, {"error": "unreadable page"})
		else:
			server._send_file(c, p))


# ------------------------------------------------------------------ films
func film_out(id: String) -> String:
	return App.cache_dir.path_join("companion-films").path_join(id + ".ogv")


func film_status(id: String) -> Dictionary:
	if FileAccess.file_exists(film_out(id)):
		var f := FileAccess.open(film_out(id), FileAccess.READ)
		return {"state": "ready", "progress": 1.0, "size": f.get_length() if f else 0}
	if _status.has(id):
		return _status[id]
	return {"state": "none", "progress": 0.0}


func _films() -> Dictionary:
	var out := []
	var mv = App.svc("movies")
	for f in App.films:
		var p: String = mv.path_of(f.id)
		var st := film_status(f.id)
		out.append({"id": f.id, "title": f.title, "year": int(f.get("year", 0)), "director": str(f.get("director", "")),
			"blurb": str(f.get("blurb", "")), "accent": str(f.get("accent", "")), "have": p != "", "place": mv.place(f.id), "place_at": mv.place_at(f.id),
			"original": p.get_file(), "prepare": st,
			"subs": FileAccess.file_exists(film_out(f.id).get_basename() + ".srt")})
	return {"films": out}


## Queues a film for converting (one film at a time, in several pieces at once).
func prepare(id: String) -> void:
	if film_status(id).state in ["ready", "working", "queued"]:
		return
	_status[id] = {"state": "queued", "progress": 0.0}
	_queue.append(id)
	_tick()


func _tick() -> void:
	if _job.is_empty():
		if _queue.is_empty():
			return
		_start(_queue.pop_front())
		return
	if _job.get("stage", "") == "probe":
		return
	var running := 0
	var done_s := 0.0
	for i in _job.procs.size():
		var pid: int = _job.procs[i]
		if pid > 0 and OS.is_process_running(pid):
			running += 1
		done_s += _progress_of(_job.progress_files[i], _job.lengths[i])
	var st: Dictionary = _status[_job.id]
	if _job.stage == "encode":
		st.progress = clampf(done_s / maxf(1.0, _job.seconds), 0.0, 0.99)
		if running == 0:
			for part in _job.parts:
				if not FileAccess.file_exists(part):
					_fail("A piece of the conversion failed.")
					return
			_join()
	elif _job.stage == "join" and running == 0:
		var out := film_out(_job.id)
		if FileAccess.file_exists(_job.joined):
			DirAccess.rename_absolute(_job.joined, out)
			for part in _job.parts + _job.progress_files + [_job.list]:
				DirAccess.remove_absolute(part)
			_status.erase(_job.id)
			App.notify("%s is ready for the phone." % App.entry(_job.id).get("title", "The film"), "ok")
			_job = {}
		else:
			_fail("Joining the pieces failed.")


static func _progress_of(file: String, length: float) -> float:
	if not FileAccess.file_exists(file):
		return 0.0
	var txt := FileAccess.get_file_as_string(file)
	var k := txt.rfind("out_time_us=")
	if k < 0:
		return 0.0
	var v := txt.substr(k + 12, 20).split("\n")[0].to_int()
	if txt.ends_with("progress=end\n"):
		return length
	return clampf(v / 1000000.0, 0.0, length)


func _fail(msg: String) -> void:
	for pid in _job.get("procs", []):
		if pid > 0 and OS.is_process_running(pid):
			OS.kill(pid)
	_status[_job.id] = {"state": "failed", "progress": 0.0, "error": msg}
	_job = {}


func _start(id: String) -> void:
	var src: String = App.svc("movies").path_of(id)
	var ff: String = App.svc("music").ffmpeg_path()
	_status[id] = {"state": "working", "progress": 0.0}
	_job = {"id": id, "stage": "probe", "procs": [], "progress_files": [], "parts": [], "lengths": []}
	var dir := film_out(id).get_base_dir()
	DirAccess.make_dir_recursive_absolute(dir)
	App.run(func():
		# Length from FFmpeg's own report.
		var out := []
		OS.execute(ff, ["-hide_banner", "-i", src], out, true, false)
		var m := RegEx.create_from_string("Duration: (\\d+):(\\d+):(\\d+(?:\\.\\d+)?)").search("\n".join(out))
		var secs := (m.get_string(1).to_int() * 3600 + m.get_string(2).to_int() * 60 + m.get_string(3).to_float()) if m else 0.0
		# Subtitles: a file beside the film, else the film's first text track.
		var srt := film_out(id).get_basename() + ".srt"
		var beside: Array = Subtitles.beside(src)
		if not beside.is_empty():
			DirAccess.copy_absolute(beside[0].path, srt)
		else:
			OS.execute(ff, ["-nostdin", "-v", "error", "-y", "-i", src, "-map", "0:s:0", "-c:s", "srt", srt], [], false, false)
			if FileAccess.file_exists(srt) and FileAccess.open(srt, FileAccess.READ).get_length() < 16:
				DirAccess.remove_absolute(srt)
		return secs,
	func(secs: float):
		if _job.is_empty() or _job.id != id:
			return
		if secs <= 0.0:
			_fail("FFmpeg couldn't read the film.")
			return
		_job.seconds = secs
		_job.stage = "encode"
		var n := clampi(OS.get_processor_count() / 2, 1, 8)
		var each := ceilf(secs / n)
		for i in n:
			var part := dir.path_join("%s.part%d.ogv" % [id, i])
			var prog := dir.path_join("%s.part%d.progress" % [id, i])
			DirAccess.remove_absolute(part)
			DirAccess.remove_absolute(prog)
			var length := minf(each, secs - i * each)
			var args := ["-nostdin", "-v", "error", "-y", "-progress", prog, "-ss", str(i * each), "-t", str(length), "-i", src,
				"-map", "0:v:0", "-map", "0:a:0?", "-sn", "-vf", "scale='min(%d,iw)':-2" % FILM_WIDTH,
				"-c:v", "libtheora", "-q:v", "5", "-c:a", "libvorbis", "-q:a", "4", "-ac", "2", "-ar", "48000", part]
			_job.procs.append(OS.create_process(ff, args))
			_job.parts.append(part)
			_job.progress_files.append(prog)
			_job.lengths.append(length))


func _join() -> void:
	var ff: String = App.svc("music").ffmpeg_path()
	var dir := film_out(_job.id).get_base_dir()
	var list := dir.path_join(_job.id + ".parts.txt")
	var lines := PackedStringArray()
	for p in _job.parts:
		lines.append("file '%s'" % str(p).replace("\\", "/").replace("'", "'\\''"))
	var f := FileAccess.open(list, FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	_job.list = list
	_job.joined = dir.path_join(_job.id + ".joined.ogv")
	DirAccess.remove_absolute(_job.joined)
	_job.stage = "join"
	_job.procs = [OS.create_process(ff, ["-nostdin", "-v", "error", "-y", "-f", "concat", "-safe", "0", "-i", list, "-c", "copy", _job.joined])]
	_job.progress_files = [""]
	_job.lengths = [0.0]


# ------------------------------------------------------------------ the phone's own video app
func ticket_route(c: Dictionary, req: Dictionary) -> void:
	var bits: PackedStringArray = str(req.path).split("/", false)   # ["s", ticket, what]
	var t: Dictionary = _tickets.get(bits[1] if bits.size() > 1 else "", {})
	if t.is_empty() or Time.get_unix_time_from_system() > float(t.until):
		server._write(c, 403, "text/plain", "This link has expired. Open the film again from the Silent Hills app.".to_utf8_buffer())
		return
	var file: String = App.svc("movies").path_of(t.id)
	var ext := file.get_extension().to_lower()
	var mime: String = {"mp4": "video/mp4", "m4v": "video/mp4", "mkv": "video/x-matroska", "webm": "video/webm",
		"avi": "video/x-msvideo", "mov": "video/quicktime", "ts": "video/mp2t", "m2ts": "video/mp2t"}.get(ext, "video/*")
	var what := bits[2] if bits.size() > 2 else "play"
	if what.begins_with("video"):
		server._stream_file(c, file, mime, req)
		return
	var title := str(App.entry(t.id).get("title", "Film")).xml_escape()
	var host := str(req.headers.get("host", ""))
	var video := "/s/%s/video.%s" % [bits[1], ext]
	var intent := "intent://%s%s#Intent;scheme=http;type=%s;end" % [host, video, mime]
	var html := """<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>%s</title><style>body{margin:0;background:#070708;color:#e8e4dc;font-family:sans-serif}
video{width:100%%;max-height:70vh;background:#000}main{padding:20px}a.b{display:block;margin:14px 0;padding:16px;text-align:center;
background:#e8e4dc;color:#070708;border-radius:6px;text-decoration:none;font-weight:600}p{color:#9a968e;font-size:14px;line-height:1.5}</style></head>
<body><video src="%s" controls playsinline></video><main><h2>%s</h2>
<a class="b" href="%s">Open in a video app</a>
<p>Streaming from your PC. If the player above can't play this file, "Open in a video app" hands it to Samsung Video, VLC or another player on your phone.
Your place isn't remembered here; for that, use Play on phone in the Silent Hills app.</p></main></body></html>""" % [title, video, title, intent]
	server._write(c, 200, "text/html; charset=utf-8", html.to_utf8_buffer())
