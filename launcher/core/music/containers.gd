class_name SoundContainers
extends RefCounted
## Readers for the containers game music comes in.
##   AFS  CRI archive (Silent Hill 3's sd.afs): "AFS\0", count, {offset, size}[],
##        then an optional name table of 0x30-byte records.
##   AIX  CRI layered stream (Silent Hill 2/3): an "AIXF" header, then "AIXP"
##        blocks {layer u8, layers u8, BE16 data size, BE32 seq, data}, "AIXE" at the end.
##        Each layer is an ordinary ADX stream; the game mixes layers in and out.


static func afs_entries(path: String) -> Array:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return []
	var head := f.get_buffer(8)
	if head.size() < 8 or head.slice(0, 3).get_string_from_ascii() != "AFS":
		return []
	var count := head.decode_u32(4)
	if count <= 0 or count > 200000:
		return []
	var table := f.get_buffer(count * 8 + 8)
	var out := []
	for i in count:
		out.append({"index": i, "offset": table.decode_u32(i * 8), "size": table.decode_u32(i * 8 + 4), "name": ""})
	# Name table: pointer right after the entries, or just before the first file.
	var names_at := table.decode_u32(count * 8)
	var names_size := table.decode_u32(count * 8 + 4)
	if names_at == 0 and not out.is_empty():
		f.seek(out[0].offset - 8)
		var p := f.get_buffer(8)
		names_at = p.decode_u32(0)
		names_size = p.decode_u32(4)
	if names_at > 0 and names_size >= count * 0x30 and names_at + names_size <= f.get_length():
		f.seek(names_at)
		var nb := f.get_buffer(count * 0x30)
		for i in count:
			out[i].name = nb.slice(i * 0x30, i * 0x30 + 32).get_string_from_ascii()
	f.close()
	return out


static func read_range(path: String, offset: int, size: int) -> PackedByteArray:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return PackedByteArray()
	f.seek(offset)
	var b := f.get_buffer(size if size > 0 else f.get_length() - offset)
	f.close()
	return b


## Splits an AIX file into its layers (each a byte stream of ADX segments).
static func aix_layers(b: PackedByteArray) -> Array:
	if b.size() < 16 or b.slice(0, 4).get_string_from_ascii() != "AIXF":
		return []
	var ranges := {}   # layer -> [start, len, start, len, ...]
	var pos := 8 + _be32(b, 4)
	while pos + 16 <= b.size():
		var tag := b.slice(pos, pos + 4).get_string_from_ascii()
		var size := _be32(b, pos + 4)
		if tag == "AIXP":
			var layer := b[pos + 8]
			if not ranges.has(layer):
				ranges[layer] = PackedInt64Array()
			var r: PackedInt64Array = ranges[layer]
			r.append(pos + 16)
			r.append((b[pos + 10] << 8) | b[pos + 11])
			ranges[layer] = r
		elif size == 0 and tag != "AIXE":
			break
		pos += 8 + size
	var keys := ranges.keys()
	keys.sort()
	var out := []
	for k in keys:
		var r: PackedInt64Array = ranges[k]
		var data := PackedByteArray()
		for i in range(0, r.size(), 2):
			data.append_array(b.slice(r[i], r[i] + r[i + 1]))
		out.append(data)
	return out


static func aix_info(path: String) -> Dictionary:
	# Reads only the first blocks: enough for rate, layer count and duration.
	var head := read_range(path, 0, 0x10000)
	if head.size() < 16 or head.slice(0, 4).get_string_from_ascii() != "AIXF":
		return {}
	var pos := 8 + _be32(head, 4)
	var layers := 0
	var info := {}
	while pos + 16 <= head.size():
		if head.slice(pos, pos + 4).get_string_from_ascii() != "AIXP":
			break
		layers = max(layers, head[pos + 9])
		if info.is_empty():
			info = AdxStream.header_info(head.slice(pos + 16, pos + 16 + 0x20))
		pos += 8 + _be32(head, pos + 4)
	if info.is_empty():
		return {}
	info.layers = layers
	# Every segment repeats the header; the file's total length gives the rest.
	var f := FileAccess.open(path, FileAccess.READ)
	var bytes := f.get_length()
	f.close()
	var per_sample: float = 18.0 / 32.0 * info.channels * max(layers, 1)
	info.seconds = max(info.seconds, (bytes - pos) / per_sample / max(info.rate, 1))
	return info


static func _be32(b: PackedByteArray, o: int) -> int:
	return (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3]
