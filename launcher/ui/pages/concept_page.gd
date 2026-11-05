extends Control
## Concept Art: official concept art for every game in one place, for easy
## access and preservation. Pictures come from Silent Hill Memories
## (silenthillmemories.net, credited and linked on every picture) and your own
## folders; "Keep offline" saves a game's pictures next to the launcher.

const NetImage := preload("res://ui/widgets/net_image.gd")

var main: Control
var _list: VBoxContainer
var _title: Label
var _sub: Label
var _actions: HBoxContainer
var _grid: VBoxContainer   # a heading and a grid of pictures per section
var _cols := 4
var _game := ""
var _buttons := {}
var _pictures: Array = []
var _open_token := 0
var _badges := {}          # picture url -> its "kept" badge on the current page
var _dl_row: HBoxContainer
var _dl_bar: ProgressBar
var _dl_text: Label
var _all_bar: ProgressBar
var _all_text: Label
var _all_btn: Button


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var concept = App.svc("concept")

	var left := Style.vbox(6)
	left.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	left.offset_left = 44
	left.offset_top = 28
	left.offset_bottom = -24
	left.custom_minimum_size.x = 280
	add_child(left)
	left.add_child(Style.label("Concept Art", "H1"))
	var row := Style.hbox(8)
	row.add_child(Style.button("Add a folder…", "Ghost", add_folder))
	row.add_child(Style.button("Open folder", "", func():
		DirAccess.make_dir_recursive_absolute(concept.offline_dir())
		OS.shell_open(ProjectSettings.globalize_path(concept.offline_dir()))))
	left.add_child(row)
	left.add_child(Style.spacer(8))
	var ls := ScrollContainer.new()
	ls.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ls.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_list = Style.vbox(2)
	_list.custom_minimum_size.x = 270
	ls.add_child(_list)
	var lm := Style.margin(ls, -Style.SPACE_S, 0, 0, 0)
	lm.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(lm)
	_all_btn = Style.button("Keep everything offline", "Ghost", func():
		concept.keep_everything_offline()
		_update_overall())
	_all_btn.tooltip_text = "Save the concept art of every game and film, so it stays available without the internet."
	left.add_child(_all_btn)
	_all_bar = _bar(260)
	_all_bar.visible = false
	left.add_child(_all_bar)
	_all_text = Style.label("", "Small", true)
	_all_text.custom_minimum_size.x = 260
	left.add_child(_all_text)

	var right := Style.vbox(14)
	right.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	right.offset_left = 380
	right.offset_right = -44
	right.offset_top = 34
	right.offset_bottom = -24
	add_child(right)
	_title = Style.label("", "H1")
	right.add_child(_title)
	_sub = Style.label("", "Meta", true)
	right.add_child(_sub)
	_actions = Style.hbox(10)
	right.add_child(_actions)
	_dl_row = Style.hbox(12)
	_dl_bar = _bar(320)
	_dl_row.add_child(_dl_bar)
	_dl_text = Style.label("", "Small")
	_dl_row.add_child(_dl_text)
	_dl_row.visible = false
	right.add_child(_dl_row)
	var gs := ScrollContainer.new()
	gs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	gs.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_grid = Style.vbox(10)
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gs.add_child(_grid)
	right.add_child(gs)
	var credit := Style.button("Pictures: Silent Hill Memories — silenthillmemories.net", "", func():
		OS.shell_open("https://www.silenthillmemories.net/"))
	credit.add_theme_font_size_override("font_size", 12)
	credit.size_flags_horizontal = Control.SIZE_SHRINK_END
	right.add_child(credit)
	resized.connect(func():
		var c := maxi(2, int((size.x - 424 + 14) / 234))
		if c != _cols:
			_cols = c
			for g in _grid.get_children():
				if g is GridContainer:
					g.columns = c)
	concept.loaded.connect(_update_button)
	concept.progress.connect(func(id):
		_update_button(id)
		if id == _game:
			_update_progress()
		_update_overall())
	concept.saved.connect(func(id, url):
		if id == _game and _badges.has(url) and is_instance_valid(_badges[url]):
			_badges[url].visible = true)
	concept.changed.connect(func(id):
		_update_button(id)
		if id == _game and visible:
			open_game(_game))
	_fill_list()


func on_shown() -> void:
	main.backdrop.set_atmosphere("mist", Color(0.5, 0.5, 0.5))
	if _game == "":
		# Fill in the counts beside each game (answers are cached for a week).
		for g in App.games + App.films:
			App.svc("concept")._site_list(g.id, func(_l): pass)
		open_game(App.games[0].id)
	else:
		_show_art()


func _fill_list() -> void:
	for c in _list.get_children():
		c.queue_free()
	_buttons.clear()
	_list.add_child(Style.margin(Style.label("GAMES", "Caps"), 0, 4, 0, 4))
	for g in App.games:
		var id: String = g.id
		var b := Style.button("", "", func(): open_game(id))
		b.set_meta("sfx", "move")
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size.y = 34
		b.clip_text = true
		b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		_buttons[id] = b
		_list.add_child(b)
		_update_button(id)
	_list.add_child(Style.margin(Style.label("FILMS", "Caps"), 0, 12, 0, 4))
	for f in App.films:
		var fid: String = f.id
		var b := Style.button("", "", func(): open_game(fid))
		b.set_meta("sfx", "move")
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size.y = 34
		b.clip_text = true
		b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		_buttons[fid] = b
		_list.add_child(b)
		_update_button(fid)
	var others: Array = App.svc("concept").other_pictures()
	if not others.is_empty():
		_list.add_child(Style.margin(Style.label("YOUR FOLDERS", "Caps"), 0, 12, 0, 4))
		var b := Style.button("Other pictures   %d" % others.size(), "", func(): open_game("_other"))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		_buttons["_other"] = b
		_list.add_child(b)


func _game_label(id: String) -> String:
	var g := App.game(id)
	if id.begins_with("film-"):
		return "%s (%d)" % [g.get("title", id), int(g.get("year", 0))]
	return str(g.get("title", id)) + (" (%s)" % g.subtitle if g.has("subtitle") else "")


func _update_button(id: String) -> void:
	var b: Button = _buttons.get(id)
	if b == null:
		return
	var concept = App.svc("concept")
	var n: int = concept.count(id)
	var tail := ""
	var j: Dictionary = concept.job(id)
	var kc: Array = concept.kept_count(id)
	if concept.busy(id):
		tail = "   ↓ %d/%d" % [j.done, j.total]
	elif not kc.is_empty() and kc[1] > 0 and kc[0] >= kc[1]:
		tail = "   ✓"
	b.text = _game_label(id) + ("   %d" % n if n > 0 else "") + tail
	b.add_theme_color_override("font_color", Style.INK if id == _game else (Style.INK_2 if n != 0 else Style.INK_3))


## A thin progress bar in the launcher's style.
func _bar(width: int) -> ProgressBar:
	var pb := ProgressBar.new()
	pb.custom_minimum_size = Vector2(width, 6)
	pb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pb.show_percentage = false
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(1, 1, 1, 0.08)
	bg.set_corner_radius_all(3)
	var fg := StyleBoxFlat.new()
	fg.bg_color = Style.INK_2
	fg.set_corner_radius_all(3)
	pb.add_theme_stylebox_override("background", bg)
	pb.add_theme_stylebox_override("fill", fg)
	return pb


static func _mb(bytes: int) -> String:
	return "%.1f MB" % (bytes / 1048576.0) if bytes >= 1048576 else "%d KB" % (bytes / 1024)


## The selected game's download: bar, count and size, updated as each picture lands.
func _update_progress() -> void:
	var concept = App.svc("concept")
	var j: Dictionary = concept.job(_game)
	var kc: Array = concept.kept_count(_game)
	if j.is_empty() and (kc.is_empty() or kc[0] == 0):
		_dl_row.visible = false
		return
	_dl_row.visible = true
	if not j.is_empty() and j.running:
		_dl_bar.max_value = maxi(1, j.total)
		_dl_bar.value = j.done
		_dl_text.text = "Saving for offline use: %d of %d  ·  %s%s" % [j.done, j.total, _mb(j.bytes),
			("  ·  %d failed" % j.failed) if j.failed > 0 else ""]
	else:
		_dl_bar.max_value = maxi(1, kc[1] if not kc.is_empty() else 1)
		_dl_bar.value = kc[0] if not kc.is_empty() else 0
		var all_kept: bool = not kc.is_empty() and kc[0] >= kc[1]
		_dl_text.text = ("All %d kept offline" % kc[1]) if all_kept else ("%d of %d kept offline" % [kc[0], kc[1]])
		if not j.is_empty() and j.failed > 0:
			_dl_text.text += "  ·  %d couldn't be saved (Keep offline tries again)" % j.failed
		if not all_kept and not concept.busy(_game) and _actions.get_children().filter(func(c): return c is Button and c.text == "Keep offline").is_empty():
			var keep := Style.button("Keep offline", "Ghost")
			keep.pressed.connect(func():
				keep.queue_free()
				concept.keep_offline(_game))
			_actions.add_child(keep)


## Everything being saved, under the list on the left.
func _update_overall() -> void:
	var o: Dictionary = App.svc("concept").overall()
	_all_bar.visible = o.running
	_all_btn.disabled = o.running
	if o.running:
		_all_bar.max_value = maxi(1, o.total)
		_all_bar.value = o.done
		_all_text.text = "Saving %d of %d pictures  ·  %s" % [o.done, o.total, _mb(o.bytes)]
	elif o.total > 0:
		_all_text.text = "Saved %d pictures (%s)%s" % [o.done - o.failed, _mb(o.bytes), ("  ·  %d failed" % o.failed) if o.failed > 0 else ""]
	else:
		_all_text.text = ""


func add_folder() -> void:
	main.choose_path("Choose a folder of concept art (art books, press kits)", "folder", PackedStringArray(), func(p):
		if p != "":
			App.svc("concept").add_folder(p))


func open_game(id: String) -> void:
	_open_token += 1
	var token := _open_token
	var prev := _game
	_game = id
	if prev != "" and _buttons.has(prev):
		_update_button(prev)
	_update_button(id)
	for c in _actions.get_children():
		c.queue_free()
	for c in _grid.get_children():
		c.queue_free()
	_show_art()
	var concept = App.svc("concept")
	if id == "_other":
		_title.text = "Other pictures"
		_sub.text = "From your folders that don't match a game"
		_set_pictures(concept.other_pictures().map(func(p): return {"name": str(p).get_file().get_basename().replace("_", " "),
			"thumb": p, "full": p, "ext": "." + str(p).get_extension(), "artist": "", "page": "", "source": "Your files", "local": true}))
		return
	var g := App.game(id)
	_title.text = _game_label(id)
	_sub.text = "Looking on Silent Hill Memories…"
	_grid.add_child(Style.skeleton_grid(8, maxi(2, int((size.x - 424 + 14) / 234)), Vector2(220, 170), 14))
	concept.pictures(id, func(list: Array):
		if not is_instance_valid(self) or token != _open_token:
			return
		var site := list.filter(func(p): return p.source == "Silent Hill Memories")
		var kept := site.filter(func(p): return p.local).size()
		var bits := []
		bits.append("%d picture%s" % [list.size(), "" if list.size() == 1 else "s"])
		if not site.is_empty():
			bits.append("from Silent Hill Memories" + (" and your folders" if site.size() < list.size() else ""))
		elif not list.is_empty():
			bits.append("from your folders")
		if kept > 0:
			bits.append("%d kept offline" % kept)
		_sub.text = "  ·  ".join(bits) if not list.is_empty() else ""
		if not site.is_empty():
			_actions.add_child(Style.button("Open the gallery", "", func(): OS.shell_open(str(site[0].page))))
		if kept < site.size() and not concept.busy(id):
			var keep := Style.button("Keep offline", "Ghost")
			keep.tooltip_text = "Save these pictures to the launcher's concept-art folder, so they stay available without the internet."
			keep.pressed.connect(func():
				keep.queue_free()
				concept.keep_offline(id))
			_actions.add_child(keep)
		_set_pictures(list)
		if list.is_empty():
			_grid.add_child(Style.empty_state("image", "No concept art for %s yet" % g.get("title", id),
				"Silent Hill Memories has none for it, or the site couldn't be reached. Pictures from your own folders (art books, press kits) show here too.",
				"Add a folder…", add_folder))
		_update_progress())


func _set_pictures(list: Array) -> void:
	_pictures = list
	_badges.clear()
	_cols = maxi(2, int((size.x - 424 + 14) / 234))
	for c in _grid.get_children():
		c.queue_free()
	var grid: GridContainer = null
	var last := "\u0000"
	for i in list.size():
		var sec := str(list[i].get("section", ""))
		if sec != last or grid == null:
			last = sec
			if sec != "":
				_grid.add_child(Style.margin(Style.label(sec.to_upper(), "Caps"), 0, 10 if i > 0 else 0, 0, 2))
			grid = GridContainer.new()
			grid.columns = _cols
			grid.add_theme_constant_override("h_separation", 14)
			grid.add_theme_constant_override("v_separation", 14)
			_grid.add_child(grid)
		grid.add_child(_tile(list[i], i))


func _tile(p: Dictionary, i: int) -> Control:
	var box := Style.vbox(6)
	var b := Button.new()
	b.custom_minimum_size = Vector2(220, 170)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.tooltip_text = str(p.name) + ("\n" + str(p.artist) if str(p.get("artist", "")) != "" else "")
	b.clip_contents = true
	var img: TextureRect = NetImage.new("", Vector2(220, 170))
	img.max_px = 480   # local scans can be huge; tiles only need a small copy
	img.load_source(str(p.thumb))
	img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	img.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	b.add_child(img)
	b.pressed.connect(func():
		var v: Control = load("res://ui/widgets/image_viewer.gd").new()
		v.set("pictures", _pictures)
		v.set("index", i)
		main.modal_layer.add_child(v))
	var badge := Label.new()
	badge.text = "Kept"
	badge.add_theme_font_size_override("font_size", 11)
	badge.add_theme_color_override("font_color", Style.INK)
	var bsb := StyleBoxFlat.new()
	bsb.bg_color = Color(0, 0, 0, 0.65)
	bsb.set_content_margin_all(4)
	bsb.content_margin_left = 7
	bsb.content_margin_right = 7
	badge.add_theme_stylebox_override("normal", bsb)
	badge.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	badge.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	badge.grow_vertical = Control.GROW_DIRECTION_BEGIN
	badge.offset_right = -6
	badge.offset_bottom = -6
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.visible = bool(p.get("local", false)) and str(p.get("source", "")) != "Your files"
	b.add_child(badge)
	if str(p.get("url", "")) != "":
		_badges[str(p.url)] = badge
	box.add_child(b)
	var cap := Style.label(str(p.name), "Small")
	cap.custom_minimum_size.x = 220
	cap.clip_text = true
	cap.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	box.add_child(cap)
	return box


func _show_art() -> void:
	if _game == "" or _game == "_other":
		main.backdrop.show_art(null)
		return
	var id := _game
	App.svc("art").get_texture(id, "hero", func(tex):
		if visible and _game == id:
			main.backdrop.show_art(tex, 0.22))
