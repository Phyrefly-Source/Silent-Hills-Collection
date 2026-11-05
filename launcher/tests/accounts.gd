extends SceneTree
## Local profiles: hashed passwords, sign in/out, favourites (max 3), play
## time per profile, the first profile adopting the shared records, and each
## profile's own achievements. Run with SILENTHILLS_ROOT set (it wipes the
## accounts of that root).
func _initialize() -> void:
	_run.call_deferred()


func _wait(box: Array) -> void:
	while box.is_empty():
		await process_frame


func _run() -> void:
	await process_frame
	var App = root.get_node("App")
	var acc = App.svc("accounts")
	var ach = App.svc("achievements")
	DirAccess.remove_absolute(acc._path())
	acc._data = {"users": {}, "remember": ""}
	acc.current = ""
	App.state("sh3").playtime = 3600
	ach.set_unlocked("sh3", "flame-on", true)   # a shared (guest) unlock
	print("check_new: ", [acc.check_new("ab", "secret1", "secret1"), acc.check_new("Heather", "123", "123"), acc.check_new("Heather", "secret1", "secret2"), acc.check_new("Heather", "secret1", "secret1")])
	var r := []
	var t := Time.get_ticks_msec()
	acc.create("Heather", "secret1", true, func(e): r.append(e))
	await _wait(r)
	print("create: '", r[0], "' in ", Time.get_ticks_msec() - t, " ms; signed in ", acc.signed_in(), " as ", acc.display_name())
	var stored := FileAccess.get_file_as_string(acc._path())
	print("password in file: ", stored.contains("secret1"), "; hash length ", str(acc.user().hash).length())
	print("adopted playtime sh3: ", acc.playtime("sh3"), "; adopted unlock: ", ach._gp("sh3").unlocked.has("flame-on"))
	print("favourites: ", [acc.toggle_favourite("sh2"), acc.toggle_favourite("sh3"), acc.toggle_favourite("sh-f"), acc.toggle_favourite("pt")], " -> ", acc.favourites())
	App.svc("runner").session_ended.emit("sh2", 120)
	print("sh2 playtime after a session: ", acc.playtime("sh2"))
	acc.sign_out()
	print("guest sh3 unlock still: ", ach._gp("sh3").unlocked.has("flame-on"))
	r.clear()
	acc.create("James", "mary1234", false, func(e): r.append(e))
	await _wait(r)
	print("second profile: ", acc.display_name(), " playtime sh3 ", acc.playtime("sh3"), " unlock ", ach._gp("sh3").unlocked.has("flame-on"), " favourites ", acc.favourites())
	acc.sign_out()
	r.clear()
	acc.sign_in("heather", "wrong", true, func(e): r.append(e))
	await _wait(r)
	print("wrong password: ", r[0], " signed in ", acc.signed_in())
	r.clear()
	acc.sign_in("HEATHER", "secret1", true, func(e): r.append(e))
	await _wait(r)
	print("right password: '", r[0], "' as ", acc.display_name(), " unlock ", ach._gp("sh3").unlocked.has("flame-on"))
	r.clear()
	acc.change_password("secret1", "newpass1", "newpass1", func(e): r.append(e))
	await _wait(r)
	acc.sign_out()
	r.clear()
	acc.sign_in("Heather", "newpass1", true, func(e): r.append(e))
	await _wait(r)
	print("after change: '", r[0], "' signed in ", acc.signed_in())
	print("profiles: ", acc.profiles().map(func(p): return p.name), " remember ", acc._data.remember)
	quit()
