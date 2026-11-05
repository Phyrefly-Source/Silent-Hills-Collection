extends RefCounted
## An Enhanced patch's own settings: a schema shipped in the package and the INI the patch reads.
##
## The manifest names the schema with "settings" (relative to its files folder, e.g.
## "Enhanced/settings.json"); it is read from the package, or from the game folder's copy.
## Schema: {version, ini, live_reload, groups: [{title, note, items: [{section, key, label, type,
## min, max, step, default, options, help, live}]}]}. "ini" is relative to the game folder.
## Types: bool (0/1), int, float (clamped to min/max, snapped to step), choice (index into options).
##
## Writes change one key's line only: every other line, comment and the file's line ending stay as
## they were. The game writes the same file, so each write re-reads it first.


## The schema for this package, or {} when it has none. Adds "_path" (where it was read from).
static func load_schema(pkg: Dictionary, game_path: String) -> Dictionary:
	var rel := str(pkg.get("settings", ""))
	if rel == "":
		return {}
	var tries := []
	if pkg.has("_dir"):
		tries.append(str(pkg._dir).path_join(str(pkg.get("files", "files"))).path_join(rel))
	if game_path != "":
		tries.append(game_path.path_join(rel))
	for p in tries:
		if FileAccess.file_exists(p):
			var d = JSON.parse_string(FileAccess.get_file_as_string(p))
			if d is Dictionary and d.get("groups", []) is Array:
				d["_path"] = p
				return d
	return {}


## {section (lower case): {key (lower case): value}}. The first of a repeated section or key wins,
## as with Windows' own INI reader.
static func parse(text: String) -> Dictionary:
	var out := {}
	var cur := ""
	for raw in text.split("\n"):
		var line := raw.strip_edges()
		if line == "" or line.begins_with(";") or line.begins_with("#"):
			continue
		if line.begins_with("[") and line.ends_with("]"):
			cur = line.substr(1, line.length() - 2).strip_edges().to_lower()
			if not out.has(cur):
				out[cur] = {}
			continue
		var eq := line.find("=")
		if cur == "" or eq <= 0:
			continue
		var k := line.substr(0, eq).strip_edges().to_lower()
		if not out[cur].has(k):
			out[cur][k] = line.substr(eq + 1).strip_edges()
	return out


static func read(ini_path: String) -> Dictionary:
	return parse(FileAccess.get_file_as_string(ini_path)) if FileAccess.file_exists(ini_path) else {}


## Clamped to min/max and snapped to step (from min). Bools are 0/1, choices an index.
static func normalize(item: Dictionary, v: float) -> float:
	match str(item.get("type", "float")):
		"bool":
			return 1.0 if v >= 0.5 else 0.0
		"choice":
			return clampf(roundf(v), 0, maxi(0, item.get("options", []).size() - 1))
	var lo := float(item.get("min", -INF))
	var hi := float(item.get("max", INF))
	var step := float(item.get("step", 1.0 if item.get("type") == "int" else 0.0))
	if item.get("type") == "int":
		step = maxf(1.0, roundf(step))
	if step > 0.0 and is_finite(lo):
		v = lo + roundf((v - lo) / step) * step
	elif step > 0.0:
		v = roundf(v / step) * step
	v = clampf(v, lo, hi)
	if item.get("type") == "int":
		return roundf(v)
	return snappedf(v, 0.0001)


## The value as the INI stores it: 0/1, an integer, or up to 4 decimals without trailing zeros.
static func format(item: Dictionary, v: float) -> String:
	v = normalize(item, v)
	if item.get("type") in ["bool", "choice", "int"]:
		return str(int(v))
	if v == roundf(v):
		return str(int(v))
	var s := String.num(v, 4)
	return "0" if s == "-0" else s


## The value an item has in parsed INI data, or its default.
static func value_of(data: Dictionary, item: Dictionary) -> float:
	var sec: Dictionary = data.get(str(item.get("section", "")).to_lower(), {})
	var key := str(item.get("key", "")).to_lower()
	var dflt := float(item.get("default", 0))
	if not sec.has(key):
		return normalize(item, dflt)
	var s: String = sec[key]
	var low := s.to_lower()
	if item.get("type") == "bool" and low in ["true", "yes", "on"]:
		return 1.0
	if item.get("type") == "bool" and low in ["false", "no", "off"]:
		return 0.0
	if not s.is_valid_float() and not s.is_valid_int():
		return normalize(item, dflt)
	return normalize(item, s.to_float())


## `text` with section/key set to value. Only that key's line changes (its own spelling, spacing
## before "=" and line ending are kept); a missing key goes after the last entry of its section,
## a missing section at the end. New lines use the file's line ending (CRLF when it has any).
static func set_key(text: String, section: String, key: String, value: String) -> String:
	var eol := "\r\n" if (text.contains("\r\n") or text == "") else "\n"
	var lines := text.split("\n")
	# A file ending in a newline splits into a last empty piece: that is not a line.
	var trailing := lines.size() > 0 and lines[lines.size() - 1] == ""
	if trailing:
		lines.remove_at(lines.size() - 1)
	var sec_l := section.strip_edges().to_lower()
	var key_l := key.strip_edges().to_lower()
	var in_sec := false
	var found_sec := false
	var last_entry := -1     # last non-blank line of the section (its header at first)
	for i in lines.size():
		var body := lines[i].trim_suffix("\r")
		var t := body.strip_edges()
		if t.begins_with("[") and t.ends_with("]"):
			if in_sec:
				break      # only the first section of that name counts
			in_sec = t.substr(1, t.length() - 2).strip_edges().to_lower() == sec_l
			if in_sec:
				found_sec = true
				last_entry = i
			continue
		if not in_sec:
			continue
		if t != "":
			last_entry = i
		if t.begins_with(";") or t.begins_with("#"):
			continue
		var eq := body.find("=")
		if eq > 0 and body.substr(0, eq).strip_edges().to_lower() == key_l:
			var line_eol := "\r" if lines[i].ends_with("\r") else ""
			var rest := body.substr(eq + 1)
			var lead := rest.substr(0, rest.length() - rest.lstrip(" \t").length())
			var new_line := body.substr(0, eq + 1) + lead + value + line_eol
			if new_line == lines[i]:
				return text
			lines[i] = new_line
			return "\n".join(lines) + ("\n" if trailing else "")
	var cr := "\r" if eol == "\r\n" else ""
	if found_sec:
		if last_entry == lines.size() - 1 and not trailing:
			# The section's last line was the file's last, with no line ending: give it one.
			if cr != "" and not lines[last_entry].ends_with("\r"):
				lines[last_entry] += cr
			trailing = true
		lines.insert(last_entry + 1, key + "=" + value + cr)
		return "\n".join(lines) + ("\n" if trailing else "")
	var out := "\n".join(lines)
	if lines.size() > 0:
		out += ("\n" if trailing else eol)
	return out + "[" + section + "]" + eol + key + "=" + value + eol


## Sets one value in the INI on disk, re-reading it first. "" = written (or already that value).
static func write(ini_path: String, section: String, key: String, value: String) -> String:
	var before := FileAccess.get_file_as_string(ini_path) if FileAccess.file_exists(ini_path) else ""
	if FileAccess.file_exists(ini_path) and before == "" and FileAccess.get_open_error() != OK:
		return "Couldn't read %s." % ini_path.get_file()
	var after := set_key(before, section, key, value)
	if after == before and before != "":
		return ""
	DirAccess.make_dir_recursive_absolute(ini_path.get_base_dir())
	var f := FileAccess.open(ini_path, FileAccess.WRITE)
	if f == null:
		return "Couldn't save %s (%s)." % [ini_path.get_file(), error_string(FileAccess.get_open_error())]
	f.store_string(after)
	f.close()
	return ""
