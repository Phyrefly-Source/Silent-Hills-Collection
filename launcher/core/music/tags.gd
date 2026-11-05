class_name AudioTags
extends RefCounted
## Reads the tags of an audio file: title, artist, album, track and disc number,
## year, duration, and whether a cover picture is embedded. Handles ID3v2 / ID3v1
## (MP3), FLAC Vorbis comments and STREAMINFO, and Ogg Vorbis comments.
## Only the start of the file is read (plus the last 128 bytes for ID3v1).

const HEAD := 256 * 1024


static func read(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var size := f.get_length()
	var head := f.get_buffer(min(HEAD, size))
	var out := {"title": "", "artist": "", "album": "", "track": 0, "disc": 0, "year": "", "seconds": 0.0, "picture": false}
	if head.size() >= 4 and head.slice(0, 4).get_string_from_ascii() == "fLaC":
		_flac(f, out)
	elif head.size() >= 3 and head.slice(0, 3).get_string_from_ascii() == "ID3":
		var tag_size := _syncsafe(head, 6) + 10
		if tag_size > head.size():
			f.seek(0)
			head = f.get_buffer(min(tag_size + 4096, size))
		_id3v2(head, out)
		out.seconds = _mp3_seconds(head, tag_size, size)
	elif head.size() >= 4 and head.slice(0, 4).get_string_from_ascii() == "OggS":
		_ogg(head, out)
	elif path.get_extension().to_lower() == "mp3":
		out.seconds = _mp3_seconds(head, 0, size)
	if out.title == "" and size > 128:
		f.seek(size - 128)
		var v1 := f.get_buffer(128)
		if v1.slice(0, 3).get_string_from_ascii() == "TAG":
			out.title = _clean(v1.slice(3, 33).get_string_from_ascii())
			out.artist = _clean(v1.slice(33, 63).get_string_from_ascii())
			out.album = _clean(v1.slice(63, 93).get_string_from_ascii())
			out.year = _clean(v1.slice(93, 97).get_string_from_ascii())
			if v1[125] == 0 and v1[126] > 0:
				out.track = v1[126]
	f.close()
	return out


static func _clean(s: String) -> String:
	return s.replace(char(0), "").strip_edges()


static func _num(s: String) -> int:
	# "3/26" -> 3
	return s.split("/")[0].strip_edges().to_int()


# ------------------------------------------------------------------ FLAC
static func _flac(f: FileAccess, out: Dictionary) -> void:
	f.seek(4)
	var last := false
	while not last and f.get_position() + 4 <= f.get_length():
		var h := f.get_buffer(4)
		last = (h[0] & 0x80) != 0
		var kind := h[0] & 0x7F
		var blen := (h[1] << 16) | (h[2] << 8) | h[3]
		var start := f.get_position()
		if kind == 0 and blen >= 18:   # STREAMINFO
			var si := f.get_buffer(18)
			var rate := (si[10] << 12) | (si[11] << 4) | (si[12] >> 4)
			var total := ((si[13] & 0x0F) << 32) | (si[14] << 24) | (si[15] << 16) | (si[16] << 8) | si[17]
			if rate > 0:
				out.seconds = float(total) / rate
		elif kind == 4:               # VORBIS_COMMENT (little endian lengths)
			_vorbis_comments(f.get_buffer(min(blen, 1 << 20)), 0, out)
		elif kind == 6:               # PICTURE
			out.picture = true
		f.seek(start + blen)


static func _vorbis_comments(b: PackedByteArray, pos: int, out: Dictionary) -> void:
	if pos + 4 > b.size():
		return
	var vendor := b.decode_u32(pos)
	pos += 4 + vendor
	if pos + 4 > b.size():
		return
	var n := b.decode_u32(pos)
	pos += 4
	for i in min(n, 1000):
		if pos + 4 > b.size():
			return
		var l := b.decode_u32(pos)
		pos += 4
		var kv := b.slice(pos, pos + l).get_string_from_utf8()
		pos += l
		var eq := kv.find("=")
		if eq <= 0:
			continue
		var k := kv.substr(0, eq).to_upper()
		var v := kv.substr(eq + 1).strip_edges()
		match k:
			"TITLE": out.title = v
			"ARTIST": if out.artist == "": out.artist = v
			"ALBUMARTIST": if out.artist == "": out.artist = v
			"ALBUM": out.album = v
			"TRACKNUMBER", "TRACK": out.track = _num(v)
			"DISCNUMBER", "DISC": out.disc = _num(v)
			"DATE", "YEAR": out.year = v.substr(0, 4)
			"METADATA_BLOCK_PICTURE": out.picture = true


# ------------------------------------------------------------------ Ogg
static func _ogg(head: PackedByteArray, out: Dictionary) -> void:
	# The comment header is the second Vorbis packet: "\x03vorbis" then comments.
	var at := _find(head, PackedByteArray([3, 0x76, 0x6F, 0x72, 0x62, 0x69, 0x73]), 0)
	if at >= 0:
		_vorbis_comments(head, at + 7, out)


static func _find(b: PackedByteArray, needle: PackedByteArray, from: int) -> int:
	var n := needle.size()
	for i in range(from, b.size() - n):
		if b[i] == needle[0] and b.slice(i, i + n) == needle:
			return i
	return -1


# ------------------------------------------------------------------ ID3
static func _syncsafe(b: PackedByteArray, o: int) -> int:
	return ((b[o] & 0x7F) << 21) | ((b[o + 1] & 0x7F) << 14) | ((b[o + 2] & 0x7F) << 7) | (b[o + 3] & 0x7F)


static func _id3_text(b: PackedByteArray) -> String:
	if b.is_empty():
		return ""
	var enc := b[0]
	var body := b.slice(1)
	var s := ""
	match enc:
		1, 2:
			# UTF-16 with BOM (1) or big endian (2).
			var be := enc == 2
			var start := 0
			if body.size() >= 2 and body[0] == 0xFE and body[1] == 0xFF:
				be = true
				start = 2
			elif body.size() >= 2 and body[0] == 0xFF and body[1] == 0xFE:
				start = 2
			var u := PackedByteArray()
			for i in range(start, body.size() - 1, 2):
				if be:
					u.append(body[i + 1])
					u.append(body[i])
				else:
					u.append(body[i])
					u.append(body[i + 1])
			s = u.get_string_from_utf16()
		3:
			s = body.get_string_from_utf8()
		_:
			s = body.get_string_from_ascii()
	return _clean(s)


static func _id3v2(b: PackedByteArray, out: Dictionary) -> void:
	var ver := b[3]
	var end := min(_syncsafe(b, 6) + 10, b.size())
	var pos := 10
	if b[5] & 0x40:   # extended header
		pos += _syncsafe(b, 10) if ver == 4 else b.decode_u32(10)
	while pos + 10 <= end:
		var id := b.slice(pos, pos + 4).get_string_from_ascii()
		if id.length() < 4 or id[0] == char(0):
			break
		var size := _syncsafe(b, pos + 4) if ver == 4 else ((b[pos + 4] << 24) | (b[pos + 5] << 16) | (b[pos + 6] << 8) | b[pos + 7])
		var data := b.slice(pos + 10, min(pos + 10 + size, end))
		match id:
			"TIT2": out.title = _id3_text(data)
			"TPE1": out.artist = _id3_text(data)
			"TALB": out.album = _id3_text(data)
			"TRCK":
				var v := _id3_text(data)
				var dm := RegEx.create_from_string("^(\\d+)\\.(\\d+)$").search(v)
				if dm:   # "1.03" = disc 1, track 3
					out.disc = dm.get_string(1).to_int()
					out.track = dm.get_string(2).to_int()
				else:
					out.track = _num(v)
			"TPOS": if _num(_id3_text(data)) > 0: out.disc = _num(_id3_text(data))
			"TYER", "TDRC": out.year = _id3_text(data).substr(0, 4)
			"APIC": out.picture = true
		pos += 10 + size


## Duration from the Xing/Info frame count, or from the first frame's bit rate.
static func _mp3_seconds(b: PackedByteArray, start: int, file_size: int) -> float:
	var rates := [0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 0]
	var srates := [44100, 48000, 32000, 0]
	var i := start
	while i + 4 < b.size():
		if b[i] == 0xFF and (b[i + 1] & 0xE0) == 0xE0:
			var v1 := (b[i + 1] & 0x18) == 0x18      # MPEG-1
			var br: int = rates[(b[i + 2] >> 4) & 0x0F]
			var sr: int = srates[(b[i + 2] >> 2) & 0x03]
			if br > 0 and sr > 0 and v1:
				var x := _find(b.slice(i, min(i + 200, b.size())), "Xing".to_ascii_buffer(), 0)
				if x < 0:
					x = _find(b.slice(i, min(i + 200, b.size())), "Info".to_ascii_buffer(), 0)
				if x >= 0:
					var p := i + x
					if b[p + 7] & 1:
						var frames := (b[p + 8] << 24) | (b[p + 9] << 16) | (b[p + 10] << 8) | b[p + 11]
						return frames * 1152.0 / sr
				return (file_size - i) * 8.0 / (br * 1000.0)
		i += 1
	return 0.0


## The embedded cover picture (FLAC PICTURE block or ID3 APIC frame), or empty.
static func picture(path: String) -> PackedByteArray:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return PackedByteArray()
	var head := f.get_buffer(min(4, f.get_length()))
	var out := PackedByteArray()
	if head.size() == 4 and head.get_string_from_ascii() == "fLaC":
		var last := false
		while not last and f.get_position() + 4 <= f.get_length():
			var h := f.get_buffer(4)
			last = (h[0] & 0x80) != 0
			var blen := (h[1] << 16) | (h[2] << 8) | h[3]
			var start := f.get_position()
			if (h[0] & 0x7F) == 6:
				var b := f.get_buffer(blen)
				var p := 4
				var mime_len := _be(b, p)
				p += 4 + mime_len
				var desc_len := _be(b, p)
				p += 4 + desc_len + 16
				var data_len := _be(b, p)
				out = b.slice(p + 4, p + 4 + data_len)
				break
			f.seek(start + blen)
	elif head.size() >= 3 and head.slice(0, 3).get_string_from_ascii() == "ID3":
		f.seek(0)
		var hdr := f.get_buffer(10)
		var size := _syncsafe(hdr, 6)
		var b := hdr + f.get_buffer(size)
		var ver := b[3]
		var pos := 10
		while pos + 10 <= b.size():
			var id := b.slice(pos, pos + 4).get_string_from_ascii()
			if id.length() < 4 or id[0] == char(0):
				break
			var fs := _syncsafe(b, pos + 4) if ver == 4 else _be(b, pos + 4)
			if id == "APIC":
				var d := b.slice(pos + 10, pos + 10 + fs)
				var enc := d[0]
				var p := d.find(0, 1) + 1          # end of MIME type
				p += 1                             # picture type
				if enc == 1 or enc == 2:           # UTF-16 description ends with 00 00
					while p + 1 < d.size() and not (d[p] == 0 and d[p + 1] == 0):
						p += 2
					p += 2
				else:
					p = d.find(0, p) + 1
				out = d.slice(p)
				break
			pos += 10 + fs
	f.close()
	return out


static func _be(b: PackedByteArray, o: int) -> int:
	return (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3]
