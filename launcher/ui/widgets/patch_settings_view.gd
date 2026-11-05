extends VBoxContainer
## An Enhanced patch's settings, grouped as its schema groups them (core/patch_settings.gd).
## Every change is saved to the patch's INI at once (sliders and typed numbers after a short
## pause). While the game runs, settings the game can't pick up live are locked; the rest stay
## editable and the game applies them as they're saved. Changes the game itself makes to the file
## show up here too.

const PS := preload("res://core/patch_settings.gd")
const DEBOUNCE := 0.25
const LOCKED_NOTE := "Applies at next start — close the game to change"

## Open groups, per game, for this session: "game_id/title" -> true.
static var open_groups := {}

var game_id := ""
var schema := {}
var game_path := ""
var patch_on := false

var _ini := ""
var _rows := []          # [{item, value, set_shown: Callable, controls: [Control], reset, lock_note}]
var _pending := {}       # row index -> Timer
var _seen := ""        # the file as last read or written
var _banner: Label
var _poll: Timer


func _ready() -> void:
	add_theme_constant_override("separation", Style.SPACE_S)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ini = game_path.path_join(str(schema.get("ini", "")))
	_seen = _disk_text()
	var data := PS.parse(_seen)
	_banner = Style.label("", "Small", true)
	_banner.custom_minimum_size.x = 300
	add_child(_banner)
	var groups: Array = schema.get("groups", [])
	for g in groups:
		_group(g, data)
	var runner = App.svc("runner")
	runner.session_started.connect(_on_session)
	runner.session_ended.connect(_on_session_ended)
	_apply_lock()
	# The game writes this file too (its own Options menu): keep what's shown current.
	_poll = Timer.new()
	_poll.wait_time = 1.5
	_poll.timeout.connect(_check_disk)
	add_child(_poll)
	_poll.start()


func _exit_tree() -> void:
	# The drawer closed or was rebuilt: save anything still waiting.
	for i in _pending.keys():
		_save(i)


func _running() -> bool:
	return App.svc("runner").is_running(game_id)


func _on_session_ended(id: String, _seconds: int) -> void:
	_on_session(id)


func _on_session(id: String) -> void:
	if id == game_id and is_inside_tree():
		_apply_lock()


# ------------------------------------------------------------------ building
func _group(g: Dictionary, data: Dictionary) -> void:
	var key := game_id + "/" + str(g.get("title", ""))
	var items: Array = g.get("items", [])
	var head := Style.button("", "", Callable())
	head.alignment = HORIZONTAL_ALIGNMENT_LEFT
	head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_theme_constant_override("icon_max_width", 16)
	head.custom_minimum_size.y = Style.target()
	var title := str(g.get("title", "")).to_upper()
	head.text = "%s   %d" % [title, items.size()]
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if Style.sans_semibold:
		head.add_theme_font_override("font", Style.sans_semibold)
	head.add_theme_font_size_override("font_size", 12)
	add_child(head)
	var body := Style.vbox(Style.SPACE_M)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var inner := Style.margin(body, Style.SPACE_S, 0, 0, Style.SPACE_S)
	add_child(inner)
	if str(g.get("note", "")) != "":
		var n := Style.label(str(g.note), "Small", true)
		n.custom_minimum_size.x = 300
		body.add_child(n)
	for it in items:
		body.add_child(_item_row(it, data))
	var set_open := func(on: bool):
		inner.visible = on
		head.icon = Style.icon("chevron-down" if on else "chevron-right", 16, Color.WHITE)
		head.accessibility_name = "%s, %s" % [g.get("title", ""), "expanded" if on else "collapsed"]
		head.tooltip_text = ("Hide " if on else "Show ") + str(g.get("title", "")).to_lower()
	set_open.call(open_groups.get(key, false))
	head.pressed.connect(func():
		var on: bool = not inner.visible
		open_groups[key] = on
		set_open.call(on))
	var sep := ColorRect.new()
	sep.color = Style.LINE
	sep.custom_minimum_size.y = 1
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(sep)


func _item_row(it: Dictionary, data: Dictionary) -> Control:
	var idx := _rows.size()
	var row := {"item": it, "value": PS.value_of(data, it), "controls": []}
	_rows.append(row)
	var type := str(it.get("type", "float"))
	var v := Style.vbox(Style.SPACE_XS)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var top := Style.hbox(Style.SPACE_S)
	var name := Style.label(str(it.get("label", it.get("key", ""))), "Meta", true)
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name.custom_minimum_size.x = 160
	top.add_child(name)
	v.add_child(top)
	var help := str(it.get("help", ""))

	match type:
		"bool":
			var t := CheckBox.new()   # the design system's drawn check box
			t.focus_mode = Control.FOCUS_ALL
			t.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			t.accessibility_name = name.text
			t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			t.toggled.connect(func(on): _changed(idx, 1.0 if on else 0.0, false))
			top.add_child(t)
			row.controls = [t]
			row.set_shown = func(x: float): t.set_pressed_no_signal(x >= 0.5)
		"choice":
			var ob := OptionButton.new()
			ob.focus_mode = Control.FOCUS_ALL
			ob.accessibility_name = name.text
			ob.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			ob.custom_minimum_size.x = 120
			var opts: Array = it.get("options", [])
			for i in opts.size():
				ob.add_item(str(opts[i]), i)
			ob.item_selected.connect(func(i): _changed(idx, float(i), false))
			top.add_child(ob)
			row.controls = [ob]
			row.set_shown = func(x: float): ob.select(int(x))
		_:
			var line := Style.hbox(Style.SPACE_M)
			var s := HSlider.new()
			s.focus_mode = Control.FOCUS_ALL
			s.accessibility_name = name.text
			s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			s.custom_minimum_size.y = 24
			s.min_value = float(it.get("min", 0))
			s.max_value = float(it.get("max", 1))
			s.step = _slider_step(it)
			var e := LineEdit.new()
			e.custom_minimum_size.x = 88
			e.alignment = HORIZONTAL_ALIGNMENT_RIGHT
			e.accessibility_name = name.text + " value"
			e.tooltip_text = "%s to %s" % [PS.format(it, s.min_value), PS.format(it, s.max_value)]
			e.select_all_on_focus = true
			s.value_changed.connect(func(x):
				e.text = PS.format(it, x)
				_changed(idx, x, true))
			var commit := func():
				var txt := e.text.strip_edges().replace(",", ".")
				if txt.is_valid_float() or txt.is_valid_int():
					var x := PS.normalize(it, txt.to_float())
					e.text = PS.format(it, x)
					s.set_value_no_signal(x)
					_changed(idx, x, false)
				else:
					e.text = PS.format(it, _rows[idx].value)
			e.text_submitted.connect(func(_t): commit.call())
			e.focus_exited.connect(commit)
			line.add_child(s)
			line.add_child(e)
			v.add_child(line)
			row.controls = [s, e]
			row.set_shown = func(x: float):
				s.set_value_no_signal(x)
				if not e.has_focus():
					e.text = PS.format(it, x)

	var reset := Style.icon_button("rotate-ccw", "Reset %s to default (%s)" % [name.text.to_lower(), _shown(it, float(it.get("default", 0)))], func(): _reset(idx), "", "", 16)
	reset.custom_minimum_size = Vector2(32, 32)
	reset.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(reset)
	row.reset = reset
	if help != "":
		var h := Style.label(help, "Small", true)
		h.custom_minimum_size.x = 260
		v.add_child(h)
	var lock := Style.label(LOCKED_NOTE, "Small", true)
	lock.custom_minimum_size.x = 260
	lock.visible = false
	v.add_child(lock)
	row.lock_note = lock
	row.set_shown.call(row.value)
	_update_reset(idx)
	return v


func _slider_step(it: Dictionary) -> float:
	var st := float(it.get("step", 0))
	if it.get("type") == "int":
		return maxf(1.0, roundf(st))
	return st if st > 0 else 0.0001


## The value as a person reads it (option names, On/Off).
func _shown(it: Dictionary, x: float) -> String:
	match str(it.get("type", "")):
		"bool":
			return "on" if x >= 0.5 else "off"
		"choice":
			var opts: Array = it.get("options", [])
			var i := int(x)
			return str(opts[i]) if i >= 0 and i < opts.size() else str(i)
	return PS.format(it, x)


# ------------------------------------------------------------------ saving
func _changed(idx: int, x: float, debounce: bool) -> void:
	var row: Dictionary = _rows[idx]
	if not _editable(row.item):
		row.set_shown.call(row.value)
		return
	row.value = PS.normalize(row.item, x)
	_update_reset(idx)
	if not debounce:
		_save(idx)
		return
	var t: Timer = _pending.get(idx)
	if t == null:
		t = Timer.new()
		t.one_shot = true
		t.wait_time = DEBOUNCE
		t.timeout.connect(func(): _save(idx))
		add_child(t)
		_pending[idx] = t
	t.start()


func _save(idx: int) -> void:
	if _pending.has(idx):
		var t: Timer = _pending[idx]
		_pending.erase(idx)
		if is_instance_valid(t):
			t.queue_free()
	var row: Dictionary = _rows[idx]
	var it: Dictionary = row.item
	if not _editable(it):
		return
	var err := PS.write(_ini, str(it.section), str(it.key), PS.format(it, row.value))
	if err != "":
		App.notify(err, "error")
	else:
		_seen = _disk_text()


func _reset(idx: int) -> void:
	var row: Dictionary = _rows[idx]
	var d := PS.normalize(row.item, float(row.item.get("default", 0)))
	row.set_shown.call(d)
	_changed(idx, d, false)
	# Keep keyboard focus somewhere sensible once the reset button hides itself.
	if row.controls.size() > 0 and row.reset.has_focus():
		row.controls[0].grab_focus()


func _update_reset(idx: int) -> void:
	var row: Dictionary = _rows[idx]
	var at_default: bool = is_equal_approx(row.value, PS.normalize(row.item, float(row.item.get("default", 0))))
	var b: Button = row.reset
	b.disabled = at_default or not _editable(row.item)
	b.modulate.a = 0.0 if b.disabled else 1.0
	b.focus_mode = Control.FOCUS_NONE if b.disabled else Control.FOCUS_ALL
	b.mouse_default_cursor_shape = Control.CURSOR_ARROW if b.disabled else Control.CURSOR_POINTING_HAND


## The game re-reads this file while running (live_reload); without that, nothing is live.
func _live(it: Dictionary) -> bool:
	return bool(schema.get("live_reload", false)) and bool(it.get("live", false))


func _editable(it: Dictionary) -> bool:
	return patch_on and (_live(it) or not _running())


func _apply_lock() -> void:
	var running := _running()
	var title: String = App.game(game_id).get("title", "The game")
	if not patch_on:
		_banner.text = "Turn the patch on to change these. They're saved in the game folder, which the patch adds."
	elif running:
		_banner.text = "%s is running. Changes apply in the game right away, except where noted." % title
	else:
		_banner.text = "Changes are saved as you make them."
	for i in _rows.size():
		var row: Dictionary = _rows[i]
		var ed := _editable(row.item)
		for c in row.controls:
			if c is BaseButton:
				c.disabled = not ed
			elif c is LineEdit:
				c.editable = ed
			elif c is Slider:
				c.editable = ed
			c.focus_mode = Control.FOCUS_ALL if ed else Control.FOCUS_NONE
			c.modulate.a = 1.0 if ed else 0.5
		row.lock_note.visible = patch_on and running and not _live(row.item)
		_update_reset(i)


func _disk_text() -> String:
	return FileAccess.get_file_as_string(_ini) if FileAccess.file_exists(_ini) else ""


## Compares contents (the file is small; modification times only have whole seconds).
func _check_disk() -> void:
	var text := _disk_text()
	if text == _seen:
		return
	_seen = text
	var data := PS.parse(text)
	for i in _rows.size():
		if _pending.has(i):
			continue
		var row: Dictionary = _rows[i]
		var x := PS.value_of(data, row.item)
		if not is_equal_approx(x, row.value):
			row.value = x
			row.set_shown.call(x)
			_update_reset(i)
