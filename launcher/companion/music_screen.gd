extends Control
## Soundtracks on the phone: your albums from the PC, played from the PC at
## home or kept on the phone for anywhere.

var main   # companion_main.gd
var _albums: Array = []
var _grid: GridContainer
var _sub: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var pv: Array = main._scroll_page()
	add_child(pv[0])
	var v: VBoxContainer = pv[1]
	v.add_child(Style.label("Soundtracks", "H1"))
	_sub = Style.label("Asking your PC for your albums…", "Small", true)
	v.add_child(_sub)
	_grid = GridContainer.new()
	_grid.columns = 2
	_grid.add_theme_constant_override("h_separation", 12)
	_grid.add_theme_constant_override("v_separation", 16)
	v.add_child(_grid)
	var kept := _kept_list()
	if kept.is_empty():
		var w: float = (main.get_viewport_rect().size.x - 32 - 12) / 2.0
		for i in 4:
			_grid.add_child(Style.skeleton(Vector2(w, w + 40)))
	else:
		_fill(kept, true)
	App.svc("pc").get_json("/api/music", func(data):
		if not is_instance_valid(_grid):
			return
		if data is Dictionary and data.has("albums"):
			_fill(data.albums, false)
		elif _albums.is_empty():
			for c in _grid.get_children():
				c.queue_free()
			_sub.text = ""
			_grid.get_parent().add_child(Style.empty_state("wifi-off", "Your PC isn't answering",
				"Nothing is kept on this phone yet, so this needs your PC: open Silent Hills on it with the phone companion turned on, on the same Wi-Fi.",
				"Try again", func(): main.show_section(main._section)))
	)


func _kept_list() -> Array:
	return main.Player.kept_index().values()


func _fill(list: Array, offline: bool) -> void:
	_albums = list
	for c in _grid.get_children():
		c.queue_free()
	if list.is_empty():
		_sub.text = ""
		if not offline:
			_grid.get_parent().add_child(Style.empty_state("music", "No soundtracks on your PC yet",
				"Put your albums in the OSTs folder next to the launcher on your PC; they show here the next time this phone syncs."))
		return
	var kept: Dictionary = main.Player.kept_index()
	_sub.text = ("%d albums kept on this phone" % list.size()) if offline else ("%d albums on %s  ·  %d kept on this phone" % [list.size(), App.svc("pc").pc().get("name", "your PC"), kept.size()])
	var w: float = (main.get_viewport_rect().size.x - 32 - 12) / 2.0
	for a in list:
		_grid.add_child(_tile(a, w))


func cover_image(a: Dictionary, size: Vector2) -> Control:
	var box := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.1, 0.11)
	sb.set_corner_radius_all(4)
	box.add_theme_stylebox_override("panel", sb)
	box.custom_minimum_size = size
	box.clip_contents = true
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var local: String = main.Player.album_dir(a.key).path_join("cover.img")
	if FileAccess.file_exists(local) or a.get("cover", false):
		var img: TextureRect = load("res://ui/widgets/net_image.gd").new("", size)
		img.max_px = int(size.x * 2)
		img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		if FileAccess.file_exists(local):
			img.load_source(local)
		else:
			img.headers = App.svc("pc").auth()
			img.load_source(App.svc("pc").base_url() + "/api/music/cover?album=" + str(a.key).uri_encode())
		box.add_child(img)
	else:
		var l := Style.label(str(a.title).left(1), "H1")
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		box.add_child(l)
	return box


func _tile(a: Dictionary, w: float) -> Control:
	var b := Button.new()
	b.flat = true
	b.custom_minimum_size = Vector2(w, w + 52)
	b.set_meta("sfx", "move")
	var v := Style.vbox(4)
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(cover_image(a, Vector2(w, w)))
	var t := Style.label(str(a.title), "", false)
	t.clip_text = true
	t.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	t.add_theme_font_size_override("font_size", 14)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(t)
	var s := Style.label(str(a.get("artist", "")) + ("  ·  kept" if main.Player.is_kept(a.key) else ""), "Small")
	s.clip_text = true
	s.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(s)
	b.add_child(v)
	b.pressed.connect(func(): _open(a))
	return b


func _open(a: Dictionary) -> void:
	var page := Control.new()
	var bg := ColorRect.new()
	bg.color = Style.BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.add_child(bg)
	var pv: Array = main._scroll_page()
	page.add_child(pv[0])
	var v: VBoxContainer = pv[1]
	var back := Style.icon_button("arrow-left", "Back to Soundtracks", func(): page.queue_free(), "Soundtracks", "", 24)
	back.custom_minimum_size.y = Style.TARGET_TOUCH
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	back.set_meta("sfx", "back")
	v.add_child(back)
	var side: float = minf(main.get_viewport_rect().size.x - 32, 320)
	var cover := cover_image(a, Vector2(side, side))
	cover.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(cover)
	var t := Style.label(str(a.title), "H2", true)
	v.add_child(t)
	var secs := 0.0
	for tr in a.tracks:
		secs += float(tr.get("seconds", 0))
	v.add_child(Style.label("%s  ·  %d tracks%s" % [a.get("artist", ""), a.tracks.size(), ("  ·  %d min" % int(secs / 60)) if secs > 0 else ""], "Small", true))
	var row := Style.hbox(8)
	row.add_child(Style.button("Play", "Primary", func():
		main.Player.set_shuffle(false)
		main.Player.play_album(a, 0)))
	row.add_child(Style.button("Shuffle", "Ghost", func():
		main.Player.shuffle = true
		main.Player.play_album(a, randi() % a.tracks.size())))
	var keep := Style.button("", "Ghost", Callable())
	row.add_child(keep)
	v.add_child(row)
	var note := Style.label("", "Small", true)
	v.add_child(note)
	var set_keep := func():
		keep.text = "Remove from phone" if main.Player.is_kept(a.key) else "Keep on phone"
	set_keep.call()
	keep.pressed.connect(func():
		if main.Player.is_kept(a.key):
			main.Player.forget_album(a.key)
			note.text = "Removed from this phone."
			set_keep.call()
			return
		keep.disabled = true
		main.Player.keep_album(a, func(d: int, n: int):
			if is_instance_valid(note):
				note.text = "Saving to this phone… %d of %d" % [d, n],
		func(ok: bool):
			if not is_instance_valid(note):
				return
			keep.disabled = false
			note.text = "Kept on this phone. It plays anywhere now." if ok else "Some tracks couldn't be saved. Try again at home."
			set_keep.call()))
	var list := Style.vbox(0)
	v.add_child(list)
	var group := ""
	for i in a.tracks.size():
		var tr: Dictionary = a.tracks[i]
		if str(tr.get("group", "")) != group:
			group = str(tr.group)
			list.add_child(Style.margin(Style.label(group.to_upper(), "Caps"), 0, 12, 0, 4))
		list.add_child(_track_row(a, i))
	main._push(page)


func _track_row(a: Dictionary, i: int) -> Control:
	var tr: Dictionary = a.tracks[i]
	var b := Button.new()
	b.flat = true
	b.custom_minimum_size.y = 52
	var h := Style.hbox(12)
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var n := Style.label("%d" % (i + 1), "Small")
	n.custom_minimum_size.x = 26
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(n)
	var tv := Style.vbox(0)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var t := Style.label(str(tr.title))
	t.clip_text = true
	t.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	t.add_theme_font_size_override("font_size", 15)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tv.add_child(t)
	if str(tr.get("artist", "")) != "" and tr.artist != a.get("artist", ""):
		var ar := Style.label(str(tr.artist), "Small")
		ar.clip_text = true
		ar.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		ar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tv.add_child(ar)
	h.add_child(tv)
	var d := Style.label(main.fmt_time(float(tr.get("seconds", 0))) if float(tr.get("seconds", 0)) > 0 else "", "Small")
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(d)
	b.add_child(h)
	b.pressed.connect(func(): main.Player.play_album(a, i))
	var on_change := func():
		if is_instance_valid(t):
			var cur: Dictionary = main.Player.current()
			var me: bool = not cur.is_empty() and cur.track.id == tr.id
			t.add_theme_color_override("font_color", Style.ACCENT if me else Style.INK)
	main.Player.changed.connect(on_change)
	b.tree_exiting.connect(func(): main.Player.changed.disconnect(on_change))
	on_change.call()
	return b
