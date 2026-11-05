extends Node
## Net: a small HTTP client with a request queue, a few parallel requests and a
## disk cache, so art, RetroAchievements and badge icons never hold up the UI.

const MAX_PARALLEL := 4
const UA := "SilentHillsLauncher/0.1 (+godot)"

var _queue: Array = []
var _active := 0
var _pool: Array[HTTPRequest] = []
var _inflight := {}   # cache path -> [callbacks]
## Tests only: fixture(url) returns a reply (JSON data, or a local file path for
## downloads) to use instead of the network, or null to go online as usual.
var fixture := Callable()


func _ready() -> void:
	for i in MAX_PARALLEL:
		var r := HTTPRequest.new()
		r.use_threads = true
		r.timeout = 25
		add_child(r)
		_pool.append(r)


func _cache_path(url: String, ext: String) -> String:
	return App.cache_dir.path_join("http").path_join(url.md5_text() + ext)


## Calls cb(data) with parsed JSON, or cb(null) on failure. Cached for ttl seconds.
func get_json(url: String, headers: PackedStringArray, ttl: int, cb: Callable) -> void:
	if fixture.is_valid():
		var v = fixture.call(url)
		if v != null:
			(func(): if cb.is_valid(): cb.call(v)).call_deferred()
			return
	var path := _cache_path(url + "|" + ",".join(headers), ".json")
	if ttl > 0 and _fresh(path, ttl):
		cb.call(JSON.parse_string(FileAccess.get_file_as_string(path)))
		return
	_enqueue({"url": url, "headers": headers, "path": path, "kind": "json", "cb": cb, "stale_ok": true})


## Calls cb(text) with a page's text (HTML), or cb("") on failure. Cached for
## ttl seconds; when the site can't be reached the last copy is used.
func get_text(url: String, ttl: int, cb: Callable, headers: PackedStringArray = PackedStringArray()) -> void:
	if fixture.is_valid():
		var v = fixture.call(url)
		if v != null:
			(func(): if cb.is_valid(): cb.call(v)).call_deferred()
			return
	var path := _cache_path(url, ".html")
	if _fresh(path, ttl):
		cb.call(FileAccess.get_file_as_string(path))
		return
	_enqueue({"url": url, "headers": headers, "path": path, "kind": "text", "cb": cb})


## Downloads url to a cached file and calls cb(local_path) or cb("") on failure.
func get_file(url: String, cb: Callable, ext: String = "", headers: PackedStringArray = PackedStringArray()) -> void:
	if ext == "":
		# Wiki images end in ".../Name.jpg/revision/latest?cb=…".
		var base := url.split("/revision/")[0].split("?")[0]
		ext = "." + base.get_file().get_extension().to_lower()
		if ext.length() > 6 or ext == ".":
			ext = ".bin"
	if fixture.is_valid():
		var v = fixture.call(url)
		if v != null:
			(func(): if cb.is_valid(): cb.call(v)).call_deferred()
			return
	var path := _cache_path(url, ext)
	if FileAccess.file_exists(path):
		cb.call(path)
		return
	_enqueue({"url": url, "headers": headers, "path": path, "kind": "file", "cb": cb})


func _fresh(path: String, ttl: int) -> bool:
	if not FileAccess.file_exists(path):
		return false
	return Time.get_unix_time_from_system() - FileAccess.get_modified_time(path) < ttl


func _enqueue(job: Dictionary) -> void:
	if _inflight.has(job.path):
		_inflight[job.path].append(job.cb)
		return
	_inflight[job.path] = [job.cb]
	_queue.append(job)
	_pump()


func _pump() -> void:
	while _active < MAX_PARALLEL and not _queue.is_empty():
		var job: Dictionary = _queue.pop_front()
		var req: HTTPRequest = null
		for r in _pool:
			if not r.has_meta("busy"):
				req = r
				break
		if req == null:
			_queue.push_front(job)
			return
		req.set_meta("busy", true)
		_active += 1
		DirAccess.make_dir_recursive_absolute(job.path.get_base_dir())
		req.download_file = (job.path + ".part") if job.kind == "file" else ""
		var headers := PackedStringArray()
		if not Array(job.headers).any(func(h): return str(h).to_lower().begins_with("user-agent:")):
			headers.append("User-Agent: " + UA)
		headers.append_array(job.headers)
		var err := req.request(job.url, headers)
		if err != OK:
			_finish(req, job, null)
			continue
		req.request_completed.connect(_on_done.bind(req, job), CONNECT_ONE_SHOT)


func _on_done(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray, req: HTTPRequest, job: Dictionary) -> void:
	var ok := result == HTTPRequest.RESULT_SUCCESS and code >= 200 and code < 300
	if job.kind == "file":
		if ok:
			if FileAccess.file_exists(job.path):
				DirAccess.remove_absolute(job.path)
			DirAccess.rename_absolute(job.path + ".part", job.path)
			_finish(req, job, job.path)
		else:
			DirAccess.remove_absolute(job.path + ".part")
			_finish(req, job, "")
		return
	if job.kind == "text":
		# A picture or other binary file is never a page (and must not be cached as one).
		if ok and (body.size() > 4 and (body[0] == 0xFF and body[1] == 0xD8 or body[0] == 0x89 and body[1] == 0x50 or body.slice(0, 512).has(0))):
			ok = false
		var text := body.get_string_from_utf8() if ok else ""
		if ok:
			var tf := FileAccess.open(job.path, FileAccess.WRITE)
			if tf:
				tf.store_buffer(body)
				tf.close()
		elif FileAccess.file_exists(job.path):
			text = FileAccess.get_file_as_string(job.path)
		_finish(req, job, text)
		return
	var data = JSON.parse_string(body.get_string_from_utf8()) if ok else null
	if data != null:
		var f := FileAccess.open(job.path, FileAccess.WRITE)
		if f:
			f.store_buffer(body)
			f.close()
	elif job.get("stale_ok") and FileAccess.file_exists(job.path):
		# Offline or the service failed: fall back to the last good answer.
		data = JSON.parse_string(FileAccess.get_file_as_string(job.path))
	_finish(req, job, data)


func _finish(req: HTTPRequest, job: Dictionary, value) -> void:
	req.remove_meta("busy")
	_active -= 1
	var cbs: Array = _inflight.get(job.path, [])
	_inflight.erase(job.path)
	for cb in cbs:
		if cb.is_valid():
			cb.call(value)
	_pump()
