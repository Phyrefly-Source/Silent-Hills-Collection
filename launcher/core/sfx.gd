extends Node
## Interface sounds, by sound profile. Each profile is themed after a Silent
## Hill game and plays that game's own menu sounds, read from your copy of the
## game when the launcher starts (nothing is bundled):
##   Silent Hill 3 — the menu sounds in data/sound/sd.afs
##   Silent Hill 2 — the sounds Silent Hill 2: Enhanced Edition adds (sh2e/sound/extra)
## "Radio static" is made by the launcher itself, so it works without any game.
## Events: move (cycling through items), tab (switching sections),
## select (pressing a button), back (closing).

const EVENTS := ["move", "tab", "select", "back"]
## Longest each event's sound may ring (game sounds can be stings of several
## seconds; a menu click shouldn't be). Cut with a short fade.
const MAX_LEN := {"move": 0.3, "tab": 0.6, "select": 0.6, "back": 0.5}
const PROFILES := {
	"off": {"name": "Off"},
	"radio": {"name": "Radio static", "about": "Made by the launcher: the crackle of Harry's pocket radio."},
	"sh2": {"name": "Silent Hill 2", "game": "sh2", "about": "From your Silent Hill 2 (Enhanced Edition's sound folder)."},
	"sh3": {"name": "Silent Hill 3", "game": "sh3", "about": "Silent Hill 3's own menu sounds, from your copy of the game."},
	"sh1": {"name": "Silent Hill", "game": "sh1", "about": "Silent Hill's own menu sounds, from the system sound bank on your disc image."},
	"sh4": {"name": "Silent Hill 4: The Room", "game": "sh4", "about": "Silent Hill 4's own menu sounds, from sound.pac in your copy."},
	"homecoming": {"name": "Silent Hill: Homecoming", "game": "homecoming", "about": "Homecoming's own interface sounds, from GLOBAL.PAK in your copy."},
	"shattered-memories": {"name": "Silent Hill: Shattered Memories", "game": "shattered-memories", "about": "Shattered Memories' own interface sounds (its phone and menus), from data.arc in your copy."},
	"pt": {"name": "P.T.", "game": "pt", "about": "P.T.'s system sounds. It has very few, so some actions share one."},
}
const GameSounds := preload("res://core/game_sounds.gd")
## Which of a game's sounds each event uses, unless you choose others.
const DEFAULTS := {
	"sh3": {"move": "10000", "tab": "10002", "select": "10001", "back": "10003"},
	"sh2": {"move": "flashlight_on", "tab": "flashlight_off", "select": "g_start", "back": "flashlight_off"},
}

var _players: Array[AudioStreamPlayer] = []   # previews
var _event_players := {}  # event -> its own player, so a sound restarts rather than piling up
var _next := 0
var _streams := {}        # event -> AudioStream for the current profile
var _library := {}        # profile -> {sound name: AudioStream}
var _last_move := 0
var profile := ""


func _ready() -> void:
	for i in 2:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	for e in EVENTS:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_event_players[e] = p
	App.settings_changed.connect(_apply)
	_apply.call_deferred()


func _apply() -> void:
	var want := str(App.settings.get("sound_profile", "radio"))
	var vol := linear_to_db(clampf(float(App.settings.get("sfx_volume", 0.5)), 0.0001, 1.0))
	for p in _players:
		p.volume_db = vol
	for p in _event_players.values():
		p.volume_db = vol
	var custom: Dictionary = App.settings.get("sfx_custom", {}).get(want, {})
	var sig := want + JSON.stringify(custom)
	if sig == profile:
		return
	profile = sig
	_streams.clear()
	if want == "off":
		return
	if want == "radio" or not available(want):
		_streams = _synth()
		return
	var lib := library(want)
	var map: Dictionary = DEFAULTS.get(want, GameSounds.DEFAULTS.get(want, {})).duplicate()
	map.merge(custom, true)
	for e in EVENTS:
		if lib.has(map.get(e, "")):
			_streams[e] = clip(lib[map[e]], MAX_LEN[e])


## Plays an interface sound for an event.
var muted := false   # set while the launcher isn't the window in front


func play(event: String) -> void:
	if muted or not _streams.has(event):
		return
	if event == "move":
		var now := Time.get_ticks_msec()
		if now - _last_move < 45:
			return
		_last_move = now
	var p: AudioStreamPlayer = _event_players[event]
	p.stream = _streams[event]
	p.play()


## Plays a single sound (for trying sounds in Settings).
func preview(stream: AudioStream) -> void:
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = stream
	p.play()


## True when the game a profile needs is connected (its sounds are read the
## first time the profile is used; if they can't be, Radio static plays).
func available(id: String) -> bool:
	if id == "off" or id == "radio":
		return true
	if _library.has(id):
		return true
	var game: String = PROFILES.get(id, {}).get("game", "")
	var root := str(App.state(game).get("path", "")) if game != "" else ""
	return root != "" and DirAccess.dir_exists_absolute(root)


## Every short sound a profile's game has: {name: AudioStream}, in game order.
func library(id: String) -> Dictionary:
	if _library.has(id):
		return _library[id]
	var out := {}
	var game: String = PROFILES.get(id, {}).get("game", "")
	var root := str(App.state(game).get("path", "")) if game != "" else ""
	if root != "" and DirAccess.dir_exists_absolute(root):
		match id:
			"sh3":
				out = _from_afs(root.path_join("data/sound/sd.afs"), 1.6)
			"sh2":
				for d in [root.path_join("sh2e/sound/extra"), root.path_join("data/sound/extra")]:
					if DirAccess.dir_exists_absolute(d):
						for f in DirAccess.get_files_at(d):
							if f.get_extension().to_lower() == "wav":
								var s := wav_stream(FileAccess.get_file_as_bytes(d.path_join(f)))
								if s:
									out[f.get_basename()] = s
			_:
				out = GameSounds.library(id, root)
	if not out.is_empty():
		_library[id] = out   # empty: the game may be found later, so look again next time
	return out


## A sound without its leading silence, at most `max_sec` long (faded out).
static func clip(s: AudioStream, max_sec: float) -> AudioStream:
	if not s is AudioStreamWAV:
		return s
	var w: AudioStreamWAV = s
	var bps := (2 if w.format == AudioStreamWAV.FORMAT_16_BITS else 1) * (2 if w.stereo else 1)
	if w.format != AudioStreamWAV.FORMAT_16_BITS and w.format != AudioStreamWAV.FORMAT_8_BITS:
		return s
	var data := w.data
	var frames := data.size() / bps
	var start := 0
	var limit := 0.02   # of full scale
	for f in frames:
		var v := 0.0
		if w.format == AudioStreamWAV.FORMAT_16_BITS:
			v = absf(data.decode_s16(f * bps) / 32768.0)
		else:
			v = absf(data.decode_s8(f * bps) / 128.0)
		if v > limit:
			start = maxi(0, f - int(0.005 * w.mix_rate))
			break
	var n := mini(frames - start, int(max_sec * w.mix_rate))
	if start == 0 and n == frames:
		return s
	var out := data.slice(start * bps, (start + n) * bps)
	var fade := mini(n, int(0.04 * w.mix_rate))
	var ch := 2 if w.stereo else 1
	for f in range(n - fade, n):
		var g := float(n - f) / fade
		for c in ch:
			var o := f * bps + c * (bps / ch)
			if w.format == AudioStreamWAV.FORMAT_16_BITS:
				out.encode_s16(o, int(out.decode_s16(o) * g))
			else:
				out.encode_s8(o, int(out.decode_s8(o) * g))
	var r := AudioStreamWAV.new()
	r.format = w.format
	r.stereo = w.stereo
	r.mix_rate = w.mix_rate
	r.data = out
	return r


## WAV sounds inside a CRI AFS archive, up to `max_sec` long, by name.
static func _from_afs(path: String, max_sec: float) -> Dictionary:
	var out := {}
	if not FileAccess.file_exists(path):
		return out
	var names := {}
	for e in SoundContainers.afs_entries(path):
		var head := SoundContainers.read_range(path, e.offset, 12)
		if head.size() < 12 or head.slice(0, 4).get_string_from_ascii() != "RIFF":
			continue
		if e.size > int(max_sec * 22050 * 2 * 2) + 4096:
			continue   # longer than a menu sound
		var name := str(e.name).get_basename()
		if name == "" or names.has(name):
			continue
		names[name] = true
		var s := wav_stream(SoundContainers.read_range(path, e.offset, e.size))
		if s and s.get_length() <= max_sec and s.get_length() > 0.03:
			out[name] = s
	return out


## A WAV file's bytes (PCM 8/16-bit, mono or stereo) as an AudioStreamWAV.
static func wav_stream(b: PackedByteArray) -> AudioStreamWAV:
	if b.size() < 44 or b.slice(0, 4).get_string_from_ascii() != "RIFF":
		return null
	var pos := 12
	var fmt := {}
	var data := PackedByteArray()
	while pos + 8 <= b.size():
		var id := b.slice(pos, pos + 4).get_string_from_ascii()
		var n := b.decode_u32(pos + 4)
		if id == "fmt ":
			fmt = {"tag": b.decode_u16(pos + 8), "ch": b.decode_u16(pos + 10), "rate": b.decode_u32(pos + 12), "bits": b.decode_u16(pos + 22)}
		elif id == "data":
			data = b.slice(pos + 8, mini(b.size(), pos + 8 + n))
			break
		pos += 8 + n + (n % 2)
	if fmt.is_empty() or data.is_empty() or int(fmt.tag) != 1:
		return null
	var s := AudioStreamWAV.new()
	s.mix_rate = int(fmt.rate)
	s.stereo = int(fmt.ch) == 2
	if int(fmt.bits) == 8:
		# Godot's 8-bit format is signed; WAV's is unsigned.
		for i in data.size():
			data[i] = (data[i] + 128) & 0xFF
		s.format = AudioStreamWAV.FORMAT_8_BITS
	else:
		s.format = AudioStreamWAV.FORMAT_16_BITS
	s.data = data
	return s


# ------------------------------------------------------------------ radio static
## Sounds made by the launcher: short bursts of radio static and low tones.
static func _synth() -> Dictionary:
	return {
		"move": _make(0.05, 0.0, 0.0, 0.55, 2600.0),
		"tab": _make(0.16, 900.0, 900.0, 0.45, 1800.0),
		"select": _make(0.12, 150.0, 110.0, 0.35, 1400.0),
		"back": _make(0.13, 520.0, 240.0, 0.35, 1200.0),
	}


static func _make(sec: float, f0: float, f1: float, noise: float, band: float) -> AudioStreamWAV:
	var rate := 44100
	var n := int(sec * rate)
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(f0 * 7 + band)
	var lp := 0.0
	var hp := 0.0
	var phase := 0.0
	var a := clampf(band / rate * TAU, 0.0, 1.0)
	for i in n:
		var t := float(i) / n
		var env := minf(1.0, t * 40.0) * pow(1.0 - t, 2.2)
		# Band-limited crackle: noise through a simple low- and high-pass.
		var w := rng.randf_range(-1.0, 1.0)
		if rng.randf() < 0.004:
			w *= 4.0   # the odd pop
		lp += a * (w - lp)
		hp = lp - hp * 0.02
		var v := hp * noise
		if f0 > 0.0:
			var f := lerpf(f0, f1, t)
			phase += TAU * f / rate
			v += sin(phase) * 0.45
		v = clampf(v * env * 0.8, -1.0, 1.0)
		data.encode_s16(i * 2, int(v * 32000))
	var s := AudioStreamWAV.new()
	s.mix_rate = rate
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.data = data
	return s
