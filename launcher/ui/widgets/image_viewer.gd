extends Control
## Full-window picture viewer for the Concept Art section.
##   ← → / A D / click the sides: previous or next   Space / Z: zoom to full size
##   drag: move around a zoomed picture   F11: full screen   Esc: close

var pictures: Array = []   # [{name, full, ext, artist, source, page, local}]
var index := 0

var _img: TextureRect
var _wait: Label
var _name: Label
var _meta: Label
var _count: Label
var _open_btn: Button
var _zoom := false
var _drag_from := Vector2.ZERO
var _offset := Vector2.ZERO
var _token := 0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	clip_contents = true
	var bg := ColorRect.new()
	bg.color = Color(0.01, 0.01, 0.012, 0.97)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	_img = TextureRect.new()
	_img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_img.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_img)
	_wait = Style.label("Loading…", "Meta")
	_wait.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	add_child(_wait)

	var bar := Style.hbox(18)
	bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_left = 28
	bar.offset_right = -28
	bar.offset_top = -64
	bar.offset_bottom = -16
	var tv := Style.vbox(2)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name = Style.label("", "H2")
	_name.clip_text = true
	_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	tv.add_child(_name)
	_meta = Style.label("", "Small")
	tv.add_child(_meta)
	bar.add_child(tv)
	_count = Style.label("", "Meta")
	bar.add_child(_count)
	bar.add_child(Style.icon_button("chevron-left", "Previous picture", func(): step(-1)))
	bar.add_child(Style.icon_button("chevron-right", "Next picture", func(): step(1)))
	bar.add_child(Style.button("Full size", "", _toggle_zoom))
	_open_btn = Style.button("Source", "", _open_source)
	bar.add_child(_open_btn)
	bar.add_child(Style.button("Close", "", queue_free))
	add_child(bar)
	resized.connect(_layout)
	_show()
	grab_focus.call_deferred()


func step(d: int) -> void:
	if pictures.is_empty():
		return
	index = wrapi(index + d, 0, pictures.size())
	_show()


func _show() -> void:
	_zoom = false
	_offset = Vector2.ZERO
	_img.texture = null
	var p: Dictionary = pictures[index]
	_name.text = str(p.name)
	var meta := []
	if str(p.get("artist", "")) != "":
		meta.append(str(p.artist))
	meta.append(str(p.get("source", "")))
	if bool(p.get("local", false)) and str(p.get("source", "")) != "Your files":
		meta.append("kept offline")
	_meta.text = "  ·  ".join(meta)
	_count.text = "%d / %d" % [index + 1, pictures.size()]
	_open_btn.text = "Show in folder" if str(p.get("page", "")) == "" else "Open the source page"
	_wait.visible = true
	_token += 1
	var token := _token
	var load_path := func(path: String):
		App.run(func():
			return Pictures.read(path) if path != "" else null,
		func(img):
			if token != _token or not is_instance_valid(self):
				return
			_wait.visible = img == null
			_wait.text = "Couldn't load this picture."
			if img:
				_img.texture = ImageTexture.create_from_image(img)
				_layout())
	var full := str(p.full)
	if full.begins_with("http"):
		Net.get_file(full, load_path, str(p.get("ext", "")))
	else:
		load_path.call(full)


func _layout() -> void:
	var tex := _img.texture
	var area := Vector2(size.x - 48, size.y - 110)
	if tex == null:
		_img.position = Vector2(24, 24)
		_img.size = area
		return
	var ts := Vector2(tex.get_width(), tex.get_height())
	var s := minf(area.x / ts.x, area.y / ts.y)
	if _zoom:
		s = maxf(1.0, s)
	else:
		s = minf(s, 2.0)
	var shown := ts * s
	_img.size = shown
	var centre := Vector2(24, 24) + (area - shown) / 2.0
	if _zoom:
		var lim := ((shown - area) / 2.0).max(Vector2.ZERO)
		_offset = _offset.clamp(-lim, lim)
		centre += _offset
	_img.position = centre


func _toggle_zoom() -> void:
	_zoom = not _zoom
	_offset = Vector2.ZERO
	_layout()


func _open_source() -> void:
	var p: Dictionary = pictures[index]
	if str(p.get("page", "")) != "":
		OS.shell_open(str(p.page))
	elif str(p.full) != "":
		OS.shell_show_in_file_manager(ProjectSettings.globalize_path(str(p.full)))


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		if e.position.y > size.y - 80:
			return
		if _zoom:
			_drag_from = e.position
		elif e.position.x < size.x * 0.25:
			step(-1)
		elif e.position.x > size.x * 0.75:
			step(1)
		else:
			_toggle_zoom()
		accept_event()
	elif e is InputEventMouseMotion and _zoom and (e.button_mask & MOUSE_BUTTON_MASK_LEFT):
		_offset += e.relative
		_layout()
	elif e is InputEventMouseButton and e.pressed and e.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and not _zoom:
		step(1 if e.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1)
		accept_event()


func _unhandled_key_input(e: InputEvent) -> void:
	if not e.pressed:
		return
	match e.keycode:
		KEY_RIGHT, KEY_D: step(1)
		KEY_LEFT, KEY_A: step(-1)
		KEY_SPACE, KEY_Z: _toggle_zoom()
		KEY_F11:
			var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)
		KEY_ESCAPE: queue_free()
		_: return
	get_viewport().set_input_as_handled()
