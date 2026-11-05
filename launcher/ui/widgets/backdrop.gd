extends Control
## Full-window backdrop: the game's art (cross-faded when the selection changes),
## shading so text stays readable, and the atmosphere shader on top.

const FX_MODES := {"none": 0, "mist": 1, "rain": 2, "snow": 3, "ash": 4, "embers": 5, "static": 6, "petals": 7, "flicker": 8}

var _a: TextureRect
var _b: TextureRect
var _front: TextureRect
var _fx: ColorRect
var _shade: TextureRect
var _tween: Tween
var _drift: Tween


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	_a = _art_rect()
	_b = _art_rect()
	_front = _a
	_shade = TextureRect.new()
	_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_shade.stretch_mode = TextureRect.STRETCH_SCALE
	_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shade.texture = _shade_texture()
	add_child(_shade)
	_fx = ColorRect.new()
	_fx.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = load("res://fx/atmosphere.gdshader")
	_fx.material = mat
	add_child(_fx)
	resized.connect(func():
		mat.set_shader_parameter("aspect", Vector2(size.x / max(size.y, 1.0), 1.0))
		# Art always covers the whole window: keep both layers sized to it and
		# zooming about its centre, whatever size the window becomes.
		for r in [_a, _b]:
			r.position = Vector2.ZERO
			r.size = size
			r.pivot_offset = size / 2)
	App.settings_changed.connect(_apply_settings)
	_apply_settings()


func _art_rect() -> TextureRect:
	var r := TextureRect.new()
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.modulate.a = 0.0
	add_child(r)
	return r


func _shade_texture() -> GradientTexture2D:
	# Dark on the left (where the list and text sit) and along the bottom.
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.38, 0.75, 1.0])
	g.colors = PackedColorArray([Color(0.02, 0.02, 0.025, 0.92), Color(0.02, 0.02, 0.025, 0.55), Color(0.02, 0.02, 0.025, 0.12), Color(0.02, 0.02, 0.025, 0.25)])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill_from = Vector2(0, 0.7)
	t.fill_to = Vector2(1, 0.35)
	t.width = 256
	t.height = 256
	return t


func _apply_settings() -> void:
	_fx.visible = App.settings.get("ambience", true)
	var still: bool = App.settings.get("reduce_motion", false)
	(_fx.material as ShaderMaterial).set_shader_parameter("speed", 0.0 if still else 1.0)


## Shows a texture (or nothing) with a soft cross-fade.
func show_art(tex: Texture2D, dim: float = 1.0) -> void:
	var back := _b if _front == _a else _a
	back.texture = tex
	back.modulate.a = 0.0
	move_child(back, 1)
	if _tween:
		_tween.kill()
	_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE)
	_tween.tween_property(back, "modulate:a", dim if tex else 0.0, Style.DUR_PAGE)
	_tween.tween_property(_front, "modulate:a", 0.0, Style.DUR_PAGE)
	_front = back
	_start_drift(back)


func _start_drift(r: TextureRect) -> void:
	if _drift:
		_drift.kill()
	r.pivot_offset = size / 2
	if App.settings.get("reduce_motion", false):
		r.scale = Vector2.ONE
		return
	r.scale = Vector2(1.06, 1.06)
	_drift = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_drift.tween_property(r, "scale", Vector2(1.0, 1.0), 24.0)


func set_atmosphere(fx: String, tint: Color) -> void:
	var m := _fx.material as ShaderMaterial
	m.set_shader_parameter("mode", FX_MODES.get(fx, 1))
	# Fog takes a little of the game's colour, mostly grey.
	m.set_shader_parameter("tint", Color(0.55, 0.55, 0.55).lerp(tint, 0.25))
	m.set_shader_parameter("fog_amount", 0.32 if fx != "none" else 0.0)
