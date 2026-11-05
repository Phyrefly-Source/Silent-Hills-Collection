# core/updater.gd — update check + install against this repo's GitHub releases.
# Service "updater" (App.svc("updater")).
#
# Flow: check() -> `checked` -> download() -> `progress`/`ready_to_apply` -> apply()
# Assets are verified against SHA256SUMS.txt before anything is touched.
extends Node
class_name Updater

signal checked(available: bool)          # latest{} is filled when true
signal progress(done: int, total: int)
signal ready_to_apply
signal failed(message: String)

const RELEASES_REPO := "Phyrefly-Source/Silent-Hills-Collection"
const API_LATEST := "https://api.github.com/repos/%s/releases/latest"
const CHECK_EVERY_SEC := 6 * 3600
const STATE_FILE := "user://updater.json"

enum Flavor { WINDOWS_PORTABLE, WINDOWS_INSTALLED, LINUX_APPIMAGE, UNKNOWN }

var current_version: String = str(ProjectSettings.get_setting("application/config/version", "0.0.0"))
var latest: Dictionary = {}     # version, notes, asset_name, asset_url, sums_url, html_url
var state: Dictionary = {"last_check": 0, "skipped": ""}

var _api: HTTPRequest
var _sums: HTTPRequest
var _dl: HTTPRequest
var _dl_path := ""
var _sums_text := ""
var _poll: Timer


func _ready() -> void:
	_load_state()
	_api = _make_http(_on_latest)
	_sums = _make_http(_on_sums)
	_dl = _make_http(_on_download)
	_dl.use_threads = true
	_poll = Timer.new()
	_poll.wait_time = 0.25
	_poll.timeout.connect(func() -> void:
		if _dl.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
			progress.emit(_dl.get_downloaded_bytes(), _dl.get_body_size()))
	add_child(_poll)


func _make_http(cb: Callable) -> HTTPRequest:
	var h := HTTPRequest.new()
	h.timeout = 60
	h.max_redirects = 8
	h.request_completed.connect(cb)
	add_child(h)
	return h


# ---------------------------------------------------------------- flavor

static func flavor() -> Flavor:
	var exe_dir := OS.get_executable_path().get_base_dir()
	match OS.get_name():
		"Windows":
			if FileAccess.file_exists(exe_dir.path_join("unins000.exe")):
				return Flavor.WINDOWS_INSTALLED
			return Flavor.WINDOWS_PORTABLE
		"Linux":
			if OS.get_environment("APPIMAGE") != "":
				return Flavor.LINUX_APPIMAGE
	return Flavor.UNKNOWN


static func _asset_suffix(f: Flavor) -> String:
	match f:
		Flavor.WINDOWS_PORTABLE: return "-windows-portable.zip"
		Flavor.WINDOWS_INSTALLED: return "-windows-setup.exe"
		Flavor.LINUX_APPIMAGE: return "-linux-x86_64.AppImage"
	return ""


# ---------------------------------------------------------------- check

## Checks at most every CHECK_EVERY_SEC unless force is true.
func check(force := false) -> void:
	var now := int(Time.get_unix_time_from_system())
	if not force and now - int(state.last_check) < CHECK_EVERY_SEC:
		checked.emit(false)
		return
	if flavor() == Flavor.UNKNOWN:
		checked.emit(false)
		return
	var err := _api.request(API_LATEST % RELEASES_REPO, _headers())
	if err != OK:
		failed.emit("Update check could not start (%d)." % err)


func _headers() -> PackedStringArray:
	return PackedStringArray([
		"Accept: application/vnd.github+json",
		"User-Agent: SilentHills/" + current_version,
	])


func _on_latest(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		failed.emit("Update check failed (HTTP %d)." % code)
		return
	var json: Variant = JSON.parse_string(body.get_string_from_utf8())
	if typeof(json) != TYPE_DICTIONARY or not json.has("tag_name"):
		failed.emit("Update check returned something unexpected.")
		return
	state.last_check = int(Time.get_unix_time_from_system())
	_save_state()

	var tag: String = str(json.get("tag_name", "")).trim_prefix("v")
	if not _is_newer(tag, current_version) or tag == str(state.skipped):
		checked.emit(false)
		return
	var suffix := _asset_suffix(flavor())
	var asset := {}
	var sums := {}
	for a in json.get("assets", []):
		var n: String = str(a.get("name", ""))
		if n.ends_with(suffix):
			asset = a
		elif n == "SHA256SUMS.txt":
			sums = a
	if asset.is_empty() or sums.is_empty():
		checked.emit(false)   # release exists but not for this flavor; stay quiet
		return
	latest = {
		"version": tag,
		"notes": str(json.get("body", "")),
		"html_url": str(json.get("html_url", "")),
		"asset_name": str(asset.name),
		"asset_url": str(asset.browser_download_url),
		"sums_url": str(sums.browser_download_url),
	}
	checked.emit(true)


static func _is_newer(a: String, b: String) -> bool:
	var pa := a.split(".")
	var pb := b.split(".")
	for i in range(maxi(pa.size(), pb.size())):
		var x := int(pa[i]) if i < pa.size() else 0
		var y := int(pb[i]) if i < pb.size() else 0
		if x != y:
			return x > y
	return false


func skip_latest() -> void:
	if not latest.is_empty():
		state.skipped = latest.version
		_save_state()


# ---------------------------------------------------------------- download

func download() -> void:
	if latest.is_empty():
		failed.emit("Nothing to download.")
		return
	var err := _sums.request(latest.sums_url, _headers())
	if err != OK:
		failed.emit("Could not fetch checksums (%d)." % err)


func _on_sums(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		failed.emit("Could not fetch checksums (HTTP %d)." % code)
		return
	_sums_text = body.get_string_from_utf8()
	var dir := OS.get_user_data_dir().path_join("update")
	DirAccess.make_dir_recursive_absolute(dir)
	_dl_path = dir.path_join(latest.asset_name)
	if FileAccess.file_exists(_dl_path):
		DirAccess.remove_absolute(_dl_path)
	_dl.download_file = _dl_path
	var err := _dl.request(latest.asset_url, _headers())
	if err != OK:
		failed.emit("Download could not start (%d)." % err)
		return
	_poll.start()


func _on_download(result: int, code: int, _h: PackedStringArray, _body: PackedByteArray) -> void:
	_poll.stop()
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		failed.emit("Download failed (HTTP %d)." % code)
		return
	var expected := ""
	for line in _sums_text.split("\n"):
		var parts := line.strip_edges().split(" ", false)
		if parts.size() >= 2 and parts[-1].trim_prefix("*") == latest.asset_name:
			expected = parts[0].to_lower()
	var actual := FileAccess.get_sha256(_dl_path)
	if expected == "" or actual != expected:
		DirAccess.remove_absolute(_dl_path)
		failed.emit("Downloaded file failed its checksum; nothing was changed.")
		return
	ready_to_apply.emit()


# ---------------------------------------------------------------- apply

## Hands over to the platform's swap mechanism and quits. Call only after ready_to_apply.
func apply() -> void:
	match flavor():
		Flavor.WINDOWS_INSTALLED:
			_apply_installer()
		Flavor.WINDOWS_PORTABLE:
			_apply_portable_zip()
		Flavor.LINUX_APPIMAGE:
			_apply_appimage()
		_:
			failed.emit("This build can't update itself. Download it from %s" % latest.html_url)


func _apply_installer() -> void:
	# Inno Setup: silent in-place upgrade; its [Run] section relaunches us.
	var pid := OS.create_process(_dl_path, ["/VERYSILENT", "/NORESTART", "/CLOSEAPPLICATIONS", "/SP-"])
	if pid <= 0:
		OS.shell_open(_dl_path)
	get_tree().quit()


func _apply_portable_zip() -> void:
	var exe := OS.get_executable_path()
	var exe_dir := exe.get_base_dir()
	var staging := OS.get_user_data_dir().path_join("update").path_join("staging")
	DirAccess.make_dir_recursive_absolute(staging)
	var z := ZIPReader.new()
	if z.open(_dl_path) != OK:
		failed.emit("Could not open the update archive.")
		return
	for f in z.get_files():
		if f.ends_with("/"):
			continue
		var rel := f.substr(f.find("/") + 1)   # strip the "Silent Hills/" top folder
		if rel == "":
			continue
		var dest := staging.path_join(rel)
		DirAccess.make_dir_recursive_absolute(dest.get_base_dir())
		var out := FileAccess.open(dest, FileAccess.WRITE)
		out.store_buffer(z.read_file(f))
		out.close()
	z.close()

	var script := OS.get_user_data_dir().path_join("update").path_join("apply.cmd")
	var pid := OS.get_process_id()
	var lines := [
		"@echo off",
		":wait",
		'tasklist /FI "PID eq %d" 2>nul | find "%d" >nul && (timeout /t 1 /nobreak >nul & goto wait)' % [pid, pid],
		'xcopy /E /Y /I /Q "%s" "%s" >nul' % [staging.replace("/", "\\"), exe_dir.replace("/", "\\")],
		'rmdir /S /Q "%s"' % staging.replace("/", "\\"),
		'start "" "%s" --updated' % exe.replace("/", "\\"),
		'del "%~f0"',
	]
	var f := FileAccess.open(script, FileAccess.WRITE)
	f.store_string("\r\n".join(lines) + "\r\n")
	f.close()
	OS.create_process("cmd.exe", ["/C", script.replace("/", "\\")])
	get_tree().quit()


func _apply_appimage() -> void:
	var target := OS.get_environment("APPIMAGE")
	OS.execute("chmod", ["+x", _dl_path])
	# Renaming over a running AppImage is fine on Linux: the old inode lives until we exit.
	if OS.execute("mv", ["-f", _dl_path, target]) != 0:
		failed.emit("Could not replace %s (is it on a read-only location?)." % target)
		return
	OS.create_process(target, ["--updated"])
	get_tree().quit()


# ---------------------------------------------------------------- state

func _load_state() -> void:
	if FileAccess.file_exists(STATE_FILE):
		var j: Variant = JSON.parse_string(FileAccess.get_file_as_string(STATE_FILE))
		if typeof(j) == TYPE_DICTIONARY:
			state.merge(j, true)


func _save_state() -> void:
	var f := FileAccess.open(STATE_FILE, FileAccess.WRITE)
	f.store_string(JSON.stringify(state))
	f.close()
