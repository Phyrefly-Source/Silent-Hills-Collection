extends Control
## Ctrl+K: one box to go anywhere and do anything in the launcher.
## Type a few letters of a game, film, comic, album or action (letters in
## order, not necessarily together: "sh2r" finds "Silent Hill 2 (2024)").
## ↑ ↓ choose, Enter runs it, Esc closes. Shortcuts are shown beside the
## commands that have one, so they can be learnt from here.

var main: Control
var _field: LineEdit
var _list: VBoxContainer
var _items: Array = []      # [{title, hint, keys, words, run}]
var _shown: Array = []
var _sel := 0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var scrim := ColorRect.new()
	scrim.color = Color(Style.BG, 0.7)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed: close())
	add_child(scrim)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", Style.raised_box(Style.SPACE_S, Style.SPACE_S))
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	panel.offset_top = 120
	panel.offset_left = -320
	panel.offset_right = 320
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	add_child(panel)
	var v := Style.vbox(Style.SPACE_S)
	panel.add_child(v)
	var row := Style.hbox(Style.SPACE_S)
	var ic := TextureRect.new()
	ic.texture = Style.icon("search", 20, Style.INK_3)
	ic.custom_minimum_size = Vector2(20, 20)
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(Style.margin(ic, Style.SPACE_S, 0, 0, 0))
	_field = LineEdit.new()
	_field.placeholder_text = "Go to a game, film, comic or album, or run a command"
	_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_field.accessibility_name = "Search commands"
	var flat := StyleBoxEmpty.new()
	flat.content_margin_top = 10
	flat.content_margin_bottom = 10
	_field.add_theme_stylebox_override("normal", flat)
	_field.add_theme_stylebox_override("focus", flat)
	_field.add_theme_font_size_override("font_size", 18)
	_field.text_changed.connect(func(_t): _filter())
	_field.gui_input.connect(_keys)
	row.add_child(_field)
	v.add_child(row)
	var sep := ColorRect.new()
	sep.color = Style.LINE
	sep.custom_minimum_size.y = 1
	v.add_child(sep)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 380
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_list = Style.vbox(0)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	v.add_child(scroll)
	_collect()
	_filter()
	_field.grab_focus.call_deferred()


func close() -> void:
	queue_free()


func _add(title: String, hint: String, run: Callable, keys: String = "", words: String = "") -> void:
	_items.append({"title": title, "hint": hint, "keys": keys, "words": (title + " " + words).to_lower(),
		"initials": initials(title), "run": run})


## "Silent Hill 2 (2024)" -> "sh22024": typing a game's initials finds it.
static func initials(t: String) -> String:
	var out := ""
	for w in t.to_lower().replace(":", " ").replace("(", " ").replace(")", " ").split(" ", false):
		out += w if w.is_valid_int() else w.left(1)
	return out


func _collect() -> void:
	var m := main
	_add("News", "Section", func(): m.show_page("news"), "Ctrl 1", "sales deals headlines announcements")
	_add("Games", "Section", func(): m.show_page("games"), "Ctrl 2")
	_add("Films", "Section", func(): m.show_page("films"), "Ctrl 3", "movies")
	_add("Comics", "Section", func(): m.show_page("comics"), "Ctrl 4")
	_add("Soundtracks", "Section", func(): m.show_page("music"), "Ctrl 5", "music ost albums")
	_add("Concept Art", "Section", func(): m.show_page("concept"), "Ctrl 6", "artwork pictures gallery")
	_add("Profile", "Profile", func(): m.open_profile(), "", "account user favourites playtime")
	_add("Check for Silent Hill news and sales", "News", func():
		m.show_page("news")
		App.svc("news").refresh(false, true), "", "refresh deals")
	_add("Settings", "Section", func(): m.open_settings(), "Ctrl ,", "options preferences")
	_add("Look for games now", "Library", func(): m.scan_everything(false), "", "scan search refresh")
	var rm: bool = App.settings.get("reduce_motion", false)
	_add("Turn reduced motion %s" % ("off" if rm else "on"), "Settings", func(): App.set_setting("reduce_motion", not rm), "", "animation accessibility")
	for g in App.games:
		var id: String = g.id
		var t := str(g.title) + ((" (%s)" % g.subtitle) if str(g.get("subtitle", "")) != "" else "")
		_add(t, "Game", func():
			m.show_page("games")
			m._pages.games.call("select", id), "", str(int(g.get("year", 0))))
		_add("Achievements: " + t, "Game", func():
			m.show_page("games")
			m._pages.games.call("select", id)
			m._pages.games.call("_open_drawer", "achievements"), "", "trophies")
		_add("Concept art: " + t, "Concept Art", func():
			m.show_page("concept")
			m._pages.concept.call("open_game", id), "", "pictures")
	for f in App.films:
		var fid: String = f.id
		_add("%s (%d)" % [f.title, int(f.get("year", 0))], "Film", func():
			m.show_page("films")
			m._pages.films.call("select", fid), "", "movie")
	for a in App.svc("music").albums():
		var key: String = a.key
		_add(str(a.title), "Album", func():
			m.show_page("music")
			m._pages.music.call("_open", key), "", "soundtrack")
	for s in App.svc("comics").shelf():
		var sid: String = s.entry.id
		if s.copies.is_empty():
			continue
		_add(str(s.entry.title), "Comic", func():
			m.show_page("comics")
			m._pages.comics.call("open_series", sid), "", "comic")


## Letters in order: a score that prefers starts of words and short titles.
static func score(q: String, words: String) -> float:
	if q == "":
		return 1.0
	var i := 0
	var s := 0.0
	var last := -2
	for ch in q:
		if ch == " ":
			continue
		var k := words.find(ch, i)
		if k < 0:
			return -1.0
		s += 3.0 if k == 0 or words[k - 1] == " " else (2.0 if k == last + 1 else 1.0)
		last = k
		i = k + 1
	return s - words.length() * 0.01


func _filter() -> void:
	var q := _field.text.strip_edges().to_lower()
	var scored := []
	for it in _items:
		var s := score(q, it.words)
		if q != "" and it.words.contains(q):
			s += 20.0
		if q != "" and str(it.initials).begins_with(q.replace(" ", "")):
			s += 15.0 + (5.0 if str(it.initials) == q.replace(" ", "") else 0.0)
		if s >= 0.0:
			scored.append([s, it])
	if q != "":
		scored.sort_custom(func(a, b): return a[0] > b[0])
	_shown = scored.slice(0, 40).map(func(x): return x[1])
	_sel = 0
	_render()


func _render() -> void:
	for c in _list.get_children():
		c.queue_free()
	if _shown.is_empty():
		_list.add_child(Style.margin(Style.label("Nothing matches \"%s\". Try fewer letters." % _field.text, "Meta", true), Style.SPACE_M, Style.SPACE_M, Style.SPACE_M, Style.SPACE_M))
		return
	for i in _shown.size():
		var it: Dictionary = _shown[i]
		var b := Button.new()
		b.flat = false
		b.custom_minimum_size.y = Style.TARGET
		b.focus_mode = Control.FOCUS_NONE
		b.set_meta("sfx", "select")
		var h := Style.hbox(Style.SPACE_M)
		h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		h.offset_left = Style.SPACE_M
		h.offset_right = -Style.SPACE_M
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var t := Style.label(it.title)
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		t.clip_text = true
		t.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		t.add_theme_font_size_override("font_size", 15)
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(t)
		var hint := Style.label(it.hint, "Small")
		hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(hint)
		if it["keys"] != "":
			var k := Style.label(it["keys"], "Caps")
			k.mouse_filter = Control.MOUSE_FILTER_IGNORE
			h.add_child(k)
		b.add_child(h)
		if i == _sel:
			b.add_theme_stylebox_override("normal", Style._box(Style.HOVER, Style.RADIUS, 0, 0))
			t.add_theme_color_override("font_color", Style.INK)
		b.mouse_entered.connect(func():
			_sel = i
			_render.call_deferred())
		b.pressed.connect(func(): _run(i))
		_list.add_child(b)


func _run(i: int) -> void:
	if i < 0 or i >= _shown.size():
		return
	var run: Callable = _shown[i].run
	close()
	run.call()


func _keys(e: InputEvent) -> void:
	if not (e is InputEventKey and e.pressed):
		return
	match e.keycode:
		KEY_DOWN:
			_sel = mini(_sel + 1, _shown.size() - 1)
			_render()
			_field.accept_event()
		KEY_UP:
			_sel = maxi(_sel - 1, 0)
			_render()
			_field.accept_event()
		KEY_ENTER, KEY_KP_ENTER:
			_run(_sel)
			_field.accept_event()
		KEY_ESCAPE:
			close()
			_field.accept_event()
