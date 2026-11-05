class_name AdxStream
extends RefCounted
## CRI ADX decoder (4-bit ADPCM, as used by Silent Hill 2 and 3), decoding on
## demand so a track starts playing at once. Handles streams made of several
## ADX segments one after another (AIX layers, intro + loop parts).
##
## Header (big endian): 0x00 0x8000, 0x02 copyright offset (data at +4),
## 0x04 encoding (3 = standard, 4 = exponential), 0x05 frame size (18),
## 0x06 bits (4), 0x07 channels, 0x08 rate, 0x0C total samples,
## 0x10 high-pass cutoff, 0x12 version.

var buf: PackedByteArray
var channels := 2
var rate := 44100
var total_samples := 0
var segments: Array = []   # {start, end, samples, channels, coef1, coef2, exp}
var ok := false

var _seg := 0
var _pos := 0
var _hist1 := PackedInt32Array()
var _hist2 := PackedInt32Array()
var _left := PackedVector2Array()   # decoded but not yet handed out
var _done := 0


static func from_bytes(b: PackedByteArray) -> AdxStream:
	var s := AdxStream.new()
	s.buf = b
	s._scan()
	return s


static func is_adx(head: PackedByteArray) -> bool:
	if head.size() < 0x14 or head[0] != 0x80 or head[1] != 0x00:
		return false
	var cofs := (head[2] << 8) | head[3]
	return head[4] in [3, 4] and head[5] == 18 and head[6] == 4 and cofs >= 0x10


static func header_info(head: PackedByteArray) -> Dictionary:
	if not is_adx(head):
		return {}
	var r := _be32(head, 8)
	var n := _be32(head, 12)
	return {"channels": head[7], "rate": r, "samples": n, "seconds": float(n) / max(r, 1)}


static func _be16(b: PackedByteArray, o: int) -> int:
	return (b[o] << 8) | b[o + 1]


static func _be32(b: PackedByteArray, o: int) -> int:
	return (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3]


func _parse_header(at: int) -> Dictionary:
	if at + 0x14 > buf.size() or not is_adx(buf.slice(at, at + 0x14)):
		return {}
	var cofs := _be16(buf, at + 2)
	var ch := buf[at + 7]
	var r := _be32(buf, at + 8)
	var n := _be32(buf, at + 12)
	var cutoff := _be16(buf, at + 0x10)
	# Prediction coefficients from the high-pass cutoff.
	var z := cos(TAU * cutoff / max(r, 1))
	var a := sqrt(2.0) - z
	var b := sqrt(2.0) - 1.0
	var c := (a - sqrt((a + b) * (a - b))) / b
	var start := at + cofs + 4
	var frames := int(ceil(n / 32.0))
	return {"start": start, "end": min(start + frames * 18 * ch, buf.size()), "samples": n, "channels": ch, "rate": r,
		"coef1": int(floor(c * 8192.0)), "coef2": int(floor(c * c * -4096.0)), "exp": buf[at + 4] == 4}


## Finds every ADX segment in the buffer.
func _scan() -> void:
	segments.clear()
	var at := 0
	while at < buf.size():
		var h := _parse_header(at)
		if h.is_empty():
			break
		segments.append(h)
		# The next segment's header follows the data, after any end/padding frames.
		var nxt := -1
		var p: int = h.end
		while p + 0x14 < buf.size() and p < h.end + 0x10000:
			if buf[p] == 0x80 and buf[p + 1] == 0x00 and is_adx(buf.slice(p, p + 0x14)):
				nxt = p
				break
			p += 1
		if nxt < 0:
			break
		at = nxt
	ok = not segments.is_empty()
	if ok:
		channels = segments[0].channels
		rate = segments[0].rate
		total_samples = 0
		for s in segments:
			total_samples += s.samples
	_reset()


func _reset() -> void:
	_seg = 0
	_pos = segments[0].start if ok else 0
	_hist1 = PackedInt32Array()
	_hist2 = PackedInt32Array()
	_hist1.resize(8)
	_hist2.resize(8)
	_left = PackedVector2Array()
	_done = 0


func seconds() -> float:
	return float(total_samples) / max(rate, 1)


func position_seconds() -> float:
	return float(_done) / max(rate, 1)


## Jumps to a sample position (frame-accurate, then trims).
func seek(sample: int) -> void:
	_reset()
	var acc := 0
	for i in segments.size():
		var s: Dictionary = segments[i]
		if sample < acc + s.samples or i == segments.size() - 1:
			_seg = i
			var local: int = clamp(sample - acc, 0, s.samples)
			var frame := local / 32
			_pos = s.start + frame * 18 * s.channels
			_done = acc + frame * 32
			# History restarts at zero; the click this causes is inaudible at a frame edge.
			return
		acc += s.samples


func finished() -> bool:
	return _done >= total_samples and _left.is_empty()


## Returns up to n stereo frames as floats in -1..1.
func read(n: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	if not ok:
		return out
	if not _left.is_empty():
		var take: int = min(n, _left.size())
		out.append_array(_left.slice(0, take))
		_left = _left.slice(take)
	while out.size() < n and _seg < segments.size():
		var s: Dictionary = segments[_seg]
		var ch: int = s.channels
		if _pos + 18 * ch > s.end:
			_seg += 1
			if _seg < segments.size():
				_pos = segments[_seg].start
			continue
		var block := _decode_frame(s, ch)
		_pos += 18 * ch
		var need := n - out.size()
		if block.size() <= need:
			out.append_array(block)
		else:
			out.append_array(block.slice(0, need))
			_left = block.slice(need)
	_done += out.size()
	return out


func _decode_frame(s: Dictionary, ch: int) -> PackedVector2Array:
	var c1: int = s.coef1
	var c2: int = s.coef2
	var lr := [PackedFloat32Array(), PackedFloat32Array()]
	for c in mini(ch, 2):
		var dst: PackedFloat32Array = lr[c]
		dst.resize(32)
		var o := _pos + c * 18
		var scale := _be16(buf, o)
		if scale & 0x8000:
			scale = 0   # end-of-stream frame: silence
		elif s.exp:
			scale = 1 << (12 - mini(scale, 12))
		var h1 := _hist1[c]
		var h2 := _hist2[c]
		for i in 32:
			var byte := buf[o + 2 + (i >> 1)]
			var nib := (byte >> 4) if (i & 1) == 0 else (byte & 0x0F)
			if nib >= 8:
				nib -= 16
			var smp := nib * scale + ((c1 * h1 + c2 * h2) >> 12)
			smp = clampi(smp, -32768, 32767)
			h2 = h1
			h1 = smp
			dst[i] = smp / 32768.0
		_hist1[c] = h1
		_hist2[c] = h2
		lr[c] = dst
	var res := PackedVector2Array()
	res.resize(32)
	var l: PackedFloat32Array = lr[0]
	var r: PackedFloat32Array = lr[1] if ch > 1 else lr[0]
	for i in 32:
		res[i] = Vector2(l[i], r[i])
	return res
