# ui/widgets/update_banner.gd — slim bar under the top nav when a build is available.
extends PanelContainer
class_name UpdateBanner

var _u: Updater
var _title: Label
var _notes: RichTextLabel
var _bar: ProgressBar
var _update_btn: Button
var _later_btn: Button
var _skip_btn: Button
var _notes_btn: Button


func _init(updater: Updater) -> void:
	_u = updater


func _ready() -> void:
	visible = false
	var v := VBoxContainer.new()
	add_child(v)
	var row := HBoxContainer.new()
	v.add_child(row)

	_title = Label.new()
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_title)

	_notes_btn = _btn(row, "What's new", func() -> void: _notes.visible = not _notes.visible)
	_update_btn = _btn(row, "Update now", _on_update)
	_later_btn = _btn(row, "Later", func() -> void: visible = false)
	_skip_btn = _btn(row, "Skip this version", func() -> void:
		_u.skip_latest()
		visible = false)

	_notes = RichTextLabel.new()
	_notes.visible = false
	_notes.fit_content = true
	_notes.bbcode_enabled = false
	v.add_child(_notes)

	_bar = ProgressBar.new()
	_bar.visible = false
	_bar.show_percentage = false
	v.add_child(_bar)

	_u.checked.connect(_on_checked)
	_u.progress.connect(_on_progress)
	_u.ready_to_apply.connect(_on_ready)
	_u.failed.connect(_on_failed)
	_u.check()


func _btn(parent: Node, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _on_checked(available: bool) -> void:
	if not available:
		return
	_title.text = "Silent Hills %s is available (you have %s)." % [_u.latest.version, _u.current_version]
	_notes.text = _u.latest.notes
	visible = true


func _on_update() -> void:
	_set_buttons(false)
	_bar.visible = true
	_bar.value = 0
	_title.text = "Downloading Silent Hills %s…" % _u.latest.version
	_u.download()


func _on_progress(done: int, total: int) -> void:
	if total > 0:
		_bar.max_value = total
		_bar.value = done
		_title.text = "Downloading Silent Hills %s… %d%%" % [_u.latest.version, done * 100 / total]


func _on_ready() -> void:
	_title.text = "Verified. Restarting to finish the update…"
	await get_tree().create_timer(0.8).timeout
	_u.apply()


func _on_failed(message: String) -> void:
	_title.text = message
	_bar.visible = false
	_set_buttons(true)
	visible = true


func _set_buttons(on: bool) -> void:
	for b in [_update_btn, _later_btn, _skip_btn, _notes_btn]:
		b.disabled = not on
