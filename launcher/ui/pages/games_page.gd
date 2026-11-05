extends Control
## Games: the series in release order on the left, the selected game over its
## art on the right. One main button that always does the next useful thing
## (Play, Find game, Choose your dump, Build for PC, Install the patch), and a
## drawer for achievements, saves, mods and the game's connection.

var main: Control

var _list: VBoxContainer
var _rows := {}
var _selected := ""
var _info: VBoxContainer
var _art_generation := 0
var _logo: TextureRect
var _title: Label
var _meta: Label
var _blurb: Label
var _note: Label
var _stats: Label
var _primary: Button
var _secondary: HBoxContainer
var _drawer: PanelContainer
var _drawer_body: VBoxContainer
var _drawer_kind := ""
var _busy_find := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_list()
	_build_info()
	_build_drawer()
	App.library_changed.connect(func(id):
		if id == _selected:
			_refresh_info()
			_load_art(id)
			# An open Mods / Manage drawer shows connection and patch state: keep it current.
			if _drawer.visible and _drawer_kind in ["mods", "manage"]:
				_open_drawer(_drawer_kind))
	App.svc("art").art_ready.connect(func(id, kind):
		if id == _selected:
			_load_art(id))
	App.svc("runner").session_ended.connect(func(id, sec):
		if sec > 0:
			App.notify("%s closed after %s." % [App.game(id).title, App.fmt_duration(sec).to_lower()]))
	App.svc("achievements").changed.connect(func(id):
		if id == _selected:
			_refresh_info()
			if _drawer_kind == "achievements":
				_open_drawer("achievements"))
	App.svc("accounts").changed.connect(func():
		_style_rows()
		_refresh_info())
	App.svc("routes").build_log.connect(_on_build_log)
	App.svc("routes").build_done.connect(func(id, ok):
		App.notify(("%s is built and ready to play." if ok else "Building %s failed. The log is in the drawer.") % App.game(id).title, "ok" if ok else "error"))
	var start: String = App.library.get("selected", "")
	select(start if not App.game(start).is_empty() else App.games[0].id)


func on_shown() -> void:
	if _selected != "":
		_load_art(_selected)


# ------------------------------------------------------------------ list
func _build_list() -> void:
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	scroll.offset_left = 28
	scroll.offset_top = 24
	scroll.offset_bottom = -64
	scroll.custom_minimum_size.x = 330
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	add_child(scroll)
	_list = Style.vbox(0)
	_list.custom_minimum_size.x = 320
	scroll.add_child(_list)
	for g in App.games:
		var b := Button.new()
		b.custom_minimum_size = Vector2(320, 50)
		b.focus_mode = Control.FOCUS_ALL
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.pressed.connect(select.bind(g.id))
		b.set_meta("sfx", "move")
		var h := Style.hbox(14)
		h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		h.offset_left = 16
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var bar := ColorRect.new()
		bar.custom_minimum_size = Vector2(2, 22)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.color = Color(1, 1, 1, 0)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(bar)
		var name := Style.label(_short_title(g))
		name.add_theme_font_override("font", Style.serif)
		name.add_theme_font_size_override("font_size", 25)
		name.mouse_filter = Control.MOUSE_FILTER_IGNORE
		name.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(name)
		var star := TextureRect.new()
		star.texture = Style.icon("star", 14, Style.ACCENT_TEXT)
		star.custom_minimum_size = Vector2(14, 14)
		star.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		star.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		star.mouse_filter = Control.MOUSE_FILTER_IGNORE
		star.tooltip_text = "Favourite"
		h.add_child(star)
		var year := Style.label(("Remake · " if g.has("subtitle") else "") + str(int(g.year)), "Small")
		year.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		year.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(year)
		b.add_child(h)
		b.mouse_entered.connect(func(): _hover_row(g.id, true))
		b.mouse_exited.connect(func(): _hover_row(g.id, false))
		_list.add_child(b)
		_rows[g.id] = {"button": b, "bar": bar, "name": name, "year": year, "star": star}
	_style_rows()


## Numbered games keep "Silent Hill N"; the rest go by their subtitle.
static func _short_title(g: Dictionary) -> String:
	var t: String = g.title
	if RegEx.create_from_string("^Silent Hill \\d").search(t):
		return t.split(":")[0]
	if t.contains(": "):
		return t.split(": ", true, 1)[1]
	return t


func _hover_row(id: String, on: bool) -> void:
	if id != _selected:
		_rows[id].name.add_theme_color_override("font_color", Style.INK if on else _row_color(id))


## Readable at every level (contrast >= 4.5:1): games you have read brighter.
func _row_color(id: String) -> Color:
	var s: Dictionary = App.svc("routes").status(id)
	return Style.INK_2 if s.connected else Style.INK_3


func _style_rows() -> void:
	for id in _rows:
		var r: Dictionary = _rows[id]
		var on: bool = id == _selected
		r.name.add_theme_color_override("font_color", Style.INK if on else _row_color(id))
		r.year.visible = on
		r.star.visible = App.svc("accounts").is_favourite(id)
		r.bar.color = Color(Style.accent_text(Style.color_hex(App.game(id).get("accent", ""))), 1.0 if on else 0.0)


func _unhandled_key_input(e: InputEvent) -> void:
	if not visible or not e.pressed:
		return
	var idx := App.games.map(func(g): return g.id).find(_selected)
	if e.keycode == KEY_DOWN and idx < App.games.size() - 1:
		select(App.games[idx + 1].id)
		accept_event()
	elif e.keycode == KEY_UP and idx > 0:
		select(App.games[idx - 1].id)
		accept_event()
	elif e.keycode == KEY_ENTER and _primary and not _primary.disabled:
		_primary.pressed.emit()
	elif e.keycode == KEY_ESCAPE and _drawer.visible:
		_close_drawer()


func select(id: String) -> void:
	if App.game(id).is_empty():
		return
	_selected = id
	App.library.selected = id
	App.mark_dirty("library")
	_style_rows()
	_load_art(id)
	var g := App.game(id)
	main.backdrop.set_atmosphere(g.get("fx", "mist"), Style.color_hex(g.get("accent", "")))
	_refresh_info()
	if _drawer.visible:
		_open_drawer(_drawer_kind)


func _load_art(id: String) -> void:
	_art_generation += 1
	var generation := _art_generation
	var art = App.svc("art")
	art.get_texture(id, "hero", func(tex):
		if id == _selected and visible:
			main.backdrop.show_art(tex, 0.9))
	_logo.texture = null
	art.get_texture(id, "logo", func(tex):
		if id == _selected and generation == _art_generation:
			_logo.texture = tex
			_logo.visible = tex != null
			_title.visible = tex == null
			if tex:
				# Size the box to the logo so it sits right on the text below.
				var aspect: float = float(tex.get_width()) / maxf(1.0, tex.get_height())
				var w := minf(460.0, 140.0 * aspect)
				_logo.custom_minimum_size = Vector2(w, w / aspect))


# ------------------------------------------------------------------ info
func _build_info() -> void:
	_info = Style.vbox(14)
	_info.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_info.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_info.offset_left = 420
	_info.offset_bottom = -72
	_info.custom_minimum_size.x = 620
	add_child(_info)

	_logo = TextureRect.new()
	_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	_logo.custom_minimum_size = Vector2(460, 150)
	_logo.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_logo.visible = false
	_info.add_child(_logo)
	_title = Style.label("", "Title", true)
	_title.custom_minimum_size.x = 560
	_info.add_child(_title)
	_meta = Style.label("", "Meta")
	_info.add_child(_meta)
	_blurb = Style.label("", "Body", true)
	_blurb.custom_minimum_size.x = 560
	_info.add_child(_blurb)
	_info.add_child(Style.spacer(6))
	_stats = Style.label("", "Num")
	_info.add_child(_stats)
	var row := Style.hbox(10)
	_primary = Style.button("", "Primary", _do_primary)
	_primary.custom_minimum_size = Vector2(170, 48)
	_primary.add_theme_constant_override("icon_max_width", 18)
	row.add_child(_primary)
	_secondary = Style.hbox(8)
	row.add_child(_secondary)
	_info.add_child(row)
	_note = Style.label("", "Small", true)
	_note.custom_minimum_size.x = 560
	_info.add_child(_note)


func _refresh_info() -> void:
	var id := _selected
	var g := App.game(id)
	var gs := App.state(id)
	var s: Dictionary = App.svc("routes").status(id)
	_title.text = g.title + (" (%s)" % g.subtitle if g.has("subtitle") else "")
	_title.visible = _logo.texture == null
	# Year · the platform the launcher plays it from · how (Steam, GOG,
	# Enhanced Edition, Native PC Decomp …), from games.json "platform" / "tag".
	var plat: Array = g.get("platforms", [])
	var where: String = str(g.get("platform", "PC" if g.route.kind == "steam" else (plat[0] if not plat.is_empty() else "")))
	_meta.text = "  ·  ".join([str(int(g.year)), where, str(g.get("tag", s.label))].filter(func(x): return x != ""))
	_blurb.text = g.get("blurb", "")
	var bits := []
	var played: int = App.svc("accounts").playtime(id)
	if played > 0:
		bits.append("%s played" % App.fmt_duration(played))
	if int(gs.last_played) > 0:
		bits.append("Last played %s" % App.fmt_ago(int(gs.last_played)).to_lower())
	if App.svc("runner").is_running(id):
		bits.push_front("Playing now")
	_stats.text = "   ·   ".join(bits)
	_stats.visible = not bits.is_empty()
	_primary.text = s.primary.label
	_primary.icon = Style.icon({"play": "play", "steam_install": "download", "rebuild": "hard-drive", "install_patch": "download", "find": "search", "choose_dump": "folder-plus"}.get(s.primary.action, "play"), 18, Color.WHITE) if s.primary.action != "none" else null
	_primary.disabled = s.primary.action == "none"
	_primary.set_meta("action", s.primary.action)
	_note.text = s.note
	_note.visible = s.note != ""

	for c in _secondary.get_children():
		c.queue_free()
	# One secondary action (Achievements, or Browse when nothing is found);
	# the rest are quieter text buttons.
	var sum: Dictionary = App.svc("achievements").summary(id)
	if s.primary.action in ["find", "choose_dump"]:
		_secondary.add_child(_ghost("Browse…", _browse, "folder-plus"))
	var ach := _ghost("Achievements" + ("  %d / %d" % [sum.unlocked, sum.total] if sum.get("total", 0) > 0 else ""), func(): _open_drawer("achievements"), "trophy")
	ach.add_theme_font_override("font", Style.numeric)
	if s.primary.action in ["find", "choose_dump"]:
		ach.theme_type_variation = ""
	_secondary.add_child(ach)
	if s.connected and not g.get("saves", []).is_empty():
		_secondary.add_child(_text_btn("Saves", func(): _open_drawer("saves"), "hard-drive"))
	if s.connected and g.get("mods", false) and gs.path != "":
		var n: int = App.svc("mods").enabled_count(id)
		_secondary.add_child(_text_btn("Mods" + ("  %d" % n if n else ""), func(): _open_drawer("mods"), "folder-plus"))
	_secondary.add_child(_text_btn("Manage", func(): _open_drawer("manage"), "settings"))
	var fav: bool = App.svc("accounts").is_favourite(id)
	var fb := Style.icon_button("star", "Remove from favourites" if fav else "Add to favourites (up to three)", func():
		var why: String = App.svc("accounts").toggle_favourite(id)
		if why != "":
			App.notify(why), "", "", 18)
	fb.icon = Style.icon("star", 18, Style.ACCENT_TEXT if fav else Color.WHITE)
	fb.custom_minimum_size = Vector2(48, 48)
	_secondary.add_child(fb)
	_style_rows()


func _ghost(text: String, cb: Callable, icon_name: String = "") -> Button:
	var b := Style.icon_button(icon_name, text, cb, text, "Ghost", 18) if icon_name != "" else Style.button(text, "Ghost", cb)
	b.custom_minimum_size.y = 48
	return b


func _text_btn(text: String, cb: Callable, icon_name: String) -> Button:
	var b := Style.icon_button(icon_name, text, cb, text, "", 18)
	b.custom_minimum_size.y = 48
	return b


# ------------------------------------------------------------------ actions
func _do_primary() -> void:
	var id := _selected
	match str(_primary.get_meta("action", "")):
		"play":
			var err: String = App.svc("runner").play(id)
			if err != "":
				App.notify(err, "error")
				return
			Jukebox.pause()
			_refresh_info()   # the window itself is handled in main.gd (session_started)
		"find":
			_find(id)
		"choose_dump":
			_browse()
		"install_patch":
			var err: String = App.svc("routes").install_patch(id)
			App.notify(err if err != "" else "Installed. Enjoy your stay.", "error" if err != "" else "ok")
			_refresh_info()
		"rebuild":
			App.svc("routes").rebuild(id)
			_open_drawer("build")
			_refresh_info()
		"steam_install":
			OS.shell_open("steam://install/%s" % App.state(id).get("steam_appid", App.game(id).install.get("steam_appid", "")))


func _find(id: String) -> void:
	if _busy_find:
		return
	_busy_find = true
	_primary.text = "Looking…"
	_primary.disabled = true
	var scanner = App.svc("scanner")
	App.run(func(): return scanner.scan(id), func(res):
		_busy_find = false
		var n: int = main.apply_scan(res, true)
		if n == 0:
			App.notify("Couldn't find %s in the usual places. Browse to it instead." % App.game(id).title)
			_refresh_info()
			_browse()
		else:
			App.notify("Found %s." % App.game(id).title)
			App.svc("art").forget(id)
			_load_art(id)
			_refresh_info())


## Browse for whatever the game needs next: its folder, or the player's dump.
func _browse() -> void:
	var id := _selected
	var g := App.game(id)
	var s: Dictionary = App.svc("routes").status(id)
	if g.route.kind == "rebuild" and not s.playable:
		var kinds: Array = g.get("dump", {}).get("kinds", [])
		if kinds.has("folder"):
			main.choose_path("Choose the folder of your %s" % g.route.get("source", "dump"), "folder", PackedStringArray(), func(p):
				if p != "":
					_set_dump(id, p))
		else:
			var f := PackedStringArray(["*." + ";*.".join(kinds) + " ; Disc images"])
			main.choose_path("Choose your %s" % g.route.get("source", "dump").to_lower(), "file", f, func(p):
				if p != "":
					_set_dump(id, p))
	else:
		main.choose_path("Where is %s installed?" % g.title, "folder", PackedStringArray(), func(p):
			if p == "":
				return
			_set_folder(id, p))


func _set_dump(id: String, p: String) -> void:
	var g := App.game(id)
	if FileAccess.file_exists(p):
		var info := preload("res://core/scanner.gd").identify(p)
		var serials: Array = g.get("dump", {}).get("serials", [])
		if info.serial != "" and not serials.any(func(s): return info.serial.replace("_", "-").to_upper().begins_with(str(s).to_upper())):
			App.notify("That looks like %s, not %s. It's been set anyway." % [info.serial, g.title], "error")
	App.set_state(id, {"dump": p})
	App.notify("Dump connected.")


func _set_folder(id: String, p: String) -> void:
	var g := App.game(id)
	var detect: Array = g.get("install", {}).get("detect", [])
	var hit := ""
	for d in detect:
		if FileAccess.file_exists(p.path_join(d)):
			hit = p.path_join(d)
			break
	if hit == "" and not detect.is_empty():
		App.notify("%s isn't in that folder. It's been set anyway; choose the program under Manage." % ", ".join(detect), "error")
	var patch := {"path": p}
	if hit != "" and g.route.kind == "rebuild":
		patch.exe = hit
	App.set_state(id, patch)


# ------------------------------------------------------------------ drawer
func _build_drawer() -> void:
	_drawer = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.035, 0.035, 0.04, 0.94)
	sb.border_color = Color(1, 1, 1, 0.06)
	sb.border_width_left = 1
	sb.content_margin_left = 32
	sb.content_margin_right = 28
	sb.content_margin_top = 28
	sb.content_margin_bottom = 28
	_drawer.add_theme_stylebox_override("panel", sb)
	_drawer.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	_drawer.offset_left = -minf(680.0, size.x)
	_drawer.offset_top = 0
	_drawer.visible = false
	add_child(_drawer)
	var v := Style.vbox(16)
	var head := Style.hbox()
	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(fill)
	head.add_child(Style.button("Close", "", _close_drawer))
	v.add_child(head)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_drawer_body = Style.vbox(14)
	_drawer_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_drawer_body)
	v.add_child(scroll)
	_drawer.add_child(v)
	resized.connect(func(): _drawer.offset_left = -minf(680.0, size.x))


func _close_drawer() -> void:
	var tw := create_tween()
	tw.tween_property(_drawer, "modulate:a", 0.0, 0.15)
	tw.tween_callback(func(): _drawer.visible = false)
	create_tween().tween_property(_info, "modulate:a", 1.0, 0.18)
	_drawer_kind = ""


func _open_drawer(kind: String) -> void:
	if kind == "achievements":
		var av: Control = load("res://ui/widgets/achievements_view.gd").new()
		av.set("main", main)
		av.set("game_id", _selected)
		av.tree_exited.connect(func():
			if is_instance_valid(self):
				_refresh_info())
		main.modal_layer.add_child(av)
		return
	_drawer_kind = kind
	for c in _drawer_body.get_children():
		c.queue_free()
	create_tween().tween_property(_info, "modulate:a", 0.25, 0.18)
	if not _drawer.visible:
		_drawer.visible = true
		_drawer.modulate.a = 0.0
		create_tween().tween_property(_drawer, "modulate:a", 1.0, 0.18)
	var view: Control = load("res://ui/pages/game_drawer.gd").new()
	view.set("game_id", _selected)
	view.set("kind", kind)
	view.set("main", main)
	view.set("page", self)
	_drawer_body.add_child(view)


func _on_build_log(id: String, line: String) -> void:
	if id == _selected and _drawer_kind == "build" and _drawer_body.get_child_count() > 0:
		_drawer_body.get_child(0).call("append_log", line)


func refresh() -> void:
	_refresh_info()
