extends Control
## News, the opening page. Across the top: this week in Silent Hill history.
## Left: every Silent Hill game sold for PC with its
## price at the official stores (Steam, GOG, Epic), sales first; new Silent
## Hill store pages. Right: the latest
## headlines about the series, from Google News and Steam.

const NetImage := preload("res://ui/widgets/net_image.gd")

var main: Control
var _sub: Label
var _sales: VBoxContainer
var _history: PanelContainer
var _news: VBoxContainer
var _filter_new := false
var _filter_btn: Button
var _refresh_btn: Button


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var news = App.svc("news")
	var root := Style.vbox(Style.SPACE_L)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 44
	root.offset_right = -44
	root.offset_top = 28
	root.offset_bottom = -24
	add_child(root)

	var head := Style.hbox(Style.SPACE_M)
	var hv := Style.vbox(4)
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hv.add_child(Style.label("News", "H1"))
	_sub = Style.label("Checking for news and sales…", "Small")
	hv.add_child(_sub)
	head.add_child(hv)
	_refresh_btn = Style.icon_button("refresh-cw", "Check again", func(): App.svc("news").refresh(false, true), "Check again", "Ghost", 18)
	_refresh_btn.size_flags_vertical = Control.SIZE_SHRINK_END
	head.add_child(_refresh_btn)
	root.add_child(head)

	# This week in Silent Hill history: a banner across the top.
	_history = PanelContainer.new()
	var hsb := StyleBoxFlat.new()
	hsb.bg_color = Color(Style.SURFACE, 0.85)
	hsb.border_color = Style.LINE
	hsb.set_border_width_all(1)
	hsb.set_corner_radius_all(Style.RADIUS)
	hsb.set_content_margin_all(Style.SPACE_M)
	_history.add_theme_stylebox_override("panel", hsb)
	_history.visible = false
	root.add_child(_history)

	var cols := Style.hbox(Style.SPACE_XL)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(cols)

	# Sales
	var left := Style.vbox(Style.SPACE_S)
	left.custom_minimum_size.x = 420
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 0.8
	left.add_child(Style.label("BUY ON PC", "Caps"))
	var ls := ScrollContainer.new()
	ls.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ls.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_sales = Style.vbox(Style.SPACE_S)
	_sales.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ls.add_child(_sales)
	left.add_child(ls)
	cols.add_child(left)

	# Headlines
	var right := Style.vbox(Style.SPACE_S)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var rh := Style.hbox(Style.SPACE_M)
	var cap := Style.label("SILENT HILL NEWS", "Caps")
	cap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rh.add_child(cap)
	_filter_btn = Style.button("Only new entries", "", func():
		_filter_new = _filter_btn.button_pressed
		_fill_news())
	_filter_btn.toggle_mode = true
	_filter_btn.tooltip_text = "Only headlines about games being announced, dated, released or remade."
	rh.add_child(_filter_btn)
	right.add_child(rh)
	var rs := ScrollContainer.new()
	rs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rs.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_news = Style.vbox(0)
	_news.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rs.add_child(_news)
	right.add_child(rs)
	cols.add_child(right)

	news.updated.connect(_fill)
	if news.checked > 0:
		_fill()
	else:
		_sales.add_child(Style.skeleton_list(3, 112))
		_news.add_child(Style.skeleton_list(8, 56))
		if not news.busy:
			news.refresh()


func on_shown() -> void:
	main.backdrop.show_art(null)
	main.backdrop.set_atmosphere("mist", Color(0.5, 0.5, 0.52))
	if App.svc("news").checked > 0:
		App.svc("news").mark_seen()


func _fill() -> void:
	var news = App.svc("news")
	_refresh_btn.disabled = false
	var when := "just now"
	var ago: int = int(Time.get_unix_time_from_system()) - int(news.checked)
	if ago > 90:
		when = _ago(news.checked)
	_sub.text = "Checked %s  ·  prices from Steam, GOG and the Epic Games Store; headlines from Google News and Steam  ·  checks again every 3 hours" % when
	_fill_history()
	_fill_sales()
	_fill_news()
	if visible:
		news.mark_seen()


func _fill_sales() -> void:
	for c in _sales.get_children():
		c.queue_free()
	var news = App.svc("news")
	if news.shop.is_empty():
		_sales.add_child(Style.empty_state("wifi-off", "Store prices aren't available",
			"Steam and GOG couldn't be reached. Check your internet connection and try again."))
	else:
		var n_sale: int = news.sales.size()
		_sales.add_child(Style.label(("%d on sale now" % n_sale) if n_sale > 0 else "Nothing's on sale right now: full prices at the official stores.", "Small", true))
		for o in news.shop:
			_sales.add_child(_shop_card(o))
	if not news.pages.is_empty():
		_sales.add_child(Style.margin(Style.label("NEW ON PC STORES", "Caps"), 0, Style.SPACE_M, 0, 0))
		for pg in news.pages:
			_sales.add_child(_page_row(pg))


func _frame(child: Control, size: Vector2) -> PanelContainer:
	var frame := PanelContainer.new()
	var fb := StyleBoxFlat.new()
	fb.bg_color = Style.RAISED
	fb.set_corner_radius_all(Style.RADIUS)
	frame.add_theme_stylebox_override("panel", fb)
	frame.custom_minimum_size = size
	frame.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	frame.clip_contents = true
	if child:
		frame.add_child(child)
	return frame


func _shop_card(o: Dictionary) -> Control:
	var news = App.svc("news")
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Style.SURFACE
	sb.border_color = Style.OK if o.sale else Style.LINE
	sb.set_border_width_all(1)
	sb.border_width_left = 3 if o.sale else 1
	sb.set_corner_radius_all(Style.RADIUS)
	sb.set_content_margin_all(Style.SPACE_M)
	panel.add_theme_stylebox_override("panel", sb)
	var h := Style.hbox(Style.SPACE_M)
	# The store's own wide art (Steam capsule or GOG banner), else the launcher's.
	var img: TextureRect
	if str(o.get("art", "")) != "":
		img = NetImage.new(str(o.art), Vector2(184, 69))
		img.max_px = 368
	else:
		img = TextureRect.new()
		img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		img.custom_minimum_size = Vector2(184, 69)
		App.svc("art").get_texture(str(o.game), "hero", func(tex):
			if tex and is_instance_valid(img):
				img.texture = tex)
	img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	h.add_child(_frame(img, Vector2(184, 69)))
	var v := Style.vbox(4)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var tr := Style.hbox(Style.SPACE_S)
	var t := Style.label(str(o.title))
	t.add_theme_font_override("font", Style.sans_semibold)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tr.add_child(t)
	if o.sale:
		var tag := Style.label("ON SALE", "Caps")
		tag.add_theme_color_override("font_color", Style.OK)
		tr.add_child(tag)
	v.add_child(tr)
	# One line per official store: price, and the full price struck through when discounted.
	for st in o.stores:
		var row := Style.hbox(Style.SPACE_S)
		var name := Style.button(str(st.store), "", func(): OS.shell_open(str(st.url)))
		name.icon = Style.icon("external-link", 14, Color.WHITE)
		name.add_theme_constant_override("icon_max_width", 14)
		name.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		name.tooltip_text = "Open %s on %s" % [o.title, st.store]
		name.custom_minimum_size.x = 170
		name.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.add_child(name)
		if int(st.discount) > 0:
			var off := Style.label("-%d%%" % int(st.discount), "Num")
			off.add_theme_color_override("font_color", Style.OK)
			off.add_theme_font_override("font", Style.sans_semibold)
			row.add_child(off)
		var now := Style.label(news.money(st.price), "Num")
		now.add_theme_color_override("font_color", Style.INK)
		row.add_child(now)
		if int(st.discount) > 0:
			var was := Style.label(news.money(st.base), "Num")
			was.add_theme_color_override("font_color", Style.INK_3)
			row.add_child(was)
		else:
			row.add_child(Style.label("full price", "Small"))
		v.add_child(row)
	h.add_child(v)
	panel.add_child(h)
	return panel


func _page_row(pg: Dictionary) -> Control:
	var b := Button.new()
	b.flat = true
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.tooltip_text = "Open on %s" % pg.store
	b.pressed.connect(func(): OS.shell_open(str(pg.url)))
	b.custom_minimum_size.y = 52
	var v := Style.vbox(2)
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = Style.SPACE_S
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var t := Style.label(str(pg.title))
	t.add_theme_color_override("font_color", Style.INK)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(t)
	var bits := ["NEW ON " + str(pg.store).to_upper()]
	if float(pg.get("price", -1)) > 0.0:
		bits.append(App.svc("news").money(float(pg.price)))
	elif float(pg.get("price", -1)) == 0.0:
		bits.append("Free")
	if str(pg.get("date", "")) != "":
		bits.append("out " + str(pg.date).replace(".", "-"))
	bits.append("spotted " + _ago(int(pg.first)))
	var m := Style.label("  ·  ".join(bits), "Small")
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(m)
	b.add_child(v)
	return b


func _fill_history() -> void:
	for c in _history.get_children():
		c.queue_free()
	var hist: Array = App.svc("news").history()
	_history.visible = not hist.is_empty()
	if hist.is_empty():
		return
	var row := Style.hbox(Style.SPACE_L)
	var cap := Style.label("THIS WEEK IN\nSILENT HILL HISTORY", "Caps")
	cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cap.custom_minimum_size.x = 170
	row.add_child(cap)
	var flow := HFlowContainer.new()
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flow.add_theme_constant_override("h_separation", Style.SPACE_XL)
	flow.add_theme_constant_override("v_separation", Style.SPACE_S)
	for h in hist:
		flow.add_child(_history_row(h))
	row.add_child(flow)
	_history.add_child(row)


func _history_row(h: Dictionary) -> Control:
	var row := Style.hbox(Style.SPACE_M)
	var d := Time.get_datetime_dict_from_unix_time(int(h.date))
	var day := Style.label("%s %d" % [["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"][d.month - 1], d.day], "Num")
	row.add_child(day)
	var when := "today" if int(h.days) == 0 else (("%d day%s ago" % [-int(h.days), "" if int(h.days) == -1 else "s"]) if int(h.days) < 0 \
		else ("in %d day%s" % [int(h.days), "" if int(h.days) == 1 else "s"]))
	var verb := "came out" if int(h.days) <= 0 else "turns"
	var text := ("%s %s %d years ago (%d)  ·  %s" % [h.title, verb, int(h.years), int(h.year), when]) if int(h.days) <= 0 \
		else ("%s turns %d (%d)  ·  %s" % [h.title, int(h.years), int(h.year), when])
	var l := Style.label(text, "Meta")
	l.add_theme_color_override("font_color", Style.INK)
	row.add_child(l)
	return row


func _fill_news() -> void:
	for c in _news.get_children():
		c.queue_free()
	var list: Array = App.svc("news").items
	if _filter_new:
		list = list.filter(func(i): return i.new_entry)
	if list.is_empty():
		if App.svc("news").items.is_empty():
			_news.add_child(Style.empty_state("wifi-off", "No headlines",
				"The news couldn't be fetched. Check your internet connection and try again.", "Check again",
				func(): App.svc("news").refresh(false, true)))
		else:
			_news.add_child(Style.empty_state("newspaper", "Nothing about new entries lately",
				"Turn off \"Only new entries\" for all the Silent Hill headlines from the last 30 days."))
		return
	for it in list:
		_news.add_child(_headline(it))


func _headline(it: Dictionary) -> Control:
	var b := Button.new()
	b.flat = true
	b.focus_mode = Control.FOCUS_ALL
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.tooltip_text = "Open in your browser"
	b.accessibility_name = str(it.title)
	b.pressed.connect(func(): OS.shell_open(str(it.url)))
	var v := Style.vbox(2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var t := Style.label(str(it.title), "", true)
	t.add_theme_color_override("font_color", Style.INK)
	t.add_theme_font_size_override("font_size", 16)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(t)
	var meta := Style.hbox(Style.SPACE_S)
	meta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if it.new_entry:
		meta.add_child(_badge("NEW ENTRY", Style.ACCENT_TEXT))
	if it.official:
		meta.add_child(_badge("OFFICIAL", Style.OK))
	var src := Style.label("%s  ·  %s" % [it.source, _ago(int(it.at))] if int(it.at) > 0 else str(it.source), "Small")
	src.mouse_filter = Control.MOUSE_FILTER_IGNORE
	meta.add_child(src)
	v.add_child(meta)
	var pad := MarginContainer.new()
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right"]:
		pad.add_theme_constant_override("margin_" + side, Style.SPACE_S)
	pad.add_theme_constant_override("margin_top", 10)
	pad.add_theme_constant_override("margin_bottom", 10)
	pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pad.add_child(v)
	b.add_child(pad)
	# A Button doesn't size to its children: follow the text's height.
	pad.minimum_size_changed.connect(func(): b.custom_minimum_size.y = pad.get_combined_minimum_size().y)
	b.custom_minimum_size.y = 56
	(func(): if is_instance_valid(pad): b.custom_minimum_size.y = pad.get_combined_minimum_size().y).call_deferred()
	return b


func _badge(text: String, c: Color) -> Label:
	var l := Style.label(text, "Caps")
	l.add_theme_color_override("font_color", c)
	return l


static func _ago(t: int) -> String:
	var d := int(Time.get_unix_time_from_system()) - t
	if d < 3600:
		return "%d min ago" % maxi(1, d / 60)
	if d < 86400:
		var h := d / 3600
		return "%d hour%s ago" % [h, "" if h == 1 else "s"]
	var days := d / 86400
	if days < 14:
		return "%d day%s ago" % [days, "" if days == 1 else "s"]
	return Time.get_date_string_from_unix_time(t)
