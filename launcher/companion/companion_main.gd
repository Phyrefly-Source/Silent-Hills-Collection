extends Control
## Silent Hills companion app (Android): the desktop launcher's achievements,
## plus concept art, soundtracks, comics and films, on your phone.
## Portrait, one section at a time, with a tab bar along the bottom.
## Data comes from the paired PC over the home network and is kept, so the
## app also works away from home.

const SECTIONS := [
	["achievements", "Achievements", "trophy"],
	["concept", "Art", "image"],
	["music", "Music", "music"],
	["comics", "Comics", "book-open"],
	["films", "Films", "film"],
]

var _body: Control
var _tabs := {}
var _status: Label
var _section := ""
var _ach_data := {}
var _modal: Control
var _banner: VBoxContainer
var _offered := {}
var _overlays: Array = []
var _mini: PanelContainer
var _scale := 1.0
var Player   # phone_player.gd: the music player, kept while you move around


func _ready() -> void:
	Style.touch = true
	theme = Style.build()
	get_tree().quit_on_go_back = false   # back closes screens first (see _notification)
	_fit_to_screen()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Style.BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var col := Style.vbox(0)
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(col)
	# Top: name and the PC link.
	var top := Style.vbox(2)
	var mark := Style.label("SILENT HILLS", "Caps")
	mark.add_theme_font_override("font", Style.serif)
	mark.add_theme_font_size_override("font_size", 20)
	mark.add_theme_color_override("font_color", Style.INK)
	top.add_child(mark)
	var srow := Style.hbox(8)
	_status = Style.label("", "Small")
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.clip_text = true
	_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	srow.add_child(_status)
	var more := Style.icon_button("monitor-smartphone", "Your PC", _pc_menu, "", "", 24)
	more.custom_minimum_size = Vector2(Style.TARGET_TOUCH, Style.TARGET_TOUCH)
	more.add_theme_font_size_override("font_size", 13)
	srow.add_child(more)
	top.add_child(srow)
	col.add_child(Style.margin(top, 18, 14, 12, 8))
	_banner = Style.vbox(6)
	_banner.visible = false
	col.add_child(Style.margin(_banner, 16, 0, 16, 8))
	_body = Control.new()
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.clip_contents = true
	col.add_child(_body)
	Player = load("res://companion/phone_player.gd").new()
	add_child(Player)
	Player.changed.connect(_update_mini)
	Player.failed.connect(func(m): App.notify(m))
	_mini = _mini_player()
	col.add_child(_mini)
	# Bottom: tab bar.
	var bar := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.04, 0.045, 1)
	sb.border_color = Style.LINE
	sb.border_width_top = 1
	sb.content_margin_top = Style.SPACE_XS
	sb.content_margin_bottom = Style.SPACE_S
	bar.add_theme_stylebox_override("panel", sb)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 0)
	# A bottom tab bar: a 24 px icon over a short label, 56 px tall.
	for s in SECTIONS:
		var key: String = s[0]
		var b := Button.new()
		b.toggle_mode = true
		b.flat = true
		b.focus_mode = Control.FOCUS_ALL
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size.y = 56
		b.accessibility_name = s[1]
		b.tooltip_text = s[1]
		b.set_meta("sfx", "none")
		b.pressed.connect(func(): show_section(key))
		var v := Style.vbox(2)
		v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var ic := TextureRect.new()
		ic.name = "Icon"
		ic.custom_minimum_size = Vector2(24, 24)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		ic.texture = Style.icon(s[2], 24, Color.WHITE)
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(ic)
		var l := Style.label(s[1], "")
		l.name = "Label"
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_font_override("font", Style.sans_medium)
		l.add_theme_font_size_override("font_size", 12)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(l)
		b.add_child(v)
		_tabs[key] = b
		tabs.add_child(b)
	bar.add_child(tabs)
	col.add_child(bar)

	var pc = App.svc("pc")
	pc.status_changed.connect(_update_status)
	App.toast.connect(_toast)
	_update_status()
	if not pc.paired():
		_pair_screen()
	else:
		show_section("achievements")
		_check_update()
	_maybe_screenshot()


## Phones have dense screens: lay out at roughly 160 dpi, portrait.
func _fit_to_screen() -> void:
	var w := get_window()
	if OS.has_feature("mobile"):
		var dpi := float(DisplayServer.screen_get_dpi())
		_scale = clampf(dpi / 160.0, 1.0, 4.0)
		w.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
		w.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
		_refit()
		# Turning the phone (films play sideways) changes the window's shape.
		w.size_changed.connect(_refit)
	else:
		# Trying the app on a PC: a phone-shaped window.
		w.min_size = Vector2i(360, 640)
		w.size = Vector2i(412, 900)


func _refit() -> void:
	var w := get_window()
	w.content_scale_size = Vector2i(Vector2(w.size) / _scale)


static func fmt_time(s: float) -> String:
	var t := int(s)
	return ("%d:%02d:%02d" % [t / 3600, (t / 60) % 60, t % 60]) if t >= 3600 else ("%d:%02d" % [t / 60, t % 60])


## Something full screen over everything (the comic reader, the film player,
## the music player). Android's back gesture closes the top one.
func overlay(node: Control) -> void:
	node.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(node)
	_overlays.append(node)
	node.tree_exited.connect(func(): _overlays.erase(node))


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_RESUMED and is_instance_valid(_banner):
		_check_update()
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		# Android's back gesture closes what's open, then the app.
		if is_instance_valid(_modal):
			_modal.queue_free()
		elif not _overlays.is_empty():
			var top: Control = _overlays[-1]
			if top.has_method("close"):
				top.close()
			else:
				top.queue_free()
		elif _body.get_child_count() > 1:
			_body.get_child(-1).queue_free()
		else:
			App.flush()
			get_tree().quit()


func _update_status() -> void:
	var pc = App.svc("pc")
	if not pc.paired():
		_status.text = "Not paired with a PC"
		return
	var p: Dictionary = pc.pc()
	var last := int(App.settings.get("companion_last_sync", 0))
	if pc.online:
		_status.text = "● %s  ·  connected" % p.get("name", "PC")
		pc.flush_outbox()
	elif last > 0:
		_status.text = "○ %s  ·  last synced %s" % [p.get("name", "PC"), App.fmt_ago(last)]
	else:
		_status.text = "○ %s  ·  not reachable" % p.get("name", "PC")


func _toast(text: String, _kind: String) -> void:
	var l := Style.label(text, "Small", true)
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.1, 0.11, 0.97)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(12)
	p.add_theme_stylebox_override("panel", sb)
	p.add_child(l)
	p.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	p.offset_left = -170
	p.offset_right = 170
	p.offset_bottom = -90
	p.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(p)
	var tw := create_tween()
	tw.tween_interval(3.0)
	tw.tween_property(p, "modulate:a", 0.0, 0.4)
	tw.tween_callback(p.queue_free)


func _clear() -> void:
	for c in _body.get_children():
		c.queue_free()


func show_section(key: String) -> void:
	if key != _section and _section != "":
		Sfx.play("tab")
	_section = key
	for k in _tabs:
		_tabs[k].button_pressed = k == key
		var on: bool = k == key
		_tabs[k].find_child("Icon", true, false).modulate = Style.INK if on else Style.INK_3
		_tabs[k].find_child("Label", true, false).add_theme_color_override("font_color", Style.INK if on else Style.INK_3)
	_clear()
	match key:
		"achievements":
			_achievements()
		"concept":
			_concept_list()
		"music", "comics", "films":
			var scr: Control = load("res://companion/%s_screen.gd" % key).new()
			scr.main = self
			_push(scr)


func _push(screen: Control) -> void:
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_body.add_child(screen)


func _scroll_page() -> Array:
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var v := Style.vbox(12)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(Style.margin(v, 16, 8, 16, 24))
	(scroll.get_child(0) as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return [scroll, v]


# ------------------------------------------------------------------ updates
## The PC carries the latest companion app; offer it when it's newer.
func _check_update() -> void:
	App.svc("pc").check_update(func(info: Dictionary):
		if not is_instance_valid(_banner) or info.is_empty() or _offered.get("code", 0) == info.code:
			return
		_offered = info
		_show_update(info))


func _show_update(info: Dictionary) -> void:
	for c in _banner.get_children():
		c.queue_free()
	_banner.visible = true
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.09, 0.1, 1)
	sb.border_color = Style.LINE
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", sb)
	var v := Style.vbox(8)
	var msg := Style.label("Version %s of this app is ready on %s (you have %s)." % [info.version, App.svc("pc").pc().get("name", "your PC"), App.svc("pc").APP_VERSION], "Small", true)
	v.add_child(msg)
	var row := Style.hbox(8)
	var go := Style.button("Update", "Primary", Callable())
	var later := Style.button("Later", "Ghost", func(): _banner.visible = false)
	row.add_child(go)
	row.add_child(later)
	v.add_child(row)
	var bar := ProgressBar.new()
	bar.visible = false
	bar.show_percentage = false
	bar.custom_minimum_size.y = 4
	v.add_child(bar)
	panel.add_child(v)
	_banner.add_child(panel)
	var pc = App.svc("pc")
	go.pressed.connect(func():
		go.disabled = true
		later.visible = false
		bar.visible = true
		msg.text = "Downloading from %s…" % pc.pc().get("name", "your PC")
		var on_progress := func(done: int, total: int):
			if is_instance_valid(bar) and total > 0:
				bar.max_value = total
				bar.value = done
				msg.text = "Downloading from %s…  %d of %d MB" % [pc.pc().get("name", "your PC"), done / 1048576, total / 1048576]
		pc.update_progress.connect(on_progress)
		pc.download_update(str(info.get("sha256", "")), func(ok: bool, m: String):
			pc.update_progress.disconnect(on_progress)
			if not is_instance_valid(msg):
				return
			go.disabled = false
			bar.visible = false
			if not ok:
				msg.text = m
				go.text = "Try again"
				return
			msg.text = "Downloaded. Android will ask to install the update (the first time, allow Silent Hills to install apps, then come back and tap Install)."
			go.text = "Install"
			for c in go.pressed.get_connections():
				go.pressed.disconnect(c.callable)
			go.pressed.connect(func():
				var err: String = pc.install_update()
				if err != "":
					msg.text = err)
			var err: String = pc.install_update()
			if err != "":
				msg.text = err))


# ------------------------------------------------------------------ pairing
func _pair_screen() -> void:
	_clear()
	for k in _tabs:
		_tabs[k].disabled = true
	var pv := _scroll_page()
	var v: VBoxContainer = pv[1]
	_push(pv[0])
	v.add_child(Style.label("Connect to your PC", "H1", true))
	v.add_child(Style.label("This app shows the Silent Hills launcher's progress from your PC. On the PC, open Silent Hills → Settings → Phone companion and turn on \"Let the phone app connect\". Then, with this phone on the same Wi-Fi:", "Body", true))
	var found := Style.vbox(8)
	var find := Style.button("Find my PC", "Primary", Callable())
	find.custom_minimum_size.y = 52
	find.pressed.connect(func():
		find.disabled = true
		find.text = "Looking…"
		for c in found.get_children():
			c.queue_free()
		App.svc("pc").discover(func(list: Array):
			if not is_instance_valid(find):
				return
			find.disabled = false
			find.text = "Look again"
			if list.is_empty():
				found.add_child(Style.label("No PC answered. Check the setting on the PC and that both are on the same Wi-Fi, or type the PC's address below.", "Small", true))
			for pc in list:
				var b := Style.button("%s  ·  %s" % [pc.name, pc.host], "Ghost", func(): _start_pair(pc.host, int(pc.port), pc.name, v))
				b.custom_minimum_size.y = 48
				found.add_child(b), 2.5, _extra_hosts()))
	v.add_child(find)
	v.add_child(found)
	v.add_child(Style.spacer(10))
	v.add_child(Style.label("Or type its address (shown in the PC's Settings):", "Small", true))
	var row := Style.hbox(8)
	var addr := LineEdit.new()
	addr.placeholder_text = "192.168.1.20"
	addr.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_URL
	addr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(addr)
	row.add_child(Style.button("Connect", "Ghost", func():
		if addr.text.strip_edges() != "":
			_start_pair(addr.text.strip_edges(), App.svc("pc").PORT, addr.text.strip_edges(), v)))
	v.add_child(row)


func _extra_hosts() -> Array:
	var h := OS.get_environment("SILENTHILLS_COMPANION_HOST")
	return [h] if h != "" else []


func _start_pair(host: String, port: int, name: String, v: VBoxContainer) -> void:
	var pc = App.svc("pc")
	var wait := Style.label("Asking %s…" % name, "Small", true)
	v.add_child(wait)
	pc.pair_start(host, port, func(ok: bool, msg: String):
		if not is_instance_valid(wait):
			return
		if not ok:
			wait.text = msg
			return
		wait.text = "Your PC is showing a 6-digit code. Type it here:"
		var row := Style.hbox(8)
		var code := LineEdit.new()
		code.placeholder_text = "123 456"
		code.max_length = 7
		code.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
		code.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		code.add_theme_font_size_override("font_size", 26)
		row.add_child(code)
		var go := Style.button("Pair", "Primary", Callable())
		go.pressed.connect(func():
			go.disabled = true
			pc.pair_finish(host, port, name, code.text.replace(" ", ""), func(done: bool, m2: String):
				go.disabled = false
				if done:
					for k in _tabs:
						_tabs[k].disabled = false
					App.notify("Paired with %s." % App.svc("pc").pc().get("name", name))
					show_section("achievements")
				else:
					wait.text = m2))
		row.add_child(go)
		v.add_child(row)
		code.grab_focus())


func _pc_menu() -> void:
	var pc = App.svc("pc")
	var v := Style.vbox(12)
	if pc.paired():
		var p: Dictionary = pc.pc()
		v.add_child(Style.label(str(p.get("name", "PC")), "H1"))
		v.add_child(Style.label("%s:%d  ·  %s" % [p.host, int(p.get("port", 47630)), "connected" if pc.online else "not reachable right now"], "Small", true))
		v.add_child(Style.button("Sync now", "Ghost", func():
			_modal.queue_free()
			_offered = {}
			_check_update()
			show_section(_section if _section != "" else "achievements")))
		v.add_child(Style.button("Forget this PC", "", func():
			pc.forget()
			_modal.queue_free()
			_pair_screen()))
	else:
		v.add_child(Style.label("Not paired", "H1"))
	v.add_child(Style.label("Silent Hills companion %s" % pc.APP_VERSION, "Small"))
	v.add_child(Style.button("Close", "", func(): _modal.queue_free()))
	_open_modal(v)


func _open_modal(content: Control) -> void:
	var scrim := ColorRect.new()
	scrim.color = Color(0, 0, 0, 0.6)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.06, 0.065, 1)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(20)
	panel.add_theme_stylebox_override("panel", sb)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size.x = 320
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.add_child(content)
	scrim.add_child(panel)
	add_child(scrim)
	_modal = scrim


# ------------------------------------------------------------------ achievements
func _achievements() -> void:
	var pv := _scroll_page()
	var v: VBoxContainer = pv[1]
	_push(pv[0])
	var head := Style.label("Achievements", "H1")
	v.add_child(head)
	var sub := Style.label("Syncing with your PC…", "Small", true)
	v.add_child(sub)
	var list := Style.vbox(10)
	v.add_child(list)
	list.add_child(Style.skeleton_list(6, 84))
	if not _ach_data.is_empty():
		_fill_achievements(list, sub)
	App.svc("pc").get_json("/api/achievements", func(data):
		if data is Dictionary and data.has("games"):
			_ach_data = data
		if is_instance_valid(list):
			_fill_achievements(list, sub))


func _fill_achievements(list: VBoxContainer, sub: Label) -> void:
	for c in list.get_children():
		c.queue_free()
	if _ach_data.is_empty():
		sub.text = ""
		list.add_child(Style.empty_state("wifi-off", "Your PC isn't answering",
			"Open Silent Hills on your PC with the phone companion turned on in Settings, and keep this phone on the same Wi-Fi.",
			"Try again", func(): show_section("achievements")))
		return
	var u := 0
	var t := 0
	for g in _ach_data.games:
		u += int(g.unlocked)
		t += int(g.total)
	sub.text = "%d of %d unlocked across the series  ·  from %s, %s" % [u, t, _ach_data.get("pc", "your PC"), App.fmt_ago(int(_ach_data.get("generated", 0)))]
	for g in _ach_data.games:
		if int(g.total) == 0 and (g.groups as Array).filter(func(gr): return str(gr.get("note", "")) != "").is_empty():
			continue
		list.add_child(_game_row(g))


func _game_row(g: Dictionary) -> Control:
	var b := Button.new()
	b.custom_minimum_size.y = 84
	b.set_meta("sfx", "move")
	var accent := Style.color_hex(App.entry(str(g.id)).get("accent", ""))
	var h := Style.hbox(14)
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 12
	h.offset_right = -12
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ring_box := Control.new()
	ring_box.custom_minimum_size = Vector2(60, 60)
	ring_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ring_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ring = load("res://ui/widgets/achievements_view.gd").Ring.new()
	ring.value = float(g.unlocked) / maxf(1.0, float(g.total))
	ring.colour = accent
	ring.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ring_box.add_child(ring)
	ring.custom_minimum_size = Vector2(60, 60)
	var pct := Style.label("%d%%" % int(round(100.0 * float(g.unlocked) / maxf(1.0, float(g.total)))), "Small")
	pct.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pct.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ring_box.add_child(pct)
	h.add_child(ring_box)
	var tv := Style.vbox(2)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sub_t := str(App.entry(str(g.id)).get("subtitle", ""))
	var name := Style.label(str(g.title) + ((" (%s)" % sub_t) if sub_t != "" else ""), "", true)
	name.add_theme_font_override("font", Style.serif)
	name.add_theme_font_size_override("font_size", 21)
	tv.add_child(name)
	var line := "%d / %d" % [int(g.unlocked), int(g.total)]
	if int(g.total) == 0:
		line = "Nothing to show yet"
		for gr in g.groups:
			if str(gr.get("note", "")) != "":
				line = str(gr.note).split("\n")[0]
				break
	var sl := Style.label(line, "Small", true)
	sl.max_lines_visible = 2
	tv.add_child(sl)
	h.add_child(tv)
	b.add_child(h)
	b.pressed.connect(func():
		var av: Control = load("res://ui/widgets/achievements_view.gd").new()
		av.set("game_id", str(g.id))
		av.set("game_title", str(g.title))
		av.set("preset_groups", _icons_via_pc(g.groups))
		_push(av))
	return b


## Achievement icons come through the PC (which keeps them), not the web.
func _icons_via_pc(groups: Array) -> Array:
	var base: String = App.svc("pc").base_url()
	var out := []
	for gr in groups:
		var g2: Dictionary = gr.duplicate(true)
		for it in g2.get("items", []):
			var icon := str(it.get("icon", ""))
			if icon.begins_with("https://"):
				it.icon = base + "/api/badge?url=" + icon.uri_encode()
		out.append(g2)
	return out


# ------------------------------------------------------------------ concept art
func _concept_list() -> void:
	var pv := _scroll_page()
	var v: VBoxContainer = pv[1]
	_push(pv[0])
	v.add_child(Style.label("Concept Art", "H1"))
	v.add_child(Style.label("Official concept art for every game and film, from Silent Hill Memories (silenthillmemories.net).", "Small", true))
	for group in [["GAMES", App.games], ["FILMS", App.films]]:
		v.add_child(Style.margin(Style.label(group[0], "Caps"), 0, 10, 0, 2))
		for e in group[1]:
			var id: String = e.id
			var title := str(e.title) + ((" (%d)" % int(e.year)) if id.begins_with("film-") else (" (%s)" % e.subtitle if e.has("subtitle") else ""))
			var b := Style.button(title, "", func(): _concept_game(id, title))
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.custom_minimum_size.y = 46
			b.set_meta("sfx", "move")
			v.add_child(b)


func _concept_game(id: String, title: String) -> void:
	var page := Control.new()
	var bg := ColorRect.new()
	bg.color = Style.BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.add_child(bg)
	var pv := _scroll_page()
	page.add_child(pv[0])
	var v: VBoxContainer = pv[1]
	var head := Style.hbox(8)
	var back := Style.icon_button("arrow-left", "Back", func(): page.queue_free(), "", "", 24)
	back.custom_minimum_size = Vector2(Style.TARGET_TOUCH, Style.TARGET_TOUCH)
	back.set_meta("sfx", "back")
	head.add_child(back)
	var t := Style.label(title, "H2", true)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	v.add_child(head)
	var sub := Style.label("Looking on Silent Hill Memories…", "Small", true)
	v.add_child(sub)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	v.add_child(grid)
	var sw := (get_viewport_rect().size.x - 32 - 8) / 2.0
	for i in 6:
		grid.add_child(Style.skeleton(Vector2(sw, sw * 0.75)))
	_push(page)
	App.svc("concept").pictures(id, func(list: Array):
		if not is_instance_valid(grid):
			return
		for c in grid.get_children():
			c.queue_free()
		sub.text = "%d pictures  ·  from Silent Hill Memories" % list.size() if not list.is_empty() else ""
		if list.is_empty():
			v.add_child(Style.empty_state("image", "No concept art here yet",
				"Silent Hill Memories has none for this one, or this phone couldn't reach it. Pictures you keep on the PC show in its Concept Art tab."))
		var w := (get_viewport_rect().size.x - 32 - 8) / 2.0
		for i in list.size():
			var p: Dictionary = list[i]
			var b := Button.new()
			b.custom_minimum_size = Vector2(w, w * 0.75)
			b.clip_contents = true
			var img: TextureRect = load("res://ui/widgets/net_image.gd").new("", b.custom_minimum_size)
			img.max_px = 360
			img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			img.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			img.load_source(str(p.thumb))
			b.add_child(img)
			var idx := i
			b.pressed.connect(func():
				var viewer: Control = load("res://ui/widgets/image_viewer.gd").new()
				viewer.set("pictures", list)
				viewer.set("index", idx)
				_push(viewer))
			grid.add_child(b))


# ------------------------------------------------------------------ next update
# ------------------------------------------------------------------ music player
func _mini_player() -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.08, 0.09, 1)
	sb.border_color = Style.LINE
	sb.border_width_top = 1
	sb.set_content_margin_all(8)
	sb.content_margin_left = 16
	p.add_theme_stylebox_override("panel", sb)
	p.visible = false
	var h := Style.hbox(10)
	var open := Button.new()
	open.flat = true
	open.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	open.custom_minimum_size.y = 44
	var tv := Style.vbox(0)
	tv.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var t := Style.label("")
	t.name = "Title"
	t.clip_text = true
	t.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	t.add_theme_font_size_override("font_size", 14)
	tv.add_child(t)
	var a := Style.label("", "Small")
	a.name = "Album"
	a.clip_text = true
	a.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	tv.add_child(a)
	open.add_child(tv)
	open.pressed.connect(_full_player)
	h.add_child(open)
	var pb := Style.icon_button("pause", "Pause", func(): Player.toggle(), "", "", 24)
	pb.name = "Play"
	pb.custom_minimum_size = Vector2(Style.TARGET_TOUCH, Style.TARGET_TOUCH)
	h.add_child(pb)
	var nx := Style.icon_button("skip-forward", "Next track", func(): Player.next(), "", "", 24)
	nx.custom_minimum_size = Vector2(Style.TARGET_TOUCH, Style.TARGET_TOUCH)
	h.add_child(nx)
	p.add_child(h)
	return p


func _update_mini() -> void:
	var cur: Dictionary = Player.current()
	_mini.visible = not cur.is_empty()
	if cur.is_empty():
		return
	_mini.find_child("Title", true, false).text = str(cur.track.title)
	_mini.find_child("Album", true, false).text = ("Loading…  ·  " if Player.loading else "") + str(cur.album.title)
	var pb: Button = _mini.find_child("Play", true, false)
	pb.icon = Style.icon("pause" if Player.playing else "play", 24, Color.WHITE)
	pb.tooltip_text = "Pause" if Player.playing else "Play"
	pb.accessibility_name = pb.tooltip_text


func _full_player() -> void:
	var page := Control.new()
	var bg := ColorRect.new()
	bg.color = Style.BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.add_child(bg)
	var v := Style.vbox(14)
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 24
	v.offset_right = -24
	v.offset_top = 20
	v.offset_bottom = -28
	page.add_child(v)
	var close := Style.icon_button("chevron-left", "Close the player", func(): page.queue_free(), "Close", "", 24)
	close.custom_minimum_size.y = Style.TARGET_TOUCH
	close.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	close.set_meta("sfx", "back")
	v.add_child(close)
	var cover_box := CenterContainer.new()
	cover_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(cover_box)
	var title := Style.label("", "H2", true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var sub := Style.label("", "Small", true)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)
	var seek := HSlider.new()
	seek.custom_minimum_size.y = 36
	seek.step = 0.5
	seek.drag_ended.connect(func(_c): Player.seek(seek.value))
	v.add_child(seek)
	var times := Style.hbox(0)
	var t0 := Style.label("0:00", "Num")
	t0.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	times.add_child(t0)
	var t1 := Style.label("0:00", "Num")
	times.add_child(t1)
	v.add_child(times)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	var shuf := Style.icon_button("shuffle", "Shuffle", Callable(), "Shuffle", "", 20)
	shuf.toggle_mode = true
	shuf.custom_minimum_size.y = Style.TARGET_TOUCH
	shuf.button_pressed = Player.shuffle
	shuf.toggled.connect(func(on): Player.set_shuffle(on))
	row.add_child(shuf)
	var pv := Style.icon_button("skip-back", "Previous track", func(): Player.prev(), "", "", 28)
	pv.custom_minimum_size = Vector2(56, 56)
	row.add_child(pv)
	var play := Style.icon_button("pause", "Pause", func(): Player.toggle(), "", "Primary", 28)
	play.custom_minimum_size = Vector2(72, 72)
	play.add_theme_stylebox_override("normal", Style._box(Style.INK, 36, 0, 0))
	play.add_theme_stylebox_override("hover", Style._box(Color.WHITE, 36, 0, 0))
	play.add_theme_stylebox_override("pressed", Style._box(Style.INK_2, 36, 0, 0))
	row.add_child(play)
	var nx := Style.icon_button("skip-forward", "Next track", func(): Player.next(), "", "", 28)
	nx.custom_minimum_size = Vector2(56, 56)
	row.add_child(nx)
	var rep := Style.icon_button("repeat", "Repeat", Callable(), "Repeat all", "", 20)
	rep.custom_minimum_size.y = Style.TARGET_TOUCH
	var rep_text := func():
		rep.text = {"off": "Repeat off", "all": "Repeat all", "one": "Repeat one"}[Player.repeat]
		rep.icon = Style.icon("repeat-1" if Player.repeat == "one" else "repeat", 20, Color.WHITE)
		rep.modulate = Style.INK_3 if Player.repeat == "off" else Color.WHITE
	rep_text.call()
	rep.pressed.connect(func():
		Player.repeat = {"off": "all", "all": "one", "one": "off"}[Player.repeat]
		rep_text.call())
	v.add_child(row)
	var row2 := HBoxContainer.new()
	row2.alignment = BoxContainer.ALIGNMENT_CENTER
	row2.add_theme_constant_override("separation", 10)
	shuf.get_parent().remove_child(shuf)
	row2.add_child(shuf)
	row2.add_child(rep)
	v.add_child(row2)
	var shown := [""]
	var refresh := func():
		var cur: Dictionary = Player.current()
		if cur.is_empty() or not is_instance_valid(title):
			return
		title.text = str(cur.track.title)
		sub.text = "%s  ·  %s" % [cur.album.title, cur.track.get("artist", cur.album.get("artist", ""))]
		play.icon = Style.icon("pause" if Player.playing else "play", 28, Color.WHITE)
		play.tooltip_text = "Pause" if Player.playing else "Play"
		play.accessibility_name = play.tooltip_text
		if shown[0] != cur.album.key:
			shown[0] = cur.album.key
			for ch in cover_box.get_children():
				ch.queue_free()
			var side := minf(get_viewport_rect().size.x - 48, 360)
			var ms: Control = load("res://companion/music_screen.gd").new()
			ms.main = self
			cover_box.add_child(ms.cover_image(cur.album, Vector2(side, side)))
			ms.free()
	Player.changed.connect(refresh)
	page.tree_exiting.connect(func(): Player.changed.disconnect(refresh))
	refresh.call()
	var tick := Timer.new()
	tick.wait_time = 0.25
	tick.autostart = true
	tick.timeout.connect(func():
		var len: float = Player.length()
		seek.max_value = maxf(1.0, len)
		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			seek.set_value_no_signal(Player.position())
		t0.text = fmt_time(Player.position())
		t1.text = fmt_time(len))
	page.add_child(tick)
	overlay(page)


# ------------------------------------------------------------------ testing
## --shot=path,section,wait,extra (extra: "game:<id>" opens a game's
## achievements, "concept:<id>" a concept gallery, "pc" the PC menu).
func _first_json(path: String):
	var r := [false, null]
	App.svc("pc").get_json(path, func(d): r[1] = d; r[0] = true)
	while not r[0]:
		await get_tree().process_frame
	return r[1]


func _maybe_screenshot() -> void:
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--shot="):
			continue
		var parts := a.substr(7).split(",")
		if parts.size() > 1 and parts[1] != "" and App.svc("pc").paired():
			show_section(parts[1])
		var wait := float(parts[2]) if parts.size() > 2 and parts[2] != "" else 3.0
		await get_tree().create_timer(wait).timeout
		if parts.size() > 3 and parts[3] != "":
			var x := parts[3]
			if x.begins_with("game:"):
				for g in _ach_data.get("games", []):
					if str(g.id) == x.substr(5):
						var row := _game_row(g)
						row.pressed.emit()
			elif x.begins_with("concept:"):
				_concept_game(x.substr(8), App.entry(x.substr(8)).get("title", ""))
			elif x == "pc":
				_pc_menu()
			elif x.begins_with("album:"):
				# Opens the n-th album and plays its first track.
				var scr: Control = _body.get_child(-1)
				var al: Dictionary = scr._albums[int(x.substr(6))]
				scr._open(al)
				Player.play_album(al, 0)
			elif x.begins_with("player:"):
				var scr: Control = _body.get_child(-1)
				Player.play_album(scr._albums[int(x.substr(7))], 0)
				await get_tree().create_timer(wait).timeout
				_full_player()
			elif x.begins_with("read:"):
				var data = await _first_json("/api/comics")
				var c: Dictionary = data.comics[int(x.substr(5))]
				var r: Control = load("res://companion/phone_reader.gd").new()
				r.main = self
				r.comic = c
				r.start_page = 1
				overlay(r)
				if x.ends_with("ui") or true:
					await get_tree().create_timer(wait).timeout
					r._ui.visible = x.contains("+ui")
			elif x.begins_with("film:"):
				var scr: Control = _body.get_child(-1)
				for f in scr._films:
					if f.id == x.substr(5).split("+")[0]:
						scr._play(f, 5.0)
				if x.contains("+side"):
					get_window().size = Vector2i(900, 412)
			await get_tree().create_timer(wait).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(parts[0])
		get_tree().quit()
