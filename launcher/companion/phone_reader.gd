extends Control
## The companion app's comic reader: one page at a time, full screen.
## Swipe or tap the sides to turn pages, tap the middle for the controls,
## pinch or double-tap to zoom, drag to look around a zoomed page.

var main
var comic: Dictionary
var start_page := 0

var _page := 0
var _total := 0
var _img: TextureRect
var _wait: Label
var _ui: Control
var _count: Label
var _slider: HSlider
var _keep: Button
var _note: Label
var _zoom := 1.0
var _offset := Vector2.ZERO
var _touches := {}
var _pinch_from := 0.0
var _zoom_from := 1.0
var _drag_total := Vector2.ZERO
var _down_at := 0
var _last_tap := 0
var _token := 0

const CS = preload("res://companion/comics_screen.gd")


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	_img = TextureRect.new()
	_img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_img.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_img)
	_wait = Style.label("", "Small")
	_wait.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_wait.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_wait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_wait)
	_build_ui()
	_total = int(comic.get("pages", 0))
	var kept: Dictionary = CS.kept_index().get(comic.id, {})
	if _total == 0 and not kept.is_empty():
		_total = int(kept.get("pages", 0))
	show_page(clampi(start_page, 0, maxi(0, _total - 1)) if _total > 0 else start_page)
	resized.connect(_layout)


func _build_ui() -> void:
	_ui = Control.new()
	_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_ui)
	var top := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.75)
	sb.set_content_margin_all(10)
	top.add_theme_stylebox_override("panel", sb)
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	var th := Style.hbox(10)
	var back := Style.icon_button("arrow-left", "Back", func(): queue_free(), "", "", 24)
	back.custom_minimum_size = Vector2(Style.TARGET_TOUCH, Style.TARGET_TOUCH)
	back.set_meta("sfx", "back")
	th.add_child(back)
	var t := Style.label(str(comic.title))
	t.clip_text = true
	t.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	th.add_child(t)
	_count = Style.label("", "Small")
	th.add_child(_count)
	top.add_child(th)
	_ui.add_child(top)
	var bottom := PanelContainer.new()
	bottom.add_theme_stylebox_override("panel", sb)
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var bv := Style.vbox(8)
	_slider = HSlider.new()
	_slider.min_value = 0
	_slider.step = 1
	_slider.custom_minimum_size.y = 32
	_slider.drag_ended.connect(func(_c): show_page(int(_slider.value)))
	bv.add_child(_slider)
	var bh := Style.hbox(8)
	for d in [[-1, "chevron-left", "Previous page"], [1, "chevron-right", "Next page"]]:
		var step: int = d[0]
		var pb := Style.icon_button(d[1], d[2], func(): show_page(_page + step), "", "Ghost", 24)
		pb.custom_minimum_size = Vector2(56, Style.TARGET_TOUCH)
		bh.add_child(pb)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bh.add_child(sp)
	_keep = Style.button("", "Ghost", _toggle_keep)
	bh.add_child(_keep)
	bv.add_child(bh)
	_note = Style.label("", "Small", true)
	bv.add_child(_note)
	bottom.add_child(bv)
	_ui.add_child(bottom)
	_set_keep_text()
	_ui.visible = false


func _set_keep_text() -> void:
	_keep.text = "Remove from phone" if CS.kept_index().has(comic.id) else "Keep on phone"


func _toggle_keep() -> void:
	if CS.kept_index().has(comic.id):
		CS.forget_comic(comic.id)
		_note.text = "Removed from this phone."
		_set_keep_text()
		return
	var c := comic.duplicate()
	c.pages = _total
	_keep.disabled = true
	CS.keep_comic(c, func(d: int, n: int):
		if is_instance_valid(_note):
			_note.text = "Saving to this phone… %d of %d pages" % [d, n],
	func(ok: bool):
		if not is_instance_valid(_note):
			return
		_keep.disabled = false
		_note.text = "Kept on this phone." if ok else "Some pages couldn't be saved. Try again at home."
		_set_keep_text())


func show_page(n: int) -> void:
	if _total > 0:
		n = clampi(n, 0, _total - 1)
	n = maxi(0, n)
	if n != _page or _img.texture == null:
		Sfx.play("move")
	_page = n
	_zoom = 1.0
	_offset = Vector2.ZERO
	_count.text = ("%d / %d" % [n + 1, _total]) if _total > 0 else "%d" % (n + 1)
	_slider.max_value = maxi(0, _total - 1)
	_slider.set_value_no_signal(n)
	_token += 1
	var tk := _token
	var file := CS.page_file(comic.id, n)
	_wait.text = "Getting page %d…" % (n + 1)
	App.svc("pc").fetch("/api/comics/page?id=%s&n=%d" % [comic.id, n], file, func(ok: bool):
		if tk != _token or not is_instance_valid(self):
			return
		if not ok:
			_wait.text = "Couldn't get this page. Is the PC on, with the companion turned on?"
			_img.texture = null
			return
		var img := Pictures.read(file)
		if img == null:
			_wait.text = "This page couldn't be read."
			return
		_wait.text = ""
		_img.texture = ImageTexture.create_from_image(img)
		_layout()
		CS.set_place(comic, n, _total)
		for k in [1, 2]:   # the next pages, ahead of time
			if _total == 0 or n + k < _total:
				App.svc("pc").fetch("/api/comics/page?id=%s&n=%d" % [comic.id, n + k], CS.page_file(comic.id, n + k), func(_ok): pass))


func _layout() -> void:
	_img.size = size
	_img.pivot_offset = Vector2.ZERO
	_img.scale = Vector2(_zoom, _zoom)
	var max_off := size * (_zoom - 1.0)
	_offset = _offset.clamp(-max_off, Vector2.ZERO)
	_img.position = _offset


func _zoom_at(point: Vector2, z: float) -> void:
	var nz := clampf(z, 1.0, 4.0)
	# Keep the point under the finger where it is.
	var img_pt := (point - _offset) / _zoom
	_zoom = nz
	_offset = point - img_pt * _zoom
	_layout()


func _gui_input(e: InputEvent) -> void:
	if e is InputEventScreenTouch:
		if e.pressed:
			_touches[e.index] = e.position
			if _touches.size() == 1:
				_drag_total = Vector2.ZERO
				_down_at = Time.get_ticks_msec()
			elif _touches.size() == 2:
				var p: Array = _touches.values()
				_pinch_from = p[0].distance_to(p[1])
				_zoom_from = _zoom
		else:
			var was_single := _touches.size() == 1
			_touches.erase(e.index)
			if was_single:
				_release(e.position)
		accept_event()
	elif e is InputEventScreenDrag:
		_touches[e.index] = e.position
		if _touches.size() >= 2:
			var p: Array = _touches.values()
			var mid: Vector2 = (p[0] + p[1]) / 2.0
			_zoom_at(mid, _zoom_from * p[0].distance_to(p[1]) / maxf(1.0, _pinch_from))
			_drag_total = Vector2(999, 999)   # not a tap or a swipe
		else:
			_drag_total += e.relative
			if _zoom > 1.01:
				_offset += e.relative
				_layout()
		accept_event()
	elif e is InputEventMouseButton and not DisplayServer.is_touchscreen_available():
		# Trying the app on a PC with a mouse.
		if e.button_index == MOUSE_BUTTON_LEFT:
			if e.pressed:
				_drag_total = Vector2.ZERO
				_down_at = Time.get_ticks_msec()
			else:
				_release(e.position)
		elif e.button_index == MOUSE_BUTTON_WHEEL_UP and e.pressed:
			_zoom_at(e.position, _zoom * 1.15)
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN and e.pressed:
			_zoom_at(e.position, _zoom / 1.15)
	elif e is InputEventMouseMotion and not DisplayServer.is_touchscreen_available() and e.button_mask & MOUSE_BUTTON_MASK_LEFT:
		_drag_total += e.relative
		if _zoom > 1.01:
			_offset += e.relative
			_layout()


func _release(at: Vector2) -> void:
	var quick := Time.get_ticks_msec() - _down_at < 400
	if _drag_total.length() < 16 and quick:
		var now := Time.get_ticks_msec()
		if now - _last_tap < 300:
			_last_tap = 0
			_zoom_at(at, 1.0 if _zoom > 1.01 else 2.5)
			return
		_last_tap = now
		# Tap: sides turn pages (unless zoomed), the middle shows the controls.
		var x := at.x / maxf(1.0, size.x)
		get_tree().create_timer(0.3).timeout.connect(func():
			if _last_tap != now or not is_instance_valid(self):
				return
			if _zoom > 1.01 or (x > 0.3 and x < 0.7):
				_ui.visible = not _ui.visible
			elif x <= 0.3:
				show_page(_page - 1)
			else:
				show_page(_page + 1))
	elif _zoom <= 1.01 and absf(_drag_total.x) > 60 and absf(_drag_total.x) > absf(_drag_total.y):
		show_page(_page + (1 if _drag_total.x < 0 else -1))


func _unhandled_key_input(e: InputEvent) -> void:
	if e.pressed:
		match e.keycode:
			KEY_RIGHT, KEY_SPACE, KEY_PAGEDOWN:
				show_page(_page + 1)
			KEY_LEFT, KEY_PAGEUP:
				show_page(_page - 1)
			KEY_ESCAPE:
				queue_free()
