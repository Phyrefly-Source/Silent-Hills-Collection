extends SceneTree
## End-to-end over loopback: the desktop's companion server and the phone's
## client in one process — discover, pair with the shown code, read the
## achievements, a game background, and check a wrong token is refused.
## Run with SILENTHILLS_ROOT set.
func _initialize() -> void:
	_run.call_deferred()


func _wait(flag: Array) -> void:
	var t := Time.get_ticks_msec()
	while not flag[0] and Time.get_ticks_msec() - t < 30000:
		await process_frame


func _run() -> void:
	await process_frame
	var App = root.get_node("App")
	App.set_setting("companion_devices", [])
	App.set_setting("companion_pc", {})
	var server = App.svc("companion")
	var pc = App.svc("pc")
	App.set_setting("companion_enabled", true)
	print("listening: ", server.running(), " on ", server.addresses())
	var shown := [""]
	server.pair_code.connect(func(code, device): shown[0] = code; print("PC shows code for ", device))

	var found := [false, []]
	pc.discover(func(list): found[1] = list; found[0] = true, 1.5, ["127.0.0.1"])
	await _wait(found)
	print("discovered: ", found[1])

	var st := [false]
	pc.pair_start("127.0.0.1", 47630, func(ok, msg): print("pair_start ", ok, " ", msg); st[0] = true)
	await _wait(st)
	var bad := [false]
	pc.pair_finish("127.0.0.1", 47630, "x", "000000" if shown[0] != "000000" else "111111", func(ok, msg): print("wrong code -> ", ok, " ", msg); bad[0] = true)
	await _wait(bad)
	var fin := [false]
	pc.pair_finish("127.0.0.1", 47630, "x", shown[0], func(ok, msg): print("pair_finish ", ok, " ", msg); fin[0] = true)
	await _wait(fin)
	print("paired: ", pc.paired(), " devices on PC: ", server.devices().size())

	var a := [false, null]
	pc.get_json("/api/achievements", func(d): a[1] = d; a[0] = true)
	await _wait(a)
	if a[1] is Dictionary:
		for g in a[1].games:
			print("  ", g.title, " ", g.unlocked, "/", g.total, " groups=", g.groups.size())
	else:
		print("achievements: ", a[1])
	for i in 10:
		await process_frame
	print("online: ", pc.online)

	var c := [false, null]
	pc.call_pc("127.0.0.1", 47630, HTTPClient.METHOD_GET, "/api/catalogue", null, func(code, d): c[1] = [code, d]; c[0] = true, "not-the-token")
	await _wait(c)
	print("wrong token -> ", c[1][0])

	var h := [false, ""]
	pc.get_picture("/api/art/sh2/hero", func(p): h[1] = p; h[0] = true)
	await _wait(h)
	print("hero art: ", h[1], " ", FileAccess.get_file_as_bytes(h[1]).size() if h[1] != "" else 0, " bytes")
	App.flush()
	quit()
