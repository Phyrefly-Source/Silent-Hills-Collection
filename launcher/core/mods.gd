extends RefCounted
## Mods with full rollback.
##
## A mod is a folder in <launcher>/mods/<game>/<mod>/. Its files mirror the game
## folder; if it has a files/ subfolder only that is installed. mod.json may set
## name, version, author, description and installTo (a subfolder of the game).
##
## Every game file a mod overwrites is copied to data/mod-backups first.
## Ownership is a stack per file, so mods can be turned off in any order and the
## game always goes back to what was there before. Enhanced patches are
## installed through the same mechanism (as the hidden mod "_enhanced").

const SKIP := ["mod.json", "readme.txt", "readme.md", "preview.png", "preview.jpg", "preview.webp"]


func _state_path() -> String:
	return App.data_dir.path_join("mods-state.json")


func _load() -> Dictionary:
	return App.read_json(_state_path(), {})


func _game_state(s: Dictionary, id: String) -> Dictionary:
	if not s.has(id):
		s[id] = {"files": {}, "enabled": {}}
	return s[id]


func mods_dir(id: String) -> String:
	var d := App.root_dir.path_join("mods").path_join(id)
	DirAccess.make_dir_recursive_absolute(d)
	return d


func list(id: String) -> Array:
	var st := _game_state(_load(), id)
	var out := []
	var root := mods_dir(id)
	for name in DirAccess.get_directories_at(root):
		var dir := root.path_join(name)
		var meta: Dictionary = App.read_json(dir.path_join("mod.json"), {})
		var files := _payload(dir)
		out.append({"id": name, "dir": dir, "name": meta.get("name", name), "version": meta.get("version", ""),
			"author": meta.get("author", ""), "description": meta.get("description", ""),
			"files": files.size(), "enabled": st.enabled.has(name)})
	out.sort_custom(func(a, b): return a.name.naturalnocasecmp_to(b.name) < 0)
	return out


func is_enabled(id: String, mod_id: String) -> bool:
	return _game_state(_load(), id).enabled.has(mod_id)


func enabled_count(id: String) -> int:
	return _game_state(_load(), id).enabled.keys().filter(func(k): return not str(k).begins_with("_")).size()


func _payload_root(dir: String) -> String:
	return dir.path_join("files") if DirAccess.dir_exists_absolute(dir.path_join("files")) else dir


func _payload(dir: String) -> Array:
	var root := _payload_root(dir)
	var out := []
	for rel in _walk(root, ""):
		if root == dir and not rel.contains("/") and SKIP.has(rel.to_lower()):
			continue
		out.append(rel)
	return out


func _walk(root: String, rel: String) -> Array:
	var out := []
	var d := root.path_join(rel) if rel != "" else root
	for f in DirAccess.get_files_at(d):
		out.append(rel.path_join(f) if rel != "" else f)
	for sub in DirAccess.get_directories_at(d):
		out.append_array(_walk(root, rel.path_join(sub) if rel != "" else sub))
	return out


## Installs a folder's files into the game folder under a mod id. "" = success.
func install_folder(id: String, mod_id: String, src: String, game_path: String, _label: String = "") -> String:
	if game_path == "" or not DirAccess.dir_exists_absolute(game_path):
		return "Connect the game's folder first."
	var s := _load()
	var st := _game_state(s, id)
	if st.enabled.has(mod_id):
		return ""
	var install_to := str(App.read_json(src.path_join("mod.json"), {}).get("installTo", ""))
	var root := _payload_root(src)
	var done := []
	var backups := App.data_dir.path_join("mod-backups").path_join(id)
	DirAccess.make_dir_recursive_absolute(backups)
	for rel in _payload(src):
		var key: String = install_to.path_join(rel) if install_to != "" else rel
		var target := game_path.path_join(key).simplify_path()
		if not target.begins_with(game_path.simplify_path()):
			continue   # never write outside the game folder
		var backup := ""
		if FileAccess.file_exists(target):
			backup = backups.path_join("%s_%s" % [str(Time.get_ticks_usec()), target.get_file()])
			DirAccess.copy_absolute(target, backup)
		DirAccess.make_dir_recursive_absolute(target.get_base_dir())
		if DirAccess.copy_absolute(root.path_join(rel), target) != OK:
			for k in done:
				_undo_top(st, k, game_path)
			App.write_json(_state_path(), s)
			return "Couldn't write %s. Is the game running?" % key
		var stack: Array = st.files.get(key, [])
		stack.append({"mod": mod_id, "backup": backup})
		st.files[key] = stack
		done.append(key)
	st.enabled[mod_id] = {"at": int(Time.get_unix_time_from_system()), "files": done}
	App.write_json(_state_path(), s)
	return ""


func enable(id: String, mod_id: String) -> String:
	return install_folder(id, mod_id, mods_dir(id).path_join(mod_id), App.state(id).path)


func disable(id: String, mod_id: String) -> String:
	var s := _load()
	var st := _game_state(s, id)
	if not st.enabled.has(mod_id):
		return ""
	var game_path: String = App.state(id).path
	for key in st.enabled[mod_id].get("files", []):
		var stack: Array = st.files.get(key, [])
		var idx := -1
		for i in stack.size():
			if stack[i].mod == mod_id:
				idx = i
		if idx < 0:
			continue
		if idx == stack.size() - 1:
			_undo_top(st, key, game_path)
		else:
			# A later mod still owns the file: hand our backup down to it.
			stack[idx + 1].backup = stack[idx].backup
			stack.remove_at(idx)
	st.enabled.erase(mod_id)
	App.write_json(_state_path(), s)
	return ""


func _undo_top(st: Dictionary, key: String, game_path: String) -> void:
	var stack: Array = st.files.get(key, [])
	if stack.is_empty():
		return
	var top: Dictionary = stack.pop_back()
	var target := game_path.path_join(key)
	if top.backup != "" and FileAccess.file_exists(top.backup):
		DirAccess.copy_absolute(top.backup, target)
		DirAccess.remove_absolute(top.backup)
	else:
		DirAccess.remove_absolute(target)
		# Folders the mod created go too, so nothing of it is left behind.
		var dir := target.get_base_dir()
		var stop := game_path.simplify_path()
		while dir.length() > stop.length() and dir.begins_with(stop) \
				and DirAccess.get_files_at(dir).is_empty() and DirAccess.get_directories_at(dir).is_empty():
			DirAccess.remove_absolute(dir)
			dir = dir.get_base_dir()
	if stack.is_empty():
		st.files.erase(key)


## Adds a mod from a .zip or a folder. Returns the new mod id, or "" on failure.
func import_mod(id: String, src: String) -> String:
	var name := src.get_file().get_basename() if src.get_extension().to_lower() == "zip" else src.get_file()
	var dest := mods_dir(id).path_join(name.validate_filename())
	var n := 2
	while DirAccess.dir_exists_absolute(dest):
		dest = mods_dir(id).path_join("%s (%d)" % [name.validate_filename(), n])
		n += 1
	DirAccess.make_dir_recursive_absolute(dest)
	if src.get_extension().to_lower() == "zip":
		var z := ZIPReader.new()
		if z.open(src) != OK:
			return ""
		var files := z.get_files()
		# A zip with a single top folder: install from inside it.
		var prefix := ""
		var tops := {}
		for f in files:
			tops[f.split("/")[0]] = true
		if tops.size() == 1 and files.size() > 1 and Array(files).any(func(f): return f.contains("/")):
			prefix = tops.keys()[0] + "/"
		for f in files:
			if f.ends_with("/") or not f.begins_with(prefix):
				continue
			var out := dest.path_join(f.substr(prefix.length()))
			DirAccess.make_dir_recursive_absolute(out.get_base_dir())
			var fa := FileAccess.open(out, FileAccess.WRITE)
			if fa:
				fa.store_buffer(z.read_file(f))
				fa.close()
		z.close()
	else:
		for rel in _walk(src, ""):
			DirAccess.make_dir_recursive_absolute(dest.path_join(rel).get_base_dir())
			DirAccess.copy_absolute(src.path_join(rel), dest.path_join(rel))
	return dest.get_file()


func remove(id: String, mod_id: String) -> void:
	disable(id, mod_id)
	OS.move_to_trash(mods_dir(id).path_join(mod_id))
