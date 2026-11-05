extends Node
## The companion app's side of the link: finds the Silent Hills PC on the
## home network, pairs with it once (6-digit code shown on the PC), and reads
## its data. Answers are kept, so everything still shows when away from home
## and refreshes the next time the PC is reachable.
##
## Settings: "companion_pc" = {host, port, name, token}.

signal status_changed

const PORT := 47630
## This app's own version. tools/build_companion.sh reads these for the APK
## and for the version.json the launcher serves.
const APP_VERSION := "1.2"
const APP_CODE := 5

signal update_progress(done: int, total: int)

var online := false        # the PC answered recently
var last_sync := 0         # unix time of the last good answer
var _http_pool: Array[HTTPRequest] = []


func pc() -> Dictionary:
	return App.settings.get("companion_pc", {})


func paired() -> bool:
	return str(pc().get("token", "")) != ""


func base_url() -> String:
	var p := pc()
	return "http://%s:%d" % [p.get("host", ""), int(p.get("port", PORT))]


func auth() -> PackedStringArray:
	return PackedStringArray(["Authorization: Bearer " + str(pc().get("token", "")),
		"X-Companion-Version: %d" % APP_CODE, "X-Companion-Version-Name: " + APP_VERSION])


func forget() -> void:
	App.set_setting("companion_pc", {})
	online = false
	status_changed.emit()


# ------------------------------------------------------------------ finding the PC
## Looks for Silent Hills PCs for `seconds`: cb([{name, host, port}]).
## extra_hosts are asked directly too (a typed-in address, or 127.0.0.1 in tests).
func discover(cb: Callable, seconds: float = 2.0, extra_hosts: Array = []) -> void:
	var udp := PacketPeerUDP.new()
	udp.set_broadcast_enabled(true)
	if udp.bind(0) != OK:
		cb.call([])
		return
	var targets := ["255.255.255.255"] + extra_hosts
	# Also each local subnet's broadcast address (some routers drop 255.255.255.255).
	for a in IP.get_local_addresses():
		if a.count(".") == 3 and not a.begins_with("127.") and not a.begins_with("169.254."):
			var parts := a.split(".")
			targets.append("%s.%s.%s.255" % [parts[0], parts[1], parts[2]])
	for t in targets:
		udp.set_dest_address(t, PORT + 1)
		udp.put_packet("SILENTHILLS?".to_utf8_buffer())
	var found := {}
	var deadline := Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < deadline:
		await get_tree().create_timer(0.1).timeout
		while udp.get_available_packet_count() > 0:
			var pkt := udp.get_packet().get_string_from_utf8()
			var ip := udp.get_packet_ip()
			var data = JSON.parse_string(pkt)
			if data is Dictionary and data.get("app", "") == "silenthills":
				found[ip] = {"name": str(data.get("name", ip)), "host": ip, "port": int(data.get("port", PORT))}
	udp.close()
	cb.call(found.values())


# ------------------------------------------------------------------ requests
func _http() -> HTTPRequest:
	for r in _http_pool:
		if not r.has_meta("busy"):
			return r
	var r := HTTPRequest.new()
	r.timeout = 8
	add_child(r)
	_http_pool.append(r)
	return r


## A request to a PC: cb(code, data) — data is parsed JSON (or null).
func call_pc(host: String, port: int, method: int, path: String, body, cb: Callable, token: String = "") -> void:
	var r := _http()
	r.set_meta("busy", true)
	var headers := PackedStringArray(["Content-Type: application/json"])
	if token != "":
		headers.append("Authorization: Bearer " + token)
		headers.append("X-Companion-Version: %d" % APP_CODE)
		headers.append("X-Companion-Version-Name: " + APP_VERSION)
	r.request_completed.connect(func(result, code, _h, bytes):
		r.remove_meta("busy")
		var data = JSON.parse_string(bytes.get_string_from_utf8()) if result == HTTPRequest.RESULT_SUCCESS else null
		cb.call(code if result == HTTPRequest.RESULT_SUCCESS else 0, data), CONNECT_ONE_SHOT)
	var err := r.request("http://%s:%d%s" % [host, port, path], headers, method, JSON.stringify(body) if body != null else "")
	if err != OK:
		r.remove_meta("busy")
		cb.call(0, null)


## Asks the PC to show a pairing code. cb(ok, message).
func pair_start(host: String, port: int, cb: Callable) -> void:
	call_pc(host, port, HTTPClient.METHOD_POST, "/api/pair/start", {"device": device_name()}, func(code, data):
		if code == 200:
			cb.call(true, "")
		elif code == 0:
			cb.call(false, "Couldn't reach that PC. Check that Silent Hills is open on it, with the companion turned on in Settings, and that both are on the same Wi-Fi.")
		else:
			cb.call(false, str(data.get("error", "The PC said no.")) if data is Dictionary else "The PC said no."))


## Sends the code the PC shows. cb(ok, message).
func pair_finish(host: String, port: int, pc_name: String, code: String, cb: Callable) -> void:
	call_pc(host, port, HTTPClient.METHOD_POST, "/api/pair/finish", {"device": device_name(), "code": code.strip_edges()}, func(status, data):
		if status == 200 and data is Dictionary and data.has("token"):
			App.set_setting("companion_pc", {"host": host, "port": port, "name": str(data.get("name", pc_name)), "token": data.token})
			online = true
			status_changed.emit()
			cb.call(true, "")
		else:
			cb.call(false, str(data.get("error", "That didn't work.")) if data is Dictionary else "Couldn't reach the PC."))


static func device_name() -> String:
	var m := OS.get_model_name()
	if m == "" or m == "GenericDevice":
		m = OS.get_name()
	return m


## Reads JSON from the paired PC: cb(data or null). Uses the last good answer
## when the PC can't be reached (away from home), and says so in `online`.
func get_json(path: String, cb: Callable, max_age: int = 0) -> void:
	if not paired():
		cb.call(null)
		return
	var url := base_url() + path
	var probe := [false]
	# Net keeps the last good answer and falls back to it when offline.
	Net.get_json(url, auth(), max_age, func(data):
		cb.call(data))
	# Separately note whether the PC is there right now (cheap hello).
	call_pc(str(pc().host), int(pc().get("port", PORT)), HTTPClient.METHOD_GET, "/api/hello", null, func(code, data):
		var was := online
		online = code == 200 and data is Dictionary and bool(data.get("paired", false))
		if online:
			last_sync = int(Time.get_unix_time_from_system())
			App.settings.companion_last_sync = last_sync
		if was != online or online:
			status_changed.emit(), str(pc().get("token", "")))


## A picture from the PC (a game's background): cb(local path or "").
func get_picture(path: String, cb: Callable) -> void:
	if not paired():
		cb.call("")
		return
	Net.get_file(base_url() + path, cb, ".img", auth())


# ------------------------------------------------------------------ updates
## Asks the PC which companion app it carries: cb({version, code, size}) when
## it's newer than this one, else cb({}).
func check_update(cb: Callable) -> void:
	if not paired():
		cb.call({})
		return
	var p := pc()
	call_pc(str(p.host), int(p.get("port", PORT)), HTTPClient.METHOD_GET, "/api/app", null, func(code, data):
		if code == 200 and data is Dictionary and int(data.get("code", 0)) > APP_CODE:
			cb.call(data)
		else:
			cb.call({}), str(p.get("token", "")))


func update_path() -> String:
	return OS.get_user_data_dir().path_join("update/SilentHillsCompanion.apk")


var _dl: HTTPRequest


## Downloads the PC's APK (update_progress while it comes), then cb(ok, message).
func download_update(sha256: String, cb: Callable) -> void:
	if is_instance_valid(_dl):
		cb.call(false, "Already downloading.")
		return
	DirAccess.make_dir_recursive_absolute(update_path().get_base_dir())
	_dl = HTTPRequest.new()
	_dl.download_file = update_path()
	_dl.timeout = 300
	_dl.download_chunk_size = 262144
	add_child(_dl)
	var t := Timer.new()
	t.wait_time = 0.25
	t.autostart = true
	_dl.add_child(t)
	t.timeout.connect(func(): update_progress.emit(_dl.get_downloaded_bytes(), _dl.get_body_size()))
	_dl.request_completed.connect(func(result, code, _h, _b):
		_dl.queue_free()
		if result == HTTPRequest.RESULT_SUCCESS and code == 200:
			if sha256 != "" and FileAccess.get_sha256(update_path()) != sha256:
				DirAccess.remove_absolute(update_path())
				cb.call(false, "The download came through damaged. Try again.")
				return
			cb.call(true, "")
		else:
			DirAccess.remove_absolute(update_path())
			cb.call(false, "The download didn't finish (%s). Try again on the same Wi-Fi as your PC." % (code if code else result)))
	var err := _dl.request(base_url() + "/api/app/apk", auth())
	if err != OK:
		_dl.queue_free()
		cb.call(false, "Couldn't start the download.")


## Hands the downloaded APK to Android's installer. Android asks once to let
## Silent Hills install apps; after that it shows the usual "Update" screen.
func install_update() -> String:
	if not FileAccess.file_exists(update_path()):
		return "The update isn't downloaded."
	if OS.has_feature("android"):
		OS.request_permission("android.permission.REQUEST_INSTALL_PACKAGES")
	var err := OS.shell_open(update_path())
	return "" if err == OK else "Android wouldn't open the installer (error %d)." % err


# ------------------------------------------------------------------ media
## Sends JSON to the paired PC: cb(ok). Changes made away from home (your place
## in a comic or film) wait in "companion_outbox" and go the next time.
func post_json(path: String, body: Dictionary, cb: Callable = Callable(), queue_if_offline: bool = false) -> void:
	if not paired():
		if cb.is_valid():
			cb.call(false)
		return
	var p := pc()
	call_pc(str(p.host), int(p.get("port", PORT)), HTTPClient.METHOD_POST, path, body, func(code, _d):
		var ok: bool = code >= 200 and code < 300
		if not ok and code == 0 and queue_if_offline:
			var box: Dictionary = App.settings.get("companion_outbox", {})
			box[path + "|" + str(body.get("id", ""))] = {"path": path, "body": body}
			App.set_setting("companion_outbox", box)
		if cb.is_valid():
			cb.call(ok), str(p.get("token", "")))


## Sends what waited while the PC was out of reach.
func flush_outbox() -> void:
	var box: Dictionary = App.settings.get("companion_outbox", {})
	if box.is_empty() or not paired():
		return
	App.set_setting("companion_outbox", {})
	for k in box:
		post_json(box[k].path, box[k].body, Callable(), true)


func media_dir(kind: String) -> String:
	var d := OS.get_user_data_dir().path_join("offline").path_join(kind)
	DirAccess.make_dir_recursive_absolute(d)
	return d


func cache_dir(kind: String) -> String:
	var d := OS.get_user_data_dir().path_join("cache").path_join(kind)
	DirAccess.make_dir_recursive_absolute(d)
	return d


var _fetching := {}   # dest -> [callbacks]


## Downloads one file from the PC to dest (once; joins a download already
## running). cb(ok). A file already at dest counts.
func fetch(path: String, dest: String, cb: Callable) -> void:
	if FileAccess.file_exists(dest):
		cb.call(true)
		return
	if _fetching.has(dest):
		_fetching[dest].append(cb)
		return
	if not paired():
		cb.call(false)
		return
	_fetching[dest] = [cb]
	DirAccess.make_dir_recursive_absolute(dest.get_base_dir())
	var part := dest + ".part"
	var r := HTTPRequest.new()
	r.download_file = part
	r.timeout = 120
	add_child(r)
	r.request_completed.connect(func(result, code, _h, _b):
		r.queue_free()
		var ok: bool = result == HTTPRequest.RESULT_SUCCESS and code == 200
		if ok:
			DirAccess.rename_absolute(part, dest)
		else:
			DirAccess.remove_absolute(part)
		var waiting: Array = _fetching.get(dest, [])
		_fetching.erase(dest)
		for w in waiting:
			if w.is_valid():
				w.call(ok))
	if r.request(base_url() + path, auth()) != OK:
		r.queue_free()
		_fetching.erase(dest)
		cb.call(false)


var _big := {}   # dest -> {stop}


## A large file (a film) in 16 MB pieces, so a dropped connection only costs
## the current piece and it carries on from there next time.
## progress(done, total); cb(ok, message).
func fetch_big(path: String, dest: String, total: int, progress: Callable, cb: Callable) -> void:
	if _big.has(dest):
		cb.call(false, "Already downloading.")
		return
	var part := dest + ".part"
	DirAccess.make_dir_recursive_absolute(dest.get_base_dir())
	_big[dest] = {"stop": false}
	var piece := 16 * 1048576
	var r := HTTPRequest.new()
	r.timeout = 60
	add_child(r)
	var step := func(self_ref: Callable):
		var have := 0
		if FileAccess.file_exists(part):
			var f0 := FileAccess.open(part, FileAccess.READ)
			have = f0.get_length()
			f0.close()
		progress.call(have, total)
		if have >= total:
			r.queue_free()
			_big.erase(dest)
			DirAccess.rename_absolute(part, dest)
			cb.call(true, "")
			return
		if _big[dest].stop:
			r.queue_free()
			_big.erase(dest)
			cb.call(false, "Paused.")
			return
		var h := auth()
		h.append("Range: bytes=%d-%d" % [have, mini(have + piece, total) - 1])
		r.request_completed.connect(func(result, code, _hh, body: PackedByteArray):
			if result != HTTPRequest.RESULT_SUCCESS or not (code == 206 or (code == 200 and have == 0)):
				r.queue_free()
				_big.erase(dest)
				cb.call(false, "The download stopped (%s). It carries on from here next time." % (code if code else result))
				return
			var f := FileAccess.open(part, FileAccess.READ_WRITE) if FileAccess.file_exists(part) else FileAccess.open(part, FileAccess.WRITE)
			f.seek_end()
			f.store_buffer(body)
			f.close()
			self_ref.call(self_ref), CONNECT_ONE_SHOT)
		r.body_size_limit = piece + 1024
		if r.request(base_url() + path, h) != OK:
			r.queue_free()
			_big.erase(dest)
			cb.call(false, "Couldn't start the download.")
	step.call(step)


func stop_big(dest: String) -> void:
	if _big.has(dest):
		_big[dest].stop = true


func downloading_big(dest: String) -> bool:
	return _big.has(dest)
