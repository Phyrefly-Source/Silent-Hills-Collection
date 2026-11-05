extends Node
## Companion service: lets the Silent Hills companion app on your phone read
## the launcher's progress over your home network.
##
##  * Off unless turned on in Settings ("companion_enabled").
##  * Found by the phone with a UDP broadcast on PORT + 1 ("SILENTHILLS?"),
##    answered with the PC's name and port.
##  * Paired once: the phone asks to pair, the PC shows a 6-digit code (in a
##    window and in Settings), the phone sends it back and gets a token. Every
##    other request needs "Authorization: Bearer <token>".
##  * Almost read only. A paired phone can only: add itself (with the code
##    shown on screen), save your place in a comic or film, and ask for a film
##    to be converted for phones (media.gd).
##
## HTTP/1.1, one request per connection, JSON answers. Endpoints:
##   GET  /api/hello                         name, version (no token needed)
##   POST /api/pair/start   {device}         shows a code on the PC
##   POST /api/pair/finish  {device, code}   -> {token}
##   GET  /api/catalogue                     games and films
##   GET  /api/achievements                  every game's achievements
##   GET  /api/art/<id>/hero                 a game's background (WebP/JPEG)
##   GET  /api/badge?url=<icon url>          an achievement icon, through the PC's cache
##   GET  /api/app                           the companion app this launcher carries {version, code, size}
##   GET  /api/app/apk                       that app's APK, for the phone to install
##
## Phones send "X-Companion-Version: <code>" so Settings can say which phones
## are behind; the app offers the update itself the next time it syncs.

signal pair_code(code: String, device: String)   # show this on screen
signal paired(device: String)

const PORT := 47630
const API_VERSION := 1
const MAX_REQUEST := 65536
const BADGE_HOSTS := ["media.retroachievements.org", "m.exophase.com", "cdn.akamai.steamstatic.com", "steamcdn-a.akamaihd.net",
	"shared.akamai.steamstatic.com", "cdn.cloudflare.steamstatic.com"]

var _tcp: TCPServer
var _udp: PacketPeerUDP
var _clients: Array = []      # [{peer, buf, since}]
var _pending := {}            # code -> {device, until}
var _ach_cache := {}          # {at, data}
var media                     # soundtracks, comics and films (media.gd)

## The companion app shipped beside the launcher: companion/SilentHillsCompanion.apk
## with companion/version.json {"version": "0.2", "code": 2}.
static func app_dir() -> String:
	return App.root_dir.path_join("companion")


static func app_info() -> Dictionary:
	var apk := app_dir().path_join("SilentHillsCompanion.apk")
	if not FileAccess.file_exists(apk):
		return {}
	var v: Dictionary = App.read_json(app_dir().path_join("version.json"), {})
	var f := FileAccess.open(apk, FileAccess.READ)
	return {"version": str(v.get("version", "")), "code": int(v.get("code", 0)), "size": f.get_length() if f else 0,
		"sha256": str(v.get("sha256", ""))}
var _building := false
var _waiting_ach: Array = []


func _ready() -> void:
	media = load("res://core/companion/media.gd").new()
	media.server = self
	add_child(media)
	App.settings_changed.connect(_apply)
	_apply()


func enabled() -> bool:
	return bool(App.settings.get("companion_enabled", false))


func running() -> bool:
	return _tcp != null and _tcp.is_listening()


func _apply() -> void:
	if enabled() and not running():
		start()
	elif not enabled() and running():
		stop()


func start() -> bool:
	_tcp = TCPServer.new()
	if _tcp.listen(PORT, "*") != OK:
		_tcp = null
		return false
	_udp = PacketPeerUDP.new()
	if _udp.bind(PORT + 1, "*") != OK:
		_udp = null
	set_process(true)
	return true


func stop() -> void:
	if _tcp:
		_tcp.stop()
	_tcp = null
	if _udp:
		_udp.close()
	_udp = null
	for c in _clients:
		c.peer.disconnect_from_host()
	_clients.clear()


## This PC's addresses on the local network (for Settings).
static func addresses() -> Array:
	var out := []
	for a in IP.get_local_addresses():
		if a.contains(":") or a.begins_with("127.") or a.begins_with("169.254."):
			continue
		out.append(a)
	return out


static func pc_name() -> String:
	var n := OS.get_environment("COMPUTERNAME")
	if n == "":
		n = OS.get_environment("HOSTNAME")
	return n if n != "" else "Silent Hills PC"


func devices() -> Array:
	return App.settings.get("companion_devices", [])


func forget(token: String) -> void:
	var list: Array = devices().filter(func(d): return d.token != token)
	App.set_setting("companion_devices", list)


# ------------------------------------------------------------------ network loop
func _process(_dt: float) -> void:
	if _udp:
		while _udp.get_available_packet_count() > 0:
			var pkt := _udp.get_packet().get_string_from_utf8()
			if pkt.begins_with("SILENTHILLS?"):
				var reply := JSON.stringify({"app": "silenthills", "name": pc_name(), "port": PORT, "api": API_VERSION})
				_udp.set_dest_address(_udp.get_packet_ip(), _udp.get_packet_port())
				_udp.put_packet(reply.to_utf8_buffer())
	if _tcp == null:
		return
	while _tcp.is_connection_available():
		var peer := _tcp.take_connection()
		peer.set_no_delay(true)
		_clients.append({"peer": peer, "buf": PackedByteArray(), "since": Time.get_ticks_msec(), "busy": false})
	for c in _clients.duplicate():
		var peer: StreamPeerTCP = c.peer
		peer.poll()
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED or Time.get_ticks_msec() - c.since > 30000:
			peer.disconnect_from_host()
			_clients.erase(c)
			continue
		if c.has("out_file"):
			_pump(c)
			continue
		if c.busy:
			continue
		var n := peer.get_available_bytes()
		if n > 0:
			var got: Array = peer.get_partial_data(n)
			if got[0] == OK:
				c.buf.append_array(got[1])
		if c.buf.size() > MAX_REQUEST:
			_send(c, 413, {"error": "too large"})
			continue
		var req := _parse(c.buf)
		if req.is_empty():
			continue
		c.busy = true
		_handle(c, req)


## A complete request from the bytes so far, or {} while more is coming.
static func _parse(buf: PackedByteArray) -> Dictionary:
	var text := buf.get_string_from_utf8()
	var end := text.find("\r\n\r\n")
	if end < 0:
		return {}
	var lines := text.substr(0, end).split("\r\n")
	var first := lines[0].split(" ")
	if first.size() < 2:
		return {"method": "BAD", "path": "/", "headers": {}, "body": ""}
	var headers := {}
	for i in range(1, lines.size()):
		var k := lines[i].find(":")
		if k > 0:
			headers[lines[i].substr(0, k).strip_edges().to_lower()] = lines[i].substr(k + 1).strip_edges()
	var body_len := int(headers.get("content-length", "0"))
	var head_bytes := text.substr(0, end + 4).to_utf8_buffer().size()
	if buf.size() < head_bytes + body_len:
		return {}
	var body := buf.slice(head_bytes, head_bytes + body_len).get_string_from_utf8()
	var path := first[1]
	var query := {}
	if path.contains("?"):
		for kv in path.split("?", true, 1)[1].split("&"):
			var p := kv.split("=", true, 1)
			query[p[0].uri_decode()] = p[1].uri_decode() if p.size() > 1 else ""
		path = path.split("?")[0]
	return {"method": first[0], "path": path, "query": query, "headers": headers, "body": body}


func _authorized(req: Dictionary) -> bool:
	var h := str(req.headers.get("authorization", ""))
	if not h.begins_with("Bearer "):
		return false
	var token := h.substr(7).strip_edges()
	for d in devices():
		if str(d.token) == token:
			d.last_seen = int(Time.get_unix_time_from_system())
			var v := int(req.headers.get("x-companion-version", "0"))
			if v > 0 and int(d.get("app_code", 0)) != v:
				d.app_code = v
				d.app_version = str(req.headers.get("x-companion-version-name", ""))
				App.set_setting("companion_devices", devices())
			return true
	return false


func _handle(c: Dictionary, req: Dictionary) -> void:
	var path: String = req.path
	if path == "/api/hello":
		_send(c, 200, {"app": "silenthills", "name": pc_name(), "version": App.VERSION, "api": API_VERSION,
			"paired": _authorized(req)})
		return
	if path == "/api/pair/start" and req.method == "POST":
		var body = JSON.parse_string(req.body)
		var device := str(body.get("device", "Phone")) if body is Dictionary else "Phone"
		var code := "%06d" % (randi() % 1000000)
		_pending[code] = {"device": device.left(40), "until": Time.get_ticks_msec() + 120000}
		pair_code.emit(code, device)
		App.notify("%s wants to pair with Silent Hills. Code: %s" % [device.left(40), code])
		_send(c, 200, {"ok": true, "expires": 120})
		return
	if path == "/api/pair/finish" and req.method == "POST":
		var body = JSON.parse_string(req.body)
		var code := str(body.get("code", "")) if body is Dictionary else ""
		var p: Dictionary = _pending.get(code, {})
		if p.is_empty() or Time.get_ticks_msec() > int(p.until):
			_send(c, 403, {"error": "That code isn't right, or it has expired. Start pairing again."})
			return
		_pending.erase(code)
		var token := Crypto.new().generate_random_bytes(24).hex_encode()
		var list: Array = devices().duplicate()
		list.append({"name": p.device, "token": token, "paired": int(Time.get_unix_time_from_system()), "last_seen": 0})
		App.set_setting("companion_devices", list)
		paired.emit(p.device)
		App.notify("%s is paired with Silent Hills." % p.device, "ok")
		_send(c, 200, {"token": token, "name": pc_name()})
		return
	if path == "/api/badge":
		# Achievement icons, through this PC's cache, so the phone has them too.
		# Public pictures from the achievement lists' own hosts only.
		var url := str(req.query.get("url", ""))
		var host := url.trim_prefix("https://").split("/")[0]
		if not url.begins_with("https://") or not (host in BADGE_HOSTS):
			_send(c, 400, {"error": "bad url"})
			return
		Net.get_file(url, func(p: String):
			if p == "":
				_send(c, 404, {"error": "not found"})
			else:
				_send_file(c, p))
		return
	if path.begins_with("/s/"):
		media.ticket_route(c, req)   # a film opened in the phone's own video app
		return
	if not _authorized(req):
		_send(c, 401, {"error": "Not paired"})
		return
	if media.route(c, req):
		return
	if path == "/api/catalogue":
		_send(c, 200, _catalogue())
	elif path == "/api/achievements":
		_achievements(func(data): _send(c, 200, data))
	elif path.begins_with("/api/art/") and path.ends_with("/hero"):
		var id := path.trim_prefix("/api/art/").trim_suffix("/hero")
		_send_art(c, id)
	elif path == "/api/app":
		_send(c, 200, app_info())
	elif path == "/api/app/apk":
		var apk := app_dir().path_join("SilentHillsCompanion.apk")
		if FileAccess.file_exists(apk):
			_stream_file(c, apk, "application/vnd.android.package-archive", req)
		else:
			_send(c, 404, {"error": "no app here"})
	else:
		_send(c, 404, {"error": "unknown"})


func _catalogue() -> Dictionary:
	var games := []
	for g in App.games:
		games.append({"id": g.id, "title": g.title, "subtitle": g.get("subtitle", ""), "year": int(g.get("year", 0)),
			"accent": g.get("accent", ""), "shm": g.get("art", {}).get("shm", "")})
	var films := []
	for f in App.films:
		films.append({"id": f.id, "title": f.title, "year": int(f.get("year", 0)), "accent": f.get("accent", ""),
			"shm": f.get("art", {}).get("shm", "")})
	return {"games": games, "films": films, "name": pc_name()}


## Every game's achievements, gathered once a minute at most.
func _achievements(cb: Callable) -> void:
	if not _ach_cache.is_empty() and Time.get_ticks_msec() - int(_ach_cache.at) < 60000:
		cb.call(_ach_cache.data)
		return
	_waiting_ach.append(cb)
	if _building:
		return
	_building = true
	var ach = App.svc("achievements")
	var out := {"generated": int(Time.get_unix_time_from_system()), "pc": pc_name(), "games": []}
	var ids: Array = App.games.map(func(g): return g.id)
	var step := [0]
	var next := func(self_ref: Callable):
		if step[0] >= ids.size():
			_ach_cache = {"at": Time.get_ticks_msec(), "data": out}
			_building = false
			var cbs := _waiting_ach.duplicate()
			_waiting_ach.clear()
			for w in cbs:
				w.call(out)
			return
		var id: String = ids[step[0]]
		step[0] += 1
		ach.view(id, func(groups: Array):
			var u := 0
			var t := 0
			for gr in groups:
				u += int(gr.unlocked)
				t += int(gr.total)
			out.games.append({"id": id, "title": App.game(id).title, "unlocked": u, "total": t, "groups": groups})
			self_ref.call(self_ref))
	next.call(next)


func _send_art(c: Dictionary, id: String) -> void:
	var art = App.svc("art")
	var cached: String = art._cache_file(id, "hero")
	if FileAccess.file_exists(cached):
		_send_file(c, cached)
		return
	art.get_texture(id, "hero", func(_tex):
		if FileAccess.file_exists(cached):
			_send_file(c, cached)
		else:
			_send(c, 404, {"error": "no art"}))


# ------------------------------------------------------------------ replies
func _send(c: Dictionary, code: int, data) -> void:
	var body := JSON.stringify(data).to_utf8_buffer()
	_write(c, code, "application/json; charset=utf-8", body)


func _send_file(c: Dictionary, path: String) -> void:
	var b := FileAccess.get_file_as_bytes(path)
	var ext := path.get_extension().to_lower()
	var mime: String = {"webp": "image/webp", "jpg": "image/jpeg", "jpeg": "image/jpeg", "png": "image/png", "bmp": "image/bmp",
		"gif": "image/gif"}.get(ext, "application/octet-stream")
	_write(c, 200, mime, b)


## Large files go out a piece at a time from _process, so the launcher keeps
## running. Honours "Range: bytes=a-b" (206) so downloads can resume and video
## players can seek; HEAD answers the headers only.
func _stream_file(c: Dictionary, path: String, mime: String, req: Dictionary = {}) -> void:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		_send(c, 404, {"error": "unreadable"})
		return
	var size := f.get_length()
	var start := 0
	var end := size - 1
	var code := 200
	var rng := str(req.get("headers", {}).get("range", ""))
	if rng.begins_with("bytes="):
		var parts := rng.substr(6).split(",")[0].split("-")
		if parts[0] != "":
			start = int(parts[0])
			if parts.size() > 1 and parts[1] != "":
				end = mini(int(parts[1]), size - 1)
		elif parts.size() > 1 and parts[1] != "":
			start = maxi(0, size - int(parts[1]))
		if start >= size or start > end:
			_write(c, 416, "text/plain", ("bytes */%d" % size).to_utf8_buffer())
			return
		code = 206
	var head := "HTTP/1.1 %d %s\r\nContent-Type: %s\r\nContent-Length: %d\r\nAccept-Ranges: bytes\r\n" % [code, "Partial Content" if code == 206 else "OK", mime, end - start + 1]
	if code == 206:
		head += "Content-Range: bytes %d-%d/%d\r\n" % [start, end, size]
	if mime == "application/vnd.android.package-archive":
		head += "Content-Disposition: attachment; filename=\"%s\"\r\n" % path.get_file()
	head += "Access-Control-Allow-Origin: *\r\nConnection: close\r\nCache-Control: no-store\r\n\r\n"
	c.out_buf = head.to_utf8_buffer()
	if str(req.get("method", "GET")) == "HEAD":
		f.close()
		c.out_file = null
		c.out_left = 0
		return
	f.seek(start)
	c.out_file = f
	c.out_left = end - start + 1


func _pump(c: Dictionary) -> void:
	var peer: StreamPeerTCP = c.peer
	for i in 32:
		if c.out_buf.is_empty():
			var f = c.out_file
			if f == null or int(c.out_left) <= 0:
				if f != null:
					f.close()
				c.erase("out_file")
				peer.disconnect_from_host()
				_clients.erase(c)
				return
			c.out_buf = f.get_buffer(mini(65536, int(c.out_left)))
			c.out_left = int(c.out_left) - c.out_buf.size()
			if c.out_buf.is_empty():
				c.out_left = 0
				continue
		var r: Array = peer.put_partial_data(c.out_buf)
		if r[0] != OK:
			peer.disconnect_from_host()
			_clients.erase(c)
			return
		var sent: int = r[1]
		if sent <= 0:
			return
		c.since = Time.get_ticks_msec()
		c.out_buf = c.out_buf.slice(sent)


func _write(c: Dictionary, code: int, mime: String, body: PackedByteArray) -> void:
	var peer: StreamPeerTCP = c.peer
	if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		_clients.erase(c)
		return
	var reason: String = {200: "OK", 202: "Accepted", 400: "Bad Request", 401: "Unauthorized", 403: "Forbidden", 404: "Not Found", 413: "Too Large", 416: "Range Not Satisfiable", 503: "Busy"}.get(code, "OK")
	var head := "HTTP/1.1 %d %s\r\nContent-Type: %s\r\nContent-Length: %d\r\nConnection: close\r\nCache-Control: no-store\r\n\r\n" % [code, reason, mime, body.size()]
	peer.put_data(head.to_utf8_buffer())
	peer.put_data(body)
	peer.disconnect_from_host()
	_clients.erase(c)
