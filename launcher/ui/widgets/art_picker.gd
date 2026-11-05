extends Control
## Picture picker for a game's (or film's) background or logo.
## Sources, one tab each: official art (Steam, Silent Hill Memories),
## SteamGridDB (with your free API key) and a web image search. Pictures can
## also come from disk, a pasted link, or be dropped onto the window.

const NetImage := preload("res://ui/widgets/net_image.gd")

var main: Control
var game_id := ""
var kind := "hero"          # "hero" (background) or "logo"

var _tabs := {}
var _tab := ""
var _body: VBoxContainer
var _grid: GridContainer
var _status: Label
var _query: LineEdit
var _token := 0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var scrim := ColorRect.new()
	scrim.color = Color(0, 0, 0, 0.72)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(scrim)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.05, 0.055, 0.985)
	sb.border_color = Color(1, 1, 1, 0.08)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(28)
	panel.add_theme_stylebox_override("panel", sb)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 70
	panel.offset_right = -70
	panel.offset_top = 50
	panel.offset_bottom = -50
	add_child(panel)
	var v := Style.vbox(14)
	panel.add_child(v)

	var head := Style.hbox(12)
	var t := Style.label("Choose a %s for %s" % ["background" if kind == "hero" else "logo", App.entry(game_id).get("title", game_id)], "H1")
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.clip_text = true
	t.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	head.add_child(t)
	head.add_child(Style.button("Close", "", queue_free))
	v.add_child(head)

	var tabs := Style.hbox(6)
	for k in [["official", "Official art"], ["sgdb", "SteamGridDB"], ["web", "Web search"]]:
		var key: String = k[0]
		var b := Style.button(k[1], "Nav", func(): _show_tab(key))
		b.toggle_mode = true
		_tabs[key] = b
		tabs.add_child(b)
	v.add_child(tabs)

	_body = Style.vbox(10)
	v.add_child(_body)
	_status = Style.label("", "Meta", true)
	v.add_child(_status)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_grid = GridContainer.new()
	_grid.add_theme_constant_override("h_separation", 12)
	_grid.add_theme_constant_override("v_separation", 12)
	scroll.add_child(_grid)
	v.add_child(scroll)

	# Your own picture: from disk, from a link, or dropped onto the window.
	var foot := Style.hbox(10)
	foot.add_child(Style.button("Use a picture…", "Ghost", func():
		main.choose_path("Choose a picture", "file", PackedStringArray(["*.png,*.jpg,*.jpeg,*.webp ; Pictures"]), func(p):
			if p != "":
				_use_file(p))))
	var link := LineEdit.new()
	link.placeholder_text = "…or paste a picture's web address"
	link.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	link.text_submitted.connect(func(s): _use_url(s.strip_edges()))
	foot.add_child(link)
	foot.add_child(Style.button("Use link", "", func(): _use_url(link.text.strip_edges())))
	foot.add_child(Style.button("Automatic", "", func():
		App.svc("art").choose(game_id, kind, "")
		App.notify("Back to the automatic %s." % ("background" if kind == "hero" else "logo"))
		queue_free()))
	v.add_child(foot)
	var hint := Style.label("You can also drop a picture from your computer onto this window.", "Small")
	v.add_child(hint)

	get_window().files_dropped.connect(_on_drop)
	resized.connect(_columns)
	_show_tab("official")


func _exit_tree() -> void:
	if get_window().files_dropped.is_connected(_on_drop):
		get_window().files_dropped.disconnect(_on_drop)


func _unhandled_key_input(e: InputEvent) -> void:
	if e.pressed and e.keycode == KEY_ESCAPE:
		queue_free()
		get_viewport().set_input_as_handled()


func _columns() -> void:
	var w := size.x - 140 - 56
	var tile := 300 if kind == "hero" else 240
	_grid.columns = maxi(1, int((w + 12) / (tile + 12)))


func _show_tab(key: String) -> void:
	_tab = key
	_token += 1
	for k in _tabs:
		_tabs[k].button_pressed = k == key
	for c in _body.get_children():
		c.queue_free()
	_clear()
	_columns()
	if key != "web":
		_skeletons()
	var art = App.svc("art")
	match key:
		"official":
			_status.text = "Looking for official art…"
			var tok := _token
			art.official_candidates(game_id, kind, func(list: Array):
				if tok == _token:
					_fill(list, "No official %s found for this one. Try SteamGridDB or a web search." % ("art" if kind == "hero" else "logos")))
		"sgdb":
			if not art.has_key():
				_sgdb_key_form()
				return
			_status.text = "Looking on SteamGridDB…"
			var tok := _token
			art.sgdb_candidates(game_id, kind, func(list: Array):
				if tok == _token:
					_fill(list, "Nothing found on SteamGridDB."))
		"web":
			var row := Style.hbox(8)
			_query = LineEdit.new()
			_query.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var title: String = App.entry(game_id).get("title", "")
			_query.text = title + (" key art wallpaper" if kind == "hero" else " logo")
			_query.text_submitted.connect(func(_s): _web_search())
			row.add_child(_query)
			row.add_child(Style.button("Search", "Primary", _web_search))
			row.add_child(Style.button("Search in browser", "", func(): OS.shell_open(App.svc("image_search").browser_url(_query.text))))
			_body.add_child(row)
			_web_search()


func _sgdb_key_form() -> void:
	_status.text = ""
	_body.add_child(Style.label("SteamGridDB has thousands of official and community pictures. It needs a free API key from your SteamGridDB account (sign in with Steam, then Preferences → API).", "Body", true))
	var row := Style.hbox(8)
	var key := LineEdit.new()
	key.placeholder_text = "Paste your API key"
	key.secret = true
	key.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(key)
	row.add_child(Style.button("Get a free key", "", func(): OS.shell_open("https://www.steamgriddb.com/profile/preferences/api")))
	row.add_child(Style.button("Save", "Primary", func():
		if key.text.strip_edges() != "":
			App.set_setting("sgdb_key", key.text.strip_edges())
			_show_tab("sgdb")))
	_body.add_child(row)


func _web_search() -> void:
	if _query == null:
		return
	_token += 1
	var tok := _token
	_clear()
	_skeletons()
	_status.text = "Searching…"
	App.svc("image_search").search(_query.text, "wide" if kind == "hero" else "logo", func(list: Array, err: String):
		if tok != _token:
			return
		if list.is_empty():
			_status.text = err + " You can search in your browser, then paste the picture's address below (right-click the picture → Copy image address)."
			return
		_fill(list.map(func(r): return {"url": r.url, "thumb": r.thumb, "author": r.source.get_slice("/", 2), "title": r.title,
			"size": "%d × %d" % [r.width, r.height] if r.width > 0 else ""}), ""))


## Static placeholders the size of the pictures while they're looked up.
func _skeletons() -> void:
	var tile := Vector2(300, 169) if kind == "hero" else Vector2(240, 120)
	for i in _grid.columns * 2:
		_grid.add_child(Style.skeleton(tile))


func _clear() -> void:
	for c in _grid.get_children():
		c.queue_free()


func _fill(list: Array, empty_text: String) -> void:
	_clear()
	_status.text = empty_text if list.is_empty() else "%d picture%s. Click one to use it." % [list.size(), "" if list.size() == 1 else "s"]
	var tile := Vector2(300, 169) if kind == "hero" else Vector2(240, 120)
	for c in list.slice(0, 60):
		var box := Style.vbox(4)
		var b := Button.new()
		b.custom_minimum_size = tile
		b.clip_contents = true
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.tooltip_text = "%s\n%s" % [c.get("title", ""), c.get("author", "")]
		var img: TextureRect = NetImage.new("", tile)
		img.max_px = 640
		img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED if kind == "hero" else TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		img.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		img.load_source(str(c.thumb))
		b.add_child(img)
		var url: String = c.url
		b.pressed.connect(func(): _use_url(url))
		box.add_child(b)
		var cap := Style.label(" · ".join([c.get("size", ""), c.get("author", "")].filter(func(x): return str(x) != "")), "Small")
		cap.custom_minimum_size.x = tile.x
		cap.clip_text = true
		cap.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		box.add_child(cap)
		_grid.add_child(box)


func _use_url(url: String) -> void:
	if not url.begins_with("http"):
		App.notify("That isn't a web address.", "error")
		return
	_status.text = "Getting the picture…"
	# Check it really is a picture before switching to it.
	Net.get_file(url, func(path: String):
		if not is_instance_valid(self):
			return
		if path == "" or Pictures.read(path) == null:
			_status.text = "That address didn't give a picture the launcher can read (JPG, PNG or WebP)."
			return
		App.svc("art").choose(game_id, kind, url)
		App.notify("%s updated." % ("Background" if kind == "hero" else "Logo"), "ok")
		queue_free())


func _use_file(path: String) -> void:
	if Pictures.read(path) == null:
		App.notify("That file isn't a picture the launcher can read.", "error")
		return
	App.svc("art").use_file(game_id, kind, path)
	App.notify("%s updated." % ("Background" if kind == "hero" else "Logo"), "ok")
	queue_free()


func _on_drop(files: PackedStringArray) -> void:
	if not is_inside_tree() or files.is_empty():
		return
	_use_file(files[0])
