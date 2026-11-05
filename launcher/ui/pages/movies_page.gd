extends Control
## Films: the Silent Hill films over their art, played in the launcher's own
## player. Your copies are found in a Movies folder beside the launcher (or
## chosen by hand); your place in each film is remembered.

var main: Control
var _list: VBoxContainer
var _rows := {}
var _selected := ""
var _title: Label
var _meta: Label
var _blurb: Label
var _note: Label
var _actions: HBoxContainer
var _scanned := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	scroll.offset_left = 28
	scroll.offset_top = 24
	scroll.offset_bottom = -64
	scroll.custom_minimum_size.x = 380
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_list = Style.vbox(0)
	_list.custom_minimum_size.x = 370
	scroll.add_child(_list)

	var info := Style.vbox(12)
	info.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	info.offset_left = 420
	info.offset_right = -60
	info.offset_bottom = -64
	info.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(info)
	_title = Style.label("", "Title", true)
	_title.custom_minimum_size.x = 600
	info.add_child(_title)
	_meta = Style.label("", "Meta")
	info.add_child(_meta)
	_blurb = Style.label("", "Body", true)
	_blurb.custom_minimum_size.x = 600
	info.add_child(_blurb)
	info.add_child(Style.spacer(8))
	_actions = Style.hbox(10)
	info.add_child(_actions)
	_note = Style.label("", "Small", true)
	_note.custom_minimum_size.x = 600
	info.add_child(_note)

	var movies = App.svc("movies")
	movies.scanned.connect(func():
		_build_list()
		if _selected != "":
			select(_selected))
	App.svc("art").art_ready.connect(func(id, kind):
		if id == _selected and kind == "hero" and visible:
			_load_art(id))
	_build_list()
	select(App.films[0].id)
	var hm: Button = App.missing_toggle()
	hm.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	hm.offset_left = 44
	hm.offset_top = -56
	hm.offset_bottom = -24
	add_child(hm)
	var was := [App.hide_missing()]
	App.settings_changed.connect(func():
		if App.hide_missing() != was[0]:
			was[0] = App.hide_missing()
			_build_list()
			if not _rows.has(_selected) and not _rows.is_empty():
				select(_rows.keys()[0])
			else:
				_style_rows())


func on_shown() -> void:
	if not _scanned:
		_scanned = true
		App.svc("movies").scan()
	if _selected != "":
		_load_art(_selected)


func _build_list() -> void:
	for c in _list.get_children():
		c.queue_free()
	_rows.clear()
	var movies = App.svc("movies")
	for f in App.films:
		var have: bool = movies.path_of(f.id) != ""
		if have or not App.hide_missing():
			_row(f.id, str(f.title), str(int(f.year)), have)
	if _rows.is_empty():
		_list.add_child(Style.margin(Style.label("No films found. Put your copies in a Movies folder next to the launcher, or turn off Hide missing to choose them by hand.", "Small", true), 16, 8, 0, 0))
	if not movies.extra.is_empty():
		_list.add_child(Style.margin(Style.label("OTHER FILES", "Caps"), 16, 18, 0, 6))
		for p in movies.extra:
			_row("file:" + str(p), str(p).get_file().get_basename(), "", true)
	_style_rows()


func _row(id: String, text: String, year: String, have: bool) -> void:
	var b := Button.new()
	b.custom_minimum_size = Vector2(370, 54)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.pressed.connect(select.bind(id))
	b.set_meta("sfx", "move")
	var h := Style.hbox(14)
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 16
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bar := ColorRect.new()
	bar.custom_minimum_size = Vector2(2, 22)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.color = Color(1, 1, 1, 0)
	h.add_child(bar)
	var name := Style.label(text)
	name.add_theme_font_override("font", Style.serif)
	name.add_theme_font_size_override("font_size", 25 if not id.begins_with("file:") else 19)
	name.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name.clip_text = true
	name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(name)
	if year != "":
		var y := Style.label(year, "Small")
		y.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(y)
	b.add_child(h)
	_list.add_child(b)
	_rows[id] = {"bar": bar, "name": name, "have": have}


func _style_rows() -> void:
	for id in _rows:
		var r: Dictionary = _rows[id]
		var on: bool = id == _selected
		r.bar.color = Style.INK if on else Color(1, 1, 1, 0)
		r.name.add_theme_color_override("font_color", Style.INK if on else (Style.INK_2 if r.have else Style.INK_3))


func select(id: String) -> void:
	_selected = id
	_style_rows()
	for c in _actions.get_children():
		c.queue_free()
	_note.text = ""
	var movies = App.svc("movies")
	if id.begins_with("file:"):
		var p := id.substr(5)
		_title.text = p.get_file().get_basename()
		_meta.text = "A video in your films folder"
		_blurb.text = ""
		_actions.add_child(Style.button("Play", "Primary", func(): play_file(p, "", _title.text)))
		main.backdrop.show_art(null)
		return
	var f := App.entry(id)
	_title.text = str(f.title)
	var meta := [str(int(f.year))]
	if str(f.get("director", "")) != "":
		meta.append("Directed by " + str(f.director))
	_meta.text = "  ·  ".join(meta)
	_blurb.text = str(f.get("blurb", ""))
	var file: String = movies.path_of(id)
	if file != "":
		var at: float = movies.place(id)
		if at > 30.0:
			var pb := Style.icon_button("play", "Resume", func(): play_file(file, id, str(f.title)), "Resume  ·  %s" % _fmt(at), "Primary", 18)
			pb.add_theme_font_override("font", Style.numeric)
			pb.custom_minimum_size.x = 210
			_actions.add_child(pb)
			_actions.add_child(Style.button("Start over", "Ghost", func():
				movies.set_place(id, 0.0)
				play_file(file, id, str(f.title))))
		else:
			var pb := Style.icon_button("play", "Play", func(): play_file(file, id, str(f.title)), "Play", "Primary", 18)
			pb.custom_minimum_size.x = 170
			_actions.add_child(pb)
		_note.text = file.get_file()
	else:
		var fb := Style.icon_button("folder-plus", "Choose the file", func(): _choose(id), "Choose the file…", "Primary", 18)
		_actions.add_child(fb)
		_note.text = "Put your copy in a Movies folder next to the launcher, or choose the file."
	if file != "":
		_actions.add_child(Style.icon_button("folder-plus", "Change file", func(): _choose(id), "Change file…", "", 18))
	# The film's soundtrack, when it's in your soundtrack folders.
	var music = App.svc("music")
	for a in music.albums():
		if a.game == id:
			var key: String = a.key
			_actions.add_child(Style.icon_button("music", "Soundtrack", func():
				main.show_page("music")
				main._pages.music.call("_open", key), "Soundtrack", "", 18))
			break
	_actions.add_child(Style.icon_button("image", "Background", func():
		var ap: Control = load("res://ui/widgets/art_picker.gd").new()
		ap.set("main", main)
		ap.set("game_id", id)
		ap.set("kind", "hero")
		main.modal_layer.add_child(ap), "Background…", "", 18))
	_actions.add_child(Style.icon_button("sparkles", "Concept art", func():
		main.show_page("concept")
		main._pages.concept.call("open_game", id), "Concept art", "", 18))
	main.backdrop.set_atmosphere(str(f.get("fx", "mist")), Style.color_hex(str(f.get("accent", ""))))
	_load_art(id)


func _choose(id: String) -> void:
	main.choose_path("Choose your copy of %s" % App.entry(id).title, "file",
		PackedStringArray(["*.mkv,*.mp4,*.m4v,*.avi,*.mov,*.webm,*.ts,*.m2ts,*.wmv ; Videos"]), func(p):
			if p != "":
				App.svc("movies").set_path(id, p))


func _load_art(id: String) -> void:
	App.svc("art").get_texture(id, "hero", func(tex):
		if visible and _selected == id:
			main.backdrop.show_art(tex, 0.75))


func play_file(file: String, id: String, title: String) -> void:
	var p: Control = load("res://ui/widgets/movie_player.gd").new()
	p.set("file", file)
	p.set("film_id", id)
	p.set("title", title)
	p.connect("closed", func():
		if is_instance_valid(self) and _selected != "":
			select(_selected))
	main.modal_layer.add_child(p)


static func _fmt(s: float) -> String:
	var t := int(s)
	return ("%d:%02d:%02d" % [t / 3600, (t / 60) % 60, t % 60]) if t >= 3600 else ("%d:%02d" % [t / 60, t % 60])
