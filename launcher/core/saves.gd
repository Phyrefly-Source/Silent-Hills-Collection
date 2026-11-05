extends RefCounted
## Save backups: each backup is one zip of every save folder the game uses,
## in data/save-backups/<game>/. Automatic backups (taken on Play) are trimmed
## to the newest KEEP_AUTO; named ones are kept until deleted.

const KEEP_AUTO := 15


func locations(id: String) -> Array:
	var g := App.game(id)
	var gs := App.state(id)
	var out := []
	var seen := {}
	for p in g.get("saves", []) + gs.get("extra_saves", []):
		var full := App.expand(str(p), gs.path, gs.get("dump", ""))
		if full == "" or seen.has(full) or (str(p).contains("{game}") and gs.path == ""):
			continue
		seen[full] = true
		out.append({"path": full, "exists": DirAccess.dir_exists_absolute(full), "files": _count(full)})
	return out


func _count(dir: String) -> int:
	if not DirAccess.dir_exists_absolute(dir):
		return 0
	var n := 0
	for f in _walk(dir, ""):
		n += 1
	return n


func _walk(root: String, rel: String) -> Array:
	var out := []
	var d := root.path_join(rel)
	for f in DirAccess.get_files_at(d):
		out.append(rel.path_join(f) if rel != "" else f)
	for sub in DirAccess.get_directories_at(d):
		out.append_array(_walk(root, rel.path_join(sub) if rel != "" else sub))
	return out


func _dir(id: String) -> String:
	return App.data_dir.path_join("save-backups").path_join(id)


func list(id: String) -> Array:
	var out := []
	var dir := _dir(id)
	if not DirAccess.dir_exists_absolute(dir):
		return out
	var meta: Dictionary = App.read_json(dir.path_join("index.json"), {})
	for f in DirAccess.get_files_at(dir):
		if f.get_extension() != "zip":
			continue
		var m: Dictionary = meta.get(f, {})
		out.append({"file": dir.path_join(f), "name": f, "label": m.get("label", ""), "kind": m.get("kind", "manual"),
			"at": int(m.get("at", FileAccess.get_modified_time(dir.path_join(f)))), "files": int(m.get("files", 0))})
	out.sort_custom(func(a, b): return a.at > b.at)
	return out


## Returns "" on success, or an error message.
func backup(id: String, label: String = "", kind: String = "manual") -> String:
	var locs := locations(id).filter(func(l): return l.exists and l.files > 0)
	if locs.is_empty():
		return "There are no saves to back up yet."
	var dir := _dir(id)
	DirAccess.make_dir_recursive_absolute(dir)
	var now := int(Time.get_unix_time_from_system())
	var stamp := Time.get_datetime_string_from_unix_time(now).replace(":", "-").replace("T", "_")
	var name := "%s_%s.zip" % [stamp, kind]
	var zip := ZIPPacker.new()
	if zip.open(dir.path_join(name)) != OK:
		return "Couldn't write the backup."
	var count := 0
	for i in locs.size():
		var root: String = locs[i].path
		for rel in _walk(root, ""):
			zip.start_file("%d/%s" % [i, rel])
			zip.write_file(FileAccess.get_file_as_bytes(root.path_join(rel)))
			zip.close_file()
			count += 1
	zip.start_file("locations.json")
	zip.write_file(JSON.stringify(locs.map(func(l): return l.path)).to_utf8_buffer())
	zip.close_file()
	zip.close()
	var meta: Dictionary = App.read_json(dir.path_join("index.json"), {})
	meta[name] = {"label": label, "kind": kind, "at": now, "files": count}
	App.write_json(dir.path_join("index.json"), meta)
	if kind == "auto":
		_trim(id)
	return ""


func _trim(id: String) -> void:
	var autos := list(id).filter(func(b): return b.kind == "auto")
	for i in range(KEEP_AUTO, autos.size()):
		delete(id, autos[i].name)


func delete(id: String, name: String) -> void:
	var dir := _dir(id)
	DirAccess.remove_absolute(dir.path_join(name))
	var meta: Dictionary = App.read_json(dir.path_join("index.json"), {})
	meta.erase(name)
	App.write_json(dir.path_join("index.json"), meta)


func rename(id: String, name: String, label: String) -> void:
	var dir := _dir(id)
	var meta: Dictionary = App.read_json(dir.path_join("index.json"), {})
	var m: Dictionary = meta.get(name, {})
	m.label = label
	if m.get("kind", "") == "auto":
		m.kind = "manual"   # named backups are never trimmed
	meta[name] = m
	App.write_json(dir.path_join("index.json"), meta)


## Restores a backup. The current saves are backed up first, so this can be undone.
func restore(id: String, name: String) -> String:
	var path := _dir(id).path_join(name)
	var zip := ZIPReader.new()
	if zip.open(path) != OK:
		return "Couldn't open the backup."
	var locs = JSON.parse_string(zip.read_file("locations.json").get_string_from_utf8())
	if not locs is Array:
		return "This backup has no folder list."
	backup(id, "Before restoring", "auto")
	for f in zip.get_files():
		if f == "locations.json" or f.ends_with("/"):
			continue
		var slash := f.find("/")
		var i := f.substr(0, slash).to_int()
		if i >= locs.size():
			continue
		var target: String = str(locs[i]).path_join(f.substr(slash + 1))
		DirAccess.make_dir_recursive_absolute(target.get_base_dir())
		var out := FileAccess.open(target, FileAccess.WRITE)
		if out:
			out.store_buffer(zip.read_file(f))
			out.close()
	zip.close()
	return ""
