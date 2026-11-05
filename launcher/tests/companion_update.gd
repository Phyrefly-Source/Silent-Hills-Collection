extends SceneTree
## The phone downloading an update from the PC over loopback: the launcher's
## companion folder carries a newer app; check_update offers it and
## download_update fetches it intact. Run with SILENTHILLS_ROOT set (its
## companion/ folder holds the APK and a version.json with a higher code).
func _initialize() -> void:
	_run.call_deferred()


func _wait(flag: Array) -> void:
	var t := Time.get_ticks_msec()
	while not flag[0] and Time.get_ticks_msec() - t < 60000:
		await process_frame


func _run() -> void:
	await process_frame
	var App = root.get_node("App")
	App.set_setting("companion_enabled", true)
	var server = App.svc("companion")
	var pc = App.svc("pc")
	print("PC carries: ", server.app_info())
	var shown := [""]
	server.pair_code.connect(func(code, _d): shown[0] = code)
	var st := [false]
	pc.pair_start("127.0.0.1", 47630, func(ok, _m): st[0] = true)
	await _wait(st)
	var fin := [false]
	pc.pair_finish("127.0.0.1", 47630, "x", shown[0], func(ok, m): print("paired ", ok, m); fin[0] = true)
	await _wait(fin)
	var u := [false, {}]
	pc.check_update(func(info): u[1] = info; u[0] = true)
	await _wait(u)
	print("offered: ", u[1])
	var last := [0]
	pc.update_progress.connect(func(d, t): last[0] = d)
	var t0 := Time.get_ticks_msec()
	var d := [false, false]
	pc.download_update(str(u[1].get("sha256", "")), func(ok, m): d[1] = ok; d[0] = true; print("download ", ok, " ", m))
	await _wait(d)
	var got := FileAccess.get_sha256(pc.update_path())
	print("took %d ms, sha matches: %s, size %d" % [Time.get_ticks_msec() - t0, got == str(u[1].get("sha256", "x")), FileAccess.open(pc.update_path(), FileAccess.READ).get_length()])
	var a := [false, null]
	pc.get_json("/api/achievements", func(x): a[1] = x; a[0] = true)
	await _wait(a)
	for dv in server.devices():
		print("PC sees phone app: ", dv.get("app_version", ""), " code ", dv.get("app_code", 0))
	App.flush()
	quit()
