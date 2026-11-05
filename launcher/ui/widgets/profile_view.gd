extends Control
## The profile, full-window: picture and name, time played and achievements
## across the series, up to three favourite games, and achievement progress
## for every game you've started. Esc closes.

var main: Control

var _body: VBoxContainer
var _sums := {}     # game id -> {unlocked, total}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color(0.015, 0.015, 0.02, 1.0)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.offset_left = 80
	scroll.offset_right = -80
	scroll.offset_top = 40
	scroll.offset_bottom = -30
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_body = Style.vbox(Style.SPACE_L)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_body)
	var close := Style.icon_button("x", "Close", queue_free, "Close")
	close.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	close.offset_left = -130
	close.offset_top = 40
	close.offset_right = -60
	close.set_meta("sfx", "back")
	add_child(close)
	App.svc("accounts").changed.connect(_build)
	_build()
	_load_sums()


func _unhandled_key_input(e: InputEvent) -> void:
	if e.pressed and e.keycode == KEY_ESCAPE:
		Sfx.play("back")
		queue_free()
		get_viewport().set_input_as_handled()


func _load_sums() -> void:
	var ach = App.svc("achievements")
	for g in App.games:
		var id: String = g.id
		ach.view(id, func(groups: Array):
			var u := 0
			var t := 0
			for gr in groups:
				u += int(gr.unlocked)
				t += int(gr.total)
			_sums[id] = {"unlocked": u, "total": t}
			if _sums.size() == App.games.size() and is_instance_valid(self):
				_build())


func _build() -> void:
	if not is_instance_valid(_body):
		return
	for c in _body.get_children():
		c.queue_free()
	var acc = App.svc("accounts")
	var me: bool = acc.signed_in()

	# Header
	var head := Style.hbox(Style.SPACE_XL)
	var pic := TextureRect.new()
	pic.texture = acc.avatar_texture(128)
	pic.custom_minimum_size = Vector2(128, 128)
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(pic)
	var hv := Style.vbox(Style.SPACE_S)
	hv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hv.add_child(Style.label("PROFILE", "Caps"))
	hv.add_child(Style.label(acc.display_name(), "Title"))
	var since := int(acc.user().get("created", 0))
	hv.add_child(Style.label(("Kept on this PC  ·  made " + App.fmt_ago(since).to_lower()) if me else "Not signed in: play time and achievements go to the shared records.", "Meta"))
	var actions := Style.hbox(Style.SPACE_S)
	if me:
		actions.add_child(Style.icon_button("camera", "Change picture", _choose_picture, "Change picture…", "Ghost", 16))
		actions.add_child(Style.icon_button("key-round", "Change password", _change_password, "Change password", "", 16))
		actions.add_child(Style.icon_button("log-out", "Sign out", func():
			acc.sign_out()
			queue_free(), "Sign out", "", 16))
	else:
		actions.add_child(Style.icon_button("user-plus", "Make a profile", func(): main.open_account("create"), "Make a profile", "Ghost", 16))
		if acc.has_profiles():
			actions.add_child(Style.icon_button("log-in", "Sign in", func(): main.open_account("sign_in"), "Sign in", "", 16))
	hv.add_child(actions)
	head.add_child(hv)
	_body.add_child(head)

	# Totals
	var total_u := 0
	var total_t := 0
	var complete := 0
	for id in _sums:
		total_u += int(_sums[id].unlocked)
		total_t += int(_sums[id].total)
		if int(_sums[id].total) > 0 and int(_sums[id].unlocked) == int(_sums[id].total):
			complete += 1
	var played := App.games.filter(func(g): return acc.playtime(g.id) > 0)
	var stats := Style.hbox(Style.SPACE_2XL)
	stats.add_child(_stat("TIME PLAYED", App.fmt_duration(acc.total_playtime()) if acc.total_playtime() > 0 else "None yet"))
	stats.add_child(_stat("GAMES PLAYED", "%d of %d" % [played.size(), App.games.size()]))
	stats.add_child(_stat("ACHIEVEMENTS", ("%d of %d" % [total_u, total_t]) if total_t > 0 else "…"))
	stats.add_child(_stat("COMPLETED", "%d game%s" % [complete, "" if complete == 1 else "s"]))
	_body.add_child(stats)

	# Favourites
	_body.add_child(Style.margin(Style.label("FAVOURITES", "Caps"), 0, Style.SPACE_M, 0, 0))
	if not me:
		_body.add_child(Style.label("Make a profile to pick up to three favourite games.", "Meta"))
	else:
		var favs := HFlowContainer.new()
		favs.add_theme_constant_override("h_separation", Style.SPACE_M)
		favs.add_theme_constant_override("v_separation", Style.SPACE_M)
		var list: Array = acc.favourites()
		for id in list:
			favs.add_child(_fav_card(id))
		if list.size() < acc.MAX_FAVOURITES:
			favs.add_child(_add_fav_card())
		_body.add_child(favs)

	# Achievement progress for the games you've started.
	_body.add_child(Style.margin(Style.label("ACHIEVEMENT PROGRESS", "Caps"), 0, Style.SPACE_M, 0, 0))
	var started := App.games.filter(func(g): return acc.playtime(g.id) > 0 or int(_sums.get(g.id, {}).get("unlocked", 0)) > 0)
	started.sort_custom(func(a, b): return _pct(a.id) > _pct(b.id))
	if started.is_empty():
		_body.add_child(Style.label("Games you've played show here with how many achievements you have.", "Meta"))
	for g in started:
		_body.add_child(_progress_row(g))


func _pct(id: String) -> float:
	var s: Dictionary = _sums.get(id, {})
	return float(s.get("unlocked", 0)) / maxf(1.0, float(s.get("total", 0)))


func _stat(cap: String, value: String) -> Control:
	var v := Style.vbox(4)
	v.add_child(Style.label(cap, "Caps"))
	var l := Style.label(value, "H2")
	l.add_theme_font_override("font", Style.numeric)
	v.add_child(l)
	return v


func _card_box(w: float, h: float) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(Style.SURFACE, 0.92)
	sb.set_corner_radius_all(Style.RADIUS)
	sb.set_content_margin_all(0)
	p.add_theme_stylebox_override("panel", sb)
	p.custom_minimum_size = Vector2(w, h)
	p.clip_contents = true
	return p


func _fav_card(id: String) -> Control:
	var g := App.game(id)
	var box := _card_box(340, 190)
	var art := TextureRect.new()
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.modulate = Color(1, 1, 1, 0.55)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	App.svc("art").get_texture(id, "hero", func(tex):
		if tex and is_instance_valid(art):
			art.texture = tex)
	box.add_child(art)
	var m := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, Style.SPACE_M)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := Style.vbox(4)
	v.alignment = BoxContainer.ALIGNMENT_END
	var top := Style.hbox(4)
	var st := TextureRect.new()
	st.texture = Style.icon("star", 16, Style.ACCENT_TEXT)
	st.custom_minimum_size = Vector2(16, 16)
	st.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	top.add_child(st)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(sp)
	var rm := Style.icon_button("x", "Remove from favourites", func(): App.svc("accounts").toggle_favourite(id), "", "", 16)
	top.add_child(rm)
	v.add_child(top)
	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(fill)
	var t := Style.label(str(g.title) + ((" (%s)" % g.subtitle) if g.has("subtitle") else ""), "H2", true)
	v.add_child(t)
	var acc = App.svc("accounts")
	var s: Dictionary = _sums.get(id, {})
	var bits := [App.fmt_duration(acc.playtime(id)) + " played" if acc.playtime(id) > 0 else "Not played yet"]
	if int(s.get("total", 0)) > 0:
		bits.append("%d / %d achievements" % [int(s.unlocked), int(s.total)])
	v.add_child(Style.label("  ·  ".join(bits), "Small"))
	m.add_child(v)
	box.add_child(m)
	return box


func _add_fav_card() -> Control:
	var b := Button.new()
	b.custom_minimum_size = Vector2(340, 190)
	b.text = "  Add a favourite"
	b.icon = Style.icon("star", 18, Color.WHITE)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.pressed.connect(_choose_favourite)
	return b


func _choose_favourite() -> void:
	var acc = App.svc("accounts")
	var v := Style.vbox(Style.SPACE_S)
	v.add_child(Style.label("Add a favourite", "H1"))
	v.add_child(Style.label("Up to three. You can also use the star on any game's page.", "Meta"))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 420
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var list := Style.vbox(2)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	v.add_child(scroll)
	var m: Control
	for g in App.games:
		if acc.is_favourite(g.id):
			continue
		var id: String = g.id
		var b := Style.button(str(g.title) + ((" (%s)" % g.subtitle) if g.has("subtitle") else "") + "  ·  " + str(int(g.year)), "", func():
			var why: String = acc.toggle_favourite(id)
			if why != "":
				App.notify(why)
			m.queue_free())
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size.y = Style.TARGET
		list.add_child(b)
	m = main.open_modal(v, 520)


func _progress_row(g: Dictionary) -> Control:
	var id: String = g.id
	var b := Button.new()
	b.flat = true
	b.custom_minimum_size.y = 64
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.tooltip_text = "Open %s's achievements" % g.title
	b.pressed.connect(func():
		var av: Control = load("res://ui/widgets/achievements_view.gd").new()
		av.set("main", main)
		av.set("game_id", id)
		main.modal_layer.add_child(av))
	var h := Style.hbox(Style.SPACE_L)
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = Style.SPACE_S
	h.offset_right = -Style.SPACE_S
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var t := Style.label(str(g.title) + ((" (%s)" % g.subtitle) if g.has("subtitle") else ""))
	t.add_theme_font_override("font", Style.serif)
	t.add_theme_font_size_override("font_size", 22)
	t.custom_minimum_size.x = 340
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(t)
	var s: Dictionary = _sums.get(id, {})
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(260, 6)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.value = 100.0 * _pct(id)
	var fg := StyleBoxFlat.new()
	fg.bg_color = Style.accent_text(Style.color_hex(g.get("accent", "")))
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(1, 1, 1, 0.08)
	bar.add_theme_stylebox_override("fill", fg)
	bar.add_theme_stylebox_override("background", bg)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(bar)
	var n := Style.label(("%d / %d  ·  %d%%" % [int(s.unlocked), int(s.total), int(round(100 * _pct(id)))]) if int(s.get("total", 0)) > 0 else "No achievements", "Num")
	n.custom_minimum_size.x = 150
	n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(n)
	var p := Style.label(App.fmt_duration(App.svc("accounts").playtime(id)) if App.svc("accounts").playtime(id) > 0 else "", "Small")
	p.custom_minimum_size.x = 90
	p.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(p)
	b.add_child(h)
	return b


func _choose_picture() -> void:
	main.choose_path("Choose a profile picture", "file", PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp ; Pictures"]), func(p: String):
		if p != "" and not App.svc("accounts").set_avatar(p):
			App.notify("That picture couldn't be read.", "error"))


func _change_password() -> void:
	var v := Style.vbox(Style.SPACE_M)
	v.add_child(Style.label("Change password", "H1"))
	var fields := []
	for ph in ["Current password", "New password", "New password again"]:
		var le := LineEdit.new()
		le.placeholder_text = ph
		le.secret = true
		le.custom_minimum_size.y = Style.TARGET
		v.add_child(le)
		fields.append(le)
	var err := Style.label("", "Small", true)
	err.add_theme_color_override("font_color", Style.DANGER)
	v.add_child(err)
	var m: Control
	var go := Style.button("Change it", "Primary", Callable())
	go.pressed.connect(func():
		go.disabled = true
		App.svc("accounts").change_password(fields[0].text, fields[1].text, fields[2].text, func(e: String):
			go.disabled = false
			if e != "":
				err.text = e
			else:
				App.notify("Password changed.", "ok")
				m.queue_free()))
	v.add_child(go)
	m = main.open_modal(v, 480)
