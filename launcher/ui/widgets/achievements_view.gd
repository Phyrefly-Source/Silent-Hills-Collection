extends Control
## Achievements for one game, full-window over its art, laid out like Steam's:
## a header with progress, then one row per achievement: icon, name,
## description, how many players have it, and when you unlocked it.
## Unlocked first (newest first), then locked (most common first); locked
## hidden ones stay folded into one row until you ask to see them.
## Filters: All / Unlocked / Locked. Esc closes.

const NetImage := preload("res://ui/widgets/net_image.gd")

var main: Control
var game_id := ""
## Groups handed in (the companion app shows the PC's achievements); when set,
## nothing is loaded locally and the view is read-only.
var preset_groups: Array = []
var game_title := ""

var _narrow := false
var _margin := 80.0

var _groups: Array = []
var _filter := "all"
var _show_hidden := false
var _body: VBoxContainer
var _accent := Color(0.69, 0.19, 0.11)


class Ring extends Control:
	var value := 0.0      # 0..1
	var colour := Color.WHITE
	var shown := 0.0

	func _ready() -> void:
		if custom_minimum_size == Vector2.ZERO:
			custom_minimum_size = Vector2(150, 150)
		create_tween().tween_property(self, "shown", value, Style.dur(0.6)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	func _process(_dt: float) -> void:
		queue_redraw()

	func _draw() -> void:
		var c := size / 2
		var r := minf(size.x, size.y) / 2 - 8
		draw_arc(c, r, 0, TAU, 96, Color(1, 1, 1, 0.08), 6, true)
		if shown > 0.0:
			draw_arc(c, r, -PI / 2, -PI / 2 + TAU * shown, 96, colour, 6, true)


## A thin bar: how many players have an achievement.
class Bar extends Control:
	var value := 0.0
	var colour := Color.WHITE

	func _ready() -> void:
		custom_minimum_size.y = 4

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.08))
		draw_rect(Rect2(Vector2.ZERO, Vector2(size.x * clampf(value, 0.0, 1.0), size.y)), colour)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_accent = Style.color_hex(App.entry(game_id).get("accent", ""))
	var shade := ColorRect.new()
	shade.color = Color(0.015, 0.015, 0.02, 1.0)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	# The game's art, faint, behind everything.
	var art := TextureRect.new()
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.modulate.a = 0.0
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(art)
	App.svc("art").get_texture(game_id, "hero", func(tex):
		if tex and is_instance_valid(art):
			art.texture = tex
			Style.tween(art).tween_property(art, "modulate:a", 0.16, Style.DUR_PAGE))
	_narrow = get_viewport_rect().size.x < 760
	_margin = 16.0 if _narrow else 80.0
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.offset_left = _margin
	scroll.offset_right = -_margin
	scroll.offset_top = 70.0 if _narrow else 40.0
	scroll.offset_bottom = -30
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_body = Style.vbox(18)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_body)
	var close := Style.icon_button("x", "Close", queue_free, "Close")
	close.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	close.offset_left = -130
	close.offset_top = 16 if _narrow else 40
	close.offset_right = -16 if _narrow else -60
	close.set_meta("sfx", "back")
	add_child(close)
	# While the list comes together: a static outline of the page.
	var sk := Style.hbox(36)
	sk.add_child(Style.skeleton(Vector2(150, 150), 75))
	var skv := Style.vbox(12)
	skv.add_child(Style.skeleton(Vector2(420, 56)))
	skv.add_child(Style.skeleton(Vector2(260, 18)))
	sk.add_child(skv)
	_body.add_child(sk)
	_body.add_child(Style.skeleton_list(6, 88))
	if not preset_groups.is_empty():
		_groups = preset_groups
		_build.call_deferred()
	else:
		_load()


func _load() -> void:
	if not preset_groups.is_empty():
		_build()
		return
	App.svc("achievements").view(game_id, func(groups: Array):
		if not is_instance_valid(self):
			return
		_groups = groups
		_build())


func _unhandled_key_input(e: InputEvent) -> void:
	if e.pressed and e.keycode == KEY_ESCAPE:
		Sfx.play("back")
		queue_free()
		get_viewport().set_input_as_handled()


func _all_items() -> Array:
	var out := []
	for gr in _groups:
		for it in gr.items:
			var x: Dictionary = it.duplicate()
			x.source = gr.source
			out.append(x)
	return out


func _build() -> void:
	for c in _body.get_children():
		c.queue_free()
	var g := App.entry(game_id)
	var items := _all_items()
	var total := items.size()
	var got := items.filter(func(i): return i.unlocked)
	var gr: Dictionary = _groups[0] if not _groups.is_empty() else {}

	# Header: ring, title, progress, where the list comes from.
	var head: BoxContainer = Style.hbox(36) if not _narrow else Style.vbox(14)
	var ring := Ring.new()
	ring.value = float(got.size()) / maxf(1.0, total)
	ring.colour = _accent
	var ring_box := Control.new()
	ring_box.custom_minimum_size = Vector2(150, 150)
	ring_box.add_child(ring)
	ring.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var pct := Style.label("%d%%" % int(round(100.0 * got.size() / maxf(1.0, total))), "H1")
	pct.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pct.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ring_box.add_child(pct)
	head.add_child(ring_box)
	var tv := Style.vbox(8)
	tv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.add_child(Style.label("ACHIEVEMENTS", "Caps"))
	var tl := Style.label(str(g.get("title", game_title if game_title != "" else game_id)), "Title" if not _narrow else "H1", true)
	tv.add_child(tl)
	var bits := ["%d of %d unlocked" % [got.size(), total]]
	var last := 0
	for it in got:
		last = maxi(last, int(it.get("at", 0)))
	if last > 0:
		bits.append("last unlocked " + App.fmt_ago(last).to_lower())
	tv.add_child(Style.label("  ·  ".join(bits), "Num"))
	if not gr.is_empty():
		var src := Style.hbox(8)
		src.add_child(Style.label(str(gr.get("title", "")), "Small"))
		if str(gr.get("link", "")) != "":
			var link: String = gr.link
			var lb := Style.icon_button("external-link", "Open the list at " + str(gr.get("credit", "its source")), func(): OS.shell_open(link),
				str(gr.get("credit", "Source")), "", 14)
			lb.add_theme_font_size_override("font_size", 12)
			src.add_child(lb)
		tv.add_child(src)
	var actions := Style.hbox(8)
	for k in [["all", "All"], ["unlocked", "Unlocked"], ["locked", "Locked"]]:
		var key: String = k[0]
		var b := Style.button(k[1], "Nav", func():
			_filter = key
			_build())
		b.toggle_mode = true
		b.button_pressed = _filter == key
		b.set_meta("sfx", "tab")
		actions.add_child(b)
	if preset_groups.is_empty():
		actions.add_child(Style.spacer(0, 16))
		actions.add_child(Style.icon_button("refresh-cw", "Check again", func(): _load(), "Check again", "", 16))
	tv.add_child(actions)
	head.add_child(tv)
	_body.add_child(head)

	if total == 0:
		_body.add_child(Style.empty_state("trophy", "This game has no achievements",
			"It never had an official list, and there's no community set for it."))
		return
	if str(gr.get("note", "")) != "" and preset_groups.is_empty():
		var n := Style.label(str(gr.note), "Small", true)
		n.custom_minimum_size.x = 400
		_body.add_child(n)

	var unlocked := got.duplicate()
	unlocked.sort_custom(func(a, b): return int(a.get("at", 0)) > int(b.get("at", 0)))
	var locked := items.filter(func(i): return not i.unlocked)
	locked.sort_custom(func(a, b): return float(a.get("rarity", -1)) > float(b.get("rarity", -1)))
	var hidden := locked.filter(func(i): return i.get("hidden", false))
	var open := locked.filter(func(i): return not i.get("hidden", false))

	var list := Style.vbox(6)
	_body.add_child(list)
	if _filter != "locked":
		for it in unlocked:
			list.add_child(_row(it))
	if _filter != "unlocked":
		if not unlocked.is_empty() and not locked.is_empty() and _filter == "all":
			list.add_child(Style.margin(Style.label("LOCKED", "Caps"), 0, 14, 0, 4))
		for it in open:
			list.add_child(_row(it))
		if not hidden.is_empty():
			if _show_hidden:
				for it in hidden:
					list.add_child(_row(it, true))
			list.add_child(_hidden_row(hidden.size()))
	if list.get_child_count() == 0:
		list.add_child(Style.label("Nothing here yet." if _filter == "unlocked" else "Everything's unlocked.", "Meta"))
	if str(gr.get("rarity_source", "")) != "":
		_body.add_child(Style.label("How many players have each achievement: %s's figures for the %s version." % [gr.rarity_source, gr.get("platform", "original")], "Small", true))


## Steam-style date: "29 Oct 2026, 9:51 pm".
static func when(unix: int) -> String:
	var bias := int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	var d := Time.get_datetime_dict_from_unix_time(unix + bias)
	var h := int(d.hour) % 12
	return "%d %s %d, %d:%02d %s" % [d.day, ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"][d.month - 1],
		d.year, 12 if h == 0 else h, d.minute, "am" if int(d.hour) < 12 else "pm"]


func _icon(it: Dictionary, secret: bool, px: int) -> Control:
	var box := Panel.new()
	box.custom_minimum_size = Vector2(px, px)
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.clip_contents = true
	var isb := StyleBoxFlat.new()
	isb.bg_color = Style.HOVER
	isb.set_corner_radius_all(Style.RADIUS)
	box.add_theme_stylebox_override("panel", isb)
	if str(it.get("icon", "")) != "" and not secret:
		var img: TextureRect = NetImage.new(str(it.icon), Vector2(px, px))
		img.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		img.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# No locked art of its own: grey the official icon, as Steam does.
		if not it.unlocked and not it.get("locked_art", false):
			img.material = _grey()
			img.modulate = Color(0.6, 0.6, 0.6)
		box.add_child(img)
	else:
		var glyph := TextureRect.new()
		glyph.texture = Style.icon("eye-off" if secret else "trophy", 24, Style.INK_3)
		glyph.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		glyph.size = Vector2(24, 24)
		glyph.position = Vector2((px - 24) / 2.0, (px - 24) / 2.0)
		box.add_child(glyph)
	return box


static var _grey_mat: ShaderMaterial
static func _grey() -> ShaderMaterial:
	if _grey_mat == null:
		var sh := Shader.new()
		sh.code = "shader_type canvas_item;\nvoid fragment() { vec4 c = texture(TEXTURE, UV) * COLOR; float l = dot(c.rgb, vec3(0.299, 0.587, 0.114)); COLOR = vec4(vec3(l), c.a); }"
		_grey_mat = ShaderMaterial.new()
		_grey_mat.shader = sh
	return _grey_mat


func _row(it: Dictionary, revealed: bool = false) -> Control:
	var secret: bool = it.get("hidden", false) and not it.unlocked and not revealed
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(Style.SURFACE, 0.92) if it.unlocked else Color(Style.SURFACE, 0.6)
	sb.border_color = Style.accent_text(_accent)
	sb.border_width_left = 3 if it.unlocked else 0
	sb.set_corner_radius_all(Style.RADIUS)
	sb.set_content_margin_all(Style.SPACE_M)
	sb.content_margin_left = Style.SPACE_M + (0 if it.unlocked else 3)
	panel.add_theme_stylebox_override("panel", sb)
	var row := Style.hbox(16)
	row.add_child(_icon(it, secret, 64))
	var v := Style.vbox(4)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var name := Style.label(str(it.name), "", true)
	name.add_theme_font_override("font", Style.sans_medium)
	name.add_theme_font_size_override("font_size", 16)
	name.add_theme_color_override("font_color", Style.INK if it.unlocked else Style.INK_2)
	v.add_child(name)
	var desc := str(it.get("description", ""))
	if desc != "":
		v.add_child(Style.label(desc, "Small", true))
	var r := float(it.get("rarity", -1.0))
	if r >= 0.0:
		var rr := Style.hbox(10)
		var bar := Bar.new()
		bar.value = r / 100.0
		bar.colour = Style.accent_text(_accent) if it.unlocked else Style.INK_3
		bar.custom_minimum_size.x = 120 if not _narrow else 70
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		rr.add_child(bar)
		var rl := Style.label(("%.1f%% of players have this" % r) + ("  ·  Rare" if r < 10.0 else ""), "Small")
		rl.add_theme_font_override("font", Style.numeric)
		rr.add_child(rl)
		v.add_child(rr)
	row.add_child(v)
	var side := Style.vbox(6)
	side.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if it.unlocked:
		var u := Style.label("Unlocked " + when(int(it.at)) if int(it.get("at", 0)) > 0 else "Unlocked", "Small")
		u.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		u.add_theme_color_override("font_color", Style.accent_text(_accent))
		u.add_theme_font_override("font", Style.numeric)
		side.add_child(u)
	if preset_groups.is_empty() and str(it.get("via", "")) != "steam" and not _is_steam():
		var b := Style.button("Lock" if it.unlocked else "Mark as unlocked", "", func():
			App.svc("achievements").set_unlocked(game_id, it.id, not it.unlocked)
			_load())
		b.add_theme_font_size_override("font_size", 12)
		b.size_flags_horizontal = Control.SIZE_SHRINK_END
		b.tooltip_text = "Mark it by hand, for achievements the game can't report yet."
		side.add_child(b)
	if side.get_child_count() > 0:
		row.add_child(side)
	panel.add_child(row)
	if secret:
		name.text = "Hidden achievement"
		for c in v.get_children().slice(1):
			c.queue_free()
		v.add_child(Style.label("Details are revealed once it's unlocked.", "Small", true))
	return panel


func _is_steam() -> bool:
	return not _groups.is_empty() and str(_groups[0].get("credit", "")) == "Steam"


func _hidden_row(n: int) -> Control:
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(Style.SURFACE, 0.6)
	sb.set_corner_radius_all(Style.RADIUS)
	sb.set_content_margin_all(Style.SPACE_M)
	panel.add_theme_stylebox_override("panel", sb)
	var row := Style.hbox(16)
	row.add_child(_icon({"unlocked": false}, true, 64))
	var v := Style.vbox(4)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var t := Style.label("%d hidden achievement%s left" % [n, "" if n == 1 else "s"])
	t.add_theme_font_override("font", Style.sans_medium)
	v.add_child(t)
	v.add_child(Style.label("Details for each one are revealed once it's unlocked.", "Small", true))
	row.add_child(v)
	var b := Style.button("Hide them" if _show_hidden else "Show them anyway", "", func():
		_show_hidden = not _show_hidden
		_build())
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(b)
	panel.add_child(row)
	return panel
