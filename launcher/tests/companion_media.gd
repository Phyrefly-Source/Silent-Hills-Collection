extends SceneTree
## Soundtracks, comics and films from the PC to the phone, over loopback, in
## one process (server and client). Run with SILENTHILLS_ROOT set to a folder
## with OSTs, comics and Movies, and tools/ffmpeg.
func _initialize() -> void:
	_run.call_deferred()


func _wait(flag: Array, ms: int = 60000) -> void:
	var t := Time.get_ticks_msec()
	while not flag[0] and Time.get_ticks_msec() - t < ms:
		await process_frame


func _api(pc, path: String) -> Array:
	var r := [false, null]
	pc.call_pc("127.0.0.1", 47630, HTTPClient.METHOD_GET, path, null, func(code, d): r[1] = [code, d]; r[0] = true, str(pc.pc().token))
	await _wait(r)
	return r[1]


func _run() -> void:
	await process_frame
	var App = root.get_node("App")
	App.set_setting("companion_enabled", true)
	var server = App.svc("companion")
	var pc = App.svc("pc")
	for d in [pc.media_dir("music"), pc.cache_dir("music"), pc.cache_dir("comics"), pc.media_dir("films")]:
		for f in DirAccess.get_files_at(d):
			DirAccess.remove_absolute(d.path_join(f))
	# Libraries.
	var ready := [false]
	App.svc("music").index(func(): ready[0] = true)
	await _wait(ready)
	ready = [false]
	App.svc("comics").scan(func(): ready[0] = true)
	await _wait(ready)
	ready = [false]
	App.svc("movies").scan(func(): ready[0] = true)
	await _wait(ready)
	# Pair.
	var shown := [""]
	server.pair_code.connect(func(code, _d): shown[0] = code)
	var st := [false]
	pc.pair_start("127.0.0.1", 47630, func(_ok, _m): st[0] = true)
	await _wait(st)
	var fin := [false]
	pc.pair_finish("127.0.0.1", 47630, "x", shown[0], func(ok, _m): fin[0] = true)
	await _wait(fin)

	# Music.
	var m: Array = await _api(pc, "/api/music")
	print("music: ", m[0], " albums ", m[1].albums.size())
	var a: Dictionary = m[1].albums[0]
	print("  ", a.title, " · ", a.artist, " · ", a.tracks.size(), " tracks, cover ", a.cover)
	var Player = load("res://companion/phone_player.gd")
	for i in mini(2, a.tracks.size()):
		var tr: Dictionary = a.tracks[i]
		var dest: String = Player.track_file(a.key, tr.id)
		var ok := [false, false]
		var t0 := Time.get_ticks_msec()
		pc.fetch(Player.track_path(tr.id), dest, func(x): ok[1] = x; ok[0] = true)
		await _wait(ok)
		var s: AudioStream = Player.load_audio(dest) if ok[1] else null
		print("  track %s: fetched %s in %d ms, plays %s, %.1f s" % [tr.title, ok[1], Time.get_ticks_msec() - t0, s != null, s.get_length() if s else 0.0])
	var kept := [false, false]
	Player.keep_album(a, func(d, n): pass, func(ok): kept[1] = ok; kept[0] = true)
	await _wait(kept, 120000)
	print("  kept album: ", kept[1], " ", Player.is_kept(a.key))

	# Comics.
	var c: Array = await _api(pc, "/api/comics")
	print("comics: ", c[0], " ", c[1].comics.size())
	var com: Dictionary = c[1].comics[0]
	print("  ", com.title, " (", com.series_title, ") pages ", com.pages, " at page ", com.page)
	var CS = load("res://companion/comics_screen.gd")
	var pg := [false, false]
	pc.fetch("/api/comics/page?id=%s&n=1" % com.id, CS.page_file(com.id, 1), func(x): pg[1] = x; pg[0] = true)
	await _wait(pg)
	var img = Pictures.read(CS.page_file(com.id, 1))
	print("  page 2: ", pg[1], " ", img.get_size() if img else null)
	CS.set_place(com, 1, int(com.pages))
	for i in 30: await process_frame
	var it: Dictionary = {}
	for x in App.svc("comics").items:
		if x.id == com.id: it = x
	print("  PC now has page ", App.svc("comics").progress(it))

	# Films.
	var f: Array = await _api(pc, "/api/films")
	var film: Dictionary = {}
	for x in f[1].films:
		print("film: ", x.title, " have ", x.have, " ", x.prepare)
		if x.have and film.is_empty(): film = x
	var pr := [false]
	pc.post_json("/api/films/prepare", {"id": film.id}, func(ok): pr[0] = true; print("  prepare asked: ", ok))
	await _wait(pr)
	var t1 := Time.get_ticks_msec()
	var status := {}
	while Time.get_ticks_msec() - t1 < 300000:
		var s2: Array = await _api(pc, "/api/films")
		for x in s2[1].films:
			if x.id == film.id: status = x.prepare
		if status.get("state", "") in ["ready", "failed"]: break
		await create_timer(2.0).timeout
	print("  prepared: ", status, " in ", (Time.get_ticks_msec() - t1) / 1000, " s")
	var FS = load("res://companion/films_screen.gd")
	var dl := [false, false]
	pc.fetch_big("/api/films/file?id=" + film.id, FS.film_file(film.id), int(status.get("size", 0)), func(d, t): pass, func(ok, msg): dl[1] = ok; dl[0] = true; print("  downloaded: ", ok, " ", msg))
	await _wait(dl, 120000)
	var vs := VideoStreamTheora.new()
	vs.file = FS.film_file(film.id)
	var vp := VideoStreamPlayer.new()
	root.add_child(vp)
	vp.stream = vs
	vp.play()
	for i in 10: await process_frame
	print("  plays on phone: length %.1f s" % vp.get_stream_length())
	vp.queue_free()
	FS.set_place(film.id, 12.5, true)
	for i in 30: await process_frame
	print("  PC place now ", App.svc("movies").place(film.id))
	var tk: Array = await _api(pc, "/api/films/ticket?id=" + film.id)
	print("  ticket: ", tk)
	var hc := HTTPClient.new()
	hc.connect_to_host("127.0.0.1", 47630)
	while hc.get_status() in [HTTPClient.STATUS_CONNECTING, HTTPClient.STATUS_RESOLVING]:
		hc.poll(); await process_frame
	hc.request(HTTPClient.METHOD_GET, str(tk[1].path).replace("/play", "/video.mp4"), ["Range: bytes=100-199"])
	while hc.get_status() == HTTPClient.STATUS_REQUESTING:
		hc.poll(); await process_frame
	print("  stream range: ", hc.get_response_code(), " ", hc.get_response_headers_as_dictionary().get("Content-Range", ""))
	App.flush()
	quit()
