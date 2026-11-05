extends RefCounted
## ReXGlue recomp runtime (DownpourRecomp) unlocks. The runtime keeps a TOML:
##   # Achievement unlock state - managed by ReXGlue runtime
##   [unlocked.0000001A]
##   filetime = 133745678901234567
## and logs "Achievement unlocked: 0000001A". Both are read from the game folder.

const HEADER := "Achievement unlocked state"
const EPOCH_DIFF_MS := 11644473600000

static var last_result := {}   # xid -> unix ms


static func read(game_path: String) -> Array:
	last_result = {}
	for f in _tomls(game_path, 4):
		var cur := -1
		for raw in FileAccess.get_file_as_string(f).split("\n"):
			var line := raw.strip_edges()
			if line.begins_with("[unlocked.") and line.ends_with("]"):
				cur = line.substr(10, line.length() - 11).hex_to_int()
				last_result[cur] = 0
			elif line.begins_with("filetime") and cur >= 0:
				var ft := line.split("=")[1].strip_edges().to_int()
				last_result[cur] = ft / 10000 - EPOCH_DIFF_MS
	var logs := game_path.path_join("logs")
	if DirAccess.dir_exists_absolute(logs):
		var re := RegEx.create_from_string("Achievement unlocked:\\s*(?:0x)?([0-9A-Fa-f]{1,8})")
		for f in DirAccess.get_files_at(logs):
			if not f.ends_with(".log"):
				continue
			var p := logs.path_join(f)
			if FileAccess.get_size(p) > 64 * 1024 * 1024:
				continue
			for m in re.search_all(FileAccess.get_file_as_string(p)):
				var x := m.get_string(1).hex_to_int()
				if not last_result.has(x) or last_result[x] == 0:
					last_result[x] = FileAccess.get_modified_time(p) * 1000
	return last_result.keys()


static func _tomls(dir: String, depth: int) -> Array:
	var out := []
	if depth < 0 or not DirAccess.dir_exists_absolute(dir):
		return out
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".toml"):
			var fa := FileAccess.open(dir.path_join(f), FileAccess.READ)
			if fa:
				var head := fa.get_buffer(200).get_string_from_utf8()
				fa.close()
				if head.contains("Achievement unlock state"):
					out.append(dir.path_join(f))
	for sub in DirAccess.get_directories_at(dir):
		if not (sub.to_lower() in ["assets", "cache", "_build", "_dumps", "shaders", "logs", "rom", "native", "shader_dump", "backups"]):
			out.append_array(_tomls(dir.path_join(sub), depth - 1))
	return out
