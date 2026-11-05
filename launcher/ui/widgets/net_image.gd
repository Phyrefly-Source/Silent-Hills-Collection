extends TextureRect
## A picture from a URL or a local file, loaded off the main thread and cached.

static var _mem := {}

var source := ""
var _key := ""
var max_px := 0   # when set, pictures are scaled down to at most this width
var headers := PackedStringArray()   # sent with the request (the companion app's PC token)


func _init(src: String = "", min_size: Vector2 = Vector2(40, 40)) -> void:
	custom_minimum_size = min_size
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if src != "":
		load_source(src)


func load_source(src: String) -> void:
	source = src
	var key := src + ("@%d" % max_px if max_px > 0 else "")
	_key = key
	if _mem.has(key):
		texture = _mem[key]
		return
	if src.begins_with("http"):
		Net.get_file(src, func(path: String):
			if path != "" and is_instance_valid(self) and _key == key:
				_decode(path, key), "", headers)
	else:
		_decode(src, key)


func _decode(path: String, key: String) -> void:
	# The work runs on another thread and may outlive this picture (lists are
	# rebuilt all the time), so it must not touch anything of `self`.
	var mp := max_px
	App.run(func(): return Pictures.load_scaled(path, mp),
	func(img):
		if img == null or not is_instance_valid(self):
			return
		var tex := ImageTexture.create_from_image(img)
		_mem[key] = tex
		if _key == key:
			texture = tex)
