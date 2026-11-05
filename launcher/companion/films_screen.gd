extends Control
## Films on the phone. Two ways to watch:
##  * Play on phone: the PC converts the film once for the phone, the phone
##    downloads it (a minute or two on home Wi-Fi) and plays it in the app,
##    anywhere, and your place is kept in step with the PC.
##  * Stream to a video app: right away, at home, in your phone's own player.

var main
var _list: VBoxContainer
var _sub: Label
var _poll: Timer
var _films: Array = []


static func kept_index() -> Dictionary:
	return App.read_json(App.svc("pc").media_dir("films").path_join("films.json"), {})


static func film_file(id: String) -> String:
	return App.svc("pc").media_dir("films").path_join(id + ".ogv")


static func places() -> Dictionary:
	return App.settings.get("film_places", {})


static func set_place(id: String, sec: float, push: bool) -> void:
	var p := places()
	p[id] = {"seconds": sec, "at": int(Time.get_unix_time_from_system())}
	App.set_setting("film_places", p)
	if push:
		App.svc("pc").post_json("/api/films/place", {"id": id, "seconds": sec}, Callable(), true)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var pv: Array = main._scroll_page()
	add_child(pv[0])
	var v: VBoxContainer = pv[1]
	v.add_child(Style.label("Films", "H1"))
	_sub = Style.label("Asking your PC about the films…", "Small", true)
	v.add_child(_sub)
	_list = Style.vbox(14)
	v.add_child(_list)
	_poll = Timer.new()
	_poll.wait_time = 3.0
	_poll.timeout.connect(_refresh)
	add_child(_poll)
	if kept_index().is_empty():
		_list.add_child(Style.skeleton_list(3, 150))
	else:
		_fill(kept_index().values(), true)
	_refresh()


func _refresh() -> void:
	App.svc("pc").get_json("/api/films", func(data):
		if not is_instance_valid(_list):
			return
		if data is Dictionary and data.has("films"):
			_fill(data.films, false)
		elif kept_index().is_empty():
			for c in _list.get_children():
				c.queue_free()
			_sub.text = ""
			_list.add_child(Style.empty_state("wifi-off", "Your PC isn't answering",
				"Nothing is kept on this phone yet, so this needs your PC: open Silent Hills on it with the phone companion turned on, on the same Wi-Fi.",
				"Try again", func(): main.show_section(main._section)))
			_poll.stop()
	)


func _fill(list: Array, offline: bool) -> void:
	_films = list
	for c in _list.get_children():
		c.queue_free()
	var busy := false
	for f in list:
		if str(f.get("prepare", {}).get("state", "")) in ["working", "queued"]:
			busy = true
		if offline or f.get("have", false) or kept_index().has(f.id):
			_list.add_child(_card(f, offline))
	if _list.get_child_count() == 0:
		_sub.text = ""
		if not offline:
			_list.add_child(Style.empty_state("film", "None of the films are on your PC yet",
				"Put your copies in the Movies folder next to the launcher, or choose them in its Films tab."))
	else:
		_sub.text = "Kept on this phone" if offline else "From %s" % App.svc("pc").pc().get("name", "your PC")
	if busy and _poll.is_stopped():
		_poll.start()
	elif not busy and not _poll.is_stopped():
		_poll.stop()


func _card(f: Dictionary, offline: bool) -> Control:
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.07, 0.075)
	sb.border_color = Style.color_hex(str(f.get("accent", "")), Style.LINE).darkened(0.3)
	sb.border_width_left = 3
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(14)
	panel.add_theme_stylebox_override("panel", sb)
	var v := Style.vbox(8)
	var t := Style.label(str(f.title), "H2", true)
	v.add_child(t)
	var meta := [str(int(f.get("year", 0)))]
	if str(f.get("director", "")) != "":
		meta.append(str(f.director))
	v.add_child(Style.label("  ·  ".join(meta), "Small"))
	var status := Style.label("", "Small", true)
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size.y = 4
	bar.visible = false
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 8)
	row.add_theme_constant_override("v_separation", 8)
	var file := film_file(f.id)
	var place := _place(f)
	if FileAccess.file_exists(file):
		status.text = "On this phone" + (("  ·  stopped at %s" % main.fmt_time(place)) if place > 30 else "")
		row.add_child(Style.icon_button("play", "Play", func(): _play(f, place if place > 30 else 0.0), ("Resume  ·  %s" % main.fmt_time(place)) if place > 30 else "Play", "Primary", 20))
		if place > 30:
			row.add_child(Style.button("Start over", "Ghost", func(): _play(f, 0.0)))
		row.add_child(Style.button("Remove from phone", "", func():
			DirAccess.remove_absolute(file)
			DirAccess.remove_absolute(file.get_basename() + ".srt")
			var idx := kept_index()
			idx.erase(f.id)
			App.write_json(App.svc("pc").media_dir("films").path_join("films.json"), idx)
			_fill(_films, offline)))
	elif not offline:
		var st: Dictionary = f.get("prepare", {})
		match str(st.get("state", "none")):
			"ready":
				var size := int(st.get("size", 0))
				var downloading: bool = App.svc("pc").downloading_big(file)
				status.text = "Ready to download  ·  %.1f GB" % (size / 1073741824.0)
				var dl := Style.icon_button("download", "Download to phone", Callable(), "Download to phone", "Ghost", 20)
				dl.pressed.connect(func(): _download(f, size, dl, status, bar))
				row.add_child(dl)
				if downloading:
					dl.text = "Pause"
					bar.visible = true
			"working", "queued":
				status.text = ("Getting ready on your PC… %d%%" % int(100 * float(st.get("progress", 0)))) if st.state == "working" else "Waiting its turn on your PC…"
				bar.visible = true
				bar.value = 100 * float(st.get("progress", 0))
			"failed":
				status.text = "Getting it ready failed: %s" % st.get("error", "")
				row.add_child(Style.button("Try again", "Ghost", func(): _prepare(f)))
			_:
				status.text = "To watch it in the app (and anywhere), your PC converts it for the phone once. That takes a while, and the PC needs to stay on with Silent Hills open."
				row.add_child(Style.icon_button("hard-drive", "Get it ready for the phone", func(): _prepare(f), "Get it ready for the phone", "Ghost", 20))
		row.add_child(Style.icon_button("external-link", "Stream to a video app", func(): _stream(f, status), "Stream to a video app", "", 20))
	v.add_child(status)
	v.add_child(bar)
	v.add_child(row)
	panel.add_child(v)
	return panel


## Seconds into the film: the newest of this phone's place and the PC's.
func _place(f: Dictionary) -> float:
	var mine: Dictionary = places().get(f.id, {})
	if not mine.is_empty() and int(mine.at) >= int(f.get("place_at", 0)):
		return float(mine.seconds)
	return float(f.get("place", 0.0))


func _prepare(f: Dictionary) -> void:
	App.svc("pc").post_json("/api/films/prepare", {"id": f.id}, func(ok: bool):
		if not ok:
			App.notify("Your PC couldn't start on that film.")
		_refresh())


func _download(f: Dictionary, size: int, btn: Button, status: Label, bar: ProgressBar) -> void:
	var pc = App.svc("pc")
	var file := film_file(f.id)
	if pc.downloading_big(file):
		pc.stop_big(file)
		btn.text = "Download to phone"
		return
	btn.text = "Pause"
	bar.visible = true
	var t0 := Time.get_ticks_msec()
	pc.fetch_big("/api/films/file?id=" + str(f.id), file, size, func(done: int, total: int):
		if is_instance_valid(bar):
			bar.value = 100.0 * done / maxf(1.0, total)
			var mbps := (done / 1048576.0) / maxf(0.5, (Time.get_ticks_msec() - t0) / 1000.0)
			status.text = "Downloading… %.2f of %.2f GB" % [done / 1073741824.0, total / 1073741824.0] + (("  ·  %.0f MB/s" % mbps) if done > 0 else ""),
	func(ok: bool, msg: String):
		if ok:
			if f.get("subs", false):
				pc.fetch("/api/films/subs?id=" + str(f.id), file.get_basename() + ".srt", func(_o): pass)
			var idx := kept_index()
			var keep := f.duplicate()
			keep.erase("prepare")
			idx[f.id] = keep
			App.write_json(pc.media_dir("films").path_join("films.json"), idx)
			App.notify("%s is on your phone." % f.title, "ok")
			if is_instance_valid(_list):
				_fill(_films, false)
		elif is_instance_valid(status):
			status.text = msg
			btn.text = "Carry on downloading")


func _stream(f: Dictionary, status: Label) -> void:
	var pc = App.svc("pc")
	var p: Dictionary = pc.pc()
	status.text = "Asking your PC…"
	pc.call_pc(str(p.host), int(p.get("port", 47630)), HTTPClient.METHOD_GET, "/api/films/ticket?id=" + str(f.id), null, func(code, data):
		if not is_instance_valid(status):
			return
		if code == 200 and data is Dictionary:
			status.text = "Opening in your browser: play it there, or tap \"Open in a video app\"."
			OS.shell_open(pc.base_url() + str(data.path))
		else:
			status.text = "Your PC isn't reachable right now.", str(p.get("token", "")))


func _play(f: Dictionary, at: float) -> void:
	var pl: Control = load("res://companion/phone_film.gd").new()
	pl.main = main
	pl.film = f
	pl.start_at = at
	pl.tree_exited.connect(func():
		if is_instance_valid(self) and is_inside_tree():
			_fill.call_deferred(_films, _films.is_empty() or not _films[0].has("prepare")))
	main.overlay(pl)
