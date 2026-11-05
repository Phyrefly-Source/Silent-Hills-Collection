extends Control
## History: the series in order, and the threads that run through it.
## Left: the timeline (in-world order, or release order). Right: the chosen
## entry with its connections, or a thread with every entry it touches.
## Everything comes from res://data/history.json, so it can be edited freely.

var main: Control

var _data := {}
var _entries: Array = []        # as listed in the file, in-world order
var _by_id := {}
var _threads: Array = []
var _thread_by_id := {}
var _release_order := false
var _current := ""              # entry id, or "thread:<id>"

var _list: VBoxContainer
var _rows := {}
var _order_btn: Button
var _detail: VBoxContainer
var _scroll: ScrollContainer


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_load()

	var left := Style.vbox(6)
	left.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	left.offset_left = 44
	left.offset_top = 28
	left.offset_bottom = -24
	left.custom_minimum_size.x = 300
	add_child(left)
	left.add_child(Style.label("History", "H1"))
	var row := Style.hbox(8)
	_order_btn = Style.button("", "Ghost", func():
		_release_order = not _release_order
		_fill_list())
	row.add_child(_order_btn)
	left.add_child(row)
	left.add_child(Style.spacer(8))
	var ls := ScrollContainer.new()
	ls.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ls.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_list = Style.vbox(2)
	_list.custom_minimum_size.x = 290
	ls.add_child(_list)
	var lm := Style.margin(ls, -Style.SPACE_S, 0, 0, 0)
	lm.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(lm)

	_scroll = ScrollContainer.new()
	_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scroll.offset_left = 400
	_scroll.offset_right = -44
	_scroll.offset_top = 34
	_scroll.offset_bottom = -24
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)
	_detail = Style.vbox(14)
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_detail)

	_fill_list()


func on_shown() -> void:
	main.backdrop.set_atmosphere("mist", Color(0.45, 0.45, 0.48))
	if _current == "" and not _entries.is_empty():
		show_entry(_entries[0].id)


# ------------------------------------------------------------------ data
func _load() -> void:
	var txt := FileAccess.get_file_as_string("res://data/history.json")
	var parsed: Variant = JSON.parse_string(txt)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("history.json could not be read")
		return
	_data = parsed
	_entries = (_data.get("entries", []) as Array).duplicate()
	_entries.sort_custom(func(a, b): return int(a.get("order", 0)) < int(b.get("order", 0)))
	for e in _entries:
		_by_id[str(e.id)] = e
	_threads = _data.get("threads", [])
	for t in _threads:
		_thread_by_id[str(t.id)] = t


func _game_of(e: Dictionary) -> Dictionary:
	return App.game(str(e.get("game", ""))) if e.has("game") else {}


func _release_year(e: Dictionary) -> int:
	return int(_game_of(e).get("year", 0))


func _threads_of(entry_id: String) -> Array:
	var out := []
	for t in _threads:
		for a in t.get("appears", []):
			if str(a.entry) == entry_id:
				out.append({"thread": t, "note": str(a.get("note", ""))})
				break
	return out


# ------------------------------------------------------------------ left list
func _fill_list() -> void:
	for c in _list.get_children():
		c.queue_free()
	_rows.clear()
	_order_btn.text = "Release order" if not _release_order else "In-world order"
	_order_btn.tooltip_text = "Switch between the order the stories happen in and the order the games came out."

	var listed: Array = _entries.duplicate()
	if _release_order:
		listed.sort_custom(func(a, b):
			var ya := _release_year(a)
			var yb := _release_year(b)
			return ya < yb if ya != yb else int(a.get("order", 0)) < int(b.get("order", 0)))
		_list.add_child(Style.margin(Style.label("BY RELEASE", "Caps"), 0, 4, 0, 4))
		for e in listed:
			_add_row(e, str(_release_year(e)))
	else:
		_list.add_child(Style.margin(Style.label("THE STORY", "Caps"), 0, 4, 0, 4))
		for e in listed:
			if not bool(e.get("aside", false)):
				_add_row(e, str(e.get("when", "")))
		_list.add_child(Style.margin(Style.label("OUTSIDE THE TIMELINE", "Caps"), 0, 12, 0, 4))
		for e in listed:
			if bool(e.get("aside", false)):
				_add_row(e, "")

	_list.add_child(Style.margin(Style.label("THREADS", "Caps"), 0, 12, 0, 4))
	for t in _threads:
		var tid := str(t.id)
		var b := Style.button("", "", func(): show_thread(tid))
		b.set_meta("sfx", "move")
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size.y = 30
		b.clip_text = true
		b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		b.text = "%s   %d" % [str(t.name), (t.get("appears", []) as Array).size()]
		_rows["thread:" + tid] = b
		_list.add_child(b)
	_style_rows()


func _add_row(e: Dictionary, tag: String) -> void:
	var id := str(e.id)
	var b := Style.button("", "", func(): show_entry(id))
	b.set_meta("sfx", "move")
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size.y = 34
	b.clip_text = true
	b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	b.text = str(e.title) + ("   " + tag if tag != "" else "")
	_rows[id] = b
	_list.add_child(b)


func _style_rows() -> void:
	for key in _rows:
		var b: Button = _rows[key]
		b.add_theme_color_override("font_color", Style.INK if key == _current else Style.INK_2)


# ------------------------------------------------------------------ right side
func _clear_detail() -> void:
	for c in _detail.get_children():
		c.queue_free()
	_scroll.scroll_vertical = 0


func _para(text: String, variation: String = "Body") -> Label:
	var l := Style.label(text, variation, true)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


func _bullets(items: Array) -> VBoxContainer:
	var v := Style.vbox(4)
	for it in items:
		var h := Style.hbox(8)
		var dot := Style.label("•", "Meta")
		dot.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		h.add_child(dot)
		h.add_child(_para(str(it), "Meta"))
		v.add_child(h)
	return v


func _link(text: String, cb: Callable) -> Button:
	var b := Style.button(text, "", cb)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.set_meta("sfx", "move")
	return b


func show_entry(id: String) -> void:
	var e: Dictionary = _by_id.get(id, {})
	if e.is_empty():
		return
	_current = id
	_style_rows()
	_clear_detail()
	var g := _game_of(e)

	_detail.add_child(Style.label(str(e.title), "H1"))
	var when := str(e.get("when", ""))
	var meta := []
	if when != "":
		meta.append(when)
	if g.has("year"):
		meta.append("released %d" % int(g.year))
	if str(e.get("protagonist", "")) != "":
		meta.append(str(e.protagonist))
	_detail.add_child(_para("  ·  ".join(meta), "Meta"))
	if str(e.get("when_note", "")) != "":
		_detail.add_child(_para(str(e.when_note), "Small"))

	var actions := Style.hbox(10)
	if not g.is_empty():
		var gid := str(g.id)
		actions.add_child(Style.button("Open in Games", "Ghost", func():
			main.show_page("games")
			main.get("_pages").games.call("select", gid)))
	_detail.add_child(actions)

	_detail.add_child(Style.spacer(4))
	var summary := str(e.get("summary", ""))
	if summary == "" and not g.is_empty():
		summary = str(g.get("blurb", ""))
	_detail.add_child(_para(summary))
	if str(e.get("setting", "")) != "":
		_detail.add_child(Style.margin(Style.label("WHERE", "Caps"), 0, 10, 0, 0))
		_detail.add_child(_para(str(e.setting), "Meta"))
	var events: Array = e.get("events", [])
	if not events.is_empty():
		_detail.add_child(Style.margin(Style.label("WHAT HAPPENS", "Caps"), 0, 10, 0, 0))
		_detail.add_child(_bullets(events))

	var ties := _threads_of(id)
	_detail.add_child(Style.margin(Style.label("CONNECTIONS", "Caps"), 0, 10, 0, 0))
	if ties.is_empty():
		_detail.add_child(_para("None recorded yet. Add them to data/history.json.", "Small"))
	for tie in ties:
		var t: Dictionary = tie.thread
		var tid := str(t.id)
		var box := Style.vbox(2)
		box.add_child(_link(str(t.name), func(): show_thread(tid)))
		box.add_child(Style.margin(_para(str(tie.note), "Meta"), 12, 0, 0, 0))
		# Where else this thread goes, as links.
		var others := []
		for a in t.get("appears", []):
			if str(a.entry) != id and _by_id.has(str(a.entry)):
				others.append(str(_by_id[str(a.entry)].title))
		if not others.is_empty():
			box.add_child(Style.margin(_para("Also in: " + ", ".join(others), "Small"), 12, 0, 0, 0))
		_detail.add_child(box)


func show_thread(tid: String) -> void:
	var t: Dictionary = _thread_by_id.get(tid, {})
	if t.is_empty():
		return
	_current = "thread:" + tid
	_style_rows()
	_clear_detail()
	_detail.add_child(Style.label(str(t.name), "H1"))
	_detail.add_child(_para(str(t.get("kind", "")).capitalize(), "Meta"))
	_detail.add_child(Style.spacer(4))
	_detail.add_child(_para(str(t.get("desc", ""))))
	_detail.add_child(Style.margin(Style.label("APPEARS IN", "Caps"), 0, 10, 0, 0))
	# In the timeline's order, so the thread reads as a story.
	var rows: Array = (t.get("appears", []) as Array).duplicate()
	rows.sort_custom(func(a, b):
		var ea: Dictionary = _by_id.get(str(a.entry), {})
		var eb: Dictionary = _by_id.get(str(b.entry), {})
		return int(ea.get("order", 0)) < int(eb.get("order", 0)))
	for a in rows:
		var eid := str(a.entry)
		var e: Dictionary = _by_id.get(eid, {})
		if e.is_empty():
			continue
		var box := Style.vbox(2)
		var when := str(e.get("when", ""))
		box.add_child(_link(str(e.title) + ("   " + when if when != "" else ""), func(): show_entry(eid)))
		box.add_child(Style.margin(_para(str(a.get("note", "")), "Meta"), 12, 0, 0, 0))
		_detail.add_child(box)
