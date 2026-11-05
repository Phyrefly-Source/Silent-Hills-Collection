class_name Style
extends RefCounted
## The launcher's (and the companion app's) design system in one place:
## tokens, fonts, icons, the Theme, and a few shared pieces.
## The decisions behind it are written down in docs/design.md; the numbers
## follow the UI checklist in that file (contrast >= 4.5:1 for text and 3:1
## for component borders and focus, checked by tests/contrast.gd).

# ------------------------------------------------------------------ colour
# Neutrals: OKLCH lightness steps with a slight warm tint (hue 70, chroma
# 0.006), each with one job. Values from oklch() below, written out so they
# are constants.
const BG := Color8(12, 10, 8)            # L .145  app background
const SURFACE := Color8(19, 17, 15)      # L .18   panels, cards
const RAISED := Color8(27, 25, 22)       # L .215  modals, menus, popovers
const HOVER := Color8(36, 33, 31)        # L .25   element hover / pressed
const LINE := Color8(48, 45, 43)         # L .30   decorative separators only
const BORDER := Color8(112, 108, 104)    # L .52   borders that mark a control (>= 3:1)
const INK := Color8(238, 234, 231)       # L .94   primary text, solid fills
const INK_2 := Color8(192, 189, 186)     # L .80   secondary text
const INK_3 := Color8(155, 152, 148)     # L .68   tertiary text (>= 5.5:1 everywhere)
const DISABLED := Color8(96, 93, 90)     # L .48   disabled text (exempt from contrast)
const PANEL := Color(0.075, 0.067, 0.059, 0.94)   # SURFACE over art, nearly opaque

# One accent (rust, hue 32) for actions and status; the games' own accents
# are derived the same way at runtime (accent_text / accent_fill).
const ACCENT := Color8(174, 63, 44)      # solid fill, L .52 (INK on it: 4.9:1)
const ACCENT_TEXT := Color8(234, 133, 107)
const FOCUS := Color8(234, 188, 110)     # focus ring: a fog-lamp amber, 10:1
const OK := Color8(147, 199, 148)
const DANGER := Color8(244, 122, 121)

# ------------------------------------------------------------------ space, shape, motion
const SPACE_XS := 4
const SPACE_S := 8
const SPACE_M := 12
const SPACE_L := 16
const SPACE_XL := 24
const SPACE_2XL := 32
const SPACE_3XL := 48
const SPACE_4XL := 64
const RADIUS := 4            # one radius for every control and card
const TARGET := 40           # desktop control height (>= 24 px, WCAG 2.5.8)
const TARGET_TOUCH := 48     # phone (Material 48 dp)

const DUR_MICRO := 0.15      # hover, press, small reveals
const DUR_UI := 0.25         # menus, toasts, sheets
const DUR_PAGE := 0.4        # rare page-level changes (backgrounds)

static var serif_light: Font
static var serif: Font
static var serif_italic: Font
static var sans: Font
static var sans_medium: Font
static var sans_semibold: Font
static var sans_light: Font      # kept for old callers: now the regular weight
static var numeric: Font         # tabular figures, for times and counts
static var _icons := {}
static var touch := false        # the companion app: 48 dp targets


static func target() -> int:
	return TARGET_TOUCH if touch else TARGET
static var _icon_svgs := {}


# ------------------------------------------------------------------ OKLCH
## OKLCH (L 0..1, C, hue degrees) to sRGB.
static func oklch(l: float, c: float, h: float, alpha: float = 1.0) -> Color:
	var a := c * cos(deg_to_rad(h))
	var b := c * sin(deg_to_rad(h))
	var l_ := l + 0.3963377774 * a + 0.2158037573 * b
	var m_ := l - 0.1055613458 * a - 0.0638541728 * b
	var s_ := l - 0.0894841775 * a - 1.2914855480 * b
	var L := l_ * l_ * l_
	var M := m_ * m_ * m_
	var S := s_ * s_ * s_
	var r := 4.0767416621 * L - 3.3077115913 * M + 0.2309699292 * S
	var g := -1.2684380046 * L + 2.6097574011 * M - 0.3413193965 * S
	var bl := -0.0041960863 * L - 0.7034186147 * M + 1.7076147010 * S
	return Color(_enc(r), _enc(g), _enc(bl), alpha)


static func _enc(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return 12.92 * x if x <= 0.0031308 else 1.055 * pow(x, 1.0 / 2.4) - 0.055


static func _dec(x: float) -> float:
	return x / 12.92 if x <= 0.04045 else pow((x + 0.055) / 1.055, 2.4)


## sRGB to OKLCH: Vector3(L, C, h).
static func to_oklch(c: Color) -> Vector3:
	var r := _dec(c.r)
	var g := _dec(c.g)
	var b := _dec(c.b)
	var l := pow(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b, 1.0 / 3.0)
	var m := pow(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b, 1.0 / 3.0)
	var s := pow(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b, 1.0 / 3.0)
	var L := 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
	var A := 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
	var B := 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
	return Vector3(L, sqrt(A * A + B * B), fposmod(rad_to_deg(atan2(B, A)), 360.0))


## WCAG 2 contrast ratio of two opaque colours.
static func contrast(a: Color, b: Color) -> float:
	var la := 0.2126 * _dec(a.r) + 0.7152 * _dec(a.g) + 0.0722 * _dec(a.b)
	var lb := 0.2126 * _dec(b.r) + 0.7152 * _dec(b.g) + 0.0722 * _dec(b.b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


## A game's accent made readable as text on the dark surfaces (>= 4.5:1).
static func accent_text(c: Color) -> Color:
	var k := to_oklch(c)
	var l := maxf(k.x, 0.70)
	var out := oklch(l, minf(k.y, 0.14), k.z)
	while contrast(out, RAISED) < 4.6 and l < 0.95:
		l += 0.02
		out = oklch(l, minf(k.y, 0.14), k.z)
	return out


## A game's accent as a solid fill that INK text stays readable on.
static func accent_fill(c: Color) -> Color:
	var k := to_oklch(c)
	var l := clampf(k.x, 0.40, 0.52)
	var out := oklch(l, minf(k.y, 0.16), k.z)
	while contrast(INK, out) < 4.6 and l > 0.25:
		l -= 0.02
		out = oklch(l, minf(k.y, 0.16), k.z)
	return out


# ------------------------------------------------------------------ fonts
static func _font(p: String) -> FontFile:
	var f: FontFile = load(p)
	f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	f.hinting = TextServer.HINTING_LIGHT
	f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
	return f


## IBM Plex Sans (latin + latin-ext), then the system's fonts for anything
## else (Japanese album titles and the like).
static func _plex(weight: int) -> Font:
	var f := _font("res://fonts/ibm-plex-sans-latin-%d-normal.woff2" % weight)
	var ext := _font("res://fonts/ibm-plex-sans-latin-ext-%d-normal.woff2" % weight)
	var sys := SystemFont.new()
	sys.font_names = PackedStringArray(["Segoe UI", "Yu Gothic UI", "Meiryo", "Noto Sans CJK JP", "Noto Sans", "Roboto", "sans-serif"])
	sys.font_weight = weight
	f.fallbacks = [ext, sys]
	return f


static func _serif(p: String) -> Font:
	var f := _font(p)
	var sys := SystemFont.new()
	sys.font_names = PackedStringArray(["Georgia", "Yu Mincho", "Noto Serif CJK JP", "Noto Serif", "serif"])
	f.fallbacks = [sys]
	return f


static func _fonts() -> void:
	if sans != null:
		return
	serif_light = _serif("res://fonts/CormorantGaramond-Light.ttf")
	serif = _serif("res://fonts/CormorantGaramond-Regular.ttf")
	serif_italic = _serif("res://fonts/CormorantGaramond-LightItalic.ttf")
	sans = _plex(400)
	sans_medium = _plex(500)
	sans_semibold = _plex(600)
	sans_light = sans
	var num := FontVariation.new()
	num.base_font = sans
	num.opentype_features = {"tnum": 1}
	numeric = num


static func _tracked(base: Font, px: int) -> FontVariation:
	var v := FontVariation.new()
	v.base_font = base
	v.spacing_glyph = px
	return v


# ------------------------------------------------------------------ icons (Lucide, ISC)
## A Lucide icon as a texture, drawn at `size` px (twice that for sharpness on
## scaled screens; Button's icon_max_width keeps it at `size`).
static func icon(name: String, size: int = 20, color: Color = INK) -> Texture2D:
	var key := "%s@%d#%s" % [name, size, color.to_html()]
	if _icons.has(key):
		return _icons[key]
	if _icon_svgs.is_empty():
		_icon_svgs = JSON.parse_string(FileAccess.get_file_as_string("res://icons/icons.json"))
	var svg: String = _icon_svgs.get(name, _icon_svgs.get("circle-alert", ""))
	svg = svg.replace("currentColor", "#" + color.to_html(false))
	var img := Image.new()
	img.load_svg_from_string(svg, size * 2.0 / 24.0)
	var tex := ImageTexture.create_from_image(img)
	_icons[key] = tex
	return tex


# ------------------------------------------------------------------ motion
## Reduce motion (Settings): movement becomes a fade or nothing.
static func reduce_motion() -> bool:
	var app = Engine.get_main_loop().root.get_node_or_null("App") if Engine.get_main_loop() is SceneTree else null
	return app != null and bool(app.settings.get("reduce_motion", false))


## Duration to use: 0 when motion is reduced and the change moves things.
static func dur(seconds: float, moves: bool = true) -> float:
	return 0.0 if moves and reduce_motion() else seconds


## A tween with the house easing (ease-out for things arriving).
static func tween(node: Node) -> Tween:
	return node.create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)


# ------------------------------------------------------------------ theme
static func build() -> Theme:
	_fonts()
	var t := Theme.new()
	t.default_font = sans
	t.default_font_size = 16

	# Type: serif display tier (64 / 40 / 26), sans UI tier (16 / 14 / 12).
	t.set_color("font_color", "Label", INK)
	t.set_color("font_outline_color", "Label", Color(0, 0, 0, 0))
	_variation(t, "Title", "Label", serif_light, 64, INK)
	_variation(t, "H1", "Label", serif_light, 40, INK)
	_variation(t, "H2", "Label", serif, 26, INK)
	_variation(t, "Body", "Label", sans, 16, INK_2)
	_variation(t, "Meta", "Label", sans, 14, INK_2)
	_variation(t, "Small", "Label", sans, 14, INK_3)
	_variation(t, "Caps", "Label", _tracked(sans_semibold, 1), 12, INK_3)
	_variation(t, "Num", "Label", numeric, 14, INK_2)
	t.set_constant("line_spacing", "Body", 6)    # ~1.5 at 16 px
	t.set_constant("line_spacing", "Meta", 4)
	t.set_constant("line_spacing", "Small", 4)

	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.border_color = FOCUS
	focus.set_border_width_all(2)
	focus.set_corner_radius_all(RADIUS + 2)
	focus.set_expand_margin_all(3)
	focus.anti_aliasing = true

	# Tertiary: text only. The default for every Button.
	var text_btn := _box(Color(0, 0, 0, 0), RADIUS, SPACE_S, SPACE_S)
	var text_hover := _box(HOVER, RADIUS, SPACE_S, SPACE_S)
	for st in ["normal", "disabled"]:
		t.set_stylebox(st, "Button", text_btn)
	t.set_stylebox("hover", "Button", text_hover)
	t.set_stylebox("pressed", "Button", _box(Color(HOVER, 1).lightened(0.05), RADIUS, SPACE_S, SPACE_S))
	t.set_stylebox("hover_pressed", "Button", text_hover)
	t.set_stylebox("focus", "Button", focus)
	t.set_color("font_color", "Button", INK_2)
	t.set_color("font_hover_color", "Button", INK)
	t.set_color("font_pressed_color", "Button", INK)
	t.set_color("font_hover_pressed_color", "Button", INK)
	t.set_color("font_focus_color", "Button", INK)
	t.set_color("font_disabled_color", "Button", DISABLED)
	t.set_color("icon_normal_color", "Button", INK_2)
	t.set_color("icon_hover_color", "Button", INK)
	t.set_color("icon_pressed_color", "Button", INK)
	t.set_color("icon_focus_color", "Button", INK)
	t.set_color("icon_disabled_color", "Button", DISABLED)
	t.set_font("font", "Button", sans_medium)
	t.set_font_size("font_size", "Button", 14)
	t.set_constant("h_separation", "Button", SPACE_S)
	t.set_constant("icon_max_width", "Button", 20)

	# Primary: the one solid button in a view.
	t.add_type("Primary")
	t.set_type_variation("Primary", "Button")
	t.set_stylebox("normal", "Primary", _box(INK, RADIUS, SPACE_XL, SPACE_M))
	t.set_stylebox("hover", "Primary", _box(Color.WHITE, RADIUS, SPACE_XL, SPACE_M))
	t.set_stylebox("hover_pressed", "Primary", _box(Color.WHITE, RADIUS, SPACE_XL, SPACE_M))
	t.set_stylebox("pressed", "Primary", _box(INK_2, RADIUS, SPACE_XL, SPACE_M))
	t.set_stylebox("disabled", "Primary", _box(HOVER, RADIUS, SPACE_XL, SPACE_M))
	t.set_stylebox("focus", "Primary", focus)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color",
			"icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_focus_color"]:
		t.set_color(c, "Primary", BG)
	t.set_color("font_disabled_color", "Primary", DISABLED)
	t.set_font("font", "Primary", sans_semibold)
	t.set_font_size("font_size", "Primary", 16)

	# Secondary ("Ghost"): outlined, the border at 3:1.
	t.add_type("Ghost")
	t.set_type_variation("Ghost", "Button")
	t.set_stylebox("normal", "Ghost", _outline(BORDER))
	t.set_stylebox("hover", "Ghost", _outline(INK_3, HOVER))
	t.set_stylebox("hover_pressed", "Ghost", _outline(INK_3, HOVER))
	t.set_stylebox("pressed", "Ghost", _outline(INK_2, HOVER.lightened(0.05)))
	t.set_stylebox("disabled", "Ghost", _outline(LINE))
	t.set_stylebox("focus", "Ghost", focus)
	t.set_color("font_color", "Ghost", INK)
	t.set_color("icon_normal_color", "Ghost", INK)
	t.set_font_size("font_size", "Ghost", 14)

	# Icon: a square icon-only button (needs an accessible name).
	t.add_type("Icon")
	t.set_type_variation("Icon", "Button")
	var ib := _box(Color(0, 0, 0, 0), RADIUS, SPACE_S, SPACE_S)
	t.set_stylebox("normal", "Icon", ib)
	t.set_stylebox("disabled", "Icon", ib)

	# Nav: top-level sections.
	t.add_type("Nav")
	t.set_type_variation("Nav", "Button")
	t.set_font("font", "Nav", _tracked(sans_semibold, 1))
	t.set_font_size("font_size", "Nav", 13)
	t.set_color("font_color", "Nav", INK_3)
	t.set_color("font_pressed_color", "Nav", INK)
	t.set_color("font_hover_color", "Nav", INK)
	t.set_color("font_hover_pressed_color", "Nav", INK)
	t.set_color("icon_normal_color", "Nav", INK_3)
	t.set_color("icon_pressed_color", "Nav", INK)
	var nav_on := StyleBoxFlat.new()
	nav_on.bg_color = Color(0, 0, 0, 0)
	nav_on.border_color = INK
	nav_on.border_width_bottom = 2
	nav_on.content_margin_left = SPACE_S
	nav_on.content_margin_right = SPACE_S
	nav_on.content_margin_top = SPACE_S
	nav_on.content_margin_bottom = SPACE_S
	t.set_stylebox("pressed", "Nav", nav_on)
	t.set_stylebox("hover_pressed", "Nav", nav_on)
	t.set_stylebox("hover", "Nav", _box(Color(0, 0, 0, 0), RADIUS, SPACE_S, SPACE_S))

	# Inputs
	var field := _box(RAISED, RADIUS, SPACE_M, 10)
	field.border_color = BORDER
	field.set_border_width_all(1)
	var field_focus := field.duplicate()
	field_focus.border_color = FOCUS
	field_focus.set_border_width_all(2)
	var field_hover := field.duplicate()
	field_hover.border_color = INK_3
	t.set_stylebox("normal", "LineEdit", field)
	t.set_stylebox("focus", "LineEdit", field_focus)
	t.set_stylebox("read_only", "LineEdit", _box(SURFACE, RADIUS, SPACE_M, 10))
	t.set_color("font_color", "LineEdit", INK)
	t.set_color("font_placeholder_color", "LineEdit", INK_3)
	t.set_color("caret_color", "LineEdit", FOCUS)
	t.set_color("selection_color", "LineEdit", Color(ACCENT, 0.55))
	t.set_font_size("font_size", "LineEdit", 16)
	t.set_stylebox("normal", "OptionButton", field)
	t.set_stylebox("hover", "OptionButton", field_hover)
	t.set_stylebox("pressed", "OptionButton", field_hover)
	t.set_stylebox("focus", "OptionButton", field_focus)
	t.set_color("font_color", "OptionButton", INK)
	t.set_font_size("font_size", "OptionButton", 15)

	# Menus, tooltips: raised surfaces with the one shadow.
	var popup := _raised(SPACE_S, SPACE_S)
	t.set_stylebox("panel", "PopupMenu", popup)
	t.set_stylebox("hover", "PopupMenu", _box(HOVER, RADIUS, SPACE_M, SPACE_S))
	t.set_color("font_color", "PopupMenu", INK_2)
	t.set_color("font_hover_color", "PopupMenu", INK)
	t.set_font_size("font_size", "PopupMenu", 15)
	t.set_constant("v_separation", "PopupMenu", SPACE_M)
	t.set_stylebox("panel", "TooltipPanel", _raised(SPACE_M, SPACE_S))
	t.set_color("font_color", "TooltipLabel", INK)
	t.set_font_size("font_size", "TooltipLabel", 14)

	# Check boxes: drawn boxes with Lucide's check, the same everywhere.
	t.set_color("font_color", "CheckBox", INK_2)
	t.set_color("font_hover_color", "CheckBox", INK)
	t.set_color("font_pressed_color", "CheckBox", INK)
	t.set_color("font_hover_pressed_color", "CheckBox", INK)
	t.set_font_size("font_size", "CheckBox", 15)
	for st in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		t.set_stylebox(st, "CheckBox", _box(Color(0, 0, 0, 0), RADIUS, SPACE_XS, SPACE_XS))
	t.set_stylebox("focus", "CheckBox", focus)
	t.set_icon("unchecked", "CheckBox", _check_icon(false))
	t.set_icon("checked", "CheckBox", _check_icon(true))
	t.set_icon("unchecked_disabled", "CheckBox", _check_icon(false))
	t.set_icon("checked_disabled", "CheckBox", _check_icon(true))
	t.set_constant("h_separation", "CheckBox", SPACE_S)

	# Sliders and progress
	t.set_stylebox("slider", "HSlider", _box(HOVER, 2, 0, 2))
	t.set_stylebox("grabber_area", "HSlider", _box(INK_2, 2, 0, 2))
	t.set_stylebox("grabber_area_highlight", "HSlider", _box(INK, 2, 0, 2))
	t.set_stylebox("focus", "HSlider", focus)
	t.set_icon("grabber", "HSlider", _dot(14, INK))
	t.set_icon("grabber_highlight", "HSlider", _dot(16, Color.WHITE))
	t.set_stylebox("background", "ProgressBar", _box(HOVER, 2, 0, 2))
	t.set_stylebox("fill", "ProgressBar", _box(INK, 2, 0, 2))
	t.set_font_size("font_size", "ProgressBar", 12)

	# Scrollbars: thin, visible on hover.
	for sb in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", sb, _box(Color(0, 0, 0, 0), 3, 0, 0))
		t.set_stylebox("grabber", sb, _box(LINE, 3, 3, 3))
		t.set_stylebox("grabber_highlight", sb, _box(BORDER, 3, 3, 3))
		t.set_stylebox("grabber_pressed", sb, _box(INK_3, 3, 3, 3))

	t.set_stylebox("panel", "PanelContainer", _box(PANEL, 0, 0, 0))
	t.set_stylebox("panel", "ItemList", StyleBoxEmpty.new())
	t.set_constant("separation", "HBoxContainer", SPACE_M)
	t.set_constant("separation", "VBoxContainer", SPACE_M)
	return t


static func _variation(t: Theme, name: String, base: String, font: Font, size: int, color: Color) -> void:
	t.add_type(name)
	t.set_type_variation(name, base)
	t.set_font("font", name, font)
	t.set_font_size("font_size", name, size)
	t.set_color("font_color", name, color)


static func _box(c: Color, radius: int, mx: int, my: int) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = c
	b.set_corner_radius_all(radius)
	b.content_margin_left = mx
	b.content_margin_right = mx
	b.content_margin_top = my
	b.content_margin_bottom = my
	b.anti_aliasing = true
	return b


static func _outline(border: Color, fill: Color = Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var b := _box(fill, RADIUS, SPACE_L + 2, 10)
	b.border_color = border
	b.set_border_width_all(1)
	return b


## The one raised surface: menus, popovers, modals, toasts.
static func _raised(mx: int, my: int) -> StyleBoxFlat:
	var b := _box(RAISED, RADIUS + 2, mx, my)
	b.border_color = LINE
	b.set_border_width_all(1)
	b.shadow_color = Color(0, 0, 0, 0.5)
	b.shadow_size = 24
	b.shadow_offset = Vector2(0, 8)
	return b


static func raised_box(mx: int = SPACE_XL, my: int = SPACE_XL) -> StyleBoxFlat:
	return _raised(mx, my)


static func _dot(size: int, c: Color) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var r := size / 2.0
	for y in size:
		for x in size:
			var d := Vector2(x + 0.5 - r, y + 0.5 - r).length()
			img.set_pixel(x, y, Color(c, clampf(r - d, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)


static func _check_icon(on: bool) -> ImageTexture:
	var s := 20
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	for y in s:
		for x in s:
			var edge := x < 2 or y < 2 or x >= s - 2 or y >= s - 2
			if on:
				img.set_pixel(x, y, INK)
			elif edge:
				img.set_pixel(x, y, BORDER)
	if on:
		var mark := Image.new()
		var svg: String = JSON.parse_string(FileAccess.get_file_as_string("res://icons/icons.json")).get("check", "")
		mark.load_svg_from_string(svg.replace("currentColor", "#" + BG.to_html(false)).replace("stroke-width=\"2\"", "stroke-width=\"3\""), 16.0 / 24.0)
		mark.convert(Image.FORMAT_RGBA8)
		img.blend_rect(mark, Rect2i(0, 0, 16, 16), Vector2i(2, 2))
	return ImageTexture.create_from_image(img)


# ------------------------------------------------------------------ building helpers
static func label(text: String, variation: String = "", wrap: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	if variation != "":
		l.theme_type_variation = variation
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


static func button(text: String, variation: String = "", cb: Callable = Callable()) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_ALL
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if variation != "":
		b.theme_type_variation = variation
	if variation in ["Primary", "Ghost"] or touch:
		b.custom_minimum_size.y = target()
	if cb.is_valid():
		b.pressed.connect(cb)
	return b


## A button with a Lucide icon (and text, or none). Icon-only buttons get
## `name` as their tooltip and accessible name.
static func icon_button(icon_name: String, name: String, cb: Callable = Callable(), text: String = "", variation: String = "", size: int = 20) -> Button:
	var b := button(text, variation if variation != "" else ("Icon" if text == "" else ""), cb)
	b.icon = icon(icon_name, size, Color.WHITE)
	b.add_theme_constant_override("icon_max_width", size)
	b.accessibility_name = name
	if text == "":
		b.tooltip_text = name
		b.custom_minimum_size = Vector2(target(), target())
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return b


static func hbox(sep: int = SPACE_M) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


static func vbox(sep: int = SPACE_M) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


static func spacer(h: int = 0, w: int = 0) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(w, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


static func margin(c: Control, l: int, t: int, r: int, b: int) -> MarginContainer:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", l)
	m.add_theme_constant_override("margin_top", t)
	m.add_theme_constant_override("margin_right", r)
	m.add_theme_constant_override("margin_bottom", b)
	m.add_child(c)
	return m


static func color_hex(s: String, fallback: Color = ACCENT) -> Color:
	return Color.from_string(s, fallback) if s != "" else fallback


# ------------------------------------------------------------------ shared pieces
## A static placeholder block for content that is loading (no shimmer).
static func skeleton(size: Vector2, radius: int = RADIUS) -> Panel:
	var p := Panel.new()
	p.custom_minimum_size = size
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel", _box(SURFACE.lerp(HOVER, 0.6), radius, 0, 0))
	return p


## Skeleton rows standing in for a list while it loads.
static func skeleton_list(rows: int, height: int = 48, width: float = 0.0) -> VBoxContainer:
	var v := vbox(SPACE_S)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in rows:
		var s := skeleton(Vector2(width, height))
		s.size_flags_horizontal = Control.SIZE_EXPAND_FILL if width == 0.0 else Control.SIZE_SHRINK_BEGIN
		s.modulate.a = 1.0 - i * 0.08
		v.add_child(s)
	return v


## Skeleton tiles standing in for a grid while it loads.
static func skeleton_grid(count: int, columns: int, tile: Vector2, sep: int = SPACE_M) -> GridContainer:
	var g := GridContainer.new()
	g.columns = columns
	g.add_theme_constant_override("h_separation", sep)
	g.add_theme_constant_override("v_separation", sep)
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in count:
		g.add_child(skeleton(tile))
	return g


## An empty state: what belongs here, and one thing to do about it.
static func empty_state(icon_name: String, title: String, body: String, action: String = "", cb: Callable = Callable()) -> VBoxContainer:
	var v := vbox(SPACE_S)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var ic := TextureRect.new()
	ic.texture = icon(icon_name, 28, INK_3)
	ic.custom_minimum_size = Vector2(28, 28)
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	ic.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	v.add_child(ic)
	var t := label(title, "")
	t.add_theme_font_override("font", sans_semibold)
	t.add_theme_font_size_override("font_size", 16)
	v.add_child(t)
	var b := label(body, "Meta", true)
	b.custom_minimum_size.x = 260
	v.add_child(b)
	if action != "" and cb.is_valid():
		var btn := button(action, "Ghost", cb)
		btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		v.add_child(Style.margin(btn, 0, SPACE_S, 0, 0))
	return v


## A spinner for one module that is busy (1-10 s). With reduced motion it
## stays still.
static func spinner(size: int = 20) -> TextureRect:
	var r := TextureRect.new()
	r.texture = icon("loader-circle", size, INK_3)
	r.custom_minimum_size = Vector2(size, size)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.pivot_offset = Vector2(size, size) / 2.0
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not reduce_motion():
		r.ready.connect(func():
			var tw := r.create_tween().set_loops()
			tw.tween_property(r, "rotation", TAU, 0.9).from(0.0))
	return r


## A dark gradient laid under text that sits on artwork, so the text keeps
## its contrast whatever the picture is. `from` is where it is darkest.
static func scrim(from: int = SIDE_BOTTOM, strength: float = 0.85) -> TextureRect:
	var g := Gradient.new()
	g.set_color(0, Color(BG, strength))
	g.set_color(1, Color(BG, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.width = 64
	gt.height = 64
	match from:
		SIDE_BOTTOM:
			gt.fill_from = Vector2(0, 1)
			gt.fill_to = Vector2(0, 0)
		SIDE_LEFT:
			gt.fill_from = Vector2(0, 0)
			gt.fill_to = Vector2(1, 0)
		SIDE_TOP:
			gt.fill_from = Vector2(0, 0)
			gt.fill_to = Vector2(0, 1)
		_:
			gt.fill_from = Vector2(1, 0)
			gt.fill_to = Vector2(0, 0)
	var r := TextureRect.new()
	r.texture = gt
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r
