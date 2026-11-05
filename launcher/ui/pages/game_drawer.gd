extends VBoxContainer
## The drawer beside a game: achievements, saves, mods, the game's connection
## (folders, program, dump, art) and the build log.

const NetImage := preload("res://ui/widgets/net_image.gd")
const PatchSettings := preload("res://core/patch_settings.gd")
const PatchSettingsView := preload("res://ui/widgets/patch_settings_view.gd")

var game_id := ""
var kind := ""
var main: Control
var page: Control
var _log: Label


func _ready() -> void:
	add_theme_constant_override("separation", 14)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	match kind:
		"achievements": _achievements()
		"saves": _saves()
		"mods": _mods()
		"manage": _manage()
		"build": _build()


func _h1(text: String) -> void:
	add_child(Style.label(text, "H1"))


func _section(text: String) -> void:
	add_child(Style.spacer(6))
	add_child(Style.label(text.to_upper(), "Caps"))


func _line() -> void:
	var r := ColorRect.new()
	r.color = Style.LINE
	r.custom_minimum_size.y = 1
	add_child(r)


func _wrap_label(text: String, variation: String) -> Label:
	var l := Style.label(text, variation, true)
	l.custom_minimum_size.x = 400
	return l


# ------------------------------------------------------------------ achievements
func _achievements() -> void:
	var ach = App.svc("achievements")
	_h1(ach.term(game_id))
	var loading := Style.label("Gathering progress…", "Small")
	add_child(loading)
	ach.view(game_id, func(groups: Array):
		if not is_instance_valid(self):
			return
		loading.queue_free()
		if groups.is_empty():
			add_child(_wrap_label("No %s for this game yet. Rebuilds and Enhanced patches report them to the launcher as they're added." % ach.term(game_id).to_lower(), "Meta"))
		for gr in groups:
			_group(gr)
		var row := Style.hbox()
		row.add_child(Style.button("Refresh", "Ghost", func(): page._open_drawer("achievements")))
		add_child(row))


func _group(gr: Dictionary) -> void:
	_section(gr.title)
	if gr.total > 0:
		var pct := int(round(100.0 * gr.unlocked / gr.total))
		var head := Style.hbox(10)
		var big := Style.label("%d" % gr.unlocked, "H1")
		head.add_child(big)
		var of := Style.label("of %d  ·  %d%%" % [gr.total, pct], "Meta")
		of.size_flags_vertical = Control.SIZE_SHRINK_END
		head.add_child(of)
		add_child(head)
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.custom_minimum_size.y = 3
		bar.value = pct
		var fg := StyleBoxFlat.new()
		fg.bg_color = Style.color_hex(App.game(game_id).get("accent", ""))
		var bgs := StyleBoxFlat.new()
		bgs.bg_color = Color(1, 1, 1, 0.1)
		bar.add_theme_stylebox_override("fill", fg)
		bar.add_theme_stylebox_override("background", bgs)
		add_child(bar)
	if gr.get("note", "") != "":
		add_child(_wrap_label(gr.note, "Small"))
	# Unlocked first, newest first; then locked in the game's order.
	var items: Array = gr.items.duplicate()
	var unlocked := items.filter(func(i): return i.unlocked)
	unlocked.sort_custom(func(a, b): return a.at > b.at)
	var locked := items.filter(func(i): return not i.unlocked)
	for it in unlocked + locked:
		add_child(_ach_row(it, gr.source))


func _ach_row(it: Dictionary, source: String) -> Control:
	var row := Style.hbox(14)
	var icon: TextureRect = NetImage.new(it.get("icon", ""), Vector2(44, 44))
	if it.get("icon", "") == "":
		var dot := Panel.new()
		dot.custom_minimum_size = Vector2(44, 44)
		dot.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(1, 1, 1, 0.04)
		sb.border_color = Style.color_hex(App.game(game_id).get("accent", "")) if it.unlocked else Color(1, 1, 1, 0.12)
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(22)
		dot.add_theme_stylebox_override("panel", sb)
		row.add_child(dot)
	else:
		icon.modulate.a = 1.0 if it.unlocked else 0.55
		icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		row.add_child(icon)
	var v := Style.vbox(2)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var secret: bool = it.get("hidden", false) and not it.unlocked
	var name := Style.label("Hidden" if secret else it.name)
	name.add_theme_font_override("font", Style.sans_medium)
	name.add_theme_font_size_override("font_size", 14)
	name.modulate.a = 1.0 if it.unlocked else 0.7
	v.add_child(name)
	if not secret and str(it.get("description", "")) != "":
		var d := _wrap_label(it.description, "Small")
		d.custom_minimum_size.x = 300
		v.add_child(d)
	var meta := []
	if it.unlocked and int(it.get("at", 0)) > 0:
		meta.append(App.fmt_ago(int(it.at)))
	if int(it.get("points", 0)) > 0:
		meta.append("%d %s" % [it.points, "pts" if source == "ra" else "G"])
	if not meta.is_empty():
		v.add_child(Style.label("  ·  ".join(meta), "Small"))
	row.add_child(v)
	if source == "list":
		var b := Style.button("Lock" if it.unlocked else "Unlock", "", func():
			App.svc("achievements").set_unlocked(game_id, it.id, not it.unlocked))
		b.add_theme_font_size_override("font_size", 12)
		row.add_child(b)
	return row


# ------------------------------------------------------------------ saves
func _saves() -> void:
	var saves = App.svc("saves")
	var gs := App.state(game_id)
	_h1("Saves")
	for l in saves.locations(game_id):
		var t := "%s\n%s" % [l.path, ("%d files" % l.files) if l.exists else "Not created yet"]
		var lab := _wrap_label(t, "Small")
		add_child(lab)
	var auto := CheckBox.new()
	auto.text = "Back up before playing (keeps the newest %d)" % saves.KEEP_AUTO
	auto.button_pressed = gs.get("auto_backup", true)
	auto.toggled.connect(func(on): App.set_state(game_id, {"auto_backup": on}))
	add_child(auto)
	var row := Style.hbox(8)
	var name := LineEdit.new()
	name.placeholder_text = "Name this backup (optional)"
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name)
	row.add_child(Style.button("Back up now", "Ghost", func():
		var err: String = saves.backup(game_id, name.text.strip_edges())
		App.notify(err if err != "" else "Saves backed up.", "error" if err != "" else "ok")
		page._open_drawer("saves")))
	add_child(row)
	_section("Backups")
	var list: Array = saves.list(game_id)
	if list.is_empty():
		add_child(_wrap_label("No backups yet. One is made each time you press Play; Back up now makes one any time.", "Meta"))
	for b in list:
		var r := Style.hbox(8)
		var v := Style.vbox(2)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_child(Style.label(b.label if b.label != "" else ("Before playing" if b.kind == "auto" else "Backup"), "Meta"))
		v.add_child(Style.label("%s  ·  %d files" % [Time.get_datetime_string_from_unix_time(b.at, true), b.files], "Small"))
		r.add_child(v)
		r.add_child(Style.button("Restore", "", func():
			main.confirm("Restore this backup? Your current saves are backed up first.", "Restore", func():
				var err: String = saves.restore(game_id, b.name)
				App.notify(err if err != "" else "Saves restored.", "error" if err != "" else "ok")
				page._open_drawer("saves"))))
		r.add_child(Style.button("Delete", "", func():
			main.confirm("Delete this backup?", "Delete", func():
				saves.delete(game_id, b.name)
				page._open_drawer("saves"))))
		add_child(r)


# ------------------------------------------------------------------ mods
func _mods() -> void:
	var mods = App.svc("mods")
	_h1("Mods")
	_enhanced_card()
	add_child(_wrap_label("Turning a mod on copies its files into the game. Anything it replaces is kept, and turning it off puts the originals back.", "Small"))
	var row := Style.hbox(8)
	row.add_child(Style.button("Add a .zip", "Ghost", func():
		main.choose_path("Choose a mod (.zip)", "file", PackedStringArray(["*.zip ; Zip archives"]), func(p):
			if p != "" and mods.import_mod(game_id, p) != "":
				App.notify("Mod added. Turn it on when you're ready.")
				page._open_drawer("mods"))))
	row.add_child(Style.button("Add a folder", "Ghost", func():
		main.choose_path("Choose the mod's folder", "folder", PackedStringArray(), func(p):
			if p != "" and mods.import_mod(game_id, p) != "":
				App.notify("Mod added. Turn it on when you're ready.")
				page._open_drawer("mods"))))
	row.add_child(Style.button("Open folder", "", func(): OS.shell_open(mods.mods_dir(game_id))))
	add_child(row)
	_line()
	var list: Array = mods.list(game_id)
	if list.is_empty():
		add_child(_wrap_label("No mods yet. Add a .zip or a folder above; nothing changes in the game until you turn a mod on.", "Meta"))
	for m in list:
		var r := Style.hbox(10)
		var v := Style.vbox(2)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_child(Style.label(m.name + ("  " + m.version if m.version != "" else ""), "Meta"))
		var sub := "%d file%s" % [m.files, "" if m.files == 1 else "s"]
		if m.author != "":
			sub += "  ·  " + m.author
		v.add_child(Style.label(sub, "Small"))
		r.add_child(v)
		var t := CheckButton.new()
		t.button_pressed = m.enabled
		t.toggled.connect(func(on):
			var err: String = mods.enable(game_id, m.id) if on else mods.disable(game_id, m.id)
			if err != "":
				App.notify(err, "error")
			App.library_changed.emit(game_id)
			page._open_drawer("mods"))
		r.add_child(t)
		add_child(r)


## The game's Enhanced patch, first on the Mods tab: one switch for the whole patch. Off puts the
## game back exactly as it was (files and the config values it changed); on brings every feature
## and setting back (the patch keeps its own settings file). When the package has a settings schema
## (manifest "settings"), the card opens into the patch's settings, saved as they're changed.
static var _patch_open := {}   # game id -> the card is open (this session)

func _enhanced_card() -> void:
	var routes = App.svc("routes")
	var pkg: Dictionary = routes.package(game_id)
	if pkg.get("kind", "") != "enhanced":
		return
	var s: Dictionary = routes.status(game_id)
	var on: bool = s.get("patch_installed", false)
	var connected: bool = s.get("connected", false)
	var game_path: String = App.state(game_id).get("path", "")
	var schema: Dictionary = PatchSettings.load_schema(pkg, game_path) if connected else {}
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", Style.raised_box(Style.SPACE_L, Style.SPACE_L))
	var col := Style.vbox(Style.SPACE_M)
	var top := Style.hbox(Style.SPACE_S)
	var chevron: Button = null
	if not schema.is_empty():
		chevron = Style.icon_button("chevron-right", "Settings", Callable(), "", "", 20)
		chevron.custom_minimum_size = Vector2(32, Style.target())
		top.add_child(chevron)
	var head := Style.vbox(2)
	head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(Style.label("%s  %s" % [pkg.get("name", "Enhanced patch"), pkg.get("version", "")], "Meta", true))
	head.add_child(Style.label(("On" if on else "Off") if connected else "Connect the game first (Manage).", "Small"))
	top.add_child(head)
	var t := CheckButton.new()
	t.button_pressed = on
	t.focus_mode = Control.FOCUS_ALL
	t.tooltip_text = "Turn %s on or off" % pkg.get("name", "the patch")
	t.accessibility_name = "%s on" % pkg.get("name", "the patch")
	t.disabled = not connected
	t.toggled.connect(func(want):
		var err: String = routes.install_patch(game_id) if want else routes.remove_patch(game_id)
		if err != "":
			App.notify(err, "error")
		else:
			App.notify("%s is %s." % [pkg.get("name", "The patch"), "on" if want else "off; the game is back to how it was"])
		App.library_changed.emit(game_id)
		page._open_drawer("mods"))
	top.add_child(t)
	col.add_child(top)
	if chevron != null:
		var view: Control = PatchSettingsView.new()
		view.set("game_id", game_id)
		view.set("schema", schema)
		view.set("game_path", game_path)
		view.set("patch_on", on)
		col.add_child(view)
		var set_open := func(open: bool):
			view.visible = open
			chevron.icon = Style.icon("chevron-down" if open else "chevron-right", 20, Color.WHITE)
			chevron.tooltip_text = "Hide settings" if open else "Show settings"
			chevron.accessibility_name = "%s settings, %s" % [pkg.get("name", "Patch"), "expanded" if open else "collapsed"]
		set_open.call(_patch_open.get(game_id, false))
		var flip := func():
			_patch_open[game_id] = not view.visible
			set_open.call(not view.visible)
		chevron.pressed.connect(flip)
		# The whole header (not the switch) opens and closes it too.
		head.mouse_filter = Control.MOUSE_FILTER_STOP
		head.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		head.gui_input.connect(func(e):
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				flip.call()
				head.accept_event())
	card.add_child(col)
	add_child(card)
	add_child(Style.spacer(8))


# ------------------------------------------------------------------ manage
func _manage() -> void:
	var g := App.game(game_id)
	var gs := App.state(game_id)
	var s: Dictionary = App.svc("routes").status(game_id)
	_h1("Manage")
	_section("Game")
	_path_row("Folder", gs.path, func():
		main.choose_path("Where is %s?" % g.title, "folder", PackedStringArray(), func(p):
			if p != "":
				page._set_folder(game_id, p)
				page._open_drawer("manage")))
	if g.route.kind != "steam":
		_path_row("Program", str(gs.get("exe", "")) if str(gs.get("exe", "")) != "" else "Found automatically", func():
			main.choose_path("Choose the program to start", "file", PackedStringArray(["*.exe ; Programs"]), func(p):
				if p != "":
					App.set_state(game_id, {"exe": p})
					page._open_drawer("manage")))
	if g.has("dump"):
		_path_row("Your dump", str(gs.get("dump", "")), func(): page._browse())
	if g.route.kind == "steam" or str(gs.get("steam_appid", "")) != "":
		add_child(Style.label("Steam app %s" % gs.get("steam_appid", g.install.get("steam_appid", "?")), "Small"))
	var row := Style.hbox(8)
	row.add_child(Style.button("Look again", "Ghost", func(): page._find(game_id)))
	if gs.path != "":
		row.add_child(Style.button("Open folder", "", func(): OS.shell_open(gs.path)))
	add_child(row)

	_section("Artwork")
	var art = App.svc("art")
	add_child(_wrap_label("Pick from official art (Steam, Silent Hill Memories), SteamGridDB or a web search, or use any picture of your own.", "Small"))
	var arow := Style.hbox(8)
	for k in [["hero", "Background"], ["logo", "Logo"]]:
		arow.add_child(Style.button(k[1] + "…", "Ghost", func(): _art_picker(k[0])))
	add_child(arow)

	_section("Package")
	var pkg: Dictionary = s.get("package", {})
	if pkg.is_empty():
		add_child(_wrap_label("%s: %s" % [g.route.get("label", ""), "not packaged with this launcher yet. When it is, it appears in the launcher's rebuilds folder and this page offers it." if g.route.kind != "steam" else "played through Steam."], "Small"))
	else:
		add_child(_wrap_label("%s %s" % [pkg.get("name", ""), pkg.get("version", "")], "Meta"))
		if pkg.get("kind", "") == "enhanced" and s.get("patch_installed", false):
			add_child(Style.button("Turn the patch off", "", func():
				main.confirm("Turn %s off? The original files and settings are put back." % pkg.get("name", "the patch"), "Turn off", func():
					var err: String = App.svc("routes").remove_patch(game_id)
					if err != "":
						App.notify(err, "error")
					App.library_changed.emit(game_id)
					page._open_drawer("manage"))))

	_section("Play time")
	var acc = App.svc("accounts")
	var n_s: int = acc.sessions(game_id)
	add_child(Style.label("Not played yet" if n_s == 0 else "%s over %d session%s" % [App.fmt_duration(acc.playtime(game_id)), n_s, "" if n_s == 1 else "s"], "Meta"))
	add_child(Style.spacer(10))
	add_child(Style.button("Disconnect this game", "", func():
		main.confirm("Disconnect %s? Nothing on disk is touched; play time and backups stay." % g.title, "Disconnect", func():
			App.set_state(game_id, {"path": "", "exe": "", "dump": ""})
			page._open_drawer("manage"))))


func _path_row(label: String, value: String, change: Callable) -> void:
	var r := Style.hbox(10)
	var v := Style.vbox(2)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(Style.label(label, "Meta"))
	var p := Style.label(value if value != "" else "Not set", "Small")
	p.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	p.custom_minimum_size.x = 300
	v.add_child(p)
	r.add_child(v)
	r.add_child(Style.button("Change", "", change))
	add_child(r)


func _art_picker(art_kind: String) -> void:
	var p: Control = load("res://ui/widgets/art_picker.gd").new()
	p.set("main", main)
	p.set("game_id", game_id)
	p.set("kind", art_kind)
	main.modal_layer.add_child(p)


# ------------------------------------------------------------------ build log
func _build() -> void:
	_h1("Building")
	add_child(_wrap_label("Making a native PC version from your dump. This runs on your PC only; nothing is downloaded.", "Small"))
	_log = Style.label("", "Small", true)
	_log.custom_minimum_size.x = 420
	_log.add_theme_font_size_override("font_size", 11)
	add_child(_log)


func append_log(line: String) -> void:
	if _log:
		var lines := (_log.text + "\n" + line).split("\n")
		_log.text = "\n".join(lines.slice(max(0, lines.size() - 400)))


