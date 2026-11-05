extends Control
## Comics on the phone: your comics from the PC, read page by page (each page
## fetched as you go) or kept on the phone. Your place syncs with the PC.

var main   # companion_main.gd
var _list: VBoxContainer
var _sub: Label


static func kept_dir(id: String) -> String:
	return App.svc("pc").media_dir("comics").path_join(id)


static func kept_index() -> Dictionary:
	return App.read_json(App.svc("pc").media_dir("comics").path_join("comics.json"), {})


static func page_file(id: String, n: int) -> String:
	var kept := kept_dir(id).path_join("%04d.webp" % n)
	if FileAccess.file_exists(kept):
		return kept
	return App.svc("pc").cache_dir("comics").path_join(id).path_join("%04d.webp" % n)


## Your place in each comic on this phone: {id: {page, at}}.
static func places() -> Dictionary:
	return App.settings.get("comic_places", {})


static func set_place(c: Dictionary, page: int, total: int) -> void:
	var p := places()
	p[c.id] = {"page": page, "total": total, "at": int(Time.get_unix_time_from_system())}
	App.set_setting("comic_places", p)
	App.svc("pc").post_json("/api/comics/progress", {"id": c.id, "page": page, "total": total}, Callable(), true)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var pv: Array = main._scroll_page()
	add_child(pv[0])
	var v: VBoxContainer = pv[1]
	v.add_child(Style.label("Comics", "H1"))
	_sub = Style.label("Asking your PC for your comics…", "Small", true)
	v.add_child(_sub)
	_list = Style.vbox(10)
	v.add_child(_list)
	if kept_index().is_empty():
		_list.add_child(Style.skeleton_list(4, 112))
	else:
		_fill(kept_index().values(), true)
	App.svc("pc").get_json("/api/comics", func(data):
		if not is_instance_valid(_list):
			return
		if data is Dictionary and data.has("comics"):
			_fill(data.comics, false)
		elif kept_index().is_empty():
			for c in _list.get_children():
				c.queue_free()
			_sub.text = ""
			_list.add_child(Style.empty_state("wifi-off", "Your PC isn't answering",
				"Nothing is kept on this phone yet, so this needs your PC: open Silent Hills on it with the phone companion turned on, on the same Wi-Fi.",
				"Try again", func(): main.show_section(main._section)))
	)


func _fill(list: Array, offline: bool) -> void:
	for c in _list.get_children():
		c.queue_free()
	if list.is_empty():
		_sub.text = ""
		if not offline:
			_list.add_child(Style.empty_state("book-open", "No comics on your PC yet",
				"Add CBZ files or folders of pages in the launcher's Comics tab; they show here the next time this phone syncs."))
		return
	_sub.text = ("%d kept on this phone" % list.size()) if offline else ("%d comics on %s" % [list.size(), App.svc("pc").pc().get("name", "your PC")])
	var series := ""
	for c in list:
		if str(c.get("series_title", "")) != series:
			series = str(c.get("series_title", ""))
			var head := Style.label(series.to_upper() + ("  ·  %d" % int(c.year) if int(c.get("year", 0)) > 0 else ""), "Caps")
			_list.add_child(Style.margin(head, 0, 12, 0, 0))
		_list.add_child(_row(c))


func _row(c: Dictionary) -> Control:
	var b := Button.new()
	b.custom_minimum_size.y = 112
	b.set_meta("sfx", "move")
	var h := Style.hbox(14)
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 8
	h.offset_top = 8
	h.offset_bottom = -8
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var img: TextureRect = load("res://ui/widgets/net_image.gd").new("", Vector2(64, 96))
	img.max_px = 160
	img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	var local := kept_dir(c.id).path_join("cover.webp")
	if FileAccess.file_exists(local):
		img.load_source(local)
	else:
		img.headers = App.svc("pc").auth()
		img.load_source(App.svc("pc").base_url() + "/api/comics/cover?id=" + str(c.id))
	h.add_child(img)
	var tv := Style.vbox(4)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var t := Style.label(str(c.title), "", true)
	t.add_theme_font_override("font", Style.serif)
	t.add_theme_font_size_override("font_size", 20)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tv.add_child(t)
	var page := _place(c)
	var total := int(c.get("pages", 0))
	var state := "Not started"
	if (c.get("finished", false) and page == 0) or (total > 0 and page >= total - 1):
		state = "Finished"
	elif page > 0:
		state = "Page %d%s" % [page + 1, (" of %d" % total) if total > 0 else ""]
	if kept_index().has(c.id):
		state += "  ·  kept"
	var s := Style.label(state, "Small")
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tv.add_child(s)
	h.add_child(tv)
	b.add_child(h)
	b.pressed.connect(func(): _open(c))
	return b


## The furthest-forward of the PC's place and this phone's newest one.
func _place(c: Dictionary) -> int:
	var mine: Dictionary = places().get(c.id, {})
	if not mine.is_empty() and int(mine.at) >= int(c.get("page_at", 0)):
		return int(mine.page)
	return int(c.get("page", 0))


func _open(c: Dictionary) -> void:
	var r: Control = load("res://companion/phone_reader.gd").new()
	r.main = main
	r.comic = c
	r.start_page = _place(c)
	r.tree_exited.connect(func():
		if is_instance_valid(self) and is_inside_tree():
			_ready_again.call_deferred())   # show the new places
	main.overlay(r)


func _ready_again() -> void:
	for ch in get_children():
		ch.queue_free()
	_ready()


## Saves every page (and the cover) to the phone. progress(done, total); cb(ok).
static func keep_comic(c: Dictionary, progress: Callable, cb: Callable) -> void:
	var pc = App.svc("pc")
	var dir := kept_dir(c.id)
	DirAccess.make_dir_recursive_absolute(dir)
	var total := int(c.get("pages", 0))
	var state := [0, true]
	var one := func(self_ref: Callable):
		if (total > 0 and state[0] >= total) or not state[1]:
			pc.fetch("/api/comics/cover?id=" + str(c.id), dir.path_join("cover.webp"), func(_ok): pass)
			if state[1] or state[0] > 0:
				var idx := kept_index()
				var cc := c.duplicate()
				cc.pages = state[0] if total == 0 else total
				idx[c.id] = cc
				App.write_json(pc.media_dir("comics").path_join("comics.json"), idx)
			cb.call(total > 0 and state[0] >= total)
			return
		var n: int = state[0]
		var dest := dir.path_join("%04d.webp" % n)
		var cached: String = pc.cache_dir("comics").path_join(c.id).path_join("%04d.webp" % n)
		if FileAccess.file_exists(cached) and not FileAccess.file_exists(dest):
			DirAccess.rename_absolute(cached, dest)
		pc.fetch("/api/comics/page?id=%s&n=%d" % [c.id, n], dest, func(ok: bool):
			if ok:
				state[0] += 1
				progress.call(state[0], total)
			else:
				state[1] = false
			self_ref.call(self_ref))
	one.call(one)


static func forget_comic(id: String) -> void:
	var dir := kept_dir(id)
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)
	var idx := kept_index()
	idx.erase(id)
	App.write_json(App.svc("pc").media_dir("comics").path_join("comics.json"), idx)
