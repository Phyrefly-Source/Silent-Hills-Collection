extends Control
## Comics: every Silent Hill comic on a shelf. Opening a series shows its issues
## with your reading progress; an issue opens in the reader. Comics you don't
## have are still shown, so the shelf doubles as a checklist.

var main: Control
var _shelf_view: Control
var _series_view: Control
var _grid: GridContainer
var _count: Label
var _continue: Button
var _loaded := false
var _series_id := ""       # the open series, "" on the shelf


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shelf_view = _build_shelf()
	add_child(_shelf_view)
	_series_view = Control.new()
	_series_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_series_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_series_view.visible = false
	add_child(_series_view)
	App.svc("comics").scanned.connect(_refresh)
	var was := [App.hide_missing()]
	App.settings_changed.connect(func():
		if App.hide_missing() != was[0]:
			was[0] = App.hide_missing()
			_refresh())


func _build_shelf() -> Control:
	var root := Style.vbox(18)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 44
	root.offset_right = -44
	root.offset_top = 28
	root.offset_bottom = -24
	var head := Style.hbox(12)
	var titles := Style.vbox(4)
	titles.add_child(Style.label("Comics", "H1"))
	_count = Style.label("", "Meta")
	titles.add_child(_count)
	head.add_child(titles)
	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(fill)
	var comics = App.svc("comics")
	_continue = Style.button("", "Primary", func():
		var it: Dictionary = comics.continue_item()
		if not it.is_empty():
			_open(it))
	_continue.icon = Style.icon("book-open", 18, Color.WHITE)
	_continue.add_theme_constant_override("icon_max_width", 18)
	_continue.visible = false
	head.add_child(_continue)
	var hm: Button = App.missing_toggle()
	hm.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(hm)
	head.add_child(Style.button("Add comics…", "Ghost", func():
		main.choose_path("Choose a comic (.cbz, .zip, .cbr) or a folder of pages", "file",
			PackedStringArray(["*.cbz,*.zip,*.cbr,*.rar,*.cb7,*.7z,*.pdf ; Comics"]), func(p):
				if p != "":
					comics.add_path(p))))
	head.add_child(Style.button("Add a folder…", "", func():
		main.choose_path("Choose a folder with your comics", "folder", PackedStringArray(), func(p):
			if p != "":
				comics.add_path(p))))
	head.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	for c in head.get_children():
		if c is Button:
			c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	root.add_child(head)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_grid = GridContainer.new()
	_grid.columns = 6
	_grid.add_theme_constant_override("h_separation", 26)
	_grid.add_theme_constant_override("v_separation", 30)
	scroll.add_child(_grid)
	root.add_child(scroll)
	resized.connect(func(): _grid.columns = max(2, int((size.x - 88) / 206)))
	return root


func on_shown() -> void:
	main.backdrop.show_art(null)
	main.backdrop.set_atmosphere("mist", Color(0.5, 0.5, 0.5))
	if not _loaded:
		_loaded = true
		_refresh()
		App.svc("comics").scan()


func _refresh() -> void:
	_fill()
	if _series_id != "":
		open_series(_series_id)


func _fill() -> void:
	for c in _grid.get_children():
		c.queue_free()
	var comics = App.svc("comics")
	var shelf: Array = comics.shelf()
	var owned := shelf.filter(func(s): return not s.copies.is_empty()).size()
	_count.text = "%d on the shelf  ·  %d in your library" % [App.comics_catalogue.size(), owned]
	for s in shelf:
		if App.hide_missing() and s.copies.is_empty():
			continue
		_grid.add_child(_series_card(s))
	var cont: Dictionary = comics.continue_item()
	_continue.visible = not cont.is_empty()
	if _continue.visible:
		_continue.text = "Continue  " + _issue_name(cont, true)


# ------------------------------------------------------------------ shelf cards
func _series_card(s: Dictionary) -> Control:
	var e: Dictionary = s.entry
	var own: bool = not s.copies.is_empty()
	var comics = App.svc("comics")
	var sub := []
	if int(e.get("year", 0)) > 0:
		sub.append(str(int(e.year)))
	var total: int = maxi(int(e.get("issues", 0)), s.copies.size())
	if not own:
		sub.append("Not in your library")
	elif total > 1:
		var done: int = s.copies.filter(func(c): return comics.finished(c)).size()
		sub.append("%d of %d read" % [done, total] if done > 0 else "%d issue%s" % [total, "" if total == 1 else "s"])
	else:
		var it: Dictionary = s.copies[0]
		sub.append("Read" if comics.finished(it) else ("Page %d" % (comics.progress(it) + 1) if comics.started(it) else "Unread"))
	var frac := 0.0
	if own:
		for c in s.copies:
			frac += 1.0 if comics.finished(c) else comics.fraction(c)
		frac /= float(maxi(total, 1))
	var card := _card(e.title, "  ·  ".join(sub), s.copies[0] if own else {}, frac, own)
	if own:
		card.pressed.connect(func(): open_series(e.id))
	return card


## A cover card: the first page of `it` as the cover (or the title set like a
## spine), a caption, a sub line and a thin progress bar.
func _card(title: String, sub: String, it: Dictionary, frac: float, enabled: bool) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(180, 350)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if enabled else Control.CURSOR_ARROW
	b.focus_mode = Control.FOCUS_ALL if enabled else Control.FOCUS_NONE
	var v := Style.vbox(8)
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cover := Panel.new()
	cover.custom_minimum_size = Vector2(180, 270)
	cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cover.clip_contents = true
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.035)
	sb.border_color = Color(1, 1, 1, 0.16 if enabled else 0.08)
	sb.set_border_width_all(1)
	cover.add_theme_stylebox_override("panel", sb)
	var t := Style.label(title, "", true)
	t.add_theme_font_override("font", Style.serif_light)
	t.add_theme_font_size_override("font_size", 26)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	t.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	t.offset_left = 14
	t.offset_right = -14
	t.modulate.a = 0.8 if enabled else 0.35
	cover.add_child(t)
	if frac > 0.0:
		var track := ColorRect.new()
		track.color = Color(0, 0, 0, 0.6)
		track.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		track.offset_top = -4
		track.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var bar := ColorRect.new()
		bar.color = Style.ACCENT if frac < 0.999 else Style.INK_2
		bar.anchor_bottom = 1.0
		bar.anchor_right = frac
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		track.add_child(bar)
		cover.add_child(track)
	v.add_child(cover)
	var cap := Style.label(title, "Meta")
	cap.clip_text = true
	cap.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	cap.custom_minimum_size.x = 180
	v.add_child(cap)
	var subl := Style.label(sub, "Small", true)
	subl.custom_minimum_size.x = 180
	v.add_child(subl)
	b.add_child(v)
	if not it.is_empty():
		App.svc("comics").cover(it, func(tex):
			if tex and is_instance_valid(cover):
				var tr := TextureRect.new()
				tr.texture = tex
				tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
				tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
				tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
				cover.add_child(tr)
				cover.move_child(tr, 1)   # under the progress bar
				t.visible = false)
	if not enabled:
		b.disabled = true
		b.modulate.a = 0.9
	return b


# ------------------------------------------------------------------ a series
func open_series(id: String) -> void:
	var comics = App.svc("comics")
	var s := {}
	for x in comics.shelf():
		if x.entry.id == id:
			s = x
	if s.is_empty() or s.copies.is_empty():
		show_shelf()
		return
	_series_id = id
	for c in _series_view.get_children():
		c.queue_free()
	_shelf_view.visible = false
	_series_view.visible = true
	var e: Dictionary = s.entry

	var root := Style.vbox(22)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 44
	root.offset_right = -44
	root.offset_top = 22
	root.offset_bottom = -24
	_series_view.add_child(root)
	var back := Style.icon_button("arrow-left", "All comics", show_shelf, "All comics")
	back.set_meta("sfx", "back")
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	root.add_child(back)

	var head := Style.hbox(30)
	var big := Panel.new()
	big.custom_minimum_size = Vector2(170, 256)
	big.mouse_filter = Control.MOUSE_FILTER_IGNORE
	big.clip_contents = true
	var bsb := StyleBoxFlat.new()
	bsb.bg_color = Color(1, 1, 1, 0.04)
	big.add_theme_stylebox_override("panel", bsb)
	comics.cover(s.copies[0], func(tex):
		if tex and is_instance_valid(big):
			var tr := TextureRect.new()
			tr.texture = tex
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			big.add_child(tr))
	head.add_child(big)
	var info := Style.vbox(10)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.size_flags_vertical = Control.SIZE_SHRINK_END
	var name := Style.label(e.title, "H1", true)
	info.add_child(name)
	var meta := []
	if int(e.get("year", 0)) > 0:
		meta.append(str(int(e.year)))
	if str(e.get("publisher", "")) != "":
		meta.append(str(e.publisher))
	if str(e.get("writer", "")) != "":
		meta.append("Written by " + str(e.writer))
	var total: int = maxi(int(e.get("issues", 0)), s.copies.size())
	if total > 1:
		meta.append("%d issues, %d in your library" % [total, s.copies.size()] if s.copies.size() < total else "%d issues" % total)
	info.add_child(Style.label("  ·  ".join(meta), "Meta", true))
	var actions := Style.hbox(10)
	var next_up := _next_to_read(s.copies)
	if comics.started(next_up) and not comics.finished(next_up):
		actions.add_child(Style.button("Continue  " + _issue_name(next_up, false) + "  ·  page %d" % (comics.progress(next_up) + 1), "Primary", func(): _open(next_up)))
		if next_up.id != s.copies[0].id or comics.progress(next_up) > 0:
			actions.add_child(Style.button("Start from the beginning", "Ghost", func(): _open(s.copies[0], 0)))
	else:
		var label := "Read" if s.copies.size() == 1 else "Read  " + _issue_name(next_up, false)
		if s.copies.all(func(c): return comics.finished(c)):
			label = "Read again"
			next_up = s.copies[0]
		actions.add_child(Style.button(label, "Primary", func(): _open(next_up, 0)))
	info.add_child(Style.spacer(6))
	info.add_child(actions)
	head.add_child(info)
	root.add_child(head)

	# Issues, including the ones you don't have yet.
	if total > 1 or s.copies.size() > 1:
		root.add_child(Style.margin(Style.label("ISSUES", "Caps"), 0, 6, 0, 0))
		var scroll := ScrollContainer.new()
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		var grid := GridContainer.new()
		grid.columns = max(2, int((size.x - 88) / 206))
		grid.add_theme_constant_override("h_separation", 26)
		grid.add_theme_constant_override("v_separation", 26)
		scroll.add_child(grid)
		root.add_child(scroll)
		var have := {}
		for c in s.copies:
			have[int(c.get("issue", 0))] = true
			var status := "Read" if comics.finished(c) else ("Page %d of %d" % [comics.progress(c) + 1, comics.page_count(c)] if comics.started(c) and comics.page_count(c) > 0 else "Unread")
			var card := _card(_issue_name(c, false), status, c, 1.0 if comics.finished(c) else comics.fraction(c), true)
			card.pressed.connect(func(): _open(c))
			grid.add_child(card)
		if int(e.get("issues", 0)) > 1 and not App.hide_missing():
			for n in range(1, int(e.issues) + 1):
				if not have.has(n):
					grid.add_child(_card("Issue #%d" % n, "Not in your library", {}, 0.0, false))
	else:
		var f := Control.new()
		f.size_flags_vertical = Control.SIZE_EXPAND_FILL
		root.add_child(f)


func show_shelf() -> void:
	_series_id = ""
	_series_view.visible = false
	_shelf_view.visible = true
	_fill()


## The first issue that's started but not finished, else the first unread one.
func _next_to_read(copies: Array) -> Dictionary:
	var comics = App.svc("comics")
	for c in copies:
		if comics.started(c) and not comics.finished(c):
			return c
	for c in copies:
		if not comics.finished(c):
			return c
	return copies[0]


## "Issue #2" (or, with the series, "Dying Inside #2"); the title for one-shots.
func _issue_name(it: Dictionary, with_series: bool) -> String:
	var n := int(it.get("issue", 0))
	var s: Dictionary = App.svc("comics").series_of(it)
	var series: String = s.get("entry", {}).get("title", it.title)
	if n <= 0:
		return series
	return ("%s #%d" % [series, n]) if with_series else ("Issue #%d" % n)


func _open(it: Dictionary, page: int = -1) -> void:
	var why: String = App.svc("comics").readable(it)
	if why != "":
		App.notify(why, "error")
		return
	var r: Control = load("res://ui/widgets/comic_reader.gd").new()
	r.set("item", it)
	r.set("start_page", page)
	r.tree_exited.connect(func():
		if is_instance_valid(self):
			_refresh())
	main.modal_layer.add_child(r)
