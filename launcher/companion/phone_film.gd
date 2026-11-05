extends Control
## The companion app's film player: a film kept on the phone, full screen and
## sideways. Tap for the controls; double-tap the left or right half to skip
## 10 seconds. Your place is saved as you watch and sent to the PC.

var main
var film: Dictionary
var start_at := 0.0

var _video: VideoStreamPlayer
var _ui: Control
var _time: Label
var _seek: HSlider
var _play_btn: Button
var _sub_label: Label
var _sub_btn: Button
var _subs = null
var _subs_on := true
var _hide_at := 0
var _saved_at := 0
var _last_tap := 0
var _len := 0.0
var _dragging := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	if OS.has_feature("mobile"):
		DisplayServer.screen_set_orientation(DisplayServer.SCREEN_SENSOR_LANDSCAPE)
		DisplayServer.screen_set_keep_on(true)
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	_video = VideoStreamPlayer.new()
	_video.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_video.expand = true
	_video.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_video)
	_sub_label = Style.label("", "Body", true)
	_sub_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_sub_label.offset_bottom = -28
	_sub_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_sub_label.add_theme_font_size_override("font_size", 20)
	_sub_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_sub_label.add_theme_constant_override("outline_size", 6)
	_sub_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_sub_label)
	_build_ui()
	var file: String = load("res://companion/films_screen.gd").film_file(film.id)
	var srt := file.get_basename() + ".srt"
	if FileAccess.file_exists(srt):
		_subs = Subtitles.from_srt(FileAccess.get_file_as_string(srt))
	_sub_btn.visible = _subs != null
	var st := VideoStreamTheora.new()
	st.file = file
	_video.stream = st
	_video.play()
	_len = _video.get_stream_length()
	if start_at > 1.0:
		_video.stream_position = start_at
	_show_ui()
	resized.connect(_fit_video)
	_fit_video()


## Keeps the film's shape (black bars rather than stretching).
func _fit_video() -> void:
	var tex := _video.get_video_texture()
	if tex == null or tex.get_size().x == 0:
		return
	var a := tex.get_size().x / tex.get_size().y
	var w := size.x
	var h := w / a
	if h > size.y:
		h = size.y
		w = h * a
	_video.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_video.position = (size - Vector2(w, h)) / 2.0
	_video.size = Vector2(w, h)


func _build_ui() -> void:
	_ui = Control.new()
	_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_ui)
	var shade := StyleBoxFlat.new()
	shade.bg_color = Color(0, 0, 0, 0.6)
	shade.set_content_margin_all(14)
	var top := PanelContainer.new()
	top.add_theme_stylebox_override("panel", shade)
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	var th := Style.hbox(12)
	var back := Style.icon_button("arrow-left", "Back", close, "", "", 24)
	back.custom_minimum_size = Vector2(Style.TARGET_TOUCH, Style.TARGET_TOUCH)
	back.set_meta("sfx", "back")
	th.add_child(back)
	var t := Style.label(str(film.title))
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.clip_text = true
	t.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	th.add_child(t)
	_sub_btn = Style.icon_button("captions", "Subtitles", Callable(), "Subtitles: on", "", 20)
	_sub_btn.custom_minimum_size.y = Style.TARGET_TOUCH
	_sub_btn.pressed.connect(func():
		_subs_on = not _subs_on
		_sub_btn.text = "Subtitles: on" if _subs_on else "Subtitles: off"
		_sub_label.text = "")
	th.add_child(_sub_btn)
	top.add_child(th)
	_ui.add_child(top)
	var bottom := PanelContainer.new()
	bottom.add_theme_stylebox_override("panel", shade)
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var bh := Style.hbox(12)
	var rw := Style.icon_button("rotate-ccw", "Back 10 seconds", func(): _skip(-10), "10", "", 24)
	rw.custom_minimum_size.y = Style.TARGET_TOUCH
	bh.add_child(rw)
	_play_btn = Style.icon_button("pause", "Pause", toggle, "", "Primary", 24)
	_play_btn.custom_minimum_size = Vector2(64, Style.TARGET_TOUCH)
	bh.add_child(_play_btn)
	var ff := Style.icon_button("fast-forward", "Forward 10 seconds", func(): _skip(10), "10", "", 24)
	ff.custom_minimum_size.y = Style.TARGET_TOUCH
	bh.add_child(ff)
	_seek = HSlider.new()
	_seek.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_seek.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_seek.step = 1
	_seek.custom_minimum_size.y = 32
	_seek.drag_started.connect(func(): _dragging = true)
	_seek.drag_ended.connect(func(_c):
		_dragging = false
		_video.stream_position = _seek.value
		_show_ui())
	bh.add_child(_seek)
	_time = Style.label("", "Small")
	bh.add_child(_time)
	bottom.add_child(bh)
	_ui.add_child(bottom)


func toggle() -> void:
	_video.paused = not _video.paused
	_play_btn.icon = Style.icon("play" if _video.paused else "pause", 24, Color.WHITE)
	_play_btn.tooltip_text = "Play" if _video.paused else "Pause"
	_play_btn.accessibility_name = _play_btn.tooltip_text
	_save(true)
	_show_ui()


func _skip(sec: float) -> void:
	_video.stream_position = clampf(_video.stream_position + sec, 0.0, maxf(0.0, _len - 1.0))
	_show_ui()


func _show_ui() -> void:
	_ui.visible = true
	_hide_at = Time.get_ticks_msec() + 3500


func _process(_dt: float) -> void:
	var pos := _video.stream_position
	if _len <= 0.0:
		_len = _video.get_stream_length()
		_fit_video()
	if not _dragging:
		_seek.max_value = maxf(1.0, _len)
		_seek.set_value_no_signal(pos)
	_time.text = "%s / %s" % [main.fmt_time(pos), main.fmt_time(_len)]
	if _ui.visible and not _video.paused and Time.get_ticks_msec() > _hide_at:
		_ui.visible = false
	if _subs != null and _subs_on:
		_sub_label.text = _subs.at(pos)
	if Time.get_ticks_msec() - _saved_at > 10000:
		_save(Time.get_ticks_msec() - _saved_at > 60000)
	if not _video.is_playing() and not _video.paused and pos > 1.0:
		# The end: start over next time.
		load("res://companion/films_screen.gd").set_place(film.id, 0.0, true)
		_saved_at = Time.get_ticks_msec() + 1000000
		close()


func _save(push: bool) -> void:
	if _saved_at > Time.get_ticks_msec():
		return
	_saved_at = Time.get_ticks_msec()
	var pos := _video.stream_position
	if pos > 5.0:
		load("res://companion/films_screen.gd").set_place(film.id, pos, push)


func close() -> void:
	if not is_inside_tree():
		return
	_save(true)
	if OS.has_feature("mobile"):
		DisplayServer.screen_set_orientation(DisplayServer.SCREEN_PORTRAIT)
		DisplayServer.screen_set_keep_on(false)
	queue_free()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if is_instance_valid(_video) and not _video.paused:
			toggle()


func _gui_input(e: InputEvent) -> void:
	var tap: bool = (e is InputEventScreenTouch and not e.pressed) or (e is InputEventMouseButton and not e.pressed and e.button_index == MOUSE_BUTTON_LEFT and not DisplayServer.is_touchscreen_available())
	if not tap:
		return
	var now := Time.get_ticks_msec()
	if now - _last_tap < 300:
		_last_tap = 0
		_skip(10 if e.position.x > size.x / 2 else -10)
		return
	_last_tap = now
	get_tree().create_timer(0.3).timeout.connect(func():
		if _last_tap == now and is_instance_valid(self):
			if _ui.visible and not _video.paused:
				_ui.visible = false
			else:
				_show_ui())
	accept_event()


func _unhandled_key_input(e: InputEvent) -> void:
	if e.pressed:
		match e.keycode:
			KEY_SPACE:
				toggle()
			KEY_LEFT:
				_skip(-10)
			KEY_RIGHT:
				_skip(10)
			KEY_ESCAPE:
				close()
