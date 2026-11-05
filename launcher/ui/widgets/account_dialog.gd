extends VBoxContainer
## Make a profile, or sign in to one, on this PC. Shown in a modal.
## mode: "create" or "sign_in". Everything is kept on this PC.

var main: Control
var modal: Control
var mode := "create"
var first_run := false      # the welcome on a PC with no profiles yet

var _name: LineEdit
var _pass: LineEdit
var _confirm: LineEdit
var _remember: CheckBox
var _error: Label
var _go: Button
var _picked := ""


func _ready() -> void:
	add_theme_constant_override("separation", Style.SPACE_M)
	_build()


func _build() -> void:
	for c in get_children():
		c.queue_free()
	var acc = App.svc("accounts")
	var creating := mode == "create"
	add_child(Style.label("Welcome to Silent Hills" if first_run else ("Make a profile" if creating else "Sign in"), "H1"))
	var intro := "A profile keeps your play time, achievements and favourite games. It's kept on this PC; nothing is sent anywhere." if creating \
		else "Choose your profile and type its password."
	add_child(Style.label(intro, "Meta", true))

	if not creating:
		var list := HFlowContainer.new()
		list.add_theme_constant_override("h_separation", Style.SPACE_S)
		list.add_theme_constant_override("v_separation", Style.SPACE_S)
		var group := ButtonGroup.new()
		for p in acc.profiles():
			var b := Button.new()
			b.toggle_mode = true
			b.button_group = group
			b.text = str(p.name)
			b.icon = acc.avatar_texture(32, p.key)
			b.add_theme_constant_override("icon_max_width", 32)
			b.custom_minimum_size.y = 48
			b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			var key: String = p.key
			b.pressed.connect(func():
				_picked = key
				_name.text = str(p.name)
				_pass.grab_focus())
			list.add_child(b)
			if _picked == "" or _picked == key:
				_picked = key
				b.button_pressed = true
		add_child(list)

	_name = LineEdit.new()
	_name.placeholder_text = "Username"
	_name.max_length = 24
	_name.custom_minimum_size.y = Style.TARGET
	_name.visible = creating
	if not creating and _picked != "":
		for p in acc.profiles():
			if p.key == _picked:
				_name.text = p.name
	add_child(_name)
	_pass = LineEdit.new()
	_pass.placeholder_text = "Password"
	_pass.secret = true
	_pass.custom_minimum_size.y = Style.TARGET
	add_child(_pass)
	_confirm = LineEdit.new()
	_confirm.placeholder_text = "Password again"
	_confirm.secret = true
	_confirm.custom_minimum_size.y = Style.TARGET
	_confirm.visible = creating
	add_child(_confirm)
	for le in [_name, _pass, _confirm]:
		le.text_submitted.connect(func(_t): _submit())
		le.text_changed.connect(func(_t): _error.text = "")
	_remember = CheckBox.new()
	_remember.text = "Keep me signed in on this PC"
	_remember.button_pressed = true
	add_child(_remember)
	_error = Style.label("", "Small", true)
	_error.add_theme_color_override("font_color", Style.DANGER)
	add_child(_error)

	var row := Style.hbox(Style.SPACE_S)
	_go = Style.button("Make my profile" if creating else "Sign in", "Primary", _submit)
	row.add_child(_go)
	if creating and acc.has_profiles():
		row.add_child(Style.button("Sign in instead", "", func():
			mode = "sign_in"
			_build()))
	elif not creating:
		row.add_child(Style.button("Make a new profile", "", func():
			mode = "create"
			_build()))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(sp)
	row.add_child(Style.button("Continue as guest", "", func():
		App.set_setting("profile_prompt_skipped", true)
		_close()))
	add_child(row)
	if creating:
		add_child(Style.label("Passwords are stored as salted hashes, never as text. There's no way to recover a forgotten one yet, so keep it somewhere safe.", "Small", true))
	(func():
		if is_instance_valid(_name):
			(_name if creating else _pass).grab_focus()).call_deferred()


func _submit() -> void:
	if _go.disabled:
		return
	var acc = App.svc("accounts")
	if mode == "create":
		var why: String = acc.check_new(_name.text, _pass.text, _confirm.text)
		if why != "":
			_error.text = why
			return
	elif _picked == "":
		_error.text = "Choose your profile first."
		return
	_go.disabled = true
	_go.text = "One moment…"
	var done := func(err: String):
		if not is_instance_valid(self):
			return
		if err != "":
			_error.text = err
			_go.disabled = false
			_go.text = "Make my profile" if mode == "create" else "Sign in"
			_pass.select_all()
			_pass.grab_focus()
			return
		App.notify("Signed in as %s." % acc.display_name(), "ok")
		_close()
	if mode == "create":
		acc.create(_name.text, _pass.text, _remember.button_pressed, done)
	else:
		acc.sign_in(_name.text, _pass.text, _remember.button_pressed, done)


func _close() -> void:
	if is_instance_valid(modal):
		modal.queue_free()
