class_name Iso9660
extends RefCounted
## Minimal read-only ISO 9660 reader. Handles plain 2048-byte images (ISO, PSP,
## PS2) and raw 2352-byte CD images (PS1 BIN, MODE1 and MODE2/XA form 1).
## Used to identify dumps and to read files (music, SYSTEM.CNF) without
## extracting the whole disc.

var path := ""
var ok := false
var sector_size := 2048
var data_offset := 0
var volume_id := ""
var _f: FileAccess
var _root_lba := 0
var _root_size := 0


static func open(p: String) -> Iso9660:
	var iso := Iso9660.new()
	iso._open(p)
	return iso


func _open(p: String) -> void:
	path = p
	_f = FileAccess.open(p, FileAccess.READ)
	if _f == null:
		return
	# Raw CD images start every sector with a 12-byte sync pattern.
	_f.seek(0)
	var sync := _f.get_buffer(16)
	if sync.size() == 16 and sync[0] == 0 and sync[1] == 0xFF and sync[11] == 0:
		sector_size = 2352
		data_offset = 24 if sync[15] == 2 else 16
	var pvd := read_sector(16)
	if pvd.size() < 2048 or pvd[0] != 1 or pvd.slice(1, 6).get_string_from_ascii() != "CD001":
		# Some PS1 rips are MODE2 with the mode byte unset; try the other offset.
		if sector_size == 2352:
			data_offset = 16 if data_offset == 24 else 24
			pvd = read_sector(16)
		if pvd.size() < 2048 or pvd[0] != 1:
			return
	volume_id = pvd.slice(40, 72).get_string_from_ascii().strip_edges()
	_root_lba = pvd.decode_u32(156 + 2)
	_root_size = pvd.decode_u32(156 + 10)
	ok = true


func close() -> void:
	if _f:
		_f.close()
		_f = null


func read_sector(lba: int) -> PackedByteArray:
	_f.seek(lba * sector_size + data_offset)
	return _f.get_buffer(2048)


func read_extent(lba: int, size: int) -> PackedByteArray:
	if sector_size == 2048:
		_f.seek(lba * 2048)
		return _f.get_buffer(size)
	var out := PackedByteArray()
	var n := int(ceil(size / 2048.0))
	for i in n:
		out.append_array(read_sector(lba + i))
	out.resize(size)
	return out


## Lists a directory: [{name, lba, size, dir}]
func list_dir(dir_path: String = "") -> Array:
	var ent := _resolve(dir_path) if dir_path != "" else {"lba": _root_lba, "size": _root_size, "dir": true}
	if ent.is_empty() or not ent.dir:
		return []
	return _read_dir(ent.lba, ent.size)


func find(file_path: String) -> Dictionary:
	return _resolve(file_path)


func read_file(file_path: String, max_bytes: int = -1) -> PackedByteArray:
	var e := _resolve(file_path)
	if e.is_empty() or e.dir:
		return PackedByteArray()
	var size: int = e.size if max_bytes < 0 else min(e.size, max_bytes)
	return read_extent(e.lba, size)


func _resolve(p: String) -> Dictionary:
	var cur := {"lba": _root_lba, "size": _root_size, "dir": true, "name": ""}
	for part in p.replace("\\", "/").split("/", false):
		var want := part.to_upper()
		var found := {}
		for e in _read_dir(cur.lba, cur.size):
			if e.name.to_upper() == want:
				found = e
				break
		if found.is_empty():
			return {}
		cur = found
	return cur


func _read_dir(lba: int, size: int) -> Array:
	var out := []
	var buf := read_extent(lba, size)
	var pos := 0
	while pos < buf.size():
		var rec_len := buf[pos]
		if rec_len == 0:
			# Records don't cross sector boundaries; skip to the next sector.
			pos = (pos / 2048 + 1) * 2048
			continue
		var name_len := buf[pos + 32]
		var name := buf.slice(pos + 33, pos + 33 + name_len).get_string_from_ascii()
		var flags := buf[pos + 25]
		if not (name_len == 1 and (buf[pos + 33] == 0 or buf[pos + 33] == 1)):
			var semi := name.find(";")
			if semi >= 0:
				name = name.substr(0, semi)
			if name.ends_with("."):
				name = name.substr(0, name.length() - 1)
			out.append({"name": name, "lba": buf.decode_u32(pos + 2), "size": buf.decode_u32(pos + 10), "dir": (flags & 2) != 0})
		pos += rec_len
	return out
