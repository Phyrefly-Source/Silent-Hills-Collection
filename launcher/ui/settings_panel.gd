extends VBoxContainer
## Launcher settings: libraries, online services, playback and tools.
## (Game settings live inside the games themselves.)

var main: Control
var modal: Control


func _ready() -> void:
	add_theme_constant_override("separation", 12)
	var head := Style.hbox()
	head.add_child(Style.label("Settings", "H1"))
	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(fill)
	head.add_child(Style.button("Done", "Ghost", func(): modal.queue_free()))
	add_child(head)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(620, 560)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var v := Style.vbox(12)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(v)
	add_child(scroll)

	_section(v, "Library")
	v.add_child(_note("Silent Hills looks for games, existing PC builds and disc dumps in each drive's usual game folders, your Steam libraries, Documents, Downloads and Desktop. Add any other folder here."))
	var roots := Style.vbox(4)
	v.add_child(roots)
	_fill_roots(roots)
	var row := Style.hbox(8)
	row.add_child(Style.button("Add a folder…", "Ghost", func():
		main.choose_path("Add a folder to look in", "folder", PackedStringArray(), func(p):
			if p != "":
				var r: Array = App.settings.get("extra_scan_roots", [])
				if not r.has(p):
					r.append(p)
					App.set_setting("extra_scan_roots", r)
				_fill_roots(roots))))
	row.add_child(Style.button("Look for games now", "Ghost", func():
		modal.queue_free()
		main.scan_everything(false)))
	v.add_child(row)

	_section(v, "Artwork")
	v.add_child(_note("Official art is fetched from SteamGridDB with your own free API key (steamgriddb.com → Preferences → API). Steam's local art cache is always used when a game is on Steam."))
	v.add_child(_field("SteamGridDB API key", "sgdb_key", true, func(t: String) -> String:
		return "" if t == "" or RegEx.create_from_string("^[0-9a-fA-F]{32}$").search(t) else "Enter the 32-character key from steamgriddb.com → Preferences → API."))

	var steam_users: Array = preload("res://core/achievements/steam_stats.gd").users(App.svc("scanner").steam_root())
	if steam_users.size() > 1:
		_section(v, "Steam")
		var ob := OptionButton.new()
		ob.add_item("Whoever has played", 0)
		var sel := 0
		for i in steam_users.size():
			ob.add_item(steam_users[i].name, i + 1)
			if steam_users[i].account == str(App.settings.get("steam_user", "")):
				sel = i + 1
		ob.select(sel)
		ob.item_selected.connect(func(i): App.set_setting("steam_user", "" if i == 0 else steam_users[i - 1].account))
		v.add_child(_labeled("Account for Steam achievements", ob))

	_section(v, "Phone companion")
	v.add_child(_note("The Silent Hills app for Android shows this launcher's achievements, concept art, soundtracks, comics and films. It connects over your home Wi-Fi: turn this on, open the app on your phone and choose Find my PC, then type the code this PC shows."))
	var comp_box := Style.vbox(8)
	v.add_child(comp_box)
	_fill_companion(comp_box)

	_section(v, "Library view")
	v.add_child(_check("Hide comics, films and soundtracks you don't have", "hide_missing"))
	v.add_child(_note("When this is off, the shelves also list what's missing, so they double as a checklist."))

	_section(v, "Sounds")
	v.add_child(_note("Interface sounds as you move through the launcher. Each profile uses a Silent Hill game's own menu sounds (Silent Hill, 2, 3, 4, Homecoming, Shattered Memories, P.T.), read from your copy of the game; Radio static is made by the launcher."))
	var sfx_box := Style.vbox(8)
	v.add_child(sfx_box)
	_fill_sounds(sfx_box)

	_section(v, "Playing")
	v.add_child(_check("Close to the tray while a game runs (click the icon by the clock to bring it back)", "minimize_on_play"))
	v.add_child(_check("Atmosphere effects (fog, weather, grain)", "ambience"))
	v.add_child(_check("Reduce motion", "reduce_motion"))
	v.add_child(_note("Keeps the backgrounds, spinners and panels still: things fade instead of moving."))
	var vol := HSlider.new()
	vol.min_value = 0
	vol.max_value = 1
	vol.step = 0.01
	vol.value = float(App.settings.get("volume", 0.8))
	vol.custom_minimum_size.x = 260
	vol.value_changed.connect(func(x): App.set_setting("volume", x))
	v.add_child(_labeled("Music volume", vol))

	_section(v, "Tools")
	var ff: String = App.svc("music").ffmpeg_path()
	var fnote := _note("FFmpeg lets the jukebox play music that needs converting first (Origins' ATRAC3 tracks, FLAC). The launcher fetches it from FFmpeg's own release builds. " + ("Found: " + ff if ff != "" else "Not found."))
	v.add_child(fnote)
	var frow := Style.hbox(8)
	var fsvc = App.svc("ffmpeg")
	var fbtn := Style.button("Update FFmpeg" if ff != "" else "Download FFmpeg", "Ghost")
	fbtn.pressed.connect(func():
		fbtn.disabled = true
		fnote.text = "Looking up the newest FFmpeg build…"
		fsvc.fetch(true))
	fsvc.progress.connect(func(done: int, total: int):
		if total > 0:
			fnote.text = "Downloading FFmpeg… %d%% (%d MB)" % [done * 100 / total, total / 1048576])
	fsvc.finished.connect(func(p: String):
		fbtn.disabled = false
		fbtn.text = "Update FFmpeg"
		fnote.text = "FFmpeg ready: " + p + "  (" + fsvc.installed_version() + ")")
	fsvc.failed.connect(func(m: String):
		fbtn.disabled = false
		fnote.text = m)
	frow.add_child(fbtn)
	frow.add_child(Style.button("Choose ffmpeg.exe…", "Ghost", func():
		main.choose_path("Choose ffmpeg.exe", "file", PackedStringArray(["*.exe ; Programs"]), func(p):
			if p != "":
				App.set_setting("ffmpeg", p))))
	v.add_child(frow)

	_section(v, "About")
	v.add_child(_note("Silent Hills %s. Built with Godot. Everything the launcher keeps is in its data folder." % App.VERSION))
	var urow := Style.hbox(8)
	var ulabel := _note("Updates come from the GitHub releases page; the launcher looks every few hours.")
	var ubtn := Style.button("Check for updates", "Ghost")
	ubtn.pressed.connect(func():
		ubtn.disabled = true
		ulabel.text = "Checking…"
		var u = App.svc("updater")
		var done := func(available: bool):
			ubtn.disabled = false
			ulabel.text = ("Silent Hills %s is available: see the banner at the top." % u.latest.version) if available else "You have the latest build (%s)." % App.VERSION
		u.checked.connect(done, CONNECT_ONE_SHOT)
		u.failed.connect(func(m: String):
			ubtn.disabled = false
			ulabel.text = m, CONNECT_ONE_SHOT)
		u.check(true))
	urow.add_child(ubtn)
	v.add_child(urow)
	v.add_child(ulabel)
	var arow := Style.hbox(8)
	arow.add_child(Style.button("Open data folder", "Ghost", func(): OS.shell_open(App.data_dir)))
	arow.add_child(Style.button("Open rebuilds folder", "", func(): OS.shell_open(App.root_dir.path_join("rebuilds"))))
	v.add_child(arow)
	v.add_child(_note("A fan-made launcher, not affiliated with or endorsed by Konami. Silent Hill is a trademark of Konami Digital Entertainment. No game data, art or music is included; everything comes from your own copies."))


func _fill_sounds(box: VBoxContainer) -> void:
	for c in box.get_children():
		c.queue_free()
	var cur := str(App.settings.get("sound_profile", "radio"))
	var ob := OptionButton.new()
	var ids: Array = Sfx.PROFILES.keys()
	for i in ids.size():
		var id: String = ids[i]
		var ok: bool = Sfx.available(id)
		var game: String = Sfx.PROFILES[id].get("game", "")
		ob.add_item(Sfx.PROFILES[id].name + ("" if ok else "  (connect %s first)" % App.entry(game).get("title", game)), i)
		ob.set_item_disabled(i, not ok)
		if id == cur:
			ob.select(i)
	ob.item_selected.connect(func(i):
		App.set_setting("sound_profile", ids[i])
		Sfx.play("select")
		_fill_sounds(box))
	box.add_child(_labeled("Sound profile", ob))
	var about: String = Sfx.PROFILES.get(cur, {}).get("about", "")
	if about != "":
		box.add_child(_note(about))
	var vol := HSlider.new()
	vol.min_value = 0
	vol.max_value = 1
	vol.step = 0.01
	vol.value = float(App.settings.get("sfx_volume", 0.5))
	vol.custom_minimum_size.x = 260
	vol.value_changed.connect(func(x): App.set_setting("sfx_volume", x))
	vol.drag_ended.connect(func(_c): Sfx.play("select"))
	box.add_child(_labeled("Sound volume", vol))
	if cur == "off":
		return
	var tries := Style.hbox(8)
	for e in [["move", "Move"], ["tab", "Section"], ["select", "Select"], ["back", "Back"]]:
		var ev: String = e[0]
		var b := Style.icon_button("play", "Play the %s sound" % e[1].to_lower(), func(): Sfx.play(ev), e[1], "", 16)
		b.set_meta("sfx", "none")
		tries.add_child(b)
	if Sfx.PROFILES.get(cur, {}).has("game"):
		tries.add_child(Style.button("Choose sounds…", "Ghost", func(): _choose_sounds(cur, box)))
	box.add_child(_labeled("Try", tries))


## Pick which of a game's sounds each event uses, trying them as you go.
func _choose_sounds(id: String, box: VBoxContainer) -> void:
	var lib: Dictionary = Sfx.library(id)
	var custom: Dictionary = App.settings.get("sfx_custom", {}).get(id, {})
	var map: Dictionary = Sfx.DEFAULTS.get(id, Sfx.GameSounds.DEFAULTS.get(id, {})).duplicate()
	map.merge(custom, true)
	var v := Style.vbox(14)
	v.add_child(Style.label("%s sounds" % Sfx.PROFILES[id].name, "H1"))
	v.add_child(_note("%d sounds found in your copy of the game. Pick one for each action; ▶ plays it." % lib.size()))
	var names: Array = lib.keys()
	for e in [["move", "Moving through items"], ["tab", "Switching sections"], ["select", "Pressing a button"], ["back", "Closing"]]:
		var ev: String = e[0]
		var row := Style.hbox(10)
		var ob := OptionButton.new()
		ob.custom_minimum_size.x = 260
		ob.fit_to_longest_item = false
		for i in names.size():
			ob.add_item("%s  (%.2fs)" % [names[i], (lib[names[i]] as AudioStream).get_length()], i)
			if names[i] == map.get(ev, ""):
				ob.select(i)
		ob.item_selected.connect(func(i):
			Sfx.preview(lib[names[i]])
			var all: Dictionary = App.settings.get("sfx_custom", {})
			var mine: Dictionary = all.get(id, {})
			mine[ev] = names[i]
			all[id] = mine
			App.set_setting("sfx_custom", all))
		row.add_child(_labeled(e[1], ob))
		var play := Style.icon_button("play", "Play this sound", func():
			if ob.selected >= 0:
				Sfx.preview(lib[names[ob.selected]]), "", "", 16)
		play.set_meta("sfx", "none")
		row.add_child(play)
		v.add_child(row)
	var foot := Style.hbox(8)
	var m: Control
	foot.add_child(Style.button("Back to the defaults", "", func():
		var all: Dictionary = App.settings.get("sfx_custom", {})
		all.erase(id)
		App.set_setting("sfx_custom", all)
		m.queue_free()))
	foot.add_child(Style.button("Done", "Ghost", func(): m.queue_free()))
	v.add_child(foot)
	m = main.open_modal(v, 700)


func _fill_companion(box: VBoxContainer) -> void:
	for c in box.get_children():
		c.queue_free()
	var comp = App.svc("companion")
	var on := CheckBox.new()
	on.text = "Let the phone app connect"
	on.button_pressed = comp.enabled()
	on.toggled.connect(func(x):
		App.set_setting("companion_enabled", x)
		_fill_companion.call_deferred(box))
	box.add_child(on)
	if comp.enabled():
		if comp.running():
			box.add_child(_note("Listening on %s (port %d). Your phone needs to be on the same network." % [", ".join(comp.addresses()), comp.PORT]))
		else:
			box.add_child(_note("Couldn't open port %d. Another program may be using it, or Windows Firewall needs to allow Silent Hills on private networks." % comp.PORT))
	var app: Dictionary = comp.app_info()
	if app.is_empty():
		box.add_child(_note("The companion app (SilentHillsCompanion.apk) isn't in the launcher's companion folder, so phones can't be updated from here."))
	else:
		box.add_child(_note("Companion app %s is here. Paired phones that are older are offered it the next time they sync; the phone downloads it from this PC and Android installs it." % app.version))
	var devs: Array = comp.devices()
	for d in devs:
		var row := Style.hbox(8)
		var seen := int(d.get("last_seen", 0))
		var bits := [str(d.name), ("last synced " + App.fmt_ago(seen)) if seen > 0 else "paired"]
		if int(d.get("app_code", 0)) > 0:
			var behind: bool = not app.is_empty() and int(d.app_code) < int(app.code)
			bits.append("app %s%s" % [d.get("app_version", "?"), ("  (update waiting)" if behind else "")])
		var l := Style.label("  ·  ".join(bits), "Meta")
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		var tok: String = d.token
		row.add_child(Style.button("Forget", "", func():
			comp.forget(tok)
			_fill_companion(box)))
		box.add_child(row)


func _section(v: VBoxContainer, text: String) -> void:
	v.add_child(Style.spacer(10))
	v.add_child(Style.label(text.to_upper(), "Caps"))


func _note(text: String) -> Label:
	var l := Style.label(text, "Small", true)
	l.custom_minimum_size.x = 600
	return l


func _labeled(text: String, c: Control) -> Control:
	var r := Style.hbox(16)
	var l := Style.label(text, "Meta")
	l.custom_minimum_size.x = 220
	r.add_child(l)
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_child(c)
	return r


## A text setting. `check` returns an error message ("" when fine); it runs
## when you leave the field, and the message goes away on the keystroke that
## fixes it.
func _field(text: String, key: String, secret: bool, check: Callable = Callable()) -> Control:
	var e := LineEdit.new()
	e.text = str(App.settings.get(key, ""))
	e.secret = secret
	e.accessibility_name = text
	var err := Style.label("", "Small", true)
	err.add_theme_color_override("font_color", Style.DANGER)
	err.visible = false
	e.text_changed.connect(func(t):
		App.set_setting(key, t.strip_edges())
		if err.visible and check.is_valid() and check.call(t.strip_edges()) == "":
			err.visible = false)
	e.focus_exited.connect(func():
		if check.is_valid():
			var m: String = check.call(e.text.strip_edges())
			err.text = m
			err.visible = m != "")
	var v := Style.vbox(Style.SPACE_XS)
	v.add_child(_labeled(text, e))
	v.add_child(err)
	return v


func _check(text: String, key: String) -> CheckBox:
	var c := CheckBox.new()
	c.text = text
	c.button_pressed = bool(App.settings.get(key, false))
	c.toggled.connect(func(on): App.set_setting(key, on))
	return c


func _fill_roots(box: VBoxContainer) -> void:
	for c in box.get_children():
		c.queue_free()
	for r in App.settings.get("extra_scan_roots", []):
		var row := Style.hbox(8)
		var l := Style.label(str(r), "Meta")
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		row.add_child(Style.button("Remove", "", func():
			var list: Array = App.settings.get("extra_scan_roots", [])
			list.erase(r)
			App.set_setting("extra_scan_roots", list)
			_fill_roots(box)))
		box.add_child(row)
