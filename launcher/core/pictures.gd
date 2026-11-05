class_name Pictures
extends RefCounted
## Picture loading that's safe on worker threads (no autoloads, no nodes).


## Loads a picture whatever its file name says, by looking at its first bytes
## (downloads are often saved without a proper extension). null if unreadable.
static func read(path: String) -> Image:
	var b := FileAccess.get_file_as_bytes(path)
	if b.size() < 12:
		return null
	var img := Image.new()
	var err := ERR_FILE_UNRECOGNIZED
	if b[0] == 0xFF and b[1] == 0xD8:
		err = img.load_jpg_from_buffer(b)
	elif b[0] == 0x89 and b[1] == 0x50:
		err = img.load_png_from_buffer(b)
	elif b.slice(0, 4).get_string_from_ascii() == "RIFF" and b.slice(8, 12).get_string_from_ascii() == "WEBP":
		err = img.load_webp_from_buffer(b)
	elif b[0] == 0x42 and b[1] == 0x4D:
		err = img.load_bmp_from_buffer(b)
	elif b.slice(0, 3).get_string_from_ascii() == "GIF":
		return null
	else:
		err = img.load(path)
	return img if err == OK and not img.is_empty() else null


## Loads and scales down to at most `max_width` (0: as is).
static func load_scaled(path: String, max_width: int) -> Image:
	var img := read(path)
	if img and max_width > 0 and img.get_width() > max_width:
		img.resize(max_width, int(img.get_height() * float(max_width) / img.get_width()), Image.INTERPOLATE_LANCZOS)
	return img
