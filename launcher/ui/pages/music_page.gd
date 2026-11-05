extends Control
## Soundtracks: a jukebox of the series' music, pulled from your games and your
## own folders. Albums on the left, tracks on the right, the player along the
## bottom. Favourites and playlists are kept in the library.

var main: Control
var _albums: VBoxContainer
var _tracks: VBoxContainer
var _album_title: Label
var _album_sub: Label
var _album_actions: HBoxContainer
var _cover: TextureRect
var _album_kind_game := ""
var _current_key := ""
var _current_list: Array = []
var _rows := {}
# player
var _np_title: Label
var _np_album: Label
var _play: Button
var _seek: HSlider
var _time: Label
var _shuffle: Button
var _repeat: Button
var _layers: Button
var _dragging := false
var _loaded := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var lib = App.svc("music")

	var left := Style.vbox(6)
	left.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	left.offset_left = 44
	left.offset_top = 28
	left.offset_bottom = -110
	left.custom_minimum_size.x = 280
	add_child(left)
	left.add_child(Style.label("Soundtracks", "H1"))
	var srow := Style.hbox(8)
	srow.add_child(Style.button("Look again", "Ghost", func():
		App.notify("Looking through your soundtrack folders…")
		lib.index(func(): App.notify("%d tracks in the jukebox." % lib.tracks.size()))))
	srow.add_child(Style.button("Add a folder…", "", add_folder))
	left.add_child(srow)
	var hm: Button = App.missing_toggle()
	hm.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	left.add_child(hm)
	left.add_child(Style.spacer(4))
	var ascroll := ScrollContainer.new()
	ascroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ascroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_albums = Style.vbox(2)
	_albums.custom_minimum_size.x = 270
	ascroll.add_child(_albums)
	# List rows have their own padding; pull them out so their text lines up
	# with the headings.
	var am := Style.margin(ascroll, -Style.SPACE_S, 0, 0, 0)
	am.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(am)

	var right := Style.vbox(10)
	right.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	right.offset_left = 380
	right.offset_right = -44
	right.offset_top = 34
	right.offset_bottom = -110
	add_child(right)
	var head := Style.hbox(22)
	_cover = preload("res://ui/widgets/net_image.gd").new("", Vector2(132, 132))
	_cover.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_cover.visible = false
	head.add_child(_cover)
	var titles := Style.vbox(6)
	titles.size_flags_vertical = Control.SIZE_SHRINK_END
	_album_title = Style.label("", "H1", true)
	_album_title.custom_minimum_size.x = 520
	titles.add_child(_album_title)
	_album_sub = Style.label("", "Meta")
	titles.add_child(_album_sub)
	head.add_child(titles)
	right.add_child(head)
	_album_actions = Style.hbox(8)
	right.add_child(_album_actions)
	var tscroll := ScrollContainer.new()
	tscroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tracks = Style.vbox(0)
	_tracks.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tscroll.add_child(_tracks)
	right.add_child(tscroll)

	add_child(_player_bar())
	lib.indexed.connect(_fill_albums)
	var was := [App.hide_missing()]
	App.settings_changed.connect(func():
		if App.hide_missing() != was[0]:
			was[0] = App.hide_missing()
			_fill_albums())
	Jukebox.track_changed.connect(func(_t): _sync_player())
	Jukebox.state_changed.connect(_sync_player)


func add_folder() -> void:
	main.choose_path("Add a folder of music", "folder", PackedStringArray(), func(p):
		if p != "":
			var f: Array = App.settings.get("music_folders", [])
			if not f.has(p):
				f.append(p)
				App.set_setting("music_folders", f)
			App.svc("music").index())


func on_shown() -> void:
	main.backdrop.set_atmosphere("mist", Color(0.45, 0.45, 0.5))
	_show_art()
	if not _loaded:
		_loaded = true
		_fill_albums()
		var lib = App.svc("music")
		if lib.tracks.is_empty():
			lib.index()
	_sync_player()


func _show_art() -> void:
	var gid: String = Jukebox.current.get("game", "")
	if gid == "":
		gid = _album_kind_game
	if gid != "":
		App.svc("art").get_texture(gid, "hero", func(tex):
			if visible:
				main.backdrop.show_art(tex, 0.35))
	else:
		main.backdrop.show_art(null)


func _process(_dt: float) -> void:
	if not visible or Jukebox.current.is_empty() or _dragging:
		return
	var d := Jukebox.duration()
	var p := Jukebox.position()
	_seek.max_value = max(d, 1.0)
	_seek.set_value_no_signal(p)
	_time.text = "%s / %s" % [_fmt(p), _fmt(d)]


## "AKIRA YAMAOKA" -> "Akira Yamaoka"; mixed-case names are left alone.
static func _nice(name: String) -> String:
	return name.capitalize() if name == name.to_upper() else name


static func _fmt(s: float) -> String:
	var t := int(s)
	return "%d:%02d" % [t / 60, t % 60]


# ------------------------------------------------------------------ albums
func _fill_albums() -> void:
	for c in _albums.get_children():
		c.queue_free()
	var lib = App.svc("music")
	var favs: Array = lib.favorites()
	_album_button("fav", "Favourites", favs.size())
	for name in lib.playlists():
		_album_button("pl:" + name, name, lib.playlist_tracks(name).size())
	_albums.add_child(Style.spacer(10))
	var albums: Array = lib.albums()
	if albums.is_empty():
		_albums.add_child(Style.empty_state("music", "No soundtracks yet",
			"Put your albums in an OSTs folder next to the launcher, or add a folder you keep music in.", "Add a folder…", add_folder))
	var heads := {"ost": "SOUNDTRACKS", "film": "FILM SOUNDTRACKS", "folder": "OTHER MUSIC"}
	var sections := {"ost": [], "film": [], "folder": []}
	var have := {}
	for a in albums:
		sections[a.kind].append(a)
		have[a.game] = true
	# Games and films whose soundtrack isn't in your folders are listed greyed
	# out in their place, unless Hide missing is on.
	var order := {}
	for i in App.games.size():
		order[App.games[i].id] = i
	for i in App.films.size():
		order[App.films[i].id] = 100 + i
	if not App.hide_missing():
		for g in App.games:
			if not have.has(g.id):
				sections.ost.append({"missing": true, "game": g.id})
		for f in App.films:
			if not have.has(f.id):
				sections.film.append({"missing": true, "game": f.id})
		for k in ["ost", "film"]:
			sections[k].sort_custom(func(a, b): return int(order.get(a.game, 999)) < int(order.get(b.game, 999)))
	for kind in ["ost", "film", "folder"]:
		if sections[kind].is_empty():
			continue
		_albums.add_child(Style.margin(Style.label(heads[kind], "Caps"), 0, 12, 0, 4))
		for a in sections[kind]:
			var g: Dictionary = App.game(a.game) if a.game != "" else {}
			var gname := str(g.get("title", "")) + (" (%s)" % g.subtitle if g.has("subtitle") else "")
			if a.get("missing", false):
				var mb := Style.button(gname, "", Callable())
				mb.alignment = HORIZONTAL_ALIGNMENT_LEFT
				mb.custom_minimum_size.y = 34
				mb.disabled = true
				mb.tooltip_text = "Not in your soundtrack folders"
				mb.add_theme_color_override("font_disabled_color", Style.INK_3)
				_albums.add_child(mb)
				continue
			# Soundtracks are listed by their game's name; the album's full name is in the header.
			_album_button(a.key, gname if kind != "folder" else str(a.title), a.tracks.size())
	if _current_key == "":
		_current_key = albums[0].key if not albums.is_empty() else "fav"
	_open(_current_key)


func _album_button(key: String, title: String, n: int) -> void:
	var b := Style.button("", "", func(): _open(key))
	b.set_meta("sfx", "move")
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.text = "%s   %d" % [title, n] if n > 0 else title
	b.custom_minimum_size.y = 34
	b.set_meta("key", key)
	b.clip_text = true
	b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_albums.add_child(b)


func _list_for(key: String) -> Array:
	var lib = App.svc("music")
	if key == "fav":
		return lib.favorites()
	if key.begins_with("pl:"):
		return lib.playlist_tracks(key.substr(3))
	for a in lib.albums():
		if a.key == key:
			return a.tracks
	return []


func _open(key: String) -> void:
	_current_key = key
	for b in _albums.get_children():
		if b is Button:
			b.add_theme_color_override("font_color", Style.INK if b.get_meta("key", "") == key else Style.INK_2)
	var lib = App.svc("music")
	_current_list = _list_for(key)
	var title := "Favourites" if key == "fav" else key.substr(3) if key.begins_with("pl:") else ""
	if title == "":
		for a in lib.albums():
			if a.key == key:
				title = a.title
	_album_title.text = title
	var album := {}
	for a in lib.albums():
		if a.key == key:
			album = a
	_cover.visible = str(album.get("cover", "")) != ""
	if _cover.visible:
		_cover.load_source(album.cover)
	_album_kind_game = album.get("game", "")
	var total := 0.0
	for t in _current_list:
		total += float(t.get("seconds", 0.0))
	var bits := []
	if album.get("kind", "") in ["ost", "film"]:
		# Main artist and year from the tags, e.g. "Akira Yamaoka · 2001".
		var artists := {}
		var year := ""
		for t in _current_list:
			var ar := str(t.get("artist", "")).strip_edges()
			if ar != "":
				artists[ar.to_lower()] = [int(artists.get(ar.to_lower(), [0, ar])[0]) + 1, ar]
			if year == "" and str(t.get("year", "")) != "":
				year = str(t.year)
		var top := [0, ""]
		for k in artists:
			if artists[k][0] > top[0]:
				top = artists[k]
		if top[1] != "":
			bits.append(_nice(str(top[1])))
		if year != "":
			bits.append(year)
	if not _current_list.is_empty():
		bits.append("%d track%s" % [_current_list.size(), "" if _current_list.size() == 1 else "s"])
		bits.append("%d min" % int(total / 60.0))
	_album_sub.text = "  ·  ".join(bits) if not bits.is_empty() else "Nothing here yet."
	for c in _album_actions.get_children():
		c.queue_free()
	if not _current_list.is_empty():
		_album_actions.add_child(Style.button("Play", "Primary", func(): Jukebox.play_list(_current_list, 0)))
		_album_actions.add_child(Style.button("Shuffle", "Ghost", func():
			Jukebox.shuffle = true
			Jukebox.play_list(_current_list, randi() % _current_list.size())))
	if key.begins_with("pl:"):
		_album_actions.add_child(Style.button("Delete playlist", "", func():
			main.confirm("Delete the playlist \"%s\"?" % key.substr(3), "Delete", func():
				lib.delete_playlist(key.substr(3))
				_current_key = "fav"
				_fill_albums())))
	_fill_tracks()
	if visible:
		_show_art()


func _fill_tracks() -> void:
	for c in _tracks.get_children():
		c.queue_free()
	_rows.clear()
	var lib = App.svc("music")
	var last_group := ""
	for i in _current_list.size():
		var t: Dictionary = _current_list[i]
		var g: String = t.get("group", "")
		if g != "" and g != last_group:
			var gl := Style.label(g.to_upper(), "Caps")
			_tracks.add_child(Style.margin(gl, 12, 16, 0, 6))
			last_group = g
		_tracks.add_child(_track_row(t, i))


func _track_row(t: Dictionary, i: int) -> Control:
	var lib = App.svc("music")
	var b := Button.new()
	b.custom_minimum_size.y = 40
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.pressed.connect(func(): Jukebox.play_list(_current_list, i))
	var h := Style.hbox(16)
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 12
	h.offset_right = -8
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var num := Style.label("%02d" % (i + 1), "Small")
	num.custom_minimum_size.x = 26
	num.mouse_filter = Control.MOUSE_FILTER_IGNORE
	num.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(num)
	var name := Style.label(lib.title_of(t))
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name.clip_text = true
	name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	h.add_child(name)
	if _current_key == "fav" or _current_key.begins_with("pl:") or str(t.get("artist", "")) != "":
		var al := Style.label(t.get("album", "") if (_current_key == "fav" or _current_key.begins_with("pl:")) else _nice(str(t.artist)), "Small")
		al.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		al.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(al)
	var dur := Style.label(_fmt(float(t.get("seconds", 0.0))) if float(t.get("seconds", 0.0)) > 0 else "", "Small")
	dur.custom_minimum_size.x = 48
	dur.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	dur.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dur.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(dur)
	b.add_child(h)
	var row := Style.hbox(4)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(b)
	var is_fav: bool = lib.is_favorite(t.id)
	var fav := Style.icon_button("heart", "Remove from favourites" if is_fav else "Add to favourites", func():
		lib.toggle_favorite(t.id)
		_fill_albums(), "", "", 16)
	if is_fav:
		fav.icon = Style.icon("heart", 16, Style.ACCENT_TEXT)
		fav.add_theme_color_override("icon_normal_color", Style.ACCENT_TEXT)
	fav.custom_minimum_size = Vector2(36, 36)
	row.add_child(fav)
	var more := MenuButton.new()
	more.icon = Style.icon("more-horizontal", 16, Color.WHITE)
	more.flat = true
	more.tooltip_text = "More"
	more.accessibility_name = "More"
	more.custom_minimum_size = Vector2(36, 36)
	var pm := more.get_popup()
	pm.add_item("Add to a new playlist…", 0)
	var names: Array = lib.playlists().keys()
	for j in names.size():
		pm.add_item("Add to " + names[j], 10 + j)
	if _current_key.begins_with("pl:"):
		pm.add_item("Remove from this playlist", 1)
	pm.add_item("Rename…", 2)
	pm.id_pressed.connect(func(id):
		if id == 0:
			_prompt("New playlist", "Name", "", func(n):
				if n != "":
					lib.add_to_playlist(n, t.id)
					_fill_albums())
		elif id == 1:
			lib.remove_from_playlist(_current_key.substr(3), t.id)
			_fill_albums()
		elif id == 2:
			_prompt("Rename track", "Title", lib.title_of(t), func(n):
				lib.rename_track(t.id, n)
				_fill_tracks())
		elif id >= 10:
			lib.add_to_playlist(names[id - 10], t.id)
			App.notify("Added to %s." % names[id - 10])
			_fill_albums())
	row.add_child(more)
	_rows[t.id] = name
	return row


func _prompt(title: String, label: String, value: String, cb: Callable) -> void:
	var v := Style.vbox(14)
	v.add_child(Style.label(title, "H2"))
	var e := LineEdit.new()
	e.text = value
	e.placeholder_text = label
	v.add_child(e)
	var row := Style.hbox(8)
	row.alignment = BoxContainer.ALIGNMENT_END
	var m: Control
	row.add_child(Style.button("Cancel", "Ghost", func(): m.queue_free()))
	var ok := func():
		m.queue_free()
		cb.call(e.text.strip_edges())
	row.add_child(Style.button("Save", "Primary", ok))
	e.text_submitted.connect(func(_t): ok.call())
	v.add_child(row)
	m = main.open_modal(v, 460)
	e.grab_focus.call_deferred()


# ------------------------------------------------------------------ player
func _player_bar() -> Control:
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.03, 0.035, 0.9)
	sb.border_color = Color(1, 1, 1, 0.06)
	sb.border_width_top = 1
	sb.content_margin_left = 44
	sb.content_margin_right = 44
	sb.content_margin_top = 14
	sb.content_margin_bottom = 14
	panel.add_theme_stylebox_override("panel", sb)
	panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	panel.offset_top = -92
	var h := Style.hbox(18)
	var info := Style.vbox(2)
	info.custom_minimum_size.x = 300
	_np_title = Style.label("Nothing playing", "Meta")
	_np_title.add_theme_color_override("font_color", Style.INK)
	_np_title.clip_text = true
	_np_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_np_album = Style.label("", "Small")
	info.add_child(_np_title)
	info.add_child(_np_album)
	h.add_child(info)
	h.add_child(Style.icon_button("skip-back", "Previous track", func(): Jukebox.prev()))
	_play = Style.icon_button("play", "Play", func():
		if Jukebox.current.is_empty() and not _current_list.is_empty():
			Jukebox.play_list(_current_list, 0)
		else:
			Jukebox.toggle())
	_play.theme_type_variation = "Ghost"
	_play.add_theme_constant_override("icon_max_width", 20)
	_play.custom_minimum_size = Vector2(52, 44)
	h.add_child(_play)
	h.add_child(Style.icon_button("skip-forward", "Next track", func(): Jukebox.next()))
	var mid := Style.vbox(4)
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_seek = HSlider.new()
	_seek.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_seek.step = 0.1
	_seek.drag_started.connect(func(): _dragging = true)
	_seek.drag_ended.connect(func(_c):
		_dragging = false
		Jukebox.seek(_seek.value))
	mid.add_child(_seek)
	_time = Style.label("0:00 / 0:00", "Small")
	mid.add_child(_time)
	h.add_child(mid)
	_shuffle = Style.button("Shuffle", "", func():
		Jukebox.set_shuffle(not Jukebox.shuffle)
		_sync_player())
	h.add_child(_shuffle)
	_repeat = Style.button("Repeat all", "", func():
		Jukebox.repeat = {"all": "one", "one": "off", "off": "all"}[Jukebox.repeat]
		_sync_player())
	h.add_child(_repeat)
	_layers = Style.button("Layers", "", _layers_menu)
	_layers.tooltip_text = "This track is made of layers the game mixes in and out. Choose which to hear."
	h.add_child(_layers)
	var vol := HSlider.new()
	vol.min_value = 0
	vol.max_value = 1
	vol.step = 0.01
	vol.value = float(App.settings.get("volume", 0.8))
	vol.custom_minimum_size.x = 110
	vol.value_changed.connect(func(x): App.set_setting("volume", x))
	h.add_child(vol)
	panel.add_child(h)
	return panel


func _sync_player() -> void:
	var t: Dictionary = Jukebox.current
	var lib = App.svc("music")
	_np_title.text = lib.title_of(t) if not t.is_empty() else "Nothing playing"
	_np_album.text = "Preparing…" if Jukebox.preparing else t.get("album", "")
	_play.icon = Style.icon("pause" if Jukebox.playing else "play", 20, Color.WHITE)
	_play.tooltip_text = "Pause" if Jukebox.playing else "Play"
	_play.accessibility_name = _play.tooltip_text
	_shuffle.add_theme_color_override("font_color", Style.INK if Jukebox.shuffle else Style.INK_3)
	_repeat.text = {"all": "Repeat all", "one": "Repeat one", "off": "No repeat"}[Jukebox.repeat]
	_layers.visible = t.get("kind", "") == "aix"
	for id in _rows:
		var r: Label = _rows[id]
		if is_instance_valid(r):
			r.add_theme_color_override("font_color", Style.color_hex(App.game(t.get("game", "")).get("accent", ""), Style.INK) if id == t.get("id", "") else Style.INK)
	if visible:
		_show_art()


func _layers_menu() -> void:
	var n: int = Jukebox._decoders.size()
	if n <= 1:
		return
	var v := Style.vbox(10)
	v.add_child(Style.label("Layers", "H2"))
	v.add_child(Style.label("The game fades these in and out as you play. All of them together is the full piece.", "Small", true))
	var cur: Array = Jukebox.current.get("layers", [])
	var boxes := []
	for i in n:
		var c := CheckBox.new()
		c.text = "Layer %d" % (i + 1)
		c.button_pressed = cur.is_empty() or cur.has(i)
		boxes.append(c)
		v.add_child(c)
	var m: Control
	v.add_child(Style.button("Apply", "Primary", func():
		var sel := []
		for i in boxes.size():
			if boxes[i].button_pressed:
				sel.append(i)
		Jukebox.set_layers([] if sel.size() == n else sel)
		m.queue_free()))
	m = main.open_modal(v, 420)
