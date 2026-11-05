extends Control
## Full-window film player, built on AVStream (FFmpeg on pipes).
##   Space / K: pause   ← → / J L: back or forward 10 s (Shift: 60 s)
##   ↑ ↓: volume   M: mute   S: subtitles   A: sound track   F / F11: full screen
##   Home: from the start   Esc: close
## The controls fade while the film plays; move the mouse to bring them back.
## Your place in each film is remembered.

signal closed

const YUV_SHADER := """
shader_type canvas_item;
uniform sampler2D tex_y : filter_linear;
uniform sampler2D tex_u : filter_linear;
uniform sampler2D tex_v : filter_linear;
void fragment() {
	float y = (texture(tex_y, UV).r - 16.0 / 255.0) * (255.0 / 219.0);
	float u = (texture(tex_u, UV).r - 128.0 / 255.0) * (255.0 / 224.0);
	float v = (texture(tex_v, UV).r - 128.0 / 255.0) * (255.0 / 224.0);
	// BT.709
	vec3 rgb = vec3(y + 1.5748 * v, y - 0.1873 * u - 0.4681 * v, y + 1.8556 * u);
	COLOR = vec4(clamp(rgb, 0.0, 1.0), 1.0);
}
"""

var film_id := ""          # catalogue id, for remembering the place
var file := ""
var title := ""

var _ff := ""
var _info := {}
var _av: AVStream
var _pic: TextureRect
var _mat: ShaderMaterial
var _ty: ImageTexture
var _tu: ImageTexture
var _tv: ImageTexture
var _player: AudioStreamPlayer
var _gen: AudioStreamGeneratorPlayback
var _gen_cap := 0
var _pushed := 0           # sound frames given to the mixer since the last start
var _paused := false
var _clock_wall := 0.0     # clock when there is no sound track
var _audio_track := 0
var _subs: Subtitles = null
var _sub_choice := -1      # -1 off, else index into _sub_options
var _sub_options: Array = []
var _sub_label: Label
var _top: Control
var _bottom: Control
var _seek: HSlider
var _time: Label
var _play_btn: Button
var _sub_btn: Button
var _audio_btn: Button
var _vol: HSlider
var _wait: Label
var _idle := 0.0
var _chrome := true
var _dragging := false
var _last_save := 0.0
var _was_fullscreen := false
var _clock := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	_pic = TextureRect.new()
	_pic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = YUV_SHADER
	_mat.shader = sh
	_pic.material = _mat
	add_child(_pic)
	_sub_label = Label.new()
	_sub_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_sub_label.offset_top = -170
	_sub_label.offset_bottom = -60
	_sub_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_sub_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sub_label.add_theme_font_override("font", Style.sans_medium)
	_sub_label.add_theme_font_size_override("font_size", 30)
	_sub_label.add_theme_color_override("font_color", Color(1, 1, 1))
	_sub_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_sub_label.add_theme_constant_override("outline_size", 8)
	_sub_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_sub_label)
	_wait = Style.label("Opening…", "Meta")
	_wait.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	add_child(_wait)
	_player = AudioStreamPlayer.new()
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = AVStream.RATE
	gen.buffer_length = 0.4
	_player.stream = gen
	add_child(_player)
	_build_chrome()
	_was_fullscreen = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	Jukebox.pause()
	_ff = App.svc("music").ffmpeg_path()
	if _ff == "":
		_wait.text = "Films play through FFmpeg, which wasn't found in the tools folder."
		return
	var ff := _ff
	var f := file
	App.run(func(): return AVStream.probe(ff, f), _opened)
	grab_focus.call_deferred()


func _opened(info: Dictionary) -> void:
	if not is_instance_valid(self):
		return
	if int(info.get("width", 0)) <= 0:
		_wait.text = "This file can't be played."
		return
	_info = info
	var max_w := mini(1920, int(DisplayServer.screen_get_size().x))
	_av = AVStream.new(_ff, file, info, max_w)
	_ty = ImageTexture.create_from_image(Image.create_empty(_av.width, _av.height, false, Image.FORMAT_L8))
	_tu = ImageTexture.create_from_image(Image.create_empty(_av.width / 2, _av.height / 2, false, Image.FORMAT_L8))
	_tv = ImageTexture.create_from_image(Image.create_empty(_av.width / 2, _av.height / 2, false, Image.FORMAT_L8))
	_mat.set_shader_parameter("tex_y", _ty)
	_mat.set_shader_parameter("tex_u", _tu)
	_mat.set_shader_parameter("tex_v", _tv)
	# A placeholder texture with the film's shape, so the picture keeps its aspect.
	var ph := Image.create_empty(_av.width, _av.height, false, Image.FORMAT_L8)
	_pic.texture = ImageTexture.create_from_image(ph)
	_seek.max_value = maxf(1.0, float(info.duration))
	_audio_track = 0 if not (info.audio as Array).is_empty() else -1
	_audio_btn.visible = (info.audio as Array).size() > 1
	_sub_options = []
	for s in Subtitles.beside(file):
		_sub_options.append({"kind": "file", "path": s.path, "label": s.title})
	for s in info.subs:
		if AVStream.is_text_sub(str(s.codec)):
			var lbl := str(s.title) if str(s.title) != "" else (str(s.lang).to_upper() if str(s.lang) != "" else "Track %d" % (int(s.n) + 1))
			_sub_options.append({"kind": "track", "n": s.n, "label": lbl})
	_sub_btn.visible = not _sub_options.is_empty()
	var saved := float(_data().get("progress", {}).get(film_id, 0.0))
	var start := saved if saved > 30.0 and saved < float(info.duration) - 120.0 else 0.0
	if start > 0.0:
		App.notify("Picking up at %s. Home starts from the beginning." % _fmt(start))
	var sub_pref := int(_data().get("subs", {}).get(film_id, -1))
	if sub_pref >= 0 and sub_pref < _sub_options.size():
		_set_subs(sub_pref)
	_start(start)


func _data() -> Dictionary:
	if not App.library.has("films"):
		App.library.films = {}
	var d: Dictionary = App.library.films
	if not d.has("progress"):
		d.progress = {}
	return d


func _start(t: float) -> void:
	_player.stop()
	_av.start(t, _audio_track)
	_clock = t
	_clock_wall = t
	_pushed = 0
	_wait.visible = true
	_wait.text = ""
	if _audio_track >= 0:
		_player.play()
		_gen = _player.get_stream_playback()
		_gen_cap = _gen.get_frames_available()
		_player.stream_paused = _paused
	_update_play()


func close() -> void:
	_save_place(true)
	if _av:
		_av.stop()
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN and not _was_fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	closed.emit()
	queue_free()


func _exit_tree() -> void:
	if _av:
		_av.stop()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _save_place(force: bool) -> void:
	if film_id == "" or _av == null:
		return
	var d := _data()
	var dur := float(_info.get("duration", 0.0))
	# Near the end counts as finished: next time starts from the beginning.
	d.progress[film_id] = 0.0 if dur > 0.0 and _clock > dur - 240.0 else _clock
	if force or Time.get_ticks_msec() - _last_save > 15000:
		_last_save = Time.get_ticks_msec()
		App.mark_dirty("library")


# ------------------------------------------------------------------ playback
func _process(dt: float) -> void:
	_idle += dt
	if _chrome and _idle > 2.5 and not _paused and not _dragging:
		_hide_chrome()
	if _av == null:
		return
	# Sound: feed the mixer; the sound clock drives the picture.
	if _audio_track >= 0 and _gen and not _paused:
		var space := _gen.get_frames_available()
		if space > 0:
			var f := _av.take_audio(space)
			var n := f.size() / 2
			if n > 0:
				var buf := PackedVector2Array()
				buf.resize(n)
				for i in n:
					buf[i] = Vector2(f[i * 2], f[i * 2 + 1])
				_gen.push_buffer(buf)
				_pushed += n
		var queued := _gen_cap - _gen.get_frames_available()
		_clock = _av.start_time + maxf(0.0, float(_pushed - queued) / AVStream.RATE - AudioServer.get_output_latency())
		if _av.ended_audio and _av.audio_ready_frames() == 0 and queued <= 0 and _av.ended_video and _av.frames_ready() == 0:
			_finished()
			return
	elif not _paused:
		if _av.frames_ready() > 0 or _av.ended_video:
			_clock_wall += dt
		_clock = _clock_wall
		if _av.ended_video and _av.frames_ready() == 0:
			_finished()
			return
	var fr := _av.take_frame(_clock)
	if not fr.is_empty():
		_show_frame(fr[1])
		_wait.visible = false
	if not _dragging:
		_seek.set_value_no_signal(_clock)
	_time.text = "%s / %s" % [_fmt(_clock), _fmt(float(_info.get("duration", 0.0)))]
	if _subs:
		var s := _subs.at(_clock)
		if _sub_label.text != s:
			_sub_label.text = s
	_save_place(false)


func _show_frame(buf: PackedByteArray) -> void:
	var w := _av.width
	var h := _av.height
	var ys := w * h
	var cs := ys / 4
	_ty.update(Image.create_from_data(w, h, false, Image.FORMAT_L8, buf.slice(0, ys)))
	_tu.update(Image.create_from_data(w / 2, h / 2, false, Image.FORMAT_L8, buf.slice(ys, ys + cs)))
	_tv.update(Image.create_from_data(w / 2, h / 2, false, Image.FORMAT_L8, buf.slice(ys + cs, ys + 2 * cs)))


func _finished() -> void:
	if film_id != "":
		_data().progress[film_id] = 0.0
		App.mark_dirty("library")
	close()


func toggle_pause() -> void:
	_paused = not _paused
	_player.stream_paused = _paused
	_update_play()
	_show_chrome()


func seek_to(t: float) -> void:
	if _av == null:
		return
	t = clampf(t, 0.0, maxf(0.0, float(_info.get("duration", 0.0)) - 1.0))
	_start(t)


func _update_play() -> void:
	_play_btn.icon = Style.icon("play" if _paused else "pause", 20, Color.WHITE)
	_play_btn.tooltip_text = "Play" if _paused else "Pause"
	_play_btn.accessibility_name = _play_btn.tooltip_text


static func _fmt(s: float) -> String:
	var t := int(maxf(0.0, s))
	return ("%d:%02d:%02d" % [t / 3600, (t / 60) % 60, t % 60]) if t >= 3600 else ("%d:%02d" % [t / 60, t % 60])


# ------------------------------------------------------------------ tracks
func _cycle_subs() -> void:
	if _sub_options.is_empty():
		return
	var next := _sub_choice + 1
	if next >= _sub_options.size():
		next = -1
	_set_subs(next)


func _set_subs(i: int) -> void:
	_sub_choice = i
	_subs = null
	_sub_label.text = ""
	if not App.library.has("films"):
		App.library.films = {}
	if not App.library.films.has("subs"):
		App.library.films.subs = {}
	App.library.films.subs[film_id] = i
	App.mark_dirty("library")
	if i < 0:
		_sub_btn.text = "Subtitles: off"
		return
	var o: Dictionary = _sub_options[i]
	_sub_btn.text = "Subtitles: " + str(o.label)
	if o.kind == "file":
		_subs = Subtitles.from_srt(FileAccess.get_file_as_string(o.path))
	else:
		_sub_btn.text = "Subtitles: preparing…"
		Subtitles.extract(_ff, file, int(o.n), func(p: String):
			if not is_instance_valid(self) or _sub_choice != i:
				return
			if p == "":
				_sub_btn.text = "Subtitles: unavailable"
				return
			_sub_btn.text = "Subtitles: " + str(o.label)
			_subs = Subtitles.from_srt(FileAccess.get_file_as_string(p)))


func _cycle_audio() -> void:
	var tracks: Array = _info.get("audio", [])
	if tracks.size() < 2:
		return
	_audio_track = (_audio_track + 1) % tracks.size()
	var a: Dictionary = tracks[_audio_track]
	_audio_btn.text = "Sound: " + (str(a.title) if str(a.title) != "" else str(a.lang).to_upper() if str(a.lang) != "" else str(_audio_track + 1))
	seek_to(_clock)


# ------------------------------------------------------------------ controls
func _bar_bg(top: bool) -> StyleBoxTexture:
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0.8) if top else Color(0, 0, 0, 0))
	g.set_color(1, Color(0, 0, 0, 0) if top else Color(0, 0, 0, 0.85))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_to = Vector2(0, 1)
	gt.width = 4
	gt.height = 64
	var sb := StyleBoxTexture.new()
	sb.texture = gt
	return sb


func _build_chrome() -> void:
	var top := PanelContainer.new()
	top.add_theme_stylebox_override("panel", _bar_bg(true))
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_bottom = 84
	var th := Style.hbox(18)
	var back := Style.icon_button("arrow-left", "Back", close, "Back")
	back.set_meta("sfx", "back")
	th.add_child(back)
	var tl := Style.label(title, "H2")
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tl.clip_text = true
	tl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	th.add_child(tl)
	top.add_child(Style.margin(th, 28, 16, 28, 18))
	add_child(top)
	_top = top

	var bottom := PanelContainer.new()
	bottom.add_theme_stylebox_override("panel", _bar_bg(false))
	bottom.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_top = -96
	var v := Style.vbox(6)
	v.size_flags_vertical = Control.SIZE_SHRINK_END
	_seek = HSlider.new()
	_seek.step = 1.0
	_seek.focus_mode = Control.FOCUS_NONE
	_seek.drag_started.connect(func(): _dragging = true)
	_seek.drag_ended.connect(func(_c):
		_dragging = false
		seek_to(_seek.value))
	_seek.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT and not _dragging:
			(func(): if not _dragging: seek_to(_seek.value)).call_deferred())
	v.add_child(_seek)
	var row := Style.hbox(14)
	_play_btn = Style.icon_button("pause", "Pause", toggle_pause)
	row.add_child(_play_btn)
	row.add_child(Style.icon_button("rotate-ccw", "Back 10 seconds", func(): seek_to(_clock - 10.0), "10"))
	row.add_child(Style.icon_button("fast-forward", "Forward 10 seconds", func(): seek_to(_clock + 10.0), "10"))
	_time = Style.label("0:00 / 0:00", "Meta")
	_time.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_time)
	_audio_btn = Style.button("Sound: 1", "", _cycle_audio)
	_audio_btn.visible = false
	row.add_child(_audio_btn)
	_sub_btn = Style.button("Subtitles: off", "", _cycle_subs)
	_sub_btn.visible = false
	row.add_child(_sub_btn)
	_vol = HSlider.new()
	_vol.custom_minimum_size.x = 110
	_vol.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_vol.min_value = 0.0
	_vol.max_value = 1.0
	_vol.step = 0.01
	_vol.focus_mode = Control.FOCUS_NONE
	_vol.value = float(App.settings.get("film_volume", 0.9))
	_vol.value_changed.connect(_set_volume)
	_set_volume(_vol.value)
	row.add_child(_vol)
	row.add_child(Style.button("Full screen", "", _toggle_fullscreen))
	v.add_child(row)
	bottom.add_child(Style.margin(v, 28, 18, 28, 14))
	add_child(bottom)
	_bottom = bottom


func _set_volume(x: float) -> void:
	_player.volume_db = linear_to_db(clampf(x, 0.0001, 1.0))
	App.settings.film_volume = x


func _toggle_fullscreen() -> void:
	var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)


func _show_chrome() -> void:
	_idle = 0.0
	if _chrome:
		return
	_chrome = true
	for c in [_top, _bottom]:
		c.visible = true
		create_tween().tween_property(c, "modulate:a", 1.0, 0.15)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _hide_chrome() -> void:
	_chrome = false
	for c in [_top, _bottom]:
		var tw := create_tween()
		tw.tween_property(c, "modulate:a", 0.0, 0.4)
		tw.tween_callback(func(): c.visible = _chrome)
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN


func _input(e: InputEvent) -> void:
	if e is InputEventMouseMotion and e.relative.length() > 2.0:
		_show_chrome()


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		if e.double_click:
			_toggle_fullscreen()
		else:
			toggle_pause()
		accept_event()


func _unhandled_key_input(e: InputEvent) -> void:
	if not e.pressed:
		return
	_show_chrome()
	var big: float = 60.0 if e.shift_pressed else 10.0
	match e.keycode:
		KEY_SPACE, KEY_K, KEY_MEDIAPLAY: toggle_pause()
		KEY_RIGHT, KEY_L: seek_to(_clock + big)
		KEY_LEFT, KEY_J: seek_to(_clock - big)
		KEY_UP: _vol.value = minf(1.0, _vol.value + 0.05)
		KEY_DOWN: _vol.value = maxf(0.0, _vol.value - 0.05)
		KEY_M: _vol.value = 0.0 if _vol.value > 0.0 else 0.9
		KEY_S: _cycle_subs()
		KEY_A: _cycle_audio()
		KEY_F, KEY_F11: _toggle_fullscreen()
		KEY_HOME: seek_to(0.0)
		KEY_ESCAPE: close()
		_: return
	get_viewport().set_input_as_handled()
