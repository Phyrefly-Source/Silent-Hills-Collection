class_name Subtitles
extends RefCounted
## Text subtitles: SRT files beside a film, or tracks inside it (extracted once
## with FFmpeg into the cache). Cues are [start, end, text].

var cues: Array = []


static func from_srt(text: String) -> Subtitles:
	var s := Subtitles.new()
	text = text.replace("\r\n", "\n").replace("\r", "\n").trim_prefix("﻿")
	var re := RegEx.create_from_string("(\\d+):(\\d+):(\\d+)[,.](\\d+)\\s*-->\\s*(\\d+):(\\d+):(\\d+)[,.](\\d+)")
	for block in text.split("\n\n", false):
		var lines := Array(block.strip_edges().split("\n"))
		for i in lines.size():
			var m := re.search(lines[i])
			if m:
				var a := _t(m, 1)
				var b := _t(m, 5)
				var body := "\n".join(lines.slice(i + 1))
				body = RegEx.create_from_string("<[^>]*>|\\{[^}]*\\}").sub(body, "", true).strip_edges()
				if body != "":
					s.cues.append([a, b, body])
				break
	s.cues.sort_custom(func(x, y): return x[0] < y[0])
	return s


static func _t(m: RegExMatch, g: int) -> float:
	return m.get_string(g).to_int() * 3600 + m.get_string(g + 1).to_int() * 60 + m.get_string(g + 2).to_int() + float("0." + m.get_string(g + 3))


## The text on screen at `t`, or "".
func at(t: float) -> String:
	var lo := 0
	var hi := cues.size()
	while lo < hi:   # first cue starting after t
		var mid := (lo + hi) / 2
		if cues[mid][0] <= t:
			lo = mid + 1
		else:
			hi = mid
	var out := []
	var i := lo - 1
	while i >= 0 and lo - i <= 4:
		if cues[i][1] >= t:
			out.push_front(cues[i][2])
		i -= 1
	return "\n".join(out)


## Subtitle files beside a film: "Film.srt", "Film.en.srt", "Film.eng.srt" …
static func beside(film: String) -> Array:
	var out := []
	var dir := film.get_base_dir()
	var stem := film.get_file().get_basename().to_lower()
	for f in DirAccess.get_files_at(dir):
		if f.get_extension().to_lower() == "srt" and f.to_lower().begins_with(stem):
			var mid := f.get_basename().substr(stem.length()).trim_prefix(".")
			out.append({"path": dir.path_join(f), "title": mid.to_upper() if mid != "" else "SRT"})
	return out


## Extracts subtitle track `n` of a film to an SRT in the cache. cb(path or "").
static func extract(ff: String, film: String, n: int, cb: Callable) -> void:
	var out := App.cache_dir.path_join("subtitles").path_join("%s-%d.srt" % [film.to_lower().md5_text().substr(0, 12), n])
	if FileAccess.file_exists(out):
		cb.call(out)
		return
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	App.run(func():
		var part := out.get_basename() + ".part.srt"
		var code := OS.execute(ff, ["-nostdin", "-v", "error", "-y", "-i", film, "-map", "0:s:%d" % n, "-c:s", "srt", part], [], false, false)
		if code == 0 and FileAccess.file_exists(part):
			DirAccess.rename_absolute(part, out)
			return out
		DirAccess.remove_absolute(part)
		return "",
	cb)
