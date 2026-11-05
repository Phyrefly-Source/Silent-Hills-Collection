extends Control
## The window: backdrop, top bar (sections, now playing, settings), the current
## page, toasts and the modal layer. Pages are built the first time they're
## opened, so start-up only pays for the Games page.

const PAGES := {
	"news": "res://ui/pages/news_page.gd",
	"games": "res://ui/pages/games_page.gd",
	"comics": "res://ui/pages/comics_page.gd",
	"music": "res://ui/pages/music_page.gd",
	"concept": "res://ui/pages/concept_page.gd",
	"films": "res://ui/pages/movies_page.gd",
}

var backdrop: Control
var page_host: Control
var modal_layer: Control
var _pages := {}
var _nav := {}
var _current := ""
var _toasts: VBoxContainer
var _now_playing: HBoxContainer
var _np_label: Label
var _np_toggle: Button
var _status: Label


func _ready() -> void:
	if App.companion:
		# The phone app has its own shell.
		var c: Control = load("res://companion/companion_main.gd").new()
		get_parent().add_child.call_deferred(c)
		queue_free()
		return
	theme = Style.build()
	drop_controller_input()
	var fx := OS.get_environment("SILENTHILLS_NET_FIXTURES")
	if fx != "" and ResourceLoader.exists("res://tests/net_fixture.gd"):
		var f = load("res://tests/net_fixture.gd").new()
		f.dir = fx
		Net.set_meta("fixture_owner", f)   # a Callable alone does not keep it alive
		Net.fixture = f.reply
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Every button makes its sound profile's sound when pressed.
	get_tree().node_added.connect(_hook_sound)
	get_window().title = "Silent Hills"
	get_window().min_size = Vector2i(1100, 680)

	var bg := ColorRect.new()
	bg.color = Style.BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	backdrop = preload("res://ui/widgets/backdrop.gd").new()
	add_child(backdrop)
	# Scrims keep text readable whatever the artwork is: under the lists on
	# the left, the details at the bottom, and the top bar.
	var left := Style.scrim(SIDE_LEFT, 0.82)
	left.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	left.offset_right = 560
	add_child(left)
	var low := Style.scrim(SIDE_BOTTOM, 0.88)
	low.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	low.offset_top = -460
	add_child(low)
	var top := Style.scrim(SIDE_TOP, 0.7)
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_bottom = 120
	add_child(top)

	page_host = Control.new()
	page_host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page_host.offset_top = 72
	add_child(page_host)

	add_child(_top_bar())
	# Update banner: hidden until a newer release exists on GitHub.
	var banner: Control = preload("res://ui/widgets/update_banner.gd").new(App.svc("updater") as Updater)
	banner.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	banner.offset_left = 44
	banner.offset_right = -36
	banner.offset_top = 66
	add_child(banner)
	if OS.get_cmdline_args().has("--updated"):
		call_deferred("_toast", "Updated to Silent Hills %s." % ProjectSettings.get_setting("application/config/version"), "ok")
	# The phone companion's link (only listens when turned on in Settings).
	var comp = App.svc("companion")
	comp.pair_code.connect(_show_pair_code)

	_status = Style.label("", "Small")
	_status.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_status.position = Vector2(44, -34)
	_status.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(_status)

	_toasts = Style.vbox(8)
	_toasts.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_toasts.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_toasts.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_toasts.offset_right = -28
	_toasts.offset_bottom = -28
	_toasts.alignment = BoxContainer.ALIGNMENT_END
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_toasts)

	modal_layer = Control.new()
	modal_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(modal_layer)

	App.toast.connect(_toast)
	App.job_progress.connect(func(_job, text, _f): _status.text = text)
	Jukebox.track_changed.connect(func(_t): _update_now_playing())
	Jukebox.state_changed.connect(_update_now_playing)
	get_window().focus_entered.connect(_on_focus.bind(true))
	get_window().focus_exited.connect(_on_focus.bind(false))
	var runner = App.svc("runner")
	runner.session_started.connect(_on_game_started)
	runner.session_ended.connect(_on_game_ended)
	App.svc("achievements").earned.connect(_achievement_popup)

	show_page("news")
	var news = App.svc("news")
	news.unseen_changed.connect(_set_news_dot)
	if news.checked == 0 and not news.busy:
		news.refresh(true)
	_update_now_playing()
	_first_run_scan.call_deferred()
	_profile_prompt.call_deferred()
	_maybe_screenshot()


func _top_bar() -> Control:
	var bar := Style.hbox(28)
	bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	bar.offset_left = 44
	bar.offset_right = -36
	bar.offset_top = 22
	bar.custom_minimum_size.y = 36
	var mark := Style.label("SILENT HILLS", "Caps")
	mark.add_theme_font_override("font", Style.serif)
	mark.add_theme_font_size_override("font_size", 17)
	mark.add_theme_color_override("font_color", Style.INK)
	mark.add_theme_constant_override("outline_size", 0)
	bar.add_child(mark)
	bar.add_child(Style.spacer(0, 18))
	var find := Style.icon_button("search", "Search and commands (Ctrl+K)", open_palette, "", "Nav", 16)
	bar.add_child(find)
	for key in ["news", "games", "films", "comics", "music", "concept"]:
		var b := Style.button({"news": "NEWS", "games": "GAMES", "films": "FILMS", "comics": "COMICS", "music": "SOUNDTRACKS", "concept": "CONCEPT ART"}[key], "Nav", func(): show_page(key))
		b.toggle_mode = true
		b.set_meta("sfx", "none")   # show_page plays the section sound
		_nav[key] = b
		bar.add_child(b)
	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(fill)

	_now_playing = Style.hbox(10)
	_np_label = Style.label("", "Small")
	_np_label.custom_minimum_size.x = 0
	_np_label.clip_text = true
	_np_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_np_label.mouse_filter = Control.MOUSE_FILTER_STOP
	_np_label.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_np_label.gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed: show_page("music"))
	_np_toggle = Style.icon_button("pause", "Pause", func(): Jukebox.toggle(), "", "", 16)
	_np_toggle.set_meta("sfx", "none")
	_now_playing.add_child(_np_label)
	_now_playing.add_child(_np_toggle)
	var nx := Style.icon_button("skip-forward", "Next track", func(): Jukebox.next(), "", "", 16)
	nx.set_meta("sfx", "none")
	_now_playing.add_child(nx)
	bar.add_child(_now_playing)
	bar.add_child(_profile_bubble())
	return bar


# ------------------------------------------------------------------ profile
var _bubble: Button
var _bubble_menu: PopupMenu


## The round profile picture in the corner; it opens Profile and Settings.
func _profile_bubble() -> Button:
	_bubble = Button.new()
	_bubble.flat = true
	_bubble.custom_minimum_size = Vector2(44, 44)
	_bubble.expand_icon = true
	_bubble.focus_mode = Control.FOCUS_ALL
	_bubble.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_bubble.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_bubble.add_theme_constant_override("icon_max_width", 36)
	_bubble.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bubble.set_meta("sfx", "select")
	_bubble_menu = PopupMenu.new()
	_bubble_menu.add_theme_constant_override("icon_max_width", 16)
	_bubble_menu.id_pressed.connect(_on_bubble_item)
	_bubble.add_child(_bubble_menu)
	_bubble.pressed.connect(func():
		_fill_bubble_menu()
		var r := _bubble.get_global_rect()
		_bubble_menu.min_size = Vector2i(200, 0)
		_bubble_menu.popup_on_parent(Rect2i(int(r.end.x) - 220, int(r.end.y) + 6, 220, 0))
		# Right edge under the bubble's right edge.
		_bubble_menu.position.x = int(r.end.x) - _bubble_menu.size.x)
	App.svc("accounts").changed.connect(_update_bubble)
	_update_bubble()
	return _bubble


func _on_bubble_item(i: int) -> void:
	if i == 0:
		open_profile()
	elif i == 1:
		open_settings()
	elif i == 2:
		App.svc("accounts").sign_out()
	elif i == 3:
		open_account("create")
	elif i == 4:
		open_account("sign_in")


func _update_bubble() -> void:
	var acc = App.svc("accounts")
	_bubble.icon = acc.avatar_texture(72)
	_bubble.tooltip_text = "%s: profile and settings" % acc.display_name()
	_bubble.accessibility_name = _bubble.tooltip_text


func _fill_bubble_menu() -> void:
	var acc = App.svc("accounts")
	_bubble_menu.clear()
	_bubble_menu.add_separator(acc.display_name())
	_bubble_menu.add_icon_item(Style.icon("user", 16, Color.WHITE), "Profile", 0)
	_bubble_menu.add_icon_item(Style.icon("settings", 16, Color.WHITE), "Settings", 1)
	_bubble_menu.add_separator()
	if acc.signed_in():
		_bubble_menu.add_icon_item(Style.icon("log-out", 16, Color.WHITE), "Sign out", 2)
	else:
		_bubble_menu.add_icon_item(Style.icon("user-plus", 16, Color.WHITE), "Make a profile", 3)
		if acc.has_profiles():
			_bubble_menu.add_icon_item(Style.icon("log-in", 16, Color.WHITE), "Sign in", 4)


func open_profile() -> void:
	var v: Control = load("res://ui/widgets/profile_view.gd").new()
	v.set("main", self)
	modal_layer.add_child(v)


## mode: "create" or "sign_in".
func open_account(mode: String, first_run: bool = false) -> void:
	var d: Control = load("res://ui/widgets/account_dialog.gd").new()
	d.set("main", self)
	d.set("mode", mode)
	d.set("first_run", first_run)
	var m := open_modal(d, 560)
	d.set("modal", m)


## At start: sign in (or make the first profile) unless already signed in.
func _profile_prompt() -> void:
	var acc = App.svc("accounts")
	if acc.signed_in() or Array(OS.get_cmdline_user_args()).any(func(a): return str(a).begins_with("--shot=")):
		return
	if acc.has_profiles():
		open_account("sign_in")
	elif not App.settings.get("profile_prompt_skipped", false):
		open_account("create", true)


func show_page(key: String) -> void:
	if key == _current:
		return
	if _current != "":
		Sfx.play("tab")
	for k in _nav:
		_nav[k].button_pressed = k == key
	if not _pages.has(key):
		var p: Control = load(PAGES[key]).new()
		p.set("main", self)
		p.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		page_host.add_child(p)
		_pages[key] = p
	for k in _pages:
		_pages[k].visible = k == key
	_current = key
	if key == "news":
		_set_news_dot(0)
	if _pages[key].has_method("on_shown"):
		_pages[key].on_shown()


## A dot on NEWS when there's a sale or a new-entry headline not seen yet.
func _set_news_dot(count: int) -> void:
	var b: Button = _nav.get("news")
	if b == null:
		return
	if count > 0 and _current != "news":
		b.icon = Style._dot(8, Style.ACCENT)
		b.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		b.tooltip_text = "%d new: sales or news about new Silent Hill games" % count
	else:
		b.icon = null
		b.tooltip_text = ""


func _update_now_playing() -> void:
	var t: Dictionary = Jukebox.current
	_now_playing.visible = not t.is_empty()
	if t.is_empty():
		return
	_np_label.text = "%s  ·  %s" % [App.svc("music").title_of(t), t.get("album", "")]
	_np_toggle.icon = Style.icon("pause" if Jukebox.playing else "play", 16, Color.WHITE)
	_np_toggle.tooltip_text = "Pause" if Jukebox.playing else "Play"
	_np_toggle.accessibility_name = _np_toggle.tooltip_text


## A phone asked to pair: show the code it needs, big, until it's used or closed.
func _show_pair_code(code: String, device: String) -> void:
	var v := Style.vbox(16)
	v.add_child(Style.label("Pair %s" % device, "H1"))
	v.add_child(Style.label("Type this code into the Silent Hills app on your phone:", "Body", true))
	var c := Style.label("%s %s" % [code.substr(0, 3), code.substr(3)], "Title")
	c.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(c)
	v.add_child(Style.label("It works for 2 minutes. If you didn't start this, just close it.", "Small", true))
	var m: Control
	v.add_child(Style.button("Close", "Ghost", func(): m.queue_free()))
	m = open_modal(v, 520)
	App.svc("companion").paired.connect(func(_d):
		if is_instance_valid(m):
			m.queue_free(), CONNECT_ONE_SHOT)


## Buttons play "select", closing buttons "back"; a button can choose its own
## sound with set_meta("sfx", "move" | "tab" | "none" …).
func _hook_sound(n: Node) -> void:
	if n is BaseButton and not n.has_meta("sfx_hooked"):
		n.set_meta("sfx_hooked", true)
		n.pressed.connect(func():
			var ev := str(n.get_meta("sfx", ""))
			if ev == "":
				var t: String = n.text if n is Button else ""
				ev = "back" if t in ["Close", "Done", "Cancel", "←  Back", "←  All comics", "Back to the shelf"] else "select"
			if ev != "none":
				Sfx.play(ev))


# ------------------------------------------------------------------ while a game runs
var _mode_before_game := Window.MODE_WINDOWED
var _in_tray := false
var _tray: StatusIndicator
var _tray_menu: PopupMenu


## In the background the launcher draws less often. (Input and sounds are
## only shut off while a game runs: see _set_playing. Tying them to window
## focus froze the launcher, because a dropdown's list is its own window and
## takes the focus while it's open.)
func _on_focus(on: bool) -> void:
	if App.svc("runner").sessions.is_empty():
		Engine.max_fps = 0 if on else 30


## While a game runs the launcher takes no input and makes no sound.
func _set_playing(on: bool) -> void:
	get_viewport().gui_disable_input = on
	Sfx.muted = on
	Engine.max_fps = 30 if on else 0


## Controllers have no say in the launcher at all: their events are taken out
## of every input action, and anything a pad still sends is dropped (see _input).
static func drop_controller_input() -> void:
	for action in InputMap.get_actions():
		for ev in InputMap.action_get_events(action):
			if ev is InputEventJoypadButton or ev is InputEventJoypadMotion:
				InputMap.action_erase_event(action, ev)


## While a game runs, the launcher closes to the system tray (an icon by the
## clock); clicking it brings the launcher back.
func _on_game_started(id: String) -> void:
	_set_playing(true)
	if not App.settings.get("minimize_on_play", true):
		return
	var w := get_window()
	if not _in_tray:
		_mode_before_game = w.mode if w.mode != Window.MODE_MINIMIZED else Window.MODE_WINDOWED
	_in_tray = true
	_show_tray("%s is running" % App.game(id).get("title", "A game"))
	w.mode = Window.MODE_MINIMIZED
	_hide_from_taskbar()


## Godot can't hide its main window, so Windows is asked to directly: the
## minimised window disappears from the taskbar too, leaving only the tray icon.
## Coming back (_from_tray) restores it the normal way, which shows it again.
func _hide_from_taskbar() -> void:
	if OS.get_name() != "Windows":
		return
	var hwnd := DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE)
	if hwnd == 0:
		return
	var ps := "Add-Type -Name W -Namespace SilentHills -MemberDefinition '[DllImport(\"user32.dll\")] public static extern bool ShowWindowAsync(System.IntPtr h, int c);'; [SilentHills.W]::ShowWindowAsync([System.IntPtr]%d, 0) | Out-Null" % hwnd
	# Passed encoded (UTF-16LE base64) so no quoting survives the command line.
	var enc := Marshalls.raw_to_base64(ps.to_utf16_buffer())
	OS.create_process("powershell.exe", ["-NoProfile", "-NonInteractive", "-WindowStyle", "Hidden", "-EncodedCommand", enc], false)


func _show_tray(tip: String) -> void:
	if _tray == null:
		_tray_menu = PopupMenu.new()
		_tray_menu.add_item("Open Silent Hills", 0)
		_tray_menu.add_separator()
		_tray_menu.add_item("Quit Silent Hills", 1)
		_tray_menu.id_pressed.connect(func(i):
			if i == 0:
				_from_tray()
			else:
				App.flush()
				get_tree().quit())
		add_child(_tray_menu)
		_tray = StatusIndicator.new()
		var img: Image = load("res://icon.png").get_image()
		img.resize(64, 64, Image.INTERPOLATE_LANCZOS)
		_tray.icon = ImageTexture.create_from_image(img)
		_tray.pressed.connect(func(button: int, _pos: Vector2i):
			if button == MOUSE_BUTTON_LEFT:
				_from_tray())
		add_child(_tray)
		_tray.menu = _tray.get_path_to(_tray_menu)
	_tray.tooltip = "Silent Hills  ·  " + tip
	_tray.visible = true


## Out of the tray: the window comes back as it was, in front.
func _from_tray() -> void:
	_in_tray = false
	if _tray:
		_tray.visible = false
	var w := get_window()
	w.mode = _mode_before_game if _mode_before_game != Window.MODE_MINIMIZED else Window.MODE_WINDOWED
	w.move_to_foreground()
	w.grab_focus()
	_set_playing(false)


## Back on the desktop when the last game closes.
func _on_game_ended(_id: String, _seconds: int) -> void:
	if not App.svc("runner").sessions.is_empty():
		return
	if _in_tray:
		_from_tray()
	else:
		_set_playing(false)


## Keyboard moves through the launcher play "move". Controller events are
## dropped here, whatever they are.
func _input(e: InputEvent) -> void:
	if e is InputEventJoypadButton or e is InputEventJoypadMotion:
		get_viewport().set_input_as_handled()
		return
	if e.is_echo() or not e.is_pressed() or not e is InputEventKey:
		return
	for a in ["ui_up", "ui_down", "ui_left", "ui_right", "ui_focus_next", "ui_focus_prev"]:
		if e.is_action_pressed(a) and get_viewport().gui_get_focus_owner() != null:
			Sfx.play("move")
			return


func _unhandled_key_input(e: InputEvent) -> void:
	if not e.pressed or e.echo:
		return
	if e.ctrl_pressed:
		match e.keycode:
			KEY_1: show_page("news")
			KEY_2: show_page("games")
			KEY_3: show_page("films")
			KEY_4: show_page("comics")
			KEY_5: show_page("music")
			KEY_6: show_page("concept")
			KEY_COMMA: open_settings()
			KEY_K: open_palette()


# ------------------------------------------------------------------ modal
## Puts a control in the middle of the window over a dark scrim.
func open_modal(content: Control, width: int = 640) -> Control:
	var scrim := ColorRect.new()
	scrim.color = Color(Style.BG, 0.78)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", Style.raised_box(Style.SPACE_2XL, Style.SPACE_2XL))
	panel.custom_minimum_size.x = width
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.add_child(content)
	scrim.add_child(panel)
	scrim.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and not panel.get_global_rect().has_point(e.global_position):
			scrim.queue_free())
	# Esc closes it; keyboard focus starts inside it and goes back afterwards.
	var before := get_viewport().gui_get_focus_owner()
	scrim.set_meta("modal", true)
	scrim.tree_exited.connect(func():
		if is_instance_valid(before) and before.is_visible_in_tree():
			before.grab_focus())
	modal_layer.add_child(scrim)
	_focus_first.call_deferred(panel)
	scrim.modulate.a = 0.0
	Style.tween(scrim).tween_property(scrim, "modulate:a", 1.0, Style.DUR_MICRO)
	return scrim


func _focus_first(root: Node) -> void:
	if not is_instance_valid(root):
		return
	for n in root.find_children("*", "Control", true, false):
		var c := n as Control
		if c.focus_mode == Control.FOCUS_ALL and c.is_visible_in_tree() and not (c is BaseButton and c.disabled):
			c.grab_focus()
			return


## Esc closes the topmost modal (or the command palette).
func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_ESCAPE:
		for i in range(modal_layer.get_child_count() - 1, -1, -1):
			var m := modal_layer.get_child(i)
			if m.has_meta("modal") or m.has_method("close"):
				if m.has_method("close"):
					m.close()
				else:
					m.queue_free()
				get_viewport().set_input_as_handled()
				return


func open_palette() -> void:
	for m in modal_layer.get_children():
		if m.get_script() == preload("res://ui/widgets/command_palette.gd"):
			return
	var p: Control = preload("res://ui/widgets/command_palette.gd").new()
	p.main = self
	modal_layer.add_child(p)


func open_settings() -> void:
	var s: Control = load("res://ui/settings_panel.gd").new()
	s.set("main", self)
	var m := open_modal(s, 680)
	s.set("modal", m)


func confirm(text: String, ok_label: String, cb: Callable) -> void:
	var v := Style.vbox(20)
	v.add_child(Style.label(text, "H2", true))
	var row := Style.hbox(10)
	row.alignment = BoxContainer.ALIGNMENT_END
	var m: Control
	row.add_child(Style.button("Cancel", "Ghost", func(): m.queue_free()))
	row.add_child(Style.button(ok_label, "Primary", func():
		m.queue_free()
		cb.call()))
	v.add_child(row)
	m = open_modal(v, 520)


## Native file / folder chooser. mode: "file" | "folder"; cb(path or "").
func choose_path(title: String, mode: String, filters: PackedStringArray, cb: Callable) -> void:
	if DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_FILE):
		DisplayServer.file_dialog_show(title, "", "", false,
			DisplayServer.FILE_DIALOG_MODE_OPEN_DIR if mode == "folder" else DisplayServer.FILE_DIALOG_MODE_OPEN_FILE,
			filters, func(status: bool, paths: PackedStringArray, _idx: int):
				cb.call(paths[0].replace("\\", "/") if status and not paths.is_empty() else ""))
		return
	var fd := FileDialog.new()
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.file_mode = FileDialog.FILE_MODE_OPEN_DIR if mode == "folder" else FileDialog.FILE_MODE_OPEN_FILE
	fd.filters = filters
	fd.title = title
	fd.size = Vector2i(900, 600)
	fd.dir_selected.connect(func(p): cb.call(p))
	fd.file_selected.connect(func(p): cb.call(p))
	fd.canceled.connect(func(): cb.call(""))
	add_child(fd)
	fd.popup_centered()


# ------------------------------------------------------------------ toasts
func _toast(text: String, kind: String) -> void:
	var p := PanelContainer.new()
	var sb := Style.raised_box(Style.SPACE_L, Style.SPACE_M)
	sb.border_color = Style.DANGER if kind == "error" else Style.LINE
	sb.border_width_left = 3 if kind == "error" else 1
	p.add_theme_stylebox_override("panel", sb)
	var h := Style.hbox(Style.SPACE_M)
	var ic := TextureRect.new()
	ic.texture = Style.icon("circle-alert" if kind == "error" else ("check" if kind == "ok" else "info"), 20,
		Style.DANGER if kind == "error" else (Style.OK if kind == "ok" else Style.INK_2))
	ic.custom_minimum_size = Vector2(20, 20)
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	h.add_child(ic)
	var l := Style.label(text, "Meta", true)
	l.custom_minimum_size.x = 340
	l.add_theme_color_override("font_color", Style.INK)
	h.add_child(l)
	p.add_child(h)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toasts.add_child(p)
	p.modulate.a = 0.0
	var tw := Style.tween(p)
	tw.tween_property(p, "modulate:a", 1.0, Style.DUR_UI)
	tw.tween_interval(5.0 if kind != "error" else 8.0)
	tw.tween_property(p, "modulate:a", 0.0, Style.DUR_UI)
	tw.tween_callback(p.queue_free)


## An achievement was unlocked: its icon, name and game, bottom right, the
## way Steam shows them. Clicking it opens the game's achievements.
func _achievement_popup(game_id: String, it: Dictionary) -> void:
	var p := PanelContainer.new()
	var sb := Style.raised_box(Style.SPACE_M, Style.SPACE_M)
	sb.border_color = Style.accent_text(Style.color_hex(App.entry(game_id).get("accent", "")))
	sb.border_width_left = 3
	p.add_theme_stylebox_override("panel", sb)
	p.custom_minimum_size.x = 380
	var h := Style.hbox(Style.SPACE_M)
	var box := Panel.new()
	box.custom_minimum_size = Vector2(56, 56)
	box.clip_contents = true
	var bsb := StyleBoxFlat.new()
	bsb.bg_color = Style.HOVER
	bsb.set_corner_radius_all(Style.RADIUS)
	box.add_theme_stylebox_override("panel", bsb)
	var url := str(it.get("icon_unlocked", it.get("icon", "")))
	if url != "":
		var img: TextureRect = load("res://ui/widgets/net_image.gd").new(url, Vector2(56, 56))
		img.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		img.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(img)
	h.add_child(box)
	var v := Style.vbox(2)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	v.add_child(Style.label("ACHIEVEMENT UNLOCKED", "Caps"))
	var n := Style.label(str(it.get("name", "")), "", true)
	n.add_theme_font_override("font", Style.sans_medium)
	n.add_theme_color_override("font_color", Style.INK)
	v.add_child(n)
	var r := float(it.get("rarity", -1.0))
	v.add_child(Style.label(str(App.entry(game_id).get("title", game_id)) + (("  ·  %.1f%% of players" % r) if r >= 0.0 else ""), "Small"))
	h.add_child(v)
	p.add_child(h)
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	p.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	p.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			show_page("games")
			_pages.games.call("select", game_id)
			_pages.games.call("_open_drawer", "achievements")
			p.queue_free())
	_toasts.add_child(p)
	Sfx.play("select")
	p.modulate.a = 0.0
	var tw := Style.tween(p)
	tw.set_parallel(true)
	tw.tween_property(p, "modulate:a", 1.0, Style.DUR_UI)
	tw.chain().tween_interval(6.0)
	tw.chain().tween_property(p, "modulate:a", 0.0, Style.DUR_UI)
	tw.chain().tween_callback(p.queue_free)


# ------------------------------------------------------------------ first run
func _first_run_scan() -> void:
	var last := int(App.library.get("last_scan", 0))
	if Time.get_unix_time_from_system() - last < 3 * 86400:
		App.svc("music").refresh_if_changed()
		return
	scan_everything(true)


func scan_everything(quiet: bool = false) -> void:
	_status.text = "Looking for your games…"
	var scanner = App.svc("scanner")
	App.run(func(): return scanner.scan("", func(t): App.job_progress.emit.call_deferred("scan", t, 0.0)),
		func(res):
			_status.text = ""
			var n := apply_scan(res, false)
			App.library.last_scan = int(Time.get_unix_time_from_system())
			App.mark_dirty("library")
			App.svc("music").refresh_if_changed()
			if not quiet or n > 0:
				App.notify("Connected %d game%s." % [n, "" if n == 1 else "s"] if n > 0 else "No new games found. You can browse to a game from its page."))


## Applies scan results to games that aren't connected yet. Returns how many changed.
func apply_scan(res: Dictionary, overwrite: bool) -> int:
	var n := 0
	for id in res.steam:
		var gs := App.state(id)
		if overwrite or gs.path == "" or not DirAccess.dir_exists_absolute(gs.path):
			App.set_state(id, {"path": res.steam[id].dir, "steam_appid": res.steam[id].appid})
			n += 1
	for id in res.installs:
		var gs := App.state(id)
		var first: Dictionary = res.installs[id][0]
		if overwrite or gs.path == "" or not DirAccess.dir_exists_absolute(gs.path):
			var g := App.game(id)
			var patch := {"path": first.path}
			if g.route.kind == "rebuild":
				patch.exe = first.exe
			App.set_state(id, patch)
			n += 1
	for id in res.dumps:
		var gs := App.state(id)
		if overwrite or str(gs.get("dump", "")) == "" or not (FileAccess.file_exists(gs.dump) or DirAccess.dir_exists_absolute(gs.dump)):
			App.set_state(id, {"dump": res.dumps[id][0].path})
			n += 1
	return n


# ------------------------------------------------------------------ testing
func _maybe_screenshot() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			var spec := a.substr(7)   # path[,page[,game]]
			var parts := spec.split(",")
			if parts.size() > 1:
				show_page(parts[1])
			if parts.size() > 2 and parts[2] != "" and _pages.has("games"):
				_pages.games.call("select", parts[2])
			if parts.size() > 4 and parts[4] != "":
				if parts[4] == "settings":
					open_settings()
				elif parts[4] == "profile":
					open_profile()
				elif parts[4] == "menu":
					await get_tree().create_timer(1.0).timeout
					_bubble.pressed.emit()
				elif parts[4].begins_with("account:"):
					open_account(parts[4].substr(8), parts[4].ends_with("create"))
				elif parts[4].begins_with("palette"):
					open_palette()
					await get_tree().process_frame
					if parts[4].contains(":"):
						var pal: Control = modal_layer.get_child(-1)
						pal._field.text = parts[4].split(":")[1]
						pal._filter()
				elif parts[4].begins_with("picker:"):
					var pk := parts[4].split(":")
					var ap: Control = load("res://ui/widgets/art_picker.gd").new()
					ap.set("main", self)
					ap.set("game_id", pk[1])
					ap.set("kind", "hero")
					modal_layer.add_child(ap)
					if pk.size() > 2:
						await get_tree().create_timer(0.5).timeout
						ap.call("_show_tab", pk[2])
				elif parts[4] == "reader":
					await get_tree().create_timer(1.5).timeout
					var items: Array = App.svc("comics").items
					if not items.is_empty():
						_pages.comics.call("_open", items[0])
				elif parts[4].begins_with("play:"):
					await get_tree().create_timer(1.0).timeout
					var fid := parts[4].substr(5)
					_pages.films.call("play_file", App.svc("movies").path_of(fid), fid, App.entry(fid).title)
					if parts.size() > 5:
						await get_tree().create_timer(1.5).timeout
						modal_layer.get_child(-1).call(parts[5])
				elif parts[4].begins_with("concept:"):
					var cbits := parts[4].split(":")
					_pages.concept.call("open_game", cbits[1])
					if parts.size() > 5:
						await get_tree().create_timer(2.0).timeout
						var v: Control = load("res://ui/widgets/image_viewer.gd").new()
						v.set("pictures", _pages.concept.get("_pictures"))
						v.set("index", int(parts[5]))
						modal_layer.add_child(v)
				elif parts[4].begins_with("series:"):
					await get_tree().create_timer(1.5).timeout
					_pages.comics.call("open_series", parts[4].substr(7))
				elif parts[4].begins_with("read:"):
					# read:<series>:<copy index>:<page>
					await get_tree().create_timer(1.5).timeout
					var bits := parts[4].split(":")
					var sh: Array = App.svc("comics").shelf().filter(func(x): return x.entry.id == bits[1])
					if not sh.is_empty():
						_pages.comics.call("_open", sh[0].copies[int(bits[2])], int(bits[3]))
						if bits.size() > 4 and bits[4] == "end":
							await get_tree().create_timer(1.0).timeout
							modal_layer.get_child(-1).call("turn", 1)
				elif parts[4].begins_with("album:"):
					_pages.music.call("_open", parts[4].substr(6))
				else:
					_pages.games.call("_open_drawer", parts[4])
			var rs := OS.get_environment("SILENTHILLS_RESIZE")
			if rs != "":
				await get_tree().create_timer(1.0).timeout
				get_window().size = Vector2i(int(rs.split("x")[0]), int(rs.split("x")[1]))
			await get_tree().create_timer(float(parts[3]) if parts.size() > 3 else 4.0).timeout
			print("backdrop ", backdrop.size, " front ", backdrop._front.texture, " a ", backdrop._front.modulate.a)
			get_viewport().get_texture().get_image().save_png(parts[0])
			get_tree().quit()
