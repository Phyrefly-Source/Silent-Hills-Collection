extends Control
## Full-window comic reader.
##   ← → / A D / Space / PgUp PgDn, or click the left or right of the page: turn pages
##   Click the middle, or move the mouse: show the controls (they fade when idle)
##   W or double-click: fit the page's width and scroll (wheel / ↑ ↓)
##   2: two-page spreads   Home / End   F11: full screen   Esc: close
## The slider jumps to any page. Pages are decoded off the main thread and the
## next few are prepared ahead. At the end of an issue the next one is offered.

signal finished_reading

var item: Dictionary
var start_page := -1          # -1: where you left off

var _pages: Array = []
var _page := 0
var _spread := false
var _fit_width := false
var _cache := {}               # index -> Texture2D
var _loading := {}
var _view: HBoxContainer
var _scroll: ScrollContainer
var _top: Control
var _bottom: Control
var _title: Label
var _sub: Label
var _count: Label
var _slider: HSlider
var _fit_btn: Button
var _spread_btn: Button
var _end: Control
var _idle := 0.0
var _chrome := true
var _was_fullscreen := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	var bg := ColorRect.new()
	bg.color = Color(0.012, 0.012, 0.014, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	_scroll = ScrollContainer.new()
	_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	_scroll.gui_input.connect(_page_input)
	add_child(_scroll)
	_view = Style.hbox(4)
	_view.alignment = BoxContainer.ALIGNMENT_CENTER
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scroll.add_child(_view)
	_build_chrome()
	_was_fullscreen = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	_spread = bool(App.library.comics.get("spread", false))
	_fit_width = bool(App.library.comics.get("fit_width", false))
	resized.connect(_layout)
	_load(item, start_page)
	grab_focus.call_deferred()


func _bar_bg(top: bool) -> StyleBoxTexture:
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0.85) if top else Color(0, 0, 0, 0))
	g.set_color(1, Color(0, 0, 0, 0) if top else Color(0, 0, 0, 0.85))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	gt.width = 4
	gt.height = 64
	var sb := StyleBoxTexture.new()
	sb.texture = gt
	return sb


func _build_chrome() -> void:
	# Top: back, title, issue.
	var top := PanelContainer.new()
	top.add_theme_stylebox_override("panel", _bar_bg(true))
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_bottom = 84
	top.mouse_filter = Control.MOUSE_FILTER_PASS
	var th := Style.hbox(18)
	var back := Style.icon_button("arrow-left", "Back", close, "Back")
	back.set_meta("sfx", "back")
	back.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	th.add_child(back)
	var tv := Style.vbox(2)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title = Style.label("", "H2")
	_title.clip_text = true
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	tv.add_child(_title)
	_sub = Style.label("", "Small")
	tv.add_child(_sub)
	th.add_child(tv)
	top.add_child(Style.margin(th, 28, 16, 28, 18))
	add_child(top)
	_top = top

	# Bottom: page slider and view options.
	var bottom := PanelContainer.new()
	bottom.add_theme_stylebox_override("panel", _bar_bg(false))
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_top = -78
	bottom.mouse_filter = Control.MOUSE_FILTER_PASS
	var bh := Style.hbox(16)
	bh.size_flags_vertical = Control.SIZE_SHRINK_END
	bh.add_child(Style.icon_button("chevron-left", "Previous page", func(): turn(-1)))
	_slider = HSlider.new()
	_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_slider.step = 1
	_slider.focus_mode = Control.FOCUS_NONE
	_slider.value_changed.connect(func(v):
		if int(v) != _page:
			_go(int(v)))
	bh.add_child(_slider)
	bh.add_child(Style.icon_button("chevron-right", "Next page", func(): turn(1)))
	_count = Style.label("", "Meta")
	_count.custom_minimum_size.x = 92
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bh.add_child(_count)
	_spread_btn = Style.button("Two pages", "", _toggle_spread)
	bh.add_child(_spread_btn)
	_fit_btn = Style.button("Fit width", "", _toggle_fit)
	bh.add_child(_fit_btn)
	bh.add_child(Style.button("Full screen", "", _toggle_fullscreen))
	bottom.add_child(Style.margin(bh, 28, 22, 28, 14))
	add_child(bottom)
	_bottom = bottom


## Opens a comic in this reader (also used to move on to the next issue).
func _load(it: Dictionary, page: int) -> void:
	item = it
	_cache.clear()
	_loading.clear()
	if is_instance_valid(_end):
		_end.queue_free()
	var comics = App.svc("comics")
	_pages = comics.pages(item)
	var saved: int = comics.progress(item)
	if comics.finished(item) and page < 0:
		saved = 0   # finished before: start again from the cover
	_page = clampi(page if page >= 0 else saved, 0, maxi(0, _pages.size() - 1))
	var s: Dictionary = comics.series_of(item)
	var series: String = s.get("entry", {}).get("title", item.title)
	var n := int(item.get("issue", 0))
	_title.text = series
	var subs := []
	if n > 0:
		subs.append("Issue #%d" % n)
	if int(s.get("entry", {}).get("year", 0)) > 0:
		subs.append(str(int(s.entry.year)))
	if str(s.get("entry", {}).get("writer", "")) != "":
		subs.append(str(s.entry.writer))
	_sub.text = "  ·  ".join(subs)
	_slider.max_value = maxi(0, _pages.size() - 1)
	_view_changed()
	_show_chrome()
	_show()
	comics.set_progress(item, _page, _pages.size())


func close() -> void:
	App.svc("comics").set_progress(item, _page, _pages.size())
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN and not _was_fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	finished_reading.emit()
	queue_free()


# ------------------------------------------------------------------ input
func _process(dt: float) -> void:
	_idle += dt
	if _chrome and _idle > 2.5 and not _pages.is_empty() and not is_instance_valid(_end):
		_hide_chrome()


func _input(e: InputEvent) -> void:
	if e is InputEventMouseMotion and e.relative.length() > 2.0:
		_idle = 0.0
		if not _chrome:
			_show_chrome()


func _page_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed:
		if e.button_index == MOUSE_BUTTON_LEFT:
			if e.double_click:
				_toggle_fit()
			else:
				var x: float = e.global_position.x
				if x < size.x * 0.3:
					turn(-1)
				elif x > size.x * 0.7:
					turn(1)
				elif _chrome:
					_hide_chrome()
				else:
					_show_chrome()
			accept_event()
		elif e.button_index in [MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_UP]:
			var down: bool = e.button_index == MOUSE_BUTTON_WHEEL_DOWN
			if _fit_width:
				# Scroll the page; past its end the wheel turns to the next one.
				var bar := _scroll.get_v_scroll_bar()
				var at_end := _scroll.scroll_vertical >= int(bar.max_value - bar.page) - 1
				var at_top := _scroll.scroll_vertical <= 0
				if down and at_end:
					turn(1)
				elif not down and at_top:
					turn(-1, true)
				else:
					_scroll.scroll_vertical += 90 if down else -90
			else:
				turn(1 if down else -1)
			accept_event()


func _unhandled_key_input(e: InputEvent) -> void:
	if not e.pressed:
		return
	_idle = 0.0
	match e.keycode:
		KEY_RIGHT, KEY_D, KEY_SPACE, KEY_PAGEDOWN: turn(1)
		KEY_LEFT, KEY_A, KEY_BACKSPACE, KEY_PAGEUP: turn(-1)
		KEY_DOWN, KEY_S:
			if _fit_width:
				_scroll.scroll_vertical += 120
		KEY_UP:
			if _fit_width:
				_scroll.scroll_vertical -= 120
		KEY_HOME: _go(0)
		KEY_END: _go(_pages.size() - 1)
		KEY_2: _toggle_spread()
		KEY_W, KEY_F: _toggle_fit()
		KEY_F11: _toggle_fullscreen()
		KEY_ENTER, KEY_KP_ENTER:
			if is_instance_valid(_end):
				_read_next()
			else:
				return
		KEY_ESCAPE:
			if is_instance_valid(_end):
				_end.queue_free()
			else:
				close()
		_: return
	get_viewport().set_input_as_handled()


func _show_chrome() -> void:
	_chrome = true
	_idle = 0.0
	for c in [_top, _bottom]:
		c.visible = true
		create_tween().tween_property(c, "modulate:a", 1.0, 0.15)
	mouse_default_cursor_shape = Control.CURSOR_ARROW
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _hide_chrome() -> void:
	_chrome = false
	for c in [_top, _bottom]:
		var tw := create_tween()
		tw.tween_property(c, "modulate:a", 0.0, 0.4)
		tw.tween_callback(func(): c.visible = _chrome)


func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


# ------------------------------------------------------------------ paging
func _step() -> int:
	return 2 if _spread and _page > 0 else 1


func turn(dir: int, to_bottom: bool = false) -> void:
	if is_instance_valid(_end):
		if dir < 0:
			_end.queue_free()
		else:
			_read_next()
		return
	if dir > 0:
		if _page + _step() >= _pages.size():
			_issue_end()
			return
		_go(_page + _step())
	else:
		_go(_page - (2 if _spread and _page > 2 else 1))
		if to_bottom and _fit_width:
			_scroll.set_deferred("scroll_vertical", 100000)


func _go(i: int) -> void:
	i = clampi(i, 0, maxi(0, _pages.size() - 1))
	if i == _page and not _view.get_children().is_empty():
		return
	_page = i
	_show()
	App.svc("comics").set_progress(item, _page, _pages.size())


func _toggle_spread() -> void:
	_spread = not _spread
	App.library.comics.spread = _spread
	App.mark_dirty("library")
	_view_changed()
	_show()


func _toggle_fit() -> void:
	_fit_width = not _fit_width
	App.library.comics.fit_width = _fit_width
	App.mark_dirty("library")
	_view_changed()
	_show()


func _toggle_fullscreen() -> void:
	var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)


func _view_changed() -> void:
	_fit_btn.text = "Fit page" if _fit_width else "Fit width"
	_spread_btn.text = "One page" if _spread else "Two pages"


# ------------------------------------------------------------------ end of an issue
func _issue_end() -> void:
	App.svc("comics").set_progress(item, _pages.size() - 1, _pages.size())
	var comics = App.svc("comics")
	var nx: Dictionary = comics.next_issue(item)
	var scrim := ColorRect.new()
	scrim.color = Color(0, 0, 0, 0.78)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	var box := Style.vbox(16)
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.custom_minimum_size.x = 460
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	var n := int(item.get("issue", 0))
	var done := Style.label(("End of issue #%d" % n) if n > 0 else "The end", "Caps")
	done.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(done)
	var row := Style.hbox(10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	if not nx.is_empty():
		var nn := int(nx.get("issue", 0))
		var head := Style.label(("Next: Issue #%d" % nn) if nn > 0 else "Next: " + str(nx.title), "H1")
		head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(head)
		row.add_child(Style.button("Read next", "Primary", _read_next))
	else:
		var s: Dictionary = comics.series_of(item)
		var head := Style.label(str(s.get("entry", {}).get("title", item.title)), "H1", true)
		head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(head)
	row.add_child(Style.button("Back to the shelf", "Ghost", close))
	box.add_child(Style.spacer(6))
	box.add_child(row)
	scrim.add_child(box)
	add_child(scrim)
	scrim.set_meta("next", nx)
	_end = scrim
	_show_chrome()
	scrim.modulate.a = 0.0
	create_tween().tween_property(scrim, "modulate:a", 1.0, 0.2)


func _read_next() -> void:
	if not is_instance_valid(_end):
		return
	var nx: Dictionary = _end.get_meta("next", {})
	if nx.is_empty():
		close()
		return
	_load(nx, 0)


# ------------------------------------------------------------------ drawing
func _visible_pages() -> Array:
	# The cover stands alone; after that pages pair up.
	if _spread and _page > 0 and _page + 1 < _pages.size():
		return [_page, _page + 1]
	return [_page]


func _show() -> void:
	for c in _view.get_children():
		_view.remove_child(c)
		c.queue_free()
	if _pages.is_empty():
		_count.text = "No pages"
		return
	var vis := _visible_pages()
	_count.text = "%s / %d" % [("%d–%d" % [vis[0] + 1, vis[-1] + 1]) if vis.size() > 1 else str(vis[0] + 1), _pages.size()]
	_slider.set_value_no_signal(_page)
	for i in vis:
		var tr := TextureRect.new()
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tr.set_meta("page", i)
		_view.add_child(tr)
		_need(i, tr)
	_layout()
	_scroll.scroll_vertical = 0
	for k in [_page + 1, _page + 2, _page + 3, _page - 1]:
		_need(k, null)
	# Keep memory small: forget pages far from here.
	for k in _cache.keys():
		if absi(int(k) - _page) > 6:
			_cache.erase(k)


func _layout() -> void:
	var avail := Vector2(size.x - 24, size.y - 12)
	var vis := _view.get_children()
	for tr in vis:
		var tex: Texture2D = tr.texture
		var aspect := 0.66
		if tex:
			aspect = float(tex.get_width()) / maxf(1.0, tex.get_height())
		var w: float
		var h: float
		if _fit_width:
			w = minf(avail.x / vis.size(), 1500.0 / vis.size())
			h = w / aspect
		else:
			h = avail.y
			w = h * aspect
			if w * vis.size() > avail.x:
				w = avail.x / vis.size()
				h = w / aspect
		tr.custom_minimum_size = Vector2(w, h)
	_view.custom_minimum_size = Vector2(size.x, size.y if not _fit_width else 0)


func _need(i: int, target: TextureRect) -> void:
	if i < 0 or i >= _pages.size():
		return
	if _cache.has(i):
		if target:
			target.texture = _cache[i]
			_layout()
		return
	if _loading.has(i):
		if target:
			_loading[i].append(target)
		return
	_loading[i] = [target] if target else []
	var comics = App.svc("comics")
	var it := item
	var max_h := int(maxf(1600.0, DisplayServer.screen_get_size().y * 1.6))
	App.run(func():
		var img: Image = comics.page_image(it, i)
		if img and img.get_height() > max_h:
			img.resize(int(img.get_width() * float(max_h) / img.get_height()), max_h, Image.INTERPOLATE_LANCZOS)
		if img:
			img.generate_mipmaps()
		return img,
	func(img):
		if not is_instance_valid(self) or it.id != item.id:
			return
		var tex: Texture2D = ImageTexture.create_from_image(img) if img else null
		_cache[i] = tex
		for tr in _loading.get(i, []):
			if is_instance_valid(tr) and tr.get_meta("page", -1) == i:
				tr.texture = tex
		_loading.erase(i)
		_layout())
