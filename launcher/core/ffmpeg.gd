# core/ffmpeg.gd — fetches FFmpeg from its maintainers' release feed instead of
# shipping it. Service "ffmpeg".
#
# Source: BtbN/FFmpeg-Builds, the builds FFmpeg's own download page links for
# Windows and Linux. The newest release-branch build (ffmpeg-n<ver>-latest-
# <os>-gpl-<ver>) is picked; master builds are the fallback. The binary lands in
# <launcher>/tools/ffmpeg(.exe) with its LICENSE and a version marker.
extends Node
class_name FfmpegFetch

signal progress(done: int, total: int)
signal finished(path: String)        # "" on failure
signal failed(message: String)

const API := "https://api.github.com/repos/BtbN/FFmpeg-Builds/releases/latest"
const VERSION_FILE := "ffmpeg.version"

var busy := false
var _dl: HTTPRequest
var _poll: Timer
var _asset := {}
var _path := ""


func _ready() -> void:
	_dl = HTTPRequest.new()
	_dl.use_threads = true
	_dl.timeout = 600
	_dl.max_redirects = 8
	_dl.request_completed.connect(_on_download)
	add_child(_dl)
	_poll = Timer.new()
	_poll.wait_time = 0.25
	_poll.timeout.connect(func() -> void:
		if busy:
			progress.emit(_dl.get_downloaded_bytes(), _dl.get_body_size()))
	add_child(_poll)


func tools_dir() -> String:
	return App.root_dir.path_join("tools")


func exe_path() -> String:
	return tools_dir().path_join("ffmpeg.exe" if OS.get_name() == "Windows" else "ffmpeg")


## The version marker written after a download ("n7.1-latest"), or "".
func installed_version() -> String:
	var p := tools_dir().path_join(VERSION_FILE)
	return FileAccess.get_file_as_string(p).strip_edges() if FileAccess.file_exists(p) else ""


static func _wanted(name: String) -> int:
	# Higher is better. Release-branch builds beat master; gpl beats lgpl (more codecs);
	# "shared" and non-matching platforms are refused.
	var os_tag := "win64" if OS.get_name() == "Windows" else "linux64"
	if not name.contains(os_tag) or name.contains("shared") or name.contains("lgpl"):
		return -1
	if OS.get_name() == "Windows" and not name.ends_with(".zip"):
		return -1
	if OS.get_name() != "Windows" and not name.ends_with(".tar.xz"):
		return -1
	if name.begins_with("ffmpeg-n") and name.contains("-latest-"):
		return 2
	if name.begins_with("ffmpeg-master-latest"):
		return 1
	return -1


## Looks up the newest build and downloads it unless the marker already matches.
func fetch(force := false) -> void:
	if busy:
		return
	busy = true
	var headers := PackedStringArray(["Accept: application/vnd.github+json", "User-Agent: SilentHills/" + App.VERSION])
	Net.get_json(API, headers, 0, func(json) -> void:
		if typeof(json) != TYPE_DICTIONARY:
			_fail("Couldn't reach FFmpeg's release feed.")
			return
		var best := {}
		var best_score := -1
		for a in json.get("assets", []):
			var score := _wanted(str(a.get("name", "")))
			if score > best_score:
				best_score = score
				best = a
		if best.is_empty():
			_fail("No FFmpeg build for this system in the latest release.")
			return
		_asset = best
		var marker := str(best.name).get_basename().replace(".tar", "")
		if not force and FileAccess.file_exists(exe_path()) and installed_version() == marker:
			busy = false
			finished.emit(exe_path())
			return
		var dir := OS.get_user_data_dir().path_join("update")
		DirAccess.make_dir_recursive_absolute(dir)
		_path = dir.path_join(str(best.name))
		if FileAccess.file_exists(_path):
			DirAccess.remove_absolute(_path)
		_dl.download_file = _path
		var err := _dl.request(str(best.browser_download_url), PackedStringArray(["User-Agent: SilentHills/" + App.VERSION]))
		if err != OK:
			_fail("Download could not start (%d)." % err)
			return
		_poll.start())


func _on_download(result: int, code: int, _h: PackedStringArray, _b: PackedByteArray) -> void:
	_poll.stop()
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_fail("FFmpeg download failed (HTTP %d)." % code)
		return
	App.run(_extract, func(ok) -> void:
		busy = false
		if bool(ok):
			App.set_setting("ffmpeg", "")   # use the tools copy from now on
			finished.emit(exe_path())
		else:
			failed.emit("Downloaded FFmpeg but couldn't unpack it."))


## Worker thread: unpack bin/ffmpeg(.exe) and LICENSE into tools/, write the marker.
func _extract() -> bool:
	DirAccess.make_dir_recursive_absolute(tools_dir())
	var exe_name := "ffmpeg.exe" if OS.get_name() == "Windows" else "ffmpeg"
	var got := false
	if _path.ends_with(".zip"):
		var z := ZIPReader.new()
		if z.open(_path) != OK:
			return false
		for f in z.get_files():
			var file := f.get_file()
			if f.contains("/bin/") and file == exe_name:
				got = _write(tools_dir().path_join(exe_name), z.read_file(f))
			elif file == "LICENSE.txt" or file == "LICENSE":
				_write(tools_dir().path_join("FFMPEG-LICENSE.txt"), z.read_file(f))
		z.close()
	else:
		var tmp := OS.get_user_data_dir().path_join("update").path_join("ffmpeg-unpack")
		DirAccess.make_dir_recursive_absolute(tmp)
		if OS.execute("tar", ["-xJf", _path, "-C", tmp]) != 0:
			return false
		var found := _find(tmp, exe_name)
		if found != "":
			got = DirAccess.copy_absolute(found, tools_dir().path_join(exe_name)) == OK
			OS.execute("chmod", ["+x", tools_dir().path_join(exe_name)])
			var lic := _find(tmp, "LICENSE.txt")
			if lic != "":
				DirAccess.copy_absolute(lic, tools_dir().path_join("FFMPEG-LICENSE.txt"))
		OS.execute("rm", ["-rf", tmp])
	DirAccess.remove_absolute(_path)
	if got:
		_write(tools_dir().path_join(VERSION_FILE), (str(_asset.name).get_basename().replace(".tar", "") + "\n").to_utf8_buffer())
	return got


static func _write(path: String, bytes: PackedByteArray) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_buffer(bytes)
	f.close()
	return true


static func _find(root: String, name: String) -> String:
	for f in DirAccess.get_files_at(root):
		if f == name:
			return root.path_join(f)
	for d in DirAccess.get_directories_at(root):
		var r := _find(root.path_join(d), name)
		if r != "":
			return r
	return ""


func _fail(msg: String) -> void:
	busy = false
	failed.emit(msg)
