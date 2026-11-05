extends SceneTree
## Enhanced patch settings (Mods card): INI writes keep everything else, values are clamped and
## snapped, and the panel locks only what the game can't take live while it runs.
## Run: SILENTHILLS_ROOT=<tmp> godot --headless --path . -s tests/enhanced_settings.gd
const PS := preload("res://core/patch_settings.gd")
var fails := 0

func ok(cond: bool, what: String) -> void:
	print(("PASS " if cond else "FAIL ") + what)
	if not cond:
		fails += 1

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await process_frame
	# ---- set_key: one line changes, everything else kept
	var crlf := "; comment\r\n[Enhanced]\r\nLogLevel=2\r\n\r\n[Stamina]\r\nMax = 100.0000\r\n; note\r\nDodge=25\r\n\r\n[Other]\r\nX=1\r\n"
	var a := PS.set_key(crlf, "stamina", "max", "120")
	ok(a == crlf.replace("Max = 100.0000", "Max = 120"), "replace keeps key spelling, other lines, CRLF: " + a.c_escape())
	a = PS.set_key(crlf, "Stamina", "RegenDelay", "1.5")
	ok(a == crlf.replace("Dodge=25\r\n", "Dodge=25\r\nRegenDelay=1.5\r\n"), "missing key goes after the section's last entry: " + a.c_escape())
	a = PS.set_key(crlf, "Combat", "Guard", "0")
	ok(a == crlf + "[Combat]\r\nGuard=0\r\n", "missing section appended with CRLF: " + a.c_escape())
	var lf := "[A]\nk=1\n[B]\nj=2"
	a = PS.set_key(lf, "B", "n", "3")
	ok(a == "[A]\nk=1\n[B]\nj=2\nn=3\n", "LF file, no final newline, key added at end: " + a.c_escape())
	a = PS.set_key(lf, "A", "k", "5")
	ok(a == "[A]\nk=5\n[B]\nj=2", "LF replace keeps missing final newline: " + a.c_escape())
	a = PS.set_key("[A]\r\nk=1", "C", "z", "9")
	ok(a == "[A]\r\nk=1\r\n[C]\r\nz=9\r\n", "new section after a line without ending: " + a.c_escape())
	ok(PS.set_key("", "S", "k", "1") == "[S]\r\nk=1\r\n", "empty file gets CRLF")
	ok(PS.set_key(crlf, "Stamina", "Max", "100.0000") == crlf, "same value: text unchanged")
	a = PS.set_key("[S]\r\n;k=old\r\nk=1\r\n", "S", "k", "2")
	ok(a == "[S]\r\n;k=old\r\nk=2\r\n", "commented-out key left alone")

	# ---- parse / value_of
	var data := PS.parse(crlf)
	ok(PS.value_of(data, {"section": "Stamina", "key": "Max", "type": "float", "min": 50, "max": 200, "step": 5, "default": 100}) == 100.0, "reads spaced key")
	ok(PS.value_of(data, {"section": "Stamina", "key": "Gone", "type": "float", "default": 7.5}) == 7.5, "missing key -> default")
	ok(PS.value_of(PS.parse("[S]\nb=true\n"), {"section": "S", "key": "b", "type": "bool", "default": 0}) == 1.0, "bool true")

	# ---- normalize / format
	var f := {"type": "float", "min": 0.05, "max": 0.6, "step": 0.01}
	ok(PS.normalize(f, 0.333) == 0.33, "snap to step from min (0.333 -> 0.33)")
	ok(PS.normalize(f, 9) == 0.6 and PS.normalize(f, -1) == 0.05, "clamp to min/max")
	var g := {"type": "float", "min": 50, "max": 200, "step": 5}
	ok(PS.normalize(g, 63) == 65.0, "snap 63 -> 65")
	ok(PS.format(g, 65) == "65", "format integer float without decimals")
	ok(PS.format({"type": "float", "min": -1, "max": 1, "step": 0.0001}, 0.123456) == "0.1235", "format 4 decimals")
	ok(PS.format({"type": "float", "min": 0, "max": 1, "step": 0.05}, 0.25) == "0.25", "format trims zeros")
	ok(PS.format({"type": "int", "min": 0, "max": 10, "step": 2}, 5.2) == "6", "int snaps to step")
	ok(PS.format({"type": "choice", "options": ["a", "b", "c"]}, 7) == "2", "choice clamps to last option")
	ok(PS.format({"type": "bool"}, 0.2) == "0", "bool 0/1")

	# ---- write: re-reads the file first
	var dir := OS.get_environment("SILENTHILLS_ROOT").path_join("settings-test")
	DirAccess.make_dir_recursive_absolute(dir.path_join("Enhanced"))
	var ini := dir.path_join("Enhanced/HomecomingEnhanced.ini")
	var fa := FileAccess.open(ini, FileAccess.WRITE)
	fa.store_string("[Stamina]\r\nMax=100\r\n")
	fa.close()
	ok(PS.write(ini, "Stamina", "Dodge", "30") == "", "write")
	var game_text := FileAccess.get_file_as_string(ini) + "[Prompts]\r\nStyle=2\r\n"   # the game writes too
	fa = FileAccess.open(ini, FileAccess.WRITE)
	fa.store_string(game_text)
	fa.close()
	ok(PS.write(ini, "Stamina", "Max", "150") == "", "write again")
	ok(FileAccess.get_file_as_string(ini) == "[Stamina]\r\nMax=150\r\nDodge=30\r\n[Prompts]\r\nStyle=2\r\n", "game's own change kept: " + FileAccess.get_file_as_string(ini).c_escape())

	# ---- schema from the package, falling back to the game folder
	var pkgdir := dir.path_join("pkg")
	DirAccess.make_dir_recursive_absolute(pkgdir.path_join("files/Enhanced"))
	var schema := {"ini": "Enhanced/HomecomingEnhanced.ini", "live_reload": true, "groups": [{"title": "Stamina", "note": "", "items": [
		{"section": "Stamina", "key": "Max", "label": "Maximum", "type": "float", "min": 50, "max": 200, "step": 5, "default": 100, "live": true},
		{"section": "Combat", "key": "DevKeys", "label": "Developer keys", "type": "bool", "default": 0, "live": false}]}]}
	fa = FileAccess.open(dir.path_join("Enhanced/settings.json"), FileAccess.WRITE)
	fa.store_string(JSON.stringify(schema))
	fa.close()
	var pkg := {"_dir": pkgdir, "files": "files", "settings": "Enhanced/settings.json"}
	ok(PS.load_schema(pkg, dir).get("_path", "") == dir.path_join("Enhanced/settings.json"), "schema: game folder fallback")
	fa = FileAccess.open(pkgdir.path_join("files/Enhanced/settings.json"), FileAccess.WRITE)
	fa.store_string(JSON.stringify(schema))
	fa.close()
	ok(PS.load_schema(pkg, dir).get("_path", "") == pkgdir.path_join("files/Enhanced/settings.json"), "schema: package first")
	ok(PS.load_schema({"_dir": pkgdir}, dir).is_empty(), "no \"settings\" in the manifest: no panel")

	# ---- the panel
	var App = root.get_node("App")
	var View = load("res://ui/widgets/patch_settings_view.gd")   # after the autoloads exist
	var v: Control = View.new()
	v.set("game_id", "homecoming")
	v.set("schema", schema)
	v.set("game_path", dir)
	v.set("patch_on", true)
	root.add_child(v)
	await process_frame
	var rows: Array = v.get("_rows")
	ok(rows.size() == 2 and rows[0].value == 150.0, "panel reads current value (150)")
	v.call("_changed", 0, 173.0, true)
	ok(FileAccess.get_file_as_string(ini).contains("Max=150"), "slider change waits (debounce)")
	await create_timer(0.4).timeout
	ok(FileAccess.get_file_as_string(ini).contains("Max=175"), "saved after the pause, snapped to 175")
	v.call("_changed", 1, 1.0, false)
	ok(FileAccess.get_file_as_string(ini).ends_with("[Combat]\r\nDevKeys=1\r\n"), "bool saved at once, section added")
	# the game starts: live stays editable, the rest locks
	App.svc("runner").sessions["homecoming"] = {"start": 0, "last_seen": 0, "seen": true, "grace": 0, "roots": [], "names": []}
	v.call("_on_session", "homecoming")
	ok(rows[0].controls[0].editable and rows[1].controls[0].disabled, "running: live slider editable, non-live switch locked")
	ok(rows[1].lock_note.visible and not rows[0].lock_note.visible, "running: lock note only on the non-live item")
	v.call("_changed", 1, 0.0, false)
	ok(FileAccess.get_file_as_string(ini).contains("DevKeys=1"), "locked item not written")
	App.svc("runner").sessions.erase("homecoming")
	v.call("_on_session", "homecoming")
	ok(not rows[1].controls[0].disabled, "game closed: unlocked")
	# the game changes the file: the panel follows
	PS.write(ini, "Stamina", "Max", "90")
	await create_timer(1.8).timeout
	ok(rows[0].value == 90.0, "panel picks up the game's own change")
	v.queue_free()
	var off: Control = View.new()
	off.set("game_id", "homecoming")
	off.set("schema", schema)
	off.set("game_path", dir)
	off.set("patch_on", false)
	root.add_child(off)
	await process_frame
	var orows: Array = off.get("_rows")
	ok(orows[0].controls[0].editable == false and orows[1].controls[0].disabled, "patch off: read-only")
	off.queue_free()
	print("FAILS ", fails)
	quit(1 if fails > 0 else 0)
