extends RefCounted
## Menu sounds of the other Silent Hill games, read from the player's own copy of each game (nothing
## is bundled, nothing is decrypted). `library(id, root)` returns {sound name: AudioStreamWAV} of
## short sounds (at most MAX_SEC) in game order; `DEFAULTS` says which ones the four interface
## events use. `root` is the game's folder (App.state(id).path).
##
##   sh1                 PS1 disc image (gamedata/*.bin, or a .bin beside/under the folder): ISO 9660,
##                       file SILENT., its first VAB sound bank (the one loaded at boot: the system
##                       sounds). VAB tones are Sony PS-ADPCM (VAG). The menu sounds are program 0,
##                       keys 48..52; from the PC port's own sound table (g_Vab_InfoTable, indexed by
##                       Sfx id - 1280): Sfx_MenuError 1304 = key 48, MenuMove = 49, MenuCancel = 50,
##                       MenuConfirm = 51, MenuMap = 52.
##   sh4                 sound/sound.pac: "SDPA", u32 count, count x {u32 offset, u32 size, u32 flags},
##                       each a PCM WAV. Named by the game's sound ids (the exe's table at 0x6019d0:
##                       0x6c-byte records {id, volume, waves, wave[...]}, group bases at 0x6018e0);
##                       SH4_WAVES below holds the system range 40000..42999. Two waves of one id
##                       with consecutive indices and equal length are the left and right channels.
##   homecoming          Engine/pak/pc/GLOBAL.PAK: "PAK_", u32 1, u32 count, u32 0, then count x 88-byte
##                       records {char name[64], u32 flags, u32 ?, u32 offset, u32 size, u32 type,
##                       u32 size}; type 0x0027FFFF entries are Ogg Vorbis files (UI_back,
##                       UI_horizontal, UI_select, UI_vertical...). Decoded to PCM with Godot's own
##                       Ogg decoder.
##   shattered-memories  data.arc of the Wii disc (an extracted disc folder: files/data.arc): entry
##                       "ui" (hash h = h*33 ^ c) is the AFX_UI project, FEV1 + FSB4 with GameCube
##                       DSP ADPCM waves (AFX_NavigateMove, AFX_NavigateSelect...).
##   pt                  CUSA01127/chunk1.psarc (PSARC, zlib blocks): as/sh/sound/asset/sys_resident.sbp,
##                       a Wwise bank (BKHD v88, DIDX, DATA, HIRC). Event -> play action -> sound ->
##                       media; only PCM media (codec 0xFFFE) are read. Play_sys_change_01 is Wwise
##                       Vorbis, and Play_sys_cancel_01 / Play_sys_ng_01 are Wwise Silence sources,
##                       so P.T. has two real menu sounds.

const MAX_SEC := 1.6

## Which sound each event uses (see the report in docs or each game's notes above).
const DEFAULTS := {
	"sh1": {"move": "MenuMove", "tab": "MenuMap", "select": "MenuConfirm", "back": "MenuCancel"},
	"sh4": {"move": "40000", "tab": "40089", "select": "42001", "back": "40002"},
	"homecoming": {"move": "UI_vertical", "tab": "UI_horizontal", "select": "UI_select", "back": "UI_back"},
	"shattered-memories": {"move": "AFX_NavigateMove", "tab": "AFX_VideoMove", "select": "AFX_NavigateSelect", "back": "AFX_CellPhoneSwitchOff"},
	"pt": {"move": "Play_sys_cursor_01", "tab": "Play_sys_cursor_01", "select": "event_f27dac95", "back": "Play_sys_cursor_01"},
}


static func library(id: String, root: String) -> Dictionary:
	if root == "" or not DirAccess.dir_exists_absolute(root):
		return {}
	match id:
		"sh1":
			return _sh1(root)
		"sh4":
			return _sh4(root)
		"homecoming":
			return _homecoming(root)
		"shattered-memories":
			return _shsm(root)
		"pt":
			return _pt(root)
	return {}


# ------------------------------------------------------------------ helpers
static func _first_file(candidates: Array) -> String:
	for p in candidates:
		if FileAccess.file_exists(p):
			return p
	return ""


static func _read(path: String, offset: int, size: int) -> PackedByteArray:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return PackedByteArray()
	f.seek(offset)
	var b := f.get_buffer(size)
	f.close()
	return b


static func _pcm16(data: PackedByteArray, rate: int, stereo: bool) -> AudioStreamWAV:
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = rate
	s.stereo = stereo
	s.data = data
	return s


## A RIFF WAV's PCM (8/16-bit, mono or stereo; tag 1, or 0xFFFE as Wwise writes PCM).
static func wav_stream(b: PackedByteArray) -> AudioStreamWAV:
	if b.size() < 44 or b.slice(0, 4).get_string_from_ascii() != "RIFF":
		return null
	var pos := 12
	var fmt := {}
	var data := PackedByteArray()
	while pos + 8 <= b.size():
		var tag := b.slice(pos, pos + 4).get_string_from_ascii()
		var n := b.decode_u32(pos + 4)
		if tag == "fmt ":
			fmt = {"tag": b.decode_u16(pos + 8), "ch": b.decode_u16(pos + 10), "rate": b.decode_u32(pos + 12), "bits": b.decode_u16(pos + 22)}
		elif tag == "data":
			data = b.slice(pos + 8, mini(b.size(), pos + 8 + n))
			break
		pos += 8 + n + (n % 2)
	if fmt.is_empty() or data.is_empty() or not (int(fmt.tag) in [1, 0xFFFE]) or int(fmt.ch) > 2:
		return null
	var s := AudioStreamWAV.new()
	s.mix_rate = int(fmt.rate)
	s.stereo = int(fmt.ch) == 2
	if int(fmt.bits) == 8:
		for i in data.size():
			data[i] = (data[i] + 128) & 0xFF   # WAV 8-bit is unsigned, Godot's signed
		s.format = AudioStreamWAV.FORMAT_8_BITS
	elif int(fmt.bits) == 16:
		s.format = AudioStreamWAV.FORMAT_16_BITS
	else:
		return null
	s.data = data
	return s


static func _unique(out: Dictionary, name: String) -> String:
	if not out.has(name):
		return name
	var i := 2
	while out.has("%s_%d" % [name, i]):
		i += 1
	return "%s_%d" % [name, i]


# ------------------------------------------------------------------ Silent Hill (PS1 disc)
const SH1_MENU := {48: "MenuError", 49: "MenuMove", 50: "MenuCancel", 51: "MenuConfirm", 52: "MenuMap"}
const VAG_COEF := [[0, 0], [60, 0], [115, -52], [98, -55], [122, -60]]


static func _sh1(root: String) -> Dictionary:
	var bin := _sh1_disc(root)
	if bin == "":
		return {}
	var f := FileAccess.open(bin, FileAccess.READ)
	if f == null:
		return {}
	# Sector layout: raw 2352-byte (MODE2 form 1: data at +24; MODE1: +16) or a plain 2048 ISO.
	var layout := [[2352, 24], [2352, 16], [2048, 0]]
	var ss := 0
	var so := 0
	for l in layout:
		f.seek(16 * l[0] + l[1])
		var pvd := f.get_buffer(6)
		if pvd.size() == 6 and pvd.slice(1, 6).get_string_from_ascii() == "CD001":
			ss = l[0]
			so = l[1]
			break
	if ss == 0:
		return {}
	var read_sectors := func(lba: int, bytes: int) -> PackedByteArray:
		var out := PackedByteArray()
		var n := (bytes + 2047) / 2048
		for k in n:
			f.seek((lba + k) * ss + so)
			var b := f.get_buffer(2048)
			if b.is_empty():
				break
			out.append_array(b)
		return out.slice(0, bytes) if out.size() > bytes else out
	var pvd: PackedByteArray = read_sectors.call(16, 2048)
	var root_lba := pvd.decode_u32(156 + 2)
	var root_size := pvd.decode_u32(156 + 10)
	var dir: PackedByteArray = read_sectors.call(root_lba, mini(root_size, 65536))
	var silent_lba := -1
	var silent_size := 0
	var p := 0
	while p < dir.size():
		var l := dir[p]
		if l == 0:
			p = (p / 2048 + 1) * 2048   # records don't cross sectors
			continue
		var nl := dir[p + 32]
		var nm := dir.slice(p + 33, p + 33 + nl).get_string_from_ascii().get_slice(";", 0)
		if nm == "SILENT." or nm == "SILENT":
			silent_lba = dir.decode_u32(p + 2)
			silent_size = dir.decode_u32(p + 10)
			break
		p += l
	if silent_lba < 0:
		return {}
	# The boot (system) sound bank: the first VAB in SILENT. whose program 0 maps keys 48..52.
	var sectors := mini(silent_size / 2048, 4000)
	for s in sectors:
		f.seek((silent_lba + s) * ss + so)
		var head := f.get_buffer(32)
		if head.size() < 32:
			break
		if head.slice(0, 4).get_string_from_ascii() != "pBAV":
			continue
		var fsize := head.decode_u32(12)
		if fsize < 2048 or fsize > 4 * 1024 * 1024:
			continue
		var vab: PackedByteArray = read_sectors.call(silent_lba + s, fsize)
		var out := _vab(vab, true)
		if not out.is_empty():
			f.close()
			return out
	f.close()
	return {}


static func _sh1_disc(root: String) -> String:
	for d in [root.path_join("gamedata"), root, root.path_join("disc")]:
		if not DirAccess.dir_exists_absolute(d):
			continue
		var bins := []
		for fn in DirAccess.get_files_at(d):
			if fn.get_extension().to_lower() in ["bin", "iso", "img"] and fn.to_lower().contains("silent"):
				bins.append(d.path_join(fn))
		bins.sort()
		if not bins.is_empty():
			return bins[0]
	return ""


## Every short tone of a VAB bank as a sound. `need_menu`: only accept a bank whose program 0 has
## the menu keys (the boot sound bank).
static func _vab(d: PackedByteArray, need_menu: bool) -> Dictionary:
	var out := {}
	if d.size() < 32 + 2048 or d.slice(0, 4).get_string_from_ascii() != "pBAV":
		return out
	var ps := d.decode_u16(18)
	var vs := d.decode_u16(22)
	var toff := 32 + 128 * 16
	var vt := toff + ps * 16 * 32
	var body := vt + 512
	if ps == 0 or ps > 128 or body > d.size():
		return out
	var vag_off := PackedInt32Array()
	var vag_size := PackedInt32Array()
	var acc := body
	for i in 256:
		var sz := d.decode_u16(vt + i * 2) * 8
		vag_off.append(acc)
		vag_size.append(sz)
		acc += sz
	if need_menu:
		var keys := {}
		for t in mini(d[32], 16):
			var a := toff + t * 32
			if d[a + 6] == d[a + 7]:
				keys[d[a + 6]] = true
		for k in SH1_MENU:
			if not keys.has(k):
				return {}
	var seen := {}
	for prog in ps:
		var tones := mini(d[32 + prog * 16], 16)
		for t in tones:
			var a := toff + (prog * 16 + t) * 32
			var vol := d[a + 2]
			var center := d[a + 4]
			var shift := d[a + 5]
			var kmin := d[a + 6]
			var kmax := d[a + 7]
			var vag := d.decode_s16(a + 22)
			if vol == 0 or vag <= 0 or vag > vs:
				continue
			# The SPU plays a tone at 44100 Hz on its centre key (+ fine tune in 1/128 semitone).
			var key := kmin if kmin == kmax else center
			var rate := int(round(44100.0 * pow(2.0, (key - center - shift / 128.0) / 12.0)))
			var sig := "%d:%d" % [vag, rate]
			if seen.has(sig) or rate < 2000 or rate > 96000:
				continue
			seen[sig] = true
			var src := d.slice(vag_off[vag], mini(d.size(), vag_off[vag] + vag_size[vag]))
			if src.size() / 16.0 * 28.0 / rate > MAX_SEC * 4.0:
				continue   # decoded samples are cut at the end flag; this skips long beds early
			var pcm := decode_vag(src, int(MAX_SEC * rate))
			if pcm.size() < int(0.01 * rate) * 2:
				continue   # MenuMove itself is a 0.026 s tick
			var name: String = SH1_MENU[kmin] if prog == 0 and kmin == kmax and SH1_MENU.has(kmin) else "p%d_t%d" % [prog, t]
			out[_unique(out, name)] = _pcm16(pcm, rate, false)
	return out


## Sony PS-ADPCM (VAG) to 16-bit PCM, up to `max_samples`; stops at a block with the end flag.
static func decode_vag(src: PackedByteArray, max_samples: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(mini(max_samples, src.size() / 16 * 28) * 2)
	var n := 0
	var s1 := 0
	var s2 := 0
	var lim := out.size() / 2
	var started := false
	for b in range(0, src.size() - 15, 16):
		var pred := mini(src[b] >> 4, 4)
		var shift := src[b] & 15
		var flags := src[b + 1]
		if not started and src[b] == 0 and flags == 0 and src.decode_u32(b + 2) == 0:
			continue   # the leading silent block
		started = true
		var c0: int = VAG_COEF[pred][0]
		var c1: int = VAG_COEF[pred][1]
		for k in 28:
			if n >= lim:
				break
			var byte := src[b + 2 + (k >> 1)]
			var nib := (byte >> 4) if (k & 1) else (byte & 15)
			var v := (nib << 12) & 0xFFFF
			if v >= 0x8000:
				v -= 0x10000
			v = (v >> shift) + ((s1 * c0 + s2 * c1 + 32) >> 6)
			v = clampi(v, -32768, 32767)
			s2 = s1
			s1 = v
			out.encode_s16(n * 2, v)
			n += 1
		if n >= lim or (flags & 1):
			break
	out.resize(n * 2)
	return out


# ------------------------------------------------------------------ Silent Hill 4 (PC)
## id -> sound.pac wave indices (from the GOG exe's table; system ids 40000..42999).
const SH4_WAVES := {40000: [104], 40002: [100], 40003: [92], 40004: [99], 40005: [103], 40006: [65], 40007: [318, 319], 40008: [88], 40009: [320, 321], 40010: [34], 40011: [31], 40012: [67], 40013: [85], 40014: [81], 40015: [33], 40016: [82], 40017: [73], 40018: [46], 40019: [43], 40021: [3], 40022: [0], 40023: [40], 40024: [66], 40025: [55], 40026: [56], 40029: [41], 40030: [69], 40031: [57], 40032: [23], 40033: [105], 40034: [71], 40035: [87], 40036: [70], 40037: [9], 40038: [15], 40039: [107], 40040: [54], 40041: [7], 40042: [83], 40043: [95], 40044: [101], 40045: [12], 40046: [79], 40050: [24], 40051: [80], 40052: [68], 40053: [60], 40054: [64], 40055: [14], 40056: [51], 40057: [39], 40058: [26], 40059: [35], 40060: [102], 40061: [42], 40062: [74], 40063: [76], 40064: [93], 40065: [72], 40066: [98], 40072: [11], 40073: [13], 40074: [10], 40075: [97], 40076: [6], 40077: [62], 40078: [19], 40079: [17], 40080: [27], 40081: [28], 40082: [61], 40083: [21], 40084: [5], 40085: [49], 40086: [38], 40087: [36], 40088: [22], 40089: [29, 29], 40090: [30], 40096: [25], 40100: [18], 40101: [59], 40102: [20], 40116: [67, 33], 40117: [84], 40118: [89], 40119: [78], 40120: [77], 40121: [47], 40122: [94], 40123: [48], 40124: [63], 40125: [53], 40128: [45, 87], 40129: [52], 40130: [86], 40131: [58], 40132: [96], 40133: [16], 40134: [2], 40135: [44, 44], 40136: [106], 40137: [108], 40138: [109], 40200: [91, 91], 40201: [90], 41000: [37, 37], 41001: [1, 1], 41049: [50], 42001: [322, 323], 42098: [324, 325], 42100: [326, 327], 42102: [328, 329], 42103: [330]}


static func _sh4(root: String) -> Dictionary:
	var out := {}
	var path := _first_file([root.path_join("sound/sound.pac"), root.path_join("Sound/sound.pac")])
	if path == "":
		return out
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return out
	var head := f.get_buffer(8)
	if head.size() < 8 or head.slice(0, 4).get_string_from_ascii() != "SDPA":
		f.close()
		return out
	var count := head.decode_u32(4)
	if count <= 0 or count > 4096:
		f.close()
		return out
	var table := f.get_buffer(count * 12)
	var wave := func(i: int) -> AudioStreamWAV:
		if i < 0 or i >= count:
			return null
		var size := table.decode_u32(i * 12 + 4)
		if size > int(MAX_SEC * 22050 * 2) + 4096 or size < 64:
			return null   # longer than a menu sound (the bank is 22 kHz 16-bit mono)
		f.seek(table.decode_u32(i * 12))
		return wav_stream(f.get_buffer(size))
	var ids := SH4_WAVES.keys()
	ids.sort()
	for id in ids:
		var ws: Array = SH4_WAVES[id]
		var s: AudioStreamWAV = wave.call(ws[0])
		if s == null or s.get_length() > MAX_SEC or s.get_length() < 0.03:
			continue
		if ws.size() == 2 and ws[1] == ws[0] + 1 and not s.stereo:
			var r: AudioStreamWAV = wave.call(ws[1])
			if r and not r.stereo and r.data.size() == s.data.size() and r.format == s.format and s.format == AudioStreamWAV.FORMAT_16_BITS:
				var st := PackedByteArray()
				st.resize(s.data.size() * 2)
				for k in range(0, s.data.size(), 2):
					st.encode_s16(k * 2, s.data.decode_s16(k))
					st.encode_s16(k * 2 + 2, r.data.decode_s16(k))
				s = _pcm16(st, s.mix_rate, true)
		out[str(id)] = s
	f.close()
	return out


# ------------------------------------------------------------------ Homecoming (PC)
const HC_OGG := 0x0027FFFF


static func _homecoming(root: String) -> Dictionary:
	var out := {}
	var path := _first_file([root.path_join("Engine/pak/pc/GLOBAL.PAK"), root.path_join("Engine/pak/PC/GLOBAL.PAK")])
	if path == "":
		return out
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return out
	var head := f.get_buffer(16)
	if head.size() < 16 or head.slice(0, 4).get_string_from_ascii() != "PAK_":
		f.close()
		return out
	var count := head.decode_u32(8)
	if count <= 0 or count > 100000:
		f.close()
		return out
	var toc := f.get_buffer(count * 88)
	var rate := int(AudioServer.get_mix_rate())
	# Only the UI sounds: everything else in GLOBAL.PAK is game sound effects (hundreds of them).
	for i in count:
		var r := i * 88
		var name := toc.slice(r, r + 64).get_string_from_ascii()
		if toc.decode_u32(r + 80) != HC_OGG or not name.to_lower().begins_with("ui_"):
			continue
		var size := toc.decode_u32(r + 76)
		if size > 200000:
			continue
		f.seek(toc.decode_u32(r + 72))
		var bytes := f.get_buffer(size)
		if bytes.slice(0, 4).get_string_from_ascii() != "OggS":
			continue
		var s := ogg_to_wav(bytes, rate)
		if s and s.get_length() > 0.03:
			out[_unique(out, name)] = s
	f.close()
	return out


## An Ogg Vorbis file decoded to 16-bit PCM (at most MAX_SEC) with Godot's decoder.
static func ogg_to_wav(bytes: PackedByteArray, rate: int) -> AudioStreamWAV:
	var ogg := AudioStreamOggVorbis.load_from_buffer(bytes)
	if ogg == null or ogg.get_length() <= 0.0:
		return null
	var frames := int(minf(ogg.get_length(), MAX_SEC) * rate)
	var pb := ogg.instantiate_playback()
	pb.start(0.0)
	var mix: PackedVector2Array = pb.mix_audio(1.0, frames)
	pb.stop()
	var pcm := PackedByteArray()
	pcm.resize(mix.size() * 4)
	for k in mix.size():
		pcm.encode_s16(k * 4, int(clampf(mix[k].x, -1.0, 1.0) * 32767.0))
		pcm.encode_s16(k * 4 + 2, int(clampf(mix[k].y, -1.0, 1.0) * 32767.0))
	return _pcm16(pcm, rate, true)


# ------------------------------------------------------------------ Shattered Memories (Wii)
static func _shsm(root: String) -> Dictionary:
	var out := {}
	var cands := [root.path_join("files/data.arc"), root.path_join("data.arc"),
		root.path_join("R5WEA4/files/data.arc"), root.path_join("decomp/orig/R5WEA4/files/data.arc")]
	for d in DirAccess.get_directories_at(root):
		cands.append(root.path_join(d).path_join("files/data.arc"))
	var path := _first_file(cands)
	if path == "":
		return out
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return out
	var head := f.get_buffer(16)
	if head.size() < 16 or head.decode_u32(0) != 0xFA10:
		f.close()
		return out
	var count := head.decode_u32(4)
	var table := f.get_buffer(16 * count)
	var want := _shsm_hash("ui")
	var data := PackedByteArray()
	for i in count:
		if table.decode_u32(i * 16) == want:
			f.seek(table.decode_u32(i * 16 + 4))
			data = f.get_buffer(table.decode_u32(i * 16 + 8))
			var unpacked := table.decode_u32(i * 16 + 12)
			if data.size() > 0 and data[0] == 0x78:
				data = data.decompress(unpacked, FileAccess.COMPRESSION_DEFLATE) if unpacked > 0 \
					else data.decompress_dynamic(16 * 1024 * 1024, FileAccess.COMPRESSION_DEFLATE)
			break
	f.close()
	var at := _find(data, "FSB4".to_ascii_buffer())
	if at < 0:
		return out
	return fsb4_dsp(data, at)


static func _shsm_hash(name: String) -> int:
	var h := 0
	for c in name.to_lower().to_ascii_buffer():
		h = ((h * 33) & 0xFFFFFFFF) ^ c
	return h


static func _find(d: PackedByteArray, what: PackedByteArray) -> int:
	var i := d.find(what[0])
	while i >= 0 and i + what.size() <= d.size():
		if d.slice(i, i + what.size()) == what:
			return i
		i = d.find(what[0], i + 1)
	return -1


## The short waves of an FSB4 bank with GameCube/Wii DSP ADPCM samples, by name (without ".wav").
static func fsb4_dsp(d: PackedByteArray, base: int) -> Dictionary:
	var out := {}
	if d.size() < base + 48 or d.slice(base, base + 4).get_string_from_ascii() != "FSB4":
		return out
	var n := d.decode_u32(base + 4)
	var h := base + 48
	var pos := base + 48 + d.decode_u32(base + 8)
	for i in n:
		if h + 0x50 > d.size():
			break
		var hsize := d.decode_u16(h)
		var name := d.slice(h + 2, h + 32).get_string_from_ascii().get_basename()
		var length := d.decode_u32(h + 32)
		var bytes := d.decode_u32(h + 36)
		var mode := d.decode_u32(h + 48)
		var rate := d.decode_u32(h + 52)
		var ch := maxi(1, d.decode_u16(h + 62))
		if (mode & 0x02000000) and ch <= 2 and rate > 0 and length > 0 and float(length) / rate <= MAX_SEC \
				and float(length) / rate > 0.03 and pos + bytes <= d.size():
			var pcm := PackedByteArray()
			pcm.resize(length * ch * 2)
			for c in ch:
				var coefs := PackedInt32Array()
				var o := h + 0x50 + c * 46
				for k in 16:
					coefs.append(_be16s(d, o + k * 2))
				var src := d.slice(pos, pos + bytes)
				if ch == 2:
					# Channels interleave every 2 bytes.
					var one := PackedByteArray()
					one.resize(bytes / 2)
					for k in range(0, bytes / 4):
						one[k * 2] = src[k * 4 + c * 2]
						one[k * 2 + 1] = src[k * 4 + c * 2 + 1]
					src = one
				_dsp(src, coefs, pcm, c, ch, length)
			out[_unique(out, name)] = _pcm16(pcm, rate, ch == 2)
		pos += bytes
		h += hsize
	return out


static func _be16s(d: PackedByteArray, o: int) -> int:
	var v := (d[o] << 8) | d[o + 1]
	return v - 65536 if v >= 32768 else v


## GameCube DSP ADPCM: 8-byte frames (predictor << 4 | scale, 7 bytes = 14 nibbles).
static func _dsp(src: PackedByteArray, coefs: PackedInt32Array, out: PackedByteArray, ch: int, nch: int, count: int) -> void:
	var h1 := 0
	var h2 := 0
	var n := 0
	var f := 0
	var o := ch * 2
	var stride := nch * 2
	while n < count and f + 8 <= src.size():
		var head := src[f]
		var c1 := coefs[((head >> 4) & 7) * 2]
		var c2 := coefs[((head >> 4) & 7) * 2 + 1]
		var scale := 1 << (head & 15)
		for k in 14:
			if n >= count:
				break
			var byte := src[f + 1 + (k >> 1)]
			var nib := (byte >> 4) if (k & 1) == 0 else (byte & 15)
			if nib >= 8:
				nib -= 16
			var v := (((nib * scale) << 11) + 1024 + c1 * h1 + c2 * h2) >> 11
			v = clampi(v, -32768, 32767)
			h2 = h1
			h1 = v
			out.encode_s16(o, v)
			o += stride
			n += 1
		f += 8


# ------------------------------------------------------------------ P.T. (PS4)
const PT_BANK := "as/sh/sound/asset/sys_resident.sbp"
const PT_EVENTS := ["Play_sys_cursor_01", "Play_sys_change_01", "Play_sys_cancel_01", "Play_sys_ng_01"]


static func _pt(root: String) -> Dictionary:
	var path := _first_file([root.path_join("CUSA01127/chunk1.psarc"), root.path_join("chunk1.psarc"),
		root.path_join("game/CUSA01127/chunk1.psarc")])
	if path == "":
		return {}
	var bank := psarc_read(path, PT_BANK)
	var at := _find(bank.slice(0, mini(bank.size(), 4096)), "BKHD".to_ascii_buffer())
	if at < 0:
		return {}
	return wwise_pcm(bank, at, PT_EVENTS)


## One file of a PSARC archive (big-endian TOC, zlib blocks), by its path in the manifest.
static func psarc_read(path: String, want: String) -> PackedByteArray:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return PackedByteArray()
	f.big_endian = true
	var magic := f.get_buffer(4).get_string_from_ascii()
	f.get_32()   # version
	var comp := f.get_buffer(4).get_string_from_ascii()
	var toc_len := f.get_32()
	var es := f.get_32()
	var n := f.get_32()
	var bs := f.get_32()
	f.get_32()   # flags
	if magic != "PSAR" or comp != "zlib" or n <= 0 or es < 30 or toc_len > 64 * 1024 * 1024:
		f.close()
		return PackedByteArray()
	var toc := f.get_buffer(toc_len - 32)
	var zw := 2 if bs <= 65536 else (3 if bs <= 16777216 else 4)
	var zbase := n * es
	var entry := func(i: int) -> PackedByteArray:
		var e := i * es
		var zi := (toc[e + 16] << 24) | (toc[e + 17] << 16) | (toc[e + 18] << 8) | toc[e + 19]
		var ln := 0
		var off := 0
		for k in 5:
			ln = (ln << 8) | toc[e + 20 + k]
			off = (off << 8) | toc[e + 25 + k]
		var out := PackedByteArray()
		f.seek(off)
		var k := zi
		while out.size() < ln:
			var z := 0
			for j in zw:
				z = (z << 8) | toc[zbase + k * zw + j]
			k += 1
			var raw := f.get_buffer(z if z > 0 else bs)
			if raw.is_empty():
				break
			var left := ln - out.size()
			if z > 0 and raw[0] == 0x78:
				var un := raw.decompress(mini(bs, left), FileAccess.COMPRESSION_DEFLATE)
				if not un.is_empty():
					raw = un
			out.append_array(raw)
		return out.slice(0, ln)
	var names: PackedStringArray = entry.call(0).get_string_from_utf8().split("\n")
	var idx := names.find(want)
	if idx < 0:
		idx = names.find("/" + want)
	var out: PackedByteArray = entry.call(idx + 1) if idx >= 0 and idx + 1 < n else PackedByteArray()
	f.close()
	return out


static func _fnv(s: String) -> int:
	var h := 2166136261
	for c in s.to_lower().to_ascii_buffer():
		h = ((h * 16777619) & 0xFFFFFFFF) ^ c
	return h


## The short PCM media of a Wwise bank, named by the event that plays them (known names, else
## "event_<hash>", else "wem_<id>").
static func wwise_pcm(d: PackedByteArray, at: int, event_names: Array) -> Dictionary:
	var out := {}
	var didx := {}   # media id -> [offset, size]
	var data_at := -1
	var objs := {}   # id -> [type, body offset, body size]
	var p := at
	while p + 8 <= d.size():
		var tag := d.slice(p, p + 4).get_string_from_ascii()
		var sz := d.decode_u32(p + 4)
		if not tag in ["BKHD", "DIDX", "DATA", "HIRC", "STID", "STMG", "ENVS", "PLAT", "INIT"]:
			break
		var b := p + 8
		if tag == "DIDX":
			for i in sz / 12:
				didx[d.decode_u32(b + i * 12)] = [d.decode_u32(b + i * 12 + 4), d.decode_u32(b + i * 12 + 8)]
		elif tag == "DATA":
			data_at = b
		elif tag == "HIRC":
			var q := b + 4
			for i in d.decode_u32(b):
				if q + 9 > b + sz:
					break
				var ln := d.decode_u32(q + 1)
				objs[d.decode_u32(q + 5)] = [d[q], q + 9, ln - 4]
				q += 5 + ln
		p = b + sz
	if data_at < 0:
		return out
	var known := {}
	for e in event_names:
		known[_fnv(e)] = e
	# media id -> name, through event -> play action -> sound.
	var media_name := {}
	for id in objs:
		var o: Array = objs[id]
		if o[0] != 4:
			continue
		var ev: String = known.get(id, "event_%08x" % id)
		var nact := d.decode_u32(o[1])
		for k in mini(nact, 16):
			var act: Array = objs.get(d.decode_u32(o[1] + 4 + k * 4), [])
			if act.is_empty() or act[0] != 3 or d.decode_u16(act[1]) != 0x0403:
				continue
			var snd: Array = objs.get(d.decode_u32(act[1] + 2), [])
			if snd.is_empty() or snd[0] != 2:
				continue
			var media := d.decode_u32(snd[1] + 8)
			if not media_name.has(media) or known.has(id):
				media_name[media] = ev
	var ids := didx.keys()
	ids.sort_custom(func(a, b): return didx[a][0] < didx[b][0])
	for m in ids:
		var r: Array = didx[m]
		var s := wav_stream(d.slice(data_at + r[0], data_at + r[0] + r[1]))
		if s == null or s.get_length() > MAX_SEC or s.get_length() < 0.03:
			continue
		out[_unique(out, media_name.get(m, "wem_%d" % m))] = s
	return out
